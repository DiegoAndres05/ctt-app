-- 062_public_profile.sql
-- Agency public profile (feature 016, US3) and the key-based public read (US2).
-- Source of truth: specs/016-multiagency-public-cms/contracts/
--
-- ERROR CONTRACT: the exception message is the API code; DETAIL names the offending field.
--   FORBIDDEN, VALIDATION_ERROR, PUBLIC_ACCESS_UNAVAILABLE

CREATE OR REPLACE FUNCTION public.public_profile_social_networks()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT ARRAY['instagram', 'facebook', 'tiktok', 'youtube', 'x', 'linkedin', 'tripadvisor'];
$$;

GRANT EXECUTE ON FUNCTION public.public_profile_social_networks() TO authenticated;

CREATE OR REPLACE FUNCTION public.public_profile_to_json(p_profile public.public_profiles)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'commercial_name', p_profile.commercial_name,
    'logo_ref', p_profile.logo_ref,
    'primary_color', p_profile.primary_color,
    'contact_email', p_profile.contact_email,
    'contact_phone', p_profile.contact_phone,
    'whatsapp', p_profile.whatsapp,
    'social_links', p_profile.social_links,
    'languages', to_jsonb(p_profile.languages),
    'currency', p_profile.currency,
    'updated_at', p_profile.updated_at,
    'updated_by_name', (
      SELECT up.full_name FROM public.user_profiles up WHERE up.id = p_profile.updated_by
    )
  );
$$;

REVOKE ALL ON FUNCTION public.public_profile_to_json(public.public_profiles) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.public_profile_to_json(public.public_profiles) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_profile()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid := nullif(auth.jwt() ->> 'organization_id', '')::uuid;
  v_profile public.public_profiles;
