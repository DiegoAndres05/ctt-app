-- customer_privacy_test.sql
-- Admin-only anonymization. Internal notes stay; customer-authored text is scrubbed.
--
-- Run with: ./supabase/tests/run-sql-tests.sh customer_privacy_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id    03000000-0000-4000-a000-000000000051
\set org_b_id  03000000-0000-4000-a000-000000000052
\set admin_id  03000000-0000-4000-b000-000000000051
\set agent_id  03000000-0000-4000-b000-000000000052
\set operator_id 03000000-0000-4000-b000-000000000053
\set admin_b_id  03000000-0000-4000-b000-000000000054

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

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (
    :'org_id'::uuid, 'Privacy', 'privacy-org', 'active',
    '{"default_phone_country_code":"57"}'::jsonb
  ),
  (
    :'org_b_id'::uuid, 'Privacy B', 'privacy-org-b', 'active',
    '{"default_phone_country_code":"57"}'::jsonb
  );

SELECT pg_temp.add_collaborator(
  :'admin_id'::uuid, :'org_id'::uuid, 'admin-priv@test.invalid', 'Admin Priv', 'admin'
);
SELECT pg_temp.add_collaborator(
  :'agent_id'::uuid, :'org_id'::uuid, 'agente-priv@test.invalid', 'Agente Priv', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid, 'operador-priv@test.invalid', 'Operador Priv', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'admin_b_id'::uuid, :'org_b_id'::uuid, 'admin-priv-b@test.invalid', 'Admin Priv B', 'admin'
);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'whatsapp', NULL,
  '{"first_name":"Privado Nombre","last_name":"Secreto","email":"privacy-ana@test.invalid","phone":"+573009990001","country_code":"CO"}'::jsonb,
  '{"special_requirements":"Texto del cliente","travel_start_date":"2027-09-01","adults":2,"children":1,"privacy_consent_at":"2026-10-01T12:00:00Z"}'::jsonb,
  '[{"free_text":"Interés libre","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'customer_id') AS customer_id \gset

SELECT id AS request_id
FROM public.customer_requests
WHERE customer_id = :'customer_id'::uuid \gset

UPDATE public.customers
SET document_type = 'cc',
    document_number = '1234567890'
WHERE id = :'customer_id'::uuid;

UPDATE public.customer_requests
SET submitted_contact = '{"first_name":"Privado Nombre","email":"privacy-ana@test.invalid"}'::jsonb
WHERE id = :'request_id'::uuid;

INSERT INTO public.channel_connections (
  organization_id, channel, provider, external_account_id, status
)
VALUES (
  :'org_id'::uuid, 'whatsapp', 'meta_cloud', 'privacy-phone-number-id', 'active'
);

INSERT INTO public.inbound_messages (
  organization_id, connection_id, channel, provider, provider_message_id,
  from_phone_e164, profile_name, message_type, body, provider_timestamp,
  customer_id, request_id
)
SELECT
  :'org_id'::uuid, c.id, 'whatsapp', 'meta_cloud', 'wamid.privacy-1',
  '+573009990001', 'Privado Nombre', 'text', 'Mensaje privado del cliente', now(),
  :'customer_id'::uuid, :'request_id'::uuid
FROM public.channel_connections c
WHERE c.external_account_id = 'privacy-phone-number-id';

SELECT public.capture_request_core(
  :'org_b_id'::uuid, 'phone', NULL,
  '{"first_name":"Otra Org","phone":"+573008880002"}'::jsonb,
  '{"special_requirements":"Ajena"}'::jsonb,
  '[{"free_text":"Ajena","quantity":1}]'::jsonb,
  NULL
) ->> 'customer_id' AS foreign_customer \gset

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT public.add_request_note(NULL, :'customer_id'::uuid, 'Nota interna que se conserva');
RESET ROLE;

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises(
  format($$SELECT public.anonymize_customer(%L::uuid, 'motivo')$$, :'customer_id'),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot anonymize a customer'
);
RESET ROLE;

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises(
  format($$SELECT public.anonymize_customer(%L::uuid, 'motivo')$$, :'customer_id'),
  'INSUFFICIENT_PERMISSIONS',
  'an operator cannot anonymize a customer'
);
RESET ROLE;

SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format($$SELECT public.anonymize_customer(%L::uuid, '   ')$$, :'customer_id'),
  'VALIDATION_ERROR',
  'anonymization requires a reason'
);

SELECT tests.assert_raises(
  format($$SELECT public.anonymize_customer(%L::uuid, 'No es mío')$$, :'foreign_customer'),
  'VALIDATION_ERROR',
  'an admin cannot anonymize a customer from another organization'
);

SELECT public.anonymize_customer(:'customer_id'::uuid, 'Solicitud del titular');

SELECT tests.assert_raises(
  format($$SELECT public.anonymize_customer(%L::uuid, 'Otra vez')$$, :'customer_id'),
  'CUSTOMER_ANONYMIZED',
  'a customer cannot be anonymized twice'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.update_customer(%L::uuid, jsonb_build_object(
        'first_name', 'Nuevo', 'email', 'nuevo@test.invalid'
      ))$$,
    :'customer_id'
  ),
  'CUSTOMER_ANONYMIZED',
  'an anonymized customer cannot be edited'
);

RESET ROLE;
SELECT pg_temp.clear_jwt();
SET LOCAL ROLE anon;

SELECT public.submit_public_request(
  :'org_id'::uuid,
  jsonb_build_object(
    'privacy_consent', true,
    'contact', jsonb_build_object(
      'first_name', 'Ana Nueva',
      'email', 'privacy-ana@test.invalid'
    ),
    'interest_text', 'Quiero volver a escribir'
  )
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT first_name = 'Cliente anonimizado'
         AND last_name IS NULL
         AND email IS NULL
         AND phone_e164 IS NULL
         AND document_type IS NULL
         AND document_number IS NULL
         AND country_code IS NULL
         AND is_anonymized
         AND anonymized_at IS NOT NULL
       FROM public.customers
       WHERE id = %L::uuid$$,
    :'customer_id'
  ),
  'anonymization clears identity fields and marks the customer'
);

SELECT tests.assert_true(
  format(
    $$SELECT r.channel = 'whatsapp'
         AND r.status = 'received'
         AND r.travel_start_date = '2027-09-01'
         AND r.adults = 2
         AND r.children = 1
         AND r.submitted_contact IS NULL
         AND r.special_requirements = '[anonimizado]'
         AND i.free_text = '[anonimizado]'
       FROM public.customer_requests r
       JOIN public.customer_request_items i ON i.request_id = r.id
       WHERE r.id = %L::uuid$$,
    :'request_id'
  ),
  'commercial fields stay and customer-authored text is replaced'
);

SELECT tests.assert_true(
  $$SELECT body = '[anonimizado]'
       AND from_phone_e164 IS NULL
       AND profile_name IS NULL
    FROM public.inbound_messages
    WHERE provider_message_id = 'wamid.privacy-1'$$,
  'inbound message text and profile fields are scrubbed'
);

SELECT tests.assert_true(
  format(
    $$SELECT content = 'Nota interna que se conserva'
       FROM public.request_notes
       WHERE customer_id = %L::uuid$$,
    :'customer_id'
  ),
  'internal notes are kept'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1
         AND bool_and(NOT is_anonymized)
         AND bool_and(id <> %L::uuid)
      FROM public.customers
      WHERE email = 'privacy-ana@test.invalid'$$,
    :'customer_id'
  ),
  'the original email can register a new customer after anonymization'
);

SELECT tests.assert_equals(
  (
    SELECT count(*)
    FROM audit.audit_events
    WHERE event_type = 'customer_anonymized'
      AND resource_id = :'customer_id'::uuid
  ),
  1,
  'anonymization writes a single audit event'
);

SELECT tests.assert_true(
  format(
    $$SELECT metadata::text NOT ILIKE '%%privacy-ana@test.invalid%%'
         AND metadata::text NOT ILIKE '%%573009990001%%'
         AND metadata::text NOT ILIKE '%%Privado Nombre%%'
         AND metadata::text NOT ILIKE '%%Solicitud del titular%%'
       FROM audit.audit_events
       WHERE event_type = 'customer_anonymized'
         AND resource_id = %L::uuid$$,
    :'customer_id'
  ),
  'anonymization audit metadata omits contact, name, and the reason text'
);

ROLLBACK;
