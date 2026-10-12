-- quotation_issue_test.sql
-- US2 tests: validity bounds, issuing, freezing and the expiry sweep
-- (quickstart scenario 2, spec FR-005/FR-008/FR-011).
-- Run with: ./supabase/tests/run-sql-tests.sh quotation_issue_test.sql
--
-- Covers: default valid_until at +48 hours; VALIDITY_EXCEEDS_HOLD past the
-- pre-reservation hold and VALIDITY_EXCEEDS_30_DAYS past the cap; TERMS_REQUIRED
-- from set_quotation_terms and at issue time; issuing from a draft only, with
-- COT-00001, the pre-reservation fingerprint and the once-only public token;
-- QUOTATION_FROZEN after issue (RPC and trigger); a catalog tariff change never
-- alters the frozen total; expire_due_quotations marks an overdue issued version
-- expired and audits quotation_expired without notes; upsert_quotation_defaults
-- is admin-only; anon cannot execute any US2 RPC.

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id       06000000-0000-4000-a000-000000000001
\set agent_id     06000000-0000-4000-b000-000000000001
\set admin_id     06000000-0000-4000-b000-000000000002
\set customer_id  06000000-0000-4000-c000-000000000001

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

-- Product with a current base tariff, activated after the tariff exists.
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

-- Marks every line of a pre-reservation as verified with a future hold, which
-- makes assert_pre_reservation_quotable accept it (feature 004). It then
-- refreshes the header status as superuser: assert_pre_reservation_quotable is
-- STABLE, so its internal re-read cannot observe the refresh it triggers, and
-- the header must already say 'verified' before the RPC is called.
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

-- Superuser test trick: valid_until is frozen outside draft, so a sweep test
-- briefly flips the version to draft, rewrites the instant and flips it back.
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
-- Setup: organization, collaborators, customer, request
-- ---------------------------------------------------------------------------

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (
  :'org_id'::uuid, 'Quotation Issue Org', 'quotation-issue-org', 'active',
  '{"default_phone_country_code":"57","default_currency":"COP"}'::jsonb
);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-quotation-issue@test.invalid', 'Agent Quotation Issue', 'agent');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-quotation-issue@test.invalid', 'Admin Quotation Issue', 'admin');

INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Test', 'Issue', 'quotation-issue@test.invalid', '+573002225566', :'agent_id'::uuid);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Test","email":"quotation-issue@test.invalid","phone":"3002225566"}'::jsonb,
  '{"travel_start_date":"2030-02-10","adults":2}'::jsonb,
  '[{"free_text":"Quotation issue tour","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset

-- Setup: catalog and two pre-reservations with a 3-day hold
SELECT pg_temp.add_product(:'org_id'::uuid, 'Tour emisión', 'experience', 'per_person', 100.00, 'COP') AS p_tour \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_tour', 'start_date', '2030-02-10', 'adults', 2, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr1_result \gset
SELECT (:'pr1_result'::jsonb ->> 'pre_reservation_id') AS pr1 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_tour', 'start_date', '2030-02-20', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr3_result \gset
SELECT (:'pr3_result'::jsonb ->> 'pre_reservation_id') AS pr3 \gset

SELECT pg_temp.make_quotable(:'pr1'::uuid, :'agent_id'::uuid);
SELECT pg_temp.make_quotable(:'pr3'::uuid, :'agent_id'::uuid);

-- =============================================================================
-- TEST: empty terms are rejected (TERMS_REQUIRED)
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.create_quotation_draft(:'pr1'::uuid) AS b1 \gset
SELECT (:'b1'::jsonb ->> 'version_id') AS v1 \gset

SELECT tests.assert_raises(
  format($$SELECT public.set_quotation_terms(%L::uuid, '', NULL)$$, :'v1'),
  'TERMS_REQUIRED',
  'set_quotation_terms rejects empty terms with TERMS_REQUIRED'
);

