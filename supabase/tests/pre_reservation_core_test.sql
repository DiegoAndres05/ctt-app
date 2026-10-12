-- pre_reservation_core_test.sql
-- Core function tests: create_pre_reservation_core, refresh_pre_reservation_status, resolve_pre_reservation_item, insert_pre_reservation_item
-- Run with: ./supabase/tests/run-sql-tests.sh pre_reservation_core_test.sql

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id         04000000-0000-4000-a000-000000000001
\set org_b_id       04000000-0000-4000-a000-000000000002
\set agent_id       04000000-0000-4000-b000-000000000001
\set operator_id    04000000-0000-4000-b000-000000000002
\set admin_id       04000000-0000-4000-b000-000000000003
\set agent_b_id     04000000-0000-4000-b000-000000000004
\set inactive_op_id 04000000-0000-4000-b000-000000000005
\set customer_id    04000000-0000-4000-c000-000000000001
\set product_exp_id 04000000-0000-4000-d000-000000000001
\set product_acc_id 04000000-0000-4000-d000-000000000002
\set product_b_id   04000000-0000-4000-d000-000000000003
\set provider_id    04000000-0000-4000-e000-000000000001

-- Helper: add_collaborator (copied from request_workflow_test.sql)
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

-- Helper: act_as (copied from request_workflow_test.sql)
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
  (:'org_id'::uuid, 'Core Test Org', 'core-test-org', 'active', '{"default_phone_country_code":"57"}'::jsonb),
  (:'org_b_id'::uuid, 'Core Test Org B', 'core-test-org-b', 'active', '{"default_phone_country_code":"57"}'::jsonb);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-core@test.invalid', 'Agent Core', 'agent');
SELECT pg_temp.add_collaborator(:'operator_id'::uuid, :'org_id'::uuid, 'operator-core@test.invalid', 'Operator Core', 'operator');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-core@test.invalid', 'Admin Core', 'admin');
SELECT pg_temp.add_collaborator(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent-core-b@test.invalid', 'Agent Core B', 'agent');

-- Setup: customer
INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Laura', 'Gómez', 'laura-core@test.invalid', '+573001112233', :'agent_id'::uuid);

-- Setup: provider
INSERT INTO public.providers (id, organization_id, name, contact_phone, contact_email, is_active)
VALUES (:'provider_id'::uuid, :'org_id'::uuid, 'Lanchas Barú', '+573001112233', 'lanchas@baru.co', true);

-- Setup: products (experience with provider, accommodation with provider)
-- Products must be priced before they can be active (enforce_active_requires_price).
INSERT INTO public.products (id, organization_id, name, type, status, provider_id)
VALUES
  (:'product_exp_id'::uuid, :'org_id'::uuid, 'City Tour', 'experience', 'draft', :'provider_id'::uuid),
  (:'product_acc_id'::uuid, :'org_id'::uuid, 'Hotel Playa', 'accommodation', 'draft', :'provider_id'::uuid);

INSERT INTO public.pricing_schemes (organization_id, product_id, base_amount, charge_type, valid_from)
VALUES
  (:'org_id'::uuid, :'product_exp_id'::uuid, 120000, 'per_person', now() - interval '1 day'),
  (:'org_id'::uuid, :'product_acc_id'::uuid, 350000, 'per_night', now() - interval '1 day');

UPDATE public.products
SET status = 'active'
WHERE id IN (:'product_exp_id'::uuid, :'product_acc_id'::uuid);

-- Helper: capture a request (received)
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Laura","email":"laura-core@test.invalid","phone":"3001112233"}'::jsonb,
  '{"travel_start_date":"2027-03-15","travel_end_date":"2027-03-18","adults":2}'::jsonb,
  ('[{"product_id":"' || :'product_exp_id' || '","quantity":1}]')::jsonb,
  NULL
) ->> 'request_id') AS received_req_id \gset

-- Helper: capture a request (in_review)
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Carlos","email":"carlos-core@test.invalid","phone":"3002223344"}'::jsonb,
  '{"travel_start_date":"2027-04-10","travel_end_date":"2027-04-12","adults":2}'::jsonb,
  ('[{"product_id":"' || :'product_acc_id' || '","quantity":1}]')::jsonb,
  NULL
) ->> 'request_id') AS review_req_id \gset

