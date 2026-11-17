-- 059_public_agency_configuration.sql
-- Agency-owned public configuration (feature 016): taxonomies, public profile, access keys and
-- source policy. Tables, RLS, defaults for new agencies and backfill for existing ones.
-- Source of truth: specs/016-multiagency-public-cms/data-model.md
--
-- Every row belongs to one organization. Writes go through SECURITY DEFINER RPCs
-- (migrations 060-063); authenticated users only get tenant-scoped SELECT here.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

CREATE TABLE public.public_taxonomy_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  kind text NOT NULL,
  code text NOT NULL,
  name_es text NOT NULL,
  name_en text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT public_taxonomy_values_kind CHECK (kind IN ('lodging_type', 'amenity')),
  CONSTRAINT public_taxonomy_values_code_format CHECK (code ~ '^[a-z0-9]+(_[a-z0-9]+)*$'),
  CONSTRAINT public_taxonomy_values_code_length CHECK (char_length(code) <= 40),
  CONSTRAINT public_taxonomy_values_name_es_not_blank CHECK (btrim(name_es) <> ''),
  CONSTRAINT public_taxonomy_values_name_en_not_blank CHECK (btrim(name_en) <> ''),
  CONSTRAINT public_taxonomy_values_unique UNIQUE (organization_id, kind, code)
);

COMMENT ON TABLE public.public_taxonomy_values IS
  'Agency-owned lodging types and amenities for public listings (feature 016).';

CREATE TABLE public.public_profiles (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations (id) ON DELETE RESTRICT,
  commercial_name text NOT NULL,
  logo_ref text,
  primary_color text,
  contact_email text,
  contact_phone text,
  whatsapp text,
  social_links jsonb NOT NULL DEFAULT '{}'::jsonb,
  languages text[] NOT NULL DEFAULT ARRAY['es', 'en'],
  currency char(3) NOT NULL DEFAULT 'COP',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  CONSTRAINT public_profiles_name_not_blank CHECK (btrim(commercial_name) <> ''),
  CONSTRAINT public_profiles_name_length CHECK (char_length(commercial_name) <= 120),
  CONSTRAINT public_profiles_color_hex CHECK (primary_color IS NULL OR primary_color ~ '^#[0-9A-F]{6}$'),
  CONSTRAINT public_profiles_social_object CHECK (jsonb_typeof(social_links) = 'object'),
  CONSTRAINT public_profiles_languages_valid CHECK (
    cardinality(languages) BETWEEN 1 AND 2
    AND languages <@ ARRAY['es', 'en']
  ),
  CONSTRAINT public_profiles_currency_iso CHECK (currency ~ '^[A-Z]{3}$')
);

COMMENT ON TABLE public.public_profiles IS
  'Public-facing agency profile read by external showcases (feature 016). Never holds internal data.';

CREATE TABLE public.public_access_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  key_fingerprint text NOT NULL,
  key_prefix text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  last_used_at timestamptz,
  CONSTRAINT public_access_keys_fingerprint_unique UNIQUE (key_fingerprint),
  CONSTRAINT public_access_keys_fingerprint_hex CHECK (key_fingerprint ~ '^[0-9a-f]{64}$')
);

COMMENT ON TABLE public.public_access_keys IS
  'Rotatable public credentials. Only the SHA-256 fingerprint is stored; the clear key is shown once.';
COMMENT ON COLUMN public.public_access_keys.expires_at IS
  'NULL for the current key; set to rotation time + 7 days when a newer key replaces it.';

-- At most one current (not rotated, not revoked) key per agency.
CREATE UNIQUE INDEX public_access_keys_one_current
  ON public.public_access_keys (organization_id)
  WHERE expires_at IS NULL AND revoked_at IS NULL;

CREATE INDEX public_access_keys_org_idx ON public.public_access_keys (organization_id, created_at DESC);

