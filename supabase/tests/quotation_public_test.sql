-- quotation_public_test.sql
-- US3 tests: the public token link and the WhatsApp copy body
-- (quickstart scenario 3, spec FR-007/FR-012).
-- Run with: ./supabase/tests/run-sql-tests.sh quotation_public_test.sql
--
-- Covers: a valid token returns the frozen breakdown with can_accept true and
-- no customer_id / email / phone / token / notes / pre_reservation keys; empty,
-- unknown and tampered tokens return { available: false } without lines; an
-- expired version answers can_accept false, an accepted one too, and a voided
-- one { available: false }; quotation_whatsapp_text carries the reference and
-- the total and never https:// nor the token; anon can execute
-- get_public_quotation (and only it plus accept_public_quotation) but cannot
-- SELECT quotation_versions nor execute the other 004/005 RPCs.

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id       07000000-0000-4000-a000-000000000001
\set agent_id     07000000-0000-4000-b000-000000000001
\set admin_id     07000000-0000-4000-b000-000000000002
\set customer_id  07000000-0000-4000-c000-000000000001

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

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

CREATE OR REPLACE FUNCTION pg_temp.add_product(
  p_org uuid,
  p_name text,
  p_type public.product_type,
  p_charge public.charge_type,
  p_amount numeric,
  p_currency text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.products (organization_id, name, type, status)
  VALUES (p_org, p_name, p_type, 'draft')
  RETURNING id INTO v_id;

  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from
  ) VALUES (
    p_org, v_id, p_currency::char(3), p_amount, p_charge, now() - interval '1 day'
  );

  UPDATE public.products SET status = 'active' WHERE id = v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.make_quotable(
  p_pre_reservation_id uuid,
  p_verified_by uuid,
  p_hold interval DEFAULT interval '3 days'
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.pre_reservation_items
  SET verification_status = 'available',
      verified_by = p_verified_by,
      verified_at = now(),
      provider_contact_person = 'Proveedor Test',
      contact_method = 'phone',
      hold_expires_at = now() + p_hold
  WHERE pre_reservation_id = p_pre_reservation_id;
  PERFORM public.refresh_pre_reservation_status(p_pre_reservation_id);
END;
$$;

-- Superuser test trick: valid_until is frozen outside draft (see issue suite).
CREATE OR REPLACE FUNCTION pg_temp.force_valid_until(
  p_version_id uuid,
  p_when timestamptz
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.quotation_versions SET status = 'draft' WHERE id = p_version_id;
  UPDATE public.quotation_versions SET valid_until = p_when WHERE id = p_version_id;
  UPDATE public.quotation_versions SET status = 'issued' WHERE id = p_version_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Setup: organization, collaborators, customer, request, catalog
-- ---------------------------------------------------------------------------

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (
  :'org_id'::uuid, 'Quotation Public Org', 'quotation-public-org', 'active',
  '{"default_phone_country_code":"57","default_currency":"COP"}'::jsonb
);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-quotation-public@test.invalid', 'Agent Quotation Public', 'agent');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-quotation-public@test.invalid', 'Admin Quotation Public', 'admin');

INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Test', 'Public', 'quotation-public@test.invalid', '+573003337788', :'agent_id'::uuid);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Test","email":"quotation-public@test.invalid","phone":"3003337788"}'::jsonb,
  '{"travel_start_date":"2030-03-10","adults":2}'::jsonb,
  '[{"free_text":"Quotation public tour","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset

SELECT pg_temp.add_product(:'org_id'::uuid, 'Tour público', 'experience', 'per_person', 100.00, 'COP') AS p_tour \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_tour', 'start_date', '2030-03-10', 'adults', 2, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr1_result \gset
SELECT (:'pr1_result'::jsonb ->> 'pre_reservation_id') AS pr1 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_tour', 'start_date', '2030-03-15', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr2_result \gset
SELECT (:'pr2_result'::jsonb ->> 'pre_reservation_id') AS pr2 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_tour', 'start_date', '2030-03-20', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr3_result \gset
SELECT (:'pr3_result'::jsonb ->> 'pre_reservation_id') AS pr3 \gset

SELECT pg_temp.make_quotable(:'pr1'::uuid, :'agent_id'::uuid);
SELECT pg_temp.make_quotable(:'pr2'::uuid, :'agent_id'::uuid);
SELECT pg_temp.make_quotable(:'pr3'::uuid, :'agent_id'::uuid);

-- Setup: three issued quotations with public tokens
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.create_quotation_draft(:'pr1'::uuid) AS b1 \gset
SELECT (:'b1'::jsonb ->> 'version_id') AS v1 \gset
SELECT public.issue_quotation(:'v1'::uuid) AS issue1 \gset
SELECT (:'issue1'::jsonb ->> 'public_token') AS token1 \gset

SELECT public.create_quotation_draft(:'pr2'::uuid) AS b2 \gset
SELECT (:'b2'::jsonb ->> 'version_id') AS v2 \gset
SELECT public.issue_quotation(:'v2'::uuid) AS issue2 \gset
SELECT (:'issue2'::jsonb ->> 'public_token') AS token2 \gset

SELECT public.create_quotation_draft(:'pr3'::uuid) AS b3 \gset
SELECT (:'b3'::jsonb ->> 'version_id') AS v3 \gset
SELECT public.issue_quotation(:'v3'::uuid) AS issue3 \gset
SELECT (:'issue3'::jsonb ->> 'public_token') AS token3 \gset

-- =============================================================================
-- TEST: anon reads an issued proposal by token with no PII and no token keys
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;

SELECT public.get_public_quotation(:'token1'::text) AS pub1 \gset

SELECT tests.assert_true(
  format($$SELECT %L::jsonb ->> 'available' = 'true'
             AND %L::jsonb ->> 'status' = 'issued'
             AND %L::jsonb ->> 'reference' = 'COT-00001'
             AND (%L::jsonb ->> 'can_accept')::boolean$$, :'pub1', :'pub1', :'pub1', :'pub1'),
  'a valid token returns the issued proposal with can_accept true'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{total}')::numeric = 200.00
             AND (%L::jsonb #>> '{subtotal}')::numeric = 200.00
             AND jsonb_array_length(%L::jsonb -> 'lines') = 1
             AND (%L::jsonb #>> '{lines,0,label}') = 'Tour público'
             AND (%L::jsonb #>> '{lines,0,line_total}')::numeric = 200.00$$,
    :'pub1', :'pub1', :'pub1', :'pub1', :'pub1'),
  'the public payload carries the frozen breakdown: 2 adults x 100.00 = 200.00'
);

SELECT tests.assert_true(
  format(
    $$SELECT NOT (%L::jsonb ? 'customer_id')
             AND NOT (%L::jsonb ? 'email')
             AND NOT (%L::jsonb ? 'phone')
             AND NOT (%L::jsonb ? 'token')
             AND NOT (%L::jsonb ? 'public_token')
             AND NOT (%L::jsonb ? 'commercial_notes')
             AND NOT (%L::jsonb ? 'pre_reservation_id')$$,
    :'pub1', :'pub1', :'pub1', :'pub1', :'pub1', :'pub1', :'pub1'
  ),
  'the public payload has no customer_id, email, phone, token, notes or pre-reservation keys'
);

SELECT tests.assert_true(
  format(
    $$SELECT %L::text NOT LIKE '%%quotation-public@test.invalid%%'
             AND %L::text NOT LIKE '%%+573003337788%%'
             AND %L::text NOT LIKE '%%' || %L::text || '%%'$$,
    :'pub1', :'pub1', :'pub1', :'token1'
  ),
  'the public payload never contains the customer email, phone or the clear token'
);

-- =============================================================================
-- TEST: empty, unknown and tampered tokens answer { available: false }
-- =============================================================================
SELECT tests.assert_true(
  $$SELECT public.get_public_quotation('') = '{"available": false}'::jsonb$$,
  'an empty token answers available false'
);

SELECT public.get_public_quotation('token-desconocido') AS pub_unknown \gset

SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb = '{"available": false}'::jsonb
             AND NOT (%L::jsonb ? 'lines')$$,
    :'pub_unknown', :'pub_unknown'
  ),
  'an unknown token answers available false without lines'
);

SELECT public.get_public_quotation(:'token1'::text || 'AAA') AS pub_tampered \gset

SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb = '{"available": false}'::jsonb
             AND NOT (%L::jsonb ? 'lines')$$,
    :'pub_tampered', :'pub_tampered'
  ),
  'a tampered token answers available false without lines'
);

