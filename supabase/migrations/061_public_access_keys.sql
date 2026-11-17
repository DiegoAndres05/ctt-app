-- 061_public_access_keys.sql
-- Public access keys (feature 016, US2) and the CTT organization-identifier transition (US4).
-- Source of truth: specs/016-multiagency-public-cms/contracts/public-consumer.md
--
-- ERROR CONTRACT: the exception message is the API code.
--   FORBIDDEN, PUBLIC_ACCESS_UNAVAILABLE (same message and SQLSTATE for every invalid key or
--   closed identifier, so a caller cannot tell whether the agency exists).
--
-- Only the SHA-256 fingerprint of a key is stored. The clear key is returned once, by
-- generate_public_access_key, and never appears in audit metadata.

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.require_tenant_admin_or_forbidden()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
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
  RETURN v_organization_id;
END;
$$;

REVOKE ALL ON FUNCTION public.require_tenant_admin_or_forbidden() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.require_tenant_admin_or_forbidden() FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.public_access_unavailable()
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'PUBLIC_ACCESS_UNAVAILABLE' USING ERRCODE = 'insufficient_privilege';
END;
$$;

REVOKE ALL ON FUNCTION public.public_access_unavailable() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.public_access_unavailable() FROM anon, authenticated;

-- Resolves a clear key to its active agency, or raises the generic denial.
CREATE OR REPLACE FUNCTION public.resolve_public_access_key(p_key text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_key text := btrim(coalesce(p_key, ''));
  v_row public.public_access_keys;
BEGIN
  IF v_key = '' OR char_length(v_key) > 128 THEN
    PERFORM public.public_access_unavailable();
  END IF;

  SELECT k.* INTO v_row
  FROM public.public_access_keys k
  JOIN public.organizations o ON o.id = k.organization_id
  WHERE k.key_fingerprint = encode(extensions.digest(v_key, 'sha256'), 'hex')
    AND k.revoked_at IS NULL
    AND (k.expires_at IS NULL OR k.expires_at > now())
    AND o.status = 'active';

  IF v_row.id IS NULL THEN
    PERFORM public.public_access_unavailable();
  END IF;

  -- Coarse usage signal (at most one write per hour per key).
  UPDATE public.public_access_keys
  SET last_used_at = now()
  WHERE id = v_row.id
    AND (last_used_at IS NULL OR last_used_at < now() - interval '1 hour');

  RETURN v_row.organization_id;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_public_access_key(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.resolve_public_access_key(text) FROM anon, authenticated;

-- CTT compatibility: the organization identifier is accepted only for a migrating agency
-- whose transition window is still open (FR-016, FR-017).
CREATE OR REPLACE FUNCTION public.require_organization_identifier_access(p_organization_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_organization_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.public_source_config sc
    JOIN public.organizations o ON o.id = sc.organization_id
    WHERE sc.organization_id = p_organization_id
      AND sc.migration_required
      AND sc.organization_identifier_until > now()
      AND o.status = 'active'
  ) THEN
    PERFORM public.public_access_unavailable();
  END IF;
  RETURN p_organization_id;
END;
$$;

REVOKE ALL ON FUNCTION public.require_organization_identifier_access(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.require_organization_identifier_access(uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Key management (Administrator only, FR-012)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.public_access_key_status(p_key public.public_access_keys)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_key.revoked_at IS NOT NULL THEN 'revoked'
    WHEN p_key.expires_at IS NULL THEN 'current'
    WHEN p_key.expires_at > now() THEN 'grace'
    ELSE 'expired'
  END;
$$;

REVOKE ALL ON FUNCTION public.public_access_key_status(public.public_access_keys) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.public_access_key_status(public.public_access_keys) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.list_public_access_keys()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
BEGIN
  v_organization_id := public.require_tenant_admin_or_forbidden();

  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', k.id,
      'key_prefix', k.key_prefix,
      'status', public.public_access_key_status(k),
      'created_at', k.created_at,
      'created_by_name', cu.full_name,
      'expires_at', k.expires_at,
      'revoked_at', k.revoked_at,
      'revoked_by_name', ru.full_name,
      'last_used_at', k.last_used_at
    ) ORDER BY k.created_at DESC)
    FROM public.public_access_keys k
    LEFT JOIN public.user_profiles cu ON cu.id = k.created_by
    LEFT JOIN public.user_profiles ru ON ru.id = k.revoked_by
    WHERE k.organization_id = v_organization_id
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_public_access_keys() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_public_access_keys() TO authenticated;

-- Generates the first key or rotates the current one. The previous key keeps working for
-- exactly 7 days (clarification 2026-11-13). Returns the clear key once.
CREATE OR REPLACE FUNCTION public.generate_public_access_key()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_previous public.public_access_keys;
  v_previous_expires_at timestamptz;
  v_key text;
  v_row public.public_access_keys;
BEGIN
  v_organization_id := public.require_tenant_admin_or_forbidden();

  -- Serialize rotations of one agency.
  PERFORM 1 FROM public.organizations o WHERE o.id = v_organization_id FOR UPDATE;

  SELECT * INTO v_previous
  FROM public.public_access_keys k
  WHERE k.organization_id = v_organization_id
    AND k.expires_at IS NULL
    AND k.revoked_at IS NULL;

  IF v_previous.id IS NOT NULL THEN
    v_previous_expires_at := now() + interval '7 days';
    UPDATE public.public_access_keys
    SET expires_at = v_previous_expires_at
    WHERE id = v_previous.id;
  END IF;

  v_key := 'pk_' || encode(extensions.gen_random_bytes(24), 'hex');

  INSERT INTO public.public_access_keys (
    organization_id, key_fingerprint, key_prefix, created_by
  )
  VALUES (
    v_organization_id,
    encode(extensions.digest(v_key, 'sha256'), 'hex'),
    left(v_key, 11),
    auth.uid()
  )
  RETURNING * INTO v_row;

  PERFORM audit.log_event(
    v_organization_id,
    'public_key_generated'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_access_key',
    v_row.id,
    jsonb_strip_nulls(jsonb_build_object(
      'action', CASE WHEN v_previous.id IS NULL THEN 'generated' ELSE 'regenerated' END,
      'previous_key_id', v_previous.id,
      'previous_key_expires_at', v_previous_expires_at
    ))
  );

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'key', v_key,
    'id', v_row.id,
    'key_prefix', v_row.key_prefix,
    'created_at', v_row.created_at,
    'previous_key_id', v_previous.id,
    'previous_key_expires_at', v_previous_expires_at
  ));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.generate_public_access_key() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_public_access_key() TO authenticated;

