-- quotation_version_test.sql
-- US4 tests: public acceptance, agent responses, versioning, voiding and the
-- 006 boundary (quickstart scenario 4, spec FR-013..FR-018).
-- Run with: ./supabase/tests/run-sql-tests.sh quotation_version_test.sql
--
-- Covers: accept without confirmation → CONFIRMATION_REQUIRED and the version
-- stays issued; with confirmation it becomes accepted with origin customer and
-- audit { response: accepted, origin: customer } without names; a second
-- acceptance → QUOTATION_NOT_OPEN; changes_requested stays issued and appends
-- quotation_responses; create_quotation_version supersedes the origin and opens
-- a draft priced with the current tariffs (never the frozen total) while the
-- family token is preserved; accepting after a main line changed → expired +
-- QUOTATION_STALE; versioning an accepted → QUOTATION_TERMINAL; void without
-- reason → VOID_REASON_REQUIRED, on accepted → QUOTATION_ACCEPTED, as agent →
-- INSUFFICIENT_PERMISSIONS, and a voided link answers available false without
-- lines; assert_quotation_confirmable is not executable by authenticated and,
-- as owner over an accepted version, returns total and party_adults without
-- email.

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id       08000000-0000-4000-a000-000000000001
\set agent_id     08000000-0000-4000-b000-000000000001
\set admin_id     08000000-0000-4000-b000-000000000002
\set customer_id  08000000-0000-4000-c000-000000000001

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

-- ---------------------------------------------------------------------------
-- Setup: organization, collaborators, customer, request, catalog
-- ---------------------------------------------------------------------------

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (
  :'org_id'::uuid, 'Quotation Version Org', 'quotation-version-org', 'active',
  '{"default_phone_country_code":"57","default_currency":"COP"}'::jsonb
);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-quotation-version@test.invalid', 'Agent Quotation Version', 'agent');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-quotation-version@test.invalid', 'Admin Quotation Version', 'admin');

INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Test', 'Version', 'quotation-version@test.invalid', '+573004448899', :'agent_id'::uuid);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Test","email":"quotation-version@test.invalid","phone":"3004448899"}'::jsonb,
  '{"travel_start_date":"2030-04-10","adults":2}'::jsonb,
  '[{"free_text":"Quotation version tour","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset

SELECT pg_temp.add_product(:'org_id'::uuid, 'Tour versión A', 'experience', 'per_person', 100.00, 'COP') AS p_a \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Tour versión B', 'experience', 'per_person', 150.00, 'COP') AS p_b \gset

-- pr1: two lines (accept flow). pr2: one line (responses + versioning).
-- pr3: two lines (stale fingerprint). pr4: one line (void flow).
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_a', 'start_date', '2030-04-10', 'adults', 2, 'children', 0, 'quantity', 1),
    jsonb_build_object('product_id', :'p_b', 'start_date', '2030-04-11', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr1_result \gset
SELECT (:'pr1_result'::jsonb ->> 'pre_reservation_id') AS pr1 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_b', 'start_date', '2030-04-20', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr2_result \gset
SELECT (:'pr2_result'::jsonb ->> 'pre_reservation_id') AS pr2 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_a', 'start_date', '2030-04-30', 'adults', 1, 'children', 0, 'quantity', 1),
    jsonb_build_object('product_id', :'p_b', 'start_date', '2030-05-01', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr3_result \gset
SELECT (:'pr3_result'::jsonb ->> 'pre_reservation_id') AS pr3 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_a', 'start_date', '2030-05-10', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr4_result \gset
SELECT (:'pr4_result'::jsonb ->> 'pre_reservation_id') AS pr4 \gset

SELECT pg_temp.make_quotable(:'pr1'::uuid, :'agent_id'::uuid);
SELECT pg_temp.make_quotable(:'pr2'::uuid, :'agent_id'::uuid);
SELECT pg_temp.make_quotable(:'pr3'::uuid, :'agent_id'::uuid);
SELECT pg_temp.make_quotable(:'pr4'::uuid, :'agent_id'::uuid);

-- Setup: four issued quotations with public tokens
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

SELECT public.create_quotation_draft(:'pr4'::uuid) AS b4 \gset
SELECT (:'b4'::jsonb ->> 'version_id') AS v4 \gset
SELECT public.issue_quotation(:'v4'::uuid) AS issue4 \gset
SELECT (:'issue4'::jsonb ->> 'public_token') AS token4 \gset

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT (%L::jsonb #>> '{total}')::numeric = 350.00$$, :'issue1'
  ),
  'pr1 is priced 2 x 100.00 + 1 x 150.00 = 350.00 before acceptance'
);

SELECT f.public_token_hash AS family2_hash
FROM public.quotation_families f
JOIN public.quotation_versions v ON v.family_id = f.id
WHERE v.id = :'v2'::uuid \gset

-- =============================================================================
-- TEST: acceptance without confirmation → CONFIRMATION_REQUIRED, still issued
-- =============================================================================
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format($$SELECT public.accept_public_quotation(%L::text, false)$$, :'token1'),
  'CONFIRMATION_REQUIRED',
  'accepting without confirmation raises CONFIRMATION_REQUIRED'
);

