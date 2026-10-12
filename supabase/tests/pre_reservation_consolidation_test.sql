-- pre_reservation_consolidation_test.sql
-- US3 (T032): add_pre_reservation_item, withdraw_pre_reservation_item,
-- promote_alternative_item, authorize_quotation_override, assert_pre_reservation_quotable
-- and the quote_eligible rule of pre_reservation_list.
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/pre_reservation_consolidation_test.sql

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id          06000000-0000-4000-a000-000000000001
\set agent_id        06000000-0000-4000-b000-000000000001
\set operator_id     06000000-0000-4000-b000-000000000002
\set admin_id        06000000-0000-4000-b000-000000000003
\set customer_id     06000000-0000-4000-c000-000000000001
\set product_a_id    06000000-0000-4000-d000-000000000001
\set product_b_id    06000000-0000-4000-d000-000000000002

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

-- Helper: mark a line available so a global status can be staged without going through US2.
-- Every field the table checks (outcome_complete, hold_only_available) is filled in.
CREATE OR REPLACE FUNCTION pg_temp.mark_available(
  p_item_id uuid,
  p_actor uuid,
  p_hold timestamptz
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.pre_reservation_items
  SET verification_status = 'available',
      verification_started_at = coalesce(verification_started_at, now()),
      verified_at = now(),
      verified_by = p_actor,
      provider_contact_person = 'Proveedor (pruebas)',
      contact_method = 'phone',
      hold_expires_at = p_hold
  WHERE id = p_item_id;
END;
$$;

-- =============================================================================
-- Setup: organization, collaborators, customer, products, request
-- =============================================================================
INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (:'org_id'::uuid, 'Consolidation Test Org', 'consolidation-test-org', 'active', '{"default_phone_country_code":"57"}'::jsonb);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-consolidation@test.invalid', 'Agent Consolidation', 'agent');
SELECT pg_temp.add_collaborator(:'operator_id'::uuid, :'org_id'::uuid, 'operator-consolidation@test.invalid', 'Operator Consolidation', 'operator');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-consolidation@test.invalid', 'Admin Consolidation', 'admin');

INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Iván', 'Soto', 'ivan-consolidation@test.invalid', '+573003334455', :'agent_id'::uuid);

-- Products must be priced before they can be active (enforce_active_requires_price).
INSERT INTO public.products (id, organization_id, name, type, status)
VALUES
  (:'product_a_id'::uuid, :'org_id'::uuid, 'Ciudad Tour', 'experience', 'draft'),
  (:'product_b_id'::uuid, :'org_id'::uuid, 'Hotel Centro', 'accommodation', 'draft');

INSERT INTO public.pricing_schemes (organization_id, product_id, base_amount, charge_type, valid_from)
VALUES
  (:'org_id'::uuid, :'product_a_id'::uuid, 120000, 'per_person', now() - interval '1 day'),
  (:'org_id'::uuid, :'product_b_id'::uuid, 280000, 'per_night', now() - interval '1 day');

UPDATE public.products
SET status = 'active'
WHERE id IN (:'product_a_id'::uuid, :'product_b_id'::uuid);

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Ivan","email":"ivan-consolidation@test.invalid","phone":"3003334455"}'::jsonb,
  '{"travel_start_date":"2028-09-01","travel_end_date":"2028-09-05","adults":2}'::jsonb,
  ('[{"product_id":"' || :'product_a_id' || '","quantity":1}]')::jsonb,
  NULL
) ->> 'request_id') AS req_id \gset

-- =============================================================================
-- Setup: one pre-reservation per scenario (created as the internal function requires)
-- =============================================================================
-- add scenario: starts with a single main line
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_a_id', 'start_date', '2028-09-01', 'adults', 2)
  )),
  :'agent_id'::uuid
) AS pr_add \gset

-- cancelled scenario
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_a_id', 'start_date', '2028-09-02', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_cancel \gset

-- withdraw scenario: two mains, an alternative is added during the test
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_a_id', 'start_date', '2028-09-03', 'adults', 1),
    jsonb_build_object('product_id', :'product_b_id', 'start_date', '2028-09-03', 'end_date', '2028-09-06', 'adults', 2)
  )),
  :'agent_id'::uuid
) AS pr_withdraw \gset

-- single-line scenario: it cannot be withdrawn
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_a_id', 'start_date', '2028-09-04', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_single \gset

