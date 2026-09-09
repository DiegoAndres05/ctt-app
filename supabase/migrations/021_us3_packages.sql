-- 021_us3_packages.sql
-- User Story 3: predefined packages as a product subtype, itinerary items, atomic create_package,
-- and get_package_consistency (warning only — never auto-deactivates).
-- Source of truth: specs/002-catalog-pricing/data-model.md ("4. Package + Package Items",
-- RLS overview, warn_package_inconsistency),
-- specs/002-catalog-pricing/contracts/api-contracts.md (create_package, get_package_consistency).
--
-- Numbering: US4 already occupied 020_us4_pricing_rpcs.sql, so this migration is 021.
--
-- ERROR CONTRACT: RPCs raise the API contract's error code as the exception message
-- (SQLSTATE P0001 / insufficient_privilege). The frontend maps `error.message` back to an
-- application error code. Messages are therefore part of the API contract and must not be
-- reworded.
--
-- A package IS a products row of type `package`, priced explicitly via its own pricing_scheme
-- (Clarifications). Components are other products (experiences/accommodations), never packages.
-- organization_id is denormalized on both tables so RLS can filter without a join, and so
-- composite FKs pin package, items, and components to one tenant.
--
-- These routines that mutate are SECURITY DEFINER and owned by the migration role, which
-- bypasses RLS. Tenant and role checks below are therefore the authorization boundary.

-- ---------------------------------------------------------------------------
-- packages (1:1 subtype of products)
-- ---------------------------------------------------------------------------

