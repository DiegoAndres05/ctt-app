-- 020_us4_pricing_rpcs.sql
-- User Story 4: define/version tariffs (operator/admin) and apply audited manual overrides (admin).
-- Source of truth: specs/002-catalog-pricing/data-model.md ("7. Pricing Scheme", Triggers & Functions),
-- specs/002-catalog-pricing/contracts/api-contracts.md (upsert_pricing_scheme, apply_price_override).
--
-- Table public.pricing_schemes, resolve_price(), and enforce_active_requires_price() already exist
-- (migration 017). This migration only adds the RPC surface, append-only enforcement, and audit.
--
-- ERROR CONTRACT: RPCs raise the API contract's error code as the exception message
-- (SQLSTATE P0001 / insufficient_privilege). The frontend maps `error.message` back to an
-- application error code. Messages are therefore part of the API contract and must not be
-- reworded.
--
-- VERSIONING: a tariff change never UPDATEs base_amount (or other descriptive columns) on an
-- existing row. The current row is closed with valid_to and a new row is inserted (SC-002).
--
-- These routines are SECURITY DEFINER and owned by the migration role, which bypasses RLS.
-- Tenant and role checks below are therefore the authorization boundary, not a convenience.

-- ---------------------------------------------------------------------------
-- Append-only: historical amounts are immutable; only valid_to may be set (to close a version)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_pricing_scheme_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.product_id IS DISTINCT FROM OLD.product_id
     OR NEW.addon_id IS DISTINCT FROM OLD.addon_id
     OR NEW.currency IS DISTINCT FROM OLD.currency
     OR NEW.base_amount IS DISTINCT FROM OLD.base_amount
     OR NEW.charge_type IS DISTINCT FROM OLD.charge_type
     OR NEW.season_start IS DISTINCT FROM OLD.season_start
     OR NEW.season_end IS DISTINCT FROM OLD.season_end
     OR NEW.valid_from IS DISTINCT FROM OLD.valid_from
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'PRICE_VERSION_IMMUTABLE' USING ERRCODE = 'raise_exception';
  END IF;

  -- A closed version cannot be reopened or have its close timestamp rewritten.
  IF OLD.valid_to IS NOT NULL AND NEW.valid_to IS DISTINCT FROM OLD.valid_to THEN
    RAISE EXCEPTION 'PRICE_VERSION_IMMUTABLE' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_pricing_scheme_append_only() IS
  'Blocks in-place mutation of pricing_schemes amounts and descriptors. Only valid_to may change, and only from NULL to a timestamp.';

CREATE TRIGGER pricing_schemes_append_only
  BEFORE UPDATE ON public.pricing_schemes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_pricing_scheme_append_only();

-- ---------------------------------------------------------------------------
-- Shared: close the matching current version (if any) and insert a new one
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.version_pricing_scheme(
  p_organization_id uuid,
  p_product_id uuid,
  p_addon_id uuid,
  p_currency text,
  p_base_amount numeric,
  p_charge_type public.charge_type,
  p_season_start date,
  p_season_end date
)
RETURNS public.pricing_schemes
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_as_of timestamptz := clock_timestamp();
  v_prior public.pricing_schemes;
  v_new public.pricing_schemes;
BEGIN
  SELECT *
  INTO v_prior
  FROM public.pricing_schemes ps
  WHERE ps.organization_id = p_organization_id
    AND ps.product_id IS NOT DISTINCT FROM p_product_id
    AND ps.addon_id IS NOT DISTINCT FROM p_addon_id
    AND ps.charge_type = p_charge_type
    AND ps.season_start IS NOT DISTINCT FROM p_season_start
    AND ps.season_end IS NOT DISTINCT FROM p_season_end
    AND ps.valid_to IS NULL
  FOR UPDATE;

  IF FOUND
     AND v_prior.base_amount = p_base_amount
     AND v_prior.currency = p_currency
  THEN
    RETURN v_prior;
  END IF;

  IF FOUND THEN
    UPDATE public.pricing_schemes
    SET valid_to = v_as_of
    WHERE id = v_prior.id
      AND valid_to IS NULL;
  END IF;

  BEGIN
    INSERT INTO public.pricing_schemes (
      organization_id,
      product_id,
      addon_id,
      currency,
      base_amount,
      charge_type,
      season_start,
      season_end,
      valid_from,
      valid_to
    )
    VALUES (
      p_organization_id,
      p_product_id,
      p_addon_id,
      p_currency,
      p_base_amount,
      p_charge_type,
      p_season_start,
      p_season_end,
      v_as_of,
      NULL
    )
    RETURNING * INTO v_new;
  EXCEPTION
    WHEN exclusion_violation THEN
      RAISE EXCEPTION 'SEASON_OVERLAP' USING ERRCODE = 'raise_exception';
    WHEN check_violation THEN
      IF SQLERRM ILIKE '%season%' THEN
        RAISE EXCEPTION 'INVALID_SEASON_RANGE' USING ERRCODE = 'raise_exception';
      END IF;
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  RETURN v_new;
END;
$$;

COMMENT ON FUNCTION public.version_pricing_scheme(uuid, uuid, uuid, text, numeric, public.charge_type, date, date) IS
  'Append-only tariff versioning: close the current matching row via valid_to, insert a new version. Never mutates historical amounts.';

