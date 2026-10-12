-- seed.sql
-- Minimal fixture for LOCAL development only: one demo agency plus one collaborator per role.
--
-- ############################################################################
-- # DO NOT RUN AGAINST A SHARED OR PRODUCTION PROJECT.                       #
-- # These credentials are public knowledge and the accounts are unprivileged #
-- # only in the sense that they belong to a throwaway tenant.                #
-- ############################################################################
--
-- Writing rows into auth.users directly is the documented way to seed a local Supabase
-- stack. Application code never does this: it goes through Supabase Auth, which owns
-- password hashing and storage (FR-007).
--
-- Accounts (password for all three: DemoPass123!):
--   admin@demo-turismo.test     -> admin,    must_change_password = false
--   operador@demo-turismo.test  -> operator, must_change_password = false
--   agente@demo-turismo.test    -> agent,    must_change_password = true  (exercises the
--                                            mandatory password change flow)

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

DO $$
DECLARE
  v_org_id uuid := '00000000-0000-4000-a000-000000000001';
  v_admin_id uuid := '00000000-0000-4000-b000-000000000001';
  v_operator_id uuid := '00000000-0000-4000-b000-000000000002';
  v_agent_id uuid := '00000000-0000-4000-b000-000000000003';
  v_password_hash text := extensions.crypt('DemoPass123!', extensions.gen_salt('bf'));
  v_user record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.organizations WHERE id = v_org_id) THEN
    RAISE NOTICE 'Demo tenant already seeded; nothing to do.';
    RETURN;
  END IF;

  INSERT INTO public.organizations (id, name, slug, status)
  VALUES (v_org_id, 'Agencia Demo Turismo', 'agencia-demo-turismo', 'active');

  FOR v_user IN
    SELECT *
    FROM (
      VALUES
        (v_admin_id,    'admin@demo-turismo.test',    'Admin Demo',    'admin'::public.app_role,    false),
        (v_operator_id, 'operador@demo-turismo.test', 'Operador Demo', 'operator'::public.app_role, false),
        (v_agent_id,    'agente@demo-turismo.test',   'Agente Demo',   'agent'::public.app_role,    true)
    ) AS t(id, email, full_name, role, must_change_password)
  LOOP
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    )
    VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_user.id,
      'authenticated',
      'authenticated',
      v_user.email,
      v_password_hash,
      now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('full_name', v_user.full_name),
      now(), now(),
      '', '', '', ''
    );

    INSERT INTO auth.identities (
      id, provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    )
    VALUES (
      gen_random_uuid(),
      v_user.id::text,
      v_user.id,
      jsonb_build_object('sub', v_user.id::text, 'email', v_user.email, 'email_verified', true),
      'email',
      now(), now(), now()
    );

    INSERT INTO public.user_profiles (
      id, organization_id, full_name, email, role, status, must_change_password
    )
    VALUES (
      v_user.id, v_org_id, v_user.full_name, v_user.email,
      v_user.role, 'active', v_user.must_change_password
    );
  END LOOP;
END;
$$;

