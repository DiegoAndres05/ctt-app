-- public_request_intake_test.sql
-- Anonymous web intake: submit_public_request as anon.
--
-- Run with: ./supabase/tests/run-sql-tests.sh public_request_intake_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id       03000000-0000-4000-a000-000000000021
\set org_off_id   03000000-0000-4000-a000-000000000022
\set operator_id  03000000-0000-4000-b000-000000000021

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid,
  p_organization_id uuid,
  p_email text,
  p_full_name text,
  p_role public.app_role
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES (
    '00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
    p_email, now(), now()
  );

  INSERT INTO public.user_profiles (
    id, organization_id, full_name, email, role, status, must_change_password
  )
  VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, 'active', false);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.act_as(
  p_user_id uuid,
  p_organization_id uuid,
  p_app_role text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'app_role', p_app_role,
      'organization_id', p_organization_id::text
    )::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.clear_jwt()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.price_and_activate(p_organization_id uuid, p_product_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
  )
  VALUES (
    p_organization_id, p_product_id, 'COP', 150000, 'per_person'::public.charge_type,
    now() - interval '1 minute', NULL
  );

  UPDATE public.products
  SET status = 'active'
  WHERE id = p_product_id
    AND organization_id = p_organization_id;
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (
    :'org_id'::uuid, 'Web Intake', 'web-intake', 'active',
    '{"default_phone_country_code":"57"}'::jsonb
  ),
  (
    :'org_off_id'::uuid, 'Web Intake Off', 'web-intake-off', 'inactive',
    '{"default_phone_country_code":"57"}'::jsonb
  );

SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid,
  'operador-web@test.invalid', 'Operador Web', 'operator'
);

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience', 'Web Offer', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 120, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 8
  ),
  NULL
) ->> 'id') AS offer_id \gset

SELECT (public.create_product(
  'experience', 'Web Draft', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 60, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 8
  ),
  NULL
) ->> 'id') AS draft_product_id \gset

SELECT (public.create_product(
  'experience', 'Web Sold', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 60, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 8
  ),
  NULL
) ->> 'id') AS sold_product_id \gset

SELECT (public.create_product(
  'experience', 'Web Inactive', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 60, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 8
  ),
  NULL
) ->> 'id') AS inactive_product_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'offer_id'::uuid);
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'draft_product_id'::uuid);
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'sold_product_id'::uuid);
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'inactive_product_id'::uuid);
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'offer_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'web-intake-offer',
  'name_es', 'Oferta', 'name_en', 'Offer',
  'description_es', 'Desc', 'description_en', 'Desc',
  'public_category_id', 'islas',
  'location', 'Islas',
  'display_price', 150000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Guía', 'en', 'Guide'))
)) ->> 'id') AS offer_listing \gset

SELECT public.attach_public_image(
  :'offer_listing'::uuid, 'cover', NULL, '/images/web-intake-offer.jpg', 0
);
SELECT public.publish_public_listing(:'offer_listing'::uuid);

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'draft_product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'web-intake-draft',
  'name_es', 'Borrador', 'name_en', 'Draft',
  'description_es', 'Desc', 'description_en', 'Desc',
  'public_category_id', 'islas',
  'location', 'Islas',
  'display_price', 150000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Guía', 'en', 'Guide'))
)) ->> 'id') AS draft_listing \gset

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'sold_product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'web-intake-sold',
  'name_es', 'Agotada', 'name_en', 'Sold',
  'description_es', 'Desc', 'description_en', 'Desc',
  'public_category_id', 'islas',
  'location', 'Islas',
  'display_price', 150000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Guía', 'en', 'Guide'))
)) ->> 'id') AS sold_listing \gset

SELECT public.attach_public_image(
  :'sold_listing'::uuid, 'cover', NULL, '/images/web-intake-sold.jpg', 0
);
SELECT public.publish_public_listing(:'sold_listing'::uuid);
SELECT public.set_public_listing_sold_out(:'sold_listing'::uuid, true);

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'inactive_product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'web-intake-inactive',
  'name_es', 'Inactiva', 'name_en', 'Inactive',
  'description_es', 'Desc', 'description_en', 'Desc',
  'public_category_id', 'islas',
  'location', 'Islas',
  'display_price', 150000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Guía', 'en', 'Guide'))
)) ->> 'id') AS inactive_listing \gset

SELECT public.attach_public_image(
  :'inactive_listing'::uuid, 'cover', NULL, '/images/web-intake-inactive.jpg', 0
);
SELECT public.publish_public_listing(:'inactive_listing'::uuid);
SELECT public.set_product_status(:'inactive_product_id'::uuid, 'inactive');

