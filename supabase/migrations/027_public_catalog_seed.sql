-- 027_public_catalog_seed.sql
-- Manifesto cutover items for the demo org + a small representative published set
-- (1 catalog offer, 1 lodging, 1 yacht). Remaining manifesto rows stay unlinked so
-- complete_public_cutover stays blocked until tests/operators fill them.
--
-- Demo org is created in supabase/seed.sql AFTER migrations; a trigger seeds when
-- that organization appears. Backfill runs if the org already exists.

CREATE OR REPLACE FUNCTION public.seed_public_cutover_manifest(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_organization_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
    RETURN;
  END IF;

  INSERT INTO public.public_cutover_items (organization_id, public_slug, placement)
  VALUES
    -- Catalog offers (29)
    (p_organization_id, 'islas-capri-premium', 'catalog'),
    (p_organization_id, 'islas-capri-classic', 'catalog'),
    (p_organization_id, 'islas-borabora-vip', 'catalog'),
    (p_organization_id, 'islas-borabora-club', 'catalog'),
    (p_organization_id, 'baru-aura', 'catalog'),
    (p_organization_id, 'baru-puerto-medallo', 'catalog'),
    (p_organization_id, 'baru-nena-beach', 'catalog'),
    (p_organization_id, 'baru-cabana-geronimo', 'catalog'),
    (p_organization_id, 'tierra-fenix-pasadia', 'catalog'),
    (p_organization_id, 'tierra-fenix-cena', 'catalog'),
    (p_organization_id, 'tierra-makani', 'catalog'),
    (p_organization_id, 'tierra-isla-real', 'catalog'),
    (p_organization_id, 'tour-5-clasicos', 'catalog'),
    (p_organization_id, 'tour-cholon-party', 'catalog'),
    (p_organization_id, 'tour-4-destinos', 'catalog'),
    (p_organization_id, 'tour-aviario-playa', 'catalog'),
    (p_organization_id, 'tour-5-clasicos-openbar', 'catalog'),
    (p_organization_id, 'cultural-chiva', 'catalog'),
    (p_organization_id, 'cultural-van', 'catalog'),
    (p_organization_id, 'cultural-pintura', 'catalog'),
    (p_organization_id, 'cultural-rones', 'catalog'),
    (p_organization_id, 'cultural-cocina', 'catalog'),
    (p_organization_id, 'aventura-atv-adrenalina', 'catalog'),
    (p_organization_id, 'aventura-atv-full', 'catalog'),
    (p_organization_id, 'aventura-acuaticos', 'catalog'),
    (p_organization_id, 'baile-latinos-azotea', 'catalog'),
    (p_organization_id, 'premium-volcan', 'catalog'),
    (p_organization_id, 'premium-sibarita', 'catalog'),
    (p_organization_id, 'premium-botes', 'catalog'),
    -- Lodgings (6)
    (p_organization_id, 'villa-caribe', 'lodging'),
    (p_organization_id, 'apartamento-centro-historico', 'lodging'),
    (p_organization_id, 'casa-del-mar', 'lodging'),
    (p_organization_id, 'loft-cartagena', 'lodging'),
    (p_organization_id, 'finca-la-paz', 'lodging'),
    (p_organization_id, 'suite-real', 'lodging'),
    -- Yachts (4)
    (p_organization_id, 'azimut-70', 'yacht'),
    (p_organization_id, 'leopard-51', 'yacht'),
    (p_organization_id, 'firpol-42', 'yacht'),
    (p_organization_id, 'bravo-380', 'yacht')
  ON CONFLICT (organization_id, public_slug) DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.seed_public_cutover_manifest(uuid) IS
  'Idempotent insert of the CTT public manifesto cutover rows for an organization.';

CREATE OR REPLACE FUNCTION public.seed_public_catalog_demo_listings(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_offer_id uuid := '00000000-0000-4000-e000-000000000101';
  v_lodging_id uuid := '00000000-0000-4000-e000-000000000102';
  v_yacht_id uuid := '00000000-0000-4000-e000-000000000103';
  v_offer_listing uuid;
  v_lodging_listing uuid;
  v_yacht_listing uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
    RETURN;
  END IF;

  -- Skip if representative listings already exist
  IF EXISTS (
    SELECT 1 FROM public.public_listings
    WHERE organization_id = p_organization_id
      AND public_slug = 'islas-capri-premium'
  ) THEN
    RETURN;
  END IF;

  -- Offer product + tariff + published listing
  INSERT INTO public.products (id, organization_id, type, name, description, status)
  VALUES (
    v_offer_id, p_organization_id, 'experience',
    'Islas Capri Premium (demo)', 'Demo catalog listing', 'draft'
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.experiences (
    id, organization_id, duration_minutes, difficulty, meeting_point, min_capacity, max_capacity
  )
  VALUES (
    v_offer_id, p_organization_id, 480, 'easy', 'Muelle La Bodeguita', 1, 12
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
  )
  SELECT p_organization_id, v_offer_id, 'COP', 500950, 'per_person', now(), NULL
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pricing_schemes
    WHERE product_id = v_offer_id AND valid_to IS NULL
  );

  UPDATE public.products SET status = 'active' WHERE id = v_offer_id AND status = 'draft';

  INSERT INTO public.public_listings (
    organization_id, product_id, placement, public_slug, status, sold_out,
    name_es, name_en, description_es, description_en, cover_image_ref,
    public_category_id, location, meeting_point, schedule, duration, max_guests,
    featured, rating, display_price, original_price, currency, includes, warnings,
    first_published_at, published_at
  )
  VALUES (
    p_organization_id, v_offer_id, 'catalog', 'islas-capri-premium', 'published', false,
    'Islas Capri Premium', 'Capri Islands Premium',
    'Día en las islas con almuerzo.', 'Island day with lunch.',
    '/images/islas-capri-premium.jpg',
    'islas', 'Islas del Rosario', 'Muelle La Bodeguita', '7:00 AM – 5:00 PM', '10 horas', 12,
    true, 4.9, 500950, 625950, 'COP',
    '[{"es":"Transporte","en":"Transport"},{"es":"Almuerzo","en":"Lunch"}]'::jsonb,
    '[]'::jsonb,
    now(), now()
  )
  ON CONFLICT (product_id) DO NOTHING
  RETURNING id INTO v_offer_listing;

  IF v_offer_listing IS NULL THEN
    SELECT id INTO v_offer_listing FROM public.public_listings WHERE product_id = v_offer_id;
  END IF;

  INSERT INTO public.public_images (organization_id, listing_id, role, sort_order, external_ref)
  SELECT p_organization_id, v_offer_listing, 'cover', 0, '/images/islas-capri-premium.jpg'
  WHERE v_offer_listing IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.public_images
      WHERE listing_id = v_offer_listing AND role = 'cover' AND replaced_at IS NULL
    );

  UPDATE public.public_cutover_items
  SET listing_id = v_offer_listing
  WHERE organization_id = p_organization_id
    AND public_slug = 'islas-capri-premium'
    AND v_offer_listing IS NOT NULL;

  -- Lodging product + tariff + published listing
  INSERT INTO public.products (id, organization_id, type, name, description, status)
  VALUES (
    v_lodging_id, p_organization_id, 'accommodation',
    'Villa Caribe (demo)', 'Demo lodging listing', 'draft'
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.accommodations (
    id, organization_id, property_type, location, max_occupancy
  )
  VALUES (
    v_lodging_id, p_organization_id, 'villa', 'Cartagena', 8
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
  )
  SELECT p_organization_id, v_lodging_id, 'COP', 850000, 'per_night', now(), NULL
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pricing_schemes
    WHERE product_id = v_lodging_id AND valid_to IS NULL
  );

  UPDATE public.products SET status = 'active' WHERE id = v_lodging_id AND status = 'draft';

  INSERT INTO public.public_listings (
    organization_id, product_id, placement, public_slug, status, sold_out,
    name_es, name_en, description_es, description_en, cover_image_ref,
    max_guests, featured, rating, display_price, currency, includes, warnings, lodging,
    first_published_at, published_at
  )
  VALUES (
    p_organization_id, v_lodging_id, 'lodging', 'villa-caribe', 'published', false,
    'Villa Caribe', 'Caribbean Villa',
    'Villa amplia cerca del mar.', 'Spacious villa near the sea.',
    '/images/villa-caribe.jpg',
    8, true, 4.8, 850000, 'COP', '[]'::jsonb, '[]'::jsonb,
    jsonb_build_object(
      'lodging_type', 'casa',
      'location_es', 'Cartagena',
      'location_en', 'Cartagena',
      'neighborhood_es', 'Bocagrande',
      'neighborhood_en', 'Bocagrande',
      'bedrooms', 4,
      'bathrooms', 3,
      'amenities', jsonb_build_array('wifi', 'pool', 'ac'),
      'tags', jsonb_build_array('familia', 'piscina'),
      'map_url', 'https://maps.example.com/villa-caribe'
    ),
    now(), now()
  )
  ON CONFLICT (product_id) DO NOTHING
  RETURNING id INTO v_lodging_listing;

  IF v_lodging_listing IS NULL THEN
    SELECT id INTO v_lodging_listing FROM public.public_listings WHERE product_id = v_lodging_id;
  END IF;

  INSERT INTO public.public_images (organization_id, listing_id, role, sort_order, external_ref)
  SELECT p_organization_id, v_lodging_listing, 'cover', 0, '/images/villa-caribe.jpg'
  WHERE v_lodging_listing IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.public_images
      WHERE listing_id = v_lodging_listing AND role = 'cover' AND replaced_at IS NULL
    );

  UPDATE public.public_cutover_items
  SET listing_id = v_lodging_listing
  WHERE organization_id = p_organization_id
    AND public_slug = 'villa-caribe'
    AND v_lodging_listing IS NOT NULL;

  -- Yacht product + tariff (no display_price) + published listing
  INSERT INTO public.products (id, organization_id, type, name, description, status)
  VALUES (
    v_yacht_id, p_organization_id, 'experience',
    'Azimut 70 (demo)', 'Demo yacht listing', 'draft'
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.experiences (
    id, organization_id, duration_minutes, difficulty, meeting_point, min_capacity, max_capacity
  )
  VALUES (
    v_yacht_id, p_organization_id, 240, 'easy', 'Marina Club de Pesca', 1, 12
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
  )
  SELECT p_organization_id, v_yacht_id, 'COP', 4500000, 'per_group', now(), NULL
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pricing_schemes
    WHERE product_id = v_yacht_id AND valid_to IS NULL
  );

  UPDATE public.products SET status = 'active' WHERE id = v_yacht_id AND status = 'draft';

  INSERT INTO public.public_listings (
    organization_id, product_id, placement, public_slug, status, sold_out,
    name_es, name_en, description_es, description_en, cover_image_ref,
    featured, yacht_lines, first_published_at, published_at
  )
  VALUES (
    p_organization_id, v_yacht_id, 'yacht', 'azimut-70', 'published', false,
    'AZIMUT 70', 'AZIMUT 70',
    'Yate de lujo para charter.', 'Luxury yacht for charter.',
    '/images/azimut-70.jpg',
    true,
    jsonb_build_array(
      jsonb_build_object(
        'kind', 'capacity', 'position', 0, 'icon', 'people',
        'text_es', 'Hasta 12 pasajeros', 'text_en', 'Up to 12 guests'
      ),
      jsonb_build_object(
        'kind', 'feature', 'position', 0, 'icon', 'boat',
        'text_es', 'Flybridge', 'text_en', 'Flybridge'
      )
    ),
    now(), now()
  )
  ON CONFLICT (product_id) DO NOTHING
  RETURNING id INTO v_yacht_listing;

  IF v_yacht_listing IS NULL THEN
    SELECT id INTO v_yacht_listing FROM public.public_listings WHERE product_id = v_yacht_id;
  END IF;

  INSERT INTO public.public_images (organization_id, listing_id, role, sort_order, external_ref)
  SELECT p_organization_id, v_yacht_listing, 'cover', 0, '/images/azimut-70.jpg'
  WHERE v_yacht_listing IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.public_images
      WHERE listing_id = v_yacht_listing AND role = 'cover' AND replaced_at IS NULL
    );

  UPDATE public.public_cutover_items
  SET listing_id = v_yacht_listing
  WHERE organization_id = p_organization_id
    AND public_slug = 'azimut-70'
    AND v_yacht_listing IS NOT NULL;
END;
$$;

COMMENT ON FUNCTION public.seed_public_catalog_demo_listings(uuid) IS
  'Seeds three representative published public listings for local demo (offer, lodging, yacht).';

CREATE OR REPLACE FUNCTION public.seed_public_catalog_on_org_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.id = '00000000-0000-4000-a000-000000000001'::uuid THEN
    PERFORM public.seed_public_cutover_manifest(NEW.id);
    PERFORM public.seed_public_catalog_demo_listings(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS organizations_seed_public_catalog ON public.organizations;
CREATE TRIGGER organizations_seed_public_catalog
  AFTER INSERT ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_public_catalog_on_org_insert();

-- Backfill when demo org already exists (e.g. re-apply)
SELECT public.seed_public_cutover_manifest('00000000-0000-4000-a000-000000000001'::uuid);
SELECT public.seed_public_catalog_demo_listings('00000000-0000-4000-a000-000000000001'::uuid);
