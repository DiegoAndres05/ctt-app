-- public_sold_out_test.sql
-- Sold-out listings stay visible with acceptsRequests=false; product status and tariff unchanged.
--
-- Run with: ./supabase/tests/run-sql-tests.sh public_sold_out_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id       99999999-9999-4000-a000-000000000099
\set operator_id  99999999-9999-4000-b000-000000000091
\set admin_id     99999999-9999-4000-b000-000000000092

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
VALUES (
  :'org_id'::uuid, 'Sold Out Org', 'sold-out-org', 'active',
  jsonb_build_object('default_currency', 'COP')
);

SELECT pg_temp.add_collaborator(
  :'operator_id'::uuid, :'org_id'::uuid,
  'operador-soldout@test.invalid', 'Operador SoldOut', 'operator'
);
SELECT pg_temp.add_collaborator(
  :'admin_id'::uuid, :'org_id'::uuid,
  'admin-soldout@test.invalid', 'Admin SoldOut', 'admin'
);

SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience',
  'Sold Out Offer',
  NULL,
  NULL,
  '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 120,
    'difficulty', 'easy',
    'meeting_point', 'Muelle',
    'min_capacity', 1,
    'max_capacity', 8
  ),
  NULL
) ->> 'id') AS product_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'org_id'::uuid, :'product_id'::uuid, 200000, 'per_person');
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'sold-out-offer',
  'name_es', 'Agotada',
  'name_en', 'Sold Out',
  'description_es', 'Desc',
  'description_en', 'Desc',
  'public_category_id', 'islas',
  'location', 'Islas',
  'display_price', 200000,
  'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Guía', 'en', 'Guide'))
)) ->> 'id') AS listing_id \gset

SELECT public.attach_public_image(
  :'listing_id'::uuid, 'cover', NULL, '/images/sold-out-offer.jpg', 0
);
SELECT public.publish_public_listing(:'listing_id'::uuid);

SELECT count(*)::bigint AS scheme_count_before
FROM public.pricing_schemes
WHERE product_id = :'product_id'::uuid \gset

SELECT public.set_public_listing_sold_out(:'listing_id'::uuid, true);

SELECT tests.assert_true(
  format(
    $sql$SELECT sold_out = true AND status = 'published'
         FROM public.public_listings WHERE id = %L$sql$,
    :'listing_id'
  ),
  'sold_out flag is set while listing stays published'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT status = 'active' FROM public.products WHERE id = %L$sql$,
    :'product_id'
  ),
  'product status remains active when marking sold out'
);

SELECT tests.assert_true(
  format(
    $sql$SELECT count(*) = %s::bigint FROM public.pricing_schemes WHERE product_id = %L$sql$,
    :'scheme_count_before',
    :'product_id'
  ),
  'pricing_schemes is unchanged by sold_out toggle'
);

-- Force panel source so anon projection includes the listing
RESET ROLE;
UPDATE public.public_sites
SET source = 'panel', cutover_completed_at = now(), cutover_completed_by = :'admin_id'::uuid
WHERE organization_id = :'org_id'::uuid;

SELECT pg_temp.clear_jwt();
SET LOCAL ROLE anon;

SELECT tests.assert_true(
  format(
    $sql$SELECT (o ->> 'soldOut')::boolean = true
         AND (o ->> 'acceptsRequests')::boolean = false
         AND o ->> 'id' = 'sold-out-offer'
         FROM jsonb_array_elements(public.get_public_site(%L::uuid) -> 'offers') o
         LIMIT 1$sql$,
    :'org_id'
  ),
  'public projection shows soldOut=true and acceptsRequests=false'
);

RESET ROLE;
SELECT pg_temp.act_as(:'operator_id'::uuid, :'org_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.set_public_listing_sold_out(:'listing_id'::uuid, false);

RESET ROLE;
SELECT pg_temp.clear_jwt();
SET LOCAL ROLE anon;

SELECT tests.assert_true(
  format(
    $sql$SELECT (o ->> 'soldOut')::boolean = false
         AND (o ->> 'acceptsRequests')::boolean = true
         FROM jsonb_array_elements(public.get_public_site(%L::uuid) -> 'offers') o
         LIMIT 1$sql$,
    :'org_id'
  ),
  'clearing sold_out restores acceptsRequests=true'
);

RESET ROLE;
ROLLBACK;
