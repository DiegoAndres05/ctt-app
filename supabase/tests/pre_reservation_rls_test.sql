-- pre_reservation_rls_test.sql
-- RLS and privilege tests for pre-reservations foundational tables
-- Run with: ./supabase/tests/run-sql-tests.sh pre_reservation_rls_test.sql

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id         04000000-0000-4000-a000-000000000011
\set org_b_id       04000000-0000-4000-a000-000000000012
\set agent_id       04000000-0000-4000-b000-000000000011
\set operator_id    04000000-0000-4000-b000-000000000012
\set admin_id       04000000-0000-4000-b000-000000000013
\set agent_b_id     04000000-0000-4000-b000-000000000014
\set customer_id    04000000-0000-4000-c000-000000000011

-- Helper: add_collaborator
CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid,
  p_organization_id uuid,
  p_email text,
  p_full_name text,
  p_role public.app_role,
  p_status public.user_status DEFAULT 'active'
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
  VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, p_status, false);
END;
$$;

-- Helper: act_as
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

-- Setup: organizations and collaborators
INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_id'::uuid, 'RLS Test Org', 'rls-test-org', 'active', '{"default_phone_country_code":"57"}'::jsonb),
  (:'org_b_id'::uuid, 'RLS Test Org B', 'rls-test-org-b', 'active', '{"default_phone_country_code":"57"}'::jsonb);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-rls@test.invalid', 'Agent RLS', 'agent');
SELECT pg_temp.add_collaborator(:'operator_id'::uuid, :'org_id'::uuid, 'operator-rls@test.invalid', 'Operator RLS', 'operator');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-rls@test.invalid', 'Admin RLS', 'admin');
SELECT pg_temp.add_collaborator(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent-rls-b@test.invalid', 'Agent RLS B', 'agent');

-- Setup: customer
INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Test', 'Customer', 'test-rls@test.invalid', '+573001112233', :'agent_id'::uuid);

-- Setup: request
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Test","email":"test-rls@test.invalid","phone":"3001112233"}'::jsonb,
  '{"travel_start_date":"2027-03-15","adults":2}'::jsonb,
  '[{"free_text":"Test tour","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS req_id \gset

-- Setup: product (priced before activation, enforce_active_requires_price)
INSERT INTO public.products (id, organization_id, name, type, status)
VALUES (gen_random_uuid(), :'org_id'::uuid, 'RLS Tour', 'experience', 'draft')
RETURNING id AS product_id \gset

INSERT INTO public.pricing_schemes (organization_id, product_id, base_amount, charge_type, valid_from)
VALUES (:'org_id'::uuid, :'product_id', 100000, 'per_person', now() - interval '1 day');

UPDATE public.products SET status = 'active' WHERE id = :'product_id'::uuid;

-- Create a pre-reservation via internal function (as superuser)
SET LOCAL ROLE postgres;
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid,
  :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2027-03-15', 'adults', 2)
  )),
  :'agent_id'::uuid
) AS pr_result \gset

SELECT (:'pr_result'::jsonb ->> 'pre_reservation_id')::uuid AS pr_id \gset
SELECT id AS item_id FROM public.pre_reservation_items WHERE pre_reservation_id = :'pr_id'::uuid \gset

-- =============================================================================
-- TEST: anon has no privileges on tables
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT * FROM public.pre_reservations',
  'permission denied',
  'anon cannot SELECT pre_reservations'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.pre_reservation_items',
  'permission denied',
  'anon cannot SELECT pre_reservation_items'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.availability_verification_events',
  'permission denied',
  'anon cannot SELECT availability_verification_events'
);

-- =============================================================================
-- TEST: anon has no privileges on views
-- =============================================================================
SELECT tests.assert_raises(
  'SELECT * FROM public.pre_reservation_list',
  'permission denied',
  'anon cannot SELECT pre_reservation_list'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.availability_verification_queue',
  'permission denied',
  'anon cannot SELECT availability_verification_queue'
);

-- =============================================================================
-- TEST: authenticated user sees only their org's rows
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

