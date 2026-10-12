-- 038_us1_pre_reservation_conversion.sql
-- Public RPCs to convert a request into a pre-reservation and to cancel one.
-- Source of truth: specs/004-prereservation-availability/data-model.md (§Functions US1),
-- specs/004-prereservation-availability/contracts/api-contracts.md (§2),
-- specs/004-prereservation-availability/research.md (R-002).
--
-- Both RPCs are SECURITY DEFINER with SET search_path = '' and authorize with
-- require_tenant_member(). Error codes travel as the exception message (contracts §7).

-- ---------------------------------------------------------------------------
-- create_pre_reservation(p_request_id uuid, p_payload jsonb) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_pre_reservation(
  p_request_id uuid,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
  v_org := public.require_tenant_member();

  -- The core locks the request FOR UPDATE, validates items and assigned_operator_id
  -- (ASSIGNEE_NOT_OPERATOR), converts the request when appropriate and emits the audits.
  RETURN public.create_pre_reservation_core(v_org, p_request_id, p_payload, auth.uid());
END;
$$;

COMMENT ON FUNCTION public.create_pre_reservation(uuid, jsonb) IS
  'Converts a request into a pre-reservation with concrete lines. Tenant member only. Returns {pre_reservation_id, reference, status, request_status}.';

REVOKE ALL ON FUNCTION public.create_pre_reservation(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pre_reservation(uuid, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- cancel_pre_reservation(p_pre_reservation_id uuid, p_reason text) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.cancel_pre_reservation(
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
  v_cancelled_at timestamptz;
BEGIN
  v_org := public.require_tenant_member();

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'CANCEL_REASON_REQUIRED' USING ERRCODE = 'raise_exception';
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

  v_cancelled_at := now();

  -- verified_at must go NULL: pre_reservations_verified_consistent ties it to status.
  -- The source request is intentionally left untouched (contracts §2.2).
  UPDATE public.pre_reservations
  SET status = 'cancelled',
      cancelled_at = v_cancelled_at,
      cancel_reason = v_reason,
      cancelled_by = auth.uid(),
      verified_at = NULL
  WHERE id = p_pre_reservation_id;

  PERFORM public.log_availability_event(
    v_org,
    p_pre_reservation_id,
    NULL,
    'pre_reservation_cancelled'::public.availability_event_kind,
    NULL,
    NULL,
    jsonb_build_object('notes', v_reason),
    auth.uid()
  );

  PERFORM audit.log_event(
    v_org,
    'pre_reservation_cancelled'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'pre_reservation',
    p_pre_reservation_id,
    jsonb_build_object('from', v_row.status)
  );

  RETURN jsonb_build_object(
    'pre_reservation_id', p_pre_reservation_id,
    'status', 'cancelled',
    'cancelled_at', v_cancelled_at
  );
END;
$$;

COMMENT ON FUNCTION public.cancel_pre_reservation(uuid, text) IS
  'Cancels a pre-reservation with a mandatory reason (1-500). Terminal state; the source request does not change. Audit stores {from} without the reason.';

REVOKE ALL ON FUNCTION public.cancel_pre_reservation(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_pre_reservation(uuid, text) TO authenticated;
