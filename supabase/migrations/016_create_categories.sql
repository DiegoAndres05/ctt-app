-- 016_create_categories.sql
-- Organization-scoped taxonomies (optional hierarchy) and product tagging (N:M).
-- Source of truth: specs/002-catalog-pricing/data-model.md ("5. Category").

CREATE TABLE public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  parent_id uuid REFERENCES public.categories (id) ON DELETE RESTRICT,
  name text NOT NULL,
  slug text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT categories_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT categories_name_max_length CHECK (char_length(name) <= 120),
  CONSTRAINT categories_slug_not_blank CHECK (btrim(slug) <> ''),
  CONSTRAINT categories_organization_id_slug_key UNIQUE (organization_id, slug),
  CONSTRAINT categories_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT categories_parent_not_self CHECK (parent_id IS DISTINCT FROM id)
);

COMMENT ON TABLE public.categories IS
  'Organization-scoped catalog taxonomy. parent_id is optional hierarchy.';

CREATE INDEX categories_organization_id_idx ON public.categories (organization_id);

CREATE INDEX categories_parent_id_idx ON public.categories (parent_id);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.categories FROM anon;

CREATE POLICY tenant_isolation_select ON public.categories
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.categories
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.categories
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

CREATE TRIGGER categories_set_updated_at
  BEFORE UPDATE ON public.categories
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.enforce_category_parent_same_org()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.parent_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.categories c
    WHERE c.id = NEW.parent_id
      AND c.organization_id = NEW.organization_id
  ) THEN
    RAISE EXCEPTION 'Category parent must belong to the same organization.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER categories_parent_same_org
  BEFORE INSERT OR UPDATE ON public.categories
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_category_parent_same_org();

CREATE TABLE public.product_categories (
  product_id uuid NOT NULL,
  category_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  PRIMARY KEY (product_id, category_id),
  CONSTRAINT product_categories_product_tenant_fkey
    FOREIGN KEY (product_id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT product_categories_category_tenant_fkey
    FOREIGN KEY (category_id, organization_id)
    REFERENCES public.categories (id, organization_id)
    ON DELETE CASCADE
);

COMMENT ON TABLE public.product_categories IS
  'N:M tagging of products with organization categories. organization_id is denormalized for RLS.';

CREATE INDEX product_categories_category_id_idx ON public.product_categories (category_id);

CREATE INDEX product_categories_organization_id_idx ON public.product_categories (organization_id);

ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.product_categories FROM anon;

CREATE POLICY tenant_isolation_select ON public.product_categories
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.product_categories
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_delete ON public.product_categories
  FOR DELETE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );
