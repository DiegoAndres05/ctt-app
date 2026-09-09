-- pricing_rules_test.sql
-- Seasonal vs base resolution (SC-003), anti-overlap EXCLUDE / SEASON_OVERLAP, and the
-- admin-only price_overridden audit trail after apply_price_override (T041 / FR-009).
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/pricing_rules_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set org_id          33333333-3333-4000-a000-000000000033
\set admin_id        33333333-3333-4000-b000-000000000031
\set operator_id     33333333-3333-4000-b000-000000000032
\set agent_id        33333333-3333-4000-b000-000000000033
\set other_org_id    44444444-4444-4000-a000-000000000044
\set other_admin_id  44444444-4444-4000-b000-000000000041

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
VALUES
  (:'org_id'::uuid, 'Pricing Alpha', 'pricing-alpha', 'active',
   jsonb_build_object('default_currency', 'COP')),
  (:'other_org_id'::uuid, 'Pricing Beta', 'pricing-beta', 'active',
   jsonb_build_object('default_currency', 'USD'));

SELECT pg_temp.add_collaborator(
  :'admin_id'::uuid, :'org_id'::uuid,
  'admin-price@test.invalid', 'Admin Price', 'admin'
);
SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid,
  'operador-price@test.invalid', 'Operador Price', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'agent_id'::uuid, :'org_id'::uuid,
  'agente-price@test.invalid', 'Agente Price', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'other_admin_id'::uuid, :'other_org_id'::uuid,
  'admin-price-beta@test.invalid', 'Admin Price Beta', 'admin'
);

-- ===========================================================================
-- 1. Operator defines base + seasonal tariffs; resolve_price picks by date
-- ===========================================================================

\echo '--- resolve_price: season vs base ---'

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience',
  'Rafting temporada',
  NULL,
  NULL,
  '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 180,
    'difficulty', 'moderate',
    'meeting_point', 'Rio',
    'min_capacity', 2,
    'max_capacity', 8
  ),
  NULL
) ->> 'id') AS product_id \gset

SELECT public.upsert_pricing_scheme(
  :'product_id'::uuid,
  NULL,
  'COP',
  150000,
  'per_person',
  NULL,
  NULL
);

SELECT public.upsert_pricing_scheme(
  :'product_id'::uuid,
  NULL,
  'COP',
  180000,
  'per_person',
  '2026-12-01',
  '2027-01-15'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT amount = 180000 AND source = 'season' AND btrim(currency) = 'COP'
         FROM public.resolve_price(%L::uuid, '2026-12-20', 'per_person')$sql$,
    :'product_id'
  ),
  'resolve_price returns the seasonal tariff when the date falls in the season'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT amount = 150000 AND source = 'base' AND btrim(currency) = 'COP'
         FROM public.resolve_price(%L::uuid, '2026-10-15', 'per_person')$sql$,
    :'product_id'
  ),
  'resolve_price returns the base tariff when the date is outside every season'
);

-- Inclusive season bounds (daterange '[]'): the start and end days themselves are seasonal.
SELECT tests.assert_true(
  format(
    $sql$SELECT amount = 180000 AND source = 'season'
         FROM public.resolve_price(%L::uuid, '2026-12-01', 'per_person')$sql$,
    :'product_id'
  ),
  'resolve_price treats season_start as inclusive'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT amount = 180000 AND source = 'season'
         FROM public.resolve_price(%L::uuid, '2027-01-15', 'per_person')$sql$,
    :'product_id'
  ),
  'resolve_price treats season_end as inclusive'
);

-- ===========================================================================
-- 2. Anti-overlap: RPC maps EXCLUDE to SEASON_OVERLAP; EXCLUDE also fires on INSERT
-- ===========================================================================

\echo '--- anti-overlap ---'

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.upsert_pricing_scheme(
      %L::uuid, NULL, 'COP', 200000, 'per_person', '2026-12-20', '2027-02-01'
    )$sql$,
    :'product_id'
  ),
  'SEASON_OVERLAP',
  'upsert_pricing_scheme rejects a season that overlaps a current seasonal scheme'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.upsert_pricing_scheme(
      %L::uuid, NULL, 'COP', 1, 'per_person', '2027-01-01', '2026-12-01'
    )$sql$,
    :'product_id'
  ),
  'INVALID_SEASON_RANGE',
  'upsert_pricing_scheme rejects season_start after season_end'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.upsert_pricing_scheme(
      %L::uuid, NULL, 'COP', 1, 'per_person', '2026-12-01', NULL
    )$sql$,
    :'product_id'
  ),
  'INVALID_SEASON_RANGE',
  'upsert_pricing_scheme rejects a half-open season range'
);

