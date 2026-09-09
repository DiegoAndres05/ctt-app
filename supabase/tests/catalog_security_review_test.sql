-- catalog_security_review_test.sql
-- Phase 7 T044: Default Deny + tenant RLS on every catalog table, price definition
-- operator/admin, manual override admin-only, and JWT claims read server-side.
-- Cross-tenant product isolation lives in catalog_rls_test.sql; this suite covers the
-- remaining tables (providers, add-ons, pricing, packages) and the claim helpers.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/catalog_security_review_test.sql
-- The suite rolls back.

\set ON_ERROR_STOP on

BEGIN;

\set alpha_org_id       88888888-8888-4000-a000-000000000088
\set beta_org_id        99999999-9999-4000-a000-000000000099
\set alpha_admin_id     88888888-8888-4000-b000-000000000081
\set alpha_operator_id  88888888-8888-4000-b000-000000000082
\set alpha_agent_id     88888888-8888-4000-b000-000000000083
\set beta_admin_id      99999999-9999-4000-b000-000000000091
\set beta_provider_id   99999999-9999-4000-c000-000000000091
\set beta_addon_id      99999999-9999-4000-d000-000000000091
\set beta_product_id    99999999-9999-4000-e000-000000000091
\set beta_package_id    99999999-9999-4000-e000-000000000092

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

-- ---------------------------------------------------------------------------
-- 1. RLS is on for every catalog table (Default Deny unless a policy matches)
-- ---------------------------------------------------------------------------

SELECT tests.assert_true(
  $$SELECT count(*) = 11 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = ANY (ARRAY[
        'providers','products','experiences','accommodations','categories',
        'product_categories','add_ons','product_addons','pricing_schemes',
        'packages','package_items'
      ])
      AND c.relrowsecurity$$,
  'RLS is enabled on all 11 catalog/pricing tables'
);

SELECT tests.assert_true(
  $$SELECT count(*) = 0 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'providers','products','experiences','accommodations','categories',
        'product_categories','add_ons','product_addons','pricing_schemes',
        'packages','package_items'
      ])
      AND cmd = 'DELETE'
      AND tablename IN ('products','experiences','accommodations','providers','packages','pricing_schemes')$$,
  'products, subtypes, providers, packages and pricing_schemes have no DELETE policy (Default Deny / logical deactivation)'
);

SELECT tests.assert_true(
  $$SELECT bool_and(
       (coalesce(qual, '') LIKE '%organization_id%' OR coalesce(with_check, '') LIKE '%organization_id%')
       AND (coalesce(qual, '') LIKE '%jwt%' OR coalesce(with_check, '') LIKE '%jwt%')
     )
     FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = ANY (ARRAY[
         'providers','products','experiences','accommodations','categories',
         'product_categories','add_ons','product_addons','pricing_schemes',
         'packages','package_items'
       ])$$,
  'every catalog RLS policy pins organization_id to the JWT claim'
);

SELECT tests.assert_true(
  $$SELECT prosrc LIKE '%auth.jwt()%'
        AND prosrc LIKE '%organization_id%'
        AND prosrc LIKE '%app_role%'
        AND prosrc LIKE '%user_profiles%'
     FROM pg_proc
     WHERE proname = 'require_catalog_manager'
       AND pronamespace = 'public'::regnamespace$$,
  'require_catalog_manager reads organization_id/app_role from JWT and the live profile'
);

SELECT tests.assert_true(
  $$SELECT prosrc LIKE '%auth.jwt()%'
        AND prosrc LIKE '%organization_id%'
        AND prosrc LIKE '%app_role%'
        AND prosrc LIKE '%user_profiles%'
     FROM pg_proc
     WHERE proname = 'require_tenant_admin'
       AND pronamespace = 'public'::regnamespace$$,
  'require_tenant_admin reads organization_id/app_role from JWT and the live profile'
);

-- ---------------------------------------------------------------------------
-- 2. Fixtures: Beta rows that Alpha must never see
-- ---------------------------------------------------------------------------

INSERT INTO public.organizations (id, name, slug, status)
VALUES
  (:'alpha_org_id'::uuid, 'Security Alpha', 'security-alpha', 'active'),
  (:'beta_org_id'::uuid, 'Security Beta', 'security-beta', 'active');

SELECT pg_temp.add_collaborator(
  :'alpha_admin_id'::uuid, :'alpha_org_id'::uuid,
  'admin-sec-alpha@test.invalid', 'Admin Sec Alpha', 'admin'
);
SELECT pg_temp.add_collaborator(
  :'alpha_operator_id'::uuid, :'alpha_org_id'::uuid,
  'operador-sec-alpha@test.invalid', 'Operador Sec Alpha', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'alpha_agent_id'::uuid, :'alpha_org_id'::uuid,
  'agente-sec-alpha@test.invalid', 'Agente Sec Alpha', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'beta_admin_id'::uuid, :'beta_org_id'::uuid,
  'admin-sec-beta@test.invalid', 'Admin Sec Beta', 'admin'
);

INSERT INTO public.providers (id, organization_id, name)
VALUES (:'beta_provider_id'::uuid, :'beta_org_id'::uuid, 'Proveedor Beta');

INSERT INTO public.add_ons (id, organization_id, name, unit, is_active)
VALUES (:'beta_addon_id'::uuid, :'beta_org_id'::uuid, 'Transporte Beta', 'per_service', true);

