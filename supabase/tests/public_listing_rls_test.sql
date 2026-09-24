-- public_listing_rls_test.sql
-- anon cannot read drafts/tariffs; cross-tenant isolation; agent gets FORBIDDEN on publish.
--
-- Run with: ./supabase/tests/run-sql-tests.sh public_listing_rls_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set alpha_org_id      66666666-6666-4000-a000-000000000066
\set beta_org_id       77777777-7777-4000-a000-000000000077
\set alpha_operator_id 66666666-6666-4000-b000-000000000061
\set alpha_agent_id    66666666-6666-4000-b000-000000000062
\set beta_operator_id  77777777-7777-4000-b000-000000000071
\set alpha_category_id 66666666-6666-4000-d000-000000000061

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

CREATE OR REPLACE FUNCTION pg_temp.clear_jwt()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.price_and_activate(
  p_organization_id uuid,
  p_product_id uuid,
  p_amount numeric,
  p_charge_type text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from, valid_to
  )
  VALUES (
    p_organization_id,
    p_product_id,
    'COP',
    p_amount,
    p_charge_type::public.charge_type,
    now() - interval '1 minute',
    NULL
  );

  UPDATE public.products
  SET status = 'active'
  WHERE id = p_product_id
    AND organization_id = p_organization_id;
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'alpha_org_id'::uuid, 'Public Alpha', 'public-alpha', 'active',
   jsonb_build_object('default_currency', 'COP')),
  (:'beta_org_id'::uuid, 'Public Beta', 'public-beta', 'active',
   jsonb_build_object('default_currency', 'COP'));

SELECT pg_temp.add_collaborator(
  :'alpha_operator_id'::uuid, :'alpha_org_id'::uuid,
  'operador-public-alpha@test.invalid', 'Operador Alpha', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'alpha_agent_id'::uuid, :'alpha_org_id'::uuid,
  'agente-public-alpha@test.invalid', 'Agente Alpha', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'beta_operator_id'::uuid, :'beta_org_id'::uuid,
  'operador-public-beta@test.invalid', 'Operador Beta', 'operator'
);

INSERT INTO public.categories (id, organization_id, name, slug)
VALUES (:'alpha_category_id'::uuid, :'alpha_org_id'::uuid, 'Islas Alpha', 'islas-alpha');

SELECT pg_temp.act_as(:'alpha_operator_id'::uuid, :'alpha_org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience',
  'Alpha Offer',
  NULL,
  NULL,
  ARRAY[:'alpha_category_id'::uuid],
  jsonb_build_object(
    'duration_minutes', 120,
    'difficulty', 'easy',
    'meeting_point', 'Alpha',
    'min_capacity', 1,
    'max_capacity', 8
  ),
  NULL
) ->> 'id') AS alpha_product_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'alpha_org_id'::uuid, :'alpha_product_id'::uuid, 111000, 'per_person');
SELECT pg_temp.act_as(:'alpha_operator_id'::uuid, :'alpha_org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'alpha_product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'alpha-offer',
  'name_es', 'Oferta Alpha',
  'name_en', 'Alpha Offer',
  'description_es', 'Desc ES',
  'description_en', 'Desc EN',
  'public_category_id', 'islas',
  'location', 'Cartagena',
  'display_price', 111000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Guía', 'en', 'Guide'))
)) ->> 'id') AS alpha_listing_id \gset

SELECT public.attach_public_image(
  :'alpha_listing_id'::uuid, 'cover', NULL, '/images/alpha-offer.jpg', 0
);
SELECT public.publish_public_listing(:'alpha_listing_id'::uuid);

-- Draft listing (not published)
SELECT (public.create_product(
  'experience',
  'Alpha Draft',
  NULL,
  NULL,
  '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 60,
    'difficulty', 'easy',
    'meeting_point', 'X',
    'min_capacity', 1,
    'max_capacity', 2
  ),
  NULL
) ->> 'id') AS draft_product_id \gset

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'draft_product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'alpha-draft',
  'name_es', 'Borrador',
  'name_en', 'Draft'
)) ->> 'id') AS draft_listing_id \gset

RESET ROLE;