-- promote scenario: two mains, two alternatives are added during the test
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_a_id', 'start_date', '2028-09-05', 'adults', 1),
    jsonb_build_object('product_id', :'product_b_id', 'start_date', '2028-09-05', 'end_date', '2028-09-08', 'adults', 2)
  )),
  :'agent_id'::uuid
) AS pr_promote \gset

-- quotable scenario: verified
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_a_id', 'start_date', '2028-09-06', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_verified \gset

-- expired scenario: available line whose hold already lapsed
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_a_id', 'start_date', '2028-09-07', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_expired \gset

-- pending scenario: never verified, gets the admin override at the end
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'product_a_id', 'start_date', '2028-09-08', 'adults', 1)
  )),
  :'agent_id'::uuid
) AS pr_pending \gset

SELECT id AS item_add1_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_add'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT id AS item_cancel_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_cancel'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT (array_agg(id ORDER BY position))[1] AS item_w_main1_id,
       (array_agg(id ORDER BY position))[2] AS item_w_main2_id
FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_withdraw'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT id AS item_single_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_single'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT (array_agg(id ORDER BY position))[1] AS item_prom1_id,
       (array_agg(id ORDER BY position))[2] AS item_prom2_id
FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_promote'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT id AS item_verified_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_verified'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT id AS item_expired_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_expired'::jsonb ->> 'pre_reservation_id')::uuid \gset

SELECT id AS item_pending_id FROM public.pre_reservation_items
WHERE pre_reservation_id = (:'pr_pending'::jsonb ->> 'pre_reservation_id')::uuid \gset

-- The cancelled scenario really is cancelled
SELECT public.cancel_pre_reservation(
  (:'pr_cancel'::jsonb ->> 'pre_reservation_id')::uuid,
  'La cliente desistió del viaje'
);

-- Stage the global statuses: verified, expired and (still) pending
SELECT pg_temp.mark_available(:'item_verified_id'::uuid, :'operator_id'::uuid, now() + interval '3 days');
SELECT pg_temp.mark_available(:'item_expired_id'::uuid, :'operator_id'::uuid, now() - interval '1 hour');

SELECT public.refresh_pre_reservation_status((:'pr_verified'::jsonb ->> 'pre_reservation_id')::uuid);
SELECT public.refresh_pre_reservation_status((:'pr_expired'::jsonb ->> 'pre_reservation_id')::uuid);

-- =============================================================================
-- TEST: assert_pre_reservation_quotable is internal (T032)
-- =============================================================================
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT public.assert_pre_reservation_quotable(gen_random_uuid(), gen_random_uuid())',
  'permission denied',
  'anon cannot EXECUTE assert_pre_reservation_quotable'
);

SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('public.assert_pre_reservation_quotable(uuid,uuid)', 'EXECUTE')$q$,
  'anon has no EXECUTE privilege on assert_pre_reservation_quotable'
);

RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  'SELECT public.assert_pre_reservation_quotable(gen_random_uuid(), gen_random_uuid())',
  'permission denied',
  'authenticated cannot EXECUTE assert_pre_reservation_quotable'
);

SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('public.assert_pre_reservation_quotable(uuid,uuid)', 'EXECUTE')$q$,
  'authenticated has no EXECUTE privilege on assert_pre_reservation_quotable'
);

-- =============================================================================
-- TEST: pending pre-reservation is not quotable yet (T032)
-- =============================================================================
RESET ROLE;

SELECT tests.assert_raises(
  format(
    $$SELECT public.assert_pre_reservation_quotable(%L::uuid, %L::uuid)$$,
    :'org_id', (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'PRE_RESERVATION_NOT_VERIFIED',
  'a pending pre-reservation is not quotable'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.assert_pre_reservation_quotable(%L::uuid, %L::uuid)$$,
    :'org_id', (:'pr_expired'::jsonb ->> 'pre_reservation_id')
  ),
  'PRE_RESERVATION_EXPIRED',
  'an expired pre-reservation without an override is not quotable'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.assert_pre_reservation_quotable(%L::uuid, %L::uuid)$$,
    :'org_id', (:'pr_cancel'::jsonb ->> 'pre_reservation_id')
  ),
  'PRE_RESERVATION_CLOSED',
  'a cancelled pre-reservation is never quotable'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_eligible = false
       FROM public.pre_reservation_list
       WHERE id = %L::uuid$$,
    (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'quote_eligible is false while pending'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_eligible = false
       FROM public.pre_reservation_list
       WHERE id = %L::uuid$$,
    (:'pr_expired'::jsonb ->> 'pre_reservation_id')
  ),
  'quote_eligible is false once expired'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_eligible = false
       FROM public.pre_reservation_list
       WHERE id = %L::uuid$$,
    (:'pr_cancel'::jsonb ->> 'pre_reservation_id')
  ),
  'quote_eligible is false once cancelled'
);

