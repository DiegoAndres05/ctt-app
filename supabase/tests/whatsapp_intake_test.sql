-- whatsapp_intake_test.sql
-- Assisted capture as an agent, and ingest_whatsapp_webhook as service_role.
-- The inbound JSON is the text-message fixture, with the test phone_number_id.
--
-- Run with: ./supabase/tests/run-sql-tests.sh whatsapp_intake_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id      03000000-0000-4000-a000-000000000031
\set org_b_id    03000000-0000-4000-a000-000000000032
\set agent_id    03000000-0000-4000-b000-000000000031
\set agent_b_id  03000000-0000-4000-b000-000000000032
\set operator_id 03000000-0000-4000-b000-000000000033
\set operator_b_id 03000000-0000-4000-b000-000000000034

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
    :'org_id'::uuid, 'WhatsApp Intake', 'wa-intake', 'active',
    '{"default_phone_country_code":"57"}'::jsonb
  ),
  (
    :'org_b_id'::uuid, 'WhatsApp Other', 'wa-other', 'active',
    '{"default_phone_country_code":"57"}'::jsonb
  );

SELECT pg_temp.add_collaborator(
  :'agent_id'::uuid, :'org_id'::uuid, 'agente-wa@test.invalid', 'Agente WA', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'agent_b_id'::uuid, :'org_b_id'::uuid, 'agente-wa-b@test.invalid', 'Agente WB', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid, 'operador-wa@test.invalid', 'Operador WA', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'operator_b_id'::uuid, :'org_b_id'::uuid, 'operador-wa-b@test.invalid', 'Operador WB', 'operator'
);

SELECT public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Cliente Local","phone":"+573001234567"}'::jsonb,
  '{"special_requirements":"Ya existía"}'::jsonb,
  '[{"free_text":"Previos","quantity":1}]'::jsonb,
  NULL
);

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience', 'WA Active', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 60, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 8
  ),
  NULL
) ->> 'id') AS active_product \gset

SELECT (public.create_product(
  'experience', 'WA Inactive', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 60, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 8
  ),
  NULL
) ->> 'id') AS inactive_product \gset

RESET ROLE;
SELECT pg_temp.act_as(:'operator_b_id'::uuid, :'org_b_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience', 'WA Foreign', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 60, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 8
  ),
  NULL
) ->> 'id') AS foreign_product \gset

RESET ROLE;

UPDATE public.products
SET status = 'inactive'
WHERE id = :'inactive_product'::uuid;

INSERT INTO public.channel_connections (
  organization_id, channel, provider, external_account_id, display_phone, status
)
VALUES (
  :'org_id'::uuid, 'whatsapp', 'meta_cloud', 'wa-test-phone-number-id', '+57 300 000 0001', 'active'
);

SELECT (
  SELECT id FROM public.customers
  WHERE organization_id = :'org_id'::uuid AND phone_e164 = '+573001234567'
) AS existing_customer \gset

SELECT public.capture_request_core(
  :'org_b_id'::uuid, 'phone', NULL,
  '{"first_name":"Foráneo","phone":"+573009991111"}'::jsonb,
  '{"special_requirements":"Otra org"}'::jsonb,
  '[{"free_text":"Otra","quantity":1}]'::jsonb,
  NULL
) ->> 'customer_id' AS foreign_customer \gset

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT (public.create_assisted_request(jsonb_build_object(
  'channel', 'whatsapp',
  'privacy_notice_given', true,
  'contact', jsonb_build_object('first_name', 'Alguien', 'phone', '3001234567'),
  'items', jsonb_build_array(jsonb_build_object('free_text', 'Cena romántica', 'quantity', 1))
)) ->> 'request_id') AS assisted_id \gset

SELECT tests.assert_raises(
  $$SELECT public.create_assisted_request(jsonb_build_object(
      'channel', 'whatsapp',
      'privacy_notice_given', false,
      'contact', jsonb_build_object('first_name', 'Ana', 'phone', '3000000001'),
      'items', jsonb_build_array(jsonb_build_object('free_text', 'Tour', 'quantity', 1))
    ))$$,
  'CONSENT_REQUIRED',
  'assisted intake requires privacy_notice_given'
);