-- Helper: capture a discarded request
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Discarded","email":"discarded-core@test.invalid","phone":"3003334455"}'::jsonb,
  '{"travel_start_date":"2027-05-01","adults":1}'::jsonb,
  '[{"free_text":"Discarded tour","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS discarded_req_id \gset

-- Set discarded request to discarded status (needs JWT claims for require_tenant_member)
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SELECT public.set_request_status(:'discarded_req_id'::uuid, 'discarded', 'Cliente desistió');

-- Setup: org B request and product (cross-tenant checks and per-org reference test)
INSERT INTO public.products (id, organization_id, name, type, status)
VALUES (:'product_b_id'::uuid, :'org_b_id'::uuid, 'Org B Tour', 'experience', 'draft');

INSERT INTO public.pricing_schemes (organization_id, product_id, base_amount, charge_type, valid_from)
VALUES (:'org_b_id'::uuid, :'product_b_id'::uuid, 90000, 'per_person', now() - interval '1 day');

UPDATE public.products SET status = 'active' WHERE id = :'product_b_id'::uuid;

SELECT (public.capture_request_core(
  :'org_b_id'::uuid, 'phone', NULL,
  '{"first_name":"Org B","email":"orgb-core@test.invalid","phone":"3006667788"}'::jsonb,
  '{"travel_start_date":"2027-06-15","adults":2}'::jsonb,
  '[{"free_text":"Org B tour","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS org_b_req_id \gset

-- =============================================================================
-- TEST: create_pre_reservation_core creates PRE-00001 with lines and converts request
-- =============================================================================
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE postgres; -- Call internal function directly as superuser

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid,
  :'received_req_id'::uuid,
  jsonb_build_object(
    'items', jsonb_build_array(
      jsonb_build_object(
        'product_id', :'product_exp_id',
        'start_date', '2027-03-15',
        'end_date', '2027-03-18',
        'adults', 2,
        'children', 0,
        'quantity', 1,
        'alternative_of', ''
      )
    ),
    'assigned_operator_id', :'operator_id'
  ),
  :'agent_id'::uuid
) AS result \gset

SELECT tests.assert_equals((:'result'::jsonb ->> 'reference')::text, 'PRE-00001', 'first reference is PRE-00001');
SELECT tests.assert_equals((:'result'::jsonb ->> 'status')::text, 'pending_verification', 'status is pending_verification');
SELECT tests.assert_equals((:'result'::jsonb ->> 'request_status')::text, 'pre_reservation', 'request status converted to pre_reservation');

-- Verify pre_reservation created with correct fields
SELECT tests.assert_true(
  format(
    $$SELECT reference = 'PRE-00001'
         AND status = 'pending_verification'
         AND responsible_agent_id = %L::uuid
         AND assigned_operator_id = %L::uuid
         AND request_id = %L::uuid
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    :'agent_id', :'operator_id', :'received_req_id', :'result'::jsonb ->> 'pre_reservation_id'
  ),
  'pre_reservation header has correct fields'
);

-- Verify line created
SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1
       FROM public.pre_reservation_items
       WHERE pre_reservation_id = %L::uuid$$,
    :'result'::jsonb ->> 'pre_reservation_id'
  ),
  'one line inserted'
);

-- Verify audit events
SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_created'
         AND resource_id = %L::uuid$$,
    :'result'::jsonb ->> 'pre_reservation_id'
  ),
  'pre_reservation_created audit emitted'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1
       FROM audit.audit_events
       WHERE event_type = 'request_status_changed'
         AND resource_id = %L::uuid
         AND metadata ->> 'to' = 'pre_reservation'$$,
    :'received_req_id'
  ),
  'request_status_changed audit emitted with pre_reservation_id'
);

-- Verify item_added event
SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1
       FROM public.availability_verification_events
       WHERE pre_reservation_id = %L::uuid
         AND event_kind = 'item_added'$$,
    :'result'::jsonb ->> 'pre_reservation_id'
  ),
  'item_added event logged'
);

