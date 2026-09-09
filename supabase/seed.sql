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