-- =============================================================================
-- TEST: quotation_whatsapp_text carries the reference and the total, never the
-- URL nor the token
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.quotation_whatsapp_text(:'v1'::uuid) AS wa1 \gset

SELECT tests.assert_true(
  format(
    $$SELECT %L::text LIKE '%%COT-00001%%'
             AND %L::text LIKE '%%Total: COP 200%%'$$,
    :'wa1', :'wa1'
  ),
  'the WhatsApp body carries the reference and the frozen total'
);

SELECT tests.assert_true(
  format(
    $$SELECT %L::text NOT LIKE '%%https://%%'
             AND %L::text NOT LIKE '%%http://%%'
             AND %L::text NOT LIKE '%%' || %L::text || '%%'$$,
    :'wa1', :'wa1', :'wa1', :'token1'
  ),
  'the WhatsApp body has no URL and never the clear token'
);

-- =============================================================================
-- TEST: an expired version answers can_accept false
-- =============================================================================
RESET ROLE;
SELECT pg_temp.force_valid_until(:'v1'::uuid, now() - interval '1 hour');

SET LOCAL ROLE anon;

SELECT public.get_public_quotation(:'token1'::text) AS pub_expired \gset

SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb ->> 'available' = 'true'
             AND %L::jsonb ->> 'status' = 'expired'
             AND (%L::jsonb ->> 'can_accept')::boolean = false$$,
    :'pub_expired', :'pub_expired', :'pub_expired'
  ),
  'an expired proposal is readable but can_accept is false'
);

