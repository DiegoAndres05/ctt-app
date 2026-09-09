-- 014_create_products.sql
-- Base catalog entity. Subtype tables share this primary key.
-- Source of truth: specs/002-catalog-pricing/data-model.md ("1. Product").

CREATE TABLE public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  provider_id uuid REFERENCES public.providers (id) ON DELETE RESTRICT,
  type public.product_type NOT NULL,
  name text NOT NULL,
  description text,
  status public.product_status NOT NULL DEFAULT 'draft',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT products_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT products_name_max_length CHECK (char_length(name) <= 255),
  -- Composite unique so subtype and join tables can pin tenant with (id, organization_id).
  CONSTRAINT products_id_organization_id_key UNIQUE (id, organization_id)
);

COMMENT ON TABLE public.products IS
  'Base catalog item (experience, accommodation or package). Never deleted physically.';
COMMENT ON COLUMN public.products.type IS
  'Immutable after insert. A product does not change subtype.';
COMMENT ON COLUMN public.products.status IS
  'draft until a current pricing scheme exists; active/inactive are logical only.';

CREATE INDEX products_organization_id_status_idx
  ON public.products (organization_id, status);

CREATE INDEX products_organization_id_type_idx
  ON public.products (organization_id, type);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.products FROM anon;

CREATE POLICY tenant_isolation_select ON public.products
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.products
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.products
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

CREATE TRIGGER products_set_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.prevent_product_type_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.type IS DISTINCT FROM OLD.type THEN
    RAISE EXCEPTION 'Product type is immutable after creation.'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER products_prevent_type_change
  BEFORE UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_product_type_change();