-- =============================================================================
-- TEST: Second pre_reservation on same request does NOT change request status
-- =============================================================================
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid,
  :'received_req_id'::uuid, -- same request (now in pre_reservation)
  jsonb_build_object(
    'items', jsonb_build_array(
      jsonb_build_object(
        'product_id', :'product_acc_id',
        'start_date', '2027-04-20',
        'end_date', '2027-04-22',
        'adults', 2,
        'quantity', 1
      )
    )
  ),
  :'agent_id'::uuid
) AS result2 \gset

SELECT tests.assert_equals((:'result2'::jsonb ->> 'request_status')::text, 'pre_reservation', 'request stays pre_reservation');
SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 2
       FROM public.pre_reservations
       WHERE request_id = %L::uuid$$,
    :'received_req_id'
  ),
  'two pre-reservations linked to same request'
);

-- =============================================================================
-- TEST: Request discarded -> REQUEST_CLOSED
-- =============================================================================
SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-06-01","adults":1}]}', %L::uuid)$$,
    :'org_id', :'discarded_req_id', :'product_exp_id', :'agent_id'
  ),
  'REQUEST_CLOSED',
  'discarded request rejected'
);

-- =============================================================================
-- TEST: Customer anonymized -> CUSTOMER_ANONYMIZED
-- =============================================================================
-- Create a request with a customer, then anonymize
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Anon","email":"anon-core@test.invalid","phone":"3004445566"}'::jsonb,
  '{"travel_start_date":"2027-07-01","adults":1}'::jsonb,
  '[{"free_text":"Anon tour","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS anon_req_id \gset

UPDATE public.customers SET is_anonymized = true, anonymized_at = now() WHERE id = (
  SELECT customer_id FROM public.customer_requests WHERE id = :'anon_req_id'::uuid
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-07-01","adults":1}]}', %L::uuid)$$,
    :'org_id', :'anon_req_id', :'product_exp_id', :'agent_id'
  ),
  'CUSTOMER_ANONYMIZED',
  'anonymized customer rejected'
);

-- =============================================================================
-- TEST: No main items -> VALIDATION_ERROR
-- =============================================================================
SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-08-01","adults":1,"alternative_of":0}]}', %L::uuid)$$,
    :'org_id', :'review_req_id', :'product_exp_id', :'agent_id'
  ),
  'VALIDATION_ERROR',
  'no main items rejected'
);

-- =============================================================================
-- TEST: 31 items -> VALIDATION_ERROR
-- =============================================================================
SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, %L::jsonb, %L::uuid)$$,
    :'org_id', :'review_req_id',
    jsonb_build_object('items',
      (SELECT jsonb_agg(jsonb_build_object('product_id', :'product_exp_id', 'start_date', '2027-09-01', 'adults', 1))
       FROM generate_series(1, 31)
      )
    ),
    :'agent_id'
  ),
  'VALIDATION_ERROR',
  '31 items rejected'
);

-- =============================================================================
-- TEST: Inactive product -> ITEM_NOT_BOOKABLE
-- =============================================================================
-- Create inactive product
INSERT INTO public.products (id, organization_id, name, type, status)
VALUES (gen_random_uuid(), :'org_id'::uuid, 'Inactive Tour', 'experience', 'inactive')
RETURNING id AS inactive_prod_id \gset

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-10-01","adults":1}]}', %L::uuid)$$,
    :'org_id', :'review_req_id', :'inactive_prod_id', :'agent_id'
  ),
  'ITEM_NOT_BOOKABLE',
  'inactive product rejected'
);

-- =============================================================================
-- TEST: Past date -> TRAVEL_DATE_IN_PAST
-- =============================================================================
SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2020-01-01","adults":1}]}', %L::uuid)$$,
    :'org_id', :'review_req_id', :'product_exp_id', :'agent_id'
  ),
  'TRAVEL_DATE_IN_PAST',
  'past date rejected'
);

-- =============================================================================
-- TEST: Accommodation without nights -> INVALID_DATE_RANGE
-- =============================================================================
SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-11-01","end_date":"2027-11-01","adults":1}]}', %L::uuid)$$,
    :'org_id', :'review_req_id', :'product_acc_id', :'agent_id'
  ),
  'INVALID_DATE_RANGE',
  'accommodation without nights rejected'
);

