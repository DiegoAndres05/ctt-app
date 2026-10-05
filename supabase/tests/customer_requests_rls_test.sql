-- customer_requests_rls_test.sql
-- Tenant isolation, Default Deny for anon, no direct writes, and internal RPC grants.
-- US4 extends this file with inbound_messages, channel_connections, request_notes, and
-- the public/authenticated/service_role execute matrix.
--
-- Run with: ./supabase/tests/run-sql-tests.sh customer_requests_rls_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a      03000000-0000-4000-a000-000000000011
\set org_b      03000000-0000-4000-a000-000000000012
\set agent_a    03000000-0000-4000-b000-000000000011

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
    jsonb_strip_nulls(jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'app_role', p_app_role,
      'organization_id', p_organization_id::text
    ))::text,
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
  (:'org_a'::uuid, 'Requests A', 'requests-a', 'active', '{"default_phone_country_code":"57"}'::jsonb),
  (:'org_b'::uuid, 'Requests B', 'requests-b', 'active', '{"default_phone_country_code":"57"}'::jsonb);

SELECT pg_temp.add_collaborator(
  :'agent_a'::uuid, :'org_a'::uuid, 'agent-a-requests@test.invalid', 'Agente A', 'agent'
);
SELECT pg_temp.add_collaborator(
  '03000000-0000-4000-b000-000000000012'::uuid, :'org_b'::uuid,
  'agent-b-requests@test.invalid', 'Agente B', 'agent'
);

INSERT INTO public.channel_connections (
  organization_id, channel, provider, external_account_id, status
)
VALUES
  (:'org_a'::uuid, 'whatsapp', 'meta_cloud', 'rls-phone-a', 'active'),
  (:'org_b'::uuid, 'whatsapp', 'meta_cloud', 'rls-phone-b', 'active');

SELECT (
  public.capture_request_core(
    :'org_a'::uuid, 'phone', NULL,
    '{"first_name":"Ana","phone":"3001110001"}'::jsonb,
    '{"special_requirements":"Org A"}'::jsonb,
    '[{"free_text":"Tour A","quantity":1}]'::jsonb,
    NULL
  ) ->> 'request_id'
) AS request_a \gset

SELECT (
  public.capture_request_core(
    :'org_b'::uuid, 'phone', NULL,
    '{"first_name":"Bea","phone":"3001110002"}'::jsonb,
    '{"special_requirements":"Org B"}'::jsonb,
    '[{"free_text":"Tour B","quantity":1}]'::jsonb,
    NULL
  ) ->> 'request_id'
) AS request_b \gset

INSERT INTO public.inbound_messages (
  organization_id, connection_id, channel, provider, provider_message_id,
  from_phone_e164, profile_name, message_type, body, provider_timestamp,
  customer_id, request_id
)
SELECT
  r.organization_id, c.id, 'whatsapp', 'meta_cloud', 'wamid.rls-' || r.organization_id::text,
  '+573001110099', 'Contacto', 'text', 'Hola', now(), r.customer_id, r.id
FROM public.customer_requests r
JOIN public.channel_connections c ON c.organization_id = r.organization_id
WHERE r.id IN (:'request_a'::uuid, :'request_b'::uuid);

INSERT INTO public.request_notes (organization_id, request_id, author_id, content)
SELECT r.organization_id, r.id, :'agent_a'::uuid, 'Nota A'
FROM public.customer_requests r
WHERE r.id = :'request_a'::uuid;

INSERT INTO public.request_notes (organization_id, request_id, author_id, content)
SELECT r.organization_id, r.id, '03000000-0000-4000-b000-000000000012'::uuid, 'Nota B'
FROM public.customer_requests r
WHERE r.id = :'request_b'::uuid;

SELECT tests.assert_true(
  $$SELECT NOT has_function_privilege(
         'anon',
         'public.capture_request_core(uuid, public.request_channel, uuid, jsonb, jsonb, jsonb, uuid)',
         'EXECUTE'
       )
       AND NOT has_function_privilege(
         'authenticated',
         'public.capture_request_core(uuid, public.request_channel, uuid, jsonb, jsonb, jsonb, uuid)',
         'EXECUTE'
       )
       AND NOT has_function_privilege('anon', 'public.match_or_create_customer(uuid, jsonb, uuid)', 'EXECUTE')
       AND NOT has_function_privilege(
         'authenticated', 'public.match_or_create_customer(uuid, jsonb, uuid)', 'EXECUTE'
       )
       AND NOT has_function_privilege('anon', 'public.normalize_phone_e164(text, text)', 'EXECUTE')
       AND NOT has_function_privilege('authenticated', 'public.normalize_phone_e164(text, text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.require_tenant_member()', 'EXECUTE')
       AND NOT has_function_privilege('authenticated', 'public.require_tenant_member()', 'EXECUTE')$$,
  'anon and authenticated cannot execute internal intake functions'
);

SELECT tests.assert_raises(
  format(
    $$UPDATE public.customer_requests SET channel = 'web' WHERE id = %L::uuid$$,
    :'request_a'
  ),
  'VALIDATION_ERROR',
  'channel cannot be changed, even by the table owner'
);

