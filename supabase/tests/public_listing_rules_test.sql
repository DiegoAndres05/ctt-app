-- public_listing_rules_test.sql
-- Validation rules for public listings: bilingual pairs, original price, immutable slug,
-- placement vs product type, and display_price not versioning tariffs.
--
-- Run with: ./supabase/tests/run-sql-tests.sh public_listing_rules_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id          55555555-5555-4000-a000-000000000055
\set operator_id     55555555-5555-4000-b000-000000000051
\set category_id     55555555-5555-4000-d000-000000000051

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

-- upsert_pricing_scheme stamps valid_from with clock_timestamp() (after txn now()),
-- and pricing_schemes rows are append-only. Insert a past valid_from as owner instead.
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
VALUES (
  :'org_id'::uuid, 'Public Rules Org', 'public-rules-org', 'active',
  jsonb_build_object('default_currency', 'COP')
);

SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid,
  'operador-public-rules@test.invalid', 'Operador Public Rules', 'operator'
);

INSERT INTO public.categories (id, organization_id, name, slug)
VALUES (:'category_id'::uuid, :'org_id'::uuid, 'Aventura', 'aventura-rules');

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience',
  'Capri Rules',
  NULL,
  NULL,
  ARRAY[:'category_id'::uuid],
  jsonb_build_object(
    'duration_minutes', 240,
    'difficulty', 'easy',
    'meeting_point', 'Muelle',
    'min_capacity', 1,
    'max_capacity', 10
  ),
  NULL
) ->> 'id') AS experience_id \gset

SELECT (public.create_product(
  'accommodation',
  'Casa Rules',
  NULL,
  NULL,
  '{}'::uuid[],
  NULL,
  jsonb_build_object(
    'property_type', 'casa',
    'location', 'Centro',
    'max_occupancy', 4
  )
) ->> 'id') AS accommodation_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'experience_id'::uuid, 100000, 'per_person');
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'accommodation_id'::uuid, 200000, 'per_night');
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

-- ===========================================================================
-- 1. PLACEMENT_PRODUCT_MISMATCH
-- ===========================================================================

\echo '--- placement vs product type ---'

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.save_public_listing(jsonb_build_object(
      'product_id', %L::uuid,
      'placement', 'lodging',
      'public_slug', 'wrong-placement',
      'name_es', 'X', 'name_en', 'X',
      'description_es', 'X', 'description_en', 'X'
    ))$sql$,
    :'experience_id'
  ),
  'PLACEMENT_PRODUCT_MISMATCH',
  'experience cannot use lodging placement'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.save_public_listing(jsonb_build_object(
      'product_id', %L::uuid,
      'placement', 'catalog',
      'public_slug', 'wrong-placement-2',
      'name_es', 'X', 'name_en', 'X',
      'description_es', 'X', 'description_en', 'X',
      'public_category_id', 'islas'
    ))$sql$,
    :'accommodation_id'
  ),
  'PLACEMENT_PRODUCT_MISMATCH',
  'accommodation cannot use catalog placement'
);

-- ===========================================================================
-- 2. Bilingual pairs + ORIGINAL_PRICE_NOT_HIGHER
-- ===========================================================================