-- Catalog & pricing demo data for the seed agency (feature 002). Idempotent so a second
-- apply after the tenant already exists still fills categories and a provider.
DO $$
DECLARE
  v_org_id uuid := '00000000-0000-4000-a000-000000000001';
  v_provider_id uuid := '00000000-0000-4000-c000-000000000001';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = v_org_id) THEN
    RAISE NOTICE 'Demo tenant missing; skip catalog seed.';
    RETURN;
  END IF;

  UPDATE public.organizations
  SET settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('default_currency', 'COP')
  WHERE id = v_org_id
    AND coalesce(settings->>'default_currency', '') = '';

  INSERT INTO public.providers (
    id, organization_id, name, contact_email, contact_phone, is_active
  )
  VALUES (
    v_provider_id,
    v_org_id,
    'Proveedor Demo Andes',
    'proveedor@demo-turismo.test',
    '+57 300 000 0000',
    true
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.categories (id, organization_id, name, slug)
  VALUES
    ('00000000-0000-4000-d000-000000000001', v_org_id, 'Aventura', 'aventura'),
    ('00000000-0000-4000-d000-000000000002', v_org_id, 'Ecológico', 'ecologico'),
    ('00000000-0000-4000-d000-000000000003', v_org_id, 'Cultural', 'cultural'),
    ('00000000-0000-4000-d000-000000000004', v_org_id, 'Lujo', 'lujo')
  ON CONFLICT (id) DO NOTHING;
END;
$$;

-- Customers and requests for the demo agency (feature 003). Stops when the tenant
-- already has customers so a second apply does not mint new SOL- references.
DO $$
DECLARE
  v_org_id uuid := '00000000-0000-4000-a000-000000000001';
  v_agent_id uuid := '00000000-0000-4000-b000-000000000003';
  v_product_id uuid;
  v_result jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM public.customers WHERE organization_id = v_org_id) THEN
    RAISE NOTICE 'Demo customers already seeded; nothing to do.';
    RETURN;
  END IF;

  UPDATE public.organizations
  SET settings = coalesce(settings, '{}'::jsonb) || '{"default_phone_country_code":"57"}'::jsonb
  WHERE id = v_org_id;

  SELECT pl.product_id
  INTO v_product_id
  FROM public.public_listings pl
  WHERE pl.organization_id = v_org_id
    AND pl.public_slug = 'islas-capri-premium';

  IF v_product_id IS NULL THEN
    RAISE EXCEPTION 'Demo listing islas-capri-premium is missing';
  END IF;

  PERFORM public.capture_request_core(
    v_org_id,
    'web',
    NULL,
    jsonb_build_object(
      'first_name', 'Laura Gómez',
      'email', 'laura@example.com',
      'phone', '+573001112233'
    ),
    jsonb_build_object(
      'privacy_consent_at', now(),
      'adults', 2,
      'travel_start_date', '2027-03-15'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', v_product_id,
      'public_slug', 'islas-capri-premium',
      'quantity', 1
    )),
    NULL
  );

  v_result := public.capture_request_core(
    v_org_id,
    'phone',
    NULL,
    jsonb_build_object('first_name', 'John Smith', 'phone', '+13055550123'),
    jsonb_build_object(
      'assign_to', v_agent_id,
      'special_requirements', 'Llamada recibida en recepción'
    ),
    jsonb_build_array(jsonb_build_object('free_text', 'Tour gastronómico', 'quantity', 1)),
    v_agent_id
  );

  UPDATE public.customer_requests
  SET status = 'in_review',
      first_handled_at = now()
  WHERE id = (v_result ->> 'request_id')::uuid;
END;
$$;

-- Simulated WhatsApp connection for local webhook tests. No credentials are stored.
INSERT INTO public.channel_connections (
  organization_id, channel, provider, external_account_id, display_phone, status
)
VALUES (
  '00000000-0000-4000-a000-000000000001',
  'whatsapp',
  'meta_cloud',
  'local-dev-phone-number-id',
  '+57 300 000 0000',
  'active'
)
ON CONFLICT (provider, external_account_id) DO NOTHING;

