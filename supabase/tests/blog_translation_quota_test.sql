-- blog_translation_quota_test.sql
-- Feature 017: hourly per-agency character quota and role check of the blog translator (FR-001, FR-012, FR-014).
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/blog_translation_quota_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a     17000000-0000-4000-a000-000000000001
\set org_b     17000000-0000-4000-a000-000000000002
\set admin_a   17000000-0000-4000-b000-000000000001
\set op_a      17000000-0000-4000-b000-000000000002
\set agent_a   17000000-0000-4000-b000-000000000003
\set op_b      17000000-0000-4000-b000-000000000004

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid, p_organization_id uuid, p_email text, p_role public.app_role
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
    p_email, now(), now());
  INSERT INTO public.user_profiles (id, organization_id, full_name, email, role, status, must_change_password)
  VALUES (p_user_id, p_organization_id, 'Colaborador', p_email, p_role, 'active', false);
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

CREATE OR REPLACE FUNCTION pg_temp.detail_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_detail text;
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
  RETURN v_detail;
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_a'::uuid, 'Traduce A', 'traduce-a', 'active', '{}'::jsonb),
  (:'org_b'::uuid, 'Traduce B', 'traduce-b', 'active', '{}'::jsonb);

SELECT pg_temp.add_collaborator(:'admin_a'::uuid, :'org_a'::uuid, 'admin-a@tr.invalid', 'admin');
SELECT pg_temp.add_collaborator(:'op_a'::uuid, :'org_a'::uuid, 'op-a@tr.invalid', 'operator');
SELECT pg_temp.add_collaborator(:'agent_a'::uuid, :'org_a'::uuid, 'agent-a@tr.invalid', 'agent');
SELECT pg_temp.add_collaborator(:'op_b'::uuid, :'org_b'::uuid, 'op-b@tr.invalid', 'operator');

-- ---------------------------------------------------------------------------
-- Roles (FR-001)
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'agent_a'::uuid, :'org_a'::uuid, 'agent');
SELECT tests.assert_raises(
  $$ SELECT public.consume_blog_translation_quota(100) $$,
  'FORBIDDEN', 'an Agent cannot use the translator'
);

SELECT set_config('request.jwt.claims', '', true);
SELECT tests.assert_raises(
  $$ SELECT public.consume_blog_translation_quota(100) $$,
  'SESSION_EXPIRED', 'without a session the translator is not available'
);

SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT tests.assert_raises(
  $$ SELECT public.consume_blog_translation_quota(0) $$,
  'VALIDATION_ERROR', 'an empty part is rejected'
);
SELECT tests.assert_raises(
  $$ SELECT public.consume_blog_translation_quota(5001) $$,
  'VALIDATION_ERROR', 'a part over 5000 characters is rejected'
);

SELECT public.consume_blog_translation_quota(1000) AS first \gset
SELECT tests.assert_equals(:'first'::jsonb ->> 'remaining', '149000', 'an Operator consumes characters');
SELECT tests.assert_true(
  format($$ (%L::jsonb ->> 'reset_at') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:00:00Z$' $$, :'first'),
  'the answer says when the hour window resets'
);

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SELECT public.consume_blog_translation_quota(1000) AS second \gset
SELECT tests.assert_equals(:'second'::jsonb ->> 'remaining', '148000', 'an Administrator shares the agency quota');

-- ---------------------------------------------------------------------------
-- Hourly limit (FR-012)
-- ---------------------------------------------------------------------------

SELECT public.consume_blog_translation_quota(5000) FROM generate_series(1, 29);
SELECT public.consume_blog_translation_quota(2000);
SELECT tests.assert_equals(
  (SELECT characters::text FROM public.blog_translation_usage WHERE organization_id = :'org_a'::uuid),
  '149000', 'parts add up within the hour'
);

SELECT tests.assert_raises(
  $$ SELECT public.consume_blog_translation_quota(1001) $$,
  'TRANSLATION_RATE_LIMITED', 'a part that would exceed 150000 characters in the hour is rejected'
);
SELECT tests.assert_true(
  format($$ (%L::jsonb ->> 'retry_at') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:00:00Z$' $$,
         pg_temp.detail_of('SELECT public.consume_blog_translation_quota(1001)')),
  'the rejection says when to retry'
);
SELECT tests.assert_equals(
  (SELECT characters::text FROM public.blog_translation_usage WHERE organization_id = :'org_a'::uuid),
  '149000', 'a rejected part is not counted'
);
SELECT tests.assert_equals(
  public.consume_blog_translation_quota(1000) ->> 'remaining', '0',
  'a part that fits exactly is accepted'
);

SELECT pg_temp.act_as(:'op_b'::uuid, :'org_b'::uuid, 'operator');
SELECT tests.assert_equals(
  public.consume_blog_translation_quota(500) ->> 'remaining', '149500',
  'another agency has its own quota'
);

-- A new hour starts a new window; old windows are cleaned up.
UPDATE public.blog_translation_usage
SET window_start = window_start - interval '2 days'
WHERE organization_id = :'org_a'::uuid;
SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT tests.assert_equals(
  public.consume_blog_translation_quota(1000) ->> 'remaining', '149000',
  'a new hour starts with the full quota'
);
SELECT tests.assert_equals(
  (SELECT count(*)::text FROM public.blog_translation_usage WHERE organization_id = :'org_a'::uuid),
  '1', 'windows older than a day are deleted'
);

-- ---------------------------------------------------------------------------
-- Grants (FR-014: no direct access to the counter)
-- ---------------------------------------------------------------------------

SET LOCAL ROLE authenticated;
SELECT tests.assert_raises(
  $$ SELECT * FROM public.blog_translation_usage $$,
  'permission denied', 'authenticated cannot read the counter directly'
);
RESET ROLE;

SET LOCAL ROLE anon;
SELECT tests.assert_raises(
  $$ SELECT public.consume_blog_translation_quota(100) $$,
  'permission denied', 'anon cannot call the quota RPC'
);
RESET ROLE;

SELECT tests.assert_true(
  $$ EXISTS (
       SELECT 1 FROM pg_proc p, unnest(p.proconfig) c
       WHERE p.proname = 'consume_blog_translation_quota' AND p.prosecdef AND c = 'search_path=""'
     ) $$,
  'the RPC is SECURITY DEFINER with an empty search_path'
);

ROLLBACK;