-- =============================================================================
-- TEST: alternative_of out of range or pointing to alternative -> VALIDATION_ERROR
-- =============================================================================
-- alternative_of index out of range
SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-12-01","adults":1,"alternative_of":5}]}', %L::uuid)$$,
    :'org_id', :'review_req_id', :'product_exp_id', :'agent_id'
  ),
  'VALIDATION_ERROR',
  'alternative_of out of range rejected'
);

-- =============================================================================
-- TEST: source_request_item_id from another request -> VALIDATION_ERROR
-- =============================================================================
SELECT cri.id AS other_cri_id FROM public.customer_request_items cri
JOIN public.customer_requests cr ON cr.id = cri.request_id
WHERE cr.organization_id = :'org_b_id'::uuid
LIMIT 1 \gset

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation_core(%L::uuid, %L::uuid, '{"items":[{"product_id":"%s","start_date":"2027-12-01","adults":1,"source_request_item_id":"%s"}]}', %L::uuid)$$,
    :'org_id', :'review_req_id', :'product_exp_id', :'other_cri_id', :'agent_id'
  ),
  'VALIDATION_ERROR',
  'source_request_item_id from another request rejected'
);

-- =============================================================================
-- TEST: Product with active provider -> snapshot taken
-- =============================================================================
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid,
  :'review_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_exp_id', 'start_date', '2028-01-15', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS prov_test \gset

SELECT tests.assert_true(
  format(
    $$SELECT provider_id = %L::uuid
         AND provider_name = 'Lanchas Barú'
         AND provider_phone = '+573001112233'
       FROM public.pre_reservation_items
       WHERE pre_reservation_id = %L::uuid$$,
    :'provider_id', :'prov_test'::jsonb ->> 'pre_reservation_id'
  ),
  'provider snapshot taken from product'
);

-- =============================================================================
-- TEST: Product without provider -> manual fields preserved
-- =============================================================================
INSERT INTO public.products (id, organization_id, name, type, status, provider_id)
VALUES (gen_random_uuid(), :'org_id'::uuid, 'No Provider Tour', 'experience', 'draft', NULL)
RETURNING id AS no_prov_prod_id \gset

INSERT INTO public.pricing_schemes (organization_id, product_id, base_amount, charge_type, valid_from)
VALUES (:'org_id'::uuid, :'no_prov_prod_id', 80000, 'per_person', now() - interval '1 day');

UPDATE public.products SET status = 'active' WHERE id = :'no_prov_prod_id'::uuid;

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid,
  :'review_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object(
      'product_id', :'no_prov_prod_id',
      'start_date', '2028-02-01',
      'adults', 1,
      'provider_name', 'Manual Provider',
      'provider_phone', '+57 311 222 3344',
      'provider_email', 'manual@provider.co'
    )
  )),
  :'agent_id'::uuid
) AS manual_prov_test \gset

SELECT tests.assert_true(
  format(
    $$SELECT provider_id IS NULL
         AND provider_name = 'Manual Provider'
         AND provider_phone = '+57 311 222 3344'
         AND provider_email = 'manual@provider.co'
       FROM public.pre_reservation_items
       WHERE pre_reservation_id = %L::uuid$$,
    :'manual_prov_test'::jsonb ->> 'pre_reservation_id'
  ),
  'manual provider fields preserved when product has no provider'
);

