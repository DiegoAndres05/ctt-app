-- pre_reservation_item_identifiers_test.sql
-- Regression for defect D1 (stabilization 2026-11-11, migration 056): the
-- "exactly one of product_id / addon_id" rule of resolve_pre_reservation_item is evaluated on
-- the effective values, so an explicit JSON null on the unused key (the shape the panel sends)
-- is accepted, while ambiguous, empty and malformed identifiers stay rejected.
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/pre_reservation_item_identifiers_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set org_id      05600000-0000-4000-a000-000000000001
\set org_b_id    05600000-0000-4000-a000-000000000002
\set agent_id    05600000-0000-4000-b000-000000000001
\set provider_id 05600000-0000-4000-e000-000000000001
\set missing_id  05600000-0000-4000-f000-000000000099

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid, p_organization_id uuid, p_email text, p_full_name text,
  p_role public.app_role
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
          p_email, now(), now());
  INSERT INTO public.user_profiles (
    id, organization_id, full_name, email, role, status, must_change_password
  ) VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, 'active', false);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user_id uuid, p_organization_id uuid, p_app_role text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_user_id::text, 'role', 'authenticated',
    'app_role', p_app_role, 'organization_id', p_organization_id::text
  )::text, true);
END;
$$;

-- Fixtures. Tariffs carry an explicit, fixed validity window so the suite does not depend on
-- the execution date; travel dates are far in the future for the same reason.
INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_id'::uuid, 'Item Ids Org', 'item-ids-org', 'active', '{"default_currency":"COP"}'::jsonb),
  (:'org_b_id'::uuid, 'Item Ids Org B', 'item-ids-org-b', 'active', '{"default_currency":"COP"}'::jsonb);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-item-ids@test.invalid', 'Agent Ids', 'agent');

INSERT INTO public.providers (id, organization_id, name, contact_phone, contact_email, is_active)
VALUES (:'provider_id'::uuid, :'org_id'::uuid, 'Lanchas Ids', '+573001112299', 'ids@lanchas.test', true);

INSERT INTO public.products (organization_id, name, type, status, provider_id)
VALUES (:'org_id'::uuid, 'Tour Ids', 'experience', 'draft', :'provider_id'::uuid)
RETURNING id AS product_id \gset
INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
) VALUES (
  :'org_id'::uuid, :'product_id'::uuid, 'COP', 90000, 'per_person',
  TIMESTAMPTZ '2026-01-01 00:00:00+00', NULL
);
UPDATE public.products SET status = 'active' WHERE id = :'product_id'::uuid;

INSERT INTO public.add_ons (organization_id, name, unit)
VALUES (:'org_id'::uuid, 'Transporte Ids', 'per_service')
RETURNING id AS addon_id \gset
INSERT INTO public.pricing_schemes (
  organization_id, addon_id, currency, base_amount, charge_type, valid_from, valid_to
) VALUES (
  :'org_id'::uuid, :'addon_id'::uuid, 'COP', 40000, 'per_group',
  TIMESTAMPTZ '2026-01-01 00:00:00+00', NULL
);

-- A product of another tenant: must never resolve for org_id.
INSERT INTO public.products (organization_id, name, type, status)
VALUES (:'org_b_id'::uuid, 'Tour Org B', 'experience', 'draft')
RETURNING id AS product_b_id \gset

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Ida","email":"ida-item-ids@test.invalid","phone":"3001110056"}'::jsonb,
  '{"travel_start_date":"2030-06-01","travel_end_date":"2030-06-05","adults":2}'::jsonb,
  '[{"free_text":"Tour","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset

-- ===========================================================================
-- 1. resolve_pre_reservation_item: identifier matrix
-- ===========================================================================

\echo '--- resolve_pre_reservation_item: product_id / addon_id ---'

SELECT tests.assert_equals(
  public.resolve_pre_reservation_item(:'org_id'::uuid, :'req_id'::uuid, jsonb_build_object(
    'product_id', :'product_id', 'start_date', '2030-06-01', 'adults', 2
  )) ->> 'product_id',
  :'product_id',
  'product without the addon_id key resolves'
);

