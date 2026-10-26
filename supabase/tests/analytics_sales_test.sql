-- analytics_sales_test.sql
\set ON_ERROR_STOP on
BEGIN;

\set org_id 09900000-0000-4000-a000-000000000001
\set agent_id 09900000-0000-4000-b000-000000000001
\set op_id 09900000-0000-4000-b000-000000000002

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
VALUES (:'org_id'::uuid, 'Sales An Org', 'sales-an-org', 'active', '{}'::jsonb);
SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'ag-salan@test.invalid', 'Ag', 'agent');
SELECT pg_temp.add_collaborator(:'op_id'::uuid, :'org_id'::uuid, 'op-salan@test.invalid', 'Op', 'operator');

SELECT pg_temp.act_as(:'op_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT public.analytics_sales_summary(CURRENT_DATE, CURRENT_DATE) AS sum \gset
SELECT tests.assert_equals((:'sum'::jsonb -> 'currencies')::text, '[]', 'empty currencies');
SELECT public.analytics_product_ranking(CURRENT_DATE, CURRENT_DATE, 20) AS rank \gset
SELECT tests.assert_equals((:'rank'::jsonb -> 'rows')::text, '[]', 'empty ranking');

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SELECT tests.assert_raises(
  $$ SELECT public.analytics_sales_summary(CURRENT_DATE, CURRENT_DATE) $$,
  'INSUFFICIENT_PERMISSIONS',
  'agent blocked'
);

ROLLBACK;
