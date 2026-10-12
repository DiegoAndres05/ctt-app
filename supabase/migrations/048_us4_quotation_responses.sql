-- 048_us4_quotation_responses.sql
-- US4 public RPCs: responses, public acceptance, versioning, voiding and the
-- internal 006 boundary.
-- Source of truth: specs/005-quotation-proposals/contracts/api-contracts.md (§5, §8),
-- specs/005-quotation-proposals/data-model.md (§Functions US4),
-- specs/005-quotation-proposals/research.md (R-004, R-007, R-008, R-010, R-011).
--
-- Both acceptance paths run, in order: tenant sweep → still issued →
-- assert_pre_reservation_quotable (004) → fingerprint comparison. A failed
-- fingerprint leaves the version expired and audits quotation_expired with
-- { reason_code: stale } before raising QUOTATION_STALE. No function here
-- inserts reservation, payment or invoice rows; assert_quotation_confirmable is
-- the internal snapshot feature 006 will consume.

-- ---------------------------------------------------------------------------
-- record_quotation_response(p_version_id uuid, p_kind quotation_response_kind) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_quotation_response(
  p_version_id uuid,
  p_kind public.quotation_response_kind
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_version public.quotation_versions%ROWTYPE;
  v_pre_reservation_id uuid;
  v_status public.quotation_status;
BEGIN
  v_org := public.require_tenant_member();

  IF p_version_id IS NULL OR p_kind IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Contracts §5 order: sweep first so a due version cannot be answered. The
  -- acceptance sweep is due-only: a stale fingerprint must surface as
  -- QUOTATION_STALE below, not as a silent expiry.
  PERFORM public.expire_due_quotations_core(v_org, false);

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status = ANY (ARRAY['accepted', 'voided', 'superseded']::public.quotation_status[]) THEN
    IF p_kind = 'accepted'::public.quotation_response_kind THEN
      RAISE EXCEPTION 'QUOTATION_NOT_OPEN' USING ERRCODE = 'raise_exception';
    END IF;
    RAISE EXCEPTION 'QUOTATION_TERMINAL' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status <> 'issued'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_NOT_OPEN' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT f.pre_reservation_id INTO v_pre_reservation_id
  FROM public.quotation_families f
  WHERE f.id = v_version.family_id AND f.organization_id = v_org;

  IF p_kind = 'accepted'::public.quotation_response_kind THEN
    PERFORM public.assert_pre_reservation_quotable(v_org, v_pre_reservation_id);

    -- Fingerprint mismatch (R-004): the version flips to expired and audits
    -- reason_code stale before raising. The raise rolls this back within the
    -- call; the fingerprint-aware sweep (expire_due_quotations / the public
    -- read) commits the same flip at the next read.
    IF public.capture_pre_reservation_fingerprint(v_org, v_pre_reservation_id)
       IS DISTINCT FROM v_version.pre_reservation_fingerprint
    THEN
      UPDATE public.quotation_versions v
      SET status = 'expired'::public.quotation_status,
          expired_at = now()
      WHERE v.id = p_version_id;

      PERFORM audit.log_event(
        v_org,
        'quotation_expired'::audit.audit_event_type,
        'success'::audit.audit_result,
        auth.uid(),
        'quotation_version',
        p_version_id,
        jsonb_build_object(
          'family_id', v_version.family_id,
          'version_number', v_version.version_number,
          'reason_code', 'stale'
        )
      );

      RAISE EXCEPTION 'QUOTATION_STALE' USING ERRCODE = 'raise_exception';
    END IF;

    UPDATE public.quotation_versions v
    SET status = 'accepted'::public.quotation_status,
        accepted_at = now(),
        response_origin = 'agent'::public.quotation_response_origin
    WHERE v.id = p_version_id;
  ELSIF p_kind = 'rejected'::public.quotation_response_kind THEN
    UPDATE public.quotation_versions v
    SET status = 'rejected'::public.quotation_status,
        rejected_at = now(),
        response_origin = 'agent'::public.quotation_response_origin
    WHERE v.id = p_version_id;
  END IF;
  -- changes_requested is not a status: only the response row is written (R-007).

  INSERT INTO public.quotation_responses (
    organization_id, version_id, kind, origin, created_by
  ) VALUES (
    v_org, p_version_id, p_kind, 'agent'::public.quotation_response_origin, auth.uid()
  );

  PERFORM audit.log_event(
    v_org,
    'quotation_response_recorded'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'quotation_version',
    p_version_id,
    jsonb_build_object(
      'family_id', v_version.family_id,
      'version_number', v_version.version_number,
      'response', p_kind,
      'origin', 'agent'
    )
  );

  SELECT v.status INTO v_status
  FROM public.quotation_versions v
  WHERE v.id = p_version_id;

  RETURN jsonb_build_object(
    'version_id', p_version_id,
    'status', v_status,
    'response', p_kind
  );
END;
$$;

COMMENT ON FUNCTION public.record_quotation_response(uuid, public.quotation_response_kind) IS
  'Agent-registered response on an issued version. accepted revalidates (sweep, quotable, fingerprint) and freezes; rejected closes; changes_requested only appends a quotation_responses row. Audit carries response/origin codes, never names.';

REVOKE ALL ON FUNCTION public.record_quotation_response(uuid, public.quotation_response_kind) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_quotation_response(uuid, public.quotation_response_kind) TO authenticated;

-- ---------------------------------------------------------------------------
-- accept_public_quotation(p_token text, p_confirmed boolean) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.accept_public_quotation(
  p_token text,
  p_confirmed boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_family_id uuid;
  v_organization_id uuid;
  v_pre_reservation_id uuid;
  v_version_id uuid;
  v_version public.quotation_versions%ROWTYPE;
BEGIN
  -- Two-step accept (R-008): nothing changes until the client confirms.
  IF coalesce(p_confirmed, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONFIRMATION_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  v_family_id := public.quotation_family_id_by_token(p_token);
  IF v_family_id IS NULL THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  SELECT f.organization_id, f.pre_reservation_id
  INTO v_organization_id, v_pre_reservation_id
  FROM public.quotation_families f
  WHERE f.id = v_family_id;

  -- Contracts §5 order: sweep, then require the version to still be issued.
  -- Due-only here: a stale fingerprint must surface as QUOTATION_STALE below.
  PERFORM public.expire_due_quotations_core(v_organization_id, false);

  v_version_id := public.quotation_current_version_id(v_family_id);
  IF v_version_id IS NULL THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = v_version_id
  FOR UPDATE;

  IF v_version.status = 'voided'::public.quotation_status THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  IF v_version.status <> 'issued'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_NOT_OPEN' USING ERRCODE = 'raise_exception';
  END IF;

  PERFORM public.assert_pre_reservation_quotable(v_organization_id, v_pre_reservation_id);

  -- Fingerprint mismatch (R-004): flip + audit reason_code stale + raise. The
  -- raise rolls this back within the call; the fingerprint-aware sweep at the
  -- next read commits the same flip (see expire_due_quotations_core).
  IF public.capture_pre_reservation_fingerprint(v_organization_id, v_pre_reservation_id)
     IS DISTINCT FROM v_version.pre_reservation_fingerprint
  THEN
    UPDATE public.quotation_versions v
    SET status = 'expired'::public.quotation_status,
        expired_at = now()
    WHERE v.id = v_version_id;

    PERFORM audit.log_event(
      v_organization_id,
      'quotation_expired'::audit.audit_event_type,
      'success'::audit.audit_result,
      NULL,
      'quotation_version',
      v_version_id,
      jsonb_build_object(
        'family_id', v_version.family_id,
        'version_number', v_version.version_number,
        'reason_code', 'stale'
      )
    );

    RAISE EXCEPTION 'QUOTATION_STALE' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.quotation_versions v
  SET status = 'accepted'::public.quotation_status,
      accepted_at = now(),
      response_origin = 'customer'::public.quotation_response_origin
  WHERE v.id = v_version_id;

  INSERT INTO public.quotation_responses (
    organization_id, version_id, kind, origin, created_by
  ) VALUES (
    v_organization_id, v_version_id,
    'accepted'::public.quotation_response_kind,
    'customer'::public.quotation_response_origin,
    NULL
  );

  PERFORM audit.log_event(
    v_organization_id,
    'quotation_response_recorded'::audit.audit_event_type,
    'success'::audit.audit_result,
    NULL,
    'quotation_version',
    v_version_id,
    jsonb_build_object(
      'family_id', v_version.family_id,
      'version_number', v_version.version_number,
      'response', 'accepted',
      'origin', 'customer'
    )
  );

  RETURN jsonb_build_object('available', true, 'status', 'accepted');
END;
$$;

COMMENT ON FUNCTION public.accept_public_quotation(text, boolean) IS
  'Two-step public acceptance by token: p_confirmed must be true (CONFIRMATION_REQUIRED), then sweep, quotable revalidation and fingerprint comparison. Origin customer. Creates no reservation.';

REVOKE ALL ON FUNCTION public.accept_public_quotation(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_public_quotation(text, boolean) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- create_quotation_version(p_version_id uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_quotation_version(
  p_version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_version public.quotation_versions%ROWTYPE;
  v_family public.quotation_families%ROWTYPE;
  v_new_id uuid;
  v_breakdown jsonb;
BEGIN
  v_org := public.require_tenant_member();

  IF p_version_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status = ANY (ARRAY['accepted', 'voided', 'superseded']::public.quotation_status[]) THEN
    RAISE EXCEPTION 'QUOTATION_TERMINAL' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status <> 'issued'::public.quotation_status
     AND v_version.status <> 'rejected'::public.quotation_status
     AND v_version.status <> 'expired'::public.quotation_status
  THEN
    RAISE EXCEPTION 'QUOTATION_NOT_OPEN' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT f.* INTO v_family
  FROM public.quotation_families f
  WHERE f.id = v_version.family_id AND f.organization_id = v_org;

  PERFORM public.assert_pre_reservation_quotable(v_org, v_family.pre_reservation_id);

  -- The origin becomes read-only; the family reference and token survive (R-007).
  UPDATE public.quotation_versions v
  SET status = 'superseded'::public.quotation_status,
      superseded_at = now()
  WHERE v.id = p_version_id;

  PERFORM audit.log_event(
    v_org,
    'quotation_superseded'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'quotation_version',
    p_version_id,
    jsonb_build_object(
      'family_id', v_version.family_id,
      'version_number', v_version.version_number,
      'pre_reservation_id', v_family.pre_reservation_id
    )
  );

  -- The new draft copies texts, not frozen amounts: tariffs are re-resolved.
  INSERT INTO public.quotation_versions (
    organization_id, family_id, version_number, status, currency,
    inclusions, exclusions, terms, commercial_notes, created_by
  ) VALUES (
    v_org, v_family.id, v_version.version_number + 1, 'draft'::public.quotation_status,
    v_version.currency, v_version.inclusions, v_version.exclusions,
    v_version.terms, v_version.commercial_notes, auth.uid()
  )
  RETURNING id INTO v_new_id;

  v_breakdown := public.recalculate_quotation_core(v_org, v_new_id);

  -- Carry over the per-line tax rates of the origin version (draft-only table).
  UPDATE public.quotation_lines l
  SET tax_rate = s.tax_rate
  FROM public.quotation_lines s
  WHERE s.version_id = p_version_id
    AND l.version_id = v_new_id
    AND s.pre_reservation_item_id = l.pre_reservation_item_id
    AND s.tax_rate IS DISTINCT FROM l.tax_rate;

  IF FOUND THEN
    v_breakdown := public.recalculate_quotation_core(v_org, v_new_id);
  END IF;

  PERFORM audit.log_event(
    v_org,
    'quotation_created'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'quotation_version',
    v_new_id,
    jsonb_build_object(
      'family_id', v_version.family_id,
      'version_number', v_version.version_number + 1,
      'pre_reservation_id', v_family.pre_reservation_id
    )
  );

  RETURN v_breakdown;
END;
$$;

COMMENT ON FUNCTION public.create_quotation_version(uuid) IS
  'Supersedes an issued/rejected/expired version and opens draft vN+1 in the same family: texts are copied, tariffs and amounts are recalculated, per-line tax rates carry over. accepted/voided/superseded reject with QUOTATION_TERMINAL. The family token is preserved.';

REVOKE ALL ON FUNCTION public.create_quotation_version(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_quotation_version(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- void_quotation(p_version_id uuid, p_reason text) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.void_quotation(
  p_version_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_version public.quotation_versions%ROWTYPE;
  v_reason text;
BEGIN
  v_org := public.require_tenant_admin();

  IF p_version_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'VOID_REASON_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;
  IF char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status = 'accepted'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_ACCEPTED' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status = ANY (ARRAY['voided', 'superseded']::public.quotation_status[]) THEN
    RAISE EXCEPTION 'QUOTATION_TERMINAL' USING ERRCODE = 'raise_exception';
  END IF;

  -- draft/issued/rejected/expired can be voided; the reason lives in the column.
  UPDATE public.quotation_versions v
  SET status = 'voided'::public.quotation_status,
      voided_at = now(),
      voided_by = auth.uid(),
      void_reason = v_reason
  WHERE v.id = p_version_id;

  PERFORM audit.log_event(
    v_org,
    'quotation_voided'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'quotation_version',
    p_version_id,
    jsonb_build_object(
      'family_id', v_version.family_id,
      'version_number', v_version.version_number
    )
  );

  RETURN jsonb_build_object('version_id', p_version_id, 'status', 'voided');
END;
$$;

COMMENT ON FUNCTION public.void_quotation(uuid, text) IS
  'Admin-only void with a mandatory reason (1-500) stored in void_reason, never in audit metadata. Kills the public link. Accepted quotations reject with QUOTATION_ACCEPTED.';

REVOKE ALL ON FUNCTION public.void_quotation(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.void_quotation(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- assert_quotation_confirmable(p_org uuid, p_version_id uuid) → jsonb (internal)
-- Feature 006 boundary (R-010): the frozen snapshot of an accepted version.
-- 005 never creates reservations, so no reservation can exist yet; the only
-- precondition here is status = accepted.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assert_quotation_confirmable(
  p_org uuid,
  p_version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_version public.quotation_versions%ROWTYPE;
  v_family public.quotation_families%ROWTYPE;
BEGIN
  IF p_org IS NULL OR p_version_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = p_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status <> 'accepted'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_NOT_ACCEPTED' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT f.* INTO v_family
  FROM public.quotation_families f
  WHERE f.id = v_version.family_id AND f.organization_id = p_org;

  RETURN jsonb_build_object(
    'version_id', v_version.id,
    'family_id', v_version.family_id,
    'version_number', v_version.version_number,
    'reference', v_family.reference,
    'pre_reservation_id', v_family.pre_reservation_id,
    'customer_id', v_family.customer_id,
    'currency', v_version.currency::text,
    'subtotal', v_version.subtotal,
    'tax_total', v_version.tax_total,
    'adjustment_total', v_version.adjustment_total,
    'total', v_version.total,
    'party_adults', v_version.party_adults,
    'party_children', v_version.party_children,
    'accepted_at', v_version.accepted_at,
    'lines', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'pre_reservation_item_id', l.pre_reservation_item_id,
        'item_kind', l.item_kind,
        'product_id', l.product_id,
        'addon_id', l.addon_id,
        'start_date', l.start_date,
        'end_date', l.end_date,
        'adults', l.adults,
        'children', l.children,
        'quantity', l.quantity,
        'charge_type', l.charge_type,
        'charge_basis', l.charge_basis,
        'tariff_currency', l.tariff_currency::text,
        'unit_price', l.unit_price,
        'tax_rate', l.tax_rate,
        'line_total', l.line_total
      ) ORDER BY l.position, l.created_at, l.id), '[]'::jsonb)
      FROM public.quotation_lines l
      WHERE l.version_id = v_version.id
    )
  );
END;
$$;

COMMENT ON FUNCTION public.assert_quotation_confirmable(uuid, uuid) IS
  'Feature 006 boundary: returns the frozen snapshot (reference, customer, pre-reservation, currency, totals, party size, lines) of an accepted version, or QUOTATION_NOT_ACCEPTED / VALIDATION_ERROR. Internal; creates no reservation.';

REVOKE ALL ON FUNCTION public.assert_quotation_confirmable(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_quotation_confirmable(uuid, uuid) FROM anon, authenticated;
