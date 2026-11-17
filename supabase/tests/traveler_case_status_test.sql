-- traveler_case_status_test.sql
-- Feature 015: get_traveler_case_status / get_traveler_case_status_by_key.
--
-- Covers FR-002..FR-008: one stage per case, the most advanced piece wins, the answer carries
-- only reference, dates and public offer name, unknown reference / foreign contact /
-- anonymized customer share one neutral body, repeated attempts are blocked, and the lookup
-- never changes the case.
--
-- Documented exception (FR-006): RATE_LIMITED is the only distinguishable error. It is raised
-- from the attempt count alone, before the case is read, so it reveals nothing about whether
-- the reference exists. This suite asserts that an invented reference hits the same limit.
--
-- Run with: ./supabase/tests/run-sql-tests.sh traveler_case_status_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id       15000000-0000-4000-a000-000000000001
\set org_closed   15000000-0000-4000-a000-000000000002
\set operator_id  15000000-0000-4000-b000-000000000001
\set admin_id     15000000-0000-4000-b000-000000000002

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid,
  p_organization_id uuid,
  p_email text,
  p_full_name text,
  p_role public.app_role
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
  VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, 'active', false);
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

-- Fingerprint of every state the lookup must not touch (FR-008, SC-004).
CREATE OR REPLACE FUNCTION pg_temp.case_state(p_org uuid)
RETURNS text
LANGUAGE sql
AS $$
  SELECT md5(coalesce(string_agg(s, '|' ORDER BY s), ''))
  FROM (
    SELECT 'r:' || r.id || ':' || r.status || ':' || r.updated_at AS s
    FROM public.customer_requests r WHERE r.organization_id = p_org
    UNION ALL
    SELECT 'c:' || c.id || ':' || c.is_anonymized || ':' || c.updated_at
    FROM public.customers c WHERE c.organization_id = p_org
    UNION ALL
    SELECT 'p:' || p.id || ':' || p.status || ':' || p.updated_at
    FROM public.pre_reservations p WHERE p.organization_id = p_org
    UNION ALL
    SELECT 'q:' || q.id || ':' || q.status || ':' || q.updated_at
    FROM public.quotation_versions q WHERE q.organization_id = p_org
    UNION ALL
    SELECT 'v:' || v.id || ':' || v.status
    FROM public.reservation_versions v WHERE v.organization_id = p_org
  ) x;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_id'::uuid, 'Case Status', 'case-status', 'active', '{"default_phone_country_code":"57"}'::jsonb),
  (:'org_closed'::uuid, 'Case Closed', 'case-closed', 'active', '{"default_phone_country_code":"57"}'::jsonb);

-- org_id models CTT during the organization-identifier transition; org_closed does not.
SELECT public.mark_public_site_as_migrated(:'org_id'::uuid);

SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid, 'operador-caso@test.invalid', 'Operador Caso', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'admin_id'::uuid, :'org_id'::uuid, 'admin-caso@test.invalid', 'Admin Caso', 'admin'
);

-- ---------------------------------------------------------------------------
-- A published offer, so the answer can carry its public name.
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience', 'Producto interno', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 120, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 8
  ),
  NULL
) ->> 'id') AS offer_id \gset

RESET ROLE;

INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
)
VALUES (
  :'org_id'::uuid, :'offer_id'::uuid, 'COP', 150000, 'per_person'::public.charge_type,
  now() - interval '1 minute', NULL
);
UPDATE public.products SET status = 'active' WHERE id = :'offer_id'::uuid;

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'offer_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'isla-del-rosario',
  'name_es', 'Islas del Rosario', 'name_en', 'Rosario Islands',
  'description_es', 'Desc', 'description_en', 'Desc',
  'public_category_id', 'islas',
  'location', 'Islas',
  'display_price', 150000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Guía', 'en', 'Guide'))
)) ->> 'id') AS listing_id \gset

SELECT public.attach_public_image(:'listing_id'::uuid, 'cover', NULL, '/images/rosario.jpg', 0);
SELECT public.publish_public_listing(:'listing_id'::uuid);

SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SELECT (public.generate_public_access_key() ->> 'key') AS case_key \gset

RESET ROLE;