-- Pre-reservations for the demo agency (feature 004). Stops when the tenant already has
-- pre-reservations so a second apply leaves the demo untouched. Creation goes through
-- public.create_pre_reservation_core (the authenticated RPC needs a JWT the seed has no
-- way to mint). The one "available" line and the derived header state are written with
-- direct UPDATEs because record_item_verification also requires a signed-in operator.
DO $$
DECLARE
  v_org_id uuid := '00000000-0000-4000-a000-000000000001';
  v_operator_id uuid := '00000000-0000-4000-b000-000000000002';
  v_agent_id uuid := '00000000-0000-4000-b000-000000000003';
  v_provider_id uuid := '00000000-0000-4000-c000-000000000001';
  v_offer_product_id uuid := '00000000-0000-4000-e000-000000000101';
  v_lodging_product_id uuid := '00000000-0000-4000-e000-000000000102';
  v_experience_product_id uuid := '00000000-0000-4000-e000-000000000103';
  v_today date := (now() AT TIME ZONE 'America/Bogota')::date;
  v_request_id uuid;
  v_source_item_id uuid;
  v_pre_reservation_id uuid;
  v_item_id uuid;
  v_hold timestamptz;
  v_result jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM public.pre_reservations WHERE organization_id = v_org_id) THEN
    RAISE NOTICE 'Demo pre-reservations already seeded; nothing to do.';
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = v_org_id) THEN
    RAISE NOTICE 'Demo tenant missing; skip pre-reservation seed.';
    RETURN;
  END IF;

  -- (a) The in-review demo request from feature 003: two main lines (a lodging with the
  -- demo provider and an experience) plus a date alternative for the experience.
  SELECT id
  INTO v_request_id
  FROM public.customer_requests
  WHERE organization_id = v_org_id
    AND status = 'in_review'
  ORDER BY created_at
  LIMIT 1;

  IF v_request_id IS NULL THEN
    RAISE EXCEPTION 'Demo in_review request is missing';
  END IF;

  UPDATE public.products
  SET provider_id = v_provider_id
  WHERE id = v_lodging_product_id
    AND organization_id = v_org_id
    AND provider_id IS NULL;

  v_result := public.create_pre_reservation_core(
    v_org_id,
    v_request_id,
    jsonb_build_object(
      'assigned_operator_id', v_operator_id,
      'items', jsonb_build_array(
        jsonb_build_object(
          'product_id', v_lodging_product_id,
          'start_date', v_today + 45,
          'end_date', v_today + 48,
          'adults', 2, 'children', 0, 'quantity', 1
        ),
        jsonb_build_object(
          'product_id', v_experience_product_id,
          'start_date', v_today + 45,
          'adults', 2, 'children', 0, 'quantity', 1
        ),
        jsonb_build_object(
          'product_id', v_experience_product_id,
          'start_date', v_today + 52,
          'adults', 2, 'children', 0, 'quantity', 1,
          'alternative_of', 1
        )
      )
    ),
    v_agent_id
  );

  v_pre_reservation_id := (v_result ->> 'pre_reservation_id')::uuid;
  v_hold := now() + interval '30 days';

  -- Mark the lodging line available so the list shows «Parcialmente verificada».
  UPDATE public.pre_reservation_items
  SET verification_status = 'available',
      verification_started_at = now(),
      verified_by = v_operator_id,
      verified_at = now(),
      provider_contact_person = 'Recepción Villa Caribe',
      contact_method = 'phone',
      hold_expires_at = v_hold
  WHERE pre_reservation_id = v_pre_reservation_id
    AND position = 0
  RETURNING id INTO v_item_id;

  PERFORM public.log_availability_event(
    v_org_id, v_pre_reservation_id, v_item_id,
    'outcome_recorded'::public.availability_event_kind,
    'pending'::public.availability_status,
    'available'::public.availability_status,
    jsonb_build_object(
      'provider_contact_person', 'Recepción Villa Caribe',
      'contact_method', 'phone',
      'hold_expires_at', v_hold
    ),
    v_operator_id
  );

  UPDATE public.pre_reservations
  SET status = 'partially_verified',
      expires_at = v_hold
  WHERE id = v_pre_reservation_id;

  -- (b) Laura Gómez's request from feature 003, still in received: one experience line
  -- tied to her catalog interest. The date matches her request travel window when the
  -- seed runs before it, and stays in the future when it runs after.
  SELECT cr.id
  INTO v_request_id
  FROM public.customer_requests cr
  JOIN public.customers c ON c.id = cr.customer_id AND c.organization_id = cr.organization_id
  WHERE cr.organization_id = v_org_id
    AND cr.status = 'received'
    AND c.email = 'laura@example.com'
  ORDER BY cr.created_at
  LIMIT 1;

  IF v_request_id IS NULL THEN
    RAISE EXCEPTION 'Demo received request for Laura Gómez is missing';
  END IF;

  SELECT cri.id
  INTO v_source_item_id
  FROM public.customer_request_items cri
  WHERE cri.request_id = v_request_id
    AND cri.product_id IS NOT NULL
  ORDER BY cri.position
  LIMIT 1;

  PERFORM public.create_pre_reservation_core(
    v_org_id,
    v_request_id,
    jsonb_build_object(
      'items', jsonb_strip_nulls(jsonb_build_array(
        jsonb_build_object(
          'product_id', v_offer_product_id,
          'start_date', greatest(v_today + 30, date '2027-03-15'),
          'adults', 2, 'children', 0, 'quantity', 1,
          'source_request_item_id', v_source_item_id
        )
      ))
    ),
    v_agent_id
  );
END;
$$;
