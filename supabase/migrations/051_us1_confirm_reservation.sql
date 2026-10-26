-- 051_us1_confirm_reservation.sql
-- confirm_reservation and record_reservation_payment.

CREATE OR REPLACE FUNCTION public.reservation_insert_payment(
  p_org uuid,
  p_family_id uuid,
  p_deposit jsonb,
  p_currency text,
  p_actor uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_amount numeric;
  v_currency text;
  v_paid_on date;
  v_method text;
  v_ref text;
  v_path text;
  v_today date := (now() AT TIME ZONE 'America/Bogota')::date;
BEGIN
  v_amount := (p_deposit ->> 'amount')::numeric;
  v_currency := upper(btrim(coalesce(p_deposit ->> 'currency', '')));
  v_paid_on := (p_deposit ->> 'paid_on')::date;
  v_method := btrim(coalesce(p_deposit ->> 'method', ''));
  v_ref := btrim(coalesce(p_deposit ->> 'transfer_reference', ''));
  v_path := nullif(btrim(coalesce(p_deposit ->> 'receipt_path', '')), '');

  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'DEPOSIT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_currency IS DISTINCT FROM p_currency THEN
    RAISE EXCEPTION 'CURRENCY_MISMATCH' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_paid_on IS NULL OR v_paid_on > v_today THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_method NOT IN ('bank_transfer', 'cash', 'card_manual', 'other') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF char_length(v_ref) < 1 OR char_length(v_ref) > 80 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.reservation_payments (
    organization_id, family_id, amount, currency, paid_on, method,
    transfer_reference, receipt_path, recorded_by
  ) VALUES (
    p_org, p_family_id, v_amount, v_currency::char(3), v_paid_on,
    v_method::public.payment_method, v_ref, v_path, p_actor
  );

  PERFORM audit.log_event(
    p_org,
    'reservation_payment_recorded'::audit.audit_event_type,
    'success'::audit.audit_result,
    p_actor,
    'reservation_family',
    p_family_id,
    jsonb_build_object('amount', v_amount, 'currency', v_currency)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reservation_insert_payment(uuid, uuid, jsonb, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reservation_insert_payment(uuid, uuid, jsonb, text, uuid)
  FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.confirm_reservation(
  p_quotation_version_id uuid,
  p_deposit jsonb,
  p_passengers jsonb,
  p_assistance_phones text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_actor uuid := auth.uid();
  v_snap jsonb;
  v_family_id uuid;
  v_version_id uuid;
  v_reference text;
  v_token text;
  v_phones text;
  v_expected int;
  v_count int;
  v_start date;
  v_end date;
  v_pax jsonb;
  v_i int;
  v_line jsonb;
  v_pos int := 0;
  v_provider uuid;
BEGIN
  v_org := public.require_tenant_member();

  IF p_quotation_version_id IS NULL OR p_deposit IS NULL OR p_passengers IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.reservation_families f
    WHERE f.quotation_version_id = p_quotation_version_id
      AND f.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'RESERVATION_ALREADY_EXISTS' USING ERRCODE = 'raise_exception';
  END IF;

  v_snap := public.assert_quotation_confirmable(v_org, p_quotation_version_id);

  v_expected := coalesce((v_snap ->> 'party_adults')::int, 0)
             + coalesce((v_snap ->> 'party_children')::int, 0);
  v_count := jsonb_array_length(p_passengers);
  IF v_count IS NULL OR v_count <> v_expected OR v_expected < 1 THEN
    RAISE EXCEPTION 'PASSENGER_COUNT_MISMATCH' USING ERRCODE = 'raise_exception';
  END IF;

  v_phones := btrim(coalesce(p_assistance_phones, ''));
  IF char_length(v_phones) > 200 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT min(l.start_date), max(coalesce(l.end_date, l.start_date))
  INTO v_start, v_end
  FROM public.quotation_lines l
  WHERE l.version_id = p_quotation_version_id AND l.organization_id = v_org;

  v_reference := 'RSV-' || lpad(
    public.next_organization_sequence(v_org, 'reservation')::text, 5, '0'
  );
  v_token := replace(encode(extensions.gen_random_bytes(32), 'base64'), E'\n', '');

  INSERT INTO public.reservation_families (
    organization_id, reference, quotation_version_id, quotation_family_id,
    pre_reservation_id, customer_id, voucher_token_hash, created_by
  ) VALUES (
    v_org,
    v_reference,
    p_quotation_version_id,
    (v_snap ->> 'family_id')::uuid,
    (v_snap ->> 'pre_reservation_id')::uuid,
    (v_snap ->> 'customer_id')::uuid,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    v_actor
  )
  RETURNING id INTO v_family_id;

  INSERT INTO public.reservation_versions (
    organization_id, family_id, version_number, status, currency, total,
    travel_start_date, travel_end_date, party_adults, party_children,
    terms, assistance_phones, created_by, status_changed_at, status_changed_by
  )
  SELECT
    v_org, v_family_id, 1, 'confirmed',
    (v_snap ->> 'currency')::char(3),
    (v_snap ->> 'total')::numeric,
    v_start, v_end,
    (v_snap ->> 'party_adults')::smallint,
    (v_snap ->> 'party_children')::smallint,
    coalesce(qv.terms, ''),
    v_phones,
    v_actor, now(), v_actor
  FROM public.quotation_versions qv
  WHERE qv.id = p_quotation_version_id
  RETURNING id INTO v_version_id;

  FOR v_i IN 0 .. v_count - 1 LOOP
    v_pax := p_passengers -> v_i;
    IF btrim(coalesce(v_pax ->> 'first_name', '')) = ''
       OR btrim(coalesce(v_pax ->> 'last_name', '')) = ''
       OR btrim(coalesce(v_pax ->> 'document_number', '')) = ''
       OR coalesce(v_pax ->> 'document_type', '') NOT IN ('cc', 'ce', 'passport', 'ti', 'other')
    THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    INSERT INTO public.reservation_passengers (
      organization_id, version_id, position, first_name, last_name,
      document_type, document_number, date_of_birth, special_requirements
    ) VALUES (
      v_org, v_version_id, v_i + 1,
      btrim(v_pax ->> 'first_name'),
      btrim(v_pax ->> 'last_name'),
      (v_pax ->> 'document_type')::public.id_document_type,
      btrim(v_pax ->> 'document_number'),
      nullif(v_pax ->> 'date_of_birth', '')::date,
      nullif(btrim(coalesce(v_pax ->> 'special_requirements', '')), '')
    );
  END LOOP;

  FOR v_line IN
    SELECT value FROM jsonb_array_elements(v_snap -> 'lines')
  LOOP
    v_pos := v_pos + 1;
    v_provider := NULL;
    IF (v_line ->> 'pre_reservation_item_id') IS NOT NULL THEN
      SELECT pri.provider_id INTO v_provider
      FROM public.pre_reservation_items pri
      WHERE pri.id = (v_line ->> 'pre_reservation_item_id')::uuid
        AND pri.organization_id = v_org;
    END IF;

    INSERT INTO public.reservation_items (
      organization_id, version_id, quotation_line_ref, pre_reservation_item_id,
      position, item_kind, item_label, product_id, addon_id, start_date, end_date,
      adults, children, quantity, line_total, provider_id
    )
    SELECT
      v_org, v_version_id, ql.id,
      (v_line ->> 'pre_reservation_item_id')::uuid,
      v_pos,
      ql.item_kind,
      ql.item_label,
      ql.product_id,
      ql.addon_id,
      ql.start_date,
      ql.end_date,
      ql.adults,
      ql.children,
      ql.quantity,
      ql.line_total,
      v_provider
    FROM public.quotation_lines ql
    WHERE ql.version_id = p_quotation_version_id
      AND ql.pre_reservation_item_id = (v_line ->> 'pre_reservation_item_id')::uuid
    LIMIT 1;
  END LOOP;

  PERFORM public.reservation_insert_payment(
    v_org, v_family_id, p_deposit, v_snap ->> 'currency', v_actor
  );

  PERFORM audit.log_event(
    v_org,
    'reservation_confirmed'::audit.audit_event_type,
    'success'::audit.audit_result,
    v_actor,
    'reservation_family',
    v_family_id,
    jsonb_build_object(
      'reference', v_reference,
      'currency', v_snap ->> 'currency',
      'total', (v_snap ->> 'total')::numeric
    )
  );

  RETURN jsonb_build_object(
    'family_id', v_family_id,
    'version_id', v_version_id,
    'reference', v_reference,
    'voucher_token', v_token,
    'total', (v_snap ->> 'total')::numeric,
    'currency', v_snap ->> 'currency'
  );
END;
$$;

COMMENT ON FUNCTION public.confirm_reservation(uuid, jsonb, jsonb, text) IS
  'Creates a reservation from an accepted quotation. Returns the voucher token once.';

REVOKE ALL ON FUNCTION public.confirm_reservation(uuid, jsonb, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_reservation(uuid, jsonb, jsonb, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_reservation_payment(
  p_family_id uuid,
  p_payment jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_currency char(3);
BEGIN
  v_org := public.require_tenant_member();
  IF p_family_id IS NULL OR p_payment IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.currency INTO v_currency
  FROM public.reservation_versions v
  JOIN public.reservation_families f ON f.id = v.family_id
  WHERE f.id = p_family_id
    AND f.organization_id = v_org
    AND v.status <> 'superseded'::public.reservation_status;

  IF v_currency IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  PERFORM public.reservation_insert_payment(
    v_org, p_family_id, p_payment, v_currency::text, auth.uid()
  );

  RETURN jsonb_build_object('family_id', p_family_id);
END;
$$;

REVOKE ALL ON FUNCTION public.record_reservation_payment(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_reservation_payment(uuid, jsonb) TO authenticated;
