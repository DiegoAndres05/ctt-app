-- availability_verification_test.sql
-- US2 (T026): assign_pre_reservation_operator, start_item_verification,
-- record_item_verification and expire_due_pre_reservations.
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/availability_verification_test.sql

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id          05000000-0000-4000-a000-000000000001
\set agent_id        05000000-0000-4000-b000-000000000001
\set operator_id     05000000-0000-4000-b000-000000000002
\set admin_id        05000000-0000-4000-b000-000000000003
\set inactive_op_id  05000000-0000-4000-b000-000000000004
\set customer_id     05000000-0000-4000-c000-000000000001
\set product_id      05000000-0000-4000-d000-000000000001

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
-- Setup: organization, collaborators, customer, product, request
-- =============================================================================
INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (:'org_id'::uuid, 'Verification Test Org', 'verification-test-org', 'active', '{"default_phone_country_code":"57"}'::jsonb);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-verification@test.invalid', 'Agent Verification', 'agent');
SELECT pg_temp.add_collaborator(:'operator_id'::uuid, :'org_id'::uuid, 'operator-verification@test.invalid', 'Operator Verification', 'operator');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-verification@test.invalid', 'Admin Verification', 'admin');
SELECT pg_temp.add_collaborator(:'inactive_op_id'::uuid, :'org_id'::uuid, 'operator-inactive-verification@test.invalid', 'Inactive Operator Verification', 'operator', 'inactive');

INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Paula', 'Rivas', 'paula-verification@test.invalid', '+573002223344', :'agent_id'::uuid);

-- Products must be priced before they can be active (enforce_active_requires_price).
INSERT INTO public.products (id, organization_id, name, type, status)
VALUES (:'product_id'::uuid, :'org_id'::uuid, 'Islas Tour', 'experience', 'draft');

INSERT INTO public.pricing_schemes (organization_id, product_id, base_amount, charge_type, valid_from)
VALUES (:'org_id'::uuid, :'product_id'::uuid, 150000, 'per_person', now() - interval '1 day');

UPDATE public.products SET status = 'active' WHERE id = :'product_id'::uuid;

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Paula","email":"paula-verification@test.invalid","phone":"3002223344"}'::jsonb,
  '{"travel_start_date":"2028-03-10","travel_end_date":"2028-03-14","adults":2}'::jsonb,
  ('[{"product_id":"' || :'product_id' || '","quantity":1}]')::jsonb,
  NULL
) ->> 'request_id') AS req_id \gset

-- =============================================================================
-- Setup: one pre-reservation per scenario (created as the internal function requires)
-- =============================================================================
-- assignment scenario (cancelled at the end of the assignment block)
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-03-10', 'adults', 2)
  )),
  :'agent_id'::uuid
) AS pr_assign \gset

-- happy path: two main lines so pending -> partially_verified -> verified is observable
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-04-10', 'adults', 1),
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-04-11', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_verify \gset

-- start scenario: nobody assigned yet (auto-assign on start)
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-05-10', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_start \gset

-- withdrawn scenario: two main lines so one can be withdrawn
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-06-10', 'adults', 1),
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-06-11', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_withdrawn \gset

-- negative validation scenario
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-07-10', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_negative \gset

-- expired hold scenario
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_id', 'start_date', '2028-08-10', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_expire \gset

SELECT id AS item_assign_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_assign'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT (array_agg(id ORDER BY position))[1] AS item_v1_id,
       (array_agg(id ORDER BY position))[2] AS item_v2_id
FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_verify'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT id AS item_start_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_start'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT (array_agg(id ORDER BY position))[1] AS item_w1_id,
       (array_agg(id ORDER BY position))[2] AS item_w2_id
FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_withdrawn'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT id AS item_neg_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_negative'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT id AS item_expire_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_expire'::jsonb ->> 'pre_reservation_id')::uuid \gset

-- =============================================================================
-- TEST: anon has no EXECUTE on the three US2 RPCs (T026)
-- =============================================================================
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT public.assign_pre_reservation_operator(gen_random_uuid(), gen_random_uuid())',
  'permission denied',
  'anon cannot EXECUTE assign_pre_reservation_operator'
);

