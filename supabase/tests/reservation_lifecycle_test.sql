-- reservation_lifecycle_test.sql
\set ON_ERROR_STOP on
BEGIN;

\set org_id 09200000-0000-4000-a000-000000000001
\set agent_id 09200000-0000-4000-b000-000000000001
\set operator_id 09200000-0000-4000-b000-000000000002
\set customer_id 09200000-0000-4000-c000-000000000001

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

CREATE OR REPLACE FUNCTION pg_temp.add_product(
  p_org uuid, p_name text, p_type public.product_type,
  p_charge public.charge_type, p_amount numeric, p_currency text
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.products (organization_id, name, type, status)
  VALUES (p_org, p_name, p_type, 'draft') RETURNING id INTO v_id;
  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from
  ) VALUES (p_org, v_id, p_currency::char(3), p_amount, p_charge, now() - interval '1 day');
  UPDATE public.products SET status = 'active' WHERE id = v_id;
  RETURN v_id;
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (:'org_id'::uuid, 'Res Life Org', 'res-life-org', 'active', '{"default_currency":"COP"}'::jsonb);
SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-res-life@test.invalid', 'Ag', 'agent');
SELECT pg_temp.add_collaborator(:'operator_id'::uuid, :'org_id'::uuid, 'op-res-life@test.invalid', 'Op', 'operator');
INSERT INTO public.customers (id, organization_id, first_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Luis', 'res-life@test.invalid', '+573001110002', :'agent_id'::uuid);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Luis","email":"res-life@test.invalid","phone":"3001110002"}'::jsonb,
  '{"travel_start_date":"2030-09-01","adults":1}'::jsonb,
  '[{"free_text":"Tour","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Tour life', 'experience', 'per_person', 80.00, 'COP') AS prod \gset
SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'prod', 'start_date', '2030-09-01', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr \gset
SELECT (:'pr'::jsonb ->> 'pre_reservation_id') AS prid \gset
UPDATE public.pre_reservation_items
SET verification_status = 'available', verified_by = :'agent_id'::uuid, verified_at = now(),
    provider_contact_person = 'P', contact_method = 'phone', hold_expires_at = now() + interval '3 days'
WHERE pre_reservation_id = :'prid'::uuid;
SELECT public.refresh_pre_reservation_status(:'prid'::uuid);

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT public.create_quotation_draft(:'prid'::uuid) AS d \gset
SELECT (:'d'::jsonb ->> 'version_id') AS vid \gset
SELECT public.set_quotation_terms(:'vid'::uuid, 'Términos.', NULL);
SELECT public.issue_quotation(:'vid'::uuid);
SELECT public.record_quotation_response(:'vid'::uuid, 'accepted');
SELECT public.confirm_reservation(
  :'vid'::uuid,
  '{"amount":20,"currency":"COP","paid_on":"2020-01-15","method":"cash","transfer_reference":"a"}'::jsonb,
  '[{"first_name":"Luis","last_name":"Paz","document_type":"cc","document_number":"99"}]'::jsonb,
  ''
) AS conf \gset
SELECT (:'conf'::jsonb ->> 'version_id') AS rvid \gset

SELECT tests.assert_raises(
  format('SELECT public.transition_reservation_status(%L::uuid, %L)', :'rvid', 'in_progress'),
  'INSUFFICIENT_PERMISSIONS',
  'agent cannot transition'
);

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SELECT public.transition_reservation_status(:'rvid'::uuid, 'in_progress');
SELECT public.transition_reservation_status(:'rvid'::uuid, 'completed');
SELECT tests.assert_raises(
  format('SELECT public.transition_reservation_status(%L::uuid, %L)', :'rvid', 'confirmed'),
  'INVALID_TRANSITION',
  'cannot go back'
);

ROLLBACK;
