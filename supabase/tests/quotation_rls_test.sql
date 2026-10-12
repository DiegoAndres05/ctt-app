-- quotation_rls_test.sql
-- RLS and privilege tests for the quotation foundational tables (042-044).
-- Run with: ./supabase/tests/run-sql-tests.sh quotation_rls_test.sql
--
-- Covers: anon has no SELECT on the six tables nor on quotation_list; an
-- authenticated user of another organization sees no rows; the internal pricing
-- functions of 044 are not executable by anon or authenticated; authenticated
-- cannot write the quotation tables directly.

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id         05000000-0000-4000-a000-000000000001
\set org_b_id       05000000-0000-4000-a000-000000000002
\set agent_id       05000000-0000-4000-b000-000000000001
\set agent_b_id     05000000-0000-4000-b000-000000000002
\set customer_id    05000000-0000-4000-c000-000000000001
\set product_id     05000000-0000-4000-d000-000000000001

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
  (:'org_id'::uuid, 'Quotation RLS Org', 'quotation-rls-org', 'active',
   '{"default_phone_country_code":"57","default_currency":"COP"}'::jsonb),
  (:'org_b_id'::uuid, 'Quotation RLS Org B', 'quotation-rls-org-b', 'active',
   '{"default_phone_country_code":"57","default_currency":"COP"}'::jsonb);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-quotation-rls@test.invalid', 'Agent Quotation RLS', 'agent');
SELECT pg_temp.add_collaborator(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent-quotation-rls-b@test.invalid', 'Agent Quotation RLS B', 'agent');

-- Setup: customer and request
INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Test', 'Quotation', 'quotation-rls@test.invalid', '+573001112233', :'agent_id'::uuid);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Test","email":"quotation-rls@test.invalid","phone":"3001112233"}'::jsonb,
  '{"travel_start_date":"2027-03-15","adults":2}'::jsonb,
  '[{"free_text":"Test tour","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset

-- Setup: pre-reservation, product and item (direct inserts as superuser)
INSERT INTO public.pre_reservations (
  organization_id, reference, request_id, customer_id, responsible_agent_id, created_by
) VALUES (
  :'org_id'::uuid, 'PRE-95001', :'req_id'::uuid, :'customer_id'::uuid, :'agent_id'::uuid, :'agent_id'::uuid
) RETURNING id AS pr_id \gset

INSERT INTO public.products (id, organization_id, name, type, status)
VALUES (:'product_id'::uuid, :'org_id'::uuid, 'Quotation RLS Tour', 'experience', 'draft');

INSERT INTO public.pre_reservation_items (
  organization_id, pre_reservation_id, position, item_kind, product_id,
  item_label, start_date, adults, children, quantity
) VALUES (
  :'org_id'::uuid, :'pr_id'::uuid, 0, 'experience', :'product_id'::uuid,
  'Quotation RLS Tour', '2027-03-15', 2, 0, 1
);

-- Setup: quotation rows, one per table
INSERT INTO public.quotation_families (
  organization_id, pre_reservation_id, customer_id, created_by
) VALUES (
  :'org_id'::uuid, :'pr_id'::uuid, :'customer_id'::uuid, :'agent_id'::uuid
) RETURNING id AS family_id \gset

INSERT INTO public.quotation_versions (
  organization_id, family_id, version_number, status, currency, created_by
) VALUES (
  :'org_id'::uuid, :'family_id'::uuid, 1, 'draft', 'COP', :'agent_id'::uuid
) RETURNING id AS version_id \gset

INSERT INTO public.quotation_lines (
  organization_id, version_id, pre_reservation_item_id, position,
  item_kind, item_label, product_id, start_date,
  adults, children, quantity, charge_type, charge_basis,
  tariff_currency, tariff_amount, unit_price,
  line_base, line_adjustment, line_tax, line_total
)
SELECT
  :'org_id'::uuid, :'version_id'::uuid, i.id, 0,
  'experience', 'Quotation RLS Tour', :'product_id'::uuid, '2027-03-15',
  2, 0, 1, 'per_person', 2,
  'COP', 100.00, 100.00,
  200.00, 0, 0, 200.00
FROM public.pre_reservation_items i
WHERE i.pre_reservation_id = :'pr_id'::uuid
RETURNING id AS line_id \gset

INSERT INTO public.quotation_adjustments (
  organization_id, version_id, pre_reservation_item_id, label,
  direction, kind, value, created_by
)
SELECT
  :'org_id'::uuid, :'version_id'::uuid, i.id, 'RLS cortesía',
  'discount', 'percent', 5, :'agent_id'::uuid
FROM public.pre_reservation_items i
WHERE i.pre_reservation_id = :'pr_id'::uuid;

INSERT INTO public.quotation_responses (
  organization_id, version_id, kind, origin, created_by
) VALUES (
  :'org_id'::uuid, :'version_id'::uuid, 'changes_requested', 'agent', :'agent_id'::uuid
);

INSERT INTO public.quotation_defaults (organization_id, terms_template, created_by)
VALUES (:'org_id'::uuid, 'Condiciones de prueba.', :'agent_id'::uuid);

-- =============================================================================
-- TEST: anon cannot SELECT the six tables nor the view
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT * FROM public.quotation_families',
  'permission denied',
  'anon cannot SELECT quotation_families'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.quotation_versions',
  'permission denied',
  'anon cannot SELECT quotation_versions'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.quotation_lines',
  'permission denied',
  'anon cannot SELECT quotation_lines'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.quotation_adjustments',
  'permission denied',
  'anon cannot SELECT quotation_adjustments'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.quotation_responses',
  'permission denied',
  'anon cannot SELECT quotation_responses'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.quotation_defaults',
  'permission denied',
  'anon cannot SELECT quotation_defaults'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.quotation_list',
  'permission denied',
  'anon cannot SELECT quotation_list'
);

-- =============================================================================
-- TEST: the 044 pricing functions have no EXECUTE for anon
-- =============================================================================
SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('public.resolve_quotation_tariff(uuid,uuid,uuid,date)', 'EXECUTE')
       AND NOT has_function_privilege('public.recalculate_quotation_core(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.quotation_adjustment_impact(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.capture_pre_reservation_fingerprint(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.quotation_default_terms()', 'EXECUTE')$q$,
  'anon has no EXECUTE privilege on the 044 internal functions'
);

-- =============================================================================
-- TEST: authenticated of another organization sees no rows
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format($$SELECT count(*) = 0 FROM public.quotation_families$$),
  'agent B sees zero quotation_families'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 0 FROM public.quotation_versions$$),
  'agent B sees zero quotation_versions'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 0 FROM public.quotation_lines$$),
  'agent B sees zero quotation_lines'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 0 FROM public.quotation_adjustments$$),
  'agent B sees zero quotation_adjustments'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 0 FROM public.quotation_responses$$),
  'agent B sees zero quotation_responses'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 0 FROM public.quotation_defaults$$),
  'agent B sees zero quotation_defaults'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 0 FROM public.quotation_list$$),
  'agent B sees zero quotation_list rows'
);

-- =============================================================================
-- TEST: authenticated of the owning organization sees its rows
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format($$SELECT count(*) = 1 FROM public.quotation_families$$),
  'agent A sees its quotation_families'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 1 FROM public.quotation_versions$$),
  'agent A sees its quotation_versions'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 1 FROM public.quotation_lines$$),
  'agent A sees its quotation_lines'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 1 FROM public.quotation_adjustments$$),
  'agent A sees its quotation_adjustments'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 1 FROM public.quotation_responses$$),
  'agent A sees its quotation_responses'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 1 FROM public.quotation_defaults$$),
  'agent A sees its quotation_defaults'
);

SELECT tests.assert_true(
  format($$SELECT count(*) = 1 FROM public.quotation_list$$),
  'agent A sees its quotation_list row'
);

-- =============================================================================
-- TEST: the 044 pricing functions have no EXECUTE for authenticated
-- =============================================================================
SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('public.resolve_quotation_tariff(uuid,uuid,uuid,date)', 'EXECUTE')
       AND NOT has_function_privilege('public.recalculate_quotation_core(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.quotation_adjustment_impact(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.capture_pre_reservation_fingerprint(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('public.quotation_default_terms()', 'EXECUTE')$q$,
  'authenticated has no EXECUTE privilege on the 044 internal functions'
);

-- =============================================================================
-- TEST: authenticated cannot write the quotation tables directly
-- =============================================================================
SELECT tests.assert_raises(
  format(
    $$INSERT INTO public.quotation_versions (organization_id, family_id, version_number, status, currency)
       VALUES (%L::uuid, %L::uuid, 99, 'draft', 'COP')$$,
    :'org_id', :'family_id'
  ),
  'permission denied',
  'authenticated cannot INSERT quotation_versions'
);

SELECT tests.assert_raises(
  format(
    $$UPDATE public.quotation_versions SET total = 1 WHERE id = %L::uuid$$,
    :'version_id'
  ),
  'permission denied',
  'authenticated cannot UPDATE quotation_versions'
);

SELECT tests.assert_raises(
  format(
    $$DELETE FROM public.quotation_adjustments WHERE version_id = %L::uuid$$,
    :'version_id'
  ),
  'permission denied',
  'authenticated cannot DELETE quotation_adjustments'
);

RESET ROLE;
ROLLBACK;