RESET ROLE;
SELECT pg_temp.clear_jwt();

SELECT count(*)::bigint AS requests_before
FROM public.customer_requests
WHERE organization_id = :'org_id'::uuid \gset

-- ---------------------------------------------------------------------------
-- Rejections leave no rows
-- ---------------------------------------------------------------------------

SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'ana@test.invalid'),
        'interest_text', 'Tour'
      ))$$,
    :'org_id'
  ),
  'CONSENT_REQUIRED',
  'web intake requires privacy_consent'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'interest_text', 'Tour'
      ))$$,
    :'org_id'
  ),
  'CONTACT_REQUIRED',
  'web intake requires a contact object'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'no-at'),
        'interest_text', 'Tour'
      ))$$,
    :'org_id'
  ),
  'INVALID_EMAIL',
  'web intake rejects a malformed email'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'phone', '12'),
        'interest_text', 'Tour'
      ))$$,
    :'org_id'
  ),
  'INVALID_PHONE',
  'web intake rejects a too-short phone'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'past@test.invalid'),
        'travel_start_date', '2020-01-01',
        'interest_text', 'Tour'
      ))$$,
    :'org_id'
  ),
  'TRAVEL_DATE_IN_PAST',
  'web intake rejects a travel date in the past'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'range@test.invalid'),
        'travel_start_date', '2027-08-10',
        'travel_end_date', '2027-08-01',
        'interest_text', 'Tour'
      ))$$,
    :'org_id'
  ),
  'INVALID_DATE_RANGE',
  'web intake rejects an end date before the start date'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'website', 'https://spam.test',
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'honey@test.invalid'),
        'interest_text', 'Tour'
      ))$$,
    :'org_id'
  ),
  'VALIDATION_ERROR',
  'a filled honeypot is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'many@test.invalid'),
        'items', (
          SELECT jsonb_agg(jsonb_build_object('public_slug', 'web-intake-offer', 'quantity', 1))
          FROM generate_series(1, 11)
        )
      ))$$,
    :'org_id'
  ),
  'VALIDATION_ERROR',
  'more than 10 items is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'empty@test.invalid')
      ))$$,
    :'org_id'
  ),
  'VALIDATION_ERROR',
  'a request with no interest and no requirements is rejected'
);

SELECT tests.assert_raises(
  $$SELECT public.submit_public_request(
      '03000000-0000-4000-a000-0000000000ff'::uuid,
      jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'missing-org@test.invalid'),
        'interest_text', 'Tour'
      )
    )$$,
  'VALIDATION_ERROR',
  'an unknown organization is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'inactive-org@test.invalid'),
        'interest_text', 'Tour'
      ))$$,
    :'org_off_id'
  ),
  'VALIDATION_ERROR',
  'an inactive organization is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'missing-slug@test.invalid'),
        'items', jsonb_build_array(jsonb_build_object('public_slug', 'no-such-slug'))
      ))$$,
    :'org_id'
  ),
  'LISTING_NOT_AVAILABLE',
  'an unknown public slug is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'draft-slug@test.invalid'),
        'items', jsonb_build_array(jsonb_build_object('public_slug', 'web-intake-draft'))
      ))$$,
    :'org_id'
  ),
  'LISTING_NOT_AVAILABLE',
  'a draft listing is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'sold-slug@test.invalid'),
        'items', jsonb_build_array(jsonb_build_object('public_slug', 'web-intake-sold'))
      ))$$,
    :'org_id'
  ),
  'LISTING_NOT_AVAILABLE',
  'a sold-out listing is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'email', 'inactive-slug@test.invalid'),
        'items', jsonb_build_array(jsonb_build_object('public_slug', 'web-intake-inactive'))
      ))$$,
    :'org_id'
  ),
  'LISTING_NOT_AVAILABLE',
  'a listing whose product is inactive is rejected'
);

RESET ROLE;

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.customer_requests WHERE organization_id = :'org_id'::uuid),
  :requests_before,
  'rejected web calls create no requests'
);

-- ---------------------------------------------------------------------------
-- Success, idempotency, fingerprint, contact conflict
-- ---------------------------------------------------------------------------

SET LOCAL ROLE anon;

SELECT result ->> 'reference' AS ok_ref,
       result ->> 'deduplicated' AS ok_dedup