-- ---------------------------------------------------------------------------
-- One case per stage. Requests come from intake; the later pieces are seeded directly.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pg_temp.new_case(p_org uuid, p_email text, p_phone text, p_offer uuid)
RETURNS jsonb
LANGUAGE sql
AS $$
  SELECT public.capture_request_core(
    p_org, 'web', NULL,
    jsonb_build_object('first_name', 'Viajero', 'email', p_email, 'phone', p_phone),
    '{"travel_start_date":"2031-03-10","travel_end_date":"2031-03-14","adults":2,"locale":"es","privacy_consent_at":"2031-01-01T00:00:00Z"}'::jsonb,
    jsonb_build_array(jsonb_build_object('product_id', p_offer, 'public_slug', 'isla-del-rosario', 'quantity', 1)),
    NULL
  );
$$;

SELECT (c ->> 'reference') AS ref_recv,   (c ->> 'request_id') AS req_recv   FROM pg_temp.new_case(:'org_id'::uuid, 'recv@test.invalid',   '3001500001', :'offer_id'::uuid) c \gset
SELECT (c ->> 'reference') AS ref_review, (c ->> 'request_id') AS req_review FROM pg_temp.new_case(:'org_id'::uuid, 'review@test.invalid', '3001500002', :'offer_id'::uuid) c \gset
SELECT (c ->> 'reference') AS ref_disc,   (c ->> 'request_id') AS req_disc   FROM pg_temp.new_case(:'org_id'::uuid, 'disc@test.invalid',   '3001500003', :'offer_id'::uuid) c \gset
SELECT (c ->> 'reference') AS ref_anon,   (c ->> 'customer_id') AS cus_anon  FROM pg_temp.new_case(:'org_id'::uuid, 'anon@test.invalid',   '3001500004', :'offer_id'::uuid) c \gset
SELECT (c ->> 'reference') AS ref_pre,    (c ->> 'request_id') AS req_pre,    (c ->> 'customer_id') AS cus_pre    FROM pg_temp.new_case(:'org_id'::uuid, 'pre@test.invalid',    '3001500005', :'offer_id'::uuid) c \gset
SELECT (c ->> 'reference') AS ref_quote,  (c ->> 'request_id') AS req_quote,  (c ->> 'customer_id') AS cus_quote  FROM pg_temp.new_case(:'org_id'::uuid, 'quote@test.invalid',  '3001500006', :'offer_id'::uuid) c \gset
SELECT (c ->> 'reference') AS ref_rsv,    (c ->> 'request_id') AS req_rsv,    (c ->> 'customer_id') AS cus_rsv    FROM pg_temp.new_case(:'org_id'::uuid, 'rsv@test.invalid',    '3001500007', :'offer_id'::uuid) c \gset
SELECT (c ->> 'reference') AS ref_cancel, (c ->> 'request_id') AS req_cancel, (c ->> 'customer_id') AS cus_cancel FROM pg_temp.new_case(:'org_id'::uuid, 'cancel@test.invalid', '3001500008', :'offer_id'::uuid) c \gset
SELECT (c ->> 'reference') AS ref_dead,   (c ->> 'request_id') AS req_dead,   (c ->> 'customer_id') AS cus_dead   FROM pg_temp.new_case(:'org_id'::uuid, 'dead@test.invalid',   '3001500009', :'offer_id'::uuid) c \gset

UPDATE public.customer_requests SET status = 'in_review', first_handled_at = now()
WHERE id = :'req_review'::uuid;

UPDATE public.customer_requests
SET status = 'discarded', discard_reason = 'Motivo interno confidencial',
    first_handled_at = now(), closed_at = now()
WHERE id = :'req_disc'::uuid;

-- Anonymized but the old email kept on purpose, to prove the flag alone blocks the lookup.
UPDATE public.customers SET is_anonymized = true, anonymized_at = now()
WHERE id = :'cus_anon'::uuid;

UPDATE public.customer_requests
SET status = 'pre_reservation', first_handled_at = now(), closed_at = now()
WHERE id IN (:'req_pre'::uuid, :'req_quote'::uuid, :'req_rsv'::uuid, :'req_cancel'::uuid, :'req_dead'::uuid);

