-- 023_public_listings.sql
-- Tables, RLS, protected categories seed helper, and product-deactivation unpublish trigger.
-- Source of truth: specs/009-catalog-site-cms/data-model.md

CREATE TABLE public.public_sites (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations (id) ON DELETE RESTRICT,
  source public.public_source NOT NULL DEFAULT 'legacy',
  cutover_completed_at timestamptz,
  cutover_completed_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT public_sites_cutover_pair CHECK (
    (source = 'legacy' AND cutover_completed_at IS NULL)
    OR (source = 'panel' AND cutover_completed_at IS NOT NULL)
  )
);

CREATE TABLE public.public_categories (
  id text NOT NULL,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  name_es text NOT NULL,
  name_en text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  protected boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, id),
  CONSTRAINT public_categories_id_format CHECK (id ~ '^[a-z0-9]+(_[a-z0-9]+)*$'),
  CONSTRAINT public_categories_name_es_not_blank CHECK (btrim(name_es) <> ''),
  CONSTRAINT public_categories_name_en_not_blank CHECK (btrim(name_en) <> '')
);

CREATE TABLE public.public_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  product_id uuid NOT NULL,
  placement public.public_placement NOT NULL,
  public_slug text NOT NULL,
  status public.public_listing_status NOT NULL DEFAULT 'draft',
  sold_out boolean NOT NULL DEFAULT false,
  name_es text,
  name_en text,
  description_es text,
  description_en text,
  cover_image_ref text,
  public_category_id text,
  location text,
  meeting_point text,
  schedule text,
  duration text,
  max_guests integer,
  featured boolean NOT NULL DEFAULT false,
  rating numeric(3, 2),
  display_price numeric(12, 2),
  original_price numeric(12, 2),
  currency char(3),
  includes jsonb NOT NULL DEFAULT '[]'::jsonb,
  warnings jsonb NOT NULL DEFAULT '[]'::jsonb,
  lodging jsonb,
  yacht_lines jsonb NOT NULL DEFAULT '[]'::jsonb,
  first_published_at timestamptz,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT public_listings_product_fkey
    FOREIGN KEY (product_id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT public_listings_product_unique UNIQUE (product_id),
  CONSTRAINT public_listings_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT public_listings_slug_unique UNIQUE (organization_id, public_slug),
  CONSTRAINT public_listings_slug_format CHECK (public_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  CONSTRAINT public_listings_category_fkey
    FOREIGN KEY (organization_id, public_category_id)
    REFERENCES public.public_categories (organization_id, id)
    ON DELETE RESTRICT,
  CONSTRAINT public_listings_rating_range CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5)),
  CONSTRAINT public_listings_display_price_positive CHECK (display_price IS NULL OR display_price > 0),
  CONSTRAINT public_listings_original_price_higher CHECK (
    original_price IS NULL
    OR (display_price IS NOT NULL AND original_price > display_price)
  ),
  CONSTRAINT public_listings_currency_iso CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
  CONSTRAINT public_listings_max_guests_positive CHECK (max_guests IS NULL OR max_guests > 0),
  CONSTRAINT public_listings_includes_array CHECK (jsonb_typeof(includes) = 'array'),
  CONSTRAINT public_listings_warnings_array CHECK (jsonb_typeof(warnings) = 'array'),
  CONSTRAINT public_listings_yacht_lines_array CHECK (jsonb_typeof(yacht_lines) = 'array')
);

CREATE INDEX public_listings_org_status_idx
  ON public.public_listings (organization_id, status, placement);

CREATE TABLE public.public_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  listing_id uuid NOT NULL,
  role public.public_image_role NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  storage_path text,
  external_ref text,
  replaced_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT public_images_listing_fkey
    FOREIGN KEY (listing_id, organization_id)
    REFERENCES public.public_listings (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT public_images_ref_xor CHECK (
    (storage_path IS NOT NULL AND external_ref IS NULL)
    OR (storage_path IS NULL AND external_ref IS NOT NULL)
  )
);

CREATE UNIQUE INDEX public_images_one_active_cover
  ON public.public_images (listing_id)
  WHERE role = 'cover' AND replaced_at IS NULL;

CREATE TABLE public.guest_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  listing_id uuid NOT NULL,
  author text NOT NULL,
  rating integer NOT NULL,
  text_es text NOT NULL,
  text_en text NOT NULL,
  reviewed_on date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT guest_reviews_listing_fkey
    FOREIGN KEY (listing_id, organization_id)
    REFERENCES public.public_listings (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT guest_reviews_author_not_blank CHECK (btrim(author) <> ''),
  CONSTRAINT guest_reviews_rating_range CHECK (rating BETWEEN 1 AND 5),
  CONSTRAINT guest_reviews_text_es_not_blank CHECK (btrim(text_es) <> ''),
  CONSTRAINT guest_reviews_text_en_not_blank CHECK (btrim(text_en) <> '')
);

