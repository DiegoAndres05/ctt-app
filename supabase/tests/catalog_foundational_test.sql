-- catalog_foundational_test.sql
-- Foundational checks for feature 002 catalog/pricing tables (T014 / T044): RLS is enabled
-- on every catalog table (011–021) and the seasonal EXCLUDE constraints are present.
--
-- Run with: supabase/tests/run-sql-tests.sh
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'providers' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.providers'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'products' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.products'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'experiences' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.experiences'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'accommodations' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.accommodations'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'categories' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.categories'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'product_categories' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.product_categories'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'pricing_schemes' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.pricing_schemes'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'add_ons' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.add_ons'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'product_addons' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.product_addons'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'packages' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.packages'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'package_items' AND c.relrowsecurity
    )$$,
  'RLS enabled on public.package_items'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = 'public.pricing_schemes'::regclass
        AND conname = 'pricing_schemes_product_season_no_overlap'
        AND contype = 'x'
    )$$,
  'EXCLUDE constraint pricing_schemes_product_season_no_overlap is active'
);

SELECT tests.assert_true(
  $$EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = 'public.pricing_schemes'::regclass
        AND conname = 'pricing_schemes_addon_season_no_overlap'
        AND contype = 'x'
    )$$,
  'EXCLUDE constraint pricing_schemes_addon_season_no_overlap is active'
);

-- Smoke: overlapping current seasons for the same product and charge_type are rejected.
DO $$
DECLARE
  v_org_id uuid := '00000000-0000-4000-a000-000000000001';
  v_product_id uuid;
BEGIN
  INSERT INTO public.products (organization_id, type, name, status)
  VALUES (v_org_id, 'experience', 'Foundational overlap probe', 'draft')
  RETURNING id INTO v_product_id;

  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type,
    season_start, season_end
  )
  VALUES (
    v_org_id, v_product_id, 'COP', 100000, 'per_person',
    DATE '2026-12-01', DATE '2027-01-15'
  );
END;
$$;

SELECT tests.assert_raises(
  $$INSERT INTO public.pricing_schemes (
      organization_id, product_id, currency, base_amount, charge_type,
      season_start, season_end
    )
    SELECT
      '00000000-0000-4000-a000-000000000001'::uuid,
      id,
      'COP',
      120000,
      'per_person',
      DATE '2026-12-20',
      DATE '2027-01-05'
    FROM public.products
    WHERE name = 'Foundational overlap probe'
    LIMIT 1$$,
  'conflicting key value',
  'overlapping current seasons are rejected by EXCLUDE'
);

ROLLBACK;
