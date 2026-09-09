-- 019_us2_addons.sql
-- User Story 2: independent add-ons, product eligibility rules, and the deferred FK from
-- pricing_schemes.addon_id. Source of truth: specs/002-catalog-pricing/data-model.md
-- ("6. Add-on + Product Add-ons", RLS overview).
--
-- organization_id is denormalized on product_addons (same pattern as product_categories) so
-- RLS can filter without a join, and so the composite FKs pin both sides to one tenant.

CREATE TABLE public.add_ons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  name text NOT NULL,
  description text,
  unit public.addon_unit NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT add_ons_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT add_ons_name_max_length CHECK (char_length(name) <= 255),
  CONSTRAINT add_ons_id_organization_id_key UNIQUE (id, organization_id)
);

COMMENT ON TABLE public.add_ons IS
  'Organization-scoped complementary service that can be offered on one or more products.';

CREATE INDEX add_ons_organization_id_idx ON public.add_ons (organization_id);

ALTER TABLE public.add_ons ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.add_ons FROM anon;

CREATE POLICY tenant_isolation_select ON public.add_ons
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.add_ons
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.add_ons
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

CREATE POLICY operator_delete ON public.add_ons
  FOR DELETE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE TRIGGER add_ons_set_updated_at
  BEFORE UPDATE ON public.add_ons
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.product_addons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  addon_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  is_mandatory boolean NOT NULL DEFAULT false,
  max_quantity integer,
  CONSTRAINT product_addons_product_addon_key UNIQUE (product_id, addon_id),
  CONSTRAINT product_addons_max_quantity_positive CHECK (max_quantity IS NULL OR max_quantity >= 1),
  CONSTRAINT product_addons_product_tenant_fkey
    FOREIGN KEY (product_id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT product_addons_addon_tenant_fkey
    FOREIGN KEY (addon_id, organization_id)
    REFERENCES public.add_ons (id, organization_id)
    ON DELETE CASCADE
);

COMMENT ON TABLE public.product_addons IS
  'Eligibility of an add-on for a product, with applicability rules (mandatory, max quantity).';

CREATE INDEX product_addons_addon_id_idx ON public.product_addons (addon_id);

CREATE INDEX product_addons_organization_id_idx ON public.product_addons (organization_id);

ALTER TABLE public.product_addons ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.product_addons FROM anon;

CREATE POLICY tenant_isolation_select ON public.product_addons
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.product_addons
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.product_addons
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

CREATE POLICY operator_delete ON public.product_addons
  FOR DELETE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

-- Deferred from 017: pricing_schemes.addon_id now has a real target.
ALTER TABLE public.pricing_schemes
  ADD CONSTRAINT pricing_schemes_addon_tenant_fkey
  FOREIGN KEY (addon_id, organization_id)
  REFERENCES public.add_ons (id, organization_id)
  ON DELETE RESTRICT;