SELECT tests.assert_raises(
  $$SELECT public.create_assisted_request(jsonb_build_object(
      'channel', 'web',
      'privacy_notice_given', true,
      'contact', jsonb_build_object('first_name', 'Ana', 'phone', '3000000002'),
      'items', jsonb_build_array(jsonb_build_object('free_text', 'Tour', 'quantity', 1))
    ))$$,
  'VALIDATION_ERROR',
  'assisted intake rejects the web channel'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_assisted_request(jsonb_build_object(
        'channel', 'phone',
        'privacy_notice_given', true,
        'customer_id', %L::uuid,
        'items', jsonb_build_array(jsonb_build_object('free_text', 'Tour', 'quantity', 1))
      ))$$,
    :'foreign_customer'
  ),
  'VALIDATION_ERROR',
  'assisted intake rejects a customer from another organization'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_assisted_request(jsonb_build_object(
        'channel', 'phone',
        'privacy_notice_given', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'phone', '3000000003'),
        'items', jsonb_build_array(jsonb_build_object('product_id', %L::uuid, 'quantity', 1))
      ))$$,
    :'inactive_product'
  ),
  'VALIDATION_ERROR',
  'assisted intake rejects an inactive product'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_assisted_request(jsonb_build_object(
        'channel', 'phone',
        'privacy_notice_given', true,
        'contact', jsonb_build_object('first_name', 'Ana', 'phone', '3000000004'),
        'items', jsonb_build_array(jsonb_build_object('product_id', %L::uuid, 'quantity', 1))
      ))$$,
    :'foreign_product'
  ),
  'VALIDATION_ERROR',
  'assisted intake rejects a product from another organization'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT r.assigned_to = %L::uuid
         AND r.channel = 'whatsapp'
         AND r.customer_id = %L::uuid
         AND (
           SELECT count(*) FROM public.customers
           WHERE organization_id = %L::uuid AND phone_e164 = '+573001234567'
         ) = 1
       FROM public.customer_requests r
       WHERE r.id = %L::uuid$$,
    :'agent_id', :'existing_customer', :'org_id', :'assisted_id'
  ),
  'a local phone links the existing customer and assigns the request to the agent'
);

SELECT tests.assert_true(
  $$SELECT NOT has_function_privilege('anon', 'public.create_assisted_request(jsonb)', 'EXECUTE')$$,
  'anon cannot execute create_assisted_request'
);

SELECT pg_temp.clear_jwt();
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  $$SELECT public.create_assisted_request('{}'::jsonb)$$,
  'permission denied',
  'anon is rejected when calling create_assisted_request'
);

RESET ROLE;

-- Fixture from supabase/functions/whatsapp-inbound/fixtures/text-message.json
-- phone_number_id points at this suite's connection.
\set fixture '{"object":"whatsapp_business_account","entry":[{"id":"local-dev-waba","changes":[{"field":"messages","value":{"messaging_product":"whatsapp","metadata":{"display_phone_number":"573000000000","phone_number_id":"wa-test-phone-number-id"},"contacts":[{"profile":{"name":"María Pérez"},"wa_id":"573009998877"}],"messages":[{"from":"573009998877","id":"wamid.local-1","timestamp":"1790000000","type":"text","text":{"body":"Hola, quiero info del tour a Islas del Rosario para 2 personas"}}]}}]}]}'

SET LOCAL ROLE service_role;

SELECT public.ingest_whatsapp_webhook(:'fixture'::jsonb) AS first_ingest \gset

SELECT public.ingest_whatsapp_webhook(:'fixture'::jsonb) AS retry_ingest \gset

SELECT public.ingest_whatsapp_webhook(
  jsonb_set(:'fixture'::jsonb, '{entry,0,changes,0,value,messages,0,id}', '"wamid.local-2"')
) AS second_ingest \gset

SELECT public.ingest_whatsapp_webhook(
  '{"object":"whatsapp_business_account","entry":[{"changes":[{"field":"messages","value":{"metadata":{"phone_number_id":"wa-test-phone-number-id"},"contacts":[{"profile":{"name":"María Pérez"},"wa_id":"573009998877"}],"messages":[{"from":"573009998877","id":"wamid.local-image","timestamp":"1790000001","type":"image"}]}}]}]}'::jsonb
) AS image_ingest \gset

