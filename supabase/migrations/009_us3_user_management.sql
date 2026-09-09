-- 009_us3_user_management.sql
-- User Story 3: administrator-only collaborator provisioning and role/status changes,
-- enforced in the database so a bypassed Angular guard cannot create users or rewrite roles.
-- Source of truth: specs/001-auth-tenant-access/spec.md (FR-002, FR-006),
-- specs/001-auth-tenant-access/contracts/api-contracts.md
--   (create_internal_user, update_user_role, toggle_user_status),
-- specs/001-auth-tenant-access/data-model.md.
--
-- ERROR CONTRACT: the RPCs raise the API contract's error code as the exception message
-- (SQLSTATE P0001 / insufficient_privilege). The frontend maps `error.message` back to an
-- AuthErrorCode. Messages are therefore part of the API contract and must not be reworded.
--
-- CLAIM NAMING: the application role travels in `app_role`, never in the reserved `role`
-- claim. See docs/adr/0002-jwt-app-role-claim.md.
--
-- AUDIT: these functions do not write the log themselves. Inserting a profile fires
-- `user_created`; changing `role` or `status` fires `role_changed` /
-- `user_activated` / `user_deactivated` through the triggers installed in migration 007
-- (rewritten in 008). The actor is taken from `auth.uid()`, which still reflects the
-- caller's JWT inside a SECURITY DEFINER function.
--
-- These routines are SECURITY DEFINER and owned by the migration role, which bypasses RLS.
-- Tenant and admin checks below are therefore the authorization boundary, not a convenience.

-- ---------------------------------------------------------------------------
-- Shared: the caller must be an active administrator of the tenant in the token
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.require_tenant_admin()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_claim_org uuid := nullif(auth.jwt() ->> 'organization_id', '')::uuid;
  v_organization_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- JWT claim AND the live profile: a demoted administrator must lose these RPCs
  -- immediately, without waiting for the next access-token refresh (US3 acceptance 3).
  IF (auth.jwt() ->> 'app_role') IS DISTINCT FROM 'admin' OR v_claim_org IS NULL THEN
    RAISE EXCEPTION 'INSUFFICIENT_PERMISSIONS' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT p.organization_id
  INTO v_organization_id
  FROM public.user_profiles p
  WHERE p.id = v_user_id
    AND p.status = 'active'
    AND p.role = 'admin'
    AND p.organization_id = v_claim_org;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'INSUFFICIENT_PERMISSIONS' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN v_organization_id;
END;
$$;

COMMENT ON FUNCTION public.require_tenant_admin() IS
  'Returns the caller''s tenant id, or raises, when the JWT and the live profile both say admin.';

REVOKE ALL ON FUNCTION public.require_tenant_admin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.require_tenant_admin() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- create_internal_user
-- ---------------------------------------------------------------------------

-- Provisions auth.users + auth.identities + user_profiles in one transaction, with a
-- temporary password the collaborator must retire on first sign-in (FR-006, FR-007).
-- The hash is bcrypt through pgcrypto, the same algorithm and column Supabase Auth uses.
-- Password material is never written to the audit log.
CREATE OR REPLACE FUNCTION public.create_internal_user(
  p_full_name text,
  p_email text,
  p_role text,
  p_temporary_password text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_max_password_bytes constant integer := 72;
  c_min_password_length constant integer := 8;

  v_organization_id uuid;
  v_email text;
  v_full_name text;
  v_role public.app_role;
  v_user_id uuid := gen_random_uuid();
  v_password_hash text;
BEGIN
  v_organization_id := public.require_tenant_admin();

  v_full_name := trim(p_full_name);
  IF v_full_name IS NULL OR v_full_name = '' OR char_length(v_full_name) > 255 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_email := lower(trim(p_email));
  IF v_email IS NULL OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- The public contract only lets an administrator invite operators and agents. Promoting
  -- someone to admin is a separate, explicit role change.
  IF p_role IS NULL OR p_role NOT IN ('operator', 'agent') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_role := p_role::public.app_role;

  IF p_temporary_password IS NULL
     OR char_length(p_temporary_password) < c_min_password_length
     OR octet_length(p_temporary_password) > c_max_password_bytes
  THEN
    RAISE EXCEPTION 'WEAK_PASSWORD' USING ERRCODE = 'raise_exception';
  END IF;

  IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email)
     OR EXISTS (SELECT 1 FROM public.user_profiles WHERE email = v_email)
  THEN
    RAISE EXCEPTION 'EMAIL_ALREADY_EXISTS' USING ERRCODE = 'raise_exception';
  END IF;

  v_password_hash := extensions.crypt(p_temporary_password, extensions.gen_salt('bf'));

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  )
  VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    v_password_hash,
    now(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object('full_name', v_full_name),
    now(), now(),
    '', '', '', ''
  );

  INSERT INTO auth.identities (
    id, provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  )
  VALUES (
    gen_random_uuid(),
    v_user_id::text,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
    'email',
    now(), now(), now()
  );

  INSERT INTO public.user_profiles (
    id, organization_id, full_name, email, role, status, must_change_password
  )
  VALUES (
    v_user_id, v_organization_id, v_full_name, v_email, v_role, 'active', true
  );

  RETURN jsonb_build_object(
    'id', v_user_id,
    'full_name', v_full_name,
    'email', v_email,
    'role', v_role,
    'status', 'active',
    'must_change_password', true
  );
END;
$$;

COMMENT ON FUNCTION public.create_internal_user(text, text, text, text) IS
  'Admin-only: create an operator or agent in the caller''s tenant with a temporary password. Never logs password material.';

REVOKE EXECUTE ON FUNCTION public.create_internal_user(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_internal_user(text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- update_user_role
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_user_role(
  p_user_id uuid,
  p_new_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_new_role public.app_role;
  v_result jsonb;
BEGIN
  v_organization_id := public.require_tenant_admin();

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_new_role IS NULL OR p_new_role NOT IN ('admin', 'operator', 'agent') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_new_role := p_new_role::public.app_role;

  -- An administrator who demotes themselves would leave the tenant with no way to recover
  -- through this module. Cross-tenant ids match zero rows and raise the same validation
  -- error, so they are indistinguishable from an unknown collaborator.
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.user_profiles
  SET role = v_new_role
  WHERE id = p_user_id
    AND organization_id = v_organization_id
  RETURNING jsonb_build_object(
    'id', id,
    'role', role,
    'updated_at', updated_at
  ) INTO v_result;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.update_user_role(uuid, text) IS
  'Admin-only: change a collaborator''s role inside the caller''s tenant. Emits role_changed via trigger.';

REVOKE EXECUTE ON FUNCTION public.update_user_role(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_user_role(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- toggle_user_status
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.toggle_user_status(
  p_user_id uuid,
  p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_status public.user_status;
  v_result jsonb;
BEGIN
  v_organization_id := public.require_tenant_admin();

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_status IS NULL OR p_status NOT IN ('active', 'inactive') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_status := p_status::public.user_status;

  -- Deactivating yourself would strand the session; the same error is used for unknown
  -- or cross-tenant ids so existence of another agency's users is not leaked.
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.user_profiles
  SET status = v_status
  WHERE id = p_user_id
    AND organization_id = v_organization_id
  RETURNING jsonb_build_object(
    'id', id,
    'status', status,
    'updated_at', updated_at
  ) INTO v_result;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.toggle_user_status(uuid, text) IS
  'Admin-only: activate or deactivate a collaborator in the caller''s tenant. Emits user_activated / user_deactivated via trigger.';

REVOKE EXECUTE ON FUNCTION public.toggle_user_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_user_status(uuid, text) TO authenticated;
