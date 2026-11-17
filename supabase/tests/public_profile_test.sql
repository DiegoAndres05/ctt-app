-- public_profile_test.sql
-- Feature 016, US3: public agency profile. Validation, roles, isolation, audit and the public
-- projection (only configured fields; nothing internal).
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/public_profile_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a        16000000-0000-4000-a000-000000000201
\set org_b        16000000-0000-4000-a000-000000000202
\set admin_a      16000000-0000-4000-b000-000000000211
\set operator_a   16000000-0000-4000-b000-000000000212
\set agent_a      16000000-0000-4000-b000-000000000213
\set operator_b   16000000-0000-4000-b000-000000000221

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

INSERT INTO public.organizations (id, name, slug, status)
VALUES
  (:'org_a'::uuid, 'Perfil Uno', 'perfil-uno-016', 'active'),
  (:'org_b'::uuid, 'Perfil Dos', 'perfil-dos-016', 'active');

SELECT pg_temp.add_collaborator(:'admin_a'::uuid, :'org_a'::uuid, 'admin-a@perfil.invalid', 'Admin A', 'admin');
SELECT pg_temp.add_collaborator(:'operator_a'::uuid, :'org_a'::uuid, 'op-a@perfil.invalid', 'Operador A', 'operator');
SELECT pg_temp.add_collaborator(:'agent_a'::uuid, :'org_a'::uuid, 'agent-a@perfil.invalid', 'Agente A', 'agent');
SELECT pg_temp.add_collaborator(:'operator_b'::uuid, :'org_b'::uuid, 'op-b@perfil.invalid', 'Operador B', 'operator');

CREATE TEMP TABLE profile_case (label text, payload jsonb, field text);
GRANT SELECT ON profile_case TO authenticated;

INSERT INTO profile_case VALUES
  ('a blank commercial name', '{"commercial_name":" ","languages":["es"],"currency":"COP"}', 'commercial_name'),
  ('a non-hex color', '{"commercial_name":"X","primary_color":"red","languages":["es"],"currency":"COP"}', 'primary_color'),
  ('an invalid email', '{"commercial_name":"X","contact_email":"sin-arroba","languages":["es"],"currency":"COP"}', 'contact_email'),
  ('a phone with letters', '{"commercial_name":"X","contact_phone":"llamar ya","languages":["es"],"currency":"COP"}', 'contact_phone'),
  ('an unsupported language', '{"commercial_name":"X","languages":["fr"],"currency":"COP"}', 'languages'),
  ('no language', '{"commercial_name":"X","languages":[],"currency":"COP"}', 'languages'),
  ('an unsupported currency', '{"commercial_name":"X","languages":["es"],"currency":"JPY"}', 'currency'),
  ('an unknown social network', '{"commercial_name":"X","languages":["es"],"currency":"COP","social_links":{"myspace":"https://myspace.com/x"}}', 'social_links'),
  ('a non-https social link', '{"commercial_name":"X","languages":["es"],"currency":"COP","social_links":{"instagram":"http://instagram.com/x"}}', 'social_links'),
  ('a logo from another agency folder', '{"commercial_name":"X","languages":["es"],"currency":"COP","logo_ref":"16000000-0000-4000-a000-000000000202/profile/logo.png"}', 'logo_ref');

-- ===========================================================================
-- 1. Save a full profile (FR-018, FR-019, FR-020)
-- ===========================================================================

\echo '--- save ---'

SELECT pg_temp.act_as(:'operator_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  $sql$SELECT public.get_public_profile() ->> 'commercial_name' = 'Perfil Uno'
         AND public.get_public_profile() -> 'supported_currencies' ? 'USD'$sql$,
  'the default profile and the supported currencies are readable'
);

SELECT public.save_public_profile(jsonb_build_object(
  'commercial_name', 'Perfil Uno Travel',
  'logo_ref', '16000000-0000-4000-a000-000000000201/profile/logo.png',
  'primary_color', '#0f766e',
  'contact_email', 'Hola@PerfilUno.test',
  'contact_phone', '+57 300 000 0000',
  'whatsapp', '+57 300 111 2222',
  'social_links', jsonb_build_object('instagram', 'https://instagram.com/perfiluno', 'facebook', ''),
  'languages', jsonb_build_array('en', 'es'),
  'currency', 'usd'
)) AS saved \gset

SELECT tests.assert_true(
  format($sql$SELECT %L::jsonb ->> 'primary_color' = '#0F766E'
               AND %L::jsonb ->> 'contact_email' = 'hola@perfiluno.test'
               AND %L::jsonb ->> 'currency' = 'USD'
               AND %L::jsonb -> 'social_links' = '{"instagram":"https://instagram.com/perfiluno"}'::jsonb
               AND %L::jsonb ->> 'updated_by_name' = 'Operador A'$sql$,
    :'saved', :'saved', :'saved', :'saved', :'saved'),
  'the profile is saved normalized: color upper-case, email lower-case, empty networks dropped'
);

-- ===========================================================================
-- 2. Validation
-- ===========================================================================