-- =============================================================================
-- TEST: refresh_pre_reservation_status derives five states per precedence
-- =============================================================================
-- Create a fresh pre-reservation for status testing
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid,
  :'review_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_exp_id', 'start_date', '2028-03-01', 'adults', 1),
    jsonb_build_object('product_id', :'product_acc_id', 'start_date', '2028-03-05', 'end_date', '2028-03-08', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS status_test \gset

-- Initially pending_verification (no lines available)
SELECT tests.assert_equals(
  public.refresh_pre_reservation_status((:'status_test'::jsonb ->> 'pre_reservation_id')::uuid)::text,
  'pending_verification',
  'initial status pending_verification'
);

-- Make one line available -> partially_verified
UPDATE public.pre_reservation_items
SET verification_status = 'available', verified_by = :'operator_id', verified_at = now(),
    provider_contact_person = 'Carlos', contact_method = 'whatsapp', hold_expires_at = now() + interval '1 day'
WHERE id = (
  SELECT id FROM public.pre_reservation_items
  WHERE pre_reservation_id = (:'status_test'::jsonb ->> 'pre_reservation_id')::uuid
    AND alternative_of_item_id IS NULL
  ORDER BY position
  LIMIT 1
);

SELECT tests.assert_equals(
  public.refresh_pre_reservation_status((:'status_test'::jsonb ->> 'pre_reservation_id')::uuid)::text,
  'partially_verified',
  'one available -> partially_verified'
);

-- Make second line available -> verified
UPDATE public.pre_reservation_items
SET verification_status = 'available', verified_by = :'operator_id', verified_at = now(),
    provider_contact_person = 'Carlos', contact_method = 'whatsapp', hold_expires_at = now() + interval '1 day'
WHERE pre_reservation_id = (:'status_test'::jsonb ->> 'pre_reservation_id')::uuid
  AND alternative_of_item_id IS NULL
  AND verification_status = 'pending';

SELECT tests.assert_equals(
  public.refresh_pre_reservation_status((:'status_test'::jsonb ->> 'pre_reservation_id')::uuid)::text,
  'verified',
  'all available -> verified'
);

-- Verify verified_at and first_verified_at set
SELECT tests.assert_true(
  format(
    $$SELECT verified_at IS NOT NULL AND first_verified_at IS NOT NULL
       FROM public.pre_reservations WHERE id = %L::uuid$$,
    :'status_test'::jsonb ->> 'pre_reservation_id'
  ),
  'verified_at and first_verified_at set on verified'
);

-- Make one line unavailable -> requires_adjustment
UPDATE public.pre_reservation_items
SET verification_status = 'unavailable', verified_by = :'operator_id', verified_at = now(),
    provider_contact_person = 'Carlos', contact_method = 'whatsapp', hold_expires_at = NULL
WHERE id = (
  SELECT id FROM public.pre_reservation_items
  WHERE pre_reservation_id = (:'status_test'::jsonb ->> 'pre_reservation_id')::uuid
    AND alternative_of_item_id IS NULL
    AND verification_status = 'available'
  ORDER BY position
  LIMIT 1
);

SELECT tests.assert_equals(
  public.refresh_pre_reservation_status((:'status_test'::jsonb ->> 'pre_reservation_id')::uuid)::text,
  'requires_adjustment',
  'one unavailable -> requires_adjustment'
);

-- Make it available again but with hold_expired -> expired
UPDATE public.pre_reservation_items
SET verification_status = 'available', hold_expires_at = now() - interval '1 hour'
WHERE pre_reservation_id = (:'status_test'::jsonb ->> 'pre_reservation_id')::uuid
  AND alternative_of_item_id IS NULL
  AND verification_status = 'unavailable';

SELECT tests.assert_equals(
  public.refresh_pre_reservation_status((:'status_test'::jsonb ->> 'pre_reservation_id')::uuid)::text,
  'expired',
  'hold expired -> expired'
);

-- Re-verify with new hold -> verified again
UPDATE public.pre_reservation_items
SET hold_expires_at = now() + interval '1 day'
WHERE pre_reservation_id = (:'status_test'::jsonb ->> 'pre_reservation_id')::uuid
  AND alternative_of_item_id IS NULL
  AND verification_status = 'available';

SELECT tests.assert_equals(
  public.refresh_pre_reservation_status((:'status_test'::jsonb ->> 'pre_reservation_id')::uuid)::text,
  'verified',
  're-verify with future hold -> verified'
);

-- =============================================================================
-- TEST: refresh_pre_reservation_status audits pre_reservation_status_changed only when status changes
-- =============================================================================
-- Count status-change audits before
SELECT count(*) AS before_audit_count FROM audit.audit_events
WHERE event_type = 'pre_reservation_status_changed'
  AND resource_id = (:'status_test'::jsonb ->> 'pre_reservation_id')::uuid \gset

-- Call refresh when status is already verified (no change)
SELECT public.refresh_pre_reservation_status((:'status_test'::jsonb ->> 'pre_reservation_id')::uuid);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) - %s = 0 FROM audit.audit_events
       WHERE event_type = 'pre_reservation_status_changed'
         AND resource_id = %L::uuid$$,
    :'before_audit_count', :'status_test'::jsonb ->> 'pre_reservation_id'
  ),
  'no status audit emitted when status unchanged'
);

