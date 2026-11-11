-- reservation_voucher_token_test.sql
-- Regression for defect D2 (stabilization 2026-11-11, migration 057): the public voucher
-- token is URL-safe base64url (32 random bytes, no padding) on confirmation and on
-- re-issue; only its SHA-256 is stored; old tokens stop working after re-issue; tokens issued
-- before 057 (standard base64) keep resolving; the public payload stays redacted.
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/reservation_voucher_token_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on
BEGIN;

\set org_id      05700000-0000-4000-a000-000000000001
\set agent_id    05700000-0000-4000-b000-000000000001
\set admin_id    05700000-0000-4000-b000-000000000002
\set provider_id 05700000-0000-4000-e000-000000000001

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid, p_organization_id uuid, p_email text, p_full_name text,
  p_role public.app_role
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
    p_email, now(), now());
  INSERT INTO public.user_profiles (id, organization_id, full_name, email, role, status, must_change_password)
  VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, 'active', false);
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

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (:'org_id'::uuid, 'Voucher Token Org', 'voucher-token-org', 'active', '{"default_currency":"COP"}'::jsonb);
SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-vtok@test.invalid', 'Ag', 'agent');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-vtok@test.invalid', 'Ad', 'admin');

-- Provider data that must never reach the public voucher.
INSERT INTO public.providers (id, organization_id, name, contact_phone, contact_email, is_active)
VALUES (:'provider_id'::uuid, :'org_id'::uuid, 'Proveedor Secreto VT', '+573009998877', 'secreto@proveedor.test', true);

-- Tariff with an explicit, fixed validity window (no dependency on the execution date).
INSERT INTO public.products (organization_id, name, type, status, provider_id)
VALUES (:'org_id'::uuid, 'Tour VT', 'experience', 'draft', :'provider_id'::uuid)
RETURNING id AS prod \gset
INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
) VALUES (
  :'org_id'::uuid, :'prod'::uuid, 'COP', 70.00, 'per_person',
  TIMESTAMPTZ '2026-01-01 00:00:00+00', NULL
);
UPDATE public.products SET status = 'active' WHERE id = :'prod'::uuid;

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Vera","email":"vtok@test.invalid","phone":"3001110057"}'::jsonb,
  '{"travel_start_date":"2030-07-01","adults":1}'::jsonb,
  '[{"free_text":"Tour","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'prod', 'start_date', '2030-07-01', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr \gset
SELECT (:'pr'::jsonb ->> 'pre_reservation_id') AS prid \gset
UPDATE public.pre_reservation_items
SET verification_status = 'available', verified_by = :'agent_id'::uuid, verified_at = now(),
    provider_contact_person = 'Contacto Interno VT', contact_method = 'phone',
    hold_expires_at = now() + interval '3 days'
WHERE pre_reservation_id = :'prid'::uuid;
SELECT public.refresh_pre_reservation_status(:'prid'::uuid);

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT public.create_quotation_draft(:'prid'::uuid) AS d \gset
SELECT (:'d'::jsonb ->> 'version_id') AS qvid \gset
SELECT public.set_quotation_terms(:'qvid'::uuid, 'Términos VT.', NULL);
SELECT public.issue_quotation(:'qvid'::uuid) AS issued \gset
SELECT public.record_quotation_response(:'qvid'::uuid, 'accepted');
SELECT public.confirm_reservation(
  :'qvid'::uuid,
  '{"amount":25,"currency":"COP","paid_on":"2026-01-15","method":"cash","transfer_reference":"vt"}'::jsonb,
  '[{"first_name":"Vera","last_name":"Tok","document_type":"cc","document_number":"5757"}]'::jsonb,
  '3000000'
) AS conf \gset
RESET ROLE;

SELECT (:'conf'::jsonb ->> 'voucher_token') AS tok1, (:'conf'::jsonb ->> 'family_id') AS fam \gset

-- Internal-only data on the reservation that must not leak.
UPDATE public.reservation_versions
SET contingency_report = 'Reporte interno VT'
WHERE family_id = :'fam'::uuid;

-- ===========================================================================
-- 1. Generation format
-- ===========================================================================

\echo '--- voucher token format ---'

SELECT tests.assert_true(
  format($$SELECT %L ~ '^[A-Za-z0-9_-]+$' AND char_length(%L) = 43$$, :'tok1', :'tok1'),
  'confirm_reservation returns a 43-char base64url token (no + / =)'
);

SELECT tests.assert_true(
  $$SELECT bool_and(t ~ '^[A-Za-z0-9_-]{43}$') AND count(DISTINCT t) = 500
      FROM (SELECT public.new_voucher_token() AS t FROM generate_series(1, 500)) s$$,
  'new_voucher_token yields 500 distinct base64url tokens of 43 chars'
);

SELECT tests.assert_true(
  format(
    $$SELECT voucher_token_hash = encode(extensions.digest(%L, 'sha256'), 'hex')
        FROM public.reservation_families WHERE id = %L::uuid$$,
    :'tok1', :'fam'
  ),
  'only the SHA-256 hex of the token is stored'
);

