-- public_key_security_test.sql
-- Feature 016, US2: public access keys. Fingerprint-only storage, Administrator-only management,
-- 7-day rotation grace, immediate revocation, generic denial and key-scoped public reads.
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/public_key_security_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a        16000000-0000-4000-a000-000000000101
\set org_b        16000000-0000-4000-a000-000000000102
\set admin_a      16000000-0000-4000-b000-000000000111
\set operator_a   16000000-0000-4000-b000-000000000112
\set agent_a      16000000-0000-4000-b000-000000000113
\set admin_b      16000000-0000-4000-b000-000000000121

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
  VALUES ('00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
          p_email, now(), now());

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
    jsonb_strip_nulls(jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'app_role', p_app_role,
      'organization_id', p_organization_id::text
    ))::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.act_anon()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.price_and_activate(
  p_organization_id uuid,
  p_product_id uuid,
  p_amount numeric,
  p_charge_type text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
  )
  VALUES (
    p_organization_id, p_product_id, 'COP', p_amount,
    p_charge_type::public.charge_type, now() - interval '1 minute', NULL
  );

  UPDATE public.products
  SET status = 'active'
  WHERE id = p_product_id
    AND organization_id = p_organization_id;
END;
$$;

-- Captures the error message of a statement (NULL when it succeeds).
CREATE OR REPLACE FUNCTION pg_temp.error_of(p_statement text)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE p_statement;
  RETURN NULL;
EXCEPTION
  WHEN others THEN
    RETURN SQLSTATE || ':' || SQLERRM;
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_a'::uuid, 'Clave Uno', 'clave-uno-016', 'active', '{"default_phone_country_code":"57"}'::jsonb),
  (:'org_b'::uuid, 'Clave Dos', 'clave-dos-016', 'active', '{"default_phone_country_code":"57"}'::jsonb);

SELECT pg_temp.add_collaborator(:'admin_a'::uuid, :'org_a'::uuid, 'admin-a@key.invalid', 'Admin A', 'admin');
SELECT pg_temp.add_collaborator(:'operator_a'::uuid, :'org_a'::uuid, 'op-a@key.invalid', 'Operador A', 'operator');
SELECT pg_temp.add_collaborator(:'agent_a'::uuid, :'org_a'::uuid, 'agent-a@key.invalid', 'Agente A', 'agent');
SELECT pg_temp.add_collaborator(:'admin_b'::uuid, :'org_b'::uuid, 'admin-b@key.invalid', 'Admin B', 'admin');

-- ===========================================================================
-- 1. Only the Administrator manages keys (FR-012)
-- ===========================================================================

\echo '--- roles ---'

