-- 025_public_site_read.sql
-- Public read projection for the external site consumer.
-- Source of truth: specs/009-catalog-site-cms/contracts/api-contracts.md

CREATE OR REPLACE FUNCTION public.get_public_site(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_source public.public_source;
  v_offers jsonb := '[]'::jsonb;
  v_lodgings jsonb := '[]'::jsonb;
  v_yachts jsonb := '[]'::jsonb;
  v_jwt_org uuid;
BEGIN
  -- Authenticated callers are limited to their JWT organization.
  -- Anonymous callers use the organization_id of the public site they host.
  IF auth.uid() IS NOT NULL THEN
    v_jwt_org := nullif(auth.jwt() ->> 'organization_id', '')::uuid;
    IF v_jwt_org IS NULL THEN
      RETURN jsonb_build_object(
        'source', 'legacy',
        'offers', '[]'::jsonb,
        'lodgings', '[]'::jsonb,
        'yachts', '[]'::jsonb
      );
    END IF;
    v_organization_id := v_jwt_org;
  ELSE
    v_organization_id := p_organization_id;
  END IF;

  IF v_organization_id IS NULL THEN
    RETURN jsonb_build_object(
      'source', 'legacy',
      'offers', '[]'::jsonb,
      'lodgings', '[]'::jsonb,
      'yachts', '[]'::jsonb
    );
  END IF;

  SELECT ps.source
  INTO v_source
  FROM public.public_sites ps
  WHERE ps.organization_id = v_organization_id;

  IF v_source IS NULL THEN
    RETURN jsonb_build_object(
      'source', 'legacy',
      'offers', '[]'::jsonb,
      'lodgings', '[]'::jsonb,
      'yachts', '[]'::jsonb
    );
  END IF;

  IF v_source = 'legacy'::public.public_source THEN
    RETURN jsonb_build_object(
      'source', 'legacy',
      'offers', '[]'::jsonb,
      'lodgings', '[]'::jsonb,
      'yachts', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(offer ORDER BY offer ->> 'id'), '[]'::jsonb)
  INTO v_offers
  FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
      'id', pl.public_slug,
      'name', pl.name_es,
      'nameEn', pl.name_en,
      'category', pl.public_category_id,
      'description', pl.description_es,
      'descriptionEn', pl.description_en,
      'image', pl.cover_image_ref,
      'includes', (
        SELECT coalesce(jsonb_agg(i ->> 'es' ORDER BY ord), '[]'::jsonb)
        FROM jsonb_array_elements(pl.includes) WITH ORDINALITY AS t(i, ord)
      ),
      'includesEn', (
        SELECT coalesce(jsonb_agg(i ->> 'en' ORDER BY ord), '[]'::jsonb)
        FROM jsonb_array_elements(pl.includes) WITH ORDINALITY AS t(i, ord)
      ),
      'meetingPoint', pl.meeting_point,
      'schedule', pl.schedule,
      'duration', pl.duration,
      'maxGuests', pl.max_guests,
      'warnings', (
        SELECT coalesce(jsonb_agg(w ->> 'es' ORDER BY ord), '[]'::jsonb)
        FROM jsonb_array_elements(pl.warnings) WITH ORDINALITY AS t(w, ord)
      ),
      'warningsEn', (
        SELECT coalesce(jsonb_agg(w ->> 'en' ORDER BY ord), '[]'::jsonb)
        FROM jsonb_array_elements(pl.warnings) WITH ORDINALITY AS t(w, ord)
      ),
      'featured', pl.featured,
      'location', pl.location,
      'rating', pl.rating,
      'price', pl.display_price,
      'originalPrice', pl.original_price,
      'currency', pl.currency,
      'soldOut', pl.sold_out,
      'acceptsRequests', NOT pl.sold_out
    )) AS offer
    FROM public.public_listings pl
    JOIN public.products p
      ON p.id = pl.product_id
     AND p.organization_id = pl.organization_id
    WHERE pl.organization_id = v_organization_id
      AND pl.placement = 'catalog'::public.public_placement
      AND pl.status = 'published'::public.public_listing_status
      AND p.status = 'active'::public.product_status
  ) s;

  SELECT coalesce(jsonb_agg(lodging ORDER BY lodging ->> 'id'), '[]'::jsonb)
  INTO v_lodgings
  FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
      'id', pl.public_slug,
      'name', pl.name_es,
      'nameEn', pl.name_en,
      'type', pl.lodging ->> 'lodging_type',
      'location', pl.lodging ->> 'location_es',
      'locationEn', pl.lodging ->> 'location_en',
      'neighborhood', pl.lodging ->> 'neighborhood_es',
      'neighborhoodEn', pl.lodging ->> 'neighborhood_en',
      'description', pl.description_es,
      'descriptionEn', pl.description_en,
      'pricePerNight', pl.display_price,
      'currency', pl.currency,
      'maxGuests', pl.max_guests,
      'bedrooms', (pl.lodging ->> 'bedrooms')::integer,
      'bathrooms', (pl.lodging ->> 'bathrooms')::integer,
      'image', pl.cover_image_ref,
      'gallery', (
        SELECT coalesce(
          jsonb_agg(coalesce(pi.external_ref, pi.storage_path) ORDER BY pi.sort_order, pi.created_at),
          '[]'::jsonb
        )
        FROM public.public_images pi
        WHERE pi.listing_id = pl.id
          AND pi.replaced_at IS NULL
      ),
      'amenities', coalesce(pl.lodging -> 'amenities', '[]'::jsonb),
      'tags', coalesce(pl.lodging -> 'tags', '[]'::jsonb),
      'rating', pl.rating,
      'reviews', (
        SELECT coalesce(jsonb_agg(
          jsonb_build_object(
            'author', gr.author,
            'rating', gr.rating,
            'text', gr.text_es,
            'textEn', gr.text_en,
            'date', gr.reviewed_on
          )
          ORDER BY gr.reviewed_on DESC, gr.created_at DESC
        ), '[]'::jsonb)
        FROM public.guest_reviews gr
        WHERE gr.listing_id = pl.id
      ),
      'reviewCount', (
        SELECT count(*)::integer FROM public.guest_reviews gr WHERE gr.listing_id = pl.id
      ),
      'mapUrl', nullif(pl.lodging ->> 'map_url', ''),
      'featured', pl.featured,
      'soldOut', pl.sold_out,
      'acceptsRequests', NOT pl.sold_out
    )) AS lodging
    FROM public.public_listings pl
    JOIN public.products p
      ON p.id = pl.product_id
     AND p.organization_id = pl.organization_id
    WHERE pl.organization_id = v_organization_id
      AND pl.placement = 'lodging'::public.public_placement
      AND pl.status = 'published'::public.public_listing_status
      AND p.status = 'active'::public.product_status
  ) s;

  SELECT coalesce(jsonb_agg(yacht ORDER BY yacht ->> 'id'), '[]'::jsonb)
  INTO v_yachts
  FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
      'id', pl.public_slug,
      'name', pl.name_es,
      'nameEn', pl.name_en,
      'description', pl.description_es,
      'descriptionEn', pl.description_en,
      'image', pl.cover_image_ref,
      'capacity', (
        SELECT coalesce(jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object(
            'icon', nullif(line ->> 'icon', ''),
            'text', line ->> 'text_es',
            'textEn', line ->> 'text_en'
          ))
          ORDER BY coalesce((line ->> 'position')::integer, 0)
        ), '[]'::jsonb)
        FROM jsonb_array_elements(pl.yacht_lines) AS line
        WHERE line ->> 'kind' = 'capacity'
      ),
      'features', (
        SELECT coalesce(jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object(
            'icon', nullif(line ->> 'icon', ''),
            'text', line ->> 'text_es',
            'textEn', line ->> 'text_en'
          ))
          ORDER BY coalesce((line ->> 'position')::integer, 0)
        ), '[]'::jsonb)
        FROM jsonb_array_elements(pl.yacht_lines) AS line
        WHERE line ->> 'kind' = 'feature'
      ),
      'price', pl.display_price,
      'currency', pl.currency,
      'soldOut', pl.sold_out,
      'acceptsRequests', NOT pl.sold_out
    )) AS yacht
    FROM public.public_listings pl
    JOIN public.products p
      ON p.id = pl.product_id
     AND p.organization_id = pl.organization_id
    WHERE pl.organization_id = v_organization_id
      AND pl.placement = 'yacht'::public.public_placement
      AND pl.status = 'published'::public.public_listing_status
      AND p.status = 'active'::public.product_status
  ) s;

  RETURN jsonb_build_object(
    'source', 'panel',
    'offers', v_offers,
    'lodgings', v_lodgings,
    'yachts', v_yachts
  );
END;
$$;

COMMENT ON FUNCTION public.get_public_site(uuid) IS
  'Anon/authenticated: project published active listings when source=panel; empty arrays when legacy.';

REVOKE EXECUTE ON FUNCTION public.get_public_site(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_site(uuid) TO anon, authenticated;