SELECT tests.assert_true(
  format(
    $$SELECT NOT EXISTS (
        SELECT 1 FROM public.reservation_families f
        WHERE f.id = %L::uuid AND to_jsonb(f)::text LIKE '%%' || %L || '%%')$$,
    :'fam', :'tok1'
  ),
  'the clear token is not persisted on the reservation family'
);

SELECT tests.assert_true(
  $$SELECT NOT has_function_privilege('anon', 'public.new_voucher_token()', 'EXECUTE')
       AND NOT has_function_privilege('authenticated', 'public.new_voucher_token()', 'EXECUTE')$$,
  'new_voucher_token is internal (no EXECUTE for anon/authenticated)'
);

-- The quotation token flow (046) is unchanged: still base64url.
SELECT tests.assert_true(
  format($$SELECT %L ~ '^[A-Za-z0-9_-]{43}$'$$, :'issued'::jsonb ->> 'public_token'),
  'quotation public token is still base64url (046 untouched)'
);

-- ===========================================================================
-- 2. Public read without session (anon), redaction, invalid tokens
-- ===========================================================================

\echo '--- anon public voucher ---'

SELECT public.new_voucher_token() AS unknown_tok \gset

SET LOCAL ROLE anon;
SELECT public.get_public_voucher(:'tok1') AS pub \gset

SELECT tests.assert_equals(:'pub'::jsonb ->> 'available', 'true', 'anon resolves the new token');

SELECT tests.assert_true(
  format(
    $$SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(%L::jsonb) k)
             = ARRAY['assistance_phones','available','items','passengers','reference',
                     'status','terms','travel_end_date','travel_start_date']$$,
    :'pub'
  ),
  'public voucher exposes only the documented keys'
);

SELECT tests.assert_true(
  format(
    $$SELECT %1$L NOT ILIKE '%%Proveedor Secreto%%'
         AND %1$L NOT ILIKE '%%secreto@proveedor%%'
         AND %1$L NOT ILIKE '%%9998877%%'
         AND %1$L NOT ILIKE '%%Contacto Interno%%'
         AND %1$L NOT ILIKE '%%Reporte interno%%'
         AND %1$L NOT ILIKE '%%5757%%'
         AND %1$L NOT ILIKE '%%line_total%%'$$,
    :'pub'
  ),
  'public voucher carries no provider data, internal notes, documents or amounts'
);

SELECT tests.assert_equals(public.get_public_voucher(NULL) ->> 'available', 'false', 'null token');
SELECT tests.assert_equals(public.get_public_voucher('   ') ->> 'available', 'false', 'blank token');
SELECT tests.assert_equals(
  public.get_public_voucher('not a token/../%2F') ->> 'available', 'false', 'malformed token'
);
SELECT tests.assert_equals(
  public.get_public_voucher(:'unknown_tok') ->> 'available', 'false',
  'well-formed but unknown token'
);
RESET ROLE;

-- ===========================================================================
-- 3. Re-issue (rotate): new token is base64url, the previous one stops working
-- ===========================================================================

\echo '--- re-issue ---'

SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;
SELECT public.rotate_reservation_voucher(:'fam'::uuid) ->> 'voucher_token' AS tok2 \gset
SELECT tests.assert_raises(
  format($$SELECT public.rotate_reservation_voucher('%s'::uuid)$$, gen_random_uuid()),
  'VALIDATION_ERROR',
  'rotating an unknown family is a VALIDATION_ERROR'
);
RESET ROLE;

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises(
  format($$SELECT public.rotate_reservation_voucher(%L::uuid)$$, :'fam'),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot re-issue the voucher'
);
RESET ROLE;

SELECT tests.assert_true(
  format($$SELECT %L ~ '^[A-Za-z0-9_-]{43}$' AND %L <> %L$$, :'tok2', :'tok2', :'tok1'),
  're-issued token is a different 43-char base64url token'
);

SET LOCAL ROLE anon;
SELECT tests.assert_equals(
  public.get_public_voucher(:'tok2') ->> 'available', 'true', 're-issued token resolves'
);
SELECT tests.assert_equals(
  public.get_public_voucher(:'tok1') ->> 'available', 'false', 'previous token is revoked by re-issue'
);
RESET ROLE;

-- ===========================================================================
-- 4. Compatibility: a token issued before 057 (standard base64 with '/', '+', '=')
-- ===========================================================================

\echo '--- legacy token compatibility ---'

UPDATE public.reservation_families
SET voucher_token_hash = encode(extensions.digest('AbC+dEf/GhI=legacy/token+0123456789abcdefgh=', 'sha256'), 'hex')
WHERE id = :'fam'::uuid;

SET LOCAL ROLE anon;
SELECT tests.assert_equals(
  public.get_public_voucher('AbC+dEf/GhI=legacy/token+0123456789abcdefgh=') ->> 'available',
  'true',
  'a pre-057 standard-base64 token still resolves (hash lookup is format-agnostic)'
);
RESET ROLE;

\echo '--- reservation_voucher_token_test: all assertions passed ---'

ROLLBACK;
