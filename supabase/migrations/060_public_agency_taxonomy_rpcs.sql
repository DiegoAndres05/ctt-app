-- 060_public_agency_taxonomy_rpcs.sql
-- Agency-owned categories, lodging types and amenities (feature 016, US1).
-- Source of truth: specs/016-multiagency-public-cms/contracts/management.md
--
-- ERROR CONTRACT: the exception message is the API code.
--   FORBIDDEN, VALIDATION_ERROR, BILINGUAL_PAIR_INCOMPLETE, CATEGORY_PROTECTED, CATEGORY_IN_USE,
--   TAXONOMY_VALUE_IN_USE, TAXONOMY_VALUE_INVALID, TAXONOMY_VALUE_INACTIVE

-- ---------------------------------------------------------------------------
-- Categories: deactivating a used category is allowed (the listing keeps it until edited);
-- deleting is only possible for unprotected, unused categories.
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

  IF p_payload IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_id := lower(btrim(coalesce(p_payload ->> 'id', '')));
  v_name_es := btrim(coalesce(p_payload ->> 'name_es', ''));
  v_name_en := btrim(coalesce(p_payload ->> 'name_en', ''));
  v_is_active := coalesce((p_payload ->> 'is_active')::boolean, true);

  IF v_name_es = '' OR v_name_en = '' THEN
    RAISE EXCEPTION 'BILINGUAL_PAIR_INCOMPLETE' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_id = '' OR v_id !~ '^[a-z0-9]+(_[a-z0-9]+)*$' OR char_length(v_id) > 40 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT * INTO v_existing
  FROM public.public_categories pc
  WHERE pc.organization_id = v_organization_id
    AND pc.id = v_id;

  INSERT INTO public.public_categories (
    id, organization_id, name_es, name_en, is_active, protected
  )
  VALUES (v_id, v_organization_id, v_name_es, v_name_en, v_is_active, false)
  ON CONFLICT (organization_id, id) DO UPDATE
  SET
    name_es = EXCLUDED.name_es,
    name_en = EXCLUDED.name_en,
    is_active = EXCLUDED.is_active,
    protected = public.public_categories.protected,
    updated_at = now();

  PERFORM audit.log_event(
    v_organization_id,
    'public_taxonomy_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_category',
    NULL,
    jsonb_build_object(
      'kind', 'category',
      'code', v_id,
      'action', CASE WHEN v_existing.id IS NULL THEN 'created' ELSE 'updated' END,
      'is_active', v_is_active
    )
  );

  RETURN jsonb_build_object(
    'id', v_id,
    'name_es', v_name_es,
    'name_en', v_name_en,
    'is_active', v_is_active,
    'protected', coalesce(v_existing.protected, false)
  );
END;
$$;

COMMENT ON FUNCTION public.save_public_category(jsonb) IS
  'Operator/admin: upsert a public category of the caller''s agency. Deactivation keeps published listings untouched.';

