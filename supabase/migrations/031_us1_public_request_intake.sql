-- 031_us1_public_request_intake.sql
-- Anonymous web intake. The external site calls this with the anon key.
-- Source of truth: specs/003-customer-requests-channels/contracts/api-contracts.md (§1),
-- specs/003-customer-requests-channels/research.md (R-001, R-002, R-003).
--
-- ERROR CONTRACT: the exception message is the API code. Do not reword it.
-- The function never writes products, listings, or tariffs. It only reads them
-- to resolve a public_slug, then delegates to capture_request_core.

CREATE OR REPLACE FUNCTION public.submit_public_request(
  p_organization_id uuid,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org_status public.organization_status;
  v_contact jsonb;
  v_first text;
  v_email text;
  v_phone text;
  v_items jsonb := '[]'::jsonb;
  v_raw_items jsonb;
  v_item jsonb;
  v_slug text;
  v_product_id uuid;
  v_qty integer;
  v_interest text;
  v_special text;
  v_idem uuid;
  v_existing_reference text;
  v_recent bigint;
  v_org_recent bigint;
  v_result jsonb;
  v_request jsonb;
BEGIN
  IF p_payload IS NULL OR octet_length(p_payload::text) > 16384 OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT o.status
  INTO v_org_status
  FROM public.organizations o
  WHERE o.id = p_organization_id;

  IF v_org_status IS NULL OR v_org_status <> 'active' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF nullif(btrim(coalesce(p_payload ->> 'website', '')), '') IS NOT NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_payload -> 'privacy_consent' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'CONSENT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  v_contact := p_payload -> 'contact';
  IF v_contact IS NULL OR jsonb_typeof(v_contact) <> 'object' THEN
    RAISE EXCEPTION 'CONTACT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  v_first := btrim(coalesce(v_contact ->> 'first_name', ''));
  IF v_first = ''
     OR (
       nullif(btrim(coalesce(v_contact ->> 'email', '')), '') IS NULL
       AND nullif(btrim(coalesce(v_contact ->> 'phone', '')), '') IS NULL
     )
  THEN
    RAISE EXCEPTION 'CONTACT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  v_email := public.normalize_email(v_contact ->> 'email');
  v_phone := public.normalize_phone_e164(
    v_contact ->> 'phone',
    public.organization_phone_country_code(p_organization_id)
  );

  IF v_email IS NULL AND v_phone IS NULL THEN
    RAISE EXCEPTION 'CONTACT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  v_raw_items := p_payload -> 'items';
  IF v_raw_items IS NOT NULL AND jsonb_typeof(v_raw_items) <> 'null' THEN
    IF jsonb_typeof(v_raw_items) <> 'array' OR jsonb_array_length(v_raw_items) > 10 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    FOR v_item IN
      SELECT value FROM jsonb_array_elements(v_raw_items)
    LOOP
      IF jsonb_typeof(v_item) <> 'object' THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END IF;

      v_slug := lower(btrim(coalesce(v_item ->> 'public_slug', '')));
      IF v_slug = '' THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END IF;

      BEGIN
        IF v_item ? 'quantity' AND jsonb_typeof(v_item -> 'quantity') = 'number' THEN
          v_qty := (v_item ->> 'quantity')::integer;
        ELSE
          v_qty := 1;
        END IF;
      EXCEPTION
        WHEN invalid_text_representation OR numeric_value_out_of_range THEN
          RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END;

      IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END IF;

      SELECT pl.product_id
      INTO v_product_id
      FROM public.public_listings pl
      JOIN public.products p
        ON p.id = pl.product_id
       AND p.organization_id = pl.organization_id
      WHERE pl.organization_id = p_organization_id
        AND pl.public_slug = v_slug
        AND pl.status = 'published'
        AND pl.sold_out = false
        AND p.status = 'active';

      IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'LISTING_NOT_AVAILABLE' USING ERRCODE = 'raise_exception';
      END IF;

      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'product_id', v_product_id,
        'public_slug', v_slug,
        'quantity', v_qty
      ));
    END LOOP;
  END IF;

  v_interest := nullif(btrim(coalesce(p_payload ->> 'interest_text', '')), '');
  IF v_interest IS NOT NULL THEN
    IF char_length(v_interest) > 500 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'free_text', v_interest,
      'quantity', 1
    ));
  END IF;

  v_special := nullif(btrim(coalesce(p_payload ->> 'special_requirements', '')), '');
  IF jsonb_array_length(v_items) = 0 AND v_special IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  BEGIN
    IF nullif(btrim(coalesce(p_payload ->> 'idempotency_key', '')), '') IS NOT NULL THEN
      v_idem := (p_payload ->> 'idempotency_key')::uuid;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  IF v_idem IS NOT NULL THEN
    SELECT r.reference
    INTO v_existing_reference
    FROM public.customer_requests r
    WHERE r.organization_id = p_organization_id
      AND r.idempotency_key = v_idem;

    IF FOUND THEN
      RETURN jsonb_build_object('reference', v_existing_reference, 'deduplicated', true);
    END IF;
  END IF;

  SELECT count(*)
  INTO v_recent
  FROM public.customer_requests r
  JOIN public.customers c ON c.id = r.customer_id
  WHERE r.organization_id = p_organization_id
    AND r.channel = 'web'
    AND r.created_at >= now() - interval '1 hour'
    AND (
      (v_email IS NOT NULL AND c.email = v_email)
      OR (v_phone IS NOT NULL AND c.phone_e164 = v_phone)
    );

  SELECT count(*)
  INTO v_org_recent
  FROM public.customer_requests r
  WHERE r.organization_id = p_organization_id
    AND r.channel = 'web'
    AND r.created_at >= now() - interval '1 hour';

  IF v_recent >= 5 OR v_org_recent >= 200 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = 'raise_exception';
  END IF;

  v_request := jsonb_strip_nulls(jsonb_build_object(
    'travel_start_date', nullif(p_payload ->> 'travel_start_date', ''),
    'travel_end_date', nullif(p_payload ->> 'travel_end_date', ''),
    'adults', p_payload -> 'adults',
    'children', p_payload -> 'children',
    'special_requirements', v_special,
    'locale', nullif(btrim(coalesce(p_payload ->> 'locale', '')), ''),
    'source_page', nullif(btrim(coalesce(p_payload ->> 'source_page', '')), ''),
    'privacy_consent_at', now(),
    'idempotency_key', v_idem
  ));

  -- adults/children may have been stored as JSON null; capture treats a missing key as the default.
  IF jsonb_typeof(p_payload -> 'adults') IS DISTINCT FROM 'number' THEN
    v_request := v_request - 'adults';
  END IF;
  IF jsonb_typeof(p_payload -> 'children') IS DISTINCT FROM 'number' THEN
    v_request := v_request - 'children';
  END IF;

  v_result := public.capture_request_core(
    p_organization_id,
    'web',
    NULL,
    v_contact,
    v_request,
    v_items,
    NULL
  );

  RETURN jsonb_build_object(
    'reference', v_result ->> 'reference',
    'deduplicated', coalesce((v_result ->> 'deduplicated')::boolean, false)
  );
END;
$$;

COMMENT ON FUNCTION public.submit_public_request(uuid, jsonb) IS
  'Public web intake. Returns only a reference and whether the call was deduplicated.';

REVOKE ALL ON FUNCTION public.submit_public_request(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_public_request(uuid, jsonb) TO anon, authenticated;
