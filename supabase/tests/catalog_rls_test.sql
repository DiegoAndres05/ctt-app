-- catalog_rls_test.sql
-- Multi-tenant isolation of catalog rows (products, subtypes, categories) required by SC-002
-- and User Story 1: a session of one organization never sees or mutates another organization's
-- catalog, including when it asks for a foreign id directly (empty result, not a leak).
--
-- Two agencies are created, then every reachable catalog operation is attempted from a session
-- belonging to the first one against data belonging to the second. Nothing here relies on
-- application code: the only thing under test is what the database itself allows a session
-- holding a given set of JWT claims to see and change.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/catalog_rls_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set alpha_org_id     11111111-1111-4000-a000-000000000011
\set beta_org_id      22222222-2222-4000-a000-000000000012
\set alpha_admin_id   11111111-1111-4000-b000-000000000011
\set alpha_operator_id 11111111-1111-4000-b000-000000000012
\set alpha_agent_id   11111111-1111-4000-b000-000000000013
\set beta_admin_id    22222222-2222-4000-b000-000000000011
\set alpha_category_id 11111111-1111-4000-d000-000000000011
\set beta_category_id  22222222-2222-4000-d000-000000000012
\set beta_product_id   22222222-2222-4000-e000-000000000012
\set beta_accommodation_id 22222222-2222-4000-e000-000000000013

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
  (:'alpha_org_id'::uuid, 'Catalog Alpha', 'catalog-alpha', 'active'),
  (:'beta_org_id'::uuid, 'Catalog Beta', 'catalog-beta', 'active');

SELECT pg_temp.add_collaborator(
  :'alpha_admin_id'::uuid, :'alpha_org_id'::uuid,
  'admin-cat-alpha@test.invalid', 'Admin Cat Alpha', 'admin'
);
SELECT pg_temp.add_collaborator(
  :'alpha_operator_id'::uuid, :'alpha_org_id'::uuid,
  'operador-cat-alpha@test.invalid', 'Operador Cat Alpha', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'alpha_agent_id'::uuid, :'alpha_org_id'::uuid,
  'agente-cat-alpha@test.invalid', 'Agente Cat Alpha', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'beta_admin_id'::uuid, :'beta_org_id'::uuid,
  'admin-cat-beta@test.invalid', 'Admin Cat Beta', 'admin'
);

INSERT INTO public.categories (id, organization_id, name, slug)
VALUES
  (:'alpha_category_id'::uuid, :'alpha_org_id'::uuid, 'Aventura Alpha', 'aventura-alpha'),
  (:'beta_category_id'::uuid, :'beta_org_id'::uuid, 'Aventura Beta', 'aventura-beta');

-- Beta catalog fixture inserted as the table owner so RLS is not in play for setup.
INSERT INTO public.products (id, organization_id, type, name, status)
VALUES (
  :'beta_product_id'::uuid, :'beta_org_id'::uuid, 'experience', 'Rafting Beta', 'draft'
);

INSERT INTO public.experiences (
  id, organization_id, duration_minutes, difficulty, meeting_point, min_capacity, max_capacity
)
VALUES (
  :'beta_product_id'::uuid, :'beta_org_id'::uuid, 180, 'moderate', 'Rio Beta', 2, 8
);

INSERT INTO public.product_categories (product_id, category_id, organization_id)
VALUES (
  :'beta_product_id'::uuid, :'beta_category_id'::uuid,   :'beta_org_id'::uuid
);

INSERT INTO public.products (id, organization_id, type, name, status)
VALUES (
  :'beta_accommodation_id'::uuid, :'beta_org_id'::uuid, 'accommodation', 'Cabaña Beta', 'draft'
);

INSERT INTO public.accommodations (
  id, organization_id, property_type, location, max_occupancy
)
VALUES (
  :'beta_accommodation_id'::uuid, :'beta_org_id'::uuid, 'cabana', 'Bosque Beta', 4
);

-- ===========================================================================
-- 1. Alpha operator creates an experience; it is visible only to Alpha
-- ===========================================================================

\echo '--- Alpha operator creates a product ---'

SELECT pg_temp.act_as(:'alpha_operator_id'::uuid, :'alpha_org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience',
  'Caminata Alpha',
  'Sendero de bosque',
  NULL,
  ARRAY[:'alpha_category_id'::uuid],
  jsonb_build_object(
    'duration_minutes', 120,
    'difficulty', 'easy',
    'meeting_point', 'Mirador Alpha',
    'min_capacity', 1,
    'max_capacity', 12
  ),
  NULL
) ->> 'id') AS alpha_product_id \gset

SELECT tests.assert_true(
  format(
    $sql$SELECT status = 'draft' AND type = 'experience' AND organization_id = %L
         FROM public.products WHERE id = %L$sql$,
    :'alpha_org_id',
    :'alpha_product_id'
  ),
  'create_product stores a draft experience in the caller''s tenant'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 1 FROM public.experiences
         WHERE id = %L AND organization_id = %L$sql$,
    :'alpha_product_id',
    :'alpha_org_id'
  ),
  'the experience subtype row is created atomically'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT bool_and(organization_id = %L) AND count(*) = 1 FROM public.products$sql$,
    :'alpha_org_id'
  ),
  'products: an Alpha operator lists only Alpha products'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT bool_and(organization_id = %L) AND count(*) = 1 FROM public.experiences$sql$,
    :'alpha_org_id'
  ),
  'experiences: an Alpha operator lists only Alpha subtypes'
);

SELECT tests.assert_true(
  'SELECT count(*) = 0 FROM public.accommodations',
  'accommodations: an Alpha operator sees no Beta accommodations'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT bool_and(organization_id = %L) AND count(*) = 1 FROM public.categories$sql$,
    :'alpha_org_id'
  ),
  'categories: an Alpha operator lists only Alpha taxonomies'
);

