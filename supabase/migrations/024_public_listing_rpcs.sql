-- 024_public_listing_rpcs.sql
-- SECURITY DEFINER RPCs for public listings (feature 009).
-- Source of truth: specs/009-catalog-site-cms/contracts/api-contracts.md
--
-- ERROR CONTRACT: raise the API code as the exception message (SQLSTATE P0001 /
-- insufficient_privilege). Frontend maps error.message to application codes.

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.require_catalog_manager_or_forbidden()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
BEGIN
  BEGIN
    v_organization_id := public.require_catalog_manager();
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM = 'SESSION_EXPIRED' THEN
        RAISE;
      END IF;
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END;
  RETURN v_organization_id;
END;
$$;

REVOKE ALL ON FUNCTION public.require_catalog_manager_or_forbidden() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.require_catalog_manager_or_forbidden() FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.validate_bilingual_pairs(p_items jsonb)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_item jsonb;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'BILINGUAL_PAIR_INCOMPLETE' USING ERRCODE = 'raise_exception';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) AS t(value)
  LOOP
    IF nullif(btrim(coalesce(v_item ->> 'es', '')), '') IS NULL
       OR nullif(btrim(coalesce(v_item ->> 'en', '')), '') IS NULL
    THEN
      RAISE EXCEPTION 'BILINGUAL_PAIR_INCOMPLETE' USING ERRCODE = 'raise_exception';
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_bilingual_pairs(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_bilingual_pairs(jsonb) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.product_has_valid_price(
  p_product_id uuid,
  p_organization_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pricing_schemes ps
    WHERE ps.product_id = p_product_id
      AND ps.organization_id = p_organization_id
      AND ps.valid_to IS NULL
      AND ps.valid_from <= now()
  );
$$;

REVOKE ALL ON FUNCTION public.product_has_valid_price(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.product_has_valid_price(uuid, uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.listing_is_complete_for_publish(
  p_listing public.public_listings
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_item jsonb;
  v_has_capacity boolean := false;
  v_has_feature boolean := false;
  v_lodging jsonb;
  v_map_url text;
BEGIN
  IF nullif(btrim(coalesce(p_listing.name_es, '')), '') IS NULL
     OR nullif(btrim(coalesce(p_listing.name_en, '')), '') IS NULL
     OR nullif(btrim(coalesce(p_listing.description_es, '')), '') IS NULL
     OR nullif(btrim(coalesce(p_listing.description_en, '')), '') IS NULL
     OR nullif(btrim(coalesce(p_listing.cover_image_ref, '')), '') IS NULL
  THEN
    RETURN false;
  END IF;

  BEGIN
    PERFORM public.validate_bilingual_pairs(p_listing.warnings);
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM = 'BILINGUAL_PAIR_INCOMPLETE' THEN
        RETURN false;
      END IF;
      RAISE;
  END;

  IF p_listing.placement = 'catalog'::public.public_placement THEN
    IF p_listing.public_category_id IS NULL
       OR nullif(btrim(coalesce(p_listing.location, '')), '') IS NULL
       OR p_listing.display_price IS NULL
       OR p_listing.currency IS NULL
       OR jsonb_array_length(coalesce(p_listing.includes, '[]'::jsonb)) < 1
    THEN
      RETURN false;
    END IF;
    BEGIN
      PERFORM public.validate_bilingual_pairs(p_listing.includes);
    EXCEPTION
      WHEN raise_exception THEN
        IF SQLERRM = 'BILINGUAL_PAIR_INCOMPLETE' THEN
          RETURN false;
        END IF;
        RAISE;
    END;
  ELSIF p_listing.placement = 'lodging'::public.public_placement THEN
    IF p_listing.display_price IS NULL
       OR p_listing.currency IS NULL
       OR p_listing.max_guests IS NULL
       OR p_listing.max_guests <= 0
       OR p_listing.lodging IS NULL
       OR jsonb_typeof(p_listing.lodging) IS DISTINCT FROM 'object'
    THEN
      RETURN false;
    END IF;
    v_lodging := p_listing.lodging;
    IF coalesce(v_lodging ->> 'lodging_type', '') NOT IN ('casa', 'apartamento', 'finca', 'habitacion')
       OR nullif(btrim(coalesce(v_lodging ->> 'location_es', '')), '') IS NULL
       OR nullif(btrim(coalesce(v_lodging ->> 'location_en', '')), '') IS NULL
       OR nullif(btrim(coalesce(v_lodging ->> 'neighborhood_es', '')), '') IS NULL
       OR nullif(btrim(coalesce(v_lodging ->> 'neighborhood_en', '')), '') IS NULL
       OR (v_lodging ->> 'bedrooms') IS NULL
       OR (v_lodging ->> 'bathrooms') IS NULL
       OR (v_lodging ->> 'bedrooms')::integer < 0
       OR (v_lodging ->> 'bathrooms')::integer < 0
    THEN
      RETURN false;
    END IF;
    v_map_url := nullif(btrim(coalesce(v_lodging ->> 'map_url', '')), '');
    IF v_map_url IS NOT NULL AND v_map_url !~ '^https://' THEN
      RETURN false;
    END IF;
  ELSIF p_listing.placement = 'yacht'::public.public_placement THEN
    IF jsonb_array_length(coalesce(p_listing.yacht_lines, '[]'::jsonb)) < 1 THEN
      RETURN false;
    END IF;
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_listing.yacht_lines) AS t(value)
    LOOP
      IF nullif(btrim(coalesce(v_item ->> 'text_es', '')), '') IS NULL
         OR nullif(btrim(coalesce(v_item ->> 'text_en', '')), '') IS NULL
         OR coalesce(v_item ->> 'kind', '') NOT IN ('capacity', 'feature')
      THEN
        RETURN false;
      END IF;
      IF v_item ->> 'kind' = 'capacity' THEN
        v_has_capacity := true;
      ELSIF v_item ->> 'kind' = 'feature' THEN
        v_has_feature := true;
      END IF;
    END LOOP;
    IF NOT (v_has_capacity AND v_has_feature) THEN
      RETURN false;
    END IF;
    IF p_listing.display_price IS NOT NULL AND p_listing.currency IS NULL THEN
      RETURN false;
    END IF;
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.listing_is_complete_for_publish(public.public_listings) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.listing_is_complete_for_publish(public.public_listings) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.placement_matches_product_type(
  p_placement public.public_placement,
  p_type public.product_type
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE p_placement
    WHEN 'catalog'::public.public_placement THEN p_type IN ('experience'::public.product_type, 'package'::public.product_type)
    WHEN 'lodging'::public.public_placement THEN p_type = 'accommodation'::public.product_type
    WHEN 'yacht'::public.public_placement THEN p_type = 'experience'::public.product_type
    ELSE false
  END;
$$;

REVOKE ALL ON FUNCTION public.placement_matches_product_type(public.public_placement, public.product_type) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.placement_matches_product_type(public.public_placement, public.product_type) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- save_public_listing
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_public_listing(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_product_id uuid;
  v_placement public.public_placement;
  v_public_slug text;
  v_product public.products;
  v_existing public.public_listings;
  v_includes jsonb;
  v_warnings jsonb;
  v_lodging jsonb;
  v_yacht_lines jsonb;
  v_display_price numeric;
  v_original_price numeric;
  v_currency text;
  v_rating numeric;
  v_max_guests integer;
  v_status public.public_listing_status;
  v_id uuid;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  IF p_payload IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_product_id := nullif(p_payload ->> 'product_id', '')::uuid;
  IF v_product_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT * INTO v_product
  FROM public.products p
  WHERE p.id = v_product_id;

  IF v_product.id IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_product.organization_id IS DISTINCT FROM v_organization_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  BEGIN
    v_placement := (p_payload ->> 'placement')::public.public_placement;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  IF NOT public.placement_matches_product_type(v_placement, v_product.type) THEN
    RAISE EXCEPTION 'PLACEMENT_PRODUCT_MISMATCH' USING ERRCODE = 'raise_exception';
  END IF;

  v_public_slug := lower(btrim(coalesce(p_payload ->> 'public_slug', '')));
  IF v_public_slug = '' OR v_public_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT * INTO v_existing
  FROM public.public_listings pl
  WHERE pl.product_id = v_product_id
    AND pl.organization_id = v_organization_id;

  IF v_existing.id IS NOT NULL AND v_existing.first_published_at IS NOT NULL THEN
    IF v_public_slug IS DISTINCT FROM v_existing.public_slug THEN
      RAISE EXCEPTION 'PUBLIC_SLUG_IMMUTABLE' USING ERRCODE = 'raise_exception';
    END IF;
    IF v_placement IS DISTINCT FROM v_existing.placement THEN
      RAISE EXCEPTION 'PUBLIC_SLUG_IMMUTABLE' USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.public_listings pl
    WHERE pl.organization_id = v_organization_id
      AND pl.public_slug = v_public_slug
      AND (v_existing.id IS NULL OR pl.id IS DISTINCT FROM v_existing.id)
  ) THEN
    RAISE EXCEPTION 'PUBLIC_SLUG_TAKEN' USING ERRCODE = 'raise_exception';
  END IF;

  v_includes := coalesce(p_payload -> 'includes', '[]'::jsonb);
  v_warnings := coalesce(p_payload -> 'warnings', '[]'::jsonb);
  v_yacht_lines := coalesce(p_payload -> 'yacht_lines', '[]'::jsonb);
  v_lodging := p_payload -> 'lodging';
  IF v_lodging = 'null'::jsonb THEN
    v_lodging := NULL;
  END IF;

  PERFORM public.validate_bilingual_pairs(v_warnings);
  IF jsonb_array_length(v_includes) > 0 THEN
    PERFORM public.validate_bilingual_pairs(v_includes);
  END IF;

  IF v_placement = 'yacht'::public.public_placement THEN
    PERFORM public.validate_bilingual_pairs(
      COALESCE(
        (
          SELECT jsonb_agg(jsonb_build_object('es', e ->> 'text_es', 'en', e ->> 'text_en'))
          FROM jsonb_array_elements(v_yacht_lines) AS e
        ),
        '[]'::jsonb
      )
    );
  END IF;

  IF v_placement = 'lodging'::public.public_placement THEN
    IF v_lodging IS NULL OR jsonb_typeof(v_lodging) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF nullif(btrim(coalesce(v_lodging ->> 'location_es', '')), '') IS NULL
       OR nullif(btrim(coalesce(v_lodging ->> 'location_en', '')), '') IS NULL
       OR nullif(btrim(coalesce(v_lodging ->> 'neighborhood_es', '')), '') IS NULL
       OR nullif(btrim(coalesce(v_lodging ->> 'neighborhood_en', '')), '') IS NULL
    THEN
      RAISE EXCEPTION 'BILINGUAL_PAIR_INCOMPLETE' USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  v_display_price := nullif(p_payload ->> 'display_price', '')::numeric;
  v_original_price := nullif(p_payload ->> 'original_price', '')::numeric;
  v_currency := nullif(upper(btrim(coalesce(p_payload ->> 'currency', ''))), '');
  v_rating := nullif(p_payload ->> 'rating', '')::numeric;
  v_max_guests := nullif(p_payload ->> 'max_guests', '')::integer;

  IF v_original_price IS NOT NULL
     AND (v_display_price IS NULL OR v_original_price <= v_display_price)
  THEN
    RAISE EXCEPTION 'ORIGINAL_PRICE_NOT_HIGHER' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_display_price IS NOT NULL AND v_currency IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_placement = 'catalog'::public.public_placement
     AND nullif(btrim(coalesce(p_payload ->> 'public_category_id', '')), '') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.public_categories pc
       WHERE pc.organization_id = v_organization_id
         AND pc.id = btrim(p_payload ->> 'public_category_id')
         AND pc.is_active
     )
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Draft by default; keep published only when already published and still complete.
  v_status := coalesce(v_existing.status, 'draft'::public.public_listing_status);
  IF v_status = 'published'::public.public_listing_status THEN
    -- Tentatively build row for completeness check after upsert fields.
    NULL; -- decided after INSERT/UPDATE payload applied via RETURNING
  ELSIF v_status IS DISTINCT FROM 'unpublished'::public.public_listing_status THEN
    v_status := 'draft'::public.public_listing_status;
  END IF;

  IF v_existing.id IS NULL THEN
    INSERT INTO public.public_listings (
      organization_id,
      product_id,
      placement,
      public_slug,
      status,
      name_es,
      name_en,
      description_es,
      description_en,
      public_category_id,
      location,
      meeting_point,
      schedule,
      duration,
      max_guests,
      featured,
      rating,
      display_price,
      original_price,
      currency,
      includes,
      warnings,
      lodging,
      yacht_lines,
      updated_at
    )
    VALUES (
      v_organization_id,
      v_product_id,
      v_placement,
      v_public_slug,
      'draft'::public.public_listing_status,
      nullif(btrim(coalesce(p_payload ->> 'name_es', '')), ''),
      nullif(btrim(coalesce(p_payload ->> 'name_en', '')), ''),
      nullif(btrim(coalesce(p_payload ->> 'description_es', '')), ''),
      nullif(btrim(coalesce(p_payload ->> 'description_en', '')), ''),
      CASE
        WHEN v_placement = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'public_category_id', '')), '')
        ELSE NULL
      END,
      CASE
        WHEN v_placement = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'location', '')), '')
        ELSE NULL
      END,
      CASE
        WHEN v_placement = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'meeting_point', '')), '')
        ELSE NULL
      END,
      CASE
        WHEN v_placement = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'schedule', '')), '')
        ELSE NULL
      END,
      CASE
        WHEN v_placement = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'duration', '')), '')
        ELSE NULL
      END,
      v_max_guests,
      coalesce((p_payload ->> 'featured')::boolean, false),
      v_rating,
      v_display_price,
      v_original_price,
      v_currency,
      v_includes,
      v_warnings,
      CASE WHEN v_placement = 'lodging'::public.public_placement THEN v_lodging ELSE NULL END,
      CASE WHEN v_placement = 'yacht'::public.public_placement THEN v_yacht_lines ELSE '[]'::jsonb END,
      now()
    )
    RETURNING id, status INTO v_id, v_status;
  ELSE
    UPDATE public.public_listings pl
    SET
      placement = CASE
        WHEN pl.first_published_at IS NULL THEN v_placement
        ELSE pl.placement
      END,
      public_slug = CASE
        WHEN pl.first_published_at IS NULL THEN v_public_slug
        ELSE pl.public_slug
      END,
      name_es = nullif(btrim(coalesce(p_payload ->> 'name_es', '')), ''),
      name_en = nullif(btrim(coalesce(p_payload ->> 'name_en', '')), ''),
      description_es = nullif(btrim(coalesce(p_payload ->> 'description_es', '')), ''),
      description_en = nullif(btrim(coalesce(p_payload ->> 'description_en', '')), ''),
      public_category_id = CASE
        WHEN coalesce(
          CASE WHEN pl.first_published_at IS NULL THEN v_placement ELSE pl.placement END,
          v_placement
        ) = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'public_category_id', '')), '')
        ELSE NULL
      END,
      location = CASE
        WHEN coalesce(
          CASE WHEN pl.first_published_at IS NULL THEN v_placement ELSE pl.placement END,
          v_placement
        ) = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'location', '')), '')
        ELSE NULL
      END,
      meeting_point = CASE
        WHEN coalesce(
          CASE WHEN pl.first_published_at IS NULL THEN v_placement ELSE pl.placement END,
          v_placement
        ) = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'meeting_point', '')), '')
        ELSE NULL
      END,
      schedule = CASE
        WHEN coalesce(
          CASE WHEN pl.first_published_at IS NULL THEN v_placement ELSE pl.placement END,
          v_placement
        ) = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'schedule', '')), '')
        ELSE NULL
      END,
      duration = CASE
        WHEN coalesce(
          CASE WHEN pl.first_published_at IS NULL THEN v_placement ELSE pl.placement END,
          v_placement
        ) = 'catalog'::public.public_placement
          THEN nullif(btrim(coalesce(p_payload ->> 'duration', '')), '')
        ELSE NULL
      END,
      max_guests = v_max_guests,
      featured = coalesce((p_payload ->> 'featured')::boolean, false),
      rating = v_rating,
      display_price = v_display_price,
      original_price = v_original_price,
      currency = v_currency,
      includes = v_includes,
      warnings = v_warnings,
      lodging = CASE
        WHEN coalesce(
          CASE WHEN pl.first_published_at IS NULL THEN v_placement ELSE pl.placement END,
          v_placement
        ) = 'lodging'::public.public_placement
          THEN v_lodging
        ELSE NULL
      END,
      yacht_lines = CASE
        WHEN coalesce(
          CASE WHEN pl.first_published_at IS NULL THEN v_placement ELSE pl.placement END,
          v_placement
        ) = 'yacht'::public.public_placement
          THEN v_yacht_lines
        ELSE '[]'::jsonb
      END,
      updated_at = now()
    WHERE pl.id = v_existing.id
    RETURNING id INTO v_id;

    SELECT * INTO v_existing FROM public.public_listings WHERE id = v_id;

    IF v_existing.status = 'published'::public.public_listing_status
       AND NOT public.listing_is_complete_for_publish(v_existing)
    THEN
      UPDATE public.public_listings
      SET status = 'draft'::public.public_listing_status, updated_at = now()
      WHERE id = v_id;
      v_status := 'draft'::public.public_listing_status;
    ELSE
      v_status := v_existing.status;
    END IF;
  END IF;

  UPDATE public.public_cutover_items ci
  SET listing_id = v_id
  WHERE ci.organization_id = v_organization_id
    AND ci.public_slug = v_public_slug;

  SELECT status INTO v_status FROM public.public_listings WHERE id = v_id;

  RETURN jsonb_build_object('id', v_id, 'status', v_status);