FROM (
  SELECT public.submit_public_request(
    :'org_id'::uuid,
    jsonb_build_object(
      'privacy_consent', true,
      'idempotency_key', '03000000-0000-4000-c000-000000000021',
      'contact', jsonb_build_object(
        'first_name', 'Ana',
        'email', ' Ana@Example.COM ',
        'phone', '3001230099'
      ),
      'travel_start_date', '2027-06-01',
      'travel_end_date', '2027-06-05',
      'adults', 2,
      'source_page', '/experiencias/web-intake-offer',
      'items', jsonb_build_array(jsonb_build_object(
        'public_slug', 'web-intake-offer',
        'quantity', 2
      ))
    )
  ) AS result
) s \gset

SELECT result ->> 'reference' AS idem_ref,
       result ->> 'deduplicated' AS idem_dedup
FROM (
  SELECT public.submit_public_request(
    :'org_id'::uuid,
    jsonb_build_object(
      'privacy_consent', true,
      'idempotency_key', '03000000-0000-4000-c000-000000000021',
      'contact', jsonb_build_object('first_name', 'Ana', 'email', 'ana@example.com'),
      'items', jsonb_build_array(jsonb_build_object('public_slug', 'web-intake-offer'))
    )
  ) AS result
) s \gset

SELECT result ->> 'reference' AS finger_ref,
       result ->> 'deduplicated' AS finger_dedup
FROM (
  SELECT public.submit_public_request(
    :'org_id'::uuid,
    jsonb_build_object(
      'privacy_consent', true,
      'contact', jsonb_build_object('first_name', 'Hugo', 'email', 'hugo-web@test.invalid'),
      'travel_start_date', '2027-07-01',
      'adults', 2,
      'interest_text', 'Cena en el muelle'
    )
  ) AS result
) s \gset

SELECT result ->> 'reference' AS finger2_ref,
       result ->> 'deduplicated' AS finger2_dedup
FROM (
  SELECT public.submit_public_request(
    :'org_id'::uuid,
    jsonb_build_object(
      'privacy_consent', true,
      'contact', jsonb_build_object('first_name', 'Hugo', 'email', 'hugo-web@test.invalid'),
      'travel_start_date', '2027-07-01',
      'adults', 2,
      'interest_text', 'Cena en el muelle'
    )
  ) AS result
) s \gset

SELECT public.submit_public_request(
  :'org_id'::uuid,
  jsonb_build_object(
    'privacy_consent', true,
    'contact', jsonb_build_object('first_name', 'Ana', 'email', 'ana-conflict@test.invalid'),
    'interest_text', 'Primera de Ana'
  )
);

SELECT public.submit_public_request(
  :'org_id'::uuid,
  jsonb_build_object(
    'privacy_consent', true,
    'contact', jsonb_build_object(
      'first_name', 'Otra Persona',
      'email', 'ana-conflict@test.invalid',
      'phone', '3005550001'
    ),
    'interest_text', 'Segunda de Ana'
  )
);

SELECT public.submit_public_request(
  :'org_id'::uuid,
  jsonb_build_object(
    'privacy_consent', true,
    'contact', jsonb_build_object('first_name', 'Bob', 'email', 'bob-conflict@test.invalid'),
    'interest_text', 'Primera de Bob'
  )
);

SELECT public.submit_public_request(
  :'org_id'::uuid,
  jsonb_build_object(
    'privacy_consent', true,
    'contact', jsonb_build_object(
      'first_name', 'Intruso',
      'email', 'bob-conflict@test.invalid',
      'phone', '3005550001'
    ),
    'interest_text', 'Cruce de contacto'
  )
);

DO $$
DECLARE
  v_i integer;
BEGIN
  FOR v_i IN 1..5 LOOP
    PERFORM public.submit_public_request(
      '03000000-0000-4000-a000-000000000021'::uuid,
      jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Rita', 'email', 'rita-rate@test.invalid'),
        'interest_text', 'Cupo ' || v_i::text
      )
    );
  END LOOP;
END;
$$;

SELECT tests.assert_raises(
  format(
    $$SELECT public.submit_public_request(%L::uuid, jsonb_build_object(
        'privacy_consent', true,
        'contact', jsonb_build_object('first_name', 'Rita', 'email', 'rita-rate@test.invalid'),
        'interest_text', 'Cupo 6'
      ))$$,
    :'org_id'
  ),
  'RATE_LIMITED',
  'the sixth web request in an hour for the same email is rate limited'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT %L = 'false'
         AND %L = %L
         AND %L = 'true'$$,
    :'ok_dedup', :'idem_ref', :'ok_ref', :'idem_dedup'
  ),
  'a repeated idempotency key returns the same reference and deduplicated=true'
);