CREATE TABLE public.public_source_config (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations (id) ON DELETE RESTRICT,
  migration_required boolean NOT NULL DEFAULT false,
  organization_identifier_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.public_source_config IS
  'Per-agency source policy: whether an existing site must be copied before cutover, and until when '
  'the legacy organization-identifier access stays open (CTT compatibility only).';

-- ---------------------------------------------------------------------------
-- RLS: tenant-scoped reads; writes only through RPCs
-- ---------------------------------------------------------------------------

ALTER TABLE public.public_taxonomy_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_access_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_source_config ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.public_taxonomy_values FROM anon;
REVOKE ALL ON public.public_profiles FROM anon;
REVOKE ALL ON public.public_access_keys FROM anon;
REVOKE ALL ON public.public_source_config FROM anon;

REVOKE INSERT, UPDATE, DELETE ON public.public_taxonomy_values FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.public_profiles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.public_access_keys FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.public_source_config FROM authenticated;

CREATE POLICY tenant_isolation_select ON public.public_taxonomy_values
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.public_profiles
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- Key metadata (never the secret) is visible to the agency administrator only.
CREATE POLICY admin_select ON public.public_access_keys
  FOR SELECT TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') = 'admin'
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY tenant_isolation_select ON public.public_source_config
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.supported_public_currencies()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT ARRAY['COP', 'USD', 'EUR'];
$$;

COMMENT ON FUNCTION public.supported_public_currencies() IS
  'Currencies an agency may choose to display public prices in. No conversion is implied.';

GRANT EXECUTE ON FUNCTION public.supported_public_currencies() TO authenticated;

-- Seeds the editable starting set for one agency. Idempotent: existing rows are never renamed.
CREATE OR REPLACE FUNCTION public.ensure_public_agency_config(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name text;
  v_currency text;
BEGIN
  SELECT o.name,
         upper(coalesce(nullif(btrim(o.settings ->> 'default_currency'), ''), 'COP'))
  INTO v_name, v_currency
  FROM public.organizations o
  WHERE o.id = p_organization_id;

  IF v_name IS NULL THEN
    RETURN;
  END IF;

  IF NOT v_currency = ANY (public.supported_public_currencies()) THEN
    v_currency := 'COP';
  END IF;

  INSERT INTO public.public_source_config (organization_id)
  VALUES (p_organization_id)
  ON CONFLICT (organization_id) DO NOTHING;

  INSERT INTO public.public_profiles (organization_id, commercial_name, currency)
  VALUES (p_organization_id, left(v_name, 120), v_currency)
  ON CONFLICT (organization_id) DO NOTHING;

  INSERT INTO public.public_taxonomy_values (organization_id, kind, code, name_es, name_en, sort_order)
  VALUES
    (p_organization_id, 'lodging_type', 'casa', 'Casa', 'House', 1),
    (p_organization_id, 'lodging_type', 'apartamento', 'Apartamento', 'Apartment', 2),
    (p_organization_id, 'lodging_type', 'finca', 'Finca', 'Country house', 3),
    (p_organization_id, 'lodging_type', 'habitacion', 'Habitación', 'Room', 4),
    (p_organization_id, 'lodging_type', 'hotel', 'Hotel', 'Hotel', 5),
    (p_organization_id, 'amenity', 'wifi', 'Wifi', 'Wi-Fi', 1),
    (p_organization_id, 'amenity', 'pool', 'Piscina', 'Pool', 2),
    (p_organization_id, 'amenity', 'ac', 'Aire acondicionado', 'Air conditioning', 3),
    (p_organization_id, 'amenity', 'kitchen', 'Cocina', 'Kitchen', 4),
    (p_organization_id, 'amenity', 'parking', 'Parqueadero', 'Parking', 5),
    (p_organization_id, 'amenity', 'sea_view', 'Vista al mar', 'Sea view', 6),
    (p_organization_id, 'amenity', 'terrace', 'Terraza', 'Terrace', 7),
    (p_organization_id, 'amenity', 'washer', 'Lavadora', 'Washer', 8),
    (p_organization_id, 'amenity', 'tv', 'Televisor', 'TV', 9),
    (p_organization_id, 'amenity', 'bbq', 'Zona BBQ', 'BBQ area', 10)
  ON CONFLICT (organization_id, kind, code) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_public_agency_config(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ensure_public_agency_config(uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.ensure_public_agency_config_on_org_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.ensure_public_agency_config(NEW.id);
  RETURN NEW;
END;
$$;

-- Trigger names fire alphabetically: this one runs before organizations_ensure_public_site_defaults
-- and organizations_seed_public_catalog, so demo listings find their taxonomy values.
CREATE TRIGGER organizations_ensure_public_agency_config
  AFTER INSERT ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_public_agency_config_on_org_insert();

-- New agencies get a generic, fully editable set of example categories (FR-002).
-- CTT's eight categories are only added for agencies migrating CTT's site (see below).
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
    ('tours', NEW.id, 'Tours', 'Tours', true, false),
    ('playa', NEW.id, 'Playa', 'Beach', true, false),
    ('aventura', NEW.id, 'Aventura', 'Adventure', true, false),
    ('cultural', NEW.id, 'Cultural', 'Cultural', true, false),
    ('gastronomia', NEW.id, 'Gastronomía', 'Food & drink', true, false),
    ('naturaleza', NEW.id, 'Naturaleza', 'Nature', true, false),
    ('premium', NEW.id, 'Premium', 'Premium', true, false)
  ON CONFLICT (organization_id, id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Migrated agencies (CTT): a cutover manifest means the agency is replacing an existing site.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.mark_public_site_as_migrated(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.public_source_config (organization_id)
  VALUES (p_organization_id)
  ON CONFLICT (organization_id) DO NOTHING;

  -- First time only: open the 90-day organization-identifier transition. An agency whose
  -- transition already ended is never reopened by a later manifest row.
  UPDATE public.public_source_config
  SET
    migration_required = true,
    organization_identifier_until = now() + interval '90 days',
    updated_at = now()
  WHERE organization_id = p_organization_id
    AND migration_required = false
    AND organization_identifier_until IS NULL;

  -- CTT's filters and addresses use these eight identifiers (FR-004).
  INSERT INTO public.public_categories (id, organization_id, name_es, name_en, is_active, protected)
  VALUES
    ('islas', p_organization_id, 'Islas', 'Islands', true, true),
    ('baru', p_organization_id, 'Barú', 'Barú', true, true),
    ('tierra_bomba', p_organization_id, 'Tierra Bomba', 'Tierra Bomba', true, true),
    ('compartidos', p_organization_id, 'Compartidos', 'Shared', true, true),
    ('cultural', p_organization_id, 'Cultural', 'Cultural', true, true),
    ('aventura', p_organization_id, 'Aventura', 'Adventure', true, true),
    ('baile', p_organization_id, 'Baile', 'Dance', true, true),
    ('premium', p_organization_id, 'Premium', 'Premium', true, true)
  ON CONFLICT (organization_id, id) DO UPDATE SET protected = true;

  -- Generic examples that CTT's site does not use are switched off while unused.
  UPDATE public.public_categories pc
  SET is_active = false, updated_at = now()
  WHERE pc.organization_id = p_organization_id
    AND pc.id IN ('tours', 'playa', 'gastronomia', 'naturaleza')
    AND NOT pc.protected
    AND pc.is_active
    AND NOT EXISTS (
      SELECT 1 FROM public.public_listings pl
      WHERE pl.organization_id = pc.organization_id
        AND pl.public_category_id = pc.id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.mark_public_site_as_migrated(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mark_public_site_as_migrated(uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.mark_public_site_as_migrated_on_manifest()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.mark_public_site_as_migrated(NEW.organization_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER public_cutover_items_mark_migrated
  AFTER INSERT ON public.public_cutover_items
  FOR EACH ROW
  EXECUTE FUNCTION public.mark_public_site_as_migrated_on_manifest();

-- ---------------------------------------------------------------------------
-- Backfill existing agencies
-- ---------------------------------------------------------------------------

SELECT public.ensure_public_agency_config(o.id) FROM public.organizations o;

-- Keep any lodging code already used by a listing, so no published value loses its label.
INSERT INTO public.public_taxonomy_values (organization_id, kind, code, name_es, name_en, sort_order)
SELECT DISTINCT pl.organization_id, 'lodging_type', pl.lodging ->> 'lodging_type',
       pl.lodging ->> 'lodging_type', pl.lodging ->> 'lodging_type', 100
FROM public.public_listings pl
WHERE pl.lodging ? 'lodging_type'
  AND (pl.lodging ->> 'lodging_type') ~ '^[a-z0-9]+(_[a-z0-9]+)*$'
ON CONFLICT (organization_id, kind, code) DO NOTHING;

INSERT INTO public.public_taxonomy_values (organization_id, kind, code, name_es, name_en, sort_order)
SELECT DISTINCT pl.organization_id, 'amenity', a.code, a.code, a.code, 100
FROM public.public_listings pl
CROSS JOIN LATERAL jsonb_array_elements_text(
  CASE WHEN jsonb_typeof(pl.lodging -> 'amenities') = 'array' THEN pl.lodging -> 'amenities' ELSE '[]'::jsonb END
) AS a(code)
WHERE a.code ~ '^[a-z0-9]+(_[a-z0-9]+)*$'
ON CONFLICT (organization_id, kind, code) DO NOTHING;

-- Agencies that already carry a manifest are migrating an existing site.
SELECT public.mark_public_site_as_migrated(x.organization_id)
FROM (SELECT DISTINCT organization_id FROM public.public_cutover_items) x;

-- Every other existing agency owns its categories outright (FR-002).
UPDATE public.public_categories pc
SET protected = false, updated_at = now()
WHERE pc.protected
  AND NOT EXISTS (
    SELECT 1 FROM public.public_source_config sc
    WHERE sc.organization_id = pc.organization_id
      AND sc.migration_required
  );