-- =============================================================================
-- TEST: add_pre_reservation_item (T032)
-- =============================================================================
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

-- An exception must exist before adding a main line can clear it
SELECT public.authorize_quotation_override(
  (:'pr_add'::jsonb ->> 'pre_reservation_id')::uuid,
  'Precio de emergencia aprobado'
) AS override_add1 \gset

SELECT public.add_pre_reservation_item(
  (:'pr_add'::jsonb ->> 'pre_reservation_id')::uuid,
  jsonb_build_object(
    'product_id', :'product_b_id',
    'start_date', '2028-09-01',
    'end_date', '2028-09-04',
    'adults', 2
  )
) AS add_main_result \gset

SELECT tests.assert_equals(
  (:'add_main_result'::jsonb ->> 'pre_reservation_status')::text,
  'pending_verification',
  'adding a main line returns the recomputed status'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 2
       FROM public.pre_reservation_items
       WHERE pre_reservation_id = %L::uuid$$,
    (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'the new main line was appended'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_override_at IS NULL
         AND quote_override_by IS NULL
         AND quote_override_reason IS NULL
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'adding a main line clears the quote override'
);

SELECT public.authorize_quotation_override(
  (:'pr_add'::jsonb ->> 'pre_reservation_id')::uuid,
  'Segunda excepción'
) AS override_add2 \gset

SELECT public.add_pre_reservation_item(
  (:'pr_add'::jsonb ->> 'pre_reservation_id')::uuid,
  jsonb_build_object(
    'product_id', :'product_b_id',
    'start_date', '2028-09-01',
    'end_date', '2028-09-03',
    'adults', 2,
    'alternative_of_item_id', :'item_add1_id'
  )
) AS add_alt_result \gset

-- Adding to a cancelled pre-reservation is rejected
SELECT tests.assert_raises(
  format(
    $$SELECT public.add_pre_reservation_item(%L::uuid, %L::jsonb)$$,
    (:'pr_cancel'::jsonb ->> 'pre_reservation_id'),
    jsonb_build_object('product_id', :'product_b_id', 'start_date', '2028-09-10', 'adults', 1)
  ),
  'PRE_RESERVATION_CLOSED',
  'add on a cancelled pre-reservation is rejected'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_override_at IS NOT NULL
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'adding an alternative keeps the quote override'
);

RESET ROLE;

-- =============================================================================
-- TEST: add audits {action:'added', override_cleared} (T032)
-- =============================================================================
SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 2
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_items_changed'
         AND resource_id = %L::uuid
         AND metadata ->> 'action' = 'added'$q$,
    (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'every added line writes one pre_reservation_items_changed audit'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 1
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_items_changed'
         AND resource_id = %L::uuid
         AND metadata ->> 'action' = 'added'
         AND (metadata ->> 'override_cleared')::boolean = true
         AND metadata ->> 'item_id' IS NOT NULL$q$,
    (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'adding a main line audits override_cleared = true with the new item id'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 1
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_items_changed'
         AND resource_id = %L::uuid
         AND metadata ->> 'action' = 'added'
         AND (metadata ->> 'override_cleared')::boolean = false$q$,
    (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'adding an alternative audits override_cleared = false'
);

-- =============================================================================
-- TEST: withdraw_pre_reservation_item (T032)
-- =============================================================================
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.add_pre_reservation_item(
  (:'pr_withdraw'::jsonb ->> 'pre_reservation_id')::uuid,
  jsonb_build_object(
    'product_id', :'product_a_id',
    'start_date', '2028-09-03',
    'adults', 1,
    'alternative_of_item_id', :'item_w_main1_id'
  )
) AS add_w_alt \gset

SELECT tests.assert_raises(
  format(
    $$SELECT public.withdraw_pre_reservation_item(%L::uuid, NULL)$$,
    :'item_w_main1_id'
  ),
  'VALIDATION_ERROR',
  'withdraw without a reason is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.withdraw_pre_reservation_item(%L::uuid, '   ')$$,
    :'item_w_main1_id'
  ),
  'VALIDATION_ERROR',
  'withdraw with a blank reason is rejected'
);

SELECT public.withdraw_pre_reservation_item(
  :'item_w_main1_id'::uuid,
  'El proveedor no tiene cupo'
) AS withdraw_result \gset

SELECT tests.assert_equals(
  jsonb_array_length(:'withdraw_result'::jsonb -> 'withdrawn_item_ids'),
  2,
  'withdrawing a main line takes its alternative with it'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.withdraw_pre_reservation_item(%L::uuid, %L)$$,
    :'item_w_main1_id', 'Otra vez'
  ),
  'ITEM_WITHDRAWN',
  'an already withdrawn line cannot be withdrawn again'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.withdraw_pre_reservation_item(%L::uuid, %L)$$,
    :'add_w_alt'::jsonb ->> 'item_id', 'Otra vez'
  ),
  'ITEM_WITHDRAWN',
  'the withdrawn alternative cannot be withdrawn again'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.withdraw_pre_reservation_item(%L::uuid, %L)$$,
    :'item_single_id', 'Se queda sin líneas'
  ),
  'PRE_RESERVATION_REQUIRES_ITEMS',
  'withdrawing the last main line is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.withdraw_pre_reservation_item(%L::uuid, %L)$$,
    :'item_cancel_id', 'Cualquier motivo'
  ),
  'PRE_RESERVATION_CLOSED',
  'withdraw on a cancelled pre-reservation is rejected'
);

