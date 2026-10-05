-- customer_intake_core_test.sql
-- Normalization, customer matching, dedup, and SOL- references. Runs as superuser and
-- calls the internal functions directly.
--
-- Run with: ./supabase/tests/run-sql-tests.sh customer_intake_core_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id   03000000-0000-4000-a000-000000000001
\set org_b_id 03000000-0000-4000-a000-000000000002

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (
    :'org_id'::uuid, 'Intake Core', 'intake-core', 'active',
    jsonb_build_object('default_phone_country_code', '57')
  ),
  (
    :'org_b_id'::uuid, 'Intake Core B', 'intake-core-b', 'active',
    '{}'::jsonb
  );

-- ---------------------------------------------------------------------------
-- Phone and email
-- ---------------------------------------------------------------------------

SELECT tests.assert_true(
  $$SELECT public.normalize_phone_e164('+57 300 123 4567', '57') = '+573001234567'
       AND public.normalize_phone_e164('0300 1234567', '57') = '+573001234567'
       AND public.normalize_phone_e164('3001234567', '57') = '+573001234567'
       AND public.normalize_phone_e164('0057 3001234567', '57') = '+573001234567'$$,
  'local and 00-prefixed numbers collapse to +573001234567'
);

SELECT tests.assert_true(
  $$SELECT public.normalize_phone_e164('+1 (305) 555-0123', '57') = '+13055550123'$$,
  'international number keeps its own country code'
);

SELECT tests.assert_true(
  $$SELECT public.normalize_phone_e164('   ', '57') IS NULL
       AND public.normalize_email('   ') IS NULL$$,
  'blank phone and email normalize to NULL'
);

SELECT tests.assert_raises(
  $$SELECT public.normalize_phone_e164('123', '57')$$,
  'INVALID_PHONE',
  'too-short phone is rejected'
);

SELECT tests.assert_raises(
  $$SELECT public.normalize_phone_e164('abc', '57')$$,
  'INVALID_PHONE',
  'non-numeric phone is rejected'
);

SELECT tests.assert_true(
  $$SELECT public.normalize_email(' Ana@Example.COM ') = 'ana@example.com'$$,
  'email is trimmed and lowercased'
);

SELECT tests.assert_raises(
  $$SELECT public.normalize_email('no-at')$$,
  'INVALID_EMAIL',
  'email without @ is rejected'
);

-- ---------------------------------------------------------------------------
-- Sequences are per organization and per scope
-- ---------------------------------------------------------------------------

SELECT tests.assert_equals(
  public.next_organization_sequence(:'org_id'::uuid, 'probe'),
  1,
  'first sequence value for org A is 1'
);

SELECT tests.assert_equals(
  public.next_organization_sequence(:'org_id'::uuid, 'probe'),
  2,
  'second sequence value for org A is 2'
);

SELECT tests.assert_equals(
  public.next_organization_sequence(:'org_b_id'::uuid, 'probe'),
  1,
  'first sequence value for org B is 1'
);

-- ---------------------------------------------------------------------------
-- Matching: create, email, phone, fill, no overwrite, split contacts, anonymized
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_org uuid := '03000000-0000-4000-a000-000000000001';
  v_created jsonb;
  v_by_email jsonb;
  v_filled jsonb;
  v_renamed jsonb;
  v_split jsonb;
  v_after_anon jsonb;
  v_customer_id uuid;
  v_other_id uuid;
