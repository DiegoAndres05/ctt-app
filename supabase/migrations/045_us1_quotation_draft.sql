-- 045_us1_quotation_draft.sql
-- US1 public RPCs: draft creation and server-side draft editing.
-- Source of truth: specs/005-quotation-proposals/contracts/api-contracts.md (§2, §8),
-- specs/005-quotation-proposals/data-model.md (§Functions US1),
-- specs/005-quotation-proposals/research.md (R-001..R-005, R-009).
--
-- Every RPC is SECURITY DEFINER with SET search_path = '', authorizes with
-- require_tenant_member() and is GRANT EXECUTE only to authenticated. Error codes
-- travel as the exception message (contracts §8 preamble). Audit metadata carries
-- only ids, version numbers and safe codes: never a label, terms, notes or token.

-- ---------------------------------------------------------------------------
-- create_quotation_draft(p_pre_reservation_id uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_quotation_draft(
  p_pre_reservation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_pr public.pre_reservations%ROWTYPE;
  v_family public.quotation_families%ROWTYPE;
  v_version_id uuid;
  v_currency text;
  v_terms text;
  v_inclusions text;
  v_breakdown jsonb;
BEGIN
  v_org := public.require_tenant_member();

  IF p_pre_reservation_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT pr.* INTO v_pr
  FROM public.pre_reservations pr
  WHERE pr.id = p_pre_reservation_id AND pr.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Feature 004 eligibility gate (research R-004): raises
  -- PRE_RESERVATION_NOT_VERIFIED / PRE_RESERVATION_EXPIRED / PRE_RESERVATION_CLOSED.
  PERFORM public.assert_pre_reservation_quotable(v_org, p_pre_reservation_id);

  -- An accepted quotation ends the quoting for this pre-reservation.
  IF EXISTS (
    SELECT 1
    FROM public.quotation_versions v
    JOIN public.quotation_families f ON f.id = v.family_id
    WHERE f.organization_id = v_org
      AND f.pre_reservation_id = p_pre_reservation_id
      AND v.status = 'accepted'::public.quotation_status
  ) THEN
    RAISE EXCEPTION 'QUOTATION_ALREADY_ACCEPTED' USING ERRCODE = 'raise_exception';
  END IF;

  -- An already-open draft is returned instead of creating a second one.
  SELECT v.id INTO v_version_id
  FROM public.quotation_versions v
  JOIN public.quotation_families f ON f.id = v.family_id
  WHERE f.organization_id = v_org
    AND f.pre_reservation_id = p_pre_reservation_id
    AND v.status = 'draft'::public.quotation_status
  ORDER BY v.created_at DESC, v.version_number DESC
  LIMIT 1;

  IF v_version_id IS NOT NULL THEN
    RETURN public.recalculate_quotation_core(v_org, v_version_id);
  END IF;

  -- An issued (open) version without a draft blocks a new family (R-007).
  IF EXISTS (
    SELECT 1
    FROM public.quotation_versions v
    JOIN public.quotation_families f ON f.id = v.family_id
    WHERE f.organization_id = v_org
      AND f.pre_reservation_id = p_pre_reservation_id
      AND v.status = 'issued'::public.quotation_status
  ) THEN
    RAISE EXCEPTION 'QUOTATION_ALREADY_OPEN' USING ERRCODE = 'raise_exception';
  END IF;

  -- Quotation currency: tenant default, COP when unset (R-003).
  SELECT coalesce(nullif(upper(btrim(o.settings ->> 'default_currency')), ''), 'COP')
  INTO v_currency
  FROM public.organizations o
  WHERE o.id = v_org;

  IF v_currency IS NULL OR v_currency !~ '^[A-Z]{3}$' THEN
    v_currency := 'COP';
  END IF;

  -- Terms: organization template, else the fixed text of research R-009.
  v_terms := (
    SELECT left(
      coalesce(nullif(btrim(d.terms_template), ''), public.quotation_default_terms()),
      8000
    )
    FROM public.quotation_defaults d
    WHERE d.organization_id = v_org
  );
  IF v_terms IS NULL THEN
    v_terms := public.quotation_default_terms();
  END IF;

  -- Spanish inclusions copied from the published public listing of each product,
  -- when one exists (research R-009). Exclusions are written by the agent.
  SELECT left(coalesce(string_agg(s.elem, E'\n' ORDER BY s.pos, s.ord), ''), 4000)
  INTO v_inclusions
  FROM (
    SELECT
      i.position AS pos,
      e.ord AS ord,
      nullif(e.value ->> 'es', '') AS elem
    FROM public.pre_reservation_items i
    JOIN public.public_listings pl
      ON pl.organization_id = i.organization_id
     AND pl.product_id = i.product_id
     AND pl.status = 'published'::public.public_listing_status
    CROSS JOIN LATERAL jsonb_array_elements(pl.includes) WITH ORDINALITY AS e(value, ord)
    WHERE i.organization_id = v_org
      AND i.pre_reservation_id = p_pre_reservation_id
      AND i.alternative_of_item_id IS NULL
      AND i.withdrawn_at IS NULL
      AND i.product_id IS NOT NULL
  ) s
  WHERE s.elem IS NOT NULL;

  INSERT INTO public.quotation_families (
    organization_id, pre_reservation_id, customer_id, created_by
  ) VALUES (
    v_org, p_pre_reservation_id, v_pr.customer_id, auth.uid()
  )
  RETURNING * INTO v_family;

  INSERT INTO public.quotation_versions (
    organization_id, family_id, version_number, status, currency,
    inclusions, terms, created_by
  ) VALUES (
    v_org, v_family.id, 1, 'draft'::public.quotation_status, v_currency::char(3),
    coalesce(v_inclusions, ''), v_terms, auth.uid()
  )
  RETURNING id INTO v_version_id;

  v_breakdown := public.recalculate_quotation_core(v_org, v_version_id);

  PERFORM audit.log_event(
    v_org,
    'quotation_created'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'quotation_version',
    v_version_id,
    jsonb_build_object(
      'family_id', v_family.id,
      'version_number', 1,
      'pre_reservation_id', p_pre_reservation_id
    )
  );

  RETURN v_breakdown;
END;
$$;

COMMENT ON FUNCTION public.create_quotation_draft(uuid) IS
  'Creates family + v1 draft for an eligible pre-reservation (or returns the open draft). Returns the server breakdown with pending_currencies. Audit quotation_created carries ids only.';

REVOKE ALL ON FUNCTION public.create_quotation_draft(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_quotation_draft(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- recalculate_quotation(p_version_id uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.recalculate_quotation(
  p_version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_status public.quotation_status;
  v_breakdown jsonb;
BEGIN
  v_org := public.require_tenant_member();

  SELECT v.status INTO v_status
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  v_breakdown := public.recalculate_quotation_core(v_org, p_version_id);

  -- Drafts tolerate a missing rate; this explicit recalculation demands one (§2).
  IF jsonb_array_length(v_breakdown -> 'pending_currencies') > 0 THEN
    RAISE EXCEPTION 'EXCHANGE_RATE_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_breakdown;
END;
$$;

COMMENT ON FUNCTION public.recalculate_quotation(uuid) IS
  'Recalculates a draft and returns the breakdown. Raises EXCHANGE_RATE_REQUIRED when a tariff currency still has no rate.';

REVOKE ALL ON FUNCTION public.recalculate_quotation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recalculate_quotation(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_quotation_line_tax(p_line_id uuid, p_tax_rate numeric) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_quotation_line_tax(
  p_line_id uuid,
  p_tax_rate numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_version_id uuid;
  v_status public.quotation_status;
BEGIN
  v_org := public.require_tenant_member();

  IF p_line_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT l.version_id, v.status INTO v_version_id, v_status
  FROM public.quotation_lines l
  JOIN public.quotation_versions v ON v.id = l.version_id
  WHERE l.id = p_line_id AND l.organization_id = v_org
  FOR UPDATE OF l;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_tax_rate IS NULL OR p_tax_rate < 0 OR p_tax_rate > 100 THEN
    RAISE EXCEPTION 'TAX_RATE_OUT_OF_RANGE' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.quotation_lines
  SET tax_rate = p_tax_rate
  WHERE id = p_line_id;

  RETURN public.recalculate_quotation_core(v_org, v_version_id);
END;
$$;

COMMENT ON FUNCTION public.set_quotation_line_tax(uuid, numeric) IS
  'Sets the per-line tax rate (0-100) on a draft line and returns the recalculated breakdown.';

REVOKE ALL ON FUNCTION public.set_quotation_line_tax(uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_quotation_line_tax(uuid, numeric) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_quotation_exchange_rate(p_version_id uuid, p_currency text, p_rate numeric) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_quotation_exchange_rate(
  p_version_id uuid,
  p_currency text,
  p_rate numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_status public.quotation_status;
  v_currency text;
BEGIN
  v_org := public.require_tenant_member();

  v_currency := upper(btrim(coalesce(p_currency, '')));
  IF v_currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_rate IS NULL OR p_rate <= 0 THEN
    RAISE EXCEPTION 'EXCHANGE_RATE_INVALID' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.status INTO v_status
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.quotation_versions
  SET exchange_rates = coalesce(exchange_rates, '{}'::jsonb)
        || jsonb_build_object(v_currency, p_rate)
  WHERE id = p_version_id;

  RETURN public.recalculate_quotation_core(v_org, p_version_id);
END;
$$;

COMMENT ON FUNCTION public.set_quotation_exchange_rate(uuid, text, numeric) IS
  'Stores a rate > 0 for a tariff currency on the draft (units of quotation currency per unit of the tariff currency) and returns the recalculated breakdown.';

REVOKE ALL ON FUNCTION public.set_quotation_exchange_rate(uuid, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_quotation_exchange_rate(uuid, text, numeric) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_quotation_texts(p_version_id uuid, p_inclusions text, p_exclusions text, p_notes text) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_quotation_texts(
  p_version_id uuid,
  p_inclusions text,
  p_exclusions text,
  p_notes text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_status public.quotation_status;
  v_inclusions text;
  v_exclusions text;
  v_notes text;
BEGIN
  v_org := public.require_tenant_member();

  SELECT v.status INTO v_status
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  v_inclusions := coalesce(p_inclusions, '');
  v_exclusions := coalesce(p_exclusions, '');
  v_notes := coalesce(p_notes, '');

  IF char_length(v_inclusions) > 4000
     OR char_length(v_exclusions) > 4000
     OR char_length(v_notes) > 2000
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.quotation_versions
  SET inclusions = v_inclusions,
      exclusions = v_exclusions,
      commercial_notes = nullif(v_notes, '')
  WHERE id = p_version_id;

  RETURN jsonb_build_object('version_id', p_version_id);
END;
$$;

COMMENT ON FUNCTION public.set_quotation_texts(uuid, text, text, text) IS
  'Updates draft texts: inclusions and exclusions (<= 4000 each) and internal notes (<= 2000).';

REVOKE ALL ON FUNCTION public.set_quotation_texts(uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_quotation_texts(uuid, text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- upsert_quotation_adjustment(...) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.upsert_quotation_adjustment(
  p_version_id uuid,
  p_pre_reservation_item_id uuid,
  p_label text,
  p_direction public.quotation_adjustment_direction,
  p_kind public.quotation_adjustment_kind,
  p_value numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_version public.quotation_versions%ROWTYPE;
  v_label text;
  v_impact jsonb;
  v_is_admin boolean := false;
  v_needs_admin boolean;
  v_pre_reservation_id uuid;
  v_breakdown jsonb;
BEGIN
  v_org := public.require_tenant_member();

  IF p_version_id IS NULL OR p_direction IS NULL OR p_kind IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  v_label := nullif(btrim(coalesce(p_label, '')), '');
  IF v_label IS NULL THEN
    RAISE EXCEPTION 'ADJUSTMENT_LABEL_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;
  IF char_length(v_label) > 80 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_value IS NULL OR p_value <= 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF p_kind = 'percent'::public.quotation_adjustment_kind AND p_value > 100 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- A line-scoped adjustment must target a line of this version.
  IF p_pre_reservation_item_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.quotation_lines l
      WHERE l.version_id = p_version_id
        AND l.pre_reservation_item_id = p_pre_reservation_item_id
    ) THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  -- Same label on the same scope is an update; anything else is a new row.
  UPDATE public.quotation_adjustments
  SET direction = p_direction,
      kind = p_kind,
      value = p_value,
      created_by = auth.uid()
  WHERE version_id = p_version_id
    AND label = v_label
    AND pre_reservation_item_id IS NOT DISTINCT FROM p_pre_reservation_item_id;

  IF NOT FOUND THEN
    INSERT INTO public.quotation_adjustments (
      organization_id, version_id, pre_reservation_item_id,
      label, direction, kind, value, created_by
    ) VALUES (
      v_org, p_version_id, p_pre_reservation_item_id,
      v_label, p_direction, p_kind, p_value, auth.uid()
    );
  END IF;

  -- Admin gates (R-005): cumulative 15 % cap and any adjustment on a family
  -- whose origin was already issued. The write above rolls back with this raise.
  v_impact := public.quotation_adjustment_impact(v_org, p_version_id);

  BEGIN
    PERFORM public.require_tenant_admin();
    v_is_admin := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_is_admin := false;
  END;

  v_needs_admin := v_version.version_number > 1 OR EXISTS (
    SELECT 1
    FROM public.quotation_versions vo
    WHERE vo.family_id = v_version.family_id
      AND vo.issued_at IS NOT NULL
  );

  IF (COALESCE((v_impact ->> 'requires_admin')::boolean, false) OR v_needs_admin)
     AND NOT v_is_admin
  THEN
    RAISE EXCEPTION 'ADJUSTMENT_REQUIRES_ADMIN' USING ERRCODE = 'raise_exception';
  END IF;

  v_breakdown := public.recalculate_quotation_core(v_org, p_version_id);

  SELECT f.pre_reservation_id INTO v_pre_reservation_id
  FROM public.quotation_families f
  WHERE f.id = v_version.family_id;

  PERFORM audit.log_event(
    v_org,
    'quotation_adjustment_applied'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'quotation_version',
    p_version_id,
    jsonb_build_object(
      'family_id', v_version.family_id,
      'version_number', v_version.version_number,
      'pre_reservation_id', v_pre_reservation_id,
      'direction', p_direction,
      'kind', p_kind
    )
  );

  RETURN v_breakdown;
END;
$$;

COMMENT ON FUNCTION public.upsert_quotation_adjustment(uuid, uuid, text, quotation_adjustment_direction, quotation_adjustment_kind, numeric) IS
  'Creates or updates one draft adjustment (line-scoped when item id is set, else global). Label mandatory. Above the 15 % cap or on a family with an issued origin only an admin passes. Audit carries direction/kind, never the label.';

REVOKE ALL ON FUNCTION public.upsert_quotation_adjustment(uuid, uuid, text, public.quotation_adjustment_direction, public.quotation_adjustment_kind, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_quotation_adjustment(uuid, uuid, text, public.quotation_adjustment_direction, public.quotation_adjustment_kind, numeric) TO authenticated;

-- ---------------------------------------------------------------------------
-- delete_quotation_adjustment(p_adjustment_id uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.delete_quotation_adjustment(
  p_adjustment_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_version_id uuid;
  v_status public.quotation_status;
BEGIN
  v_org := public.require_tenant_member();

  IF p_adjustment_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT a.version_id, v.status INTO v_version_id, v_status
  FROM public.quotation_adjustments a
  JOIN public.quotation_versions v ON v.id = a.version_id
  WHERE a.id = p_adjustment_id AND a.organization_id = v_org
  FOR UPDATE OF a;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  DELETE FROM public.quotation_adjustments
  WHERE id = p_adjustment_id;

  RETURN public.recalculate_quotation_core(v_org, v_version_id);
END;
$$;

COMMENT ON FUNCTION public.delete_quotation_adjustment(uuid) IS
  'Removes one draft adjustment and returns the recalculated breakdown. Frozen versions reject with QUOTATION_FROZEN.';

REVOKE ALL ON FUNCTION public.delete_quotation_adjustment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_quotation_adjustment(uuid) TO authenticated;