-- Should see org A's pre-reservation
SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM public.pre_reservations$$
  ),
  'agent sees org A pre_reservations'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM public.pre_reservation_list$$
  ),
  'agent sees org A pre_reservation_list'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM public.availability_verification_queue$$
  ),
  'agent sees org A availability_verification_queue'
);

-- =============================================================================
-- TEST: authenticated user from org B sees only org B rows (none in this case)
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 0 FROM public.pre_reservations$$
  ),
  'agent B sees zero pre_reservations'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 0 FROM public.pre_reservation_list$$
  ),
  'agent B sees zero pre_reservation_list'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 0 FROM public.availability_verification_queue$$
  ),
  'agent B sees zero availability_verification_queue'
);

-- =============================================================================
-- TEST: authenticated cannot INSERT/UPDATE/DELETE on tables
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $$INSERT INTO public.pre_reservations (organization_id, reference, request_id, customer_id, responsible_agent_id, status)
       VALUES (%L::uuid, 'PRE-99999', %L::uuid, %L::uuid, %L::uuid, 'pending_verification')$$,
    :'org_id', :'req_id', :'customer_id', :'agent_id'
  ),
  'permission denied',
  'authenticated cannot INSERT pre_reservations'
);

SELECT tests.assert_raises(
  format(
    $$UPDATE public.pre_reservations SET reference = 'PRE-HACKED' WHERE id = %L::uuid$$,
    :'pr_id'
  ),
  'permission denied',
  'authenticated cannot UPDATE pre_reservations'
);

SELECT tests.assert_raises(
  format(
    $$DELETE FROM public.pre_reservations WHERE id = %L::uuid$$,
    :'pr_id'
  ),
  'permission denied',
  'authenticated cannot DELETE pre_reservations'
);

SELECT tests.assert_raises(
  format(
    $$INSERT INTO public.pre_reservation_items (organization_id, pre_reservation_id, position, item_kind, product_id, start_date, adults, children, quantity, verification_status)
       VALUES (%L::uuid, %L::uuid, 99, 'experience', %L::uuid, '2027-03-15', 1, 0, 1, 'pending')$$,
    :'org_id', :'pr_id', :'product_id'
  ),
  'permission denied',
  'authenticated cannot INSERT pre_reservation_items'
);

SELECT tests.assert_raises(
  format(
    $$UPDATE public.pre_reservation_items SET item_label = 'HACKED' WHERE id = %L::uuid$$,
    :'item_id'
  ),
  'permission denied',
  'authenticated cannot UPDATE pre_reservation_items'
);

SELECT tests.assert_raises(
  format(
    $$DELETE FROM public.pre_reservation_items WHERE id = %L::uuid$$,
    :'item_id'
  ),
  'permission denied',
  'authenticated cannot DELETE pre_reservation_items'
);

SELECT tests.assert_raises(
  'INSERT INTO public.availability_verification_events (organization_id, pre_reservation_id, event_kind, actor_id) VALUES (gen_random_uuid(), gen_random_uuid(), ' || '''item_added''' || ', gen_random_uuid())',
  'permission denied',
  'authenticated cannot INSERT availability_verification_events'
);

-- =============================================================================
-- TEST: availability_verification_events is append-only (UPDATE/DELETE/TRUNCATE fail even as superuser)
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE postgres;

SELECT tests.assert_raises(
  format(
    $$UPDATE public.availability_verification_events SET notes = 'HACKED' WHERE pre_reservation_id = %L::uuid$$,
    :'pr_id'
  ),
  'append-only',
  'UPDATE on availability_verification_events rejected even as superuser'
);

SELECT tests.assert_raises(
  format(
    $$DELETE FROM public.availability_verification_events WHERE pre_reservation_id = %L::uuid$$,
    :'pr_id'
  ),
  'append-only',
  'DELETE on availability_verification_events rejected even as superuser'
);

SELECT tests.assert_raises(
  'TRUNCATE public.availability_verification_events',
  'append-only',
  'TRUNCATE on availability_verification_events rejected even as superuser'
);

-- =============================================================================
-- TEST: RPC EXECUTE denied for anon and authenticated on internal functions
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT public.require_availability_verifier()',
  'permission denied',
  'anon cannot EXECUTE require_availability_verifier'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid, '{"product_id":"%s","start_date":"2027-03-15","adults":1}')$$,
    :'org_id', :'req_id', :'product_id'
  ),
  'permission denied',
  'anon cannot EXECUTE resolve_pre_reservation_item'
);