SELECT tests.assert_raises(
  'SELECT public.start_item_verification(gen_random_uuid())',
  'permission denied',
  'anon cannot EXECUTE start_item_verification'
);

SELECT tests.assert_raises(
  'SELECT public.record_item_verification(gen_random_uuid(), ''{}''::jsonb)',
  'permission denied',
  'anon cannot EXECUTE record_item_verification'
);

SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('public.assign_pre_reservation_operator(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.start_item_verification(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.record_item_verification(uuid,jsonb)', 'EXECUTE')$q$,
  'anon has no EXECUTE privilege on the three US2 RPCs'
);

RESET ROLE;

-- =============================================================================
-- TEST: assign_pre_reservation_operator (T026)
-- =============================================================================
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.assign_pre_reservation_operator(
  (:'pr_assign'::jsonb ->> 'pre_reservation_id')::uuid,
  :'operator_id'::uuid
) AS assign_result \gset

SELECT tests.assert_equals(
  (:'assign_result'::jsonb ->> 'assigned_operator_id')::text,
  :'operator_id'::text,
  'assign returns the new assigned_operator_id'
);

SELECT public.assign_pre_reservation_operator(
  (:'pr_assign'::jsonb ->> 'pre_reservation_id')::uuid,
  NULL
) AS assign_clear_result \gset

SELECT tests.assert_raises(
  format(
    $$SELECT public.assign_pre_reservation_operator(%L::uuid, %L::uuid)$$,
    (:'pr_assign'::jsonb ->> 'pre_reservation_id'), :'agent_id'
  ),
  'ASSIGNEE_NOT_OPERATOR',
  'an agent cannot be assigned as verifier'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.assign_pre_reservation_operator(%L::uuid, %L::uuid)$$,
    (:'pr_assign'::jsonb ->> 'pre_reservation_id'), :'inactive_op_id'
  ),
  'ASSIGNEE_NOT_OPERATOR',
  'an inactive operator cannot be assigned as verifier'
);

SELECT public.assign_pre_reservation_operator(
  (:'pr_assign'::jsonb ->> 'pre_reservation_id')::uuid,
  :'admin_id'::uuid
);

-- Clear the assignment again so the audit shows {from, to} twice
SELECT public.assign_pre_reservation_operator(
  (:'pr_assign'::jsonb ->> 'pre_reservation_id')::uuid,
  NULL
);

-- =============================================================================
-- TEST: assign / start / record on a cancelled pre-reservation (T026)
-- =============================================================================
SELECT public.cancel_pre_reservation(
  (:'pr_assign'::jsonb ->> 'pre_reservation_id')::uuid,
  'Cliente desistió'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.assign_pre_reservation_operator(%L::uuid, %L::uuid)$$,
    (:'pr_assign'::jsonb ->> 'pre_reservation_id'), :'operator_id'
  ),
  'PRE_RESERVATION_CLOSED',
  'assign on a cancelled pre-reservation is rejected'
);

RESET ROLE;
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $$SELECT public.start_item_verification(%L::uuid)$$,
    :'item_assign_id'
  ),
  'PRE_RESERVATION_CLOSED',
  'start on a line of a cancelled pre-reservation is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_assign_id',
    jsonb_build_object(
      'status', 'available',
      'contact_person', 'Carlos (recepción)',
      'contact_method', 'whatsapp'
    )
  ),
  'PRE_RESERVATION_CLOSED',
  'record on a line of a cancelled pre-reservation is rejected'
);

-- =============================================================================
-- TEST: assign audit stores {from, to} (T026)
-- =============================================================================
RESET ROLE;

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 4
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_assigned'
         AND resource_id = %L::uuid$q$,
    (:'pr_assign'::jsonb ->> 'pre_reservation_id')
  ),
  'each assignment writes one pre_reservation_assigned audit'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 1
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_assigned'
         AND resource_id = %L::uuid
         AND metadata ->> 'from' IS NULL
         AND metadata ->> 'to' = %L$q$,
    (:'pr_assign'::jsonb ->> 'pre_reservation_id'), :'operator_id'
  ),
  'the first assignment records {from: null, to: operator}'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 2
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_assigned'
         AND resource_id = %L::uuid
         AND metadata ->> 'to' IS NULL$q$,
    (:'pr_assign'::jsonb ->> 'pre_reservation_id')
  ),
  'clearing the assignment records {to: null}'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 4
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_assigned'
         AND resource_id = %L::uuid
         AND metadata - 'from' - 'to' = '{}'::jsonb$q$,
    (:'pr_assign'::jsonb ->> 'pre_reservation_id')
  ),
  'assignment audit carries ids only, never free text'
);