END;
$$;

COMMENT ON FUNCTION public.save_public_listing(jsonb) IS
  'Operator/admin: create or update a public listing draft (keeps published when still valid).';

REVOKE EXECUTE ON FUNCTION public.save_public_listing(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_public_listing(jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- publish_public_listing
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.publish_public_listing(p_listing_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_listing public.public_listings;
  v_product public.products;
  v_first_published_at timestamptz;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  IF p_listing_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT * INTO v_listing
  FROM public.public_listings pl
  WHERE pl.id = p_listing_id;

  IF v_listing.id IS NULL OR v_listing.organization_id IS DISTINCT FROM v_organization_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_product
  FROM public.products p
  WHERE p.id = v_listing.product_id
    AND p.organization_id = v_organization_id;

  IF v_product.id IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_product.status IS DISTINCT FROM 'active'::public.product_status THEN
    RAISE EXCEPTION 'PRODUCT_NOT_ACTIVE' USING ERRCODE = 'raise_exception';
  END IF;

  IF NOT public.product_has_valid_price(v_product.id, v_organization_id) THEN
    RAISE EXCEPTION 'PRODUCT_HAS_NO_VALID_PRICE' USING ERRCODE = 'raise_exception';
  END IF;

  IF NOT public.listing_is_complete_for_publish(v_listing) THEN
    RAISE EXCEPTION 'PUBLIC_LISTING_INCOMPLETE' USING ERRCODE = 'raise_exception';
  END IF;

  v_first_published_at := coalesce(v_listing.first_published_at, now());

  UPDATE public.public_listings
  SET
    status = 'published'::public.public_listing_status,
    first_published_at = v_first_published_at,
    published_at = now(),
    sold_out = CASE
      WHEN status = 'published'::public.public_listing_status THEN sold_out
      ELSE false
    END,
    updated_at = now()
  WHERE id = v_listing.id;

  PERFORM audit.log_event(
    v_organization_id,
    'public_listing_published'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_listing',
    v_listing.id,
    jsonb_build_object('public_slug', v_listing.public_slug, 'placement', v_listing.placement)
  );

  RETURN jsonb_build_object(
    'status', 'published',
    'first_published_at', v_first_published_at
  );
END;
$$;

COMMENT ON FUNCTION public.publish_public_listing(uuid) IS
  'Operator/admin: publish a complete listing whose product is active with a valid tariff.';

REVOKE EXECUTE ON FUNCTION public.publish_public_listing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_public_listing(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- unpublish_public_listing
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.unpublish_public_listing(p_listing_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_listing public.public_listings;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  SELECT * INTO v_listing
  FROM public.public_listings pl
  WHERE pl.id = p_listing_id;

  IF v_listing.id IS NULL OR v_listing.organization_id IS DISTINCT FROM v_organization_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.public_listings
  SET
    status = 'unpublished'::public.public_listing_status,
    sold_out = false,
    updated_at = now()
  WHERE id = v_listing.id;

  PERFORM audit.log_event(
    v_organization_id,
    'public_listing_unpublished'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_listing',
    v_listing.id,
    jsonb_build_object('public_slug', v_listing.public_slug)
  );

  RETURN jsonb_build_object('status', 'unpublished');
END;
$$;

COMMENT ON FUNCTION public.unpublish_public_listing(uuid) IS
  'Operator/admin: unpublish a listing without touching product or tariff.';

REVOKE EXECUTE ON FUNCTION public.unpublish_public_listing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unpublish_public_listing(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_public_listing_sold_out
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_public_listing_sold_out(
  p_listing_id uuid,
  p_sold_out boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_listing public.public_listings;
  v_previous boolean;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  IF p_sold_out IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT * INTO v_listing
  FROM public.public_listings pl
  WHERE pl.id = p_listing_id;

  IF v_listing.id IS NULL OR v_listing.organization_id IS DISTINCT FROM v_organization_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_listing.status IS DISTINCT FROM 'published'::public.public_listing_status THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_previous := v_listing.sold_out;

  UPDATE public.public_listings
  SET sold_out = p_sold_out, updated_at = now()
  WHERE id = v_listing.id;

  PERFORM audit.log_event(
    v_organization_id,
    'public_listing_sold_out_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_listing',
    v_listing.id,
    jsonb_build_object('from', v_previous, 'to', p_sold_out)
  );

  RETURN jsonb_build_object('sold_out', p_sold_out);
END;
$$;

COMMENT ON FUNCTION public.set_public_listing_sold_out(uuid, boolean) IS
  'Operator/admin: toggle sold_out on a published listing without changing product status.';

REVOKE EXECUTE ON FUNCTION public.set_public_listing_sold_out(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_public_listing_sold_out(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- attach_public_image
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.attach_public_image(
  p_listing_id uuid,
  p_role text,
  p_storage_path text DEFAULT NULL,
  p_external_ref text DEFAULT NULL,
  p_sort_order integer DEFAULT 0,
  p_byte_size bigint DEFAULT NULL,
  p_content_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_listing public.public_listings;
  v_role public.public_image_role;
  v_storage_path text;
  v_external_ref text;
  v_image_id uuid;
  v_prev_cover public.public_images;
  v_ref text;
  v_byte_size bigint;
  v_content_type text;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  SELECT * INTO v_listing
  FROM public.public_listings pl
  WHERE pl.id = p_listing_id;

  IF v_listing.id IS NULL OR v_listing.organization_id IS DISTINCT FROM v_organization_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  BEGIN
    v_role := p_role::public.public_image_role;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  IF v_role = 'gallery'::public.public_image_role
     AND v_listing.placement IS DISTINCT FROM 'lodging'::public.public_placement
  THEN
    RAISE EXCEPTION 'GALLERY_ONLY_FOR_LODGING' USING ERRCODE = 'raise_exception';
  END IF;

  v_storage_path := nullif(btrim(coalesce(p_storage_path, '')), '');
  v_external_ref := nullif(btrim(coalesce(p_external_ref, '')), '');

  IF (v_storage_path IS NULL) = (v_external_ref IS NULL) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_byte_size := p_byte_size;
  v_content_type := lower(nullif(btrim(coalesce(p_content_type, '')), ''));

  IF v_storage_path IS NOT NULL AND to_regclass('storage.objects') IS NOT NULL THEN
    IF v_byte_size IS NULL THEN
      BEGIN
        EXECUTE $q$
          SELECT COALESCE((metadata ->> 'size')::bigint, (metadata ->> 'contentLength')::bigint)
          FROM storage.objects
          WHERE bucket_id = 'catalog-media' AND name = $1
          LIMIT 1
        $q$
        INTO v_byte_size
        USING v_storage_path;
      EXCEPTION
        WHEN undefined_table OR undefined_column THEN
          NULL;
      END;
    END IF;
    IF v_content_type IS NULL THEN
      BEGIN
        EXECUTE $q$
          SELECT lower(COALESCE(metadata ->> 'mimetype', metadata ->> 'contentType'))
          FROM storage.objects
          WHERE bucket_id = 'catalog-media' AND name = $1
          LIMIT 1
        $q$
        INTO v_content_type
        USING v_storage_path;
      EXCEPTION
        WHEN undefined_table OR undefined_column THEN
          NULL;
      END;
    END IF;
  END IF;

  IF v_byte_size IS NOT NULL AND v_byte_size > (10 * 1024 * 1024) THEN
    RAISE EXCEPTION 'IMAGE_TOO_LARGE' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_content_type IS NOT NULL
     AND v_content_type NOT IN ('image/jpeg', 'image/png', 'image/webp', 'image/jpg')
  THEN
    RAISE EXCEPTION 'IMAGE_TYPE_NOT_ALLOWED' USING ERRCODE = 'raise_exception';
  END IF;

  v_ref := coalesce(v_external_ref, v_storage_path);

  IF v_role = 'cover'::public.public_image_role THEN
    SELECT * INTO v_prev_cover
    FROM public.public_images pi
    WHERE pi.listing_id = v_listing.id
      AND pi.role = 'cover'::public.public_image_role
      AND pi.replaced_at IS NULL
    LIMIT 1;

    IF v_prev_cover.id IS NOT NULL THEN
      UPDATE public.public_images
      SET replaced_at = now()
      WHERE id = v_prev_cover.id;

      PERFORM audit.log_event(
        v_organization_id,
        'public_image_replaced'::audit.audit_event_type,
        'success'::audit.audit_result,
        auth.uid(),
        'public_image',
        v_prev_cover.id,
        jsonb_build_object(
          'listing_id', v_listing.id,
          'previous_ref', coalesce(v_prev_cover.external_ref, v_prev_cover.storage_path),
          'new_ref', v_ref
        )
      );
    END IF;
  END IF;

  INSERT INTO public.public_images (
    organization_id,
    listing_id,
    role,
    sort_order,
    storage_path,
    external_ref
  )
  VALUES (
    v_organization_id,
    v_listing.id,
    v_role,
    coalesce(p_sort_order, 0),
    v_storage_path,
    v_external_ref
  )
  RETURNING id INTO v_image_id;

  IF v_role = 'cover'::public.public_image_role THEN
    UPDATE public.public_listings
    SET cover_image_ref = v_ref, updated_at = now()
    WHERE id = v_listing.id;
  END IF;

  RETURN jsonb_build_object('id', v_image_id, 'role', v_role, 'ref', v_ref);
END;
$$;

COMMENT ON FUNCTION public.attach_public_image(uuid, text, text, text, integer, bigint, text) IS
  'Operator/admin: attach cover or gallery image; replacing cover keeps prior row and audits.';

REVOKE EXECUTE ON FUNCTION public.attach_public_image(uuid, text, text, text, integer, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_public_image(uuid, text, text, text, integer, bigint, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- reorder_public_gallery
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reorder_public_gallery(
  p_listing_id uuid,
  p_image_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_listing public.public_listings;
  v_cover_id uuid;
  v_i integer;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  SELECT * INTO v_listing
  FROM public.public_listings pl
  WHERE pl.id = p_listing_id;

  IF v_listing.id IS NULL OR v_listing.organization_id IS DISTINCT FROM v_organization_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_listing.placement IS DISTINCT FROM 'lodging'::public.public_placement THEN
    RAISE EXCEPTION 'GALLERY_ONLY_FOR_LODGING' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_image_ids IS NULL OR cardinality(p_image_ids) = 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT pi.id INTO v_cover_id
  FROM public.public_images pi
  WHERE pi.listing_id = v_listing.id
    AND pi.role = 'cover'::public.public_image_role
    AND pi.replaced_at IS NULL
  LIMIT 1;

  IF v_cover_id IS NULL OR NOT (v_cover_id = ANY (p_image_ids)) THEN
    RAISE EXCEPTION 'COVER_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(p_image_ids) AS x(id)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.public_images pi
      WHERE pi.id = x.id
        AND pi.listing_id = v_listing.id
        AND pi.replaced_at IS NULL
    )
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  FOR v_i IN 1 .. cardinality(p_image_ids) LOOP
    UPDATE public.public_images
    SET sort_order = v_i - 1
    WHERE id = p_image_ids[v_i];
  END LOOP;

  UPDATE public.public_listings SET updated_at = now() WHERE id = v_listing.id;

  RETURN jsonb_build_object('image_ids', to_jsonb(p_image_ids));
END;
$$;

COMMENT ON FUNCTION public.reorder_public_gallery(uuid, uuid[]) IS
  'Operator/admin: reorder lodging gallery; active cover must remain included.';

REVOKE EXECUTE ON FUNCTION public.reorder_public_gallery(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reorder_public_gallery(uuid, uuid[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- save_guest_review
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_guest_review(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_listing public.public_listings;
  v_review_id uuid;
  v_author text;
  v_rating integer;
  v_text_es text;
  v_text_en text;
  v_reviewed_on date;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  v_review_id := nullif(p_payload ->> 'review_id', '')::uuid;

  SELECT * INTO v_listing
  FROM public.public_listings pl
  WHERE pl.id = nullif(p_payload ->> 'listing_id', '')::uuid;

  IF v_listing.id IS NULL OR v_listing.organization_id IS DISTINCT FROM v_organization_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_listing.placement IS DISTINCT FROM 'lodging'::public.public_placement THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_author := btrim(coalesce(p_payload ->> 'author', ''));
  v_text_es := btrim(coalesce(p_payload ->> 'text_es', ''));
  v_text_en := btrim(coalesce(p_payload ->> 'text_en', ''));
  v_rating := nullif(p_payload ->> 'rating', '')::integer;
  v_reviewed_on := nullif(p_payload ->> 'reviewed_on', '')::date;

  IF v_author = '' OR v_text_es = '' OR v_text_en = ''
     OR v_rating IS NULL OR v_rating < 1 OR v_rating > 5
     OR v_reviewed_on IS NULL
  THEN
    IF v_text_es = '' OR v_text_en = '' THEN
      RAISE EXCEPTION 'BILINGUAL_PAIR_INCOMPLETE' USING ERRCODE = 'raise_exception';
    END IF;
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_review_id IS NULL THEN
    INSERT INTO public.guest_reviews (
      organization_id, listing_id, author, rating, text_es, text_en, reviewed_on
    )
    VALUES (
      v_organization_id, v_listing.id, v_author, v_rating, v_text_es, v_text_en, v_reviewed_on
    )
    RETURNING id INTO v_review_id;
  ELSE
    UPDATE public.guest_reviews gr
    SET
      author = v_author,
      rating = v_rating,
      text_es = v_text_es,
      text_en = v_text_en,
      reviewed_on = v_reviewed_on
    WHERE gr.id = v_review_id
      AND gr.listing_id = v_listing.id
      AND gr.organization_id = v_organization_id
    RETURNING id INTO v_review_id;

    IF v_review_id IS NULL THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  UPDATE public.public_listings SET updated_at = now() WHERE id = v_listing.id;

  RETURN jsonb_build_object('id', v_review_id);
END;
$$;

COMMENT ON FUNCTION public.save_guest_review(jsonb) IS
  'Operator/admin: create or update a guest review on a lodging listing.';

REVOKE EXECUTE ON FUNCTION public.save_guest_review(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_guest_review(jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- save_public_category
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_public_category(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_id text;
  v_name_es text;
  v_name_en text;
  v_is_active boolean;
  v_existing public.public_categories;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  v_id := lower(btrim(coalesce(p_payload ->> 'id', '')));
  v_name_es := btrim(coalesce(p_payload ->> 'name_es', ''));
  v_name_en := btrim(coalesce(p_payload ->> 'name_en', ''));
  v_is_active := coalesce((p_payload ->> 'is_active')::boolean, true);

  IF v_id = '' OR v_id !~ '^[a-z0-9]+(_[a-z0-9]+)*$'
     OR v_name_es = '' OR v_name_en = ''
  THEN
    IF v_name_es = '' OR v_name_en = '' THEN
      RAISE EXCEPTION 'BILINGUAL_PAIR_INCOMPLETE' USING ERRCODE = 'raise_exception';
    END IF;
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT * INTO v_existing
  FROM public.public_categories pc
  WHERE pc.organization_id = v_organization_id
    AND pc.id = v_id;

  IF NOT v_is_active AND EXISTS (
    SELECT 1
    FROM public.public_listings pl
    WHERE pl.organization_id = v_organization_id
      AND pl.public_category_id = v_id
      AND pl.status = 'published'::public.public_listing_status
  ) THEN
    RAISE EXCEPTION 'CATEGORY_IN_USE' USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.public_categories (
    id, organization_id, name_es, name_en, is_active, protected
  )
  VALUES (
    v_id,
    v_organization_id,
    v_name_es,
    v_name_en,
    v_is_active,
    coalesce(v_existing.protected, false)
  )
  ON CONFLICT (organization_id, id) DO UPDATE
  SET
    name_es = EXCLUDED.name_es,
    name_en = EXCLUDED.name_en,
    is_active = EXCLUDED.is_active,
    protected = public.public_categories.protected,
    updated_at = now();

  RETURN jsonb_build_object(
    'id', v_id,
    'name_es', v_name_es,
    'name_en', v_name_en,
    'is_active', v_is_active
  );
END;
$$;

COMMENT ON FUNCTION public.save_public_category(jsonb) IS
  'Operator/admin: upsert a public category; deactivating one in use by published listings fails.';

REVOKE EXECUTE ON FUNCTION public.save_public_category(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_public_category(jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- complete_public_cutover (admin only)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.complete_public_cutover()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_site public.public_sites;
  v_missing text[];
  v_completed_at timestamptz;
BEGIN
  BEGIN
    v_organization_id := public.require_tenant_admin();
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM = 'SESSION_EXPIRED' THEN
        RAISE;
      END IF;
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'insufficient_privilege';
  END;

  SELECT * INTO v_site
  FROM public.public_sites ps
  WHERE ps.organization_id = v_organization_id;

  IF v_site.organization_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_site.source = 'panel'::public.public_source THEN
    RAISE EXCEPTION 'CUTOVER_ALREADY_COMPLETED' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT coalesce(array_agg(ci.public_slug ORDER BY ci.public_slug), '{}'::text[])
  INTO v_missing
  FROM public.public_cutover_items ci
  WHERE ci.organization_id = v_organization_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.public_listings pl
      JOIN public.products p
        ON p.id = pl.product_id
       AND p.organization_id = pl.organization_id
      WHERE pl.organization_id = ci.organization_id
        AND pl.public_slug = ci.public_slug
        AND pl.status = 'published'::public.public_listing_status
        AND p.status = 'active'::public.product_status
    );

  IF cardinality(v_missing) > 0 THEN
    RAISE EXCEPTION 'CUTOVER_INCOMPLETE'
      USING ERRCODE = 'raise_exception',
            DETAIL = array_to_json(v_missing)::text;
  END IF;

  v_completed_at := now();

  UPDATE public.public_sites
  SET
    source = 'panel'::public.public_source,
    cutover_completed_at = v_completed_at,
    cutover_completed_by = auth.uid(),
    updated_at = now()
  WHERE organization_id = v_organization_id;

  PERFORM audit.log_event(
    v_organization_id,
    'public_cutover_completed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_site',
    NULL,
    jsonb_build_object('source', 'panel')
  );

  RETURN jsonb_build_object(
    'source', 'panel',
    'cutover_completed_at', v_completed_at
  );
END;
$$;

COMMENT ON FUNCTION public.complete_public_cutover() IS
  'Admin: switch public site source to panel when every manifesto item is published and active.';

REVOKE EXECUTE ON FUNCTION public.complete_public_cutover() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_public_cutover() TO authenticated;