RESET ROLE;

SELECT request_id AS open_request
FROM public.inbound_messages
WHERE provider_message_id = 'wamid.local-1' \gset

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT public.set_request_status(:'open_request'::uuid, 'discarded', 'Cerrada en la prueba');
RESET ROLE;

SET LOCAL ROLE service_role;

SELECT public.ingest_whatsapp_webhook(
  jsonb_set(:'fixture'::jsonb, '{entry,0,changes,0,value,messages,0,id}', '"wamid.local-3"')
) AS after_discard \gset

SELECT public.ingest_whatsapp_webhook(
  '{"object":"whatsapp_business_account","entry":[{"changes":[{"field":"messages","value":{"metadata":{"phone_number_id":"unknown-phone"},"messages":[{"from":"573001110000","id":"wamid.unknown","timestamp":"1790000002","type":"text","text":{"body":"hola"}}]}}]}]}'::jsonb
) AS unknown_phone \gset

SELECT public.ingest_whatsapp_webhook(
  '{"object":"whatsapp_business_account","entry":[{"changes":[{"field":"messages","value":{"metadata":{"phone_number_id":"wa-test-phone-number-id"},"statuses":[{"id":"wamid.local-1","status":"delivered"}]}}]}]}'::jsonb
) AS statuses_only \gset

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT (%L::jsonb ->> 'processed')::int = 1
         AND (%L::jsonb ->> 'requests_created')::int = 1
         AND (%L::jsonb ->> 'duplicates')::int = 0
         AND (%L::jsonb ->> 'processed')::int = 0
         AND (%L::jsonb ->> 'duplicates')::int = 1
         AND (%L::jsonb ->> 'messages_attached')::int = 1
         AND (%L::jsonb ->> 'requests_created')::int = 0
         AND (%L::jsonb ->> 'requests_created')::int = 1$$,
    :'first_ingest', :'first_ingest', :'first_ingest',
    :'retry_ingest', :'retry_ingest',
    :'second_ingest', :'second_ingest',
    :'after_discard'
  ),
  'ingest creates, deduplicates by wamid, attaches, and opens a new request after discard'
);

SELECT tests.assert_true(
  $$SELECT c.first_name = 'María Pérez'
       AND c.phone_e164 = '+573009998877'
       AND r.channel = 'whatsapp'
       AND r.status = 'discarded'
       AND r.special_requirements = 'Hola, quiero info del tour a Islas del Rosario para 2 personas'
       AND m.body = r.special_requirements
    FROM public.customers c
    JOIN public.customer_requests r ON r.customer_id = c.id
    JOIN public.inbound_messages m ON m.request_id = r.id
    WHERE c.phone_e164 = '+573009998877'
      AND m.provider_message_id = 'wamid.local-1'$$,
  'the text fixture creates the customer from the profile name and stores the message'
);

SELECT tests.assert_true(
  $$SELECT body = '[mensaje no soportado: image]'
    FROM public.inbound_messages
    WHERE provider_message_id = 'wamid.local-image'$$,
  'an image message is stored with the unsupported-message marker'
);

SELECT tests.assert_true(
  format(
    $$SELECT (%L::jsonb ->> 'ignored')::int = 1
         AND (%L::jsonb ->> 'processed')::int = 0
         AND (%L::jsonb ->> 'processed')::int = 0
         AND (%L::jsonb ->> 'ignored')::int = 0
         AND (%L::jsonb ->> 'duplicates')::int = 0$$,
    :'unknown_phone', :'unknown_phone',
    :'statuses_only', :'statuses_only', :'statuses_only'
  ),
  'an unknown phone_number_id is ignored and status callbacks create nothing'
);

SELECT tests.assert_equals(
  (
    SELECT count(*)
    FROM public.inbound_messages
    WHERE provider_message_id = 'wamid.local-1'
  ),
  1,
  'replaying the same wamid does not insert another message'
);

ROLLBACK;