RESET ROLE;

-- =============================================================================
-- TEST: withdraw writes one event per line and audits item_ids (T032)
-- =============================================================================
SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 2
         AND count(*) FILTER (WHERE withdrawn_at IS NOT NULL
                                AND withdrawn_reason = 'El proveedor no tiene cupo') = 2
       FROM public.pre_reservation_items
       WHERE id IN (%L::uuid, %L::uuid)$$,
    :'item_w_main1_id', (:'add_w_alt'::jsonb ->> 'item_id')
  ),
  'the main line and its alternative are both withdrawn with the reason'
);

SELECT tests.assert_true(
  format(
    $$SELECT withdrawn_at IS NULL
       FROM public.pre_reservation_items
       WHERE id = %L::uuid$$,
    :'item_w_main2_id'
  ),
  'the other main line stays active'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 2
       FROM public.availability_verification_events
       WHERE event_kind = 'item_withdrawn'
         AND item_id IN (%L::uuid, %L::uuid)$$,
    :'item_w_main1_id', (:'add_w_alt'::jsonb ->> 'item_id')
  ),
  'one item_withdrawn event is written per withdrawn line'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 1
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_items_changed'
         AND resource_id = %L::uuid
         AND metadata ->> 'action' = 'withdrawn'
         AND jsonb_array_length(metadata -> 'item_ids') = 2
         AND (metadata ->> 'override_cleared')::boolean = false$q$,
    (:'pr_withdraw'::jsonb ->> 'pre_reservation_id')
  ),
  'the withdrawal audits action, item_ids and override_cleared'
);

-- =============================================================================
-- TEST: promote_alternative_item (T032)
-- =============================================================================
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT public.authorize_quotation_override(
  (:'pr_promote'::jsonb ->> 'pre_reservation_id')::uuid,
  'Excepción antes de promover'
) AS override_promote \gset

SELECT public.add_pre_reservation_item(
  (:'pr_promote'::jsonb ->> 'pre_reservation_id')::uuid,
  jsonb_build_object(
    'product_id', :'product_a_id',
    'start_date', '2028-09-05',
    'adults', 1,
    'alternative_of_item_id', :'item_prom1_id'
  )
) AS prom_alt_a \gset

SELECT public.add_pre_reservation_item(
  (:'pr_promote'::jsonb ->> 'pre_reservation_id')::uuid,
  jsonb_build_object(
    'product_id', :'product_b_id',
    'start_date', '2028-09-05',
    'end_date', '2028-09-07',
    'adults', 2,
    'alternative_of_item_id', :'item_prom1_id'
  )
) AS prom_alt_b \gset

-- A main line cannot be promoted
SELECT tests.assert_raises(
  format(
    $$SELECT public.promote_alternative_item(%L::uuid)$$,
    :'item_prom1_id'
  ),
  'VALIDATION_ERROR',
  'promoting a main line is rejected'
);