SELECT tests.assert_raises(
  format($$SELECT public.accept_public_quotation(%L::text, NULL)$$, :'token1'),
  'CONFIRMATION_REQUIRED',
  'a NULL confirmation also raises CONFIRMATION_REQUIRED'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT v.status = 'issued' AND v.accepted_at IS NULL
      FROM public.quotation_versions v WHERE v.id = %L::uuid$$,
    :'v1'
  ),
  'a rejected confirmation leaves the version issued'
);

-- =============================================================================
-- TEST: confirmed acceptance → accepted, origin customer, audit without names
-- =============================================================================
SET LOCAL ROLE anon;

SELECT public.accept_public_quotation(:'token1'::text, true) AS acc1 \gset

SELECT tests.assert_equals(
  (:'acc1'::jsonb ->> 'available'),
  'true',
  'the confirmed public acceptance succeeds'
);

SELECT tests.assert_equals(
  (:'acc1'::jsonb ->> 'status'),
  'accepted',
  'the confirmed public acceptance answers status accepted'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT v.status = 'accepted' AND v.accepted_at IS NOT NULL
             AND v.response_origin = 'customer'
      FROM public.quotation_versions v WHERE v.id = %L::uuid$$,
    :'v1'
  ),
  'the version is accepted with origin customer'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM public.quotation_responses r
      WHERE r.version_id = %L::uuid
        AND r.kind = 'accepted' AND r.origin = 'customer' AND r.created_by IS NULL$$,
    :'v1'
  ),
  'one customer response row with no agent actor was appended'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM audit.audit_events
      WHERE organization_id = %L::uuid
        AND event_type = 'quotation_response_recorded'
        AND resource_id = %L::uuid
        AND (metadata ->> 'response') = 'accepted'
        AND (metadata ->> 'origin') = 'customer'
        AND NOT (metadata ? 'first_name')
        AND NOT (metadata ? 'last_name')
        AND NOT (metadata ? 'email')
        AND NOT (metadata ? 'phone')
        AND NOT (metadata ? 'label')
        AND NOT (metadata ? 'terms')
        AND NOT (metadata ? 'public_token')$$,
    :'org_id', :'v1'
  ),
  'quotation_response_recorded audit carries response/origin codes, never names or contact data'
);

-- =============================================================================
-- TEST: a second acceptance → QUOTATION_NOT_OPEN
-- =============================================================================
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format($$SELECT public.accept_public_quotation(%L::text, true)$$, :'token1'),
  'QUOTATION_NOT_OPEN',
  'a second acceptance of the same token raises QUOTATION_NOT_OPEN'
);

RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format($$SELECT public.record_quotation_response(%L::uuid, 'accepted')$$, :'v1'),
  'QUOTATION_NOT_OPEN',
  'an agent cannot re-accept an accepted version'
);

SELECT tests.assert_raises(
  format($$SELECT public.create_quotation_version(%L::uuid)$$, :'v1'),
  'QUOTATION_TERMINAL',
  'versioning an accepted version raises QUOTATION_TERMINAL'
);

-- =============================================================================
-- TEST: changes_requested stays issued and appends quotation_responses
-- =============================================================================
SELECT public.record_quotation_response(:'v2'::uuid, 'changes_requested') AS rc2 \gset