-- Immediate invalidation, also for a key in its grace period. Idempotent.
CREATE OR REPLACE FUNCTION public.revoke_public_access_key(p_key_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_row public.public_access_keys;
BEGIN
  v_organization_id := public.require_tenant_admin_or_forbidden();

  SELECT * INTO v_row
  FROM public.public_access_keys k
  WHERE k.id = p_key_id
    AND k.organization_id = v_organization_id;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_row.revoked_at IS NULL THEN
    UPDATE public.public_access_keys
    SET revoked_at = now(), revoked_by = auth.uid()
    WHERE id = v_row.id
    RETURNING * INTO v_row;

    PERFORM audit.log_event(
      v_organization_id,
      'public_key_revoked'::audit.audit_event_type,
      'success'::audit.audit_result,
      auth.uid(),
      'public_access_key',
      v_row.id,
      jsonb_build_object('action', 'revoked')
    );
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'status', public.public_access_key_status(v_row),
    'revoked_at', v_row.revoked_at
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.revoke_public_access_key(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_public_access_key(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Catalog projection shared by every public entry point (not callable directly).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.build_public_catalog(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid := p_organization_id;
  v_source public.public_source;
  v_migration_required boolean;
  v_offers jsonb := '[]'::jsonb;
  v_lodgings jsonb := '[]'::jsonb;
  v_yachts jsonb := '[]'::jsonb;
BEGIN
  SELECT ps.source, coalesce(sc.migration_required, false)
  INTO v_source, v_migration_required
  FROM public.public_sites ps
  LEFT JOIN public.public_source_config sc ON sc.organization_id = ps.organization_id
  WHERE ps.organization_id = v_organization_id;

  -- A migrating agency shows the «preparing» state until its cutover is complete (FR-027).
  -- An agency without an external source publishes directly (FR-028).
  IF v_source IS NULL
     OR (v_source = 'legacy'::public.public_source AND v_migration_required)
  THEN
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


REVOKE ALL ON FUNCTION public.build_public_catalog(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.build_public_catalog(uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- get_public_site(organization_id): signed-in staff preview their own agency; anonymous
-- callers may use the organization identifier only during the CTT transition.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_public_site(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_jwt_org uuid;
BEGIN
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
    RETURN public.build_public_catalog(v_jwt_org);
  END IF;

  RETURN public.build_public_catalog(
    public.require_organization_identifier_access(p_organization_id)
  );
END;
$$;

COMMENT ON FUNCTION public.get_public_site(uuid) IS
  'Authenticated: own agency preview. Anon: CTT transition only (organization identifier); '
  'after the transition use get_public_site_by_key.';

REVOKE EXECUTE ON FUNCTION public.get_public_site(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_site(uuid) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Traveler request intake: the 003 implementation becomes an internal function; the public
-- entry points resolve the agency from a key or from the CTT transition identifier.
-- ---------------------------------------------------------------------------

ALTER FUNCTION public.submit_public_request(uuid, jsonb) RENAME TO submit_public_request_for_org;

REVOKE EXECUTE ON FUNCTION public.submit_public_request_for_org(uuid, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.submit_public_request(
  p_organization_id uuid,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.submit_public_request_for_org(
    public.require_organization_identifier_access(p_organization_id),
    p_payload
  );
END;
$$;

COMMENT ON FUNCTION public.submit_public_request(uuid, jsonb) IS
  'Anon: CTT transition only. After the transition use submit_public_request_by_key.';

REVOKE EXECUTE ON FUNCTION public.submit_public_request(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_public_request(uuid, jsonb) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.submit_public_request_by_key(
  p_key text,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.submit_public_request_for_org(
    public.resolve_public_access_key(p_key),
    p_payload
  );
END;
$$;

COMMENT ON FUNCTION public.submit_public_request_by_key(text, jsonb) IS
  'Anon: traveler request for the agency that owns the public key. Not a reservation.';

REVOKE EXECUTE ON FUNCTION public.submit_public_request_by_key(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_public_request_by_key(text, jsonb) TO anon, authenticated;
