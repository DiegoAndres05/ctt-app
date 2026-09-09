-- 003_create_user_profiles.sql
-- Business extension of auth.users: an internal collaborator of an agency.
-- Credentials themselves (bcrypt hash) stay in auth.users.encrypted_password and are managed
-- exclusively by Supabase Auth (FR-007). This table never stores password material.
-- Source of truth: specs/001-auth-tenant-access/data-model.md ("2. User Profile").

CREATE TABLE public.user_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  full_name text NOT NULL,
  email text NOT NULL,
  role public.app_role NOT NULL DEFAULT 'agent',
  status public.user_status NOT NULL DEFAULT 'active',
  must_change_password boolean NOT NULL DEFAULT true,
  failed_login_attempts integer NOT NULL DEFAULT 0,
  locked_until timestamptz,
  last_activity_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_email_key UNIQUE (email),
  CONSTRAINT user_profiles_full_name_not_blank CHECK (btrim(full_name) <> ''),
  CONSTRAINT user_profiles_full_name_max_length CHECK (char_length(full_name) <= 255),
  CONSTRAINT user_profiles_email_is_wellformed CHECK (email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  CONSTRAINT user_profiles_failed_login_attempts_non_negative CHECK (failed_login_attempts >= 0)
);

COMMENT ON TABLE public.user_profiles IS
  'Internal collaborator of an agency. Extends auth.users with tenant, role and lockout state.';
COMMENT ON COLUMN public.user_profiles.email IS
  'Display copy of auth.users.email. auth.users remains the authoritative credential store.';
COMMENT ON COLUMN public.user_profiles.must_change_password IS
  'Set while the collaborator still holds the temporary password assigned by an administrator.';
COMMENT ON COLUMN public.user_profiles.locked_until IS
  'Set when consecutive failed logins trip the lockout threshold; NULL means not locked.';
COMMENT ON COLUMN public.user_profiles.last_activity_at IS
  'Drives the inactivity-based session timeout.';

-- Tenant filtering; every RLS policy on this table reads organization_id.
CREATE INDEX user_profiles_organization_id_idx ON public.user_profiles (organization_id);

-- Listing active collaborators of an organization.
CREATE INDEX user_profiles_organization_id_status_idx
  ON public.user_profiles (organization_id, status);

-- Default Deny: enabled at creation so the table is never reachable without an explicit
-- policy. Policies are granted in migration 005.
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.user_profiles FROM anon;
