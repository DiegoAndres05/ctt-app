-- reservation_confirm_test.sql
\set ON_ERROR_STOP on
BEGIN;

\set org_id     09100000-0000-4000-a000-000000000001
\set agent_id   09100000-0000-4000-b000-000000000001
\set customer_id 09100000-0000-4000-c000-000000000001

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
VALUES (
  :'org_id'::uuid, 'Res Confirm Org', 'res-confirm-org', 'active',
  '{"default_phone_country_code":"57","default_currency":"COP"}'::jsonb
);
SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-res-confirm@test.invalid', 'Agent RC', 'agent');
INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Ana', 'Viaje', 'res-confirm@test.invalid', '+573001110001', :'agent_id'::uuid);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Ana","email":"res-confirm@test.invalid","phone":"3001110001"}'::jsonb,
  '{"travel_start_date":"2030-08-10","adults":2}'::jsonb,
  '[{"free_text":"Islas","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset

SELECT pg_temp.add_product(:'org_id'::uuid, 'Tour confirm', 'experience', 'per_person', 100.00, 'COP') AS prod \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'prod', 'start_date', '2030-08-10', 'adults', 2, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr_result \gset
SELECT (:'pr_result'::jsonb ->> 'pre_reservation_id') AS prid \gset

UPDATE public.pre_reservation_items
SET verification_status = 'available',
    verified_by = :'agent_id'::uuid,
    verified_at = now(),
    provider_contact_person = 'Prov',
    contact_method = 'phone',
    hold_expires_at = now() + interval '3 days'
WHERE pre_reservation_id = :'prid'::uuid;
SELECT public.refresh_pre_reservation_status(:'prid'::uuid);

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.create_quotation_draft(:'prid'::uuid) AS draft \gset
SELECT (:'draft'::jsonb ->> 'version_id') AS vid \gset
SELECT public.set_quotation_terms(:'vid'::uuid, 'Condiciones de prueba.', NULL);
SELECT public.issue_quotation(:'vid'::uuid) AS issued \gset

SELECT tests.assert_raises(
  $q$ SELECT public.confirm_reservation(
    '09100000-0000-4000-d000-000000000099'::uuid,
    '{"amount":10,"currency":"COP","paid_on":"2020-01-15","method":"cash","transfer_reference":"x"}'::jsonb,
    '[{"first_name":"A","last_name":"B","document_type":"cc","document_number":"1"}]'::jsonb,
    ''
  ) $q$,
  'VALIDATION_ERROR',
  'unknown version'
);

-- issued, not accepted
SELECT tests.assert_raises(
  format(
    $q$ SELECT public.confirm_reservation(%L::uuid,
      '{"amount":50,"currency":"COP","paid_on":"2020-01-15","method":"cash","transfer_reference":"dep1"}'::jsonb,
      '[{"first_name":"Ana","last_name":"Uno","document_type":"cc","document_number":"11"},{"first_name":"Luis","last_name":"Dos","document_type":"cc","document_number":"22"}]'::jsonb,
      '') $q$,
    :'vid'
  ),
  'QUOTATION_NOT_ACCEPTED',
  'issued cannot confirm'
);

SELECT public.record_quotation_response(:'vid'::uuid, 'accepted');

SELECT tests.assert_raises(
  format(
    $q$ SELECT public.confirm_reservation(%L::uuid,
      '{"amount":50,"currency":"COP","paid_on":"2020-01-15","method":"cash","transfer_reference":"dep1"}'::jsonb,
      '[{"first_name":"Ana","last_name":"Uno","document_type":"cc","document_number":"11"}]'::jsonb,
      '') $q$,
    :'vid'
  ),
  'PASSENGER_COUNT_MISMATCH',
  'too few passengers'
);

SELECT tests.assert_raises(
  format(
    $q$ SELECT public.confirm_reservation(%L::uuid,
      '{"amount":0,"currency":"COP","paid_on":"2020-01-15","method":"cash","transfer_reference":"dep1"}'::jsonb,
      '[{"first_name":"Ana","last_name":"Uno","document_type":"cc","document_number":"11"},{"first_name":"Luis","last_name":"Dos","document_type":"cc","document_number":"22"}]'::jsonb,
      '') $q$,
    :'vid'
  ),
  'DEPOSIT_REQUIRED',
  'zero deposit'
);

SELECT public.confirm_reservation(
  :'vid'::uuid,
  '{"amount":50,"currency":"COP","paid_on":"2020-01-15","method":"cash","transfer_reference":"dep1"}'::jsonb,
  '[{"first_name":"Ana","last_name":"Uno","document_type":"cc","document_number":"11"},{"first_name":"Luis","last_name":"Dos","document_type":"cc","document_number":"22"}]'::jsonb,
  '3001234567'
) AS conf \gset

SELECT tests.assert_equals(
  :'conf'::jsonb ->> 'reference',
  'RSV-00001',
  'first locator'
);

SELECT tests.assert_raises(
  format(
    $q$ SELECT public.confirm_reservation(%L::uuid,
      '{"amount":50,"currency":"COP","paid_on":"2020-01-15","method":"cash","transfer_reference":"dep2"}'::jsonb,
      '[{"first_name":"Ana","last_name":"Uno","document_type":"cc","document_number":"11"},{"first_name":"Luis","last_name":"Dos","document_type":"cc","document_number":"22"}]'::jsonb,
      '') $q$,
    :'vid'
  ),
  'RESERVATION_ALREADY_EXISTS',
  'second confirm'
);

SELECT tests.assert_true(
  format(
    $$ SELECT NOT EXISTS (
      SELECT 1 FROM audit.audit_events e
      WHERE e.event_type = 'reservation_confirmed'
        AND e.metadata::text ILIKE '%%' || %L || '%%'
    ) $$,
    :'conf'::jsonb ->> 'voucher_token'
  ),
  'token not in audit metadata'
);

RESET ROLE;
SELECT tests.assert_true(
  $$ SELECT NOT has_function_privilege('anon', 'public.confirm_reservation(uuid,jsonb,jsonb,text)', 'EXECUTE') $$,
  'anon cannot confirm'
);

ROLLBACK;