BEGIN
  IF auth.uid() IS NULL OR v_organization_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.ensure_public_agency_config(v_organization_id);

  SELECT * INTO v_profile
  FROM public.public_profiles pp
  WHERE pp.organization_id = v_organization_id;

  RETURN public.public_profile_to_json(v_profile)
    || jsonb_build_object(
      'supported_currencies', to_jsonb(public.supported_public_currencies()),
      'social_networks', to_jsonb(public.public_profile_social_networks())
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile() TO authenticated;

CREATE OR REPLACE FUNCTION public.save_public_profile(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_before public.public_profiles;
  v_after public.public_profiles;
  v_name text;
  v_logo text;
  v_color text;
  v_email text;
  v_phone text;
  v_whatsapp text;
  v_social jsonb := '{}'::jsonb;
  v_languages text[];
  v_currency text;
  v_network text;
  v_url text;
  v_changed text[] := '{}'::text[];
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  IF p_payload IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object'
     OR octet_length(p_payload::text) > 8192
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_name := btrim(coalesce(p_payload ->> 'commercial_name', ''));
  IF v_name = '' OR char_length(v_name) > 120 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'commercial_name';
  END IF;

  -- Logo: a path inside the agency's own folder of catalog-media, or an https URL.
  v_logo := nullif(btrim(coalesce(p_payload ->> 'logo_ref', '')), '');
  IF v_logo IS NOT NULL
     AND NOT (
       v_logo LIKE v_organization_id::text || '/%'
       OR v_logo ~ '^https://[^\s]+$'
     )
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'logo_ref';
  END IF;

  v_color := nullif(upper(btrim(coalesce(p_payload ->> 'primary_color', ''))), '');
  IF v_color IS NOT NULL AND v_color !~ '^#[0-9A-F]{6}$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'primary_color';
  END IF;

  v_email := nullif(lower(btrim(coalesce(p_payload ->> 'contact_email', ''))), '');
  IF v_email IS NOT NULL AND v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'contact_email';
  END IF;

  v_phone := nullif(btrim(coalesce(p_payload ->> 'contact_phone', '')), '');
  IF v_phone IS NOT NULL AND v_phone !~ '^\+?[0-9 ()-]{7,25}$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'contact_phone';
  END IF;

  v_whatsapp := nullif(btrim(coalesce(p_payload ->> 'whatsapp', '')), '');
  IF v_whatsapp IS NOT NULL AND v_whatsapp !~ '^\+?[0-9 ()-]{7,25}$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'whatsapp';
  END IF;

  IF p_payload ? 'social_links' AND p_payload -> 'social_links' <> 'null'::jsonb THEN
    IF jsonb_typeof(p_payload -> 'social_links') IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'social_links';
    END IF;
    FOR v_network, v_url IN
      SELECT key, btrim(coalesce(value #>> '{}', ''))
      FROM jsonb_each(p_payload -> 'social_links')
    LOOP
      CONTINUE WHEN v_url = '';
      IF NOT v_network = ANY (public.public_profile_social_networks())
         OR v_url !~ '^https://[^\s]+$'
         OR char_length(v_url) > 300
      THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'social_links';
      END IF;
      v_social := v_social || jsonb_build_object(v_network, v_url);
    END LOOP;
  END IF;

  IF jsonb_typeof(p_payload -> 'languages') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'languages';
  END IF;
  SELECT coalesce(array_agg(DISTINCT l ORDER BY l DESC), '{}'::text[])
  INTO v_languages
  FROM jsonb_array_elements_text(p_payload -> 'languages') AS t(l);
  IF cardinality(v_languages) = 0 OR NOT v_languages <@ ARRAY['es', 'en'] THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'languages';
  END IF;

  v_currency := upper(btrim(coalesce(p_payload ->> 'currency', '')));
  IF NOT v_currency = ANY (public.supported_public_currencies()) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'currency';
  END IF;

  PERFORM public.ensure_public_agency_config(v_organization_id);

  SELECT * INTO v_before
  FROM public.public_profiles pp
  WHERE pp.organization_id = v_organization_id
  FOR UPDATE;

  UPDATE public.public_profiles
  SET
    commercial_name = v_name,
    logo_ref = v_logo,
    primary_color = v_color,
    contact_email = v_email,
    contact_phone = v_phone,
    whatsapp = v_whatsapp,
    social_links = v_social,
    languages = v_languages,
    currency = v_currency,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE organization_id = v_organization_id
  RETURNING * INTO v_after;

  -- Audit names the fields that changed, never their values.
  IF v_before.commercial_name IS DISTINCT FROM v_after.commercial_name THEN v_changed := array_append(v_changed, 'commercial_name'); END IF;
  IF v_before.logo_ref IS DISTINCT FROM v_after.logo_ref THEN v_changed := array_append(v_changed, 'logo_ref'); END IF;
  IF v_before.primary_color IS DISTINCT FROM v_after.primary_color THEN v_changed := array_append(v_changed, 'primary_color'); END IF;
  IF v_before.contact_email IS DISTINCT FROM v_after.contact_email THEN v_changed := array_append(v_changed, 'contact_email'); END IF;
  IF v_before.contact_phone IS DISTINCT FROM v_after.contact_phone THEN v_changed := array_append(v_changed, 'contact_phone'); END IF;
  IF v_before.whatsapp IS DISTINCT FROM v_after.whatsapp THEN v_changed := array_append(v_changed, 'whatsapp'); END IF;
  IF v_before.social_links IS DISTINCT FROM v_after.social_links THEN v_changed := array_append(v_changed, 'social_links'); END IF;
  IF v_before.languages IS DISTINCT FROM v_after.languages THEN v_changed := array_append(v_changed, 'languages'); END IF;
  IF v_before.currency IS DISTINCT FROM v_after.currency THEN v_changed := array_append(v_changed, 'currency'); END IF;

  PERFORM audit.log_event(
    v_organization_id,
    'public_profile_updated'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_profile',
    NULL,
    jsonb_build_object('changed_fields', to_jsonb(v_changed))
  );

  RETURN public.public_profile_to_json(v_after);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_public_profile(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_public_profile(jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- Public projections (internal)
-- ---------------------------------------------------------------------------

-- Only fields the agency configured; empty values are absent, not blank (edge case 7).
CREATE OR REPLACE FUNCTION public.build_public_profile(p_organization_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'commercialName', pp.commercial_name,
    'logo', pp.logo_ref,
    'primaryColor', pp.primary_color,
    'contactEmail', pp.contact_email,
    'contactPhone', pp.contact_phone,
    'whatsapp', pp.whatsapp,
    'socialLinks', CASE WHEN pp.social_links = '{}'::jsonb THEN NULL ELSE pp.social_links END,
    'languages', to_jsonb(pp.languages),
    'currency', pp.currency
  ))
  FROM public.public_profiles pp
  WHERE pp.organization_id = p_organization_id;
$$;

REVOKE ALL ON FUNCTION public.build_public_profile(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.build_public_profile(uuid) FROM anon, authenticated;

-- Labels for every active value plus inactive ones still shown by a published listing.
CREATE OR REPLACE FUNCTION public.build_public_taxonomy(p_organization_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'categories', coalesce((
      SELECT jsonb_agg(jsonb_build_object('id', pc.id, 'name', pc.name_es, 'nameEn', pc.name_en)
                       ORDER BY pc.name_es)
      FROM public.public_categories pc
      WHERE pc.organization_id = p_organization_id
        AND (
          pc.is_active
          OR EXISTS (
            SELECT 1 FROM public.public_listings pl
            WHERE pl.organization_id = pc.organization_id
              AND pl.public_category_id = pc.id
              AND pl.status = 'published'::public.public_listing_status
          )
        )
    ), '[]'::jsonb),
    'lodgingTypes', coalesce((
      SELECT jsonb_agg(jsonb_build_object('id', tv.code, 'name', tv.name_es, 'nameEn', tv.name_en)
                       ORDER BY tv.sort_order, tv.code)
      FROM public.public_taxonomy_values tv
      WHERE tv.organization_id = p_organization_id
        AND tv.kind = 'lodging_type'
        AND (
          tv.is_active
          OR EXISTS (
            SELECT 1 FROM public.public_listings pl
            WHERE pl.organization_id = tv.organization_id
              AND pl.status = 'published'::public.public_listing_status
              AND pl.lodging ->> 'lodging_type' = tv.code
          )
        )
    ), '[]'::jsonb),
    'amenities', coalesce((
      SELECT jsonb_agg(jsonb_build_object('id', tv.code, 'name', tv.name_es, 'nameEn', tv.name_en)
                       ORDER BY tv.sort_order, tv.code)
      FROM public.public_taxonomy_values tv
      WHERE tv.organization_id = p_organization_id
        AND tv.kind = 'amenity'
        AND (
          tv.is_active
          OR EXISTS (
            SELECT 1 FROM public.public_listings pl
            WHERE pl.organization_id = tv.organization_id
              AND pl.status = 'published'::public.public_listing_status
              AND jsonb_typeof(pl.lodging -> 'amenities') = 'array'
              AND (pl.lodging -> 'amenities') ? tv.code
          )
        )
    ), '[]'::jsonb)
  );
$$;

REVOKE ALL ON FUNCTION public.build_public_taxonomy(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.build_public_taxonomy(uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- get_public_site_by_key: the contract every external showcase uses (FR-022, FR-023).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_public_site_by_key(p_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
BEGIN
  v_organization_id := public.resolve_public_access_key(p_key);

  RETURN jsonb_build_object(
    'profile', coalesce(public.build_public_profile(v_organization_id), '{}'::jsonb),
    'catalog', public.build_public_catalog(v_organization_id)
               || public.build_public_taxonomy(v_organization_id)
  );
END;
$$;

COMMENT ON FUNCTION public.get_public_site_by_key(text) IS
  'Anon: public profile + published catalog of the agency that owns the key. Invalid keys get '
  'PUBLIC_ACCESS_UNAVAILABLE.';

REVOKE EXECUTE ON FUNCTION public.get_public_site_by_key(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_site_by_key(text) TO anon, authenticated;