-- ===========================================================================
-- 2. Direct access by foreign id yields nothing (SC-002)
-- ===========================================================================

\echo '--- direct access by foreign id ---'

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.products WHERE id = %L', :'beta_product_id'),
  'products: fetching Beta by its own id returns no row'
);

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.experiences WHERE id = %L', :'beta_product_id'),
  'experiences: fetching a Beta subtype by id returns no row'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 0 FROM public.accommodations WHERE id = %L',
    :'beta_accommodation_id'
  ),
  'accommodations: fetching a Beta subtype by id returns no row'
);

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.categories WHERE id = %L', :'beta_category_id'),
  'categories: fetching a Beta category by id returns no row'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 0 FROM public.product_categories WHERE product_id = %L',
    :'beta_product_id'
  ),
  'product_categories: fetching Beta tags by product id returns no row'
);

SELECT tests.assert_true(
  '(SELECT count(*) FROM public.products WHERE id = '
  || quote_literal(:'beta_product_id') || '::uuid)
   = (SELECT count(*) FROM public.products WHERE id = gen_random_uuid())',
  'a foreign product id and a non-existent id are indistinguishable'
);

-- ===========================================================================
-- 3. Writes cannot cross the tenant boundary
-- ===========================================================================

\echo '--- cross-tenant writes ---'

UPDATE public.products SET name = 'Owned by Alpha' WHERE id = :'beta_product_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'products: an Alpha operator cannot rename a Beta product'
);

UPDATE public.experiences SET duration_minutes = 15 WHERE id = :'beta_product_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'experiences: an Alpha operator cannot mutate a Beta subtype'
);

UPDATE public.categories SET name = 'Hijacked' WHERE id = :'beta_category_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'categories: an Alpha operator cannot rename a Beta category'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.set_product_status(%L::uuid, 'inactive')$sql$,
    :'beta_product_id'
  ),
  'VALIDATION_ERROR',
  'set_product_status on a foreign id does not disclose that the product exists'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.create_product(
      'experience',
      'Intruso',
      NULL,
      NULL,
      ARRAY[%L::uuid],
      jsonb_build_object(
        'duration_minutes', 60,
        'min_capacity', 1,
        'max_capacity', 2
      ),
      NULL
    )$sql$,
    :'beta_category_id'
  ),
  'VALIDATION_ERROR',
  'create_product rejects a category that belongs to another tenant'
);

-- ===========================================================================
-- 4. Activation without a current price is rejected (R-008)
-- ===========================================================================

\echo '--- activation requires a valid price ---'

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.set_product_status(%L::uuid, 'active')$sql$,
    :'alpha_product_id'
  ),
  'PRODUCT_HAS_NO_VALID_PRICE',
  'set_product_status refuses to activate a product without a current pricing scheme'
);

SELECT public.set_product_status(:'alpha_product_id'::uuid, 'inactive');

SELECT tests.assert_true(
  format(
    $sql$SELECT status = 'inactive' FROM public.products WHERE id = %L$sql$,
    :'alpha_product_id'
  ),
  'set_product_status can deactivate a draft product'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 1 FROM audit.audit_events
         WHERE event_type = 'product_deactivated'
           AND resource_id = %L
           AND actor_id = %L$sql$,
    :'alpha_product_id',
    :'alpha_operator_id'
  ),
  'deactivating a product emits product_deactivated attributed to the operator'
);

-- ===========================================================================
-- 5. Agents may read the catalog but cannot manage it (FR-008)
-- ===========================================================================

\echo '--- agent is read-only ---'

RESET ROLE;
SELECT pg_temp.act_as(:'alpha_agent_id'::uuid, :'alpha_org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 1 FROM public.products WHERE organization_id = %L$sql$,
    :'alpha_org_id'
  ),
  'products: an agent can read its own tenant catalog'
);

SELECT tests.assert_raises(
  $sql$SELECT public.create_product(
    'accommodation',
    'Cabaña agente',
    NULL,
    NULL,
    '{}'::uuid[],
    NULL,
    jsonb_build_object(
      'property_type', 'cabana',
      'location', 'Bosque',
      'max_occupancy', 4
    )
  )$sql$,
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot create a product'
);

SELECT tests.assert_raises(
  format(
    $sql$INSERT INTO public.categories (organization_id, name, slug)
         VALUES (%L, 'Intrusa', 'intrusa')$sql$,
    :'alpha_org_id'
  ),
  'row-level security',
  'categories: an agent cannot insert a taxonomy'
);

-- ===========================================================================
-- 6. Sessions without a tenant claim see nothing
-- ===========================================================================

\echo '--- sessions with no tenant claim ---'

RESET ROLE;
SELECT pg_temp.act_as(:'alpha_operator_id'::uuid, NULL, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  'SELECT count(*) = 0 FROM public.products',
  'products: a session with no organization_id claim reads nothing'
);

SELECT tests.assert_true(
  'SELECT count(*) = 0 FROM public.categories',
  'categories: a session with no organization_id claim reads nothing'
);

RESET ROLE;

-- ===========================================================================
-- 7. Beta is intact
-- ===========================================================================

\echo '--- Beta is intact ---'

SELECT tests.assert_true(
  format(
    $sql$SELECT name = 'Rafting Beta' FROM public.products WHERE id = %L$sql$,
    :'beta_product_id'
  ),
  'Beta''s product name is unchanged after every attempt'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT name = 'Aventura Beta' FROM public.categories WHERE id = %L$sql$,
    :'beta_category_id'
  ),
  'Beta''s category name is unchanged after every attempt'
);

\echo '--- catalog_rls_test: all assertions passed ---'

ROLLBACK;