REVOKE ALL ON FUNCTION public.version_pricing_scheme(uuid, uuid, uuid, text, numeric, public.charge_type, date, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.version_pricing_scheme(uuid, uuid, uuid, text, numeric, public.charge_type, date, date) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Audit a manual price override (FR-009, US4 scenario 2)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.audit_price_override(
  p_organization_id uuid,
  p_product_id uuid,
  p_previous_amount numeric,
  p_new_amount numeric,
  p_reason text,
  p_currency text,
  p_pricing_scheme_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM audit.log_event(
    p_organization_id,
    'price_overridden'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'product',
    p_product_id,
    jsonb_build_object(
      'product_id', p_product_id,
      'pricing_scheme_id', p_pricing_scheme_id,
      'previous_amount', p_previous_amount,
      'new_amount', p_new_amount,
      'reason', p_reason,
      'currency', p_currency
    )
  );
END;
$$;

COMMENT ON FUNCTION public.audit_price_override(uuid, uuid, numeric, numeric, text, text, uuid) IS
  'Writes price_overridden with actor, organization, previous/new amounts, currency, and reason.';

REVOKE ALL ON FUNCTION public.audit_price_override(uuid, uuid, numeric, numeric, text, text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.audit_price_override(uuid, uuid, numeric, numeric, text, text, uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- upsert_pricing_scheme (operator / admin)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.upsert_pricing_scheme(
  p_product_id uuid DEFAULT NULL,
  p_addon_id uuid DEFAULT NULL,
  p_currency text DEFAULT NULL,
  p_base_amount numeric DEFAULT NULL,
  p_charge_type text DEFAULT NULL,
  p_season_start date DEFAULT NULL,
  p_season_end date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_currency text;
  v_charge_type public.charge_type;
  v_season_start date;
  v_season_end date;
  v_row public.pricing_schemes;
BEGIN
  v_organization_id := public.require_catalog_manager();

  IF (p_product_id IS NULL) = (p_addon_id IS NULL) THEN
    RAISE EXCEPTION 'INVALID_PRICE_TARGET' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_product_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.products p
    WHERE p.id = p_product_id
      AND p.organization_id = v_organization_id
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_addon_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.add_ons a
    WHERE a.id = p_addon_id
      AND a.organization_id = v_organization_id
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_base_amount IS NULL OR p_base_amount < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_charge_type IS NULL OR p_charge_type NOT IN ('per_person', 'per_night', 'per_group') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_charge_type := p_charge_type::public.charge_type;

  v_season_start := p_season_start;
  v_season_end := p_season_end;
  IF (v_season_start IS NULL) <> (v_season_end IS NULL) THEN
    RAISE EXCEPTION 'INVALID_SEASON_RANGE' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_season_start IS NOT NULL AND v_season_start > v_season_end THEN
    RAISE EXCEPTION 'INVALID_SEASON_RANGE' USING ERRCODE = 'raise_exception';
  END IF;

  v_currency := upper(nullif(btrim(coalesce(p_currency, '')), ''));
  IF v_currency IS NULL THEN
    SELECT upper(coalesce(nullif(btrim(o.settings ->> 'default_currency'), ''), 'COP'))
    INTO v_currency
    FROM public.organizations o
    WHERE o.id = v_organization_id;
  END IF;
  IF v_currency IS NULL OR v_currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_row := public.version_pricing_scheme(
    v_organization_id,
    p_product_id,
    p_addon_id,
    v_currency,
    p_base_amount,
    v_charge_type,
    v_season_start,
    v_season_end
  );

  RETURN jsonb_build_object('id', v_row.id, 'valid_from', v_row.valid_from);
END;
$$;

COMMENT ON FUNCTION public.upsert_pricing_scheme(uuid, uuid, text, numeric, text, date, date) IS
  'Operator/admin: create or version a base or seasonal tariff (append-only). Raises SEASON_OVERLAP, INVALID_SEASON_RANGE, INVALID_PRICE_TARGET.';

REVOKE EXECUTE ON FUNCTION public.upsert_pricing_scheme(uuid, uuid, text, numeric, text, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_pricing_scheme(uuid, uuid, text, numeric, text, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- apply_price_override (admin only)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_price_override(
  p_product_id uuid,
  p_new_amount numeric,
  p_reason text,
  p_charge_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_reason text;
  v_charge_type public.charge_type;
  v_current public.pricing_schemes;
  v_new public.pricing_schemes;
BEGIN
  v_organization_id := public.require_tenant_admin();

  IF p_product_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_new_amount IS NULL OR p_new_amount < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_reason := btrim(coalesce(p_reason, ''));
  IF v_reason = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_charge_type IS NOT NULL THEN
    IF p_charge_type NOT IN ('per_person', 'per_night', 'per_group') THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    v_charge_type := p_charge_type::public.charge_type;
  END IF;

  SELECT *
  INTO v_current
  FROM public.pricing_schemes ps
  WHERE ps.organization_id = v_organization_id
    AND ps.product_id = p_product_id
    AND ps.valid_to IS NULL
    AND (v_charge_type IS NULL OR ps.charge_type = v_charge_type)
  ORDER BY
    (ps.season_start IS NULL) DESC,
    ps.valid_from DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_new := public.version_pricing_scheme(
    v_organization_id,
    v_current.product_id,
    v_current.addon_id,
    v_current.currency,
    p_new_amount,
    v_current.charge_type,
    v_current.season_start,
    v_current.season_end
  );

  PERFORM public.audit_price_override(
    v_organization_id,
    p_product_id,
    v_current.base_amount,
    p_new_amount,
    v_reason,
    v_new.currency,
    v_new.id
  );

  RETURN jsonb_build_object(
    'pricing_scheme_id', v_new.id,
    'previous_amount', v_current.base_amount,
    'new_amount', p_new_amount
  );
END;
$$;

COMMENT ON FUNCTION public.apply_price_override(uuid, numeric, text, text) IS
  'Admin only: append-only manual tariff override. Emits price_overridden with actor, org, previous/new amounts, and reason.';

REVOKE EXECUTE ON FUNCTION public.apply_price_override(uuid, numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_price_override(uuid, numeric, text, text) TO authenticated;
