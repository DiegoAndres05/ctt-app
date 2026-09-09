-- 00_supabase_harness.sql
-- Recreates the parts of a Supabase project that the migrations and the SQL tests depend on,
-- so both can run against a plain PostgreSQL 17 instance.
--
-- Only for local verification. A real Supabase project already provides everything below, and
-- this file must never be applied to one.
--
-- What is reproduced, and why each piece matters for the tests:
--   * the four platform roles, because every RLS policy is scoped `TO authenticated` and the
--     tests must be able to `SET ROLE` into it (the migration owner bypasses RLS);
--   * default privileges on `public`, because RLS only becomes the deciding factor once the
--     role already holds table privileges, exactly as on Supabase;
--   * `auth.uid()` and `auth.jwt()`, which read the request claims the tests set with
--     `set_config('request.jwt.claims', ...)`, the same GUC PostgREST populates;
--   * the `auth` tables the credential functions touch.

-- ---------------------------------------------------------------------------
-- Platform roles
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin NOLOGIN NOINHERIT;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Schemas and extensions
-- ---------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO authenticated, service_role, supabase_auth_admin;

-- Mirrors the Supabase defaults: application roles hold table privileges on `public`, and RLS
-- is what narrows them down. Without this the tests would pass for the wrong reason.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- auth.users and friends
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS auth.users (
  instance_id uuid,
  id uuid PRIMARY KEY,
  aud varchar(255),
  role varchar(255),
  email varchar(255) UNIQUE,
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb,
  created_at timestamptz,
  updated_at timestamptz,
  confirmation_token varchar(255),
  recovery_token varchar(255),
  email_change varchar(255),
  email_change_token_new varchar(255)
);

CREATE TABLE IF NOT EXISTS auth.identities (
  id uuid PRIMARY KEY,
  provider_id text NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  identity_data jsonb NOT NULL,
  provider text NOT NULL,
  last_sign_in_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS auth.sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at timestamptz,
  updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS auth.refresh_tokens (
  id bigserial PRIMARY KEY,
  session_id uuid REFERENCES auth.sessions (id) ON DELETE CASCADE,
  user_id uuid,
  token text,
  revoked boolean NOT NULL DEFAULT false,
  created_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Claim accessors
-- ---------------------------------------------------------------------------

-- Identical in behaviour to Supabase's: both read the `request.jwt.claims` GUC that PostgREST
-- sets per request from the verified token. Nothing here validates a signature, and nothing
-- in the migrations relies on it doing so.
CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb;
$$;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(
    coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ),
    ''
  )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  );
$$;

GRANT EXECUTE ON FUNCTION auth.jwt(), auth.uid(), auth.role()
  TO anon, authenticated, service_role, supabase_auth_admin;