-- =============================================================================
-- TEST: an accepted version answers can_accept false
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.accept_public_quotation(:'token2'::text, true) AS acc2 \gset

SELECT tests.assert_equals(
  (:'acc2'::jsonb ->> 'status'),
  'accepted',
  'the public acceptance with confirmation succeeds'
);

RESET ROLE;
SET LOCAL ROLE anon;

SELECT public.get_public_quotation(:'token2'::text) AS pub_accepted \gset

SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb ->> 'available' = 'true'
             AND %L::jsonb ->> 'status' = 'accepted'
             AND (%L::jsonb ->> 'can_accept')::boolean = false$$,
    :'pub_accepted', :'pub_accepted', :'pub_accepted'
  ),
  'an accepted proposal is readable but can_accept is false'
);

-- =============================================================================
-- TEST: a voided version kills the link: available false without lines
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT public.void_quotation(:'v3'::uuid, 'Duplicada con otra propuesta.') AS void3 \gset

RESET ROLE;
SET LOCAL ROLE anon;

SELECT public.get_public_quotation(:'token3'::text) AS pub_voided \gset

SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb = '{"available": false}'::jsonb
             AND NOT (%L::jsonb ? 'lines')$$,
    :'pub_voided', :'pub_voided'
  ),
  'a voided proposal answers available false without lines'
);

-- =============================================================================
-- TEST: anon executes get_public_quotation and nothing else
-- =============================================================================
RESET ROLE;

SELECT tests.assert_true(
  $q$SELECT has_function_privilege('anon', 'public.get_public_quotation(text)', 'EXECUTE')
       AND has_function_privilege('anon', 'public.accept_public_quotation(text,boolean)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.create_quotation_draft(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.recalculate_quotation(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.set_quotation_terms(uuid,text,timestamptz)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.issue_quotation(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.expire_due_quotations()', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.upsert_quotation_defaults(text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.quotation_whatsapp_text(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.record_quotation_response(uuid,public.quotation_response_kind)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.create_quotation_version(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.void_quotation(uuid,text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.assert_quotation_confirmable(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.quotation_family_id_by_token(text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.quotation_current_version_id(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.expire_due_quotations_core(uuid,boolean)', 'EXECUTE')$q$,
  'anon holds EXECUTE only on get_public_quotation and accept_public_quotation'
);

SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format($$SELECT public.create_quotation_draft(%L::uuid)$$, :'pr1'),
  'permission denied',
  'anon cannot EXECUTE create_quotation_draft'
);

SELECT tests.assert_raises(
  format($$SELECT public.issue_quotation(%L::uuid)$$, :'v1'),
  'permission denied',
  'anon cannot EXECUTE issue_quotation'
);

SELECT tests.assert_raises(
  format($$SELECT public.quotation_whatsapp_text(%L::uuid)$$, :'v1'),
  'permission denied',
  'anon cannot EXECUTE quotation_whatsapp_text'
);

SELECT tests.assert_raises(
  format($$SELECT public.record_quotation_response(%L::uuid, 'accepted')$$, :'v1'),
  'permission denied',
  'anon cannot EXECUTE record_quotation_response'
);

SELECT tests.assert_raises(
  format($$SELECT public.assert_pre_reservation_quotable(%L::uuid, %L::uuid)$$, :'org_id', :'pr1'),
  'permission denied',
  'anon cannot EXECUTE the 004 gate assert_pre_reservation_quotable'
);

SELECT tests.assert_raises(
  'SELECT * FROM public.quotation_versions',
  'permission denied',
  'anon cannot SELECT quotation_versions'
);

RESET ROLE;
ROLLBACK;
