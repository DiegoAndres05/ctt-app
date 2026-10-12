-- 037_pre_reservation_core.sql
-- Internal core functions for pre-reservations.
-- Source of truth: specs/004-prereservation-availability/data-model.md (§Functions Núcleo),
-- specs/004-prereservation-availability/research.md (R-002, R-003, R-005, R-006).
--
-- All functions are SECURITY DEFINER, SET search_path = '', REVOKE ALL FROM PUBLIC/anon/authenticated.
-- They are called by public RPCs in later migrations (038, 039, 040) and by seed/tests.

-- ---------------------------------------------------------------------------
-- require_availability_verifier() → uuid (internal, wraps require_catalog_manager)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.require_availability_verifier()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.require_catalog_manager();
END;
$$;

COMMENT ON FUNCTION public.require_availability_verifier() IS
  'Returns the caller tenant id when the JWT and live profile are an active operator or admin. Delegates to require_catalog_manager.';

REVOKE ALL ON FUNCTION public.require_availability_verifier() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.require_availability_verifier() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- resolve_pre_reservation_item(p_org uuid, p_request_id uuid, p_item jsonb) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resolve_pre_reservation_item(
  p_org uuid,
  p_request_id uuid,
  p_item jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item jsonb := p_item;
  v_product_id uuid;
  v_addon_id uuid;
  v_start_date date;
  v_end_date date;
  v_adults integer;
  v_children integer;
  v_quantity integer;
  v_source_request_item_id uuid;
  v_provider_name text;
  v_provider_phone text;
  v_provider_email text;
  v_item_kind text;
  v_item_label text;
  v_provider_id uuid;
  v_product public.products%ROWTYPE;
  v_addon public.add_ons%ROWTYPE;
  v_today date;
BEGIN
  IF p_org IS NULL OR p_request_id IS NULL OR v_item IS NULL OR jsonb_typeof(v_item) <> 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- XOR product_id / addon_id
  IF (v_item ? 'product_id' AND v_item ? 'addon_id')
     OR NOT (v_item ? 'product_id' OR v_item ? 'addon_id')
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_item ? 'product_id' AND v_item ->> 'product_id' <> '' THEN
    v_product_id := (v_item ->> 'product_id')::uuid;
    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_product_id AND organization_id = p_org;
    IF NOT FOUND OR v_product.status <> 'active' THEN
      RAISE EXCEPTION 'ITEM_NOT_BOOKABLE' USING ERRCODE = 'raise_exception';
    END IF;
    v_item_kind := v_product.type;
    v_item_label := v_product.name;
    v_provider_id := v_product.provider_id;
  ELSE
    v_addon_id := (v_item ->> 'addon_id')::uuid;
    SELECT * INTO v_addon
    FROM public.add_ons
    WHERE id = v_addon_id AND organization_id = p_org;
    IF NOT FOUND OR v_addon.is_active <> true THEN
      RAISE EXCEPTION 'ITEM_NOT_BOOKABLE' USING ERRCODE = 'raise_exception';
    END IF;
    v_item_kind := 'addon';
    v_item_label := v_addon.name;
    v_provider_id := NULL;
  END IF;

  -- Dates
  BEGIN
    v_start_date := (v_item ->> 'start_date')::date;
    IF v_item ? 'end_date' AND v_item ->> 'end_date' <> '' THEN
      v_end_date := (v_item ->> 'end_date')::date;
    ELSE
      v_end_date := NULL;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  v_today := (now() AT TIME ZONE 'America/Bogota')::date;
  IF v_start_date < v_today THEN
    RAISE EXCEPTION 'TRAVEL_DATE_IN_PAST' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_end_date IS NOT NULL AND v_end_date < v_start_date THEN
    RAISE EXCEPTION 'INVALID_DATE_RANGE' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_item_kind = 'accommodation' AND (v_end_date IS NULL OR v_end_date <= v_start_date) THEN
    RAISE EXCEPTION 'INVALID_DATE_RANGE' USING ERRCODE = 'raise_exception';
  END IF;

  -- Passengers
  BEGIN
    v_adults := COALESCE(NULLIF(v_item ->> 'adults', '')::integer, 1);
    v_children := COALESCE(NULLIF(v_item ->> 'children', '')::integer, 0);
    v_quantity := COALESCE(NULLIF(v_item ->> 'quantity', '')::integer, 1);
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;
  IF v_adults < 1 OR v_adults > 99
     OR v_children < 0 OR v_children > 99
     OR v_quantity < 1 OR v_quantity > 99
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- source_request_item_id
  IF v_item ? 'source_request_item_id' AND v_item ->> 'source_request_item_id' <> '' THEN
    v_source_request_item_id := (v_item ->> 'source_request_item_id')::uuid;
    IF NOT EXISTS (
      SELECT 1 FROM public.customer_request_items
      WHERE id = v_source_request_item_id
        AND request_id = p_request_id
    ) THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
  ELSE
    v_source_request_item_id := NULL;
  END IF;

  -- Provider snapshot or manual fields
  IF v_provider_id IS NOT NULL THEN
    SELECT name, contact_phone, contact_email
    INTO v_provider_name, v_provider_phone, v_provider_email
    FROM public.providers
    WHERE id = v_provider_id AND organization_id = p_org AND is_active = true;
    IF NOT FOUND THEN
      v_provider_id := NULL;
      v_provider_name := NULL;
      v_provider_phone := NULL;
      v_provider_email := NULL;
    END IF;
  ELSE
    v_provider_name := nullif(btrim(coalesce(v_item ->> 'provider_name', '')), '');
    v_provider_phone := nullif(btrim(coalesce(v_item ->> 'provider_phone', '')), '');
    v_provider_email := nullif(btrim(coalesce(v_item ->> 'provider_email', '')), '');
    IF v_provider_name IS NOT NULL AND char_length(v_provider_name) > 255 THEN
      v_provider_name := left(v_provider_name, 255);
    END IF;
    IF v_provider_phone IS NOT NULL AND char_length(v_provider_phone) > 40 THEN
      v_provider_phone := left(v_provider_phone, 40);
    END IF;
    IF v_provider_email IS NOT NULL AND char_length(v_provider_email) > 254 THEN
      v_provider_email := left(v_provider_email, 254);
    END IF;
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'item_kind', v_item_kind,
    'item_label', v_item_label,
    'product_id', v_product_id,
    'addon_id', v_addon_id,
    'source_request_item_id', v_source_request_item_id,
    'start_date', v_start_date,
    'end_date', v_end_date,
    'adults', v_adults,
    'children', v_children,
    'quantity', v_quantity,
    'provider_id', v_provider_id,
    'provider_name', v_provider_name,
    'provider_phone', v_provider_phone,
    'provider_email', v_provider_email
  ));
