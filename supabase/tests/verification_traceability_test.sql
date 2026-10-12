-- verification_traceability_test.sql
-- US4 (T038): availability_verification_history and pre_reservation_verification_times
-- plus the full create -> start -> results -> withdraw -> promote event chain.
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/verification_traceability_test.sql

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id          07000000-0000-4000-a000-000000000001
\set org_b_id        07000000-0000-4000-a000-000000000002
\set agent_id        07000000-0000-4000-b000-000000000001
\set operator1_id    07000000-0000-4000-b000-000000000002
\set operator2_id    07000000-0000-4000-b000-000000000003
\set admin_id        07000000-0000-4000-b000-000000000004
\set agent_b_id      07000000-0000-4000-b000-000000000005
\set customer_id     07000000-0000-4000-c000-000000000001
\set product_id      07000000-0000-4000-d000-000000000001

-- Helper: add_collaborator (copied from pre_reservation_core_test.sql)
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

-- Helper: act_as (copied from pre_reservation_core_test.sql)
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

-- =============================================================================
-- Setup: organizations, collaborators, customer, product, request
-- =============================================================================
INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_id'::uuid, 'Traceability Test Org', 'traceability-test-org', 'active', '{"default_phone_country_code":"57"}'::jsonb),
  (:'org_b_id'::uuid, 'Traceability Test Org B', 'traceability-test-org-b', 'active', '{"default_phone_country_code":"57"}'::jsonb);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-traceability@test.invalid', 'Agent Traceability', 'agent');
SELECT pg_temp.add_collaborator(:'operator1_id'::uuid, :'org_id'::uuid, 'operator1-traceability@test.invalid', 'Operator One Traceability', 'operator');
SELECT pg_temp.add_collaborator(:'operator2_id'::uuid, :'org_id'::uuid, 'operator2-traceability@test.invalid', 'Operator Two Traceability', 'operator');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-traceability@test.invalid', 'Admin Traceability', 'admin');
SELECT pg_temp.add_collaborator(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent-traceability-b@test.invalid', 'Agent Traceability B', 'agent');

INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Nadia', 'Cortés', 'nadia-traceability@test.invalid', '+573004445566', :'agent_id'::uuid);

-- Products must be priced before they can be active (enforce_active_requires_price).
INSERT INTO public.products (id, organization_id, name, type, status)
VALUES (:'product_id'::uuid, :'org_id'::uuid, 'Sabana Tour', 'experience', 'draft');

INSERT INTO public.pricing_schemes (organization_id, product_id, base_amount, charge_type, valid_from)
VALUES (:'org_id'::uuid, :'product_id'::uuid, 110000, 'per_person', now() - interval '1 day');

UPDATE public.products SET status = 'active' WHERE id = :'product_id'::uuid;

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Nadia","email":"nadia-traceability@test.invalid","phone":"3004445566"}'::jsonb,
  '{"travel_start_date":"2028-10-01","travel_end_date":"2028-10-04","adults":2}'::jsonb,
  ('[{"product_id":"' || :'product_id' || '","quantity":1}]')::jsonb,
  NULL
) ->> 'request_id') AS req_id \gset

-- =============================================================================
-- Setup: the scenario pre-reservations
-- =============================================================================
-- verification times: two lines verified by two different operators
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-10-01', 'adults', 1),
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-10-02', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_times \gset

-- event chain: two mains, an alternative added during the sequence
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-10-03', 'adults', 1),
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-10-04', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_chain \gset

SELECT (array_agg(id ORDER BY position))[1] AS item_t1_id,
       (array_agg(id ORDER BY position))[2] AS item_t2_id
FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_times'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT (array_agg(id ORDER BY position))[1] AS item_c1_id,
       (array_agg(id ORDER BY position))[2] AS item_c2_id
FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_chain'::jsonb ->> 'pre_reservation_id')::uuid \gset