INSERT INTO public.pre_reservations (id, organization_id, reference, request_id, customer_id, responsible_agent_id, status, cancelled_at, cancel_reason)
VALUES
  ('15000000-0000-4000-d000-000000000001', :'org_id'::uuid, 'PRE-15001', :'req_pre'::uuid,    :'cus_pre'::uuid,    :'operator_id'::uuid, 'pending_verification', NULL, NULL),
  ('15000000-0000-4000-d000-000000000002', :'org_id'::uuid, 'PRE-15002', :'req_quote'::uuid,  :'cus_quote'::uuid,  :'operator_id'::uuid, 'pending_verification', NULL, NULL),
  ('15000000-0000-4000-d000-000000000003', :'org_id'::uuid, 'PRE-15003', :'req_rsv'::uuid,    :'cus_rsv'::uuid,    :'operator_id'::uuid, 'pending_verification', NULL, NULL),
  ('15000000-0000-4000-d000-000000000004', :'org_id'::uuid, 'PRE-15004', :'req_cancel'::uuid, :'cus_cancel'::uuid, :'operator_id'::uuid, 'pending_verification', NULL, NULL),
  ('15000000-0000-4000-d000-000000000005', :'org_id'::uuid, 'PRE-15005', :'req_dead'::uuid,   :'cus_dead'::uuid,   :'operator_id'::uuid, 'cancelled', now(), 'Sin cupo');

INSERT INTO public.quotation_families (id, organization_id, pre_reservation_id, customer_id, reference, public_token_hash)
VALUES
  ('15000000-0000-4000-e000-000000000002', :'org_id'::uuid, '15000000-0000-4000-d000-000000000002', :'cus_quote'::uuid,  'COT-15002', repeat('a', 64)),
  ('15000000-0000-4000-e000-000000000003', :'org_id'::uuid, '15000000-0000-4000-d000-000000000003', :'cus_rsv'::uuid,    'COT-15003', repeat('b', 64)),
  ('15000000-0000-4000-e000-000000000004', :'org_id'::uuid, '15000000-0000-4000-d000-000000000004', :'cus_cancel'::uuid, 'COT-15004', repeat('c', 64));

INSERT INTO public.quotation_versions (
  id, organization_id, family_id, version_number, status, currency, subtotal, total,
  issued_at, valid_until, pre_reservation_fingerprint, accepted_at
)
VALUES
  ('15000000-0000-4000-f000-000000000002', :'org_id'::uuid, '15000000-0000-4000-e000-000000000002', 1, 'issued',   'COP', 987654, 987654, now(), now() + interval '7 days', '{}'::jsonb, NULL),
  ('15000000-0000-4000-f000-000000000003', :'org_id'::uuid, '15000000-0000-4000-e000-000000000003', 1, 'accepted', 'COP', 987654, 987654, now(), now() + interval '7 days', '{}'::jsonb, now()),
  ('15000000-0000-4000-f000-000000000004', :'org_id'::uuid, '15000000-0000-4000-e000-000000000004', 1, 'accepted', 'COP', 987654, 987654, now(), now() + interval '7 days', '{}'::jsonb, now());

INSERT INTO public.reservation_families (
  id, organization_id, reference, quotation_version_id, quotation_family_id,
  pre_reservation_id, customer_id, voucher_token_hash
)
VALUES
  ('15000000-0000-4000-9000-000000000003', :'org_id'::uuid, 'RSV-15003', '15000000-0000-4000-f000-000000000003', '15000000-0000-4000-e000-000000000003', '15000000-0000-4000-d000-000000000003', :'cus_rsv'::uuid,    repeat('d', 64)),
  ('15000000-0000-4000-9000-000000000004', :'org_id'::uuid, 'RSV-15004', '15000000-0000-4000-f000-000000000004', '15000000-0000-4000-e000-000000000004', '15000000-0000-4000-d000-000000000004', :'cus_cancel'::uuid, repeat('e', 64));

