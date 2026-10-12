-- 039_us2_availability_verification.sql
-- Public RPCs for the operational verification queue: operator assignment,
-- starting the provider conversation, and recording availability outcomes.
-- Source of truth: specs/004-prereservation-availability/data-model.md (§Functions US2),
-- specs/004-prereservation-availability/contracts/api-contracts.md (§3),
-- specs/004-prereservation-availability/research.md (R-003, R-007, R-009).
--
-- All RPCs are SECURITY DEFINER with SET search_path = ''. start/record authorize with
-- require_availability_verifier() (operator/admin); assign with require_tenant_member().
-- Locking order: pre-reservation FOR UPDATE first, then the line (data-model §Functions).

-- ---------------------------------------------------------------------------
-- assign_pre_reservation_operator(p_pre_reservation_id uuid, p_operator_id uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assign_pre_reservation_operator(
  p_pre_reservation_id uuid,
  p_operator_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.pre_reservations%ROWTYPE;
BEGIN
  v_org := public.require_tenant_member();

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

  -- NULL clears the assignment; anything else must be an active operator/admin of the org.
  IF p_operator_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_profiles p
    WHERE p.id = p_operator_id
      AND p.organization_id = v_org
      AND p.status = 'active'
      AND p.role IN ('operator', 'admin')
  ) THEN
    RAISE EXCEPTION 'ASSIGNEE_NOT_OPERATOR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.pre_reservations
  SET assigned_operator_id = p_operator_id
  WHERE id = p_pre_reservation_id;

  PERFORM audit.log_event(
    v_org,
    'pre_reservation_assigned'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'pre_reservation',
    p_pre_reservation_id,
    jsonb_build_object('from', v_row.assigned_operator_id, 'to', p_operator_id)
  );

  RETURN jsonb_build_object(
    'pre_reservation_id', p_pre_reservation_id,
    'assigned_operator_id', p_operator_id
  );
END;
$$;

COMMENT ON FUNCTION public.assign_pre_reservation_operator(uuid, uuid) IS
  'Assigns or clears the verification operator on a non-cancelled pre-reservation. Audit stores ids only.';

REVOKE ALL ON FUNCTION public.assign_pre_reservation_operator(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_pre_reservation_operator(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- start_item_verification(p_item_id uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.start_item_verification(
  p_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_actor uuid;
  v_pre_reservation_id uuid;
  v_pr public.pre_reservations%ROWTYPE;
  v_item public.pre_reservation_items%ROWTYPE;
  v_started_at timestamptz;
BEGIN
  v_org := public.require_availability_verifier();
  v_actor := auth.uid();

  -- Locate the line first so the pre-reservation is locked before it (data-model §Functions).
  SELECT i.pre_reservation_id
  INTO v_pre_reservation_id
  FROM public.pre_reservation_items i
  WHERE i.id = p_item_id
    AND i.organization_id = v_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_pr
  FROM public.pre_reservations pr
  WHERE pr.id = v_pre_reservation_id
    AND pr.organization_id = v_org
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_pr.status = 'cancelled' THEN
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

  -- Idempotent: only the first call stamps and logs.
  IF v_item.verification_started_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'item_id', p_item_id,
      'verification_started_at', v_item.verification_started_at,
      'assigned_operator_id', v_pr.assigned_operator_id
    );
  END IF;

  UPDATE public.pre_reservation_items
  SET verification_started_at = now()
  WHERE id = p_item_id
  RETURNING verification_started_at INTO v_started_at;

  -- First start auto-assigns the caller when nobody is assigned (research R-009).
  IF v_pr.assigned_operator_id IS NULL THEN
    UPDATE public.pre_reservations
    SET assigned_operator_id = v_actor
    WHERE id = v_pre_reservation_id;
    v_pr.assigned_operator_id := v_actor;
  END IF;

  PERFORM public.log_availability_event(
    v_org,
    v_pre_reservation_id,
    p_item_id,
    'verification_started'::public.availability_event_kind,
    NULL,
    v_item.verification_status,
    jsonb_build_object(),
    v_actor
  );

  PERFORM public.refresh_pre_reservation_status(v_pre_reservation_id);

  RETURN jsonb_build_object(
    'item_id', p_item_id,
    'verification_started_at', v_started_at,
    'assigned_operator_id', v_pr.assigned_operator_id
  );
END;
$$;

COMMENT ON FUNCTION public.start_item_verification(uuid) IS
  'Marks the first provider contact on a line. Idempotent; auto-assigns the caller when the pre-reservation has no operator. Operator/admin only.';

REVOKE ALL ON FUNCTION public.start_item_verification(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_item_verification(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- record_item_verification(p_item_id uuid, p_payload jsonb) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_item_verification(
  p_item_id uuid,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_actor uuid;
  v_pre_reservation_id uuid;
  v_pr public.pre_reservations%ROWTYPE;
  v_item public.pre_reservation_items%ROWTYPE;
  v_status_text text;
  v_new_status public.availability_status;
  v_contact_person text;
  v_method_text text;
  v_contact_method public.provider_contact_method;
  v_hold_text text;
  v_hold_expires_at timestamptz;
  v_alternative text;
  v_notes text;
  v_pr_status public.pre_reservation_status;
  v_expires_at timestamptz;
BEGIN
  v_org := public.require_availability_verifier();
  v_actor := auth.uid();

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
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
  INTO v_pr
  FROM public.pre_reservations pr
  WHERE pr.id = v_pre_reservation_id
    AND pr.organization_id = v_org
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_pr.status = 'cancelled' THEN
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

  -- Result status: available | unavailable | alternative_suggested (pending rejected)
  v_status_text := nullif(btrim(coalesce(p_payload ->> 'status', '')), '');
  IF v_status_text IS NULL
     OR v_status_text NOT IN ('available', 'unavailable', 'alternative_suggested')
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_new_status := v_status_text::public.availability_status;

  -- Contact person at the provider: mandatory, 1-120
  v_contact_person := nullif(btrim(coalesce(p_payload ->> 'contact_person', '')), '');
  IF v_contact_person IS NULL THEN
    RAISE EXCEPTION 'CONTACT_PERSON_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;
  IF char_length(v_contact_person) > 120 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Contact method: mandatory and valid
  v_method_text := nullif(btrim(coalesce(p_payload ->> 'contact_method', '')), '');
  IF v_method_text IS NULL
     OR v_method_text NOT IN ('phone', 'whatsapp', 'email', 'other')
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_contact_method := v_method_text::public.provider_contact_method;

  -- Provider hold: only with available, and it must be in the future
  v_hold_text := nullif(btrim(coalesce(p_payload ->> 'hold_expires_at', '')), '');
  IF v_hold_text IS NOT NULL THEN
    BEGIN
      v_hold_expires_at := v_hold_text::timestamptz;
    EXCEPTION
      WHEN invalid_text_representation OR datetime_field_overflow THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;
    IF v_new_status <> 'available' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF v_hold_expires_at <= now() THEN
      RAISE EXCEPTION 'HOLD_EXPIRY_IN_PAST' USING ERRCODE = 'raise_exception';
    END IF;
  ELSE
    v_hold_expires_at := NULL;
  END IF;

  -- Alternative suggestion: mandatory with alternative_suggested, cleared otherwise
  v_alternative := nullif(btrim(coalesce(p_payload ->> 'alternative_suggestion', '')), '');
  IF v_new_status = 'alternative_suggested' THEN
    IF v_alternative IS NULL THEN
      RAISE EXCEPTION 'ALTERNATIVE_SUGGESTION_REQUIRED' USING ERRCODE = 'raise_exception';
    END IF;
    IF char_length(v_alternative) > 1000 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
  ELSE
    v_alternative := NULL;
  END IF;

  -- Operator notes: optional, <= 2000
  v_notes := nullif(btrim(coalesce(p_payload ->> 'notes', '')), '');
  IF v_notes IS NOT NULL AND char_length(v_notes) > 2000 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.pre_reservation_items
  SET verification_status = v_new_status,
      verified_by = v_actor,
      verified_at = now(),
      verification_started_at = coalesce(verification_started_at, now()),
      provider_contact_person = v_contact_person,
      contact_method = v_contact_method,
      hold_expires_at = v_hold_expires_at,
      alternative_suggestion = v_alternative,
      operator_notes = v_notes
  WHERE id = p_item_id;

  -- First outcome auto-assigns the caller when nobody is assigned (research R-009).
  IF v_pr.assigned_operator_id IS NULL THEN
    UPDATE public.pre_reservations
    SET assigned_operator_id = v_actor
    WHERE id = v_pre_reservation_id;
    v_pr.assigned_operator_id := v_actor;
  END IF;

  PERFORM public.log_availability_event(
    v_org,
    v_pre_reservation_id,
    p_item_id,
    'outcome_recorded'::public.availability_event_kind,
    v_item.verification_status,
    v_new_status,
    jsonb_strip_nulls(jsonb_build_object(
      'provider_contact_person', v_contact_person,
      'contact_method', v_contact_method,
      'hold_expires_at', v_hold_expires_at,
      'notes', v_notes
    )),
    v_actor
  );

  PERFORM audit.log_event(
    v_org,
    'availability_recorded'::audit.audit_event_type,
    'success'::audit.audit_result,
    v_actor,
    'pre_reservation_item',
    p_item_id,
    jsonb_build_object(
      'item_id', p_item_id,
      'from', v_item.verification_status,
      'to', v_new_status,
      'has_hold', v_hold_expires_at IS NOT NULL
    )
  );

  v_pr_status := public.refresh_pre_reservation_status(v_pre_reservation_id);

  SELECT pr.expires_at
  INTO v_expires_at
  FROM public.pre_reservations pr
  WHERE pr.id = v_pre_reservation_id;

  RETURN jsonb_build_object(
    'item_id', p_item_id,
    'verification_status', v_new_status,
    'pre_reservation_status', v_pr_status,
    'expires_at', v_expires_at
  );
END;
$$;

COMMENT ON FUNCTION public.record_item_verification(uuid, jsonb) IS
  'Records one availability outcome for a line (available/unavailable/alternative_suggested), stamps verifier and contact data, then recomputes the global status. Operator/admin only.';

REVOKE ALL ON FUNCTION public.record_item_verification(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_item_verification(uuid, jsonb) TO authenticated;