SELECT public.promote_alternative_item(
  (:'prom_alt_a'::jsonb ->> 'item_id')::uuid
) AS promote_result \gset

SELECT tests.assert_equals(
  (:'promote_result'::jsonb ->> 'replaced_item_id')::text,
  :'item_prom1_id'::text,
  'promotion reports the replaced main line'
);

-- A withdrawn alternative cannot be promoted
SELECT tests.assert_raises(
  format(
    $$SELECT public.promote_alternative_item(%L::uuid)$$,
    :'add_w_alt'::jsonb ->> 'item_id'
  ),
  'ITEM_WITHDRAWN',
  'promoting a withdrawn alternative is rejected'
);

RESET ROLE;

-- =============================================================================
-- TEST: promotion rewires the lines, clears the override and writes events (T032)
-- =============================================================================
SELECT tests.assert_true(
  format(
    $$SELECT withdrawn_at IS NOT NULL
         AND withdrawn_reason = 'Reemplazada por alternativa'
       FROM public.pre_reservation_items
       WHERE id = %L::uuid$$,
    :'item_prom1_id'
  ),
  'the original main line is withdrawn with the automatic reason'
);

SELECT tests.assert_true(
  format(
    $$SELECT alternative_of_item_id IS NULL
       FROM public.pre_reservation_items
       WHERE id = %L::uuid$$,
    (:'prom_alt_a'::jsonb ->> 'item_id')
  ),
  'the promoted alternative becomes a main line'
);

SELECT tests.assert_true(
  format(
    $$SELECT alternative_of_item_id = %L::uuid
       FROM public.pre_reservation_items
       WHERE id = %L::uuid$$,
    (:'prom_alt_a'::jsonb ->> 'item_id'), (:'prom_alt_b'::jsonb ->> 'item_id')
  ),
  'the sibling alternative is reparented to the promoted line'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_override_at IS NULL
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    (:'pr_promote'::jsonb ->> 'pre_reservation_id')
  ),
  'promoting a line clears the quote override'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1
       FROM public.availability_verification_events
       WHERE event_kind = 'alternative_promoted'
         AND item_id = %L::uuid
         AND metadata ->> 'replaced_item_id' = %L
         AND from_status = to_status$$,
    (:'prom_alt_a'::jsonb ->> 'item_id'), :'item_prom1_id'
  ),
  'promotion writes alternative_promoted with metadata.replaced_item_id'
);

SELECT tests.assert_true(
  format(
    $q$SELECT count(*) = 1
       FROM audit.audit_events
       WHERE event_type = 'pre_reservation_items_changed'
         AND resource_id = %L::uuid
         AND metadata ->> 'action' = 'promoted'
         AND metadata ->> 'item_id' = %L
         AND metadata ->> 'replaced_item_id' = %L
         AND (metadata ->> 'override_cleared')::boolean = true$q$,
    (:'pr_promote'::jsonb ->> 'pre_reservation_id'),
    (:'prom_alt_a'::jsonb ->> 'item_id'),
    :'item_prom1_id'
  ),
  'the promotion audit records action, ids and override_cleared'
);

-- =============================================================================
-- TEST: authorize_quotation_override (T032)
-- =============================================================================
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $$SELECT public.authorize_quotation_override(%L::uuid, %L)$$,
    (:'pr_pending'::jsonb ->> 'pre_reservation_id'), 'Un motivo cualquiera'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an operator cannot authorize a quotation override'
);

RESET ROLE;
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $$SELECT public.authorize_quotation_override(%L::uuid, NULL)$$,
    (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'OVERRIDE_REASON_REQUIRED',
  'override without a reason is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.authorize_quotation_override(%L::uuid, '   ')$$,
    (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'OVERRIDE_REASON_REQUIRED',
  'override with a blank reason is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.authorize_quotation_override(%L::uuid, %L)$$,
    (:'pr_pending'::jsonb ->> 'pre_reservation_id'), repeat('x', 501)
  ),
  'VALIDATION_ERROR',
  'override reason longer than 500 is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.authorize_quotation_override(%L::uuid, %L)$$,
    (:'pr_verified'::jsonb ->> 'pre_reservation_id'), 'No haría falta'
  ),
  'OVERRIDE_NOT_REQUIRED',
  'a verified pre-reservation does not need an override'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.authorize_quotation_override(%L::uuid, %L)$$,
    (:'pr_cancel'::jsonb ->> 'pre_reservation_id'), 'Motivo'
  ),
  'PRE_RESERVATION_CLOSED',
  'override on a cancelled pre-reservation is rejected'
);