CREATE TABLE public.public_cutover_items (
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  public_slug text NOT NULL,
  placement public.public_placement NOT NULL,
  listing_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, public_slug),
  CONSTRAINT public_cutover_items_listing_fkey
    FOREIGN KEY (listing_id, organization_id)
    REFERENCES public.public_listings (id, organization_id)
    ON DELETE SET NULL
);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

ALTER TABLE public.public_sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guest_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_cutover_items ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.public_sites FROM anon;
REVOKE ALL ON public.public_categories FROM anon;
REVOKE ALL ON public.public_listings FROM anon;
REVOKE ALL ON public.public_images FROM anon;
REVOKE ALL ON public.guest_reviews FROM anon;
REVOKE ALL ON public.public_cutover_items FROM anon;

CREATE POLICY tenant_isolation_select ON public.public_sites
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.public_categories
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_write ON public.public_categories
  FOR ALL TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY tenant_isolation_select ON public.public_listings
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_write ON public.public_listings
  FOR ALL TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY tenant_isolation_select ON public.public_images
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_write ON public.public_images
  FOR ALL TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY tenant_isolation_select ON public.guest_reviews
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_write ON public.guest_reviews
  FOR ALL TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY tenant_isolation_select ON public.public_cutover_items
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_write ON public.public_cutover_items
  FOR ALL TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_write ON public.public_sites
  FOR ALL TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

-- ---------------------------------------------------------------------------
-- Ensure public site + protected categories for every organization
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ensure_public_site_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.public_sites (organization_id)
  VALUES (NEW.id)
  ON CONFLICT (organization_id) DO NOTHING;

  INSERT INTO public.public_categories (id, organization_id, name_es, name_en, is_active, protected)
  VALUES
    ('islas', NEW.id, 'Islas', 'Islands', true, true),
    ('baru', NEW.id, 'Barú', 'Barú', true, true),
    ('tierra_bomba', NEW.id, 'Tierra Bomba', 'Tierra Bomba', true, true),
    ('compartidos', NEW.id, 'Compartidos', 'Shared', true, true),
    ('cultural', NEW.id, 'Cultural', 'Cultural', true, true),
    ('aventura', NEW.id, 'Aventura', 'Adventure', true, true),
    ('baile', NEW.id, 'Baile', 'Dance', true, true),
    ('premium', NEW.id, 'Premium', 'Premium', true, true)
  ON CONFLICT (organization_id, id) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE TRIGGER organizations_ensure_public_site_defaults
  AFTER INSERT ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_public_site_defaults();

-- Backfill existing organizations
INSERT INTO public.public_sites (organization_id)
SELECT id FROM public.organizations
ON CONFLICT (organization_id) DO NOTHING;

INSERT INTO public.public_categories (id, organization_id, name_es, name_en, is_active, protected)
SELECT c.id, o.id, c.name_es, c.name_en, true, true
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('islas', 'Islas', 'Islands'),
    ('baru', 'Barú', 'Barú'),
    ('tierra_bomba', 'Tierra Bomba', 'Tierra Bomba'),
    ('compartidos', 'Compartidos', 'Shared'),
    ('cultural', 'Cultural', 'Cultural'),
    ('aventura', 'Aventura', 'Adventure'),
    ('baile', 'Baile', 'Dance'),
    ('premium', 'Premium', 'Premium')
) AS c(id, name_es, name_en)
ON CONFLICT (organization_id, id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Deactivating a product unpublishes its public listing (FR-019)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.unpublish_listing_on_product_inactive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status = 'inactive'::public.product_status
  THEN
    UPDATE public.public_listings pl
    SET
      status = 'unpublished'::public.public_listing_status,
      updated_at = now()
    WHERE pl.product_id = NEW.id
      AND pl.organization_id = NEW.organization_id
      AND pl.status = 'published'::public.public_listing_status;

    IF FOUND THEN
      PERFORM audit.log_event(
        NEW.organization_id,
        'public_listing_unpublished'::audit.audit_event_type,
        'success'::audit.audit_result,
        auth.uid(),
        'public_listing',
        (
          SELECT pl.id
          FROM public.public_listings pl
          WHERE pl.product_id = NEW.id
          LIMIT 1
        ),
        jsonb_build_object('reason', 'product_inactive')
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER products_unpublish_public_listing
  AFTER UPDATE OF status ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.unpublish_listing_on_product_inactive();