BEGIN
  v_created := public.match_or_create_customer(
    v_org,
    jsonb_build_object('first_name', 'Laura', 'email', 'laura@example.com'),
    NULL
  );
  PERFORM tests.assert_true(
    format(
      'SELECT (%L::jsonb ->> ''customer_created'')::boolean',
      v_created
    ),
    'match creates a customer when nothing matches'
  );

  v_customer_id := (v_created ->> 'customer_id')::uuid;

  v_by_email := public.match_or_create_customer(
    v_org,
    jsonb_build_object('first_name', 'Laura', 'email', ' Laura@Example.com '),
    NULL
  );
  PERFORM tests.assert_true(
    format(
      'SELECT (%L::jsonb ->> ''customer_id'')::uuid = %L::uuid AND NOT (%L::jsonb ->> ''customer_created'')::boolean',
      v_by_email, v_customer_id, v_by_email
    ),
    'second contact with the same email links the existing customer'
  );

  v_filled := public.match_or_create_customer(
    v_org,
    jsonb_build_object(
      'first_name', 'Laura',
      'email', 'laura@example.com',
      'phone', '3001112233'
    ),
    NULL
  );
  PERFORM tests.assert_true(
    format(
      $q$SELECT phone_e164 = '+573001112233'
            AND NOT (%L::jsonb ->> 'contact_review_required')::boolean
         FROM public.customers WHERE id = %L::uuid$q$,
      v_filled, v_customer_id
    ),
    'an empty phone is filled and does not flag review'
  );

  PERFORM tests.assert_true(
    format(
      $q$SELECT (%L::jsonb ->> 'customer_id')::uuid = %L::uuid
         FROM public.customers c
         WHERE c.organization_id = %L::uuid
           AND c.phone_e164 = '+573001112233'$q$,
      public.match_or_create_customer(
        v_org,
        jsonb_build_object('first_name', 'Laura', 'phone', '+57 300 111 2233'),
        NULL
      ),
      v_customer_id,
      v_org
    ),
    'a later contact links by phone'
  );

  v_renamed := public.match_or_create_customer(
    v_org,
    jsonb_build_object(
      'first_name', 'Otra',
      'email', 'laura@example.com',
      'phone', '+573001112233'
    ),
    NULL
  );
  PERFORM tests.assert_true(
    format(
      $q$SELECT first_name = 'Laura'
            AND (%L::jsonb ->> 'contact_review_required')::boolean
            AND (%L::jsonb -> 'submitted_contact' ->> 'first_name') = 'Otra'
         FROM public.customers WHERE id = %L::uuid$q$,
      v_renamed, v_renamed, v_customer_id
    ),
    'a different name is not overwritten and is kept for review'
  );

  PERFORM public.match_or_create_customer(
    v_org,
    jsonb_build_object('first_name', 'Bruno', 'email', 'bruno@example.com', 'phone', '+573009998877'),
    NULL
  );

  v_split := public.match_or_create_customer(
    v_org,
    jsonb_build_object(
      'first_name', 'Laura',
      'email', 'laura@example.com',
      'phone', '+573009998877'
    ),
    NULL
  );
  PERFORM tests.assert_true(
    format(
      $q$SELECT (%L::jsonb ->> 'customer_id')::uuid = %L::uuid
            AND (%L::jsonb ->> 'contact_review_required')::boolean
            AND (SELECT phone_e164 FROM public.customers WHERE id = %L::uuid) = '+573001112233'
            AND (
              SELECT phone_e164 FROM public.customers
              WHERE organization_id = %L::uuid AND email = 'bruno@example.com'
            ) = '+573009998877'$q$,
      v_split, v_customer_id, v_split, v_customer_id, v_org
    ),
    'email wins when email and phone point at different customers'
  );

  UPDATE public.customers
  SET first_name = 'Cliente anonimizado',
      last_name = NULL,
      email = NULL,
      phone_e164 = NULL,
      country_code = NULL,
      is_anonymized = true,
      anonymized_at = now()
  WHERE id = v_customer_id;

  v_after_anon := public.match_or_create_customer(
    v_org,
    jsonb_build_object('first_name', 'Laura', 'email', 'laura@example.com'),
    NULL
  );
  v_other_id := (v_after_anon ->> 'customer_id')::uuid;
  PERFORM tests.assert_true(
    format(
      'SELECT %L::uuid <> %L::uuid AND (%L::jsonb ->> ''customer_created'')::boolean',
      v_other_id, v_customer_id, v_after_anon
    ),
    'an anonymized customer is ignored and a new one is created'
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Capture: reference, idempotency, fingerprint window, dates, audit without PII
-- ---------------------------------------------------------------------------

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.capture_request_core(
      %L::uuid, 'web', NULL,
      '{"first_name":"Pasada","email":"pasada@example.com"}'::jsonb,
      '{"travel_start_date":"2000-01-01","privacy_consent_at":"2026-01-01T00:00:00Z"}'::jsonb,
      '[]'::jsonb, NULL
    )$sql$,
    :'org_id'
  ),
  'TRAVEL_DATE_IN_PAST',
  'a start date before today in Bogota is rejected'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.capture_request_core(
      %L::uuid, 'web', NULL,
      '{"first_name":"Rango","email":"rango@example.com"}'::jsonb,
      '{"travel_start_date":"2027-08-10","travel_end_date":"2027-08-01","privacy_consent_at":"2026-01-01T00:00:00Z"}'::jsonb,
      '[]'::jsonb, NULL
    )$sql$,
    :'org_id'
  ),
  'INVALID_DATE_RANGE',
  'an end date before the start date is rejected'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.customer_requests WHERE organization_id = :'org_id'::uuid),
  0,
  'rejected captures insert no request'
);