-- =============================================================================
-- TEST: start_item_verification is idempotent and auto-assigns the caller (T026)
-- =============================================================================
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.start_item_verification(:'item_start_id'::uuid) AS start_result \gset

SELECT tests.assert_true(
  format(
    $$SELECT assigned_operator_id = %L::uuid
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    :'operator_id', (:'pr_start'::jsonb ->> 'pre_reservation_id')
  ),
  'first start auto-assigns the caller when nobody was assigned'
);

SELECT tests.assert_true(
  format(
    $$SELECT %L IS NOT NULL$$,
    (:'start_result'::jsonb ->> 'verification_started_at')
  ),
  'start returns verification_started_at'
);

SELECT tests.assert_equals(
  (:'start_result'::jsonb ->> 'assigned_operator_id')::text,
  :'operator_id'::text,
  'start returns the auto-assigned operator'
);

-- Second call: same timestamp, no extra event
SELECT public.start_item_verification(:'item_start_id'::uuid) AS start_result2 \gset

SELECT tests.assert_equals(
  (:'start_result2'::jsonb ->> 'verification_started_at')::text,
  (:'start_result'::jsonb ->> 'verification_started_at')::text,
  'a second start keeps the original verification_started_at'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.availability_verification_events
   WHERE item_id = :'item_start_id'::uuid AND event_kind = 'verification_started'),
  1,
  'a second start adds no verification_started event'
);

-- An agent is not a verifier
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $$SELECT public.start_item_verification(%L::uuid)$$,
    :'item_v1_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot start a verification'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_v1_id',
    jsonb_build_object('status', 'available', 'contact_person', 'Carlos', 'contact_method', 'phone')
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot record a verification result'
);

-- =============================================================================
-- TEST: withdrawn line rejects start and record (T026)
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.withdraw_pre_reservation_item(:'item_w1_id'::uuid, 'Suspendido por el proveedor');

RESET ROLE;
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $$SELECT public.start_item_verification(%L::uuid)$$,
    :'item_w1_id'
  ),
  'ITEM_WITHDRAWN',
  'start on a withdrawn line is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_w1_id',
    jsonb_build_object('status', 'available', 'contact_person', 'Carlos', 'contact_method', 'phone')
  ),
  'ITEM_WITHDRAWN',
  'record on a withdrawn line is rejected'
);

-- =============================================================================
-- TEST: record_item_verification negative cases (T026)
-- =============================================================================
-- pending is not a result
SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_neg_id',
    jsonb_build_object('status', 'pending', 'contact_person', 'Carlos', 'contact_method', 'phone')
  ),
  'VALIDATION_ERROR',
  'pending outcome is rejected'
);

-- missing contact person
SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_neg_id',
    jsonb_build_object('status', 'available', 'contact_method', 'phone')
  ),
  'CONTACT_PERSON_REQUIRED',
  'outcome without contact_person is rejected'
);

-- missing contact method
SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_neg_id',
    jsonb_build_object('status', 'available', 'contact_person', 'Carlos')
  ),
  'VALIDATION_ERROR',
  'outcome without contact_method is rejected'
);

-- invalid contact method
SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_neg_id',
    jsonb_build_object('status', 'available', 'contact_person', 'Carlos', 'contact_method', 'carrier_pigeon')
  ),
  'VALIDATION_ERROR',
  'outcome with an unknown contact_method is rejected'
);

-- hold in the past
SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_neg_id',
    jsonb_build_object(
      'status', 'available',
      'contact_person', 'Carlos',
      'contact_method', 'phone',
      'hold_expires_at', (now() - interval '1 hour')::text
    )
  ),
  'HOLD_EXPIRY_IN_PAST',
  'hold_expires_at in the past is rejected'
);