SELECT tests.assert_true(
  format(
    $$SELECT r ->> 'product_id' = %L AND r ->> 'item_kind' = 'experience' AND NOT (r ? 'addon_id')
        FROM (SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid, jsonb_build_object(
          'product_id', %L, 'addon_id', NULL, 'start_date', '2030-06-01', 'adults', 2
        )) AS r) s$$,
    :'product_id', :'org_id', :'req_id', :'product_id'
  ),
  'product with "addon_id": null resolves as a product line (D1)'
);

SELECT tests.assert_equals(
  public.resolve_pre_reservation_item(:'org_id'::uuid, :'req_id'::uuid, jsonb_build_object(
    'addon_id', :'addon_id', 'start_date', '2030-06-01', 'adults', 2
  )) ->> 'item_kind',
  'addon',
  'add-on without the product_id key resolves'
);

SELECT tests.assert_true(
  format(
    $$SELECT r ->> 'addon_id' = %L AND r ->> 'item_kind' = 'addon' AND NOT (r ? 'product_id')
        FROM (SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid, jsonb_build_object(
          'product_id', NULL, 'addon_id', %L, 'start_date', '2030-06-01', 'adults', 2
        )) AS r) s$$,
    :'addon_id', :'org_id', :'req_id', :'addon_id'
  ),
  'add-on with "product_id": null resolves as an add-on line (D1)'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid, jsonb_build_object(
        'product_id', %L, 'addon_id', %L, 'start_date', '2030-06-01'))$$,
    :'org_id', :'req_id', :'product_id', :'addon_id'
  ),
  'VALIDATION_ERROR',
  'both identifiers with values are rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid,
        '{"start_date":"2030-06-01","adults":1}'::jsonb)$$,
    :'org_id', :'req_id'
  ),
  'VALIDATION_ERROR',
  'both identifiers absent are rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid,
        '{"product_id":null,"addon_id":null,"start_date":"2030-06-01","adults":1}'::jsonb)$$,
    :'org_id', :'req_id'
  ),
  'VALIDATION_ERROR',
  'both identifiers null are rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid,
        '{"product_id":"  ","addon_id":null,"start_date":"2030-06-01","adults":1}'::jsonb)$$,
    :'org_id', :'req_id'
  ),
  'VALIDATION_ERROR',
  'a blank product_id with a null addon_id is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid,
        '{"product_id":"not-a-uuid","addon_id":null,"start_date":"2030-06-01","adults":1}'::jsonb)$$,
    :'org_id', :'req_id'
  ),
  'VALIDATION_ERROR',
  'a malformed product_id is a controlled VALIDATION_ERROR'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid,
        '{"product_id":null,"addon_id":"123","start_date":"2030-06-01","adults":1}'::jsonb)$$,
    :'org_id', :'req_id'
  ),
  'VALIDATION_ERROR',
  'a malformed addon_id is a controlled VALIDATION_ERROR'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid, jsonb_build_object(
        'product_id', %L, 'addon_id', NULL, 'start_date', '2030-06-01'))$$,
    :'org_id', :'req_id', :'missing_id'
  ),
  'ITEM_NOT_BOOKABLE',
  'a non-existent product_id is ITEM_NOT_BOOKABLE'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid, jsonb_build_object(
        'product_id', NULL, 'addon_id', %L, 'start_date', '2030-06-01'))$$,
    :'org_id', :'req_id', :'missing_id'
  ),
  'ITEM_NOT_BOOKABLE',
  'a non-existent addon_id is ITEM_NOT_BOOKABLE'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.resolve_pre_reservation_item(%L::uuid, %L::uuid, jsonb_build_object(
        'product_id', %L, 'addon_id', NULL, 'start_date', '2030-06-01'))$$,
    :'org_id', :'req_id', :'product_b_id'
  ),
  'ITEM_NOT_BOOKABLE',
  'another tenant''s product is ITEM_NOT_BOOKABLE'
);

