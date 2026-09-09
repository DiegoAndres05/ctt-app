-- 017_create_pricing.sql
-- Versioned tariff schemes, anti-overlap of seasons, price resolution, and R-008 activation.
-- Source of truth: specs/002-catalog-pricing/data-model.md ("7. Pricing Scheme").
--
-- addon_id is part of the XOR target now; the FK to public.add_ons is added when that table
-- is created (US2). btree_gist is required so EXCLUDE can mix uuid/text equality with ranges.

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Enum → text is not marked IMMUTABLE (labels can be renamed), so EXCLUDE cannot use
-- `charge_type::text` directly. Labels of this enum are a closed set; wrapping the cast
-- is safe and lets GiST compare charge types as text.
CREATE OR REPLACE FUNCTION public.charge_type_key(p_charge_type public.charge_type)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT p_charge_type::text;
$$;

CREATE TABLE public.pricing_schemes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  product_id uuid,
  addon_id uuid,
  currency char(3) NOT NULL,
  base_amount numeric(12, 2) NOT NULL,
  charge_type public.charge_type NOT NULL,
  season_start date,
  season_end date,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_to timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pricing_schemes_product_fkey
    FOREIGN KEY (product_id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT pricing_schemes_xor_target CHECK (
    (product_id IS NOT NULL AND addon_id IS NULL)
    OR (product_id IS NULL AND addon_id IS NOT NULL)
  ),
  CONSTRAINT pricing_schemes_currency_iso4217 CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT pricing_schemes_base_amount_non_negative CHECK (base_amount >= 0),
  CONSTRAINT pricing_schemes_season_pair CHECK (
    (season_start IS NULL AND season_end IS NULL)
    OR (season_start IS NOT NULL AND season_end IS NOT NULL AND season_start <= season_end)
  ),
  CONSTRAINT pricing_schemes_valid_range CHECK (valid_to IS NULL OR valid_to > valid_from),
  CONSTRAINT pricing_schemes_product_season_no_overlap EXCLUDE USING gist (
    product_id WITH =,
    (public.charge_type_key(charge_type)) WITH =,
    daterange(season_start, season_end, '[]') WITH &&
  ) WHERE (
    valid_to IS NULL
    AND product_id IS NOT NULL
    AND season_start IS NOT NULL
    AND season_end IS NOT NULL
  ),
  CONSTRAINT pricing_schemes_addon_season_no_overlap EXCLUDE USING gist (
    addon_id WITH =,
    (public.charge_type_key(charge_type)) WITH =,
    daterange(season_start, season_end, '[]') WITH &&
  ) WHERE (
    valid_to IS NULL
    AND addon_id IS NOT NULL
    AND season_start IS NOT NULL
    AND season_end IS NOT NULL
  )
);

COMMENT ON TABLE public.pricing_schemes IS
  'Append-only tariff versions for a product or add-on. valid_to NULL means the current version.';
COMMENT ON COLUMN public.pricing_schemes.currency IS
  'ISO 4217. Inherited from organizations.settings.default_currency when omitted.';
COMMENT ON COLUMN public.pricing_schemes.addon_id IS
  'XOR with product_id. Foreign key to add_ons is added when that table exists (US2).';

CREATE INDEX pricing_schemes_product_id_idx ON public.pricing_schemes (product_id);

CREATE INDEX pricing_schemes_addon_id_idx ON public.pricing_schemes (addon_id);

CREATE INDEX pricing_schemes_organization_id_idx ON public.pricing_schemes (organization_id);

ALTER TABLE public.pricing_schemes ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.pricing_schemes FROM anon;

CREATE POLICY tenant_isolation_select ON public.pricing_schemes
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.pricing_schemes
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.pricing_schemes
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

-- Fill currency from the tenant default when the insert omits it (R-009).
-- NOT NULL is checked after BEFORE triggers, so a NULL arriving here is valid.
CREATE OR REPLACE FUNCTION public.set_pricing_scheme_currency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_currency text;
BEGIN
  IF NEW.currency IS NOT NULL AND btrim(NEW.currency) <> '' THEN
    NEW.currency := upper(btrim(NEW.currency));
    RETURN NEW;
  END IF;

  SELECT coalesce(nullif(btrim(o.settings ->> 'default_currency'), ''), 'COP')
  INTO v_currency
  FROM public.organizations o
  WHERE o.id = NEW.organization_id;

  NEW.currency := upper(coalesce(v_currency, 'COP'));
  RETURN NEW;
END;
$$;

CREATE TRIGGER pricing_schemes_set_currency
  BEFORE INSERT ON public.pricing_schemes
  FOR EACH ROW
  EXECUTE FUNCTION public.set_pricing_scheme_currency();

-- R-008: a product cannot become commercially active without a current pricing scheme.
CREATE OR REPLACE FUNCTION public.enforce_active_requires_price()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM 'active'::public.product_status THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.pricing_schemes ps
    WHERE ps.product_id = NEW.id
      AND ps.organization_id = NEW.organization_id
      AND ps.valid_to IS NULL
      AND ps.valid_from <= now()
  ) THEN
    RAISE EXCEPTION 'PRODUCT_HAS_NO_VALID_PRICE'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_active_requires_price() IS
  'Blocks products.status = active unless a current pricing_scheme exists (R-008).';

CREATE TRIGGER products_enforce_active_requires_price
  BEFORE INSERT OR UPDATE OF status ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_active_requires_price();

-- Deterministic tariff for a product on a calendar date (SC-003). Seasonal match wins
-- over the unseasoned base scheme among versions whose valid_from/valid_to cover on_date.
CREATE OR REPLACE FUNCTION public.resolve_price(
  p_product_id uuid,
  p_on_date date,
  p_charge_type public.charge_type
)
RETURNS TABLE (currency character(3), amount numeric, source text)
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT
    ps.currency,
    ps.base_amount AS amount,
    CASE
      WHEN ps.season_start IS NOT NULL THEN 'season'
      ELSE 'base'
    END AS source
  FROM public.pricing_schemes ps
  WHERE ps.product_id = p_product_id
    AND ps.charge_type = p_charge_type
    AND ps.valid_from <= p_on_date::timestamptz
    AND (ps.valid_to IS NULL OR ps.valid_to > p_on_date::timestamptz)
    AND (
      (ps.season_start IS NULL AND ps.season_end IS NULL)
      OR (p_on_date BETWEEN ps.season_start AND ps.season_end)
    )
  ORDER BY
    (ps.season_start IS NOT NULL) DESC,
    ps.valid_from DESC
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.resolve_price(uuid, date, public.charge_type) IS
  'Returns the current tariff for a product on a date: seasonal scheme if the date falls in a season, otherwise the base scheme.';

REVOKE EXECUTE ON FUNCTION public.resolve_price(uuid, date, public.charge_type) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_price(uuid, date, public.charge_type) TO authenticated, service_role;