-- Change to expired and verify the audit is emitted
UPDATE public.pre_reservation_items
SET hold_expires_at = now() - interval '1 hour'
WHERE pre_reservation_id = (:'status_test'::jsonb ->> 'pre_reservation_id')::uuid
  AND alternative_of_item_id IS NULL;

SELECT public.refresh_pre_reservation_status((:'status_test'::jsonb ->> 'pre_reservation_id')::uuid);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) - %s = 1 FROM audit.audit_events
       WHERE event_type = 'pre_reservation_status_changed'
         AND resource_id = %L::uuid$$,
    :'before_audit_count', :'status_test'::jsonb ->> 'pre_reservation_id'
  ),
  'status audit emitted when status changes'
);

-- =============================================================================
-- TEST: Reference increments per organization
-- =============================================================================
-- Snapshot org A's counter: the sequence is shared per organization, so the expected
-- values depend on every pre-reservation created earlier in this suite.
SELECT substring(max(reference) from 5)::bigint AS prev_ref_num
FROM public.pre_reservations
WHERE organization_id = :'org_id'::uuid \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid,
  :'review_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_exp_id', 'start_date', '2028-04-01', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS ref_test_1 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid,
  :'review_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_exp_id', 'start_date', '2028-04-02', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS ref_test_2 \gset

SELECT tests.assert_equals(
  substring((:'ref_test_1'::jsonb ->> 'reference') from 5)::bigint,
  (:'prev_ref_num'::bigint + 1),
  'org A reference continues its own sequence'
);
SELECT tests.assert_equals(
  substring((:'ref_test_2'::jsonb ->> 'reference') from 5)::bigint,
  (:'prev_ref_num'::bigint + 2),
  'org A reference increments by one per creation'
);

-- Different org starts at 00001
SELECT public.create_pre_reservation_core(
  :'org_b_id'::uuid,
  :'org_b_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_b_id', 'start_date', '2028-04-01', 'adults', 1)
  )),
  :'agent_b_id'::uuid
) AS ref_test_org_b \gset

SELECT tests.assert_equals((:'ref_test_org_b'::jsonb ->> 'reference')::text, 'PRE-00001', 'org B starts at PRE-00001');

RESET ROLE;

-- =============================================================================
-- TEST (T017): create_pre_reservation RPC as authenticated — agent/operator/admin
-- =============================================================================

-- anon has no EXECUTE on the US1 RPCs
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation(%L::uuid, '{"items":[]}')$$,
    :'review_req_id'
  ),
  'permission denied',
  'anon cannot EXECUTE create_pre_reservation'
);

SELECT tests.assert_raises(
  'SELECT public.cancel_pre_reservation(gen_random_uuid(), ''motivo'')',
  'permission denied',
  'anon cannot EXECUTE cancel_pre_reservation'
);

RESET ROLE;

-- Fresh request for the authenticated RPC tests
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"RPC","email":"rpc-core@test.invalid","phone":"3007778899"}'::jsonb,
  '{"travel_start_date":"2027-09-10","adults":2}'::jsonb,
  '[{"free_text":"RPC tour","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS rpc_req_id \gset

-- A second fresh request for the valid operator assignment case
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"RPC Op","email":"rpc-op-core@test.invalid","phone":"3008889900"}'::jsonb,
  '{"travel_start_date":"2027-09-15","adults":2}'::jsonb,
  '[{"free_text":"RPC operator tour","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS rpc_op_req_id \gset