-- The function stays internal after the redefinition.
SELECT tests.assert_true(
  $$SELECT NOT has_function_privilege('authenticated',
      'public.resolve_pre_reservation_item(uuid, uuid, jsonb)', 'EXECUTE')
       AND NOT has_function_privilege('anon',
      'public.resolve_pre_reservation_item(uuid, uuid, jsonb)', 'EXECUTE')$$,
  'resolve_pre_reservation_item is still not executable by anon/authenticated'
);

-- ===========================================================================
-- 2. Public RPCs with the exact payload shape the panel sends
-- ===========================================================================

\echo '--- create_pre_reservation / add_pre_reservation_item (panel payload) ---'

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

-- buildCreatePayload before the client fix: every key present, unused ones null.
SELECT public.create_pre_reservation(
  :'req_id'::uuid,
  jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', :'product_id', 'addon_id', NULL,
      'start_date', '2030-06-01', 'end_date', NULL,
      'adults', 2, 'children', 0, 'quantity', 1,
      'source_request_item_id', NULL,
      'provider_name', NULL, 'provider_phone', NULL, 'provider_email', NULL
    )),
    'assigned_operator_id', NULL
  )
) AS created \gset

SELECT tests.assert_equals(
  :'created'::jsonb ->> 'status',
  'pending_verification',
  'create_pre_reservation accepts a product line with "addon_id": null (D1)'
);

SELECT (:'created'::jsonb ->> 'pre_reservation_id') AS prid \gset

-- Add-on line with "product_id": null and no alternative.
SELECT public.add_pre_reservation_item(
  :'prid'::uuid,
  jsonb_build_object(
    'product_id', NULL, 'addon_id', :'addon_id',
    'start_date', '2030-06-02', 'end_date', NULL,
    'adults', 2, 'children', 0, 'quantity', 1,
    'source_request_item_id', NULL,
    'provider_name', 'Transportes Isla', 'provider_phone', NULL, 'provider_email', NULL,
    'alternative_of_item_id', NULL
  )
) AS added_addon \gset

-- Product line with "addon_id": null.
SELECT public.add_pre_reservation_item(
  :'prid'::uuid,
  jsonb_build_object(
    'product_id', :'product_id', 'addon_id', NULL,
    'start_date', '2030-06-03', 'adults', 1, 'children', 0, 'quantity', 1,
    'alternative_of_item_id', NULL
  )
) AS added_product \gset

SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb ? 'item_id' AND %L::jsonb ? 'item_id'$$,
    :'added_addon', :'added_product'
  ),
  'add_pre_reservation_item accepts add-on and product lines with the unused key null (D1)'
);

-- Same pre-reservation, still rejects ambiguous lines through the public RPC.
SELECT tests.assert_raises(
  format(
    $$SELECT public.add_pre_reservation_item(%L::uuid, jsonb_build_object(
        'product_id', %L, 'addon_id', %L, 'start_date', '2030-06-04', 'adults', 1))$$,
    :'prid', :'product_id', :'addon_id'
  ),
  'VALIDATION_ERROR',
  'add_pre_reservation_item still rejects a line with both identifiers'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.add_pre_reservation_item(%L::uuid,
        '{"product_id":null,"addon_id":null,"start_date":"2030-06-04","adults":1}'::jsonb)$$,
    :'prid'
  ),
  'VALIDATION_ERROR',
  'add_pre_reservation_item still rejects a line without identifiers'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 3
         AND count(*) FILTER (WHERE item_kind = 'addon' AND addon_id = %L AND product_id IS NULL) = 1
         AND count(*) FILTER (WHERE item_kind = 'experience' AND product_id = %L AND addon_id IS NULL) = 2
       FROM public.pre_reservation_items
       WHERE pre_reservation_id = %L$$,
    :'addon_id', :'product_id', :'prid'
  ),
  'the pre-reservation holds the 3 lines with the right identifiers'
);

\echo '--- pre_reservation_item_identifiers_test: all assertions passed ---'

ROLLBACK;
