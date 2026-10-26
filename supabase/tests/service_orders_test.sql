-- service_orders_test.sql
\set ON_ERROR_STOP on
BEGIN;

\set org_id 09400000-0000-4000-a000-000000000001
\set agent_id 09400000-0000-4000-b000-000000000001
\set operator_id 09400000-0000-4000-b000-000000000002
\set customer_id 09400000-0000-4000-c000-000000000001
\set prov_a 09400000-0000-4000-e000-000000000001
\set prov_b 09400000-0000-4000-e000-000000000002

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
VALUES (:'org_id'::uuid, 'Res Ord Org', 'res-ord-org', 'active', '{"default_currency":"COP"}'::jsonb);
SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-res-ord@test.invalid', 'Ag', 'agent');
SELECT pg_temp.add_collaborator(:'operator_id'::uuid, :'org_id'::uuid, 'op-res-ord@test.invalid', 'Op', 'operator');
INSERT INTO public.providers (id, organization_id, name)
VALUES (:'prov_a'::uuid, :'org_id'::uuid, 'Prov A'), (:'prov_b'::uuid, :'org_id'::uuid, 'Prov B');
INSERT INTO public.customers (id, organization_id, first_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Nia', 'res-ord@test.invalid', '+573001110004', :'agent_id'::uuid);

INSERT INTO public.products (id, organization_id, name, type, status, provider_id)
VALUES
  ('09400000-0000-4000-d000-000000000001'::uuid, :'org_id'::uuid, 'Tour A', 'experience', 'draft', :'prov_a'::uuid),
  ('09400000-0000-4000-d000-000000000002'::uuid, :'org_id'::uuid, 'Tour B', 'experience', 'draft', :'prov_b'::uuid);
INSERT INTO public.pricing_schemes (organization_id, product_id, currency, base_amount, charge_type, valid_from)
VALUES
  (:'org_id'::uuid, '09400000-0000-4000-d000-000000000001'::uuid, 'COP', 50, 'per_person', now() - interval '1 day'),
  (:'org_id'::uuid, '09400000-0000-4000-d000-000000000002'::uuid, 'COP', 60, 'per_person', now() - interval '1 day');
UPDATE public.products SET status = 'active' WHERE organization_id = :'org_id'::uuid;

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Nia","email":"res-ord@test.invalid","phone":"3001110004"}'::jsonb,
  '{"travel_start_date":"2030-07-01","adults":1}'::jsonb,
  '[{"free_text":"Mix","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', '09400000-0000-4000-d000-000000000001', 'start_date', '2030-07-01', 'adults', 1, 'children', 0, 'quantity', 1),
    jsonb_build_object('product_id', '09400000-0000-4000-d000-000000000002', 'start_date', '2030-07-02', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr \gset
SELECT (:'pr'::jsonb ->> 'pre_reservation_id') AS prid \gset
UPDATE public.pre_reservation_items
SET verification_status = 'available', verified_by = :'agent_id'::uuid, verified_at = now(),
    provider_contact_person = 'P', contact_method = 'phone', hold_expires_at = now() + interval '3 days',
    provider_id = CASE product_id
      WHEN '09400000-0000-4000-d000-000000000001'::uuid THEN :'prov_a'::uuid
      ELSE :'prov_b'::uuid
    END
WHERE pre_reservation_id = :'prid'::uuid;
SELECT public.refresh_pre_reservation_status(:'prid'::uuid);

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT public.create_quotation_draft(:'prid'::uuid) AS d \gset
SELECT (:'d'::jsonb ->> 'version_id') AS qvid \gset
SELECT public.set_quotation_terms(:'qvid'::uuid, 'Términos.', NULL);
SELECT public.issue_quotation(:'qvid'::uuid);
SELECT public.record_quotation_response(:'qvid'::uuid, 'accepted');
SELECT public.confirm_reservation(
  :'qvid'::uuid,
  '{"amount":40,"currency":"COP","paid_on":"2020-01-15","method":"cash","transfer_reference":"o"}'::jsonb,
  '[{"first_name":"Nia","last_name":"Mar","document_type":"cc","document_number":"77"}]'::jsonb,
  ''
) AS conf \gset
SELECT (:'conf'::jsonb ->> 'version_id') AS rvid \gset

SELECT i.id AS item_a
FROM public.reservation_items i
WHERE i.version_id = :'rvid'::uuid AND i.provider_id = :'prov_a'::uuid
\gset

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SELECT public.reservation_provider_order_text(:'item_a'::uuid) AS order_a \gset
SELECT tests.assert_true(
  format(
    $$ SELECT (%L IS NOT NULL)
         AND (%L NOT ILIKE '%%line_total%%')
         AND (%L NOT ILIKE '%%Prov B%%') $$,
    :'order_a'::jsonb ->> 'item_label',
    :'order_a'::jsonb::text,
    :'order_a'::jsonb::text
  ),
  'order text hides sale price and other provider'
);
SELECT public.mark_provider_order_sent(:'item_a'::uuid, 'print');
SELECT tests.assert_equals(
  (SELECT ops_status::text FROM public.reservation_items WHERE id = :'item_a'::uuid),
  'confirmed_with_provider',
  'marked sent'
);
SELECT public.reassign_reservation_item_provider(:'item_a'::uuid, :'prov_b'::uuid, 'Cambio de cupo');
SELECT tests.assert_equals(
  (SELECT ops_status::text FROM public.reservation_items WHERE id = :'item_a'::uuid),
  'pending_provider',
  'reassigned pending'
);

ROLLBACK;