SELECT tests.assert_equals(
  (:'rc2'::jsonb ->> 'status'),
  'issued',
  'changes_requested leaves the version issued'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM public.quotation_responses r
      WHERE r.version_id = %L::uuid
        AND r.kind = 'changes_requested' AND r.origin = 'agent'$$,
    :'v2'
  ),
  'changes_requested appended one agent response row'
);

-- =============================================================================
-- TEST: create_quotation_version supersedes the origin and reprices the draft;
-- the family token is preserved
-- =============================================================================
-- pricing_schemes is append-only (020): a new version with a later valid_from
-- is the catalog's way of changing the tariff from 150.00 to 250.00.
INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type, valid_from
) VALUES (
  :'org_id'::uuid, :'p_b'::uuid, 'COP', 250.00, 'per_person', now()
);

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.create_quotation_version(:'v2'::uuid) AS nb2 \gset
SELECT (:'nb2'::jsonb ->> 'version_id') AS v2b \gset

SELECT tests.assert_equals(
  (:'nb2'::jsonb ->> 'status'),
  'draft',
  'the new version opens as draft'
);

SELECT tests.assert_equals(
  (:'nb2'::jsonb ->> 'version_number'),
  '2',
  'the new version is v2 of the same family'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{total}')::numeric = 250.00$$, :'nb2'),
  'the new draft is priced with the current tariff: 1 x 250.00, not the frozen 150.00'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT v.status = 'superseded' AND v.superseded_at IS NOT NULL AND v.total = 150.00
      FROM public.quotation_versions v WHERE v.id = %L::uuid$$,
    :'v2'
  ),
  'the origin version is superseded and keeps its frozen total'
);

SELECT tests.assert_true(
  format(
    $$SELECT f.public_token_hash IS NOT NULL AND f.public_token_hash = %L::text
      FROM public.quotation_families f
      JOIN public.quotation_versions v ON v.family_id = f.id
      WHERE v.id = %L::uuid$$,
    :'family2_hash', :'v2'
  ),
  'the family public token hash is preserved across versioning'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM audit.audit_events
      WHERE organization_id = %L::uuid
        AND event_type = 'quotation_superseded'
        AND resource_id = %L::uuid
        AND metadata ? 'version_number'
        AND NOT (metadata ? 'label')
        AND NOT (metadata ? 'terms')$$,
    :'org_id', :'v2'
  ),
  'quotation_superseded audit carries ids only'
);

-- =============================================================================
-- TEST: accepting after a main line changed → expired + QUOTATION_STALE
-- =============================================================================
-- Withdraw one of the two main lines: the fingerprint no longer matches while
-- the remaining line keeps the pre-reservation verified.
UPDATE public.pre_reservation_items
SET withdrawn_at = now(),
    withdrawn_reason = 'Cambio de itinerario',
    withdrawn_by = :'agent_id'::uuid
WHERE pre_reservation_id = :'pr3'::uuid
  AND position = 0;

SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format($$SELECT public.accept_public_quotation(%L::text, true)$$, :'token3'),
  'QUOTATION_STALE',
  'accepting after a main line changed raises QUOTATION_STALE'
);

-- The raise rolls back the flip inside the call. The fingerprint-aware sweep
-- commits it at the next read, which is how the panel sees «Expirada».
-- Here we invoke the internal sweep core directly (as superuser, with the
-- fingerprint check on) so the flip is observable inside this test
-- transaction; the panel RPC `expire_due_quotations` performs the same sweep.
RESET ROLE;

SELECT public.expire_due_quotations_core(:'org_id'::uuid, true) AS sweep_stale \gset

SELECT tests.assert_true(
  format(
    $$SELECT v.status = 'expired' AND v.expired_at IS NOT NULL
      FROM public.quotation_versions v WHERE v.id = %L::uuid$$,
    :'v3'
  ),
  'the stale version is left expired'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) >= 1 FROM audit.audit_events
      WHERE organization_id = %L::uuid
        AND event_type = 'quotation_expired'
        AND resource_id = %L::uuid
        AND (metadata ->> 'reason_code') = 'stale'$$,
    :'org_id', :'v3'
  ),
  'quotation_expired audit carries reason_code stale'
);