-- The confirmed reservation has a superseded first version with other dates.
INSERT INTO public.reservation_versions (
  organization_id, family_id, version_number, status, currency, total,
  travel_start_date, travel_end_date, party_adults, cancelled_at, cancel_reason
)
VALUES
  (:'org_id'::uuid, '15000000-0000-4000-9000-000000000003', 1, 'superseded', 'COP', 987654, '2031-03-01', '2031-03-05', 2, NULL, NULL),
  (:'org_id'::uuid, '15000000-0000-4000-9000-000000000003', 2, 'confirmed',  'COP', 987654, '2031-03-11', '2031-03-15', 2, NULL, NULL),
  (:'org_id'::uuid, '15000000-0000-4000-9000-000000000004', 1, 'cancelled',  'COP', 987654, '2031-04-01', '2031-04-03', 2, now(), 'Cliente desistió');

SELECT pg_temp.case_state(:'org_id'::uuid) AS state_before \gset
SELECT count(*) AS audit_before FROM audit.audit_events WHERE event_type = 'traveler_case_lookup' \gset

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

SELECT tests.assert_true(
  $$ has_function_privilege('anon', 'public.get_traveler_case_status(uuid, text, text)', 'EXECUTE')
     AND has_function_privilege('authenticated', 'public.get_traveler_case_status(uuid, text, text)', 'EXECUTE')
     AND has_function_privilege('anon', 'public.get_traveler_case_status_by_key(text, text, text)', 'EXECUTE') $$,
  'anon and authenticated may call both entry points'
);

SELECT tests.assert_true(
  $$ NOT has_function_privilege('anon', 'public.traveler_case_status_for_org(uuid, text, text)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.traveler_case_status_for_org(uuid, text, text)', 'EXECUTE')
     AND NOT has_table_privilege('anon', 'public.traveler_case_lookups', 'SELECT')
     AND NOT has_table_privilege('authenticated', 'public.traveler_case_lookups', 'SELECT') $$,
  'the internal function and the attempt ledger are not reachable from the API'
);

SELECT tests.assert_true(
  $$ EXISTS (
       SELECT 1 FROM pg_proc p, unnest(p.proconfig) cfg
       WHERE p.oid = 'public.traveler_case_status_for_org(uuid, text, text)'::regprocedure
         AND cfg = 'search_path=""'::text
     ) $$,
  'the implementation runs with an empty search_path'
);

-- ---------------------------------------------------------------------------
-- US1 / US2: the right contact sees one stage, dates and the public name.
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;

SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_recv', 'RECV@test.invalid ') AS r_recv \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, lower(:'ref_recv'), '300 150 0001') AS r_recv_phone \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_review', 'review@test.invalid') AS r_review \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_disc', 'disc@test.invalid') AS r_disc \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_pre', 'pre@test.invalid') AS r_pre \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_quote', 'quote@test.invalid') AS r_quote \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_rsv', 'rsv@test.invalid') AS r_rsv \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_cancel', 'cancel@test.invalid') AS r_cancel \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_dead', 'dead@test.invalid') AS r_dead \gset

RESET ROLE;

SELECT tests.assert_equals(:'r_recv'::jsonb ->> 'stage', 'request_received', 'a received request shows request_received');
SELECT tests.assert_equals(:'r_recv'::jsonb ->> 'reference', :'ref_recv', 'the answer carries the reference');
SELECT tests.assert_equals(:'r_recv'::jsonb ->> 'travel_start', '2031-03-10', 'the answer carries the requested start date');
SELECT tests.assert_equals(:'r_recv'::jsonb ->> 'travel_end', '2031-03-14', 'the answer carries the requested end date');
SELECT tests.assert_equals(:'r_recv'::jsonb ->> 'offer_name', 'Islas del Rosario', 'the offer name is the public listing name, not the internal product name');
SELECT tests.assert_equals(:'r_recv_phone'::jsonb ->> 'stage', 'request_received', 'a local-format phone and a lowercase reference also match');

SELECT tests.assert_true(
  format($$ (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(%L::jsonb) k)
            = ARRAY['found','offer_name','reference','stage','travel_end','travel_start'] $$, :'r_recv'),
  'a found answer has exactly found, stage, reference, travel_start, travel_end and offer_name'
);