-- =============================================================================
-- TEST: validity beyond the hold and beyond the 30-day cap (R-006)
-- =============================================================================
SELECT tests.assert_raises(
  format(
    $$SELECT public.set_quotation_terms(%L::uuid, 'Condiciones de prueba.', now() + interval '5 days')$$,
    :'v1'
  ),
  'VALIDITY_EXCEEDS_HOLD',
  'validity past the 3-day pre-reservation hold raises VALIDITY_EXCEEDS_HOLD'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.set_quotation_terms(%L::uuid, 'Condiciones de prueba.', now() + interval '31 days')$$,
    :'v1'
  ),
  'VALIDITY_EXCEEDS_30_DAYS',
  'validity past 30 days raises VALIDITY_EXCEEDS_30_DAYS'
);

-- =============================================================================
-- TEST: issuing assigns COT-00001, defaults validity to +48h, stores token hash
-- and fingerprint; audit carries no token
-- =============================================================================
SELECT public.issue_quotation(:'v1'::uuid) AS issue1 \gset

SELECT tests.assert_equals(
  (:'issue1'::jsonb ->> 'reference'),
  'COT-00001',
  'first issue assigns the COT-00001 reference'
);

SELECT tests.assert_equals(
  (:'issue1'::jsonb ->> 'status'),
  'issued',
  'issue_quotation reports status issued'
);

SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb ->> 'public_token' IS NOT NULL$$, :'issue1'
  ),
  'issue returns the clear public token exactly once'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT abs(extract(epoch from (v.valid_until - v.issued_at - interval '48 hours'))) < 60
      FROM public.quotation_versions v WHERE v.id = %L::uuid$$,
    :'v1'
  ),
  'default validity is issued_at + 48 hours (within a minute)'
);

SELECT tests.assert_true(
  format(
    $$SELECT v.pre_reservation_fingerprint IS NOT NULL
             AND jsonb_array_length(v.pre_reservation_fingerprint) = 1
      FROM public.quotation_versions v WHERE v.id = %L::uuid$$,
    :'v1'
  ),
  'issuing stores the pre-reservation fingerprint'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM audit.audit_events
      WHERE organization_id = %L::uuid
        AND event_type = 'quotation_issued'
        AND resource_id = %L::uuid
        AND metadata ? 'version_number'
        AND metadata ? 'currency'
        AND NOT (metadata ? 'public_token')
        AND NOT (metadata ? 'token')
        AND NOT (metadata ? 'terms')$$,
    :'org_id', :'v1'
  ),
  'quotation_issued audit carries version_number/currency and never the token or terms'
);

-- The stored hash matches the returned clear token and no clear token is kept.
SELECT tests.assert_true(
  format(
    $$SELECT f.public_token_hash = encode(extensions.digest(%L::text, 'sha256'), 'hex')
             AND length(f.public_token_hash) = 64
      FROM public.quotation_families f
      JOIN public.quotation_versions v ON v.family_id = f.id AND v.organization_id = f.organization_id
      WHERE v.id = %L::uuid$$,
    (:'issue1'::jsonb ->> 'public_token'),
    :'v1'
  ),
  'the family stores only the SHA-256 hex of the returned token'
);

-- =============================================================================
-- TEST: issued versions are frozen (RPC and trigger)
-- =============================================================================
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format($$SELECT public.issue_quotation(%L::uuid)$$, :'v1'),
  'QUOTATION_FROZEN',
  'issuing twice is rejected: only a draft can be issued'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.set_quotation_terms(%L::uuid, 'Otras condiciones.', NULL)$$,
    :'v1'
  ),
  'QUOTATION_FROZEN',
  'terms of an issued version cannot be edited'
);

RESET ROLE;

SELECT tests.assert_raises(
  format(
    $$UPDATE public.quotation_lines SET unit_price = 999.00 WHERE version_id = %L::uuid$$,
    :'v1'
  ),
  'QUOTATION_FROZEN',
  'the freeze trigger rejects a unit_price UPDATE on an issued version'
);

-- =============================================================================
-- TEST: a catalog tariff change never alters the frozen total
-- =============================================================================
-- pricing_schemes is append-only (020): a new version with a later valid_from
-- is the catalog's way of changing a tariff.
INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type, valid_from
) VALUES (
  :'org_id'::uuid, :'p_tour'::uuid, 'COP', 9999.00, 'per_person', now()
);

SELECT tests.assert_true(
  format(
    $$SELECT v.total = 200.00
      FROM public.quotation_versions v WHERE v.id = %L::uuid$$,
    :'v1'
  ),
  'changing the catalog tariff does not alter the issued total: 2 adults x 100.00 = 200.00'
);

