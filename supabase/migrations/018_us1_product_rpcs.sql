-- 018_us1_product_rpcs.sql
-- User Story 1: atomic product + subtype creation, status transitions with R-008, and
-- catalog-manager authorization. Category DELETE completes the taxonomy CRUD surface.
-- Source of truth: specs/002-catalog-pricing/data-model.md,
-- specs/002-catalog-pricing/contracts/api-contracts.md (create_product, set_product_status).
--
-- ERROR CONTRACT: RPCs raise the API contract's error code as the exception message
-- (SQLSTATE P0001 / insufficient_privilege). The frontend maps `error.message` back to an
-- application error code. Messages are therefore part of the API contract and must not be
-- reworded.
--
-- CLAIM NAMING: the application role travels in `app_role`, never in the reserved `role`
-- claim. See docs/adr/0002-jwt-app-role-claim.md.
--
-- These routines are SECURITY DEFINER and owned by the migration role, which bypasses RLS.
-- Tenant and role checks below are therefore the authorization boundary, not a convenience.

-- ---------------------------------------------------------------------------
-- Category DELETE (operator/admin, same tenant) — taxonomy CRUD for T017
-- ---------------------------------------------------------------------------

CREATE POLICY operator_delete ON public.categories
  FOR DELETE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

-- ---------------------------------------------------------------------------
-- Shared: the caller must be an active operator or admin of the tenant in the token
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.require_catalog_manager()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_claim_org uuid := nullif(auth.jwt() ->> 'organization_id', '')::uuid;
  v_claim_role text := auth.jwt() ->> 'app_role';
  v_organization_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_claim_role IS NULL OR v_claim_role NOT IN ('operator', 'admin') OR v_claim_org IS NULL THEN
    RAISE EXCEPTION 'INSUFFICIENT_PERMISSIONS' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT p.organization_id
  INTO v_organization_id
  FROM public.user_profiles p
  WHERE p.id = v_user_id
    AND p.status = 'active'
    AND p.role IN ('operator', 'admin')
    AND p.organization_id = v_claim_org;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'INSUFFICIENT_PERMISSIONS' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN v_organization_id;
END;
$$;

COMMENT ON FUNCTION public.require_catalog_manager() IS
  'Returns the caller''s tenant id, or raises, when JWT and live profile both say operator or admin.';

REVOKE ALL ON FUNCTION public.require_catalog_manager() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.require_catalog_manager() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Audit product activation / deactivation (FR-001 logical status)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.audit_product_status_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'active'::public.product_status THEN
    PERFORM audit.log_event(
      NEW.organization_id,
      'product_activated'::audit.audit_event_type,
      'success'::audit.audit_result,
      auth.uid(),
      'product',
      NEW.id,
      jsonb_build_object('from', OLD.status, 'to', NEW.status)
    );
  ELSIF NEW.status = 'inactive'::public.product_status THEN
    PERFORM audit.log_event(
      NEW.organization_id,
      'product_deactivated'::audit.audit_event_type,
      'success'::audit.audit_result,
      auth.uid(),
      'product',
      NEW.id,
      jsonb_build_object('from', OLD.status, 'to', NEW.status)
    );
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.audit_product_status_changed() IS
  'Writes product_activated / product_deactivated when products.status changes.';

CREATE TRIGGER products_audit_status_changed
  AFTER UPDATE OF status ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_product_status_changed();