-- Inactive operator for the ASSIGNEE_NOT_OPERATOR case
SELECT pg_temp.add_collaborator(
  :'inactive_op_id'::uuid, :'org_id'::uuid, 'operator-inactive-core@test.invalid',
  'Inactive Operator Core', 'operator', 'inactive'
);

-- Agent can create
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.create_pre_reservation(
  :'rpc_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_exp_id', 'start_date', '2028-06-01', 'adults', 2)
  ))
) AS agent_create \gset

SELECT tests.assert_equals(
  (:'agent_create'::jsonb ->> 'status')::text,
  'pending_verification',
  'agent create returns status pending_verification'
);
SELECT tests.assert_equals(
  (:'agent_create'::jsonb ->> 'request_status')::text,
  'pre_reservation',
  'agent create converts the request to pre_reservation'
);
SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb ? 'pre_reservation_id'
         AND %L::jsonb ? 'reference'
         AND (%L::jsonb ->> 'reference') LIKE 'PRE-%%'$$,
    :'agent_create', :'agent_create', :'agent_create'
  ),
  'agent create returns pre_reservation_id and a PRE-##### reference'
);
SELECT tests.assert_true(
  format(
    $$SELECT responsible_agent_id = %L::uuid
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    :'agent_id', :'agent_create'::jsonb ->> 'pre_reservation_id'
  ),
  'the creating agent becomes the responsible agent'
);

-- Operator can create
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');

SELECT public.create_pre_reservation(
  :'rpc_op_req_id'::uuid,
  jsonb_build_object(
    'items', jsonb_build_array(
      jsonb_build_object('product_id', :'product_exp_id', 'start_date', '2028-06-05', 'adults', 1)
    ),
    'assigned_operator_id', :'operator_id'
  )
) AS operator_create \gset

SELECT tests.assert_equals(
  (:'operator_create'::jsonb ->> 'status')::text,
  'pending_verification',
  'operator can create a pre-reservation'
);
SELECT tests.assert_true(
  format(
    $$SELECT assigned_operator_id = %L::uuid
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    :'operator_id', :'operator_create'::jsonb ->> 'pre_reservation_id'
  ),
  'a valid assigned_operator_id is persisted'
);

-- Admin can create
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');

SELECT public.create_pre_reservation(
  :'rpc_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_acc_id', 'start_date', '2028-06-10', 'end_date', '2028-06-13', 'adults', 2)
  ))
) AS admin_create \gset

SELECT tests.assert_equals(
  (:'admin_create'::jsonb ->> 'request_status')::text,
  'pre_reservation',
  'admin can create an additional pre-reservation on the same request'
);

-- A request from another organization returns VALIDATION_ERROR
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');

SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation(%L::uuid, '{"items":[{"product_id":"%s","start_date":"2028-07-01","adults":1}]}')$$,
    :'org_b_req_id', :'product_exp_id'
  ),
  'VALIDATION_ERROR',
  'a request from another organization returns VALIDATION_ERROR'
);

-- assigned_operator_id that is an agent -> ASSIGNEE_NOT_OPERATOR
SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation(%L::uuid, jsonb_build_object(
        'items', jsonb_build_array(jsonb_build_object('product_id', %L, 'start_date', '2028-08-01', 'adults', 1)),
        'assigned_operator_id', %L::uuid))$$,
    :'rpc_req_id', :'product_exp_id', :'agent_id'
  ),
  'ASSIGNEE_NOT_OPERATOR',
  'an agent cannot be the assigned operator'
);

-- assigned_operator_id that is an inactive operator -> ASSIGNEE_NOT_OPERATOR
SELECT tests.assert_raises(
  format(
    $$SELECT public.create_pre_reservation(%L::uuid, jsonb_build_object(
        'items', jsonb_build_array(jsonb_build_object('product_id', %L, 'start_date', '2028-08-02', 'adults', 1)),
        'assigned_operator_id', %L::uuid))$$,
    :'rpc_req_id', :'product_exp_id', :'inactive_op_id'
  ),
  'ASSIGNEE_NOT_OPERATOR',
  'an inactive operator cannot be the assigned operator'
);

-- =============================================================================
-- TEST (T017): cancel_pre_reservation RPC
-- =============================================================================