SELECT tests.assert_raises(
  $sql$SELECT public.upsert_pricing_scheme(
    NULL, NULL, 'COP', 1, 'per_person', NULL, NULL
  )$sql$,
  'INVALID_PRICE_TARGET',
  'upsert_pricing_scheme requires exactly one of product_id / addon_id'
);

RESET ROLE;

SELECT tests.assert_raises(
  format(
    $sql$INSERT INTO public.pricing_schemes (
           organization_id, product_id, currency, base_amount, charge_type,
           season_start, season_end
         )
         VALUES (
           %L, %L, 'COP', 999, 'per_person',
           '2026-12-10', '2027-02-01'
         )$sql$,
    :'org_id',
    :'product_id'
  ),
  'pricing_schemes_product_season_no_overlap',
  'EXCLUDE USING gist rejects overlapping current seasons on direct insert'
);

-- Adjacent seasons (end then next start) are allowed.
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.upsert_pricing_scheme(
  :'product_id'::uuid,
  NULL,
  'COP',
  160000,
  'per_person',
  '2027-01-16',
  '2027-03-01'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 3 FROM public.pricing_schemes
         WHERE product_id = %L AND valid_to IS NULL$sql$,
    :'product_id'
  ),
  'adjacent (non-overlapping) seasons can coexist with the base tariff'
);

-- ===========================================================================
-- 3. RBAC: definition is operator/admin; override is admin only
-- ===========================================================================

\echo '--- pricing RBAC ---'

RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.upsert_pricing_scheme(
      %L::uuid, NULL, 'COP', 1, 'per_person', NULL, NULL
    )$sql$,
    :'product_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot define a pricing scheme'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.apply_price_override(%L::uuid, 1, 'no')$sql$,
    :'product_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot apply a price override'
);

RESET ROLE;
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.apply_price_override(%L::uuid, 175000, 'Ajuste de margen')$sql$,
    :'product_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an operator cannot apply a price override'
);

-- ===========================================================================
-- 4. Admin override emits price_overridden with actor, org, previous/new, reason
-- ===========================================================================

\echo '--- price_overridden audit ---'

RESET ROLE;
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT public.apply_price_override(
  :'product_id'::uuid,
  175000,
  'Ajuste comercial autorizado',
  'per_person'
) AS override_result \gset

SELECT tests.assert_true(
  format(
    $sql$SELECT (j->>'previous_amount')::numeric = 150000
            AND (j->>'new_amount')::numeric = 175000
         FROM (SELECT %L::jsonb AS j) s$sql$,
    :'override_result'
  ),
  'apply_price_override returns the previous base amount and the new amount'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 1 FROM audit.audit_events
         WHERE event_type = 'price_overridden'
           AND organization_id = %L
           AND actor_id = %L
           AND resource_id = %L
           AND result = 'success'
           AND metadata->>'reason' = 'Ajuste comercial autorizado'
           AND (metadata->>'previous_amount')::numeric = 150000
           AND (metadata->>'new_amount')::numeric = 175000
           AND btrim(metadata->>'currency') = 'COP'$sql$,
    :'org_id',
    :'admin_id',
    :'product_id'
  ),
  'apply_price_override writes price_overridden with actor, org, previous/new amounts, currency and reason'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT amount = 175000 AND source = 'base'
         FROM public.resolve_price(%L::uuid, '2026-10-15', 'per_person')$sql$,
    :'product_id'
  ),
  'after override, resolve_price returns the new base amount outside the season'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 0 FROM audit.audit_events
         WHERE event_type = 'price_overridden'
           AND organization_id = %L
           AND actor_id = %L$sql$,
    :'org_id',
    :'operator_id'
  ),
  'operator upserts do not emit price_overridden'
);

\echo '--- pricing_rules_test: all assertions passed ---'

ROLLBACK;
