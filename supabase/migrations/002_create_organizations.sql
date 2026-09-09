-- 002_create_organizations.sql
-- Organization = tourism agency = tenant. It is the unit of data isolation.
-- Source of truth: specs/001-auth-tenant-access/data-model.md ("1. Organization (Tenant)").

CREATE TABLE public.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL,
  status public.organization_status NOT NULL DEFAULT 'active',
  settings jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organizations_slug_key UNIQUE (slug),
  CONSTRAINT organizations_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT organizations_name_max_length CHECK (char_length(name) <= 255),
  CONSTRAINT organizations_slug_is_url_friendly CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

COMMENT ON TABLE public.organizations IS
  'Tourism agency (tenant). Every business row in the platform belongs to exactly one organization.';
COMMENT ON COLUMN public.organizations.slug IS
  'Globally unique URL-friendly identifier: lowercase letters, digits and single hyphens.';
COMMENT ON COLUMN public.organizations.settings IS
  'Tenant-scoped operational configuration. Extends behaviour without forking business logic.';

-- Listing active organizations.
CREATE INDEX organizations_status_idx ON public.organizations (status);

-- Default Deny: enabled at creation so the table is never reachable without an explicit
-- policy. Policies are granted in migration 005.
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.organizations FROM anon;