-- hold together with a non-available state
SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_neg_id',
    jsonb_build_object(
      'status', 'unavailable',
      'contact_person', 'Carlos',
      'contact_method', 'phone',
      'hold_expires_at', (now() + interval '2 days')::text
    )
  ),
  'VALIDATION_ERROR',
  'hold_expires_at with unavailable is rejected'
);

-- alternative_suggested without text
SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_neg_id',
    jsonb_build_object('status', 'alternative_suggested', 'contact_person', 'Carlos', 'contact_method', 'phone')
  ),
  'ALTERNATIVE_SUGGESTION_REQUIRED',
  'alternative_suggested without a suggestion is rejected'
);

-- contact person too long
SELECT tests.assert_raises(
  format(
    $$SELECT public.record_item_verification(%L::uuid, %L::jsonb)$$,
    :'item_neg_id',
    jsonb_build_object(
      'status', 'available',
      'contact_person', repeat('x', 121),
      'contact_method', 'phone'
    )
  ),
  'VALIDATION_ERROR',
  'contact_person longer than 120 is rejected'
);

-- Nothing was written by the rejected attempts
RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT verification_status = 'pending'
         AND verified_at IS NULL
         AND provider_contact_person IS NULL
       FROM public.pre_reservation_items
       WHERE id = %L::uuid$$,
    :'item_neg_id'
  ),
  'a rejected outcome leaves the line untouched'
);

SELECT tests.assert_equals(
  (SELECT count(*) FROM public.availability_verification_events
   WHERE item_id = :'item_neg_id'::uuid AND event_kind = 'outcome_recorded'),
  0,
  'a rejected outcome writes no history event'
);

-- =============================================================================
-- TEST: record_item_verification writes the three valid states (T026)
-- =============================================================================
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

-- First outcome: available with a hold -> partially_verified (and auto-assign)
SELECT public.record_item_verification(
  :'item_v1_id'::uuid,
  jsonb_build_object(
    'status', 'available',
    'contact_person', 'Carlos (recepción)',
    'contact_method', 'whatsapp',
    'hold_expires_at', (now() + interval '3 days')::text,
    'notes', 'Confirma dos cabañas'
  )
) AS rec_v1 \gset

SELECT tests.assert_equals(
  (:'rec_v1'::jsonb ->> 'verification_status')::text,
  'available',
  'first result records the available state'
);

SELECT tests.assert_equals(
  (:'rec_v1'::jsonb ->> 'pre_reservation_status')::text,
  'partially_verified',
  'one available line of two makes the pre-reservation partially_verified'
);

SELECT tests.assert_true(
  format(
    $$SELECT assigned_operator_id = %L::uuid
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    :'operator_id', (:'pr_verify'::jsonb ->> 'pre_reservation_id')
  ),
  'the first outcome auto-assigns the caller'
);

-- Second outcome: available without hold -> verified
SELECT public.record_item_verification(
  :'item_v2_id'::uuid,
  jsonb_build_object(
    'status', 'available',
    'contact_person', 'María (reservas)',
    'contact_method', 'email'
  )
) AS rec_v2 \gset

SELECT tests.assert_equals(
  (:'rec_v2'::jsonb ->> 'pre_reservation_status')::text,
  'verified',
  'every main line available makes the pre-reservation verified'
);

-- Third state: alternative_suggested on its own line
SELECT public.record_item_verification(
  :'item_w2_id'::uuid,
  jsonb_build_object(
    'status', 'alternative_suggested',
    'contact_person', 'Jorge (operaciones)',
    'contact_method', 'phone',
    'alternative_suggestion', 'Cambiaría la fecha al sábado'
  )
);

-- Re-verification: available -> unavailable clears the retention
SELECT public.record_item_verification(
  :'item_v1_id'::uuid,
  jsonb_build_object(
    'status', 'unavailable',
    'contact_person', 'Carlos (recepción)',
    'contact_method', 'whatsapp',
    'notes', 'La cabaña 2 está en mantenimiento'
  )
) AS rec_v1_again \gset

SELECT tests.assert_equals(
  (:'rec_v1_again'::jsonb ->> 'pre_reservation_status')::text,
  'requires_adjustment',
  'an unavailable main line moves the pre-reservation to requires_adjustment'
);