REVOKE EXECUTE ON FUNCTION public.save_public_category(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_public_category(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_public_category(p_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_category public.public_categories;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  SELECT * INTO v_category
  FROM public.public_categories pc
  WHERE pc.organization_id = v_organization_id
    AND pc.id = lower(btrim(coalesce(p_id, '')));

  IF v_category.id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_category.protected THEN
    RAISE EXCEPTION 'CATEGORY_PROTECTED' USING ERRCODE = 'raise_exception';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.public_listings pl
    WHERE pl.organization_id = v_organization_id
      AND pl.public_category_id = v_category.id
  ) THEN
    RAISE EXCEPTION 'CATEGORY_IN_USE' USING ERRCODE = 'raise_exception';
  END IF;

  DELETE FROM public.public_categories
  WHERE organization_id = v_organization_id
    AND id = v_category.id;

  PERFORM audit.log_event(
    v_organization_id,
    'public_taxonomy_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_category',
    NULL,
    jsonb_build_object('kind', 'category', 'code', v_category.id, 'action', 'deleted')
  );

  RETURN jsonb_build_object('id', v_category.id, 'deleted', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_public_category(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_public_category(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Lodging types and amenities
-- ---------------------------------------------------------------------------

-- True when any listing of the agency (any status) references the value.
CREATE OR REPLACE FUNCTION public.public_taxonomy_value_in_use(
  p_organization_id uuid,
  p_kind text,
  p_code text
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.public_listings pl
    WHERE pl.organization_id = p_organization_id
      AND pl.lodging IS NOT NULL
      AND (
        (p_kind = 'lodging_type' AND pl.lodging ->> 'lodging_type' = p_code)
        OR (
          p_kind = 'amenity'
          AND jsonb_typeof(pl.lodging -> 'amenities') = 'array'
          AND (pl.lodging -> 'amenities') ? p_code
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION public.public_taxonomy_value_in_use(uuid, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.public_taxonomy_value_in_use(uuid, text, text) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.list_public_taxonomy_values()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid := nullif(auth.jwt() ->> 'organization_id', '')::uuid;
BEGIN
  IF auth.uid() IS NULL OR v_organization_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', tv.id,
      'kind', tv.kind,
      'code', tv.code,
      'name_es', tv.name_es,
      'name_en', tv.name_en,
      'is_active', tv.is_active,
      'sort_order', tv.sort_order,
      'in_use', public.public_taxonomy_value_in_use(tv.organization_id, tv.kind, tv.code)
    ) ORDER BY tv.kind, tv.sort_order, tv.code)
    FROM public.public_taxonomy_values tv
    WHERE tv.organization_id = v_organization_id
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_public_taxonomy_values() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_public_taxonomy_values() TO authenticated;

CREATE OR REPLACE FUNCTION public.save_public_taxonomy_value(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_kind text;
  v_code text;
  v_name_es text;
  v_name_en text;
  v_is_active boolean;
  v_sort integer;
  v_existing public.public_taxonomy_values;
  v_row public.public_taxonomy_values;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  IF p_payload IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_kind := btrim(coalesce(p_payload ->> 'kind', ''));
  v_code := lower(btrim(coalesce(p_payload ->> 'code', '')));
  v_name_es := btrim(coalesce(p_payload ->> 'name_es', ''));
  v_name_en := btrim(coalesce(p_payload ->> 'name_en', ''));
  v_is_active := coalesce((p_payload ->> 'is_active')::boolean, true);

  IF v_kind NOT IN ('lodging_type', 'amenity') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_name_es = '' OR v_name_en = '' THEN
    RAISE EXCEPTION 'BILINGUAL_PAIR_INCOMPLETE' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_code = '' OR v_code !~ '^[a-z0-9]+(_[a-z0-9]+)*$' OR char_length(v_code) > 40 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT * INTO v_existing
  FROM public.public_taxonomy_values tv
  WHERE tv.organization_id = v_organization_id
    AND tv.kind = v_kind
    AND tv.code = v_code;

  v_sort := coalesce(
    nullif(p_payload ->> 'sort_order', '')::integer,
    v_existing.sort_order,
    (SELECT coalesce(max(tv.sort_order), 0) + 1
     FROM public.public_taxonomy_values tv
     WHERE tv.organization_id = v_organization_id AND tv.kind = v_kind)
  );

  INSERT INTO public.public_taxonomy_values (
    organization_id, kind, code, name_es, name_en, is_active, sort_order
  )
  VALUES (v_organization_id, v_kind, v_code, v_name_es, v_name_en, v_is_active, v_sort)
  ON CONFLICT (organization_id, kind, code) DO UPDATE
  SET
    name_es = EXCLUDED.name_es,
    name_en = EXCLUDED.name_en,
    is_active = EXCLUDED.is_active,
    sort_order = EXCLUDED.sort_order,
    updated_at = now()
  RETURNING * INTO v_row;

  PERFORM audit.log_event(
    v_organization_id,
    'public_taxonomy_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_taxonomy_value',
    v_row.id,
    jsonb_build_object(
      'kind', v_kind,
      'code', v_code,
      'action', CASE WHEN v_existing.id IS NULL THEN 'created' ELSE 'updated' END,
      'is_active', v_is_active
    )
  );

  RETURN jsonb_build_object(
    'id', v_row.id,
    'kind', v_row.kind,
    'code', v_row.code,
    'name_es', v_row.name_es,
    'name_en', v_row.name_en,
    'is_active', v_row.is_active,
    'sort_order', v_row.sort_order,
    'in_use', public.public_taxonomy_value_in_use(v_organization_id, v_kind, v_code)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_public_taxonomy_value(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_public_taxonomy_value(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_public_taxonomy_value(p_kind text, p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_row public.public_taxonomy_values;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  SELECT * INTO v_row
  FROM public.public_taxonomy_values tv
  WHERE tv.organization_id = v_organization_id
    AND tv.kind = p_kind
    AND tv.code = lower(btrim(coalesce(p_code, '')));

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- FR-008: a used value is never deleted; it can only be deactivated.
  IF public.public_taxonomy_value_in_use(v_organization_id, v_row.kind, v_row.code) THEN
    RAISE EXCEPTION 'TAXONOMY_VALUE_IN_USE' USING ERRCODE = 'raise_exception';
  END IF;

  DELETE FROM public.public_taxonomy_values WHERE id = v_row.id;

  PERFORM audit.log_event(
    v_organization_id,
    'public_taxonomy_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_taxonomy_value',
    v_row.id,
    jsonb_build_object('kind', v_row.kind, 'code', v_row.code, 'action', 'deleted')
  );

  RETURN jsonb_build_object('kind', v_row.kind, 'code', v_row.code, 'deleted', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_public_taxonomy_value(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_public_taxonomy_value(text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Listing guard: lodging values must be the agency's own; a value can only be newly
-- assigned while active. Values already on the listing are kept even if deactivated later.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_public_listing_taxonomy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_type text;
  v_old_type text;
  v_code text;
  v_old_amenities jsonb := '[]'::jsonb;
  v_value public.public_taxonomy_values;
BEGIN
  IF NEW.lodging IS NULL OR jsonb_typeof(NEW.lodging) IS DISTINCT FROM 'object' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.lodging IS NOT NULL AND jsonb_typeof(OLD.lodging) = 'object' THEN
    v_old_type := OLD.lodging ->> 'lodging_type';
    IF jsonb_typeof(OLD.lodging -> 'amenities') = 'array' THEN
      v_old_amenities := OLD.lodging -> 'amenities';
    END IF;
  END IF;

  v_type := nullif(btrim(coalesce(NEW.lodging ->> 'lodging_type', '')), '');
  IF v_type IS NOT NULL THEN
    SELECT * INTO v_value
    FROM public.public_taxonomy_values tv
    WHERE tv.organization_id = NEW.organization_id
      AND tv.kind = 'lodging_type'
      AND tv.code = v_type;

    IF v_value.id IS NULL THEN
      RAISE EXCEPTION 'TAXONOMY_VALUE_INVALID' USING ERRCODE = 'raise_exception';
    END IF;
    IF NOT v_value.is_active AND v_type IS DISTINCT FROM v_old_type THEN
      RAISE EXCEPTION 'TAXONOMY_VALUE_INACTIVE' USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  IF NEW.lodging ? 'amenities' THEN
    IF jsonb_typeof(NEW.lodging -> 'amenities') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    FOR v_code IN SELECT jsonb_array_elements_text(NEW.lodging -> 'amenities')
    LOOP
      v_value := NULL;
      SELECT * INTO v_value
      FROM public.public_taxonomy_values tv
      WHERE tv.organization_id = NEW.organization_id
        AND tv.kind = 'amenity'
        AND tv.code = v_code;

      IF v_value.id IS NULL THEN
        RAISE EXCEPTION 'TAXONOMY_VALUE_INVALID' USING ERRCODE = 'raise_exception';
      END IF;
      IF NOT v_value.is_active AND NOT (v_old_amenities ? v_code) THEN
        RAISE EXCEPTION 'TAXONOMY_VALUE_INACTIVE' USING ERRCODE = 'raise_exception';
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER public_listings_validate_taxonomy
  BEFORE INSERT OR UPDATE OF lodging ON public.public_listings
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_public_listing_taxonomy();

-- ---------------------------------------------------------------------------
-- Publish completeness: the lodging type comes from the agency taxonomy instead of a fixed list.
-- ---------------------------------------------------------------------------

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
    IF NOT EXISTS (
         SELECT 1
         FROM public.public_taxonomy_values tv
         WHERE tv.organization_id = p_listing.organization_id
           AND tv.kind = 'lodging_type'
           AND tv.code = coalesce(v_lodging ->> 'lodging_type', '')
       )
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
