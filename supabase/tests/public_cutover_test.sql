-- public_cutover_test.sql
-- Cutover gate, successful cutover, initial tariff vs later display_price, yacht without
-- invented display price.
--
-- Run with: ./supabase/tests/run-sql-tests.sh public_cutover_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id       88888888-8888-4000-a000-000000000088
\set admin_id     88888888-8888-4000-b000-000000000081
\set operator_id  88888888-8888-4000-b000-000000000082

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
  :'org_id'::uuid, 'Cutover Org', 'cutover-org', 'active',
  jsonb_build_object('default_currency', 'COP')
);

SELECT pg_temp.add_collaborator(
  :'admin_id'::uuid, :'org_id'::uuid,
  'admin-cutover@test.invalid', 'Admin Cutover', 'admin'
);
SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid,
  'operador-cutover@test.invalid', 'Operador Cutover', 'operator'
);

-- Small manifesto for this test org (not the full CTT list)
INSERT INTO public.public_cutover_items (organization_id, public_slug, placement)
VALUES
  (:'org_id'::uuid, 'cutover-offer', 'catalog'),
  (:'org_id'::uuid, 'cutover-villa', 'lodging'),
  (:'org_id'::uuid, 'cutover-yacht', 'yacht');

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

-- ===========================================================================
-- 1. Incomplete cutover
-- ===========================================================================

\echo '--- incomplete cutover ---'

RESET ROLE;
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  'SELECT public.complete_public_cutover()',
  'CUTOVER_INCOMPLETE',
  'complete_public_cutover fails while manifesto items lack published active listings'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT source = 'legacy' FROM public.public_sites WHERE organization_id = %L$sql$,
    :'org_id'
  ),
  'source stays legacy after incomplete cutover attempt'
);

-- ===========================================================================
-- 2. Seed published manifesto items; yacht without display_price
-- ===========================================================================

\echo '--- publish manifesto items ---'

RESET ROLE;
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience', 'Cutover Offer', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 180, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 10
  ),
  NULL
) ->> 'id') AS offer_product_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'offer_product_id'::uuid, 500950, 'per_person');
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'offer_product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'cutover-offer',
  'name_es', 'Oferta', 'name_en', 'Offer',
  'description_es', 'Desc', 'description_en', 'Desc',
  'public_category_id', 'islas',
  'location', 'Islas',
  'display_price', 500950,
  'original_price', 625950,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Transporte', 'en', 'Transport'))
)) ->> 'id') AS offer_listing_id \gset

SELECT public.attach_public_image(
  :'offer_listing_id'::uuid, 'cover', NULL, '/images/cutover-offer.jpg', 0
);
SELECT public.publish_public_listing(:'offer_listing_id'::uuid);

SELECT (public.create_product(
  'accommodation', 'Cutover Villa', NULL, NULL, '{}'::uuid[],
  NULL,
  jsonb_build_object('property_type', 'villa', 'location', 'Bocagrande', 'max_occupancy', 6)
) ->> 'id') AS lodging_product_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'lodging_product_id'::uuid, 850000, 'per_night');
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'lodging_product_id'::uuid,
  'placement', 'lodging',
  'public_slug', 'cutover-villa',
  'name_es', 'Villa', 'name_en', 'Villa',
  'description_es', 'Desc', 'description_en', 'Desc',
  'max_guests', 6,
  'display_price', 850000,
  'currency', 'COP',
  'lodging', jsonb_build_object(
    'lodging_type', 'casa',
    'location_es', 'Cartagena', 'location_en', 'Cartagena',
    'neighborhood_es', 'Bocagrande', 'neighborhood_en', 'Bocagrande',
    'bedrooms', 3, 'bathrooms', 2,
    'amenities', jsonb_build_array('wifi'),
    'tags', jsonb_build_array('mar')
  )
)) ->> 'id') AS lodging_listing_id \gset