SELECT (
  public.capture_request_core(
    :'org_id'::uuid,
    'web',
    NULL,
    '{"first_name":"Idem","email":"idem@example.com","phone":"+573001010101"}'::jsonb,
    jsonb_build_object(
      'idempotency_key', '03000000-0000-4000-c000-0000000000aa',
      'travel_start_date', '2027-06-01',
      'adults', 2,
      'privacy_consent_at', now(),
      'special_requirements', 'Idempotencia'
    ),
    '[{"free_text":"Tour","quantity":1}]'::jsonb,
    NULL
  )
) AS first_capture \gset

SELECT tests.assert_true(
  format(
    $$SELECT (%L::jsonb ->> 'reference') = 'SOL-00001'
         AND NOT (%L::jsonb ->> 'deduplicated')::boolean
         AND (SELECT status FROM public.customer_requests WHERE id = (%L::jsonb ->> 'request_id')::uuid) = 'received'$$,
    :'first_capture', :'first_capture', :'first_capture'
  ),
  'first capture is received with reference SOL-00001'
);

SELECT (
  public.capture_request_core(
    :'org_id'::uuid,
    'web',
    NULL,
    '{"first_name":"Idem","email":"idem@example.com"}'::jsonb,
    jsonb_build_object(
      'idempotency_key', '03000000-0000-4000-c000-0000000000aa',
      'travel_start_date', '2027-06-01',
      'privacy_consent_at', now(),
      'special_requirements', 'Idempotencia repetida'
    ),
    '[]'::jsonb,
    NULL
  )
) AS idem_capture \gset

SELECT tests.assert_true(
  format(
    $$SELECT (%L::jsonb ->> 'deduplicated')::boolean
         AND (%L::jsonb ->> 'request_id') = (%L::jsonb ->> 'request_id')$$,
    :'idem_capture', :'idem_capture', :'first_capture'
  ),
  'the same idempotency key returns the existing request'
);

SELECT (
  public.capture_request_core(
    :'org_id'::uuid,
    'phone',
    NULL,
    '{"first_name":"Huella","phone":"3002020202"}'::jsonb,
    '{"travel_start_date":"2027-07-01","adults":1,"children":0,"special_requirements":"Misma huella"}'::jsonb,
    '[{"free_text":"Cena","quantity":2}]'::jsonb,
    NULL
  )
) AS finger_capture \gset

SELECT (
  public.capture_request_core(
    :'org_id'::uuid,
    'phone',
    NULL,
    '{"first_name":"Huella","phone":"+573002020202"}'::jsonb,
    '{"travel_start_date":"2027-07-01","special_requirements":"misma huella"}'::jsonb,
    '[{"free_text":"cena","quantity":2}]'::jsonb,
    NULL
  )
) AS finger_again \gset

SELECT tests.assert_true(
  format(
    $$SELECT (%L::jsonb ->> 'deduplicated')::boolean
         AND (%L::jsonb ->> 'request_id') = (%L::jsonb ->> 'request_id')$$,
    :'finger_again', :'finger_again', :'finger_capture'
  ),
  'the same fingerprint inside two minutes is deduplicated'
);

ALTER TABLE public.customer_requests DISABLE TRIGGER customer_requests_prevent_identity_change;

UPDATE public.customer_requests
SET created_at = now() - interval '3 minutes'
WHERE id = (:'finger_capture'::jsonb ->> 'request_id')::uuid;

ALTER TABLE public.customer_requests ENABLE TRIGGER customer_requests_prevent_identity_change;

SELECT (
  public.capture_request_core(
    :'org_id'::uuid,
    'phone',
    NULL,
    '{"first_name":"Huella","phone":"+573002020202"}'::jsonb,
    '{"travel_start_date":"2027-07-01","special_requirements":"misma huella"}'::jsonb,
    '[{"free_text":"cena","quantity":2}]'::jsonb,
    NULL
  )
) AS finger_late \gset

SELECT tests.assert_true(
  format(
    $$SELECT NOT (%L::jsonb ->> 'deduplicated')::boolean
         AND (%L::jsonb ->> 'request_id') <> (%L::jsonb ->> 'request_id')$$,
    :'finger_late', :'finger_late', :'finger_capture'
  ),
  'a fingerprint older than two minutes creates a new request'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 3
         AND bool_and(NOT (metadata ? 'email'))
         AND bool_and(NOT (metadata ? 'phone'))
         AND bool_and(NOT (metadata ? 'phone_e164'))
         AND bool_and(NOT (metadata ? 'first_name'))
         AND bool_and(metadata ->> 'deduplicated' = 'false')
         AND bool_and(position('idem@example.com' IN metadata::text) = 0)
         AND bool_and(position('+573001010101' IN metadata::text) = 0)
       FROM audit.audit_events
       WHERE organization_id = %L::uuid
         AND event_type = 'request_received'$q$,
    :'org_id'
  ),
  'each new request writes request_received without PII in metadata'
);

ROLLBACK;