RESET ROLE;

-- =============================================================================
-- TEST: outcomes write outcome_recorded events and availability_recorded audit (T026)
-- =============================================================================
SELECT tests.assert_equals(
  (SELECT count(*) FROM public.availability_verification_events
   WHERE item_id = :'item_v1_id'::uuid AND event_kind = 'outcome_recorded'),
  2,
  're-verification appends a second outcome_recorded event'
);

SELECT tests.assert_true(
  format(
    $q$SELECT from_status = 'pending' AND to_status = 'available'
         AND hold_expires_at IS NOT NULL
         AND provider_contact_person = 'Carlos (recepción)'
         AND notes = 'Confirma dos cabañas'
       FROM public.availability_verification_events
       WHERE item_id = %L::uuid
         AND event_kind = 'outcome_recorded'
         AND from_status = 'pending'$q$,
    :'item_v1_id'
  ),
  'the first outcome event carries pending -> available with contact data'
);

SELECT tests.assert_true(
  format(
    $q$SELECT metadata ->> 'item_id' IS NOT NULL
         AND metadata ->> 'from' = 'available'
         AND metadata ->> 'to' = 'unavailable'
         AND (metadata ->> 'has_hold')::boolean = false
         AND NOT (metadata ? 'notes')
       FROM audit.audit_events
       WHERE event_type = 'availability_recorded'
         AND resource_id = %L::uuid
       ORDER BY id DESC LIMIT 1$q$,
    :'item_v1_id'
  ),
  'availability_recorded audit stores {item_id, from, to, has_hold} without notes'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 4
       FROM audit.audit_events
       WHERE event_type = 'availability_recorded'
         AND resource_id IN (%L::uuid, %L::uuid, %L::uuid)$q$,
    :'item_v1_id', :'item_v2_id', :'item_w2_id'
  ),
  'every recorded outcome writes one availability_recorded audit'
);

-- The retention is gone after re-verifying as unavailable
SELECT tests.assert_true(
  format(
    $$SELECT hold_expires_at IS NULL
         AND verification_status = 'unavailable'
         AND alternative_suggestion IS NULL
       FROM public.pre_reservation_items
       WHERE id = %L::uuid$$,
    :'item_v1_id'
  ),
  're-verification without a hold clears the previous retention'
);

SELECT tests.assert_true(
  format(
    $$SELECT status = 'requires_adjustment'
         AND expires_at IS NULL
         AND verified_at IS NULL
         AND first_verified_at IS NOT NULL
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    (:'pr_verify'::jsonb ->> 'pre_reservation_id')
  ),
  'verified_at follows the status while first_verified_at is kept'
);

-- =============================================================================
-- TEST: expire_due_pre_reservations marks an expired hold (T026)
-- =============================================================================
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.record_item_verification(
  :'item_expire_id'::uuid,
  jsonb_build_object(
    'status', 'available',
    'contact_person', 'Rocío (recepción)',
    'contact_method', 'phone',
    'hold_expires_at', (now() + interval '1 day')::text
  )
) AS rec_expire \gset

SELECT tests.assert_equals(
  (:'rec_expire'::jsonb ->> 'pre_reservation_status')::text,
  'verified',
  'the expiry scenario starts out verified'
);

-- Simulate the hold lapsing: only a superuser can move time
RESET ROLE;

UPDATE public.pre_reservation_items
SET hold_expires_at = now() - interval '1 hour'
WHERE id = :'item_expire_id'::uuid;

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.expire_due_pre_reservations() AS expired_count \gset

SELECT tests.assert_equals(
  (:'expired_count')::bigint,
  1,
  'the sweep returns how many pre-reservations became expired'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT status = 'expired'
         AND expires_at IS NULL
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    (:'pr_expire'::jsonb ->> 'pre_reservation_id')
  ),
  'the lapsed hold marks the pre-reservation expired'
);

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.expire_due_pre_reservations() AS expired_count_again \gset

SELECT tests.assert_equals(
  (:'expired_count_again')::bigint,
  0,
  'the sweep is idempotent'
);

RESET ROLE;
ROLLBACK;