-- =============================================================================
-- TEST: both views are closed to anon (T038)
-- =============================================================================
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT * FROM public.availability_verification_history',
  'permission denied',
  'anon cannot SELECT availability_verification_history'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.pre_reservation_verification_times',
  'permission denied',
  'anon cannot SELECT pre_reservation_verification_times'
);

SELECT tests.assert_true(
  $q$SELECT NOT has_table_privilege('public.availability_verification_history', 'SELECT')
       AND NOT has_table_privilege('public.pre_reservation_verification_times', 'SELECT')$q$,
  'anon has no SELECT privilege on either view'
);

RESET ROLE;

-- =============================================================================
-- TEST: verification times report both verifiers and the elapsed hours (T038)
-- =============================================================================
SELECT pg_temp.act_as(:'operator1_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.record_item_verification(
  :'item_t1_id'::uuid,
  jsonb_build_object(
    'status', 'available',
    'contact_person', 'Andrés (recepción)',
    'contact_method', 'phone',
    'hold_expires_at', (now() + interval '3 days')::text
  )
);

RESET ROLE;
SELECT pg_temp.act_as(:'operator2_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.record_item_verification(
  :'item_t2_id'::uuid,
  jsonb_build_object(
    'status', 'available',
    'contact_person', 'Beatriz (reservas)',
    'contact_method', 'whatsapp',
    'hold_expires_at', (now() + interval '4 days')::text
  )
);

-- The elapsed hours must be measurable, so stage explicit stamps on top of now()
RESET ROLE;

UPDATE public.pre_reservation_items
SET verification_started_at = (SELECT created_at FROM public.pre_reservations WHERE id = (:'pr_times'::jsonb ->> 'pre_reservation_id')::uuid) + interval '2 hours'
WHERE pre_reservation_id = (:'pr_times'::jsonb ->> 'pre_reservation_id')::uuid;

UPDATE public.pre_reservations
SET first_verified_at = created_at + interval '5 hours'
WHERE id = (:'pr_times'::jsonb ->> 'pre_reservation_id')::uuid;

SELECT tests.assert_true(
  format(
    $q$SELECT first_started_at = created_at + interval '2 hours'
         AND first_verified_at = created_at + interval '5 hours'
         AND hours_to_first_start = 2
         AND hours_to_verified = 5
         AND item_count = 2
         AND verifier_count = 2
         AND status = 'verified'
       FROM public.pre_reservation_verification_times
       WHERE id = %L::uuid$q$,
    (:'pr_times'::jsonb ->> 'pre_reservation_id')
  ),
  'verification times compute hours, item_count and two verifiers'
);

SELECT pg_temp.act_as(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent');
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT * FROM public.availability_verification_history',
  'permission denied',
  'anon cannot read the history view after the data exists'
);

RESET ROLE;
SELECT pg_temp.act_as(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  $$SELECT count(*) = 0 FROM public.availability_verification_history$$,
  'another tenant sees no history rows'
);

SELECT tests.assert_true(
  $$SELECT count(*) = 0 FROM public.pre_reservation_verification_times$$,
  'another tenant sees no verification times'
);

RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format(
    $$SELECT count(*) > 0
         AND count(*) FILTER (WHERE organization_id = %L::uuid) = count(*)
       FROM public.availability_verification_history$$,
    :'org_id'
  ),
  'the owning tenant reads only its own history rows'
);

SELECT tests.assert_true(
  $q$SELECT count(*) > 0
       AND count(*) FILTER (WHERE actor_name IS NULL) = 0
       AND count(*) FILTER (WHERE item_id IS NOT NULL AND item_label IS NULL) = 0
    FROM public.availability_verification_history$q$,
  'every history row carries the actor name and the line label'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 1
       FROM public.availability_verification_history
       WHERE pre_reservation_id = %L::uuid
         AND event_kind = 'outcome_recorded'
         AND actor_name = 'Operator One Traceability'
         AND item_label IS NOT NULL
         AND from_status = 'pending'
         AND to_status = 'available'$q$,
    (:'pr_times'::jsonb ->> 'pre_reservation_id')
  ),
  'the history resolves the verifier name, the line label and the transition'
);

