-- price_freeze_test.sql
-- Append-only tariff versioning (SC-002 / R-003): creating a new price version closes the
-- previous row via valid_to and never mutates its amount. Historical resolution still
-- returns the frozen tariff for dates covered by the closed version.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/price_freeze_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set org_id      55555555-5555-4000-a000-000000000055
\set operator_id 55555555-5555-4000-b000-000000000052

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid,
  p_organization_id uuid,
  p_email text,
  p_full_name text,
  p_role public.app_role
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
          p_email, now(), now());

  INSERT INTO public.user_profiles (
    id, organization_id, full_name, email, role, status, must_change_password
  )
  VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, 'active', false);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.act_as(
  p_user_id uuid,
  p_organization_id uuid,
  p_app_role text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_strip_nulls(jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'app_role', p_app_role,
      'organization_id', p_organization_id::text
    ))::text,
    true
  );
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (
  :'org_id'::uuid, 'Freeze Org', 'freeze-org', 'active',
  jsonb_build_object('default_currency', 'COP')
);

SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid,
  'operador-freeze@test.invalid', 'Operador Freeze', 'operator'
);

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience',
  'Caminata congelada',
  NULL,
  NULL,
  '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 90,
    'min_capacity', 1,
    'max_capacity', 6
  ),
  NULL
) ->> 'id') AS product_id \gset

RESET ROLE;

-- Seed a historical current version whose valid_from is well in the past, so a later
-- versioning can be shown to leave that amount frozen for dates in its window.
INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type,
  valid_from, valid_to
)
VALUES (
  :'org_id'::uuid, :'product_id'::uuid, 'COP', 100000, 'per_person',
  '2026-01-01 00:00:00+00', NULL
)
RETURNING id AS original_scheme_id \gset

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.upsert_pricing_scheme(
  :'product_id'::uuid,
  NULL,
  'COP',
  250000,
  'per_person',
  NULL,
  NULL
) ->> 'id') AS new_scheme_id \gset

SELECT tests.assert_true(
  format(
    $sql$SELECT id <> %L FROM public.pricing_schemes WHERE id = %L$sql$,
    :'original_scheme_id',
    :'new_scheme_id'
  ),
  'upsert_pricing_scheme inserts a new version instead of reusing the historical row'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT base_amount = 100000
            AND valid_to IS NOT NULL
            AND valid_from = '2026-01-01 00:00:00+00'
         FROM public.pricing_schemes WHERE id = %L$sql$,
    :'original_scheme_id'
  ),
  'the historical row keeps its original amount and valid_from; only valid_to is closed'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT base_amount = 250000 AND valid_to IS NULL
         FROM public.pricing_schemes WHERE id = %L$sql$,
    :'new_scheme_id'
  ),
  'the new version carries the new amount and is the current row'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT amount = 100000 AND source = 'base'
         FROM public.resolve_price(%L::uuid, '2026-03-01', 'per_person')$sql$,
    :'product_id'
  ),
  'resolve_price on a date covered by the closed version still returns the frozen amount'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT amount = 250000 AND source = 'base'
         FROM public.resolve_price(%L::uuid, '2026-12-01', 'per_person')$sql$,
    :'product_id'
  ),
  'resolve_price on a date after the new version took effect returns the new amount'
);

SELECT tests.assert_raises(
  format(
    $sql$UPDATE public.pricing_schemes SET base_amount = 1 WHERE id = %L$sql$,
    :'original_scheme_id'
  ),
  'PRICE_VERSION_IMMUTABLE',
  'an in-place UPDATE of a historical amount is rejected'
);

SELECT tests.assert_raises(
  format(
    $sql$UPDATE public.pricing_schemes SET base_amount = 1 WHERE id = %L$sql$,
    :'new_scheme_id'
  ),
  'PRICE_VERSION_IMMUTABLE',
  'an in-place UPDATE of the current amount is rejected; versioning must insert a new row'
);

\echo '--- price_freeze_test: all assertions passed ---'

ROLLBACK;
