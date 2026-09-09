-- 013_create_providers.sql
-- Organization-scoped supplier metadata. Availability logic belongs to a later capability.
-- Source of truth: specs/002-catalog-pricing/data-model.md ("8. Provider").

CREATE TABLE public.providers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  name text NOT NULL,
  contact_email text,
  contact_phone text,
  metadata jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT providers_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT providers_name_max_length CHECK (char_length(name) <= 255)
);

COMMENT ON TABLE public.providers IS
  'Supplier metadata for catalog products, scoped to one organization.';

CREATE INDEX providers_organization_id_idx ON public.providers (organization_id);

ALTER TABLE public.providers ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.providers FROM anon;

CREATE POLICY tenant_isolation_select ON public.providers
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.providers
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.providers
  FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE TRIGGER providers_set_updated_at
  BEFORE UPDATE ON public.providers
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();