-- ===========================================================================
-- 1. Agent FORBIDDEN on publish / save
-- ===========================================================================

\echo '--- agent forbidden ---'

SELECT pg_temp.act_as(:'alpha_agent_id'::uuid, :'alpha_org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.publish_public_listing(%L::uuid)$sql$,
    :'alpha_listing_id'
  ),
  'FORBIDDEN',
  'agent cannot publish'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.save_public_listing(jsonb_build_object(
      'product_id', %L::uuid,
      'placement', 'catalog',
      'public_slug', 'alpha-offer',
      'name_es', 'X', 'name_en', 'X',
      'description_es', 'X', 'description_en', 'X',
      'public_category_id', 'islas',
      'location', 'X',
      'display_price', 1,
      'currency', 'COP',
      'includes', jsonb_build_array(jsonb_build_object('es', 'A', 'en', 'A'))
    ))$sql$,
    :'alpha_product_id'
  ),
  'FORBIDDEN',
  'agent cannot save public listing'
);

RESET ROLE;

-- ===========================================================================
-- 2. Cross-tenant: Beta cannot see Alpha listings via RLS
-- ===========================================================================

\echo '--- cross-tenant ---'

SELECT pg_temp.act_as(:'beta_operator_id'::uuid, :'beta_org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = 0 FROM public.public_listings WHERE id = %L$sql$,
    :'alpha_listing_id'
  ),
  'beta operator cannot SELECT alpha public_listings'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.publish_public_listing(%L::uuid)$sql$,
    :'alpha_listing_id'
  ),
  'FORBIDDEN',
  'beta operator cannot publish alpha listing'
);

RESET ROLE;

-- ===========================================================================
-- 3. anon: get_public_site empty while legacy; no drafts/tariffs
-- ===========================================================================

\echo '--- anon isolation ---'

SELECT pg_temp.clear_jwt();
SET LOCAL ROLE anon;

SELECT tests.assert_true(
  format(
    $sql$SELECT (public.get_public_site(%L::uuid) ->> 'source') = 'legacy'
         AND jsonb_array_length(public.get_public_site(%L::uuid) -> 'offers') = 0$sql$,
    :'alpha_org_id',
    :'alpha_org_id'
  ),
  'anon get_public_site returns empty arrays while source=legacy'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT count(*) FROM public.public_listings WHERE id = %L$sql$,
    :'draft_listing_id'
  ),
  'permission denied',
  'anon cannot SELECT public_listings rows (including drafts)'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT count(*) FROM public.pricing_schemes WHERE product_id = %L$sql$,
    :'alpha_product_id'
  ),
  'permission denied',
  'anon cannot SELECT pricing_schemes'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT count(*) FROM public.products WHERE id = %L$sql$,
    :'alpha_product_id'
  ),
  'permission denied',
  'anon cannot SELECT products'
);

RESET ROLE;

-- Switch Alpha site to panel via SECURITY DEFINER path (owner bypass) for projection check
UPDATE public.public_sites
SET source = 'panel', cutover_completed_at = now(), cutover_completed_by = :'alpha_operator_id'::uuid
WHERE organization_id = :'alpha_org_id'::uuid;

SELECT pg_temp.clear_jwt();
SET LOCAL ROLE anon;

SELECT tests.assert_true(
  format(
    $sql$SELECT (public.get_public_site(%L::uuid) ->> 'source') = 'panel'
         AND jsonb_array_length(public.get_public_site(%L::uuid) -> 'offers') = 1
         AND (public.get_public_site(%L::uuid) -> 'offers' -> 0 ->> 'id') = 'alpha-offer'$sql$,
    :'alpha_org_id',
    :'alpha_org_id',
    :'alpha_org_id'
  ),
  'anon get_public_site projects only published active offers when source=panel'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT NOT EXISTS (
           SELECT 1
           FROM jsonb_array_elements(public.get_public_site(%L::uuid) -> 'offers') o
           WHERE o ->> 'id' = 'alpha-draft'
         )$sql$,
    :'alpha_org_id'
  ),
  'anon projection never includes draft listings'
);

RESET ROLE;
ROLLBACK;