SELECT tests.assert_equals(:'r_review'::jsonb ->> 'stage', 'request_in_review', 'a request in review shows request_in_review');
SELECT tests.assert_equals(:'r_disc'::jsonb ->> 'stage', 'request_closed', 'a discarded request shows request_closed');
SELECT tests.assert_true(
  format($$ position('Motivo' IN %L) = 0 $$, :'r_disc'),
  'a discarded request does not include the discard reason'
);

SELECT tests.assert_equals(:'r_pre'::jsonb ->> 'stage', 'checking_availability', 'a live pre-reservation shows checking_availability');
SELECT tests.assert_equals(:'r_dead'::jsonb ->> 'stage', 'request_closed', 'a request whose only pre-reservation was cancelled shows request_closed');

SELECT tests.assert_equals(:'r_quote'::jsonb ->> 'stage', 'proposal_ready', 'an issued quotation shows proposal_ready');
SELECT tests.assert_true(
  format($$ position('987654' IN %1$L) = 0 AND position('COT-' IN %1$L) = 0 AND position('aaaa' IN %1$L) = 0 $$, :'r_quote'),
  'a proposal answer has no price, no quotation reference and no token'
);

SELECT tests.assert_equals(:'r_rsv'::jsonb ->> 'stage', 'reservation_confirmed', 'a confirmed reservation wins over its accepted quotation');
SELECT tests.assert_equals(:'r_rsv'::jsonb ->> 'travel_start', '2031-03-11', 'dates come from the open reservation version, not the superseded one');
SELECT tests.assert_true(
  format($$ position('987654' IN %1$L) = 0 AND position('RSV-' IN %1$L) = 0 AND position('dddd' IN %1$L) = 0 $$, :'r_rsv'),
  'a reservation answer has no total, no reservation reference and no voucher token'
);

SELECT tests.assert_equals(:'r_cancel'::jsonb ->> 'stage', 'reservation_cancelled', 'a cancelled reservation shows reservation_cancelled');
SELECT tests.assert_true(
  format($$ position('desisti' IN %L) = 0 $$, :'r_cancel'),
  'a cancelled reservation does not include the cancel reason'
);

DELETE FROM public.traveler_case_lookups;

-- ---------------------------------------------------------------------------
-- US3: the same silence for every miss.
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;

SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_recv', 'otra@test.invalid') AS miss_contact \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, 'SOL-99999', 'recv@test.invalid') AS miss_reference \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_recv', 'no es un contacto') AS miss_garbage \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_recv', NULL) AS miss_null \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_anon', 'anon@test.invalid') AS miss_anon \gset
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_quote', 'recv@test.invalid') AS miss_cross \gset

RESET ROLE;

SELECT tests.assert_equals(:'miss_contact', '{"found": false}', 'a real reference with a foreign email returns the neutral body');
SELECT tests.assert_equals(:'miss_reference', :'miss_contact', 'an invented reference returns the same body as a foreign contact');
SELECT tests.assert_equals(:'miss_garbage', :'miss_contact', 'an unparseable contact returns the same body, not a different error');
SELECT tests.assert_equals(:'miss_null', :'miss_contact', 'a missing contact returns the same body');
SELECT tests.assert_equals(:'miss_anon', :'miss_contact', 'an anonymized customer cannot be looked up with the old email');
SELECT tests.assert_equals(:'miss_cross', :'miss_contact', 'the contact of another case does not open this case');

DELETE FROM public.traveler_case_lookups;

-- ---------------------------------------------------------------------------
-- Agency resolution: JWT for staff, transition identifier or key for anon.
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format($$ SELECT public.get_traveler_case_status(%L::uuid, %L, 'recv@test.invalid') $$, :'org_closed', :'ref_recv'),
  'PUBLIC_ACCESS_UNAVAILABLE',
  'anon cannot use the identifier of an agency outside the transition'
);

SELECT tests.assert_raises(
  format($$ SELECT public.get_traveler_case_status_by_key('ctt_pk_invented', %L, 'recv@test.invalid') $$, :'ref_recv'),
  'PUBLIC_ACCESS_UNAVAILABLE',
  'an invalid key gets the generic denial'
);

SELECT public.get_traveler_case_status_by_key(:'case_key', :'ref_recv', 'recv@test.invalid') AS by_key \gset