END;
$$;

COMMENT ON FUNCTION public.resolve_pre_reservation_item(uuid, uuid, jsonb) IS
  'Validates and normalizes a pre-reservation item payload. Returns normalized item with item_kind, item_label, and provider snapshot.';

REVOKE ALL ON FUNCTION public.resolve_pre_reservation_item(uuid, uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_pre_reservation_item(uuid, uuid, jsonb) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- log_availability_event(...) → bigint (internal)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.log_availability_event(
  p_org uuid,
  p_pre_reservation_id uuid,
  p_item_id uuid,
  p_kind public.availability_event_kind,
  p_from public.availability_status,
  p_to public.availability_status,
  p_details jsonb,
  p_actor uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event_id bigint;
BEGIN
  INSERT INTO public.availability_verification_events (
    organization_id, pre_reservation_id, item_id,
    event_kind, from_status, to_status,
    provider_contact_person, contact_method, hold_expires_at, notes, metadata,
    actor_id
  ) VALUES (
    p_org, p_pre_reservation_id, p_item_id,
    p_kind, p_from, p_to,
    p_details ->> 'provider_contact_person',
    COALESCE(NULLIF(p_details ->> 'contact_method', ''), NULL)::public.provider_contact_method,
    CASE WHEN p_details ? 'hold_expires_at' AND p_details ->> 'hold_expires_at' <> ''
         THEN (p_details ->> 'hold_expires_at')::timestamptz END,
    p_details ->> 'notes',
    COALESCE(p_details -> 'metadata', '{}'::jsonb),
    p_actor
  ) RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

COMMENT ON FUNCTION public.log_availability_event(uuid, uuid, uuid, availability_event_kind, availability_status, availability_status, jsonb, uuid) IS
  'Inserts an availability verification event. p_details may contain provider_contact_person, contact_method, hold_expires_at, notes, metadata.';

REVOKE ALL ON FUNCTION public.log_availability_event(uuid, uuid, uuid, availability_event_kind, availability_status, availability_status, jsonb, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.log_availability_event(uuid, uuid, uuid, availability_event_kind, availability_status, availability_status, jsonb, uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- insert_pre_reservation_item(p_org, p_pre_reservation_id, p_resolved jsonb, p_alternative_of uuid, p_actor uuid) → uuid
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.insert_pre_reservation_item(
  p_org uuid,
  p_pre_reservation_id uuid,
  p_resolved jsonb,
  p_alternative_of uuid,
  p_actor uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item_id uuid;
  v_position smallint;
  v_count integer;
  v_main_item uuid;
BEGIN
  -- Position = max + 1
  SELECT COALESCE(max(position), -1) + 1 INTO v_position
  FROM public.pre_reservation_items
  WHERE pre_reservation_id = p_pre_reservation_id;

  -- Validate alternative_of
  IF p_alternative_of IS NOT NULL THEN
    SELECT id INTO v_main_item
    FROM public.pre_reservation_items
    WHERE id = p_alternative_of
      AND organization_id = p_org
      AND pre_reservation_id = p_pre_reservation_id
      AND alternative_of_item_id IS NULL
      AND withdrawn_at IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  -- Insert the item
  INSERT INTO public.pre_reservation_items (
    organization_id, pre_reservation_id, position,
    alternative_of_item_id, item_kind, product_id, addon_id,
    source_request_item_id, item_label,
    start_date, end_date, adults, children, quantity,
    provider_id, provider_name, provider_phone, provider_email,
    verification_status, created_by
  ) VALUES (
    p_org, p_pre_reservation_id, v_position,
    p_alternative_of,
    (p_resolved ->> 'item_kind')::text,
    NULLIF(p_resolved ->> 'product_id', '')::uuid,
    NULLIF(p_resolved ->> 'addon_id', '')::uuid,
    NULLIF(p_resolved ->> 'source_request_item_id', '')::uuid,
    p_resolved ->> 'item_label',
    (p_resolved ->> 'start_date')::date,
    NULLIF(p_resolved ->> 'end_date', '')::date,
    (p_resolved ->> 'adults')::smallint,
    (p_resolved ->> 'children')::smallint,
    (p_resolved ->> 'quantity')::smallint,
    NULLIF(p_resolved ->> 'provider_id', '')::uuid,
    p_resolved ->> 'provider_name',
    p_resolved ->> 'provider_phone',
    p_resolved ->> 'provider_email',
    'pending'::public.availability_status,
    p_actor
  ) RETURNING id INTO v_item_id;

  -- Check line count (including withdrawn)
  SELECT count(*) INTO v_count
  FROM public.pre_reservation_items
  WHERE pre_reservation_id = p_pre_reservation_id;
  IF v_count > 30 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Log event
  PERFORM public.log_availability_event(
    p_org, p_pre_reservation_id, v_item_id,
    'item_added'::public.availability_event_kind,
    NULL, 'pending'::public.availability_status,
    jsonb_build_object(),
    p_actor
  );

  RETURN v_item_id;
END;
$$;

COMMENT ON FUNCTION public.insert_pre_reservation_item(uuid, uuid, jsonb, uuid, uuid) IS
  'Inserts a pre-reservation item, assigns position, validates alternative_of and line limit, logs item_added event.';

REVOKE ALL ON FUNCTION public.insert_pre_reservation_item(uuid, uuid, jsonb, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.insert_pre_reservation_item(uuid, uuid, jsonb, uuid, uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- refresh_pre_reservation_status(p_pre_reservation_id uuid) → pre_reservation_status (internal)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.refresh_pre_reservation_status(
  p_pre_reservation_id uuid
)
RETURNS public.pre_reservation_status
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.pre_reservations%ROWTYPE;
  v_new_status public.pre_reservation_status;
  v_old_status public.pre_reservation_status;
  v_expires_at timestamptz;
  v_verified_at timestamptz;
  v_first_verified_at timestamptz;
  v_min_hold timestamptz;
  v_main_available_count integer;
  v_main_unavailable_count integer;
  v_main_alternative_count integer;
  v_main_pending_count integer;
  v_main_total integer;
BEGIN
  -- Get the pre-reservation with FOR UPDATE to serialize
  SELECT * INTO v_row
  FROM public.pre_reservations
  WHERE id = p_pre_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_org := v_row.organization_id;
  v_old_status := v_row.status;

  -- Cancelled is terminal, don't recalculate
  IF v_old_status = 'cancelled' THEN
    RETURN v_old_status;
  END IF;

  -- Count main (non-alternative, non-withdrawn) lines by status
  SELECT
    count(*) FILTER (WHERE verification_status = 'available') AS available_count,
    count(*) FILTER (WHERE verification_status = 'unavailable') AS unavailable_count,
    count(*) FILTER (WHERE verification_status = 'alternative_suggested') AS alternative_count,
    count(*) FILTER (WHERE verification_status = 'pending') AS pending_count,
    count(*) AS total,
    min(hold_expires_at) FILTER (WHERE verification_status = 'available' AND hold_expires_at IS NOT NULL) AS min_hold
  INTO v_main_available_count, v_main_unavailable_count, v_main_alternative_count, v_main_pending_count, v_main_total, v_min_hold
  FROM public.pre_reservation_items
  WHERE pre_reservation_id = p_pre_reservation_id
    AND alternative_of_item_id IS NULL
    AND withdrawn_at IS NULL;

  -- Recompute status per precedence (R-003)
  IF v_main_unavailable_count > 0 OR v_main_alternative_count > 0 THEN
    v_new_status := 'requires_adjustment';
  ELSIF v_main_total = 0 THEN
    -- Should not happen (PRE_RESERVATION_REQUIRES_ITEMS enforced on withdraw), but handle gracefully
    v_new_status := 'pending_verification';
  ELSIF v_main_available_count = v_main_total THEN
    v_new_status := 'verified';
  ELSIF v_main_available_count > 0 THEN
    v_new_status := 'partially_verified';
  ELSE
    v_new_status := 'pending_verification';
  END IF;

  -- Check expiration (available lines with hold_expires_at <= now)
  IF v_min_hold IS NOT NULL AND v_min_hold <= now() THEN
    v_new_status := 'expired';
  END IF;

  -- Prepare verified_at / first_verified_at
  IF v_new_status = 'verified' AND v_old_status <> 'verified' THEN
    v_verified_at := now();
    v_first_verified_at := COALESCE(v_row.first_verified_at, now());
  ELSIF v_new_status = 'verified' THEN
    -- Stays verified: keep the entry timestamp (data-model §1).
    v_verified_at := v_row.verified_at;
    v_first_verified_at := v_row.first_verified_at;
  ELSE
    v_verified_at := NULL;
    v_first_verified_at := v_row.first_verified_at;
  END IF;

  -- Prepare expires_at
  IF v_new_status = 'verified' OR v_new_status = 'partially_verified' THEN
    v_expires_at := v_min_hold;
  ELSE
    v_expires_at := NULL;
  END IF;

  -- Update if changed
  IF v_new_status IS DISTINCT FROM v_old_status
     OR v_expires_at IS DISTINCT FROM v_row.expires_at
     OR v_verified_at IS DISTINCT FROM v_row.verified_at
     OR v_first_verified_at IS DISTINCT FROM v_row.first_verified_at
  THEN
    UPDATE public.pre_reservations
    SET status = v_new_status,
        expires_at = v_expires_at,
        verified_at = v_verified_at,
        first_verified_at = v_first_verified_at
    WHERE id = p_pre_reservation_id;

    -- Emit the status change audit (data-model §Functions: pre_reservation_status_changed)
    PERFORM audit.log_event(
      v_org,
      'pre_reservation_status_changed'::audit.audit_event_type,
      'success'::audit.audit_result,
      auth.uid(),
      'pre_reservation',
      p_pre_reservation_id,
      jsonb_build_object('from', v_old_status, 'to', v_new_status)
    );
  END IF;

  RETURN v_new_status;
END;
$$;

COMMENT ON FUNCTION public.refresh_pre_reservation_status(uuid) IS
  'Recalculates and persists the global pre-reservation status from main active lines. Precedence: expired > requires_adjustment > verified > partially_verified > pending_verification. Persists expires_at, verified_at, first_verified_at. Emits pre_reservation_status_changed event if status changes. Does nothing for cancelled.';

REVOKE ALL ON FUNCTION public.refresh_pre_reservation_status(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.refresh_pre_reservation_status(uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- create_pre_reservation_core(p_org uuid, p_request_id uuid, p_payload jsonb, p_actor uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_pre_reservation_core(
  p_org uuid,
  p_request_id uuid,
  p_payload jsonb,
  p_actor uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_request public.customer_requests%ROWTYPE;
  v_customer public.customers%ROWTYPE;
  v_items jsonb;
  v_main_count integer := 0;
  v_total_count integer := 0;
  v_reference text;
  v_pre_reservation_id uuid;
  v_assigned_operator_id uuid;
  v_resolved jsonb;
  v_alternative_of uuid;
  v_item_id uuid;
  v_item_index integer := 0;
  v_item jsonb;
  v_request_status text;
BEGIN
  -- Validate payload
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_items := p_payload -> 'items';
  IF v_items IS NULL OR jsonb_typeof(v_items) <> 'array' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_assigned_operator_id := NULLIF(p_payload ->> 'assigned_operator_id', '')::uuid;

  -- Lock the request FOR UPDATE
  SELECT * INTO v_request
  FROM public.customer_requests
  WHERE id = p_request_id AND organization_id = p_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Validate request status
  IF v_request.status = 'discarded' THEN
    RAISE EXCEPTION 'REQUEST_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;

  -- Validate customer not anonymized
  SELECT * INTO v_customer
  FROM public.customers
  WHERE id = v_request.customer_id AND organization_id = p_org;

  IF v_customer.is_anonymized THEN
    RAISE EXCEPTION 'CUSTOMER_ANONYMIZED' USING ERRCODE = 'raise_exception';
  END IF;

  -- Validate assigned_operator_id if provided
  IF v_assigned_operator_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.user_profiles
      WHERE id = v_assigned_operator_id
        AND organization_id = p_org
        AND status = 'active'
        AND role IN ('operator', 'admin')
    ) THEN
      RAISE EXCEPTION 'ASSIGNEE_NOT_OPERATOR' USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  -- Validate items: at least one main, max 30 total
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    v_total_count := v_total_count + 1;
    IF v_total_count > 30 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF NOT (v_item ? 'alternative_of') OR (v_item ->> 'alternative_of') = '' THEN
      v_main_count := v_main_count + 1;
    END IF;
  END LOOP;

  IF v_main_count < 1 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Generate reference
  v_reference := 'PRE-' || lpad(public.next_organization_sequence(p_org, 'pre_reservation')::text, 5, '0');

  -- Insert pre_reservation header
  INSERT INTO public.pre_reservations (
    organization_id, reference, request_id, customer_id,
    responsible_agent_id, assigned_operator_id,
    status, created_by
  ) VALUES (
    p_org, v_reference, p_request_id, v_request.customer_id,
    p_actor, v_assigned_operator_id,
    'pending_verification'::public.pre_reservation_status,
    p_actor
  ) RETURNING id INTO v_pre_reservation_id;

  -- Insert lines
  v_item_index := 0;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    -- Resolve the item
    v_resolved := public.resolve_pre_reservation_item(p_org, p_request_id, v_item);

    -- Determine alternative_of (index in array)
    v_alternative_of := NULL;
    IF v_item ? 'alternative_of' AND v_item ->> 'alternative_of' <> '' THEN
      -- The alternative_of in payload is 0-based index of a main item in the same array
      -- We need to find the actual UUID of that main item
      -- Since we insert in order, we can track main items as we go
      DECLARE
        v_main_index integer := (v_item ->> 'alternative_of')::integer;
        v_target_id uuid;
      BEGIN
        -- This requires knowing the UUID of the main item at that index
        -- We'll handle this by first inserting all items, then updating alternatives
        -- For now, we defer alternative linking to a second pass
        -- Actually, we need a different approach: insert all first, then update
      END;
    END IF;

    -- Insert the item (alternative_of will be set in second pass)
    v_item_id := public.insert_pre_reservation_item(
      p_org, v_pre_reservation_id, v_resolved, NULL, p_actor
    );
    v_item_index := v_item_index + 1;
  END LOOP;

  -- Now handle alternative_of references (second pass)
  v_item_index := 0;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    IF v_item ? 'alternative_of' AND v_item ->> 'alternative_of' <> '' THEN
      DECLARE
        v_main_index integer := (v_item ->> 'alternative_of')::integer;
        v_main_id uuid;
      BEGIN
        SELECT id INTO v_main_id
        FROM public.pre_reservation_items
        WHERE pre_reservation_id = v_pre_reservation_id
          AND alternative_of_item_id IS NULL
          AND position = v_main_index;
        IF FOUND THEN
          UPDATE public.pre_reservation_items
          SET alternative_of_item_id = v_main_id
          WHERE id = (
            SELECT id FROM public.pre_reservation_items
            WHERE pre_reservation_id = v_pre_reservation_id
            ORDER BY position
            LIMIT 1 OFFSET v_item_index
          );
        ELSE
          RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
        END IF;
      END;
    END IF;
    v_item_index := v_item_index + 1;
  END LOOP;

  -- Update request status if first conversion
  IF v_request.status IN ('received', 'in_review') THEN
    v_request_status := v_request.status;
    UPDATE public.customer_requests
    SET status = 'pre_reservation'::public.request_status,
        closed_at = now(),
        first_handled_at = COALESCE(first_handled_at, now())
    WHERE id = p_request_id;

    PERFORM audit.log_event(
      p_org,
      'request_status_changed'::audit.audit_event_type,
      'success'::audit.audit_result,
      p_actor,
      'customer_request',
      p_request_id,
      jsonb_build_object('from', v_request_status, 'to', 'pre_reservation', 'pre_reservation_id', v_pre_reservation_id)
    );
  END IF;

  -- Log pre_reservation_created audit
  PERFORM audit.log_event(
    p_org,
    'pre_reservation_created'::audit.audit_event_type,
    'success'::audit.audit_result,
    p_actor,
    'pre_reservation',
    v_pre_reservation_id,
    jsonb_build_object('request_id', p_request_id, 'item_count', v_total_count)
  );

  -- Refresh status (sets verified_at/first_verified_at/expires_at if applicable)
  PERFORM public.refresh_pre_reservation_status(v_pre_reservation_id);

  -- Return result
  SELECT status INTO v_request_status
  FROM public.pre_reservations WHERE id = v_pre_reservation_id;

  SELECT cr.status INTO v_request_status
  FROM public.customer_requests cr WHERE cr.id = p_request_id;

  RETURN jsonb_build_object(
    'pre_reservation_id', v_pre_reservation_id,
    'reference', v_reference,
    'status', (SELECT status FROM public.pre_reservations WHERE id = v_pre_reservation_id),
    'request_status', v_request_status
  );
END;
$$;

COMMENT ON FUNCTION public.create_pre_reservation_core(uuid, uuid, jsonb, uuid) IS
  'Internal core: creates pre-reservation and lines atomically. Converts request to pre_reservation if received/in_review. Emits audits and events.';

REVOKE ALL ON FUNCTION public.create_pre_reservation_core(uuid, uuid, jsonb, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_pre_reservation_core(uuid, uuid, jsonb, uuid) FROM anon, authenticated;