-- 057_fix_voucher_token_base64url.sql
-- Corrective migration (stabilization 2026-11-11, defect D2).
--
-- confirm_reservation (051) and rotate_reservation_voucher (054) generated the public voucher
-- token as standard base64 (alphabet with '+', '/' and '=' padding). A '/' splits the
-- /r/<token> route, so the raw link failed for most tokens. The quotation token (046) already
-- uses base64url and is NOT touched here.
--
-- Changes:
--   * new internal helper new_voucher_token(): 32 random bytes (same entropy as before),
--     base64url alphabet ('-', '_'), no padding. Same recipe as 046.
--   * confirm_reservation and rotate_reservation_voucher redefined to call it. Everything
--     else (signature, SECURITY DEFINER, search_path, validations, audit, comment, grants)
--     is copied unchanged from 051/054.
--
-- Compatibility: the database stores only encode(digest(token, 'sha256'), 'hex') and
-- get_public_voucher hashes whatever text it receives, so tokens issued before this
-- migration keep resolving. Old tokens containing '/' only work through a link that
-- percent-encodes the token (the panel builds links with encodeURIComponent).

CREATE OR REPLACE FUNCTION public.new_voucher_token()
RETURNS text
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT rtrim(
    translate(
      replace(encode(extensions.gen_random_bytes(32), 'base64'), E'\n', ''),
      '+/', '-_'
    ),
    '='
  );
$$;

COMMENT ON FUNCTION public.new_voucher_token() IS
  'Internal: 32 random bytes as base64url without padding (43 chars, [A-Za-z0-9_-]). Used for the public voucher token.';

REVOKE ALL ON FUNCTION public.new_voucher_token() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.new_voucher_token() FROM anon, authenticated;

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
  -- 057: base64url (RFC 4648 §5), 32 random bytes; only the SHA-256 hex is stored.
  v_token := public.new_voucher_token();

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

CREATE OR REPLACE FUNCTION public.rotate_reservation_voucher(
  p_family_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_token text;
BEGIN
  v_org := public.require_tenant_admin();
  -- 057: base64url (RFC 4648 §5), 32 random bytes; only the SHA-256 hex is stored.
  v_token := public.new_voucher_token();

  UPDATE public.reservation_families
  SET voucher_token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex')
  WHERE id = p_family_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN jsonb_build_object('family_id', p_family_id, 'voucher_token', v_token);
END;
$$;

REVOKE ALL ON FUNCTION public.rotate_reservation_voucher(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rotate_reservation_voucher(uuid) TO authenticated;