-- ---------------------------------------------------------------------------
-- create_product
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_product(
  p_type text,
  p_name text,
  p_description text DEFAULT NULL,
  p_provider_id uuid DEFAULT NULL,
  p_category_ids uuid[] DEFAULT '{}'::uuid[],
  p_experience jsonb DEFAULT NULL,
  p_accommodation jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_name text;
  v_description text;
  v_type public.product_type;
  v_product_id uuid;
  v_category_id uuid;
  v_duration integer;
  v_min_capacity integer;
  v_max_capacity integer;
  v_difficulty text;
  v_property_type text;
  v_location text;
  v_max_occupancy integer;
  v_check_in time;
  v_check_out time;
BEGIN
  v_organization_id := public.require_catalog_manager();

  v_name := btrim(p_name);
  IF v_name IS NULL OR v_name = '' OR char_length(v_name) > 255 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_description := nullif(btrim(coalesce(p_description, '')), '');

  IF p_type IS NULL OR p_type NOT IN ('experience', 'accommodation') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_type := p_type::public.product_type;

  IF p_provider_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.providers pr
    WHERE pr.id = p_provider_id
      AND pr.organization_id = v_organization_id
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_type = 'experience' THEN
    IF p_experience IS NULL OR jsonb_typeof(p_experience) <> 'object' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    BEGIN
      v_duration := (p_experience ->> 'duration_minutes')::integer;
      v_min_capacity := (p_experience ->> 'min_capacity')::integer;
      v_max_capacity := (p_experience ->> 'max_capacity')::integer;
    EXCEPTION
      WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;

    IF v_duration IS NULL OR v_duration <= 0
       OR v_min_capacity IS NULL OR v_min_capacity < 1
       OR v_max_capacity IS NULL OR v_max_capacity < v_min_capacity
    THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    v_difficulty := nullif(btrim(coalesce(p_experience ->> 'difficulty', '')), '');
    IF v_difficulty IS NOT NULL AND v_difficulty NOT IN ('easy', 'moderate', 'hard') THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
  ELSIF p_type = 'accommodation' THEN
    IF p_accommodation IS NULL OR jsonb_typeof(p_accommodation) <> 'object' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    v_property_type := btrim(coalesce(p_accommodation ->> 'property_type', ''));
    v_location := btrim(coalesce(p_accommodation ->> 'location', ''));
    IF v_property_type = '' OR v_location = '' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    BEGIN
      v_max_occupancy := (p_accommodation ->> 'max_occupancy')::integer;
      v_check_in := nullif(btrim(coalesce(p_accommodation ->> 'check_in', '')), '')::time;
      v_check_out := nullif(btrim(coalesce(p_accommodation ->> 'check_out', '')), '')::time;
    EXCEPTION
      WHEN invalid_text_representation OR numeric_value_out_of_range OR datetime_field_overflow THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;

    IF v_max_occupancy IS NULL OR v_max_occupancy < 1 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  INSERT INTO public.products (
    organization_id, provider_id, type, name, description, status
  )
  VALUES (
    v_organization_id, p_provider_id, v_type, v_name, v_description, 'draft'
  )
  RETURNING id INTO v_product_id;

  IF p_type = 'experience' THEN
    INSERT INTO public.experiences (
      id, organization_id, duration_minutes, difficulty, meeting_point, min_capacity, max_capacity
    )
    VALUES (
      v_product_id,
      v_organization_id,
      v_duration,
      CASE WHEN v_difficulty IS NULL THEN NULL ELSE v_difficulty::public.experience_difficulty END,
      nullif(btrim(coalesce(p_experience ->> 'meeting_point', '')), ''),
      v_min_capacity,
      v_max_capacity
    );
  ELSE
    INSERT INTO public.accommodations (
      id, organization_id, property_type, location, check_in, check_out, max_occupancy, occupancy_rules
    )
    VALUES (
      v_product_id,
      v_organization_id,
      v_property_type,
      v_location,
      v_check_in,
      v_check_out,
      v_max_occupancy,
      CASE
        WHEN jsonb_typeof(p_accommodation -> 'occupancy_rules') = 'object'
          THEN p_accommodation -> 'occupancy_rules'
        ELSE NULL
      END
    );
  END IF;

  IF p_category_ids IS NOT NULL THEN
    FOREACH v_category_id IN ARRAY p_category_ids LOOP
      IF v_category_id IS NULL THEN
        CONTINUE;
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM public.categories c
        WHERE c.id = v_category_id
          AND c.organization_id = v_organization_id
      ) THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END IF;

      INSERT INTO public.product_categories (product_id, category_id, organization_id)
      VALUES (v_product_id, v_category_id, v_organization_id)
      ON CONFLICT (product_id, category_id) DO NOTHING;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('id', v_product_id, 'status', 'draft');
END;
$$;

COMMENT ON FUNCTION public.create_product(text, text, text, uuid, uuid[], jsonb, jsonb) IS
  'Operator/admin: create a draft experience or accommodation with its subtype row atomically.';

REVOKE EXECUTE ON FUNCTION public.create_product(text, text, text, uuid, uuid[], jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_product(text, text, text, uuid, uuid[], jsonb, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_product_status
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_product_status(
  p_product_id uuid,
  p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_status public.product_status;
  v_result jsonb;
BEGIN
  v_organization_id := public.require_catalog_manager();

  IF p_product_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_status IS NULL OR p_status NOT IN ('active', 'inactive') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_status := p_status::public.product_status;

  BEGIN
    UPDATE public.products
    SET status = v_status
    WHERE id = p_product_id
      AND organization_id = v_organization_id
    RETURNING jsonb_build_object(
      'id', id,
      'status', status
    ) INTO v_result;
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM = 'PRODUCT_HAS_NO_VALID_PRICE' THEN
        RAISE EXCEPTION 'PRODUCT_HAS_NO_VALID_PRICE' USING ERRCODE = 'raise_exception';
      END IF;
      RAISE;
  END;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.set_product_status(uuid, text) IS
  'Operator/admin: activate or deactivate a product in the caller''s tenant. Activation requires a current pricing scheme (R-008). Emits product_activated / product_deactivated via trigger.';

REVOKE EXECUTE ON FUNCTION public.set_product_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_product_status(uuid, text) TO authenticated;
