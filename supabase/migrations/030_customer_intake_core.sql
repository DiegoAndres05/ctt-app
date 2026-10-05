-- 030_customer_intake_core.sql
-- Single phone/email normalization and the only request-capture path.
-- Source of truth: specs/003-customer-requests-channels/data-model.md ("Functions"),
-- specs/003-customer-requests-channels/research.md (R-004, R-005, R-006, R-013).
--
-- These routines are internal: EXECUTE is revoked from PUBLIC, anon, and authenticated.
-- Channel RPCs in later migrations are the only callers. SECURITY DEFINER so they can
-- insert despite RLS and append to the audit log. search_path is empty; names are qualified.
--
-- "Today" for travel dates is America/Bogota, not the database TimeZone.

-- ---------------------------------------------------------------------------
-- normalize_email
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.normalize_email(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_email text;
BEGIN
  v_email := lower(btrim(coalesce(p_raw, '')));
  IF v_email = '' THEN
    RETURN NULL;
  END IF;

  IF char_length(v_email) > 254 OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'INVALID_EMAIL' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_email;
END;
$$;

COMMENT ON FUNCTION public.normalize_email(text) IS
  'lower(trim) an email, or NULL when empty. Invalid shape raises INVALID_EMAIL.';

REVOKE ALL ON FUNCTION public.normalize_email(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.normalize_email(text) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- normalize_phone_e164
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.normalize_phone_e164(
  p_raw text,
  p_default_country_code text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_raw text;
  v_cc text;
BEGIN
  v_raw := regexp_replace(btrim(coalesce(p_raw, '')), '[\s\-().]', '', 'g');
  IF v_raw = '' THEN
    RETURN NULL;
  END IF;

  v_cc := regexp_replace(coalesce(p_default_country_code, ''), '[^0-9]', '', 'g');
  IF v_cc !~ '^[1-9][0-9]{0,3}$' THEN
    RAISE EXCEPTION 'INVALID_PHONE' USING ERRCODE = 'raise_exception';
  END IF;

  IF left(v_raw, 1) = '+' THEN
    NULL;
  ELSIF left(v_raw, 2) = '00' THEN
    v_raw := '+' || substring(v_raw FROM 3);
  ELSE
    IF left(v_raw, 1) = '0' THEN
      v_raw := substring(v_raw FROM 2);
    END IF;
    v_raw := '+' || v_cc || v_raw;
  END IF;

  IF v_raw !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'INVALID_PHONE' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_raw;
END;
$$;

COMMENT ON FUNCTION public.normalize_phone_e164(text, text) IS
  'E.164 normalization (R-004). Empty input is NULL; anything else that is not E.164 raises INVALID_PHONE.';

REVOKE ALL ON FUNCTION public.normalize_phone_e164(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.normalize_phone_e164(text, text) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- organization_phone_country_code
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.organization_phone_country_code(p_org uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code text;
BEGIN
  SELECT nullif(btrim(o.settings ->> 'default_phone_country_code'), '')
  INTO v_code
  FROM public.organizations o
  WHERE o.id = p_org;

  RETURN coalesce(v_code, '57');
END;
$$;

COMMENT ON FUNCTION public.organization_phone_country_code(uuid) IS
  'settings.default_phone_country_code for the organization, or 57 when unset.';

REVOKE ALL ON FUNCTION public.organization_phone_country_code(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.organization_phone_country_code(uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- next_organization_sequence
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.next_organization_sequence(p_org uuid, p_scope text)
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_next bigint;
BEGIN
  IF p_org IS NULL OR p_scope IS NULL OR btrim(p_scope) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.organization_sequences (organization_id, scope, last_value)
  VALUES (p_org, p_scope, 1)
  ON CONFLICT (organization_id, scope)
  DO UPDATE SET last_value = organization_sequences.last_value + 1
  RETURNING last_value INTO v_next;

  RETURN v_next;
END;
$$;

COMMENT ON FUNCTION public.next_organization_sequence(uuid, text) IS
  'Allocates the next per-tenant counter for a scope. First call returns 1.';

REVOKE ALL ON FUNCTION public.next_organization_sequence(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.next_organization_sequence(uuid, text) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- require_tenant_member
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.require_tenant_member()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_claim_org uuid := nullif(auth.jwt() ->> 'organization_id', '')::uuid;
  v_claim_role text := auth.jwt() ->> 'app_role';
  v_organization_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_claim_role IS NULL
     OR v_claim_role NOT IN ('agent', 'operator', 'admin')
     OR v_claim_org IS NULL
  THEN
    RAISE EXCEPTION 'INSUFFICIENT_PERMISSIONS' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT p.organization_id
  INTO v_organization_id
  FROM public.user_profiles p
  WHERE p.id = v_user_id
    AND p.status = 'active'
    AND p.role IN ('agent', 'operator', 'admin')
    AND p.organization_id = v_claim_org;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'INSUFFICIENT_PERMISSIONS' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN v_organization_id;
END;
$$;

COMMENT ON FUNCTION public.require_tenant_member() IS
  'Returns the caller tenant id when the JWT and the live profile are an active agent, operator, or admin.';

REVOKE ALL ON FUNCTION public.require_tenant_member() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.require_tenant_member() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- match_or_create_customer
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.match_or_create_customer(
  p_org uuid,
  p_contact jsonb,
  p_actor uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_first text;
  v_last text;
  v_email text;
  v_phone text;
  v_country text;
  v_by_email uuid;
  v_by_phone uuid;
  v_customer_id uuid;
  v_created boolean := false;
  v_review boolean := false;
  v_row public.customers%ROWTYPE;
  v_submitted jsonb;
BEGIN
  IF p_org IS NULL OR p_contact IS NULL OR jsonb_typeof(p_contact) <> 'object' THEN
    RAISE EXCEPTION 'CONTACT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  v_first := btrim(coalesce(p_contact ->> 'first_name', ''));
  v_last := nullif(btrim(coalesce(p_contact ->> 'last_name', '')), '');
  v_country := nullif(upper(btrim(coalesce(p_contact ->> 'country_code', ''))), '');

  IF v_first = '' THEN
    RAISE EXCEPTION 'CONTACT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;
  IF char_length(v_first) > 120 OR (v_last IS NOT NULL AND char_length(v_last) > 120) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_country IS NOT NULL AND v_country !~ '^[A-Z]{2}$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_email := public.normalize_email(p_contact ->> 'email');
  v_phone := public.normalize_phone_e164(
    coalesce(nullif(btrim(coalesce(p_contact ->> 'phone', '')), ''), p_contact ->> 'phone_e164'),
    public.organization_phone_country_code(p_org)
  );

  IF v_email IS NULL AND v_phone IS NULL THEN
    RAISE EXCEPTION 'CONTACT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_email IS NOT NULL THEN
    SELECT c.id
    INTO v_by_email
    FROM public.customers c
    WHERE c.organization_id = p_org
      AND c.email = v_email
      AND c.is_anonymized = false;
  END IF;

  IF v_phone IS NOT NULL THEN
    SELECT c.id
    INTO v_by_phone
    FROM public.customers c
    WHERE c.organization_id = p_org
      AND c.phone_e164 = v_phone
      AND c.is_anonymized = false;
  END IF;

  v_submitted := jsonb_strip_nulls(jsonb_build_object(
    'first_name', v_first,
    'last_name', v_last,
    'email', v_email,
    'phone_e164', v_phone,
    'country_code', v_country
  ));

  IF v_by_email IS NULL AND v_by_phone IS NULL THEN
    BEGIN
      INSERT INTO public.customers (
        organization_id, first_name, last_name, email, phone_e164, country_code, created_by
      )
      VALUES (p_org, v_first, v_last, v_email, v_phone, v_country, p_actor)
      RETURNING id INTO v_customer_id;
      v_created := true;
    EXCEPTION
      WHEN unique_violation THEN
        v_created := false;
        IF v_email IS NOT NULL THEN
          SELECT c.id INTO v_by_email
          FROM public.customers c
          WHERE c.organization_id = p_org AND c.email = v_email AND c.is_anonymized = false;
        END IF;
        IF v_phone IS NOT NULL THEN
          SELECT c.id INTO v_by_phone
          FROM public.customers c
          WHERE c.organization_id = p_org AND c.phone_e164 = v_phone AND c.is_anonymized = false;
        END IF;
        v_customer_id := coalesce(v_by_email, v_by_phone);
        IF v_customer_id IS NULL THEN
          RAISE;
        END IF;
    END;

    IF v_created THEN
      RETURN jsonb_build_object(
        'customer_id', v_customer_id,
        'customer_created', true,
        'contact_review_required', false,
        'submitted_contact', NULL
      );
    END IF;
  END IF;

  IF v_by_email IS NOT NULL AND v_by_phone IS NOT NULL AND v_by_email IS DISTINCT FROM v_by_phone THEN
    v_customer_id := v_by_email;
    v_review := true;
  ELSIF v_by_email IS NOT NULL THEN
    v_customer_id := v_by_email;
  ELSE
    v_customer_id := v_by_phone;
  END IF;

  SELECT *
  INTO v_row
  FROM public.customers
  WHERE id = v_customer_id
  FOR UPDATE;

  IF lower(v_row.first_name) IS DISTINCT FROM lower(v_first) THEN
    v_review := true;
  END IF;
  IF v_last IS NOT NULL
     AND v_row.last_name IS NOT NULL
     AND lower(btrim(v_row.last_name)) IS DISTINCT FROM lower(v_last)
  THEN
    v_review := true;
  END IF;
  IF v_email IS NOT NULL AND v_row.email IS NOT NULL AND v_row.email IS DISTINCT FROM v_email THEN
    v_review := true;
  END IF;
  IF v_phone IS NOT NULL AND v_row.phone_e164 IS NOT NULL AND v_row.phone_e164 IS DISTINCT FROM v_phone THEN
    v_review := true;
  END IF;

  IF v_row.last_name IS NULL AND v_last IS NOT NULL THEN
    UPDATE public.customers SET last_name = v_last WHERE id = v_customer_id;
  END IF;

  IF v_row.email IS NULL AND v_email IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.customers c
      WHERE c.organization_id = p_org
        AND c.email = v_email
        AND c.id <> v_customer_id
    ) THEN
      v_review := true;
    ELSE
      UPDATE public.customers SET email = v_email WHERE id = v_customer_id;
    END IF;
  END IF;

  IF v_row.phone_e164 IS NULL AND v_phone IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.customers c
      WHERE c.organization_id = p_org
        AND c.phone_e164 = v_phone
        AND c.id <> v_customer_id
    ) THEN
      v_review := true;
    ELSE
      UPDATE public.customers SET phone_e164 = v_phone WHERE id = v_customer_id;
    END IF;
  END IF;

  IF v_row.country_code IS NULL AND v_country IS NOT NULL THEN
    UPDATE public.customers SET country_code = v_country WHERE id = v_customer_id;
  END IF;

  RETURN jsonb_build_object(
    'customer_id', v_customer_id,
    'customer_created', false,
    'contact_review_required', v_review,
    'submitted_contact', CASE WHEN v_review THEN v_submitted ELSE NULL END
  );
END;
$$;

COMMENT ON FUNCTION public.match_or_create_customer(uuid, jsonb, uuid) IS
  'Links a contact to an existing customer (email, then phone) or creates one. Never overwrites or merges.';

REVOKE ALL ON FUNCTION public.match_or_create_customer(uuid, jsonb, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.match_or_create_customer(uuid, jsonb, uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- capture_request_core
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.capture_request_core(
  p_org uuid,
  p_channel public.request_channel,
  p_customer_id uuid,
  p_contact jsonb,
  p_request jsonb,
  p_items jsonb,
  p_actor uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_request jsonb := coalesce(p_request, '{}'::jsonb);
  v_items jsonb;
  v_norm jsonb := '[]'::jsonb;
  v_item jsonb;
  v_product_id uuid;
  v_slug text;
  v_free text;
  v_qty integer;
  v_start date;
  v_end date;
  v_today date;
  v_adults integer;
  v_children integer;
  v_special text;
  v_locale text;
  v_source text;
  v_consent timestamptz;
  v_idem uuid;
  v_assign uuid;
  v_existing public.customer_requests%ROWTYPE;
  v_match jsonb;
  v_customer_id uuid;
  v_customer_created boolean := false;
  v_review boolean := false;
  v_submitted jsonb;
  v_cust public.customers%ROWTYPE;
  v_fp text;
  v_ref text;
  v_request_id uuid;
  v_pos integer := 0;
  v_assigned_at timestamptz;
BEGIN
  IF p_org IS NULL OR p_channel IS NULL OR jsonb_typeof(v_request) <> 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_items IS NULL THEN
    v_items := '[]'::jsonb;
  ELSIF jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  ELSE
    v_items := p_items;
  END IF;

  BEGIN
    IF nullif(v_request ->> 'travel_start_date', '') IS NOT NULL THEN
      v_start := (v_request ->> 'travel_start_date')::date;
    END IF;
    IF nullif(v_request ->> 'travel_end_date', '') IS NOT NULL THEN
      v_end := (v_request ->> 'travel_end_date')::date;
    END IF;
    IF nullif(v_request ->> 'privacy_consent_at', '') IS NOT NULL THEN
      v_consent := (v_request ->> 'privacy_consent_at')::timestamptz;
    END IF;
    IF nullif(v_request ->> 'idempotency_key', '') IS NOT NULL THEN
      v_idem := (v_request ->> 'idempotency_key')::uuid;
    END IF;
    IF nullif(v_request ->> 'assign_to', '') IS NOT NULL THEN
      v_assign := (v_request ->> 'assign_to')::uuid;
    END IF;

    IF v_request ? 'adults' AND v_request -> 'adults' IS NOT NULL
       AND jsonb_typeof(v_request -> 'adults') <> 'null'
    THEN
      v_adults := (v_request ->> 'adults')::integer;
    ELSE
      v_adults := 1;
    END IF;

    IF v_request ? 'children' AND v_request -> 'children' IS NOT NULL
       AND jsonb_typeof(v_request -> 'children') <> 'null'
    THEN
      v_children := (v_request ->> 'children')::integer;
    ELSE
      v_children := 0;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow
         OR numeric_value_out_of_range
    THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  v_today := (now() AT TIME ZONE 'America/Bogota')::date;
  IF v_start IS NOT NULL AND v_start < v_today THEN
    RAISE EXCEPTION 'TRAVEL_DATE_IN_PAST' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_end IS NOT NULL AND v_start IS NOT NULL AND v_end < v_start THEN
    RAISE EXCEPTION 'INVALID_DATE_RANGE' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_adults IS NULL OR v_adults < 1 OR v_adults > 99
     OR v_children IS NULL OR v_children < 0 OR v_children > 99
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_special := nullif(btrim(coalesce(v_request ->> 'special_requirements', '')), '');
  IF v_special IS NOT NULL AND char_length(v_special) > 2000 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_locale := nullif(btrim(coalesce(v_request ->> 'locale', '')), '');
  IF v_locale IS NOT NULL AND v_locale NOT IN ('es', 'en') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_source := nullif(btrim(coalesce(v_request ->> 'source_page', '')), '');
  IF v_source IS NOT NULL AND char_length(v_source) > 500 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_channel = 'web' AND v_consent IS NULL THEN
    RAISE EXCEPTION 'CONSENT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  FOR v_item IN
    SELECT value FROM jsonb_array_elements(v_items)
  LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    BEGIN
      IF nullif(v_item ->> 'product_id', '') IS NOT NULL THEN
        v_product_id := (v_item ->> 'product_id')::uuid;
      ELSE
        v_product_id := NULL;
      END IF;
      IF v_item ? 'quantity' AND v_item -> 'quantity' IS NOT NULL
         AND jsonb_typeof(v_item -> 'quantity') <> 'null'
      THEN
        v_qty := (v_item ->> 'quantity')::integer;
      ELSE
        v_qty := 1;
      END IF;
    EXCEPTION
      WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;

    v_slug := nullif(btrim(coalesce(v_item ->> 'public_slug', '')), '');
    v_free := nullif(btrim(coalesce(v_item ->> 'free_text', '')), '');
    IF v_free IS NOT NULL AND char_length(v_free) > 500 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF v_slug IS NOT NULL AND char_length(v_slug) > 200 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF v_product_id IS NULL AND v_free IS NULL THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF v_product_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.products p
      WHERE p.id = v_product_id
        AND p.organization_id = p_org
    ) THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    v_norm := v_norm || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'product_id', v_product_id,
      'public_slug', v_slug,
      'free_text', v_free,
      'quantity', v_qty
    )));
  END LOOP;

  IF v_idem IS NOT NULL THEN
    SELECT *
    INTO v_existing
    FROM public.customer_requests r
    WHERE r.organization_id = p_org
      AND r.idempotency_key = v_idem;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'request_id', v_existing.id,
        'reference', v_existing.reference,
        'customer_id', v_existing.customer_id,
        'customer_created', false,
        'deduplicated', true,
        'contact_review_required', v_existing.contact_review_required
      );
    END IF;
  END IF;

  IF p_customer_id IS NOT NULL THEN
    SELECT *
    INTO v_cust
    FROM public.customers c
    WHERE c.id = p_customer_id
      AND c.organization_id = p_org;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF v_cust.is_anonymized THEN
      RAISE EXCEPTION 'CUSTOMER_ANONYMIZED' USING ERRCODE = 'raise_exception';
    END IF;

    v_customer_id := v_cust.id;
    v_customer_created := false;
    v_review := false;
    v_submitted := NULL;
  ELSE
    v_match := public.match_or_create_customer(p_org, p_contact, p_actor);
    v_customer_id := (v_match ->> 'customer_id')::uuid;
    v_customer_created := coalesce((v_match ->> 'customer_created')::boolean, false);
    v_review := coalesce((v_match ->> 'contact_review_required')::boolean, false);
    v_submitted := v_match -> 'submitted_contact';
    IF v_submitted IS NULL OR v_submitted = 'null'::jsonb THEN
      v_submitted := NULL;
    END IF;
  END IF;

  SELECT md5(
    p_channel::text || '|' ||
    v_customer_id::text || '|' ||
    coalesce(v_start::text, '') || '|' ||
    coalesce(v_end::text, '') || '|' ||
    v_adults::text || '|' ||
    v_children::text || '|' ||
    lower(coalesce(v_special, '')) || '|' ||
    coalesce((
      SELECT string_agg(
        coalesce(item ->> 'product_id', '') || ':' ||
        coalesce(item ->> 'public_slug', '') || ':' ||
        lower(coalesce(item ->> 'free_text', '')) || ':' ||
        coalesce(item ->> 'quantity', '1'),
        '|'
        ORDER BY
          coalesce(item ->> 'product_id', ''),
          coalesce(item ->> 'public_slug', ''),
          lower(coalesce(item ->> 'free_text', '')),
          coalesce(item ->> 'quantity', '1')
      )
      FROM jsonb_array_elements(v_norm) AS item
    ), '')
  )
  INTO v_fp;

  -- Closed requests stay in history. A later submission, including a WhatsApp
  -- message after discard, must open a new request instead of reviving them.
  SELECT *
  INTO v_existing
  FROM public.customer_requests r
  WHERE r.organization_id = p_org
    AND r.dedup_fingerprint = v_fp
    AND r.status IN ('received', 'in_review')
    AND r.created_at >= now() - interval '2 minutes'
  ORDER BY r.created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'request_id', v_existing.id,
      'reference', v_existing.reference,
      'customer_id', v_existing.customer_id,
      'customer_created', v_customer_created,
      'deduplicated', true,
      'contact_review_required', v_existing.contact_review_required
    );
  END IF;

  v_ref := 'SOL-' || lpad(public.next_organization_sequence(p_org, 'customer_request')::text, 5, '0');
  IF v_assign IS NOT NULL THEN
    v_assigned_at := now();
  END IF;

  BEGIN
    INSERT INTO public.customer_requests (
      organization_id, reference, customer_id, channel, status,
      assigned_to, assigned_at,
      travel_start_date, travel_end_date, adults, children,
      special_requirements, locale, source_page,
      submitted_contact, contact_review_required,
      privacy_consent_at, idempotency_key, dedup_fingerprint,
      created_by
    )
    VALUES (
      p_org, v_ref, v_customer_id, p_channel, 'received',
      v_assign, v_assigned_at,
      v_start, v_end, v_adults::smallint, v_children::smallint,
      v_special, v_locale, v_source,
      CASE WHEN v_review THEN v_submitted ELSE NULL END,
      v_review,
      v_consent, v_idem, v_fp,
      p_actor
    )
    RETURNING id INTO v_request_id;

    FOR v_item IN
      SELECT value FROM jsonb_array_elements(v_norm)
    LOOP
      INSERT INTO public.customer_request_items (
        organization_id, request_id, product_id, public_slug, free_text, quantity, position
      )
      VALUES (
        p_org,
        v_request_id,
        nullif(v_item ->> 'product_id', '')::uuid,
        v_item ->> 'public_slug',
        v_item ->> 'free_text',
        (v_item ->> 'quantity')::smallint,
        v_pos::smallint
      );
      v_pos := v_pos + 1;
    END LOOP;
  EXCEPTION
    WHEN unique_violation THEN
      IF v_idem IS NOT NULL THEN
        SELECT *
        INTO v_existing
        FROM public.customer_requests r
        WHERE r.organization_id = p_org
          AND r.idempotency_key = v_idem;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'request_id', v_existing.id,
            'reference', v_existing.reference,
            'customer_id', v_existing.customer_id,
            'customer_created', false,
            'deduplicated', true,
            'contact_review_required', v_existing.contact_review_required
          );
        END IF;
      END IF;
      RAISE;
  END;

  PERFORM audit.log_event(
    p_org,
    'request_received'::audit.audit_event_type,
    'success'::audit.audit_result,
    p_actor,
    'customer_request',
    v_request_id,
    jsonb_build_object('channel', p_channel, 'deduplicated', false)
  );

  RETURN jsonb_build_object(
    'request_id', v_request_id,
    'reference', v_ref,
    'customer_id', v_customer_id,
    'customer_created', v_customer_created,
    'deduplicated', false,
    'contact_review_required', v_review
  );
END;
$$;

COMMENT ON FUNCTION public.capture_request_core(
  uuid, public.request_channel, uuid, jsonb, jsonb, jsonb, uuid
) IS
  'Creates a received request, or returns an existing one for the same idempotency key or 2-minute fingerprint.';

REVOKE ALL ON FUNCTION public.capture_request_core(
  uuid, public.request_channel, uuid, jsonb, jsonb, jsonb, uuid
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.capture_request_core(
  uuid, public.request_channel, uuid, jsonb, jsonb, jsonb, uuid
) FROM anon, authenticated;