-- The list view exposes the same read to authenticated users
SELECT tests.assert_true(
  $q$SELECT count(*) > 0
       AND count(*) FILTER (WHERE hours_to_first_start IS NULL AND item_count IS NULL) = 0
    FROM public.pre_reservation_verification_times$q$,
  'the owning tenant reads its verification times'
);

-- =============================================================================
-- TEST: full sequence leaves one coherent event per action (T038)
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'operator1_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

-- 1. start the first line
SELECT public.start_item_verification(:'item_c1_id'::uuid);

-- 2. two outcomes: the pre-reservation becomes verified
SELECT public.record_item_verification(
  :'item_c1_id'::uuid,
  jsonb_build_object(
    'status', 'available',
    'contact_person', 'Carla (recepción)',
    'contact_method', 'email',
    'hold_expires_at', (now() + interval '3 days')::text
  )
);

SELECT public.record_item_verification(
  :'item_c2_id'::uuid,
  jsonb_build_object(
    'status', 'available',
    'contact_person', 'Diego (operaciones)',
    'contact_method', 'phone',
    'hold_expires_at', (now() + interval '4 days')::text
  )
);

RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

-- 3. an alternative line
SELECT public.add_pre_reservation_item(
  (:'pr_chain'::jsonb ->> 'pre_reservation_id')::uuid,
  jsonb_build_object(
    'product_id', :'product_id',
    'start_date', '2028-10-03',
    'adults', 1,
    'alternative_of_item_id', :'item_c1_id'
  )
) AS chain_alt \gset

-- 4. withdraw the second main line
SELECT public.withdraw_pre_reservation_item(:'item_c2_id'::uuid, 'Proveedor sin cupo');

-- 5. promote the alternative: the original main line goes away with it
SELECT public.promote_alternative_item((:'chain_alt'::jsonb ->> 'item_id')::uuid);

RESET ROLE;

SELECT tests.assert_equals(
  (SELECT count(*)
   FROM public.availability_verification_history
   WHERE pre_reservation_id = (:'pr_chain'::jsonb ->> 'pre_reservation_id')::uuid),
  9,
  'the full sequence writes exactly one event per action'
);

SELECT tests.assert_true(
  format(
    $q$SELECT array_agg(event_kind ORDER BY created_at, id) = ARRAY[
         'item_added', 'item_added', 'verification_started',
         'outcome_recorded', 'outcome_recorded', 'item_added',
         'item_withdrawn', 'alternative_promoted', 'item_withdrawn'
       ]::public.availability_event_kind[]
       FROM public.availability_verification_history
       WHERE pre_reservation_id = %L::uuid$q$,
    (:'pr_chain'::jsonb ->> 'pre_reservation_id')
  ),
  'ordering by created_at, id yields the sequence of actions'
);

SELECT tests.assert_true(
  format(
    $q$SELECT array_agg(
         coalesce(from_status::text, '-') || '>' || coalesce(to_status::text, '-')
         ORDER BY created_at, id
       ) = ARRAY[
         '->pending', '->pending', '->pending',
         'pending>available', 'pending>available', '->pending',
         'available>-', 'pending>pending', 'available>-'
       ]
       FROM public.availability_verification_history
       WHERE pre_reservation_id = %L::uuid$q$,
    (:'pr_chain'::jsonb ->> 'pre_reservation_id')
  ),
  'every event carries a coherent from_status/to_status pair'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1
       FROM public.availability_verification_history
       WHERE pre_reservation_id = %L::uuid
         AND event_kind = 'alternative_promoted'
         AND item_id = %L::uuid
         AND metadata ->> 'replaced_item_id' = %L$$,
    (:'pr_chain'::jsonb ->> 'pre_reservation_id'),
    (:'chain_alt'::jsonb ->> 'item_id'),
    :'item_c1_id'
  ),
  'the promoted event keeps metadata.replaced_item_id'
);

RESET ROLE;
ROLLBACK;
