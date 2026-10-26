-- analytics_funnel_test.sql
\set ON_ERROR_STOP on
BEGIN;

\set org_id 09700000-0000-4000-a000-000000000001
\set agent_id 09700000-0000-4000-b000-000000000001
\set customer_id 09700000-0000-4000-c000-000000000001

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
VALUES (:'org_id'::uuid, 'Funnel Org', 'funnel-org', 'active', '{}'::jsonb);
SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'ag-fun@test.invalid', 'Ag', 'operator');
INSERT INTO public.customers (id, organization_id, first_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'F', 'fun@test.invalid', '+573001110090', :'agent_id'::uuid);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"F","email":"fun1@test.invalid","phone":"3001110091"}'::jsonb,
  '{"travel_start_date":"2031-01-01","adults":1}'::jsonb,
  '[{"free_text":"A","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id');
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"G","email":"fun2@test.invalid","phone":"3001110092"}'::jsonb,
  '{"travel_start_date":"2031-01-01","adults":1}'::jsonb,
  '[{"free_text":"B","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id');
SELECT (public.capture_request_core(
  :'org_id'::uuid, 'whatsapp', NULL,
  '{"first_name":"H","email":"fun3@test.invalid","phone":"3001110093"}'::jsonb,
  '{"travel_start_date":"2031-01-01","adults":1}'::jsonb,
  '[{"free_text":"C","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id');

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.analytics_funnel(CURRENT_DATE, CURRENT_DATE, NULL) AS allc \gset
SELECT tests.assert_equals((:'allc'::jsonb -> 'stages' -> 0 ->> 'count'), '3', 'three requests');
SELECT tests.assert_equals((:'allc'::jsonb -> 'stages' -> 0 ->> 'conversion_from_top'), '1.0000', 'top is 100%');
SELECT tests.assert_equals((:'allc'::jsonb -> 'stages' -> 1 ->> 'count'), '0', 'no pre-reservations');
SELECT tests.assert_equals((:'allc'::jsonb -> 'stages' -> 1 ->> 'conversion_from_previous'), '0.0000', 'zero over three');

SELECT public.analytics_funnel(CURRENT_DATE, CURRENT_DATE, 'whatsapp') AS wa \gset
SELECT tests.assert_equals((:'wa'::jsonb -> 'stages' -> 0 ->> 'count'), '1', 'whatsapp only');

SELECT public.analytics_funnel('1999-01-01'::date, '1999-01-02'::date, NULL) AS empty \gset
SELECT tests.assert_equals((:'empty'::jsonb -> 'stages' -> 0 ->> 'count'), '0', 'empty period');
SELECT tests.assert_true(
  format($$ SELECT (%L) IS NULL $$, :'empty'::jsonb -> 'stages' -> 0 ->> 'conversion_from_top'),
  'null conversion when no requests'
);

SELECT tests.assert_raises(
  $$ SELECT public.analytics_funnel('2020-01-01'::date, '2022-01-02'::date, NULL) $$,
  'DATE_RANGE_TOO_LONG',
  'range cap'
);

ROLLBACK;
