-- 010_us5_register_agency.sql
-- User Story 5: public agency onboarding. The Edge Function creates the auth user first,
-- then this RPC inserts the tenant and the founding administrator in one transaction.
-- Source of truth: specs/001-auth-tenant-access/spec.md (FR-008),
-- specs/001-auth-tenant-access/data-model.md ("Registro Atómico de Agencia"),
-- specs/001-auth-tenant-access/contracts/api-contracts.md (POST /auth/v1/signup).
--
-- ERROR CONTRACT: raises the API contract's error code as the exception message
-- (SQLSTATE P0001). The Edge Function and the frontend map `error.message` back to
-- EMAIL_ALREADY_EXISTS / AGENCY_SLUG_EXISTS / VALIDATION_ERROR. Do not reword.
--
-- AUTHORIZATION: callable only by service_role. anon and authenticated cannot create tenants
-- by invoking this function directly; that would skip the Admin API password hashing path
-- (FR-007) and leave auth.users and user_profiles out of step. The Edge Function holds the
-- service role key and is the only supported caller.
--
-- AUDIT: inserting the organization fires `organization_created`; inserting the profile fires
-- `user_created` (migration 007). This function does not write the log itself. The founding
-- admin is not yet in user_profiles when those triggers run under service_role, so actor_id
-- is recorded as NULL (system event), which is allowed.
--
-- TENANT SAFETY: the RPC never trusts a client-supplied organization_id. It always creates a
-- new tenant. The supplied user_id must already exist in auth.users, must not already have a
-- profile, and its email must match p_email, so a leaked UUID cannot be attached to a new
-- agency.

CREATE OR REPLACE FUNCTION public.register_agency(
  p_agency_name text,
  p_admin_user_id uuid,
  p_full_name text,
  p_email text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_agency_name text;
  v_full_name text;
  v_email text;
  v_slug text;
  v_auth_email text;
  v_org_id uuid;
BEGIN
  v_agency_name := trim(p_agency_name);
  IF v_agency_name IS NULL OR v_agency_name = '' OR char_length(v_agency_name) > 255 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_full_name := trim(p_full_name);
  IF v_full_name IS NULL OR v_full_name = '' OR char_length(v_full_name) > 255 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_email := lower(trim(p_email));
  IF v_email IS NULL OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_slug := lower(regexp_replace(v_agency_name, '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  v_slug := regexp_replace(v_slug, '-+', '-', 'g');

  IF v_slug IS NULL OR v_slug = '' OR v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF EXISTS (SELECT 1 FROM public.organizations WHERE slug = v_slug) THEN
    RAISE EXCEPTION 'AGENCY_SLUG_EXISTS' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT u.email INTO v_auth_email
  FROM auth.users u
  WHERE u.id = p_admin_user_id;

  IF v_auth_email IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF lower(v_auth_email) IS DISTINCT FROM v_email THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF EXISTS (SELECT 1 FROM public.user_profiles WHERE id = p_admin_user_id)
     OR EXISTS (SELECT 1 FROM public.user_profiles WHERE email = v_email)
     OR EXISTS (SELECT 1 FROM auth.users WHERE email = v_email AND id IS DISTINCT FROM p_admin_user_id)
  THEN
    RAISE EXCEPTION 'EMAIL_ALREADY_EXISTS' USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.organizations (name, slug, status)
  VALUES (v_agency_name, v_slug, 'active')
  RETURNING id INTO v_org_id;

  -- Founder: must_change_password is false. Collaborators created later (US3) keep the
  -- default of true. The flag is not client-writable (ADR-0003).
  INSERT INTO public.user_profiles (
    id, organization_id, full_name, email, role, status, must_change_password
  )
  VALUES (
    p_admin_user_id, v_org_id, v_full_name, v_email, 'admin', 'active', false
  );

  RETURN jsonb_build_object(
    'organization_id', v_org_id,
    'slug', v_slug,
    'name', v_agency_name,
    'user_id', p_admin_user_id,
    'email', v_email,
    'full_name', v_full_name,
    'role', 'admin'
  );
EXCEPTION
  WHEN unique_violation THEN
    -- Race: two registrations that slugify to the same value, or a duplicate email that
    -- slipped past the SELECT. Map the constraint, never leak table names to the client.
    IF SQLERRM ILIKE '%organizations_slug_key%' OR SQLERRM ILIKE '%slug%' THEN
      RAISE EXCEPTION 'AGENCY_SLUG_EXISTS' USING ERRCODE = 'raise_exception';
    END IF;
    RAISE EXCEPTION 'EMAIL_ALREADY_EXISTS' USING ERRCODE = 'raise_exception';
END;
$$;

COMMENT ON FUNCTION public.register_agency(text, uuid, text, text) IS
  'Service-role only: create a new tenant and attach an already-provisioned auth user as its founding admin. Atomic: both inserts share one transaction.';

REVOKE ALL ON FUNCTION public.register_agency(text, uuid, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_agency(text, uuid, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_agency(text, uuid, text, text) TO service_role;
