-- 040_us3_pre_reservation_consolidation.sql
-- Public RPCs to consolidate a pre-reservation: add/withdraw/promote lines, sweep expired
-- holds, authorize the admin quotation override, and the internal eligibility contract 005
-- will call.
-- Source of truth: specs/004-prereservation-availability/data-model.md (§Functions US3),
-- specs/004-prereservation-availability/contracts/api-contracts.md (§4),
-- specs/004-prereservation-availability/research.md (R-003, R-004, R-005, R-008).
--
-- All RPCs are SECURITY DEFINER with SET search_path = ''. Line-changing RPCs lock the
-- pre-reservation FOR UPDATE first, then the line, and end with
-- refresh_pre_reservation_status. Adding/withdrawing/promoving a MAIN line clears the
-- quote override (override_cleared in the audit metadata).

-- ---------------------------------------------------------------------------
-- add_pre_reservation_item(p_pre_reservation_id uuid, p_item jsonb) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.add_pre_reservation_item(
  p_pre_reservation_id uuid,
  p_item jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.pre_reservations%ROWTYPE;
  v_alternative_of uuid;
  v_resolved jsonb;
  v_item_id uuid;
  v_had_override boolean;
  v_override_cleared boolean;
  v_status public.pre_reservation_status;
BEGIN
  v_org := public.require_tenant_member();

  IF p_item IS NULL OR jsonb_typeof(p_item) <> 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_row
  FROM public.pre_reservations pr
  WHERE pr.id = p_pre_reservation_id
    AND pr.organization_id = v_org
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_row.status = 'cancelled' THEN
    RAISE EXCEPTION 'PRE_RESERVATION_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;

  -- Same payload as create, but alternatives point to an item id instead of an index.
  IF p_item ? 'alternative_of_item_id' AND p_item ->> 'alternative_of_item_id' <> '' THEN
    BEGIN
      v_alternative_of := (p_item ->> 'alternative_of_item_id')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;
  END IF;

  v_resolved := public.resolve_pre_reservation_item(v_org, v_row.request_id, p_item);

  -- Validates the 30-line cap and the alternative target, and logs item_added.
  v_item_id := public.insert_pre_reservation_item(
    v_org, p_pre_reservation_id, v_resolved, v_alternative_of, auth.uid()
  );

  v_had_override := v_row.quote_override_at IS NOT NULL;
  v_override_cleared := v_had_override AND v_alternative_of IS NULL;
  IF v_override_cleared THEN
    UPDATE public.pre_reservations
    SET quote_override_at = NULL,
        quote_override_by = NULL,
        quote_override_reason = NULL
    WHERE id = p_pre_reservation_id;
  END IF;

  PERFORM audit.log_event(
    v_org,
    'pre_reservation_items_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'pre_reservation',
    p_pre_reservation_id,
    jsonb_build_object(
      'action', 'added',
      'item_id', v_item_id,
      'override_cleared', v_override_cleared
    )
  );

  v_status := public.refresh_pre_reservation_status(p_pre_reservation_id);

  RETURN jsonb_build_object(
    'item_id', v_item_id,
    'pre_reservation_status', v_status
  );
END;
$$;

COMMENT ON FUNCTION public.add_pre_reservation_item(uuid, jsonb) IS
  'Adds one line (main or alternative) to a non-cancelled pre-reservation. Adding a main line clears the quote override.';

REVOKE ALL ON FUNCTION public.add_pre_reservation_item(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_pre_reservation_item(uuid, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- withdraw_pre_reservation_item(p_item_id uuid, p_reason text) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.withdraw_pre_reservation_item(
  p_item_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_pre_reservation_id uuid;
  v_row public.pre_reservations%ROWTYPE;
  v_item public.pre_reservation_items%ROWTYPE;
  v_reason text;
  v_is_main boolean;
  v_had_override boolean;
  v_override_cleared boolean;
  v_ids uuid[];
  v_alt_ids uuid[];
  v_remaining_mains integer;
  v_one record;
  v_status public.pre_reservation_status;
BEGIN
  v_org := public.require_tenant_member();

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  IF v_reason IS NULL OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Locking order: pre-reservation first, then the line.
  SELECT i.pre_reservation_id
  INTO v_pre_reservation_id
  FROM public.pre_reservation_items i
  WHERE i.id = p_item_id
    AND i.organization_id = v_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_row
  FROM public.pre_reservations pr
  WHERE pr.id = v_pre_reservation_id
    AND pr.organization_id = v_org
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_row.status = 'cancelled' THEN
    RAISE EXCEPTION 'PRE_RESERVATION_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_item
  FROM public.pre_reservation_items i
  WHERE i.id = p_item_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_item.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'ITEM_WITHDRAWN' USING ERRCODE = 'raise_exception';
  END IF;

  v_is_main := v_item.alternative_of_item_id IS NULL;
  v_had_override := v_row.quote_override_at IS NOT NULL;
  v_override_cleared := v_had_override AND v_is_main;

  -- Withdrawing a main also withdraws its active alternatives.
  v_ids := ARRAY[v_item.id];
  IF v_is_main THEN
    SELECT coalesce(array_agg(i.id), ARRAY[]::uuid[])
    INTO v_alt_ids
    FROM public.pre_reservation_items i
    WHERE i.pre_reservation_id = v_pre_reservation_id
      AND i.alternative_of_item_id = v_item.id
      AND i.withdrawn_at IS NULL;
    v_ids := v_ids || v_alt_ids;
  END IF;

  -- At least one active main line must remain.
  SELECT count(*)
  INTO v_remaining_mains
  FROM public.pre_reservation_items i
  WHERE i.pre_reservation_id = v_pre_reservation_id
    AND i.alternative_of_item_id IS NULL
    AND i.withdrawn_at IS NULL
    AND NOT (i.id = ANY (v_ids));
  IF v_remaining_mains = 0 THEN
    RAISE EXCEPTION 'PRE_RESERVATION_REQUIRES_ITEMS' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.pre_reservation_items
  SET withdrawn_at = now(),
      withdrawn_reason = v_reason,
      withdrawn_by = auth.uid()
  WHERE id = ANY (v_ids);

  -- One event per withdrawn line.
  FOR v_one IN
    SELECT i.id, i.verification_status
    FROM public.pre_reservation_items i
    WHERE i.id = ANY (v_ids)
  LOOP
    PERFORM public.log_availability_event(
      v_org,
      v_pre_reservation_id,
      v_one.id,
      'item_withdrawn'::public.availability_event_kind,
      v_one.verification_status,
      NULL,
      jsonb_build_object(
        'notes', v_reason,
        'metadata', jsonb_build_object('override_cleared', v_override_cleared)
      ),
      auth.uid()
    );
  END LOOP;

  IF v_override_cleared THEN
    UPDATE public.pre_reservations
    SET quote_override_at = NULL,
        quote_override_by = NULL,
        quote_override_reason = NULL
    WHERE id = v_pre_reservation_id;
  END IF;

  PERFORM audit.log_event(
    v_org,
    'pre_reservation_items_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'pre_reservation',
    v_pre_reservation_id,
    jsonb_build_object(
      'action', 'withdrawn',
      'item_ids', to_jsonb(v_ids),
      'override_cleared', v_override_cleared
    )
  );

  v_status := public.refresh_pre_reservation_status(v_pre_reservation_id);

  RETURN jsonb_build_object(
    'withdrawn_item_ids', to_jsonb(v_ids),
    'pre_reservation_status', v_status
  );
END;
$$;

COMMENT ON FUNCTION public.withdraw_pre_reservation_item(uuid, text) IS
  'Withdraws a line with a mandatory reason (1-500); a main line takes its active alternatives with it and clears the quote override.';

REVOKE ALL ON FUNCTION public.withdraw_pre_reservation_item(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.withdraw_pre_reservation_item(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- promote_alternative_item(p_item_id uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.promote_alternative_item(
  p_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_pre_reservation_id uuid;
  v_row public.pre_reservations%ROWTYPE;
  v_item public.pre_reservation_items%ROWTYPE;
  v_replaced public.pre_reservation_items%ROWTYPE;
  v_replaced_id uuid;
  v_had_override boolean;
  v_status public.pre_reservation_status;
BEGIN
  v_org := public.require_tenant_member();

  -- Locking order: pre-reservation first, then the line.
  SELECT i.pre_reservation_id
  INTO v_pre_reservation_id
  FROM public.pre_reservation_items i
  WHERE i.id = p_item_id
    AND i.organization_id = v_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_row
  FROM public.pre_reservations pr
  WHERE pr.id = v_pre_reservation_id
    AND pr.organization_id = v_org
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_row.status = 'cancelled' THEN
    RAISE EXCEPTION 'PRE_RESERVATION_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_item
  FROM public.pre_reservation_items i
  WHERE i.id = p_item_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_item.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'ITEM_WITHDRAWN' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_item.alternative_of_item_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_replaced_id := v_item.alternative_of_item_id;
  SELECT *
  INTO v_replaced
  FROM public.pre_reservation_items i
  WHERE i.id = v_replaced_id
    AND i.pre_reservation_id = v_pre_reservation_id
    AND i.organization_id = v_org
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_had_override := v_row.quote_override_at IS NOT NULL;

  -- The original main is withdrawn with the automatic reason.
  UPDATE public.pre_reservation_items
  SET withdrawn_at = now(),
      withdrawn_reason = 'Reemplazada por alternativa',
      withdrawn_by = auth.uid()
  WHERE id = v_replaced_id;

  -- The alternative becomes a main line.
  UPDATE public.pre_reservation_items
  SET alternative_of_item_id = NULL
  WHERE id = p_item_id;

  -- Sibling alternatives reparent to the promoted line.
  UPDATE public.pre_reservation_items
  SET alternative_of_item_id = p_item_id
  WHERE pre_reservation_id = v_pre_reservation_id
    AND alternative_of_item_id = v_replaced_id
    AND id <> p_item_id
    AND withdrawn_at IS NULL;

  IF v_had_override THEN
    UPDATE public.pre_reservations
    SET quote_override_at = NULL,
        quote_override_by = NULL,
        quote_override_reason = NULL
    WHERE id = v_pre_reservation_id;
  END IF;

  PERFORM public.log_availability_event(
    v_org,
    v_pre_reservation_id,
    p_item_id,
    'alternative_promoted'::public.availability_event_kind,
    v_item.verification_status,
    v_item.verification_status,
    jsonb_build_object(
      'metadata', jsonb_build_object(
        'replaced_item_id', v_replaced_id,
        'override_cleared', v_had_override
      )
    ),
    auth.uid()
  );

  PERFORM public.log_availability_event(
    v_org,
    v_pre_reservation_id,
    v_replaced_id,
    'item_withdrawn'::public.availability_event_kind,
    v_replaced.verification_status,
    NULL,
    jsonb_build_object(
      'notes', 'Reemplazada por alternativa',
      'metadata', jsonb_build_object('override_cleared', v_had_override)
    ),
    auth.uid()
  );

  PERFORM audit.log_event(
    v_org,
    'pre_reservation_items_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'pre_reservation',
    v_pre_reservation_id,
    jsonb_build_object(
      'action', 'promoted',
      'item_id', p_item_id,
      'replaced_item_id', v_replaced_id,
      'override_cleared', v_had_override
    )
  );

  v_status := public.refresh_pre_reservation_status(v_pre_reservation_id);

  RETURN jsonb_build_object(
    'item_id', p_item_id,
    'replaced_item_id', v_replaced_id,
    'pre_reservation_status', v_status
  );
END;
$$;

COMMENT ON FUNCTION public.promote_alternative_item(uuid) IS
  'Promotes an active alternative to main line: the original main is withdrawn («Reemplazada por alternativa»), siblings reparent, the quote override is cleared.';

REVOKE ALL ON FUNCTION public.promote_alternative_item(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.promote_alternative_item(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- expire_due_pre_reservations() → integer
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.expire_due_pre_reservations()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_count integer := 0;
  v_pre_reservation_id uuid;
BEGIN
  v_org := public.require_tenant_member();

  -- Idempotent sweep of the caller's tenant only (research R-004).
  FOR v_pre_reservation_id IN
    SELECT DISTINCT pr.id
    FROM public.pre_reservations pr
    JOIN public.pre_reservation_items i
      ON i.pre_reservation_id = pr.id
     AND i.organization_id = pr.organization_id
    WHERE pr.organization_id = v_org
      AND pr.status NOT IN ('cancelled', 'expired')
      AND i.alternative_of_item_id IS NULL
      AND i.withdrawn_at IS NULL
      AND i.verification_status = 'available'
      AND i.hold_expires_at IS NOT NULL
      AND i.hold_expires_at <= now()
  LOOP
    IF public.refresh_pre_reservation_status(v_pre_reservation_id) = 'expired' THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.expire_due_pre_reservations() IS
  'Sweeps the caller tenant: recomputes every non-cancelled pre-reservation whose main available line has an expired hold. Returns how many became expired.';

REVOKE ALL ON FUNCTION public.expire_due_pre_reservations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.expire_due_pre_reservations() TO authenticated;

-- ---------------------------------------------------------------------------
-- authorize_quotation_override(p_pre_reservation_id uuid, p_reason text) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.authorize_quotation_override(
  p_pre_reservation_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.pre_reservations%ROWTYPE;
  v_reason text;
  v_override_at timestamptz;
BEGIN
  v_org := public.require_tenant_admin();

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'OVERRIDE_REASON_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;
  IF char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_row
  FROM public.pre_reservations pr
  WHERE pr.id = p_pre_reservation_id
    AND pr.organization_id = v_org
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_row.status = 'cancelled' THEN
    RAISE EXCEPTION 'PRE_RESERVATION_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_row.status = 'verified' THEN
    RAISE EXCEPTION 'OVERRIDE_NOT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  v_override_at := now();

  UPDATE public.pre_reservations
  SET quote_override_at = v_override_at,
      quote_override_by = auth.uid(),
      quote_override_reason = v_reason
  WHERE id = p_pre_reservation_id;

  -- History keeps the reason; the audit log does not (research R-007).
  PERFORM public.log_availability_event(
    v_org,
    p_pre_reservation_id,
    NULL,
    'quote_override_authorized'::public.availability_event_kind,
    NULL,
    NULL,
    jsonb_build_object('notes', v_reason),
    auth.uid()
  );

  PERFORM audit.log_event(
    v_org,
    'quotation_override_authorized'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'pre_reservation',
    p_pre_reservation_id,
    jsonb_build_object('status', v_row.status)
  );

  RETURN jsonb_build_object(
    'pre_reservation_id', p_pre_reservation_id,
    'quote_override_at', v_override_at
  );
END;
$$;

COMMENT ON FUNCTION public.authorize_quotation_override(uuid, text) IS
  'Admin-only exception that makes a not-fully-verified pre-reservation quotable. Mandatory reason (1-500); audit stores {status} without the reason.';

REVOKE ALL ON FUNCTION public.authorize_quotation_override(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_quotation_override(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- assert_pre_reservation_quotable(p_org uuid, p_pre_reservation_id uuid) → jsonb (internal)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assert_pre_reservation_quotable(
  p_org uuid,
  p_pre_reservation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row public.pre_reservations%ROWTYPE;
  v_basis text;
BEGIN
  IF p_org IS NULL OR p_pre_reservation_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_row
  FROM public.pre_reservations pr
  WHERE pr.id = p_pre_reservation_id
    AND pr.organization_id = p_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Recompute first so an expired hold can never be quoted (research R-004/R-008).
  PERFORM public.refresh_pre_reservation_status(p_pre_reservation_id);

  SELECT *
  INTO v_row
  FROM public.pre_reservations pr
  WHERE pr.id = p_pre_reservation_id
    AND pr.organization_id = p_org;

  IF v_row.status = 'cancelled' THEN
    RAISE EXCEPTION 'PRE_RESERVATION_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_row.status = 'verified' THEN
    v_basis := 'verified';
  ELSIF v_row.quote_override_at IS NOT NULL THEN
    -- An authorized exception also covers expired (research R-008).
    v_basis := 'override';
  ELSIF v_row.status = 'expired' THEN
    RAISE EXCEPTION 'PRE_RESERVATION_EXPIRED' USING ERRCODE = 'raise_exception';
  ELSE
    RAISE EXCEPTION 'PRE_RESERVATION_NOT_VERIFIED' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN jsonb_build_object(
    'eligible', true,
    'basis', v_basis,
    'status', v_row.status,
    'expires_at', v_row.expires_at
  );
END;
$$;

COMMENT ON FUNCTION public.assert_pre_reservation_quotable(uuid, uuid) IS
  'Integration point for feature 005: recomputes the status and returns {eligible, basis, status, expires_at} or raises PRE_RESERVATION_CLOSED / PRE_RESERVATION_EXPIRED / PRE_RESERVATION_NOT_VERIFIED. Internal.';

REVOKE ALL ON FUNCTION public.assert_pre_reservation_quotable(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_pre_reservation_quotable(uuid, uuid) FROM anon, authenticated;