RESET ROLE;

SELECT tests.assert_equals(:'by_key'::jsonb ->> 'stage', 'request_received', 'the public key resolves the agency and finds the case');

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT public.get_traveler_case_status(:'org_closed'::uuid, :'ref_recv', 'recv@test.invalid') AS staff_answer \gset
RESET ROLE;

SELECT tests.assert_equals(:'staff_answer'::jsonb ->> 'stage', 'request_received', 'a signed-in caller uses the JWT agency and the argument is ignored');

DELETE FROM public.traveler_case_lookups;

-- ---------------------------------------------------------------------------
-- FR-006: 8 attempts per contact and 30 per agency per hour, misses included.
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;

SELECT public.get_traveler_case_status(:'org_id'::uuid, 'SOL-0000' || g, 'insist@test.invalid')
FROM generate_series(1, 8) g;

SELECT tests.assert_raises(
  format($$ SELECT public.get_traveler_case_status(%L::uuid, 'SOL-99998', 'INSIST@test.invalid') $$, :'org_id'),
  'RATE_LIMITED',
  'the ninth attempt in an hour for one contact is blocked even with an invented reference'
);

SELECT tests.assert_raises(
  format($$ SELECT public.get_traveler_case_status(%L::uuid, %L, 'insist@test.invalid') $$, :'org_id', :'ref_recv'),
  'RATE_LIMITED',
  'a real reference gets the same RATE_LIMITED, so the limit does not reveal the case'
);

SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_recv', 'recv@test.invalid') AS other_contact \gset

RESET ROLE;

SELECT tests.assert_equals(:'other_contact'::jsonb ->> 'stage', 'request_received', 'another contact is not blocked by the first one');

DELETE FROM public.traveler_case_lookups;
INSERT INTO public.traveler_case_lookups (organization_id, contact_fingerprint)
SELECT :'org_id'::uuid, md5(g::text) || md5(g::text) FROM generate_series(1, 30) g;

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format($$ SELECT public.get_traveler_case_status(%L::uuid, %L, 'recv@test.invalid') $$, :'org_id', :'ref_recv'),
  'RATE_LIMITED',
  'after 30 attempts in an hour the agency is blocked for every contact'
);

RESET ROLE;

UPDATE public.traveler_case_lookups SET created_at = now() - interval '2 hours';

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;
SELECT public.get_traveler_case_status(:'org_id'::uuid, :'ref_recv', 'recv@test.invalid') AS after_window \gset
RESET ROLE;

SELECT tests.assert_equals(:'after_window'::jsonb ->> 'stage', 'request_received', 'attempts older than one hour no longer count');

SELECT tests.assert_true(
  $$ NOT EXISTS (SELECT 1 FROM public.traveler_case_lookups WHERE position('@' IN contact_fingerprint) > 0) $$,
  'the attempt ledger stores fingerprints, not contacts'
);

-- ---------------------------------------------------------------------------
-- FR-008 and audit.
-- ---------------------------------------------------------------------------

SELECT tests.assert_equals(
  pg_temp.case_state(:'org_id'::uuid),
  :'state_before',
  'no lookup changed a request, customer, pre-reservation, quotation or reservation'
);

SELECT tests.assert_true(
  format($$ (SELECT count(*) FROM audit.audit_events WHERE event_type = 'traveler_case_lookup') > %s $$, :'audit_before'),
  'each lookup leaves an audit event'
);

SELECT tests.assert_true(
  $$ NOT EXISTS (
       SELECT 1 FROM audit.audit_events
       WHERE event_type = 'traveler_case_lookup'
         AND (metadata::text LIKE '%@%' OR metadata::text LIKE '%+57%' OR metadata::text LIKE '%Viajero%'
              OR NOT (metadata ? 'found'))
     ) $$,
  'lookup audit events carry the reference and found, never email, phone or name'
);

SELECT tests.assert_true(
  $$ EXISTS (
       SELECT 1 FROM audit.audit_events
       WHERE event_type = 'traveler_case_lookup' AND metadata ->> 'found' = 'false' AND result = 'failure'
     ) $$,
  'a miss is audited as a failure with found false'
);

ROLLBACK;