-- Retire the newer tariff for the rest of the suite (valid_to must exceed
-- valid_from; both stay decades before the 2030 service dates).
UPDATE public.pricing_schemes
SET valid_to = valid_from + interval '1 second'
WHERE organization_id = :'org_id'::uuid
  AND product_id = :'p_tour'::uuid
  AND base_amount = 9999.00;

-- =============================================================================
-- TEST: issue rejects a draft whose terms were emptied (TERMS_REQUIRED)
-- =============================================================================
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.create_quotation_draft(:'pr3'::uuid) AS b3 \gset
SELECT (:'b3'::jsonb ->> 'version_id') AS v3 \gset

SELECT public.set_quotation_terms(:'v3'::uuid, 'Condiciones aceptadas.', now() + interval '2 days') AS t3 \gset

SELECT tests.assert_true(
  format(
    $$SELECT (%L::jsonb ->> 'valid_until')::timestamptz > now() + interval '1 hour'
             AND (%L::jsonb ->> 'terms') = 'Condiciones aceptadas.'$$,
    :'t3', :'t3'
  ),
  'set_quotation_terms stores terms and a validity within the bounds'
);

RESET ROLE;
UPDATE public.quotation_versions SET terms = '' WHERE id = :'v3'::uuid;

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format($$SELECT public.issue_quotation(%L::uuid)$$, :'v3'),
  'TERMS_REQUIRED',
  'issue rejects a draft with empty terms'
);

-- =============================================================================
-- TEST: expire_due_quotations marks an overdue issued version expired and
-- audits quotation_expired without notes
-- =============================================================================
RESET ROLE;
SELECT pg_temp.force_valid_until(:'v1'::uuid, now() - interval '1 hour');

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.expire_due_quotations() AS sweep1 \gset

SELECT tests.assert_equals(
  (:'sweep1'::jsonb ->> 'expired_count'),
  '1',
  'the sweep expires exactly the overdue issued version'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT v.status = 'expired' AND v.expired_at IS NOT NULL
      FROM public.quotation_versions v WHERE v.id = %L::uuid$$,
    :'v1'
  ),
  'the overdue version is now expired'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM audit.audit_events
      WHERE organization_id = %L::uuid
        AND event_type = 'quotation_expired'
        AND resource_id = %L::uuid
        AND (metadata ->> 'reason_code') = 'due'
        AND NOT (metadata ? 'notes')
        AND NOT (metadata ? 'terms')
        AND NOT (metadata ? 'label')$$,
    :'org_id', :'v1'
  ),
  'quotation_expired audit carries reason_code due, never notes, terms or labels'
);

-- =============================================================================
-- TEST: upsert_quotation_defaults is admin-only and requires terms
-- =============================================================================
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  $$SELECT public.upsert_quotation_defaults('Condiciones de la agencia.')$$,
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot save the organization terms template'
);

RESET ROLE;
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  $$SELECT public.upsert_quotation_defaults('   ')$$,
  'TERMS_REQUIRED',
  'the terms template cannot be empty'
);

SELECT public.upsert_quotation_defaults('Condiciones de la agencia.') AS d1 \gset

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT d.terms_template = 'Condiciones de la agencia.'
      FROM public.quotation_defaults d WHERE d.organization_id = %L::uuid$$,
    :'org_id'
  ),
  'an admin saves the organization terms template'
);

-- =============================================================================
-- TEST: anon cannot execute any US2 RPC
-- =============================================================================
RESET ROLE;

SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('anon', 'public.set_quotation_terms(uuid,text,timestamptz)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.issue_quotation(uuid)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.expire_due_quotations()', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.upsert_quotation_defaults(text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.expire_due_quotations_core(uuid,boolean)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'public.assert_quotation_validity(uuid,uuid,timestamptz)', 'EXECUTE')$q$,
  'anon has no EXECUTE privilege on the US2 functions'
);

SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format($$SELECT public.issue_quotation(%L::uuid)$$, :'v3'),
  'permission denied',
  'anon cannot EXECUTE issue_quotation'
);

SELECT tests.assert_raises(
  $$SELECT public.expire_due_quotations()$$,
  'permission denied',
  'anon cannot EXECUTE expire_due_quotations'
);

RESET ROLE;
ROLLBACK;