SELECT public.attach_public_image(
  :'lodging_listing_id'::uuid, 'cover', NULL, '/images/cutover-villa.jpg', 0
);
SELECT public.publish_public_listing(:'lodging_listing_id'::uuid);

SELECT (public.create_product(
  'experience', 'Cutover Yacht', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 240, 'difficulty', 'easy', 'meeting_point', 'Marina',
    'min_capacity', 1, 'max_capacity', 12
  ),
  NULL
) ->> 'id') AS yacht_product_id \gset

-- Yacht needs a real tariff from 002; no invented display_price on the listing
RESET ROLE;
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'yacht_product_id'::uuid, 4500000, 'per_group');
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'yacht_product_id'::uuid,
  'placement', 'yacht',
  'public_slug', 'cutover-yacht',
  'name_es', 'Yate', 'name_en', 'Yacht',
  'description_es', 'Desc', 'description_en', 'Desc',
  'yacht_lines', jsonb_build_array(
    jsonb_build_object(
      'kind', 'capacity', 'position', 0, 'icon', 'people',
      'text_es', '12 pax', 'text_en', '12 guests'
    ),
    jsonb_build_object(
      'kind', 'feature', 'position', 0, 'icon', 'boat',
      'text_es', 'Flybridge', 'text_en', 'Flybridge'
    )
  )
)) ->> 'id') AS yacht_listing_id \gset

SELECT tests.assert_true(
  format(
    $sql$SELECT display_price IS NULL AND currency IS NULL
         FROM public.public_listings WHERE id = %L$sql$,
    :'yacht_listing_id'
  ),
  'yacht listing has no invented display_price'
);

SELECT public.attach_public_image(
  :'yacht_listing_id'::uuid, 'cover', NULL, '/images/cutover-yacht.jpg', 0
);
SELECT public.publish_public_listing(:'yacht_listing_id'::uuid);

-- ===========================================================================
-- 3. Successful cutover + already completed
-- ===========================================================================

\echo '--- successful cutover ---'

RESET ROLE;
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  $sql$SELECT (public.complete_public_cutover() ->> 'source') = 'panel'$sql$,
  'complete_public_cutover switches source to panel'
);

SELECT tests.assert_raises(
  'SELECT public.complete_public_cutover()',
  'CUTOVER_ALREADY_COMPLETED',
  'second cutover call is rejected'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT jsonb_array_length(public.get_public_site(%L::uuid) -> 'offers') = 1
         AND jsonb_array_length(public.get_public_site(%L::uuid) -> 'lodgings') = 1
         AND jsonb_array_length(public.get_public_site(%L::uuid) -> 'yachts') = 1$sql$,
    :'org_id', :'org_id', :'org_id'
  ),
  'panel projection includes the three published manifesto listings'
);

-- ===========================================================================
-- 4. Initial tariff equals copied current price; later vitrina does not version
-- ===========================================================================

\echo '--- tariff vs later display_price ---'

RESET ROLE;
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT count(*)::bigint AS offer_schemes_before
FROM public.pricing_schemes
WHERE product_id = :'offer_product_id'::uuid \gset

SELECT public.save_public_listing(jsonb_build_object(
  'product_id', :'offer_product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'cutover-offer',
  'name_es', 'Oferta', 'name_en', 'Offer',
  'description_es', 'Desc', 'description_en', 'Desc',
  'public_category_id', 'islas',
  'location', 'Islas',
  'display_price', 999999,
  'original_price', 1200000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Transporte', 'en', 'Transport'))
));

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = %s::bigint FROM public.pricing_schemes WHERE product_id = %L$sql$,
    :'offer_schemes_before',
    :'offer_product_id'
  ),
  'later display_price edit does not version pricing_schemes'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT base_amount = 500950 AND valid_to IS NULL
         FROM public.pricing_schemes
         WHERE product_id = %L
         ORDER BY valid_from DESC LIMIT 1$sql$,
    :'offer_product_id'
  ),
  'initial tariff remains the copied current price (500950)'
);

RESET ROLE;
ROLLBACK;