-- capture_request_core is internal: reset to the session user for the setup only
RESET ROLE;
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Cancel","email":"cancel-core@test.invalid","phone":"3009990011"}'::jsonb,
  '{"travel_start_date":"2027-09-20","adults":2}'::jsonb,
  '[{"free_text":"Cancel tour","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS cancel_req_id \gset
SET LOCAL ROLE authenticated;

SELECT public.create_pre_reservation(
  :'cancel_req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_exp_id', 'start_date', '2028-09-01', 'adults', 1)
  ))
) AS cancel_pr \gset

-- Missing reason -> CANCEL_REASON_REQUIRED
SELECT tests.assert_raises(
  format(
    $$SELECT public.cancel_pre_reservation(%L::uuid, NULL)$$,
    :'cancel_pr'::jsonb ->> 'pre_reservation_id'
  ),
  'CANCEL_REASON_REQUIRED',
  'cancel without a reason is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.cancel_pre_reservation(%L::uuid, '   ')$$,
    :'cancel_pr'::jsonb ->> 'pre_reservation_id'
  ),
  'CANCEL_REASON_REQUIRED',
  'cancel with a blank reason is rejected'
);

-- Reason longer than 500 -> VALIDATION_ERROR
SELECT tests.assert_raises(
  format(
    $$SELECT public.cancel_pre_reservation(%L::uuid, %L)$$,
    :'cancel_pr'::jsonb ->> 'pre_reservation_id', repeat('x', 501)
  ),
  'VALIDATION_ERROR',
  'cancel reason longer than 500 is rejected'
);

-- A valid cancellation
SELECT public.cancel_pre_reservation(
  (:'cancel_pr'::jsonb ->> 'pre_reservation_id')::uuid, 'Cliente desistió'
) AS cancel_result \gset

SELECT tests.assert_equals(
  (:'cancel_result'::jsonb ->> 'status')::text,
  'cancelled',
  'cancel returns status cancelled'
);
SELECT tests.assert_true(
  format(
    $$SELECT status = 'cancelled'
         AND cancelled_at IS NOT NULL
         AND cancel_reason = 'Cliente desistió'
         AND cancelled_by = %L::uuid
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    :'agent_id', :'cancel_pr'::jsonb ->> 'pre_reservation_id'
  ),
  'cancel fixes cancelled_at, cancel_reason and cancelled_by'
);

-- The history event carries the reason in notes
SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1
       FROM public.availability_verification_events
       WHERE pre_reservation_id = %L::uuid
         AND event_kind = 'pre_reservation_cancelled'
         AND item_id IS NULL
         AND notes = 'Cliente desistió'$$,
    :'cancel_pr'::jsonb ->> 'pre_reservation_id'
  ),
  'cancel writes a pre_reservation_cancelled event with the reason in notes'
);

-- The audit stores {from} without the reason (audit_events is admin-readable only)
RESET ROLE;
SELECT tests.assert_true(
  format(
    $$SELECT metadata ->> 'from' = 'pending_verification'
         AND NOT (metadata ? 'reason')
         AND metadata::text NOT ILIKE '%%desisti%%'
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_cancelled'
         AND resource_id = %L::uuid$$,
    :'cancel_pr'::jsonb ->> 'pre_reservation_id'
  ),
  'cancel audit stores {from} without the reason'
);
SET LOCAL ROLE authenticated;

-- The source request keeps pre_reservation
SELECT tests.assert_true(
  format(
    $$SELECT status = 'pre_reservation'
       FROM public.customer_requests
       WHERE id = %L::uuid$$,
    :'cancel_req_id'
  ),
  'the source request keeps its pre_reservation status'
);

-- Double cancellation -> PRE_RESERVATION_CLOSED
SELECT tests.assert_raises(
  format(
    $$SELECT public.cancel_pre_reservation(%L::uuid, 'De nuevo')$$,
    :'cancel_pr'::jsonb ->> 'pre_reservation_id'
  ),
  'PRE_RESERVATION_CLOSED',
  'a cancelled pre-reservation cannot be cancelled again'
);

RESET ROLE;
ROLLBACK;