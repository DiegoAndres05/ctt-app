-- reservation_rls_test.sql
\set ON_ERROR_STOP on
BEGIN;

\set org_id     09000000-0000-4000-a000-000000000001
\set org_b_id   09000000-0000-4000-a000-000000000002
\set agent_id   09000000-0000-4000-b000-000000000001
\set agent_b_id 09000000-0000-4000-b000-000000000002

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid, p_organization_id uuid, p_email text, p_full_name text,
  p_role public.app_role, p_status public.user_status DEFAULT 'active'
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
    p_email, now(), now());
  INSERT INTO public.user_profiles (id, organization_id, full_name, email, role, status, must_change_password)
  VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, p_status, false);
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
VALUES
  (:'org_id'::uuid, 'Res RLS A', 'res-rls-a', 'active', '{"default_currency":"COP"}'::jsonb),
  (:'org_b_id'::uuid, 'Res RLS B', 'res-rls-b', 'active', '{"default_currency":"COP"}'::jsonb);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'a-res-rls@test.invalid', 'A', 'agent');
SELECT pg_temp.add_collaborator(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'b-res-rls@test.invalid', 'B', 'agent');

SELECT tests.assert_true(
  $$ SELECT NOT has_table_privilege('anon', 'public.reservation_families', 'SELECT') $$,
  'anon cannot select reservation_families'
);
SELECT tests.assert_true(
  $$ SELECT NOT has_table_privilege('anon', 'public.reservation_list', 'SELECT') $$,
  'anon cannot select reservation_list'
);
SELECT tests.assert_true(
  $$ SELECT NOT has_function_privilege('anon', 'public.assert_quotation_confirmable(uuid,uuid)', 'EXECUTE') $$,
  'anon cannot execute assert_quotation_confirmable'
);
SELECT tests.assert_true(
  $$ SELECT NOT has_function_privilege(
    'authenticated',
    'public.reservation_insert_payment(uuid,uuid,jsonb,text,uuid)',
    'EXECUTE'
  ) $$,
  'authenticated cannot execute internal payment helper'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.act_as(:'agent_b_id'::uuid, :'org_b_id'::uuid, 'agent');
SELECT tests.assert_equals(
  (SELECT count(*) FROM public.reservation_list),
  0::bigint,
  'other org sees empty reservation_list'
);

ROLLBACK;