SELECT tests.assert_raises(
  'SELECT public.insert_pre_reservation_item(gen_random_uuid(), gen_random_uuid(), ' || '''{}''' || '::jsonb, NULL, gen_random_uuid())',
  'permission denied',
  'anon cannot EXECUTE insert_pre_reservation_item'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.refresh_pre_reservation_status(%L::uuid)$$,
    :'pr_id'
  ),
  'permission denied',
  'anon cannot EXECUTE refresh_pre_reservation_status'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-03-15","adults":1}]}', %L::uuid)$$,
    :'org_id', :'req_id', :'product_id', :'agent_id'
  ),
  'permission denied',
  'anon cannot EXECUTE create_pre_reservation_core'
);

-- Same for authenticated
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  'SELECT public.require_availability_verifier()',
  'permission denied',
  'authenticated cannot EXECUTE require_availability_verifier'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid, '{"product_id":"%s","start_date":"2027-03-15","adults":1}')$$,
    :'org_id', :'req_id', :'product_id'
  ),
  'permission denied',
  'authenticated cannot EXECUTE resolve_pre_reservation_item'
);

SELECT tests.assert_raises(
  'SELECT public.insert_pre_reservation_item(gen_random_uuid(), gen_random_uuid(), ' || '''{}''' || '::jsonb, NULL, gen_random_uuid())',
  'permission denied',
  'authenticated cannot EXECUTE insert_pre_reservation_item'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.refresh_pre_reservation_status(%L::uuid)$$,
    :'pr_id'
  ),
  'permission denied',
  'authenticated cannot EXECUTE refresh_pre_reservation_status'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-03-15","adults":1}]}', %L::uuid)$$,
    :'org_id', :'req_id', :'product_id', :'agent_id'
  ),
  'permission denied',
  'authenticated cannot EXECUTE create_pre_reservation_core'
);

-- =============================================================================
-- TEST: has_function_privilege confirms EXECUTE was revoked (T007)
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;

SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('public.require_availability_verifier()', 'EXECUTE')
       AND NOT has_function_privilege('public.resolve_pre_reservation_item(uuid,uuid,jsonb)', 'EXECUTE')
       AND NOT has_function_privilege('public.insert_pre_reservation_item(uuid,uuid,jsonb,uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.refresh_pre_reservation_status(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.create_pre_reservation_core(uuid,uuid,jsonb,uuid)', 'EXECUTE')$q$,
  'anon has no EXECUTE privilege on the five internal functions'
);

RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('public.require_availability_verifier()', 'EXECUTE')
       AND NOT has_function_privilege('public.resolve_pre_reservation_item(uuid,uuid,jsonb)', 'EXECUTE')
       AND NOT has_function_privilege('public.insert_pre_reservation_item(uuid,uuid,jsonb,uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.refresh_pre_reservation_status(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.create_pre_reservation_core(uuid,uuid,jsonb,uuid)', 'EXECUTE')$q$,
  'authenticated has no EXECUTE privilege on the five internal functions'
);

-- =============================================================================
-- TEST: Superuser UPDATE on pre_reservations changing reference -> VALIDATION_ERROR
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE postgres;

SELECT tests.assert_raises(
  format(
    $$UPDATE public.pre_reservations SET reference = 'PRE-HACKED' WHERE id = %L::uuid$$,
    :'pr_id'
  ),
  'VALIDATION_ERROR',
  'superuser UPDATE changing reference rejected by trigger'
);

-- =============================================================================
-- TEST: Superuser UPDATE on pre_reservation_items changing start_date -> VALIDATION_ERROR
-- =============================================================================
SELECT tests.assert_raises(
  format(
    $$UPDATE public.pre_reservation_items SET start_date = '2020-01-01' WHERE id = %L::uuid$$,
    :'item_id'
  ),
  'VALIDATION_ERROR',
  'superuser UPDATE changing start_date rejected by trigger'
);

RESET ROLE;
ROLLBACK;