CREATE TABLE public.packages (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  total_days integer,
  total_nights integer,
  CONSTRAINT packages_product_tenant_fkey
    FOREIGN KEY (id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT packages_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT packages_total_days_non_negative CHECK (total_days IS NULL OR total_days >= 0),
  CONSTRAINT packages_total_nights_non_negative CHECK (total_nights IS NULL OR total_nights >= 0)
);

COMMENT ON TABLE public.packages IS
  'Package itinerary metadata. Primary key is the parent products.id (type = package). Priced explicitly as that product, not as the sum of components.';

CREATE INDEX packages_organization_id_idx ON public.packages (organization_id);

ALTER TABLE public.packages ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.packages FROM anon;

CREATE POLICY tenant_isolation_select ON public.packages
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.packages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.packages
  FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

-- ---------------------------------------------------------------------------
-- package_items (composition + itinerary)
-- ---------------------------------------------------------------------------

CREATE TABLE public.package_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL,
  component_product_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  sort_order integer NOT NULL,
  day_number integer,
  CONSTRAINT package_items_package_tenant_fkey
    FOREIGN KEY (package_id, organization_id)
    REFERENCES public.packages (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT package_items_component_tenant_fkey
    FOREIGN KEY (component_product_id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT package_items_sort_order_non_negative CHECK (sort_order >= 0),
  CONSTRAINT package_items_day_number_positive CHECK (day_number IS NULL OR day_number >= 1)
);

COMMENT ON TABLE public.package_items IS
  'Ordered itinerary components of a package. Component and package share organization_id; nested packages are rejected.';

CREATE INDEX package_items_package_id_idx ON public.package_items (package_id);

CREATE INDEX package_items_component_product_id_idx ON public.package_items (component_product_id);

CREATE INDEX package_items_organization_id_idx ON public.package_items (organization_id);

ALTER TABLE public.package_items ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.package_items FROM anon;

CREATE POLICY tenant_isolation_select ON public.package_items
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.package_items
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.package_items
  FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_delete ON public.package_items
  FOR DELETE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

-- Nested packages are forbidden even if the caller bypasses create_package (PostgREST insert).
CREATE OR REPLACE FUNCTION public.enforce_package_item_not_nested()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_type public.product_type;
BEGIN
  SELECT p.type
  INTO v_type
  FROM public.products p
  WHERE p.id = NEW.component_product_id;

  IF v_type IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_type = 'package'::public.product_type THEN
    RAISE EXCEPTION 'PACKAGE_NESTING_NOT_ALLOWED' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_package_item_not_nested() IS
  'Rejects package_items whose component is itself a package (PACKAGE_NESTING_NOT_ALLOWED).';

CREATE TRIGGER package_items_not_nested
  BEFORE INSERT OR UPDATE OF component_product_id ON public.package_items
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_package_item_not_nested();

-- ---------------------------------------------------------------------------
-- create_package
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_package(
  p_name text,
  p_description text DEFAULT NULL,
  p_provider_id uuid DEFAULT NULL,
  p_category_ids uuid[] DEFAULT '{}'::uuid[],
  p_total_days integer DEFAULT NULL,
  p_total_nights integer DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
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
  v_product_id uuid;
  v_category_id uuid;
  v_elem jsonb;
  v_ord integer;
  v_component_id uuid;
  v_component_type public.product_type;
  v_sort_order integer;
  v_day_number integer;
BEGIN
  v_organization_id := public.require_catalog_manager();

  v_name := btrim(p_name);
  IF v_name IS NULL OR v_name = '' OR char_length(v_name) > 255 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_description := nullif(btrim(coalesce(p_description, '')), '');

  IF p_total_days IS NOT NULL AND p_total_days < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_total_nights IS NOT NULL AND p_total_nights < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_provider_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.providers pr
    WHERE pr.id = p_provider_id
      AND pr.organization_id = v_organization_id
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) < 1 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  FOR v_elem, v_ord IN
    SELECT elem, ord
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(elem, ord)
  LOOP
    IF jsonb_typeof(v_elem) <> 'object' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    BEGIN
      v_component_id := nullif(btrim(coalesce(v_elem ->> 'component_product_id', '')), '')::uuid;
      v_sort_order := coalesce(nullif(btrim(coalesce(v_elem ->> 'sort_order', '')), '')::integer, (v_ord - 1)::integer);
      v_day_number := nullif(btrim(coalesce(v_elem ->> 'day_number', '')), '')::integer;
    EXCEPTION
      WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;

    IF v_component_id IS NULL THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    SELECT p.type
    INTO v_component_type
    FROM public.products p
    WHERE p.id = v_component_id
      AND p.organization_id = v_organization_id;

    -- Missing or other-org component: same code so the RPC does not leak foreign ids.
    IF v_component_type IS NULL THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    IF v_component_type = 'package'::public.product_type THEN
      RAISE EXCEPTION 'PACKAGE_NESTING_NOT_ALLOWED' USING ERRCODE = 'raise_exception';
    END IF;
  END LOOP;

  INSERT INTO public.products (
    organization_id, provider_id, type, name, description, status
  )
  VALUES (
    v_organization_id, p_provider_id, 'package'::public.product_type, v_name, v_description, 'draft'
  )
  RETURNING id INTO v_product_id;

  INSERT INTO public.packages (id, organization_id, total_days, total_nights)
  VALUES (v_product_id, v_organization_id, p_total_days, p_total_nights);

  FOR v_elem, v_ord IN
    SELECT elem, ord
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(elem, ord)
  LOOP
    v_component_id := (v_elem ->> 'component_product_id')::uuid;
    v_sort_order := coalesce(nullif(btrim(coalesce(v_elem ->> 'sort_order', '')), '')::integer, (v_ord - 1)::integer);
    v_day_number := nullif(btrim(coalesce(v_elem ->> 'day_number', '')), '')::integer;

    INSERT INTO public.package_items (
      package_id, component_product_id, organization_id, sort_order, day_number
    )
    VALUES (
      v_product_id, v_component_id, v_organization_id, v_sort_order, v_day_number
    );
  END LOOP;

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

COMMENT ON FUNCTION public.create_package(text, text, uuid, uuid[], integer, integer, jsonb) IS
  'Operator/admin: create a draft package product with itinerary items. Rejects nested packages and cross-org components.';

REVOKE EXECUTE ON FUNCTION public.create_package(text, text, uuid, uuid[], integer, integer, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_package(text, text, uuid, uuid[], integer, integer, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_package_consistency (R-008 / US3 escenario 2)
-- Reports inactive components. Does NOT change the package status.
-- Invoker rights so RLS scopes the result to the caller's tenant.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_package_consistency(p_package_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_packages jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(report ORDER BY package_name), '[]'::jsonb)
  INTO v_packages
  FROM (
    SELECT
      prod.name AS package_name,
      jsonb_build_object(
        'package_id', pkg.id,
        'package_name', prod.name,
        'package_status', prod.status,
        'consistent', coalesce(inactive.cnt, 0) = 0,
        'inactive_components', coalesce(inactive.components, '[]'::jsonb)
      ) AS report
    FROM public.packages pkg
    JOIN public.products prod
      ON prod.id = pkg.id
    LEFT JOIN LATERAL (
      SELECT
        count(*)::integer AS cnt,
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'product_id', c.id,
              'name', c.name,
              'status', c.status,
              'type', c.type
            )
            ORDER BY pi.sort_order, c.name
          ),
          '[]'::jsonb
        ) AS components
      FROM public.package_items pi
      JOIN public.products c
        ON c.id = pi.component_product_id
      WHERE pi.package_id = pkg.id
        AND c.status = 'inactive'::public.product_status
    ) inactive ON true
    WHERE p_package_id IS NULL OR pkg.id = p_package_id
  ) q;

  RETURN jsonb_build_object('packages', v_packages);
END;
$$;

COMMENT ON FUNCTION public.get_package_consistency(uuid) IS
  'Returns packages whose components are inactive as a warning payload. Never mutates package status (R-008).';

REVOKE EXECUTE ON FUNCTION public.get_package_consistency(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_package_consistency(uuid) TO authenticated;
