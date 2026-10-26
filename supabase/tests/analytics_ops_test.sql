-- analytics_ops_test.sql
\set ON_ERROR_STOP on
BEGIN;

\set org_id 09800000-0000-4000-a000-000000000001
\set agent_id 09800000-0000-4000-b000-000000000001
\set customer_id 09800000-0000-4000-c000-000000000001

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
VALUES (:'org_id'::uuid, 'Ops Org', 'ops-an-org', 'active', '{}'::jsonb);
SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'ag-opsan@test.invalid', 'Ag', 'operator');
INSERT INTO public.customers (id, organization_id, first_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'O', 'opsan@test.invalid', '+573001110094', :'agent_id'::uuid);

INSERT INTO public.customer_requests (
  organization_id, reference, customer_id, channel, status, adults, children,
  dedup_fingerprint, created_by, created_at, first_handled_at, updated_at
) VALUES (
  :'org_id'::uuid, 'SOL-99001', :'customer_id'::uuid, 'phone', 'in_review', 1, 0,
  'ops-an-fp-1', :'agent_id'::uuid, now() - interval '48 hours',
  now() - interval '46 hours', now()
);

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT public.analytics_ops_times(CURRENT_DATE - 3, CURRENT_DATE, NULL) AS times \gset
SELECT tests.assert_equals((:'times'::jsonb ->> 'sample_request'), '1', 'one handled request');
SELECT tests.assert_true(
  format($$ SELECT (%L)::numeric >= 1 $$, :'times'::jsonb ->> 'avg_request_response_hours'),
  'response hours recorded'
);
SELECT public.analytics_stale_queue() AS stale \gset
SELECT tests.assert_true(
  format($$ SELECT jsonb_array_length(%L::jsonb) >= 1 $$, :'stale'::jsonb -> 'items'),
  'stale queue has the old request'
);

ROLLBACK;