SELECT pg_temp.act_as(:'operator_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises('SELECT public.generate_public_access_key()', 'FORBIDDEN', 'an operator cannot generate a key');
SELECT tests.assert_raises('SELECT public.list_public_access_keys()', 'FORBIDDEN', 'an operator cannot list keys');

RESET ROLE;
SELECT pg_temp.act_as(:'agent_a'::uuid, :'org_a'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises('SELECT public.generate_public_access_key()', 'FORBIDDEN', 'an agent cannot generate a key');

RESET ROLE;
SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT tests.assert_raises('SELECT public.generate_public_access_key()', 'permission denied', 'anon cannot call key management');
SELECT tests.assert_raises('SELECT public.resolve_public_access_key(''pk_x'')', 'permission denied', 'anon cannot call the internal resolver');
SELECT tests.assert_raises('SELECT public.build_public_catalog(''16000000-0000-4000-a000-000000000101'')', 'permission denied', 'anon cannot call the internal catalog builder');
RESET ROLE;

-- ===========================================================================
-- 2. Generate: the clear key is returned once, only its fingerprint is stored
-- ===========================================================================

\echo '--- generate ---'

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT public.generate_public_access_key() AS gen1 \gset
SELECT (:'gen1'::jsonb ->> 'key') AS key1, (:'gen1'::jsonb ->> 'id') AS key1_id \gset

SELECT tests.assert_true(
  format($sql$SELECT %L ~ '^pk_[0-9a-f]{48}$' AND NOT (%L::jsonb ? 'previous_key_id')$sql$, :'key1', :'gen1'),
  'the first key is opaque and has no predecessor'
);

SELECT tests.assert_true(
  $sql$SELECT jsonb_array_length(public.list_public_access_keys()) = 1
         AND public.list_public_access_keys() -> 0 ->> 'status' = 'current'
         AND NOT (public.list_public_access_keys() -> 0 ? 'key')$sql$,
  'listing shows metadata and status, never the key'
);

RESET ROLE;

SELECT tests.assert_true(
  format($sql$SELECT key_fingerprint = encode(extensions.digest(%L, 'sha256'), 'hex')
               AND key_fingerprint <> %L AND key_prefix = left(%L, 11)
             FROM public.public_access_keys WHERE id = %L$sql$, :'key1', :'key1', :'key1', :'key1_id'),
  'only the SHA-256 fingerprint and a short prefix are stored'
);

SELECT tests.assert_true(
  format($sql$SELECT NOT EXISTS (SELECT 1 FROM audit.audit_events
               WHERE metadata::text LIKE '%%' || %L || '%%')$sql$, :'key1'),
  'the clear key never appears in audit metadata'
);

-- Operators cannot even read key metadata through RLS.
SELECT pg_temp.act_as(:'operator_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT tests.assert_true(
  $sql$SELECT count(*) = 0 FROM public.public_access_keys$sql$,
  'an operator sees no key rows'
);
RESET ROLE;

-- ===========================================================================
-- 3. Public read and request intake with the key (FR-010, FR-022, FR-023)
-- ===========================================================================

\echo '--- key-scoped public access ---'

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;

SELECT public.get_public_site_by_key(:'key1') AS site1 \gset

SELECT tests.assert_true(
  format($sql$SELECT %L::jsonb #>> '{profile,commercialName}' = 'Clave Uno'
               AND %L::jsonb #> '{catalog,offers}' = '[]'::jsonb
               AND jsonb_typeof(%L::jsonb #> '{catalog,categories}') = 'array'
               AND jsonb_typeof(%L::jsonb #> '{catalog,amenities}') = 'array'$sql$,
    :'site1', :'site1', :'site1', :'site1'),
  'a valid key returns the agency profile and its catalog'
);

SELECT tests.assert_true(
  format($sql$SELECT position(%L IN %L) = 0
               AND %L !~ '(organization_id|base_amount|pricing|user_profiles|email.*@key\.invalid|notes)'$sql$,
    :'org_a', :'site1', :'site1'),
  'the projection exposes no agency id, tariffs, users or notes'
);

SELECT public.submit_public_request_by_key(:'key1', jsonb_build_object(
  'privacy_consent', true,
  'contact', jsonb_build_object('first_name', 'Lucía', 'email', 'lucia@viajero.invalid'),
  'interest_text', 'Quiero información para cuatro personas.'
)) AS req \gset

RESET ROLE;

SELECT tests.assert_true(
  format($sql$SELECT EXISTS (SELECT 1 FROM public.customer_requests
                 WHERE organization_id = %L AND channel = 'web' AND reference = (%L::jsonb ->> 'reference'))
               AND NOT EXISTS (SELECT 1 FROM public.customer_requests WHERE organization_id = %L)$sql$,
    :'org_a', :'req', :'org_b'),
  'a request sent with the key belongs to the key''s agency'
);

-- ===========================================================================
-- 4. Rotation: the previous key works for 7 days (clarification 2026-11-13)
-- ===========================================================================

\echo '--- rotation ---'

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT public.generate_public_access_key() AS gen2 \gset
SELECT (:'gen2'::jsonb ->> 'key') AS key2, (:'gen2'::jsonb ->> 'id') AS key2_id \gset

SELECT tests.assert_true(
  format($sql$SELECT (%L::jsonb ->> 'previous_key_id') = %L
               AND (%L::jsonb ->> 'previous_key_expires_at')::timestamptz = now() + interval '7 days'$sql$,
    :'gen2', :'key1_id', :'gen2'),
  'regenerating reports the previous key and its expiry exactly 7 days later'
);

SELECT tests.assert_true(
  $sql$SELECT (SELECT array_agg(k ->> 'status' ORDER BY k ->> 'status')
               FROM jsonb_array_elements(public.list_public_access_keys()) k) = ARRAY['current', 'grace']$sql$,
  'the list shows one current key and one in its grace period'
);

RESET ROLE;
SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;

SELECT tests.assert_true(
  format($sql$SELECT public.get_public_site_by_key(%L) #>> '{profile,commercialName}' = 'Clave Uno'
               AND public.get_public_site_by_key(%L) #>> '{profile,commercialName}' = 'Clave Uno'$sql$,
    :'key1', :'key2'),
  'during the grace period both the old and the new key work'
);

RESET ROLE;

-- Simulate the end of the 7 days.
UPDATE public.public_access_keys SET expires_at = now() - interval '1 second' WHERE id = :'key1_id'::uuid;

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  format('SELECT public.get_public_site_by_key(%L)', :'key1'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'an expired key is rejected'
);
SELECT tests.assert_raises(
  format($sql$SELECT public.submit_public_request_by_key(%L, '{"privacy_consent":true}'::jsonb)$sql$, :'key1'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'an expired key cannot send requests'
);
SELECT tests.assert_true(
  format($sql$SELECT public.get_public_site_by_key(%L) ? 'profile'$sql$, :'key2'),
  'the new key keeps working after the old one expired'
);

RESET ROLE;

-- ===========================================================================
-- 5. Revocation is immediate and idempotent
-- ===========================================================================

\echo '--- revocation ---'

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT public.generate_public_access_key() AS gen3 \gset
SELECT (:'gen3'::jsonb ->> 'key') AS key3, (:'gen3'::jsonb ->> 'id') AS key3_id \gset

-- key2 is now in grace; revoking it must cut it at once.
SELECT tests.assert_true(
  format($sql$SELECT public.revoke_public_access_key(%L) ->> 'status' = 'revoked'
               AND public.revoke_public_access_key(%L) ->> 'status' = 'revoked'$sql$, :'key2_id', :'key2_id'),
  'revoking is immediate and a second revocation is a no-op'
);

RESET ROLE;
SELECT pg_temp.act_as(:'admin_b'::uuid, :'org_b'::uuid, 'admin');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises(
  format('SELECT public.revoke_public_access_key(%L)', :'key3_id'),
  'VALIDATION_ERROR', 'another agency''s administrator cannot revoke this key'
);
SELECT public.generate_public_access_key() ->> 'key' AS key_b \gset
RESET ROLE;

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT tests.assert_raises(
  format('SELECT public.get_public_site_by_key(%L)', :'key2'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'a revoked key is rejected even inside its grace period'
);
SELECT tests.assert_true(
  format($sql$SELECT public.get_public_site_by_key(%L) #>> '{profile,commercialName}' = 'Clave Dos'$sql$, :'key_b'),
  'agency B''s key only reads agency B'
);
RESET ROLE;

-- ===========================================================================
-- 6. Every invalid key gets the same response (FR-015, SC-003)
-- ===========================================================================

\echo '--- generic denial ---'

SELECT pg_temp.act_anon();

SELECT tests.assert_true(
  format($sql$SELECT count(DISTINCT e) = 1 AND min(e) = '42501:PUBLIC_ACCESS_UNAVAILABLE'
             FROM (VALUES
               (pg_temp.error_of(format('SELECT public.get_public_site_by_key(%%L)', %L))),
               (pg_temp.error_of(format('SELECT public.get_public_site_by_key(%%L)', %L))),
               (pg_temp.error_of('SELECT public.get_public_site_by_key(''pk_000000000000000000000000000000000000000000000000'')')),
               (pg_temp.error_of('SELECT public.get_public_site_by_key('''')')),
               (pg_temp.error_of('SELECT public.get_public_site_by_key(NULL)')),
               (pg_temp.error_of(format('SELECT public.get_public_site_by_key(%%L)', repeat('x', 500))))
             ) AS t(e)$sql$, :'key1', :'key2'),
  'expired, revoked, unknown, empty, null and oversized keys produce the identical error'
);

-- An inactive agency's valid key is denied the same way.
UPDATE public.organizations SET status = 'inactive' WHERE id = :'org_b'::uuid;
SELECT tests.assert_equals(
  pg_temp.error_of(format('SELECT public.get_public_site_by_key(%L)', :'key_b')),
  '42501:PUBLIC_ACCESS_UNAVAILABLE',
  'the key of an inactive agency gets the same generic denial'
);

-- ===========================================================================
-- 7. Audit (FR-013)
-- ===========================================================================

\echo '--- audit ---'

SELECT tests.assert_true(
  format($sql$SELECT count(*) FILTER (WHERE event_type = 'public_key_generated') = 3
               AND count(*) FILTER (WHERE event_type = 'public_key_revoked') = 1
               AND bool_and(actor_id = %L)
             FROM audit.audit_events
             WHERE organization_id = %L AND event_type IN ('public_key_generated', 'public_key_revoked')$sql$,
    :'admin_a', :'org_a'),
  'three generations and one revocation are audited with the administrator as actor'
);

SELECT tests.assert_true(
  format($sql$SELECT EXISTS (SELECT 1 FROM audit.audit_events
               WHERE organization_id = %L AND event_type = 'public_key_generated'
                 AND metadata ->> 'action' = 'regenerated'
                 AND metadata ? 'previous_key_expires_at')$sql$, :'org_a'),
  'a regeneration records the predecessor expiry'
);

ROLLBACK;