SELECT public.authorize_quotation_override(
  (:'pr_pending'::jsonb ->> 'pre_reservation_id')::uuid,
  'El cliente exige la cotización hoy'
) AS override_result \gset

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT quote_override_at IS NOT NULL
         AND quote_override_by = %L::uuid
         AND quote_override_reason = 'El cliente exige la cotización hoy'
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    :'admin_id', (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'the override stores timestamp, admin and reason'
);

SELECT tests.assert_true(
  format(
    $q$SELECT metadata ->> 'status' = 'pending_verification'
         AND NOT (metadata ? 'reason')
       FROM audit.audit_events
       WHERE event_type = 'quotation_override_authorized'
         AND resource_id = %L::uuid$q$,
    (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'the override audit stores {status} without the reason'
);

SELECT tests.assert_true(
  format(
    $q$SELECT notes = 'El cliente exige la cotización hoy'
         AND from_status IS NULL
         AND to_status IS NULL
       FROM public.availability_verification_events
       WHERE event_kind = 'quote_override_authorized'
         AND pre_reservation_id = %L::uuid$q$,
    (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'the override event keeps the reason in notes'
);

-- =============================================================================
-- TEST: assert_pre_reservation_quotable and quote_eligible agree (T032)
-- =============================================================================
SELECT tests.assert_true(
  format(
    $q$SELECT (r ->> 'eligible')::boolean
         AND r ->> 'basis' = 'verified'
         AND r ->> 'status' = 'verified'
       FROM (SELECT public.assert_pre_reservation_quotable(%L::uuid, %L::uuid) AS r) s$q$,
    :'org_id', (:'pr_verified'::jsonb ->> 'pre_reservation_id')
  ),
  'a verified pre-reservation is quotable on the verified basis'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_eligible = true
       FROM public.pre_reservation_list
       WHERE id = %L::uuid$$,
    (:'pr_verified'::jsonb ->> 'pre_reservation_id')
  ),
  'quote_eligible is true while verified'
);

-- The override keeps an expired pre-reservation quotable
SELECT pg_temp.mark_available(:'item_add1_id'::uuid, :'operator_id'::uuid, now() - interval '1 hour');

SELECT public.refresh_pre_reservation_status((:'pr_add'::jsonb ->> 'pre_reservation_id')::uuid);

SELECT tests.assert_true(
  format(
    $$SELECT status = 'expired'
       FROM public.pre_reservations
       WHERE id = %L::uuid$$,
    (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'the add scenario is expired after its hold lapsed'
);

SELECT tests.assert_true(
  format(
    $q$SELECT (r ->> 'eligible')::boolean
         AND r ->> 'basis' = 'override'
         AND r ->> 'status' = 'expired'
       FROM (SELECT public.assert_pre_reservation_quotable(%L::uuid, %L::uuid) AS r) s$q$,
    :'org_id', (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'a live exception covers an expired pre-reservation (basis override)'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_eligible = true
       FROM public.pre_reservation_list
       WHERE id = %L::uuid$$,
    (:'pr_add'::jsonb ->> 'pre_reservation_id')
  ),
  'quote_eligible is true while an override is live'
);

-- The override also covers the pending one
SELECT tests.assert_true(
  format(
    $q$SELECT (r ->> 'eligible')::boolean
         AND r ->> 'basis' = 'override'
       FROM (SELECT public.assert_pre_reservation_quotable(%L::uuid, %L::uuid) AS r) s$q$,
    :'org_id', (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'a live exception covers a pending pre-reservation (basis override)'
);

SELECT tests.assert_true(
  format(
    $$SELECT quote_eligible = true
       FROM public.pre_reservation_list
       WHERE id = %L::uuid$$,
    (:'pr_pending'::jsonb ->> 'pre_reservation_id')
  ),
  'quote_eligible is true for the pending pre-reservation with an override'
);

-- The list view follows the same rule for every row of the tenant
SELECT tests.assert_true(
  $q$SELECT count(*) = count(*) FILTER (
        WHERE quote_eligible = (status = 'verified'
                                OR (has_quote_override AND status <> 'cancelled'))
      )
      AND count(*) > 0
    FROM public.pre_reservation_list$q$,
  'quote_eligible matches the rule for every row in the list view'
);

RESET ROLE;
ROLLBACK;