INSERT INTO public.products (id, organization_id, type, name, status)
VALUES
  (:'beta_product_id'::uuid, :'beta_org_id'::uuid, 'experience', 'Rafting Beta Sec', 'draft'),
  (:'beta_package_id'::uuid, :'beta_org_id'::uuid, 'package', 'Paquete Beta Sec', 'draft');

INSERT INTO public.experiences (
  id, organization_id, duration_minutes, min_capacity, max_capacity
)
VALUES (:'beta_product_id'::uuid, :'beta_org_id'::uuid, 60, 1, 4);

INSERT INTO public.packages (id, organization_id, total_days, total_nights)
VALUES (:'beta_package_id'::uuid, :'beta_org_id'::uuid, 2, 1);

INSERT INTO public.package_items (
  package_id, component_product_id, organization_id, sort_order, day_number
)
VALUES (
  :'beta_package_id'::uuid, :'beta_product_id'::uuid, :'beta_org_id'::uuid, 0, 1
);

INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type
)
VALUES (:'beta_org_id'::uuid, :'beta_product_id'::uuid, 'USD', 99, 'per_person');

-- ---------------------------------------------------------------------------
-- 3. Alpha operator: tenant isolation of remaining tables + US2 link rules
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'alpha_operator_id'::uuid, :'alpha_org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.providers WHERE id = %L', :'beta_provider_id'),
  'providers: fetching Beta by id returns no row'
);

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.add_ons WHERE id = %L', :'beta_addon_id'),
  'add_ons: fetching Beta by id returns no row'
);

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.pricing_schemes WHERE product_id = %L', :'beta_product_id'),
  'pricing_schemes: fetching Beta tariffs by product id returns no row'
);

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.packages WHERE id = %L', :'beta_package_id'),
  'packages: fetching Beta by id returns no row'
);

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.package_items WHERE package_id = %L', :'beta_package_id'),
  'package_items: fetching Beta itinerary by package id returns no row'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 0 FROM public.resolve_price(%L::uuid, '2026-06-01', 'per_person')$sql$,
    :'beta_product_id'
  ),
  'resolve_price on a foreign product_id returns no row (RLS on pricing_schemes)'
);

SELECT (public.create_product(
  'experience',
  'Caminata Security Alpha',
  NULL,
  NULL,
  '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 90,
    'difficulty', 'easy',
    'meeting_point', 'Mirador',
    'min_capacity', 1,
    'max_capacity', 8
  ),
  NULL
) ->> 'id') AS alpha_product_id \gset

INSERT INTO public.add_ons (organization_id, name, unit, is_active)
VALUES (:'alpha_org_id'::uuid, 'Transporte privado', 'per_service', true)
RETURNING id AS alpha_addon_id \gset

INSERT INTO public.product_addons (
  product_id, addon_id, organization_id, is_mandatory, max_quantity
)
VALUES (
  :'alpha_product_id'::uuid, :'alpha_addon_id'::uuid, :'alpha_org_id'::uuid, true, 2
);

SELECT tests.assert_true(
  format(
    $sql$SELECT is_mandatory AND max_quantity = 2
         FROM public.product_addons
         WHERE product_id = %L AND addon_id = %L$sql$,
    :'alpha_product_id',
    :'alpha_addon_id'
  ),
  'operator can link an add-on with is_mandatory and max_quantity'
);

SELECT tests.assert_raises(
  format(
    $sql$INSERT INTO public.product_addons (
           product_id, addon_id, organization_id, is_mandatory
         )
         VALUES (%L, %L, %L, false)$sql$,
    :'alpha_product_id',
    :'beta_addon_id',
    :'alpha_org_id'
  ),
  'product_addons_addon_tenant_fkey',
  'product_addons cannot attach a foreign add-on (composite FK pins tenant)'
);

SELECT public.upsert_pricing_scheme(
  :'alpha_product_id'::uuid, NULL, 'COP', 10000, 'per_person', NULL, NULL
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.apply_price_override(%L::uuid, 1, 'no')$sql$,
    :'alpha_product_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an operator cannot apply a manual price override'
);

-- ---------------------------------------------------------------------------
-- 4. Agent is catalog-read-only (FR-008)
-- ---------------------------------------------------------------------------

RESET ROLE;
SELECT pg_temp.act_as(:'alpha_agent_id'::uuid, :'alpha_org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 1 FROM public.add_ons WHERE id = %L$sql$,
    :'alpha_addon_id'
  ),
  'an agent can read add-ons of its own tenant'
);

SELECT tests.assert_raises(
  format(
    $sql$INSERT INTO public.add_ons (organization_id, name, unit)
         VALUES (%L, 'Intruso', 'per_unit')$sql$,
    :'alpha_org_id'
  ),
  'row-level security',
  'an agent cannot insert an add-on'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.upsert_pricing_scheme(%L::uuid, NULL, 'COP', 1, 'per_person', NULL, NULL)$sql$,
    :'alpha_product_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot define a pricing scheme'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $sql$SELECT name = 'Transporte Beta' FROM public.add_ons WHERE id = %L$sql$,
    :'beta_addon_id'
  ),
  'Beta add-on is unchanged after every Alpha attempt'
);

\echo '--- catalog_security_review_test: all assertions passed ---'

ROLLBACK;