SELECT pg_temp.clear_jwt();
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.customers',
  'permission denied',
  'anon cannot select customers'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.customer_requests',
  'permission denied',
  'anon cannot select customer_requests'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.customer_request_items',
  'permission denied',
  'anon cannot select customer_request_items'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.customer_request_list',
  'permission denied',
  'anon cannot select customer_request_list'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.customer_list',
  'permission denied',
  'anon cannot select customer_list'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.inbound_messages',
  'permission denied',
  'anon cannot select inbound_messages'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.channel_connections',
  'permission denied',
  'anon cannot select channel_connections'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.request_notes',
  'permission denied',
  'anon cannot select request_notes'
);

RESET ROLE;
SELECT pg_temp.act_as(:'agent_a'::uuid, :'org_a'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.customers),
  1,
  'authenticated sees only customers of their organization'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.customer_requests),
  1,
  'authenticated sees only requests of their organization'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.customer_request_items),
  1,
  'authenticated sees only request items of their organization'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.customer_request_list),
  1,
  'request list view is limited to the caller tenant'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.customer_list),
  1,
  'customer list view is limited to the caller tenant'
);

SELECT tests.assert_true(
  format(
    $$SELECT NOT EXISTS (SELECT 1 FROM public.customer_requests WHERE id = %L::uuid)$$,
    :'request_b'
  ),
  'a request from another organization is invisible'
);

SELECT tests.assert_raises(
  format(
    $$INSERT INTO public.customers (organization_id, first_name, email)
      VALUES (%L::uuid, 'Intruso', 'intruso@test.invalid')$$,
    :'org_a'
  ),
  'permission denied',
  'authenticated cannot insert customers'
);

SELECT tests.assert_raises(
  $$UPDATE public.customers SET first_name = 'Cambiado'$$,
  'permission denied',
  'authenticated cannot update customers'
);

SELECT tests.assert_raises(
  'DELETE FROM public.customers',
  'permission denied',
  'authenticated cannot delete customers'
);

SELECT tests.assert_raises(
  format(
    $$INSERT INTO public.customer_requests (
        organization_id, reference, customer_id, channel, dedup_fingerprint
      )
      SELECT organization_id, 'SOL-99999', id, 'phone', 'fp'
      FROM public.customers LIMIT 1$$
  ),
  'permission denied',
  'authenticated cannot insert customer_requests'
);

SELECT tests.assert_raises(
  $$UPDATE public.customer_requests SET adults = 2$$,
  'permission denied',
  'authenticated cannot update customer_requests'
);

SELECT tests.assert_raises(
  'DELETE FROM public.customer_requests',
  'permission denied',
  'authenticated cannot delete customer_requests'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.inbound_messages),
  1,
  'authenticated sees only inbound messages of their organization'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.channel_connections),
  1,
  'authenticated sees only channel connections of their organization'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.request_notes),
  1,
  'authenticated sees only notes of their organization'
);

SELECT tests.assert_raises(
  $$INSERT INTO public.request_notes (organization_id, request_id, author_id, content)
    SELECT organization_id, id, assigned_to, 'Directa'
    FROM public.customer_requests
    WHERE assigned_to IS NOT NULL
    LIMIT 1$$,
  'permission denied',
  'authenticated cannot insert request_notes'
);

SELECT tests.assert_raises(
  $$UPDATE public.inbound_messages SET body = 'Cambiado'$$,
  'permission denied',
  'authenticated cannot update inbound_messages'
);

SELECT tests.assert_raises(
  'DELETE FROM public.channel_connections',
  'permission denied',
  'authenticated cannot delete channel_connections'
);

RESET ROLE;

SELECT tests.assert_true(
  $$SELECT has_function_privilege(
         'anon', 'public.submit_public_request(uuid, jsonb)', 'EXECUTE'
       )
       AND has_function_privilege(
         'anon', 'public.get_public_site(uuid)', 'EXECUTE'
       )
       AND NOT has_function_privilege('anon', 'public.create_assisted_request(jsonb)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.update_customer(uuid, jsonb)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.assign_request(uuid, uuid)', 'EXECUTE')
       AND NOT has_function_privilege(
         'anon',
         'public.set_request_status(uuid, public.request_status, text)',
         'EXECUTE'
       )
       AND NOT has_function_privilege('anon', 'public.add_request_note(uuid, uuid, text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.anonymize_customer(uuid, text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.ingest_whatsapp_webhook(jsonb)', 'EXECUTE')
       AND has_function_privilege(
         'authenticated', 'public.create_assisted_request(jsonb)', 'EXECUTE'
       )
       AND has_function_privilege('authenticated', 'public.update_customer(uuid, jsonb)', 'EXECUTE')
       AND has_function_privilege('authenticated', 'public.assign_request(uuid, uuid)', 'EXECUTE')
       AND has_function_privilege(
         'authenticated',
         'public.set_request_status(uuid, public.request_status, text)',
         'EXECUTE'
       )
       AND has_function_privilege(
         'authenticated', 'public.add_request_note(uuid, uuid, text)', 'EXECUTE'
       )
       AND has_function_privilege(
         'authenticated', 'public.anonymize_customer(uuid, text)', 'EXECUTE'
       )
       AND NOT has_function_privilege(
         'authenticated', 'public.ingest_whatsapp_webhook(jsonb)', 'EXECUTE'
       )
       AND has_function_privilege(
         'service_role', 'public.ingest_whatsapp_webhook(jsonb)', 'EXECUTE'
       )
       AND NOT has_function_privilege(
         'anon', 'public.capture_request_core(uuid, public.request_channel, uuid, jsonb, jsonb, jsonb, uuid)',
         'EXECUTE'
       )$$,
  'execute grants match the public, collaborator, and service_role boundaries'
);

ROLLBACK;
