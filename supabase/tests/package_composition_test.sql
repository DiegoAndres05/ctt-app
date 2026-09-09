-- package_composition_test.sql
-- User Story 3: create_package composition (experience + nights of accommodation), reject
-- nested packages (PACKAGE_NESTING_NOT_ALLOWED), reject cross-org components, and report
-- inactive components via get_package_consistency without auto-deactivating the package (R-008).
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/package_composition_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set org_id           55555555-5555-4000-a000-000000000055
\set other_org_id     66666666-6666-4000-a000-000000000066
\set admin_id         55555555-5555-4000-b000-000000000051
\set operator_id      55555555-5555-4000-b000-000000000052
\set agent_id         55555555-5555-4000-b000-000000000053
\set other_admin_id   66666666-6666-4000-b000-000000000061
\set other_product_id 66666666-6666-4000-e000-000000000061

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

INSERT INTO public.organizations (id, name, slug, status)
VALUES
  (:'org_id'::uuid, 'Package Alpha', 'package-alpha', 'active'),
  (:'other_org_id'::uuid, 'Package Beta', 'package-beta', 'active');

SELECT pg_temp.add_collaborator(
  :'admin_id'::uuid, :'org_id'::uuid,
  'admin-pkg@test.invalid', 'Admin Package', 'admin'
);
SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid,
  'operador-pkg@test.invalid', 'Operador Package', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'agent_id'::uuid, :'org_id'::uuid,
  'agente-pkg@test.invalid', 'Agente Package', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'other_admin_id'::uuid, :'other_org_id'::uuid,
  'admin-pkg-beta@test.invalid', 'Admin Package Beta', 'admin'
);

INSERT INTO public.products (id, organization_id, type, name, status)
VALUES (
  :'other_product_id'::uuid, :'other_org_id'::uuid, 'experience', 'Rafting Beta', 'draft'
);

INSERT INTO public.experiences (
  id, organization_id, duration_minutes, difficulty, meeting_point, min_capacity, max_capacity
)
VALUES (
  :'other_product_id'::uuid, :'other_org_id'::uuid, 120, 'easy', 'Rio Beta', 1, 8
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

-- ===========================================================================
-- 1. Operator creates a package: experience + two nights of accommodation
-- ===========================================================================

\echo '--- create_package: experience + accommodation nights ---'

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience',
  'Caminata de bosque',
  NULL,
  NULL,
  '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 180,
    'difficulty', 'moderate',
    'meeting_point', 'Mirador',
    'min_capacity', 2,
    'max_capacity', 10
  ),
  NULL
) ->> 'id') AS experience_id \gset

SELECT (public.create_product(
  'accommodation',
  'Cabaña del valle',
  NULL,
  NULL,
  '{}'::uuid[],
  NULL,
  jsonb_build_object(
    'property_type', 'cabana',
    'location', 'Valle',
    'max_occupancy', 4
  )
) ->> 'id') AS accommodation_id \gset

SELECT (public.create_package(
  'Fin de semana en el valle',
  'Una experiencia y dos noches de cabaña',
  NULL,
  '{}'::uuid[],
  3,
  2,
  jsonb_build_array(
    jsonb_build_object(
      'component_product_id', :'experience_id'::uuid,
      'sort_order', 0,
      'day_number', 1
    ),
    jsonb_build_object(
      'component_product_id', :'accommodation_id'::uuid,
      'sort_order', 1,
      'day_number', 1
    )
  )
) ->> 'id') AS package_id \gset

SELECT tests.assert_true(
  format(
    $sql$SELECT type = 'package' AND status = 'draft' AND organization_id = %L
         FROM public.products WHERE id = %L$sql$,
    :'org_id',
    :'package_id'
  ),
  'create_package stores a draft product of type package in the caller''s tenant'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT total_days = 3 AND total_nights = 2 AND organization_id = %L
         FROM public.packages WHERE id = %L$sql$,
    :'org_id',
    :'package_id'
  ),
  'package itinerary metadata is stored atomically'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 2 FROM public.package_items WHERE package_id = %L$sql$,
    :'package_id'
  ),
  'package_items are created for the experience and the accommodation'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT (public.get_package_consistency(%L::uuid) -> 'packages' -> 0 ->> 'consistent')::boolean$sql$,
    :'package_id'
  ),
  'a package whose components are not inactive is consistent'
);

-- ===========================================================================
-- 2. Nested packages are rejected
-- ===========================================================================

\echo '--- PACKAGE_NESTING_NOT_ALLOWED ---'

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.create_package(
      'Paquete anidado',
      NULL,
      NULL,
      '{}'::uuid[],
      1,
      0,
      jsonb_build_array(
        jsonb_build_object('component_product_id', %L::uuid, 'sort_order', 0, 'day_number', 1)
      )
    )$sql$,
    :'package_id'
  ),
  'PACKAGE_NESTING_NOT_ALLOWED',
  'create_package rejects a package as a component'
);

-- ===========================================================================
-- 3. Cross-org components are rejected without leaking the foreign id
-- ===========================================================================

\echo '--- cross-org component ---'

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.create_package(
      'Paquete ajeno',
      NULL,
      NULL,
      '{}'::uuid[],
      1,
      0,
      jsonb_build_array(
        jsonb_build_object('component_product_id', %L::uuid, 'sort_order', 0, 'day_number', 1)
      )
    )$sql$,
    :'other_product_id'
  ),
  'VALIDATION_ERROR',
  'create_package rejects a component that belongs to another organization'
);

-- ===========================================================================
-- 4. Agent cannot compose packages
-- ===========================================================================

\echo '--- agent cannot create_package ---'

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.create_package(
      'Paquete agente',
      NULL,
      NULL,
      '{}'::uuid[],
      1,
      0,
      jsonb_build_array(
        jsonb_build_object('component_product_id', %L::uuid, 'sort_order', 0, 'day_number', 1)
      )
    )$sql$,
    :'experience_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot create a package'
);

-- ===========================================================================
-- 5. Deactivating a component warns; the package is not auto-deactivated
-- ===========================================================================

\echo '--- get_package_consistency warning, no auto-deactivate ---'

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');

SELECT public.set_product_status(:'experience_id'::uuid, 'inactive');

SELECT tests.assert_true(
  format(
    $sql$SELECT status = 'inactive' FROM public.products WHERE id = %L$sql$,
    :'experience_id'
  ),
  'the component was deactivated'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT status = 'draft' FROM public.products WHERE id = %L$sql$,
    :'package_id'
  ),
  'deactivating a component does not change the package status'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT (public.get_package_consistency(%L::uuid) -> 'packages' -> 0 ->> 'consistent') = 'false'
         AND (public.get_package_consistency(%L::uuid) -> 'packages' -> 0 -> 'inactive_components' -> 0 ->> 'product_id') = %L$sql$,
    :'package_id',
    :'package_id',
    :'experience_id'
  ),
  'get_package_consistency reports the inactive component as a warning'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT bool_or((pkg ->> 'package_id') = %L AND (pkg ->> 'consistent') = 'false')
         FROM jsonb_array_elements(public.get_package_consistency(NULL) -> 'packages') AS pkg$sql$,
    :'package_id'
  ),
  'get_package_consistency without an id includes the inconsistent package'
);

RESET ROLE;

ROLLBACK;
