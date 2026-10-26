-- 053_us3_cancel_and_version.sql

CREATE OR REPLACE FUNCTION public.cancel_reservation(
  p_version_id uuid,
  p_reason text,
  p_contingency_report text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.reservation_versions%ROWTYPE;
  v_role text := auth.jwt() ->> 'app_role';
  v_reason text := btrim(coalesce(p_reason, ''));
  v_report text := nullif(btrim(coalesce(p_contingency_report, '')), '');
BEGIN
  v_org := public.require_tenant_member();

  SELECT v.* INTO v_row
  FROM public.reservation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_row.status = 'confirmed'::public.reservation_status THEN
    NULL;
  ELSIF v_row.status = 'in_progress'::public.reservation_status THEN
    IF v_role <> 'admin' THEN
      RAISE EXCEPTION 'ADMIN_REQUIRED' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF v_report IS NULL OR char_length(v_report) < 1 THEN
      RAISE EXCEPTION 'CONTINGENCY_REQUIRED' USING ERRCODE = 'raise_exception';
    END IF;
  ELSE
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.reservation_versions
  SET status = 'cancelled',
      cancelled_at = now(),
      cancel_reason = v_reason,
      contingency_report = CASE
        WHEN v_row.status = 'in_progress'::public.reservation_status THEN v_report
        ELSE contingency_report
      END,
      cancelled_by = auth.uid(),
      status_changed_at = now(),
      status_changed_by = auth.uid()
  WHERE id = p_version_id;

  UPDATE public.reservation_items
  SET ops_status = 'provider_failed'::public.reservation_item_ops_status
  WHERE version_id = p_version_id
    AND ops_status NOT IN (
      'completed'::public.reservation_item_ops_status,
      'provider_failed'::public.reservation_item_ops_status
    );

  PERFORM audit.log_event(
    v_org,
    'reservation_cancelled'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'reservation_version',
    p_version_id,
    jsonb_build_object('from', v_row.status::text)
  );

  RETURN jsonb_build_object('version_id', p_version_id, 'status', 'cancelled');
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_reservation(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_reservation(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_reservation_version(
  p_version_id uuid,
  p_items jsonb,
  p_passengers jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_old public.reservation_versions%ROWTYPE;
  v_new_id uuid;
  v_count int;
  v_expected int;
  v_i int;
  v_pax jsonb;
  v_item jsonb;
  v_pos int := 0;
  v_start date;
  v_end date;
BEGIN
  v_org := public.require_tenant_member();

  SELECT v.* INTO v_old
  FROM public.reservation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_old.status NOT IN (
    'confirmed'::public.reservation_status,
    'in_progress'::public.reservation_status
  ) THEN
    RAISE EXCEPTION 'RESERVATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  v_count := jsonb_array_length(p_passengers);
  IF v_count IS NULL OR jsonb_array_length(p_items) IS NULL
     OR jsonb_array_length(p_items) < 1 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.reservation_versions
  SET status = 'superseded'::public.reservation_status
  WHERE id = p_version_id;

  SELECT min((value ->> 'start_date')::date),
         max(coalesce((value ->> 'end_date')::date, (value ->> 'start_date')::date))
  INTO v_start, v_end
  FROM jsonb_array_elements(p_items);

  v_expected := v_count;

  INSERT INTO public.reservation_versions (
    organization_id, family_id, version_number, status, currency, total,
    travel_start_date, travel_end_date, party_adults, party_children,
    terms, assistance_phones, created_by, status_changed_at, status_changed_by
  ) VALUES (
    v_org, v_old.family_id, v_old.version_number + 1,
    CASE
      WHEN v_old.status = 'in_progress'::public.reservation_status THEN 'in_progress'::public.reservation_status
      ELSE 'confirmed'::public.reservation_status
    END,
    v_old.currency, v_old.total, v_start, v_end,
    v_old.party_adults, v_old.party_children,
    v_old.terms, v_old.assistance_phones, auth.uid(), now(), auth.uid()
  )
  RETURNING id INTO v_new_id;

  IF v_expected <> (v_old.party_adults + v_old.party_children) THEN
    RAISE EXCEPTION 'PASSENGER_COUNT_MISMATCH' USING ERRCODE = 'raise_exception';
  END IF;

  FOR v_i IN 0 .. v_count - 1 LOOP
    v_pax := p_passengers -> v_i;
    INSERT INTO public.reservation_passengers (
      organization_id, version_id, position, first_name, last_name,
      document_type, document_number, date_of_birth, special_requirements
    ) VALUES (
      v_org, v_new_id, v_i + 1,
      btrim(v_pax ->> 'first_name'),
      btrim(v_pax ->> 'last_name'),
      (v_pax ->> 'document_type')::public.id_document_type,
      btrim(v_pax ->> 'document_number'),
      nullif(v_pax ->> 'date_of_birth', '')::date,
      nullif(btrim(coalesce(v_pax ->> 'special_requirements', '')), '')
    );
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_pos := v_pos + 1;
    INSERT INTO public.reservation_items (
      organization_id, version_id, quotation_line_ref, pre_reservation_item_id,
      position, item_kind, item_label, product_id, addon_id, start_date, end_date,
      adults, children, quantity, line_total, provider_id, ops_status
    ) VALUES (
      v_org, v_new_id,
      nullif(v_item ->> 'quotation_line_ref', '')::uuid,
      nullif(v_item ->> 'pre_reservation_item_id', '')::uuid,
      v_pos,
      coalesce(v_item ->> 'item_kind', 'experience'),
      coalesce(v_item ->> 'item_label', 'Servicio'),
      nullif(v_item ->> 'product_id', '')::uuid,
      nullif(v_item ->> 'addon_id', '')::uuid,
      (v_item ->> 'start_date')::date,
      nullif(v_item ->> 'end_date', '')::date,
      coalesce((v_item ->> 'adults')::smallint, 1),
      coalesce((v_item ->> 'children')::smallint, 0),
      coalesce((v_item ->> 'quantity')::smallint, 1),
      coalesce((v_item ->> 'line_total')::numeric, 0),
      nullif(v_item ->> 'provider_id', '')::uuid,
      'pending_provider'::public.reservation_item_ops_status
    );
  END LOOP;

  PERFORM audit.log_event(
    v_org,
    'reservation_version_created'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'reservation_version',
    v_new_id,
    jsonb_build_object('from_version', p_version_id, 'version_number', v_old.version_number + 1)
  );

  RETURN jsonb_build_object('version_id', v_new_id, 'family_id', v_old.family_id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_reservation_version(uuid, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_reservation_version(uuid, jsonb, jsonb) TO authenticated;