\echo '--- validation ---'

DO $$
DECLARE
  v_case record;
  v_detail text;
  v_message text;
BEGIN
  FOR v_case IN SELECT * FROM profile_case LOOP
    v_message := NULL;
    BEGIN
      PERFORM public.save_public_profile(v_case.payload);
    EXCEPTION
      WHEN others THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL;
    END;
    IF v_message IS DISTINCT FROM 'VALIDATION_ERROR' OR v_detail IS DISTINCT FROM v_case.field THEN
      RAISE EXCEPTION 'FAILED: % should be rejected on % (got %, %)', v_case.label, v_case.field, v_message, v_detail;
    END IF;
    RAISE NOTICE 'ok   % is rejected and names the field %', v_case.label, v_case.field;
  END LOOP;
END;
$$;

SELECT tests.assert_true(
  $sql$SELECT public.get_public_profile() ->> 'commercial_name' = 'Perfil Uno Travel'$sql$,
  'rejected saves leave the profile unchanged'
);

-- ===========================================================================
-- 3. Roles and isolation
-- ===========================================================================

\echo '--- roles and isolation ---'

RESET ROLE;
SELECT pg_temp.act_as(:'agent_a'::uuid, :'org_a'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  $sql$SELECT public.save_public_profile('{"commercial_name":"Hack","languages":["es"],"currency":"COP"}'::jsonb)$sql$,
  'FORBIDDEN', 'an agent cannot edit the public profile'
);
SELECT tests.assert_raises(
  $sql$UPDATE public.public_profiles SET commercial_name = 'Hack'$sql$,
  'permission denied', 'direct profile updates are not granted'
);

RESET ROLE;
SELECT pg_temp.act_as(:'operator_b'::uuid, :'org_b'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 AND min(commercial_name) = 'Perfil Dos' FROM public.public_profiles$sql$,
  'agency B only sees its own profile'
);

SELECT public.save_public_profile('{"commercial_name":"Perfil Dos","languages":["es"],"currency":"COP"}'::jsonb);
RESET ROLE;

SELECT tests.assert_true(
  format($sql$SELECT commercial_name = 'Perfil Uno Travel' FROM public.public_profiles WHERE organization_id = %L$sql$, :'org_a'),
  'agency B saving its profile does not touch agency A'
);

-- ===========================================================================
-- 4. Public projection: configured fields only (FR-022, FR-023, edge case 7)
-- ===========================================================================

\echo '--- public projection ---'

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SET LOCAL ROLE authenticated;
SELECT public.generate_public_access_key() ->> 'key' AS key_a \gset
RESET ROLE;
SELECT pg_temp.act_as(:'operator_b'::uuid, :'org_b'::uuid, 'operator');
RESET ROLE;

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT public.get_public_site_by_key(:'key_a') -> 'profile' AS public_profile \gset
RESET ROLE;

SELECT tests.assert_true(
  format($sql$SELECT %L::jsonb = jsonb_build_object(
      'commercialName', 'Perfil Uno Travel',
      'logo', '16000000-0000-4000-a000-000000000201/profile/logo.png',
      'primaryColor', '#0F766E',
      'contactEmail', 'hola@perfiluno.test',
      'contactPhone', '+57 300 000 0000',
      'whatsapp', '+57 300 111 2222',
      'socialLinks', jsonb_build_object('instagram', 'https://instagram.com/perfiluno'),
      'languages', jsonb_build_array('es', 'en'),
      'currency', 'USD')$sql$, :'public_profile'),
  'the public profile has exactly the configured fields, with no ids, users or audit data'
);

SELECT pg_temp.act_as(:'operator_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT public.save_public_profile('{"commercial_name":"Perfil Uno","languages":["es"],"currency":"COP","social_links":{}}'::jsonb);
RESET ROLE;

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT tests.assert_true(
  format($sql$SELECT public.get_public_site_by_key(%L) -> 'profile'
               = '{"commercialName":"Perfil Uno","languages":["es"],"currency":"COP"}'::jsonb$sql$, :'key_a'),
  'optional fields left empty are absent from the projection, not blank'
);
RESET ROLE;

-- ===========================================================================
-- 5. Audit (FR-021)
-- ===========================================================================

\echo '--- audit ---'

SELECT tests.assert_true(
  format($sql$SELECT count(*) = 2 AND bool_and(actor_id = %L)
             FROM audit.audit_events
             WHERE organization_id = %L AND event_type = 'public_profile_updated'$sql$, :'operator_a', :'org_a'),
  'each profile save is audited with the operator and the agency'
);

SELECT tests.assert_true(
  format($sql$SELECT metadata -> 'changed_fields' ? 'primary_color'
               AND metadata::text NOT LIKE '%%perfiluno%%'
             FROM audit.audit_events
             WHERE organization_id = %L AND event_type = 'public_profile_updated'
             ORDER BY id LIMIT 1$sql$, :'org_a'),
  'the audit names the changed fields without copying their values'
);

ROLLBACK;