SELECT tests.assert_true(
  format(
    $$SELECT %L = 'false'
         AND %L = %L
         AND %L = 'true'$$,
    :'finger_dedup', :'finger2_ref', :'finger_ref', :'finger2_dedup'
  ),
  'an identical request inside two minutes is deduplicated by fingerprint'
);

SELECT tests.assert_true(
  format(
    $$SELECT r.status = 'received'
         AND r.channel = 'web'
         AND r.privacy_consent_at IS NOT NULL
         AND c.email = 'ana@example.com'
         AND c.phone_e164 = '+573001230099'
         AND i.product_id = %L::uuid
         AND i.public_slug = 'web-intake-offer'
         AND i.quantity = 2
       FROM public.customer_requests r
       JOIN public.customers c ON c.id = r.customer_id
       JOIN public.customer_request_items i ON i.request_id = r.id
       WHERE r.organization_id = %L::uuid
         AND r.reference = %L$$,
    :'offer_id', :'org_id', :'ok_ref'
  ),
  'the stored request is received on the web channel with a normalized customer and listing item'
);

SELECT tests.assert_true(
  format(
    $$SELECT jsonb_typeof(public.submit_public_request(
           %L::uuid,
           jsonb_build_object(
             'privacy_consent', true,
             'idempotency_key', '03000000-0000-4000-c000-000000000021',
             'contact', jsonb_build_object('first_name', 'Ana', 'email', 'ana@example.com'),
             'items', jsonb_build_array(jsonb_build_object('public_slug', 'web-intake-offer'))
           )
         )) = 'object'$$,
    :'org_id'
  ),
  'idempotent replay still returns an object'
);

-- The public return has only reference and deduplicated. Replay as the table owner is enough
-- to read the keys; the call above already ran as anon.
SELECT tests.assert_true(
  $$SELECT (
       SELECT array_agg(key ORDER BY key)
       FROM jsonb_object_keys(
         public.submit_public_request(
           '03000000-0000-4000-a000-000000000021'::uuid,
           jsonb_build_object(
             'privacy_consent', true,
             'idempotency_key', '03000000-0000-4000-c000-000000000021',
             'contact', jsonb_build_object('first_name', 'Ana', 'email', 'ana@example.com'),
             'items', jsonb_build_array(jsonb_build_object('public_slug', 'web-intake-offer'))
           )
         )
       ) AS key
     ) = ARRAY['deduplicated', 'reference']$$,
  'submit_public_request returns only reference and deduplicated'
);

SELECT tests.assert_true(
  $$SELECT c.first_name = 'Ana'
       AND c.phone_e164 = '+573005550001'
       AND r.contact_review_required
       AND r.submitted_contact ->> 'first_name' = 'Otra Persona'
    FROM public.customers c
    JOIN public.customer_requests r ON r.customer_id = c.id
    WHERE c.email = 'ana-conflict@test.invalid'
      AND r.special_requirements IS NULL
      AND EXISTS (
        SELECT 1
        FROM public.customer_request_items i
        WHERE i.request_id = r.id
          AND i.free_text = 'Segunda de Ana'
      )$$,
  'a different name links to the existing email and flags the submitted contact for review'
);

SELECT tests.assert_true(
  $$SELECT ana.first_name = 'Ana'
       AND ana.phone_e164 = '+573005550001'
       AND bob.first_name = 'Bob'
       AND bob.phone_e164 IS NULL
       AND r.customer_id = bob.id
       AND r.contact_review_required
    FROM public.customers ana
    JOIN public.customers bob ON bob.organization_id = ana.organization_id
    JOIN public.customer_requests r ON r.customer_id = bob.id
    WHERE ana.email = 'ana-conflict@test.invalid'
      AND bob.email = 'bob-conflict@test.invalid'
      AND EXISTS (
        SELECT 1
        FROM public.customer_request_items i
        WHERE i.request_id = r.id
          AND i.free_text = 'Cruce de contacto'
      )$$,
  'when email and phone point at different customers, email wins and neither profile is overwritten'
);

SELECT tests.assert_equals(
  (
    SELECT count(*)
    FROM public.customer_requests r
    JOIN public.customers c ON c.id = r.customer_id
    WHERE c.email = 'rita-rate@test.invalid'
  ),
  5,
  'rate limiting stops the sixth request before it is stored'
);

ROLLBACK;