-- =============================================================================
-- TEST: void rules — agent denied, reason mandatory, accepted protected,
-- the link dies, second void is terminal
-- =============================================================================
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format($$SELECT public.void_quotation(%L::uuid, 'Motivo válido.')$$, :'v4'),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot void a quotation'
);

RESET ROLE;
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format($$SELECT public.void_quotation(%L::uuid, '')$$, :'v4'),
  'VOID_REASON_REQUIRED',
  'voiding without a reason raises VOID_REASON_REQUIRED'
);

SELECT tests.assert_raises(
  format($$SELECT public.void_quotation(%L::uuid, 'Motivo.')$$, :'v1'),
  'QUOTATION_ACCEPTED',
  'an accepted quotation cannot be voided'
);

SELECT public.void_quotation(:'v4'::uuid, 'Duplicada con otra agencia.') AS void4 \gset

SELECT tests.assert_equals(
  (:'void4'::jsonb ->> 'status'),
  'voided',
  'an admin voids an issued quotation with a reason'
);

SELECT tests.assert_raises(
  format($$SELECT public.void_quotation(%L::uuid, 'Otra vez.')$$, :'v4'),
  'QUOTATION_TERMINAL',
  'voiding twice raises QUOTATION_TERMINAL'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 1 FROM audit.audit_events
      WHERE organization_id = %L::uuid
        AND event_type = 'quotation_voided'
        AND resource_id = %L::uuid
        AND NOT (metadata ? 'void_reason')
        AND NOT (metadata ? 'reason')$$,
    :'org_id', :'v4'
  ),
  'quotation_voided audit carries no reason text'
);

SET LOCAL ROLE anon;

SELECT public.get_public_quotation(:'token4'::text) AS pub_voided \gset

SELECT tests.assert_true(
  format(
    $$SELECT %L::jsonb = '{"available": false}'::jsonb
             AND NOT (%L::jsonb ? 'lines')$$,
    :'pub_voided', :'pub_voided'
  ),
  'after voiding, the public link answers available false without lines'
);

-- =============================================================================
-- TEST: assert_quotation_confirmable is internal and returns the snapshot
-- =============================================================================
RESET ROLE;

SELECT tests.assert_true(
  $q$SELECT NOT has_function_privilege('anon', 'public.assert_quotation_confirmable(uuid,uuid)', 'EXECUTE')
       AND NOT has_function_privilege('authenticated', 'public.assert_quotation_confirmable(uuid,uuid)', 'EXECUTE')$q$,
  'assert_quotation_confirmable is not executable by anon nor authenticated'
);

SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format($$SELECT public.assert_quotation_confirmable(%L::uuid, %L::uuid)$$, :'org_id', :'v1'),
  'permission denied',
  'authenticated cannot EXECUTE assert_quotation_confirmable'
);

RESET ROLE;

SELECT public.assert_quotation_confirmable(:'org_id'::uuid, :'v1'::uuid) AS snap1 \gset

SELECT tests.assert_true(
  format(
    $$SELECT (%L::jsonb #>> '{total}')::numeric = 350.00
             AND (%L::jsonb ->> 'party_adults')::numeric = 2
             AND %L::jsonb ->> 'reference' = 'COT-00001'
             AND jsonb_array_length(%L::jsonb -> 'lines') = 2$$,
    :'snap1', :'snap1', :'snap1', :'snap1'
  ),
  'the confirmable snapshot carries total, party size, reference and lines'
);

SELECT tests.assert_true(
  format(
    $$SELECT NOT (%L::jsonb ? 'email')
             AND %L::text NOT LIKE '%%quotation-version@test.invalid%%'$$,
    :'snap1', :'snap1'
  ),
  'the confirmable snapshot carries no email'
);

SELECT tests.assert_raises(
  format($$SELECT public.assert_quotation_confirmable(%L::uuid, %L::uuid)$$, :'org_id', :'v2b'),
  'QUOTATION_NOT_ACCEPTED',
  'a draft version is not confirmable'
);

RESET ROLE;
ROLLBACK;