\echo '--- bilingual pairs and original price ---'

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.save_public_listing(jsonb_build_object(
      'product_id', %L::uuid,
      'placement', 'catalog',
      'public_slug', 'capri-rules',
      'name_es', 'Capri', 'name_en', 'Capri',
      'description_es', 'Desc', 'description_en', 'Desc',
      'public_category_id', 'islas',
      'location', 'Islas',
      'display_price', 100000,
      'currency', 'COP',
      'includes', jsonb_build_array(jsonb_build_object('es', 'Transporte', 'en', ''))
    ))$sql$,
    :'experience_id'
  ),
  'BILINGUAL_PAIR_INCOMPLETE',
  'incomplete includes pair is rejected'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.save_public_listing(jsonb_build_object(
      'product_id', %L::uuid,
      'placement', 'catalog',
      'public_slug', 'capri-rules',
      'name_es', 'Capri', 'name_en', 'Capri',
      'description_es', 'Desc', 'description_en', 'Desc',
      'public_category_id', 'islas',
      'location', 'Islas',
      'display_price', 100000,
      'original_price', 90000,
      'currency', 'COP',
      'includes', jsonb_build_array(jsonb_build_object('es', 'Transporte', 'en', 'Transport'))
    ))$sql$,
    :'experience_id'
  ),
  'ORIGINAL_PRICE_NOT_HIGHER',
  'original_price must exceed display_price'
);

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'experience_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'capri-rules',
  'name_es', 'Capri',
  'name_en', 'Capri EN',
  'description_es', 'Descripción',
  'description_en', 'Description',
  'public_category_id', 'islas',
  'location', 'Islas del Rosario',
  'display_price', 100000,
  'original_price', 150000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Transporte', 'en', 'Transport')),
  'warnings', '[]'::jsonb
)) ->> 'id') AS listing_id \gset

SELECT public.attach_public_image(
  :'listing_id'::uuid, 'cover', NULL, '/images/capri-rules.jpg', 0
);

SELECT public.publish_public_listing(:'listing_id'::uuid);

-- ===========================================================================
-- 3. PUBLIC_SLUG_IMMUTABLE after first publish
-- ===========================================================================

\echo '--- slug immutable ---'

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.save_public_listing(jsonb_build_object(
      'product_id', %L::uuid,
      'placement', 'catalog',
      'public_slug', 'capri-rules-renamed',
      'name_es', 'Capri', 'name_en', 'Capri EN',
      'description_es', 'Descripción', 'description_en', 'Description',
      'public_category_id', 'islas',
      'location', 'Islas del Rosario',
      'display_price', 100000,
      'currency', 'COP',
      'includes', jsonb_build_array(jsonb_build_object('es', 'Transporte', 'en', 'Transport'))
    ))$sql$,
    :'experience_id'
  ),
  'PUBLIC_SLUG_IMMUTABLE',
  'slug cannot change after first_published_at'
);

-- ===========================================================================
-- 4. Display price change does not version pricing_schemes
-- ===========================================================================

\echo '--- display price vs tariff ---'

SELECT count(*)::bigint AS scheme_count_before
FROM public.pricing_schemes
WHERE product_id = :'experience_id'::uuid \gset

SELECT public.save_public_listing(jsonb_build_object(
  'product_id', :'experience_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'capri-rules',
  'name_es', 'Capri',
  'name_en', 'Capri EN',
  'description_es', 'Descripción',
  'description_en', 'Description',
  'public_category_id', 'islas',
  'location', 'Islas del Rosario',
  'display_price', 222222,
  'original_price', 333333,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Transporte', 'en', 'Transport'))
));

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = %s::bigint FROM public.pricing_schemes WHERE product_id = %L$sql$,
    :'scheme_count_before',
    :'experience_id'
  ),
  'editing display_price does not insert a new pricing_schemes row'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT display_price = 222222 FROM public.public_listings WHERE id = %L$sql$,
    :'listing_id'
  ),
  'display_price on the listing is updated'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT base_amount = 100000 AND valid_to IS NULL
         FROM public.pricing_schemes
         WHERE product_id = %L
         ORDER BY valid_from DESC LIMIT 1$sql$,
    :'experience_id'
  ),
  'current tariff amount is unchanged after display_price edit'
);

-- Incomplete publish
SELECT (public.create_product(
  'experience',
  'Incomplete Capri',
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
) ->> 'id') AS incomplete_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'incomplete_id'::uuid, 50000, 'per_person');
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'incomplete_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'incomplete-capri',
  'name_es', 'Solo ES',
  'name_en', 'Only EN'
)) ->> 'id') AS incomplete_listing_id \gset

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.publish_public_listing(%L::uuid)$sql$,
    :'incomplete_listing_id'
  ),
  'PUBLIC_LISTING_INCOMPLETE',
  'publish rejects incomplete catalog listing'
);

RESET ROLE;
ROLLBACK;
