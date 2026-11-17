-- public_cms_config_test.sql
-- Feature 016, US1 + foundational isolation: agency-owned categories, lodging types and
-- amenities; defaults for a new agency; role permissions; used-value protection.
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/public_cms_config_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a        16000000-0000-4000-a000-000000000001
\set org_b        16000000-0000-4000-a000-000000000002
\set admin_a      16000000-0000-4000-b000-000000000011
\set operator_a   16000000-0000-4000-b000-000000000012
\set agent_a      16000000-0000-4000-b000-000000000013
\set operator_b   16000000-0000-4000-b000-000000000021

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

CREATE OR REPLACE FUNCTION pg_temp.act_anon()
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
    p_organization_id, p_product_id, 'COP', p_amount,
    p_charge_type::public.charge_type, now() - interval '1 minute', NULL
  );

  UPDATE public.products
  SET status = 'active'
  WHERE id = p_product_id
    AND organization_id = p_organization_id;
END;
$$;

-- Captures the error message of a statement (NULL when it succeeds).
CREATE OR REPLACE FUNCTION pg_temp.error_of(p_statement text)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE p_statement;
  RETURN NULL;
EXCEPTION
  WHEN others THEN
    RETURN SQLSTATE || ':' || SQLERRM;
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_a'::uuid, 'Agencia Uno', 'agencia-uno-016', 'active', '{"default_currency":"USD"}'::jsonb),
  (:'org_b'::uuid, 'Agencia Dos', 'agencia-dos-016', 'active', '{}'::jsonb);

SELECT pg_temp.add_collaborator(:'admin_a'::uuid, :'org_a'::uuid, 'admin-a@016.invalid', 'Admin A', 'admin');
SELECT pg_temp.add_collaborator(:'operator_a'::uuid, :'org_a'::uuid, 'op-a@016.invalid', 'Operador A', 'operator');
SELECT pg_temp.add_collaborator(:'agent_a'::uuid, :'org_a'::uuid, 'agent-a@016.invalid', 'Agente A', 'agent');
SELECT pg_temp.add_collaborator(:'operator_b'::uuid, :'org_b'::uuid, 'op-b@016.invalid', 'Operador B', 'operator');

-- ===========================================================================
-- 1. A new agency starts with an editable, generic set (FR-002, FR-006)
-- ===========================================================================

\echo '--- defaults for a new agency ---'

SELECT tests.assert_true(
  format($sql$SELECT count(*) = 7 AND bool_and(NOT protected) AND bool_and(is_active)
               FROM public.public_categories WHERE organization_id = %L$sql$, :'org_a'),
  'a new agency gets seven unprotected example categories'
);

SELECT tests.assert_true(
  format($sql$SELECT NOT EXISTS (SELECT 1 FROM public.public_categories
               WHERE organization_id = %L AND id IN ('islas', 'baru', 'tierra_bomba', 'baile'))$sql$, :'org_a'),
  'CTT-only categories are not imposed on a new agency'
);

SELECT tests.assert_true(
  format($sql$SELECT array_agg(code ORDER BY code) @> ARRAY['apartamento', 'casa', 'finca', 'habitacion', 'hotel']
               FROM public.public_taxonomy_values WHERE organization_id = %L AND kind = 'lodging_type'$sql$, :'org_a'),
  'lodging types include casa, apartamento, finca, habitacion and hotel'
);

SELECT tests.assert_true(
  format($sql$SELECT array_agg(code ORDER BY code) @> ARRAY['ac', 'kitchen', 'parking', 'pool', 'sea_view', 'wifi']
               FROM public.public_taxonomy_values WHERE organization_id = %L AND kind = 'amenity'$sql$, :'org_a'),
  'amenities include wifi, pool, ac, kitchen, parking and sea_view'
);

SELECT tests.assert_true(
  format($sql$SELECT commercial_name = 'Agencia Uno' AND currency = 'USD' AND languages = ARRAY['es', 'en']
               FROM public.public_profiles WHERE organization_id = %L$sql$, :'org_a'),
  'a new agency gets a public profile from its name and default currency'
);

SELECT tests.assert_true(
  format($sql$SELECT NOT migration_required AND organization_identifier_until IS NULL
               FROM public.public_source_config WHERE organization_id = %L$sql$, :'org_a'),
  'a new agency publishes directly and has no organization-identifier access'
);

-- ===========================================================================
-- 2. Same code in two agencies, no shared rows (FR-009, FR-024)
-- ===========================================================================

\echo '--- agency-local codes ---'

SELECT pg_temp.act_as(:'operator_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.save_public_category('{"id":"buceo","name_es":"Buceo","name_en":"Diving"}'::jsonb);
SELECT public.save_public_taxonomy_value('{"kind":"amenity","code":"jacuzzi","name_es":"Jacuzzi","name_en":"Hot tub"}'::jsonb);

RESET ROLE;
SELECT pg_temp.act_as(:'operator_b'::uuid, :'org_b'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT public.save_public_category('{"id":"buceo","name_es":"Buceo B","name_en":"Diving B"}'::jsonb);
SELECT public.save_public_taxonomy_value('{"kind":"amenity","code":"solo_b","name_es":"Solo B","name_en":"Only B"}'::jsonb);

SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 AND min(name_es) = 'Buceo B' FROM public.public_categories WHERE id = 'buceo'$sql$,
  'agency B sees only its own «buceo» category'
);

SELECT tests.assert_true(
  $sql$SELECT NOT EXISTS (SELECT 1 FROM public.public_taxonomy_values WHERE code = 'jacuzzi')$sql$,
  'agency B cannot read agency A amenities'
);

SELECT tests.assert_raises(
  $sql$SELECT public.delete_public_taxonomy_value('amenity', 'jacuzzi')$sql$,
  'VALIDATION_ERROR',
  'agency B cannot delete an agency A value'
);

SELECT tests.assert_raises(
  $sql$INSERT INTO public.public_taxonomy_values (organization_id, kind, code, name_es, name_en)
       VALUES ('16000000-0000-4000-a000-000000000001', 'amenity', 'intruso', 'X', 'X')$sql$,
  'permission denied',
  'direct writes to taxonomy values are not granted'
);

RESET ROLE;

SELECT tests.assert_true(
  format($sql$SELECT name_es = 'Buceo' FROM public.public_categories WHERE organization_id = %L AND id = 'buceo'$sql$, :'org_a'),
  'agency A category is untouched by agency B'
);

-- ===========================================================================
-- 3. Roles (FR-003, FR-007)
-- ===========================================================================

\echo '--- roles ---'

SELECT pg_temp.act_as(:'agent_a'::uuid, :'org_a'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  $sql$SELECT public.save_public_category('{"id":"x_agent","name_es":"X","name_en":"X"}'::jsonb)$sql$,
  'FORBIDDEN', 'an agent cannot create categories'
);
SELECT tests.assert_raises(
  $sql$SELECT public.save_public_taxonomy_value('{"kind":"amenity","code":"x_agent","name_es":"X","name_en":"X"}'::jsonb)$sql$,
  'FORBIDDEN', 'an agent cannot create amenities'
);
SELECT tests.assert_raises(
  $sql$SELECT public.delete_public_taxonomy_value('amenity', 'jacuzzi')$sql$,
  'FORBIDDEN', 'an agent cannot delete amenities'
);
SELECT tests.assert_raises(
  $sql$SELECT public.delete_public_category('buceo')$sql$,
  'FORBIDDEN', 'an agent cannot delete categories'
);
SELECT tests.assert_true(
  $sql$SELECT jsonb_array_length(public.list_public_taxonomy_values()) >= 15$sql$,
  'an agent can still read the taxonomy for its agency'
);

RESET ROLE;
SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT public.save_public_taxonomy_value('{"kind":"lodging_type","code":"glamping","name_es":"Glamping","name_en":"Glamping"}'::jsonb);

SELECT tests.assert_true(
  $sql$SELECT EXISTS (SELECT 1 FROM public.public_taxonomy_values WHERE kind = 'lodging_type' AND code = 'glamping')$sql$,
  'an administrator can create lodging types'
);

-- ===========================================================================
-- 4. Validation
-- ===========================================================================

\echo '--- validation ---'

SELECT tests.assert_raises(
  $sql$SELECT public.save_public_taxonomy_value('{"kind":"amenity","code":"Mal Código","name_es":"X","name_en":"X"}'::jsonb)$sql$,
  'VALIDATION_ERROR', 'an invalid code is rejected'
);
SELECT tests.assert_raises(
  $sql$SELECT public.save_public_taxonomy_value('{"kind":"amenity","code":"sauna","name_es":"Sauna","name_en":"  "}'::jsonb)$sql$,
  'BILINGUAL_PAIR_INCOMPLETE', 'a blank English name is rejected'
);
SELECT tests.assert_raises(
  $sql$SELECT public.save_public_taxonomy_value('{"kind":"color","code":"rojo","name_es":"Rojo","name_en":"Red"}'::jsonb)$sql$,
  'VALIDATION_ERROR', 'an unknown kind is rejected'
);
SELECT tests.assert_raises(
  $sql$SELECT public.save_public_category('{"id":"sin_nombre","name_es":"","name_en":"No name"}'::jsonb)$sql$,
  'BILINGUAL_PAIR_INCOMPLETE', 'a category needs both names'
);

-- Renaming keeps the stable code.
SELECT public.save_public_taxonomy_value('{"kind":"amenity","code":"wifi","name_es":"Internet","name_en":"Internet"}'::jsonb);
SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 FROM public.public_taxonomy_values WHERE kind = 'amenity' AND code = 'wifi' AND name_es = 'Internet'$sql$,
  'renaming a value keeps one row with the same code'
);

-- ===========================================================================
-- 5. A used value can be deactivated, not deleted (FR-008)
-- ===========================================================================

\echo '--- used values ---'

RESET ROLE;
SELECT pg_temp.act_as(:'operator_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'accommodation', 'Casa Uno', NULL, NULL, '{}'::uuid[],
  NULL,
  jsonb_build_object('property_type', 'villa', 'location', 'Centro', 'max_occupancy', 4)
) ->> 'id') AS lodging_product_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'org_a'::uuid, :'lodging_product_id'::uuid, 300000, 'per_night');
SELECT pg_temp.act_as(:'operator_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'lodging_product_id'::uuid,
  'placement', 'lodging',
  'public_slug', 'casa-uno',
  'name_es', 'Casa Uno', 'name_en', 'House One',
  'description_es', 'Desc', 'description_en', 'Desc',
  'max_guests', 4, 'display_price', 300000, 'currency', 'COP',
  'lodging', jsonb_build_object(
    'lodging_type', 'hotel',
    'location_es', 'Centro', 'location_en', 'Downtown',
    'neighborhood_es', 'San Diego', 'neighborhood_en', 'San Diego',
    'bedrooms', 2, 'bathrooms', 1,
    'amenities', jsonb_build_array('wifi', 'jacuzzi')
  )
)) ->> 'id') AS listing_id \gset

SELECT public.attach_public_image(:'listing_id'::uuid, 'cover', NULL, '/images/casa-uno.jpg', 0);
SELECT public.publish_public_listing(:'listing_id'::uuid);

SELECT tests.assert_raises(
  $sql$SELECT public.delete_public_taxonomy_value('amenity', 'jacuzzi')$sql$,
  'TAXONOMY_VALUE_IN_USE', 'an amenity used by a published listing cannot be deleted'
);
SELECT tests.assert_raises(
  $sql$SELECT public.delete_public_taxonomy_value('lodging_type', 'hotel')$sql$,
  'TAXONOMY_VALUE_IN_USE', 'a lodging type used by a published listing cannot be deleted'
);

SELECT public.save_public_taxonomy_value('{"kind":"amenity","code":"jacuzzi","name_es":"Jacuzzi","name_en":"Hot tub","is_active":false}'::jsonb);
SELECT public.save_public_taxonomy_value('{"kind":"lodging_type","code":"hotel","name_es":"Hotel","name_en":"Hotel","is_active":false}'::jsonb);

SELECT tests.assert_true(
  format($sql$SELECT status = 'published' AND lodging -> 'amenities' ? 'jacuzzi' AND lodging ->> 'lodging_type' = 'hotel'
               FROM public.public_listings WHERE id = %L$sql$, :'listing_id'),
  'deactivating values leaves the published listing untouched'
);

SELECT tests.assert_true(
  $sql$SELECT (v ->> 'in_use')::boolean AND NOT (v ->> 'is_active')::boolean
       FROM jsonb_array_elements(public.list_public_taxonomy_values()) v
       WHERE v ->> 'code' = 'jacuzzi'$sql$,
  'the list reports the value as inactive and in use'
);

-- Editing the listing keeps values it already had, even if inactive.
SELECT public.save_public_listing(jsonb_build_object(
  'product_id', :'lodging_product_id'::uuid,
  'placement', 'lodging',
  'public_slug', 'casa-uno',
  'name_es', 'Casa Uno', 'name_en', 'House One',
  'description_es', 'Desc 2', 'description_en', 'Desc 2',
  'max_guests', 4, 'display_price', 300000, 'currency', 'COP',
  'lodging', jsonb_build_object(
    'lodging_type', 'hotel',
    'location_es', 'Centro', 'location_en', 'Downtown',
    'neighborhood_es', 'San Diego', 'neighborhood_en', 'San Diego',
    'bedrooms', 2, 'bathrooms', 1,
    'amenities', jsonb_build_array('wifi', 'jacuzzi', 'tv')
  )
));

SELECT tests.assert_true(
  format($sql$SELECT status = 'published' FROM public.public_listings WHERE id = %L$sql$, :'listing_id'),
  'a listing that keeps its now-inactive values stays published after an edit'
);

SELECT public.save_public_taxonomy_value('{"kind":"amenity","code":"bbq","name_es":"BBQ","name_en":"BBQ","is_active":false}'::jsonb);

SELECT tests.assert_raises(
  format($sql$SELECT public.save_public_listing(jsonb_build_object(
    'product_id', %L::uuid, 'placement', 'lodging', 'public_slug', 'casa-uno',
    'name_es', 'Casa Uno', 'name_en', 'House One',
    'description_es', 'Desc', 'description_en', 'Desc',
    'max_guests', 4, 'display_price', 300000, 'currency', 'COP',
    'lodging', jsonb_build_object(
      'lodging_type', 'hotel', 'location_es', 'Centro', 'location_en', 'Downtown',
      'neighborhood_es', 'San Diego', 'neighborhood_en', 'San Diego',
      'bedrooms', 2, 'bathrooms', 1, 'amenities', jsonb_build_array('wifi', 'bbq'))))$sql$,
    :'lodging_product_id'),
  'TAXONOMY_VALUE_INACTIVE', 'an inactive amenity cannot be newly assigned'
);

SELECT tests.assert_raises(
  format($sql$SELECT public.save_public_listing(jsonb_build_object(
    'product_id', %L::uuid, 'placement', 'lodging', 'public_slug', 'casa-uno',
    'name_es', 'Casa Uno', 'name_en', 'House One',
    'description_es', 'Desc', 'description_en', 'Desc',
    'max_guests', 4, 'display_price', 300000, 'currency', 'COP',
    'lodging', jsonb_build_object(
      'lodging_type', 'hotel', 'location_es', 'Centro', 'location_en', 'Downtown',
      'neighborhood_es', 'San Diego', 'neighborhood_en', 'San Diego',
      'bedrooms', 2, 'bathrooms', 1, 'amenities', jsonb_build_array('solo_b'))))$sql$,
    :'lodging_product_id'),
  'TAXONOMY_VALUE_INVALID', 'another agency''s amenity code is not valid here'
);

-- Labels of inactive values still used by a published listing reach the public projection.
RESET ROLE;
SELECT tests.assert_true(
  format($sql$SELECT EXISTS (
               SELECT 1 FROM jsonb_array_elements(public.build_public_taxonomy(%L) -> 'amenities') a
               WHERE a ->> 'id' = 'jacuzzi' AND a ->> 'nameEn' = 'Hot tub')
             AND NOT EXISTS (
               SELECT 1 FROM jsonb_array_elements(public.build_public_taxonomy(%L) -> 'amenities') a
               WHERE a ->> 'id' = 'bbq')$sql$, :'org_a', :'org_a'),
  'the public projection keeps the label of an inactive value in use and hides unused inactive ones'
);

-- ===========================================================================
-- 6. Categories: deactivate in use, delete only unused and unprotected
-- ===========================================================================

\echo '--- categories ---'

UPDATE public.public_listings SET public_category_id = 'tours' WHERE id = :'listing_id'::uuid;

SELECT pg_temp.act_as(:'operator_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  $sql$SELECT public.delete_public_category('tours')$sql$,
  'CATEGORY_IN_USE', 'a category used by a listing cannot be deleted'
);

SELECT public.save_public_category('{"id":"tours","name_es":"Tours","name_en":"Tours","is_active":false}'::jsonb);

SELECT tests.assert_true(
  $sql$SELECT NOT is_active FROM public.public_categories WHERE id = 'tours'$sql$,
  'a category used by a published listing can be deactivated'
);

SELECT public.delete_public_category('naturaleza');

SELECT tests.assert_true(
  $sql$SELECT NOT EXISTS (SELECT 1 FROM public.public_categories WHERE id = 'naturaleza')$sql$,
  'an unused example category can be deleted'
);

-- ===========================================================================
-- 7. Audit (FR-029)
-- ===========================================================================

\echo '--- audit ---'

RESET ROLE;

SELECT tests.assert_true(
  format($sql$SELECT count(*) >= 6 FROM audit.audit_events
               WHERE organization_id = %L AND event_type = 'public_taxonomy_changed'
                 AND actor_id IS NOT NULL$sql$, :'org_a'),
  'taxonomy changes are audited with actor and agency'
);

SELECT tests.assert_true(
  format($sql$SELECT EXISTS (SELECT 1 FROM audit.audit_events
               WHERE organization_id = %L AND event_type = 'public_taxonomy_changed'
                 AND actor_id = %L AND metadata ->> 'code' = 'naturaleza'
                 AND metadata ->> 'action' = 'deleted')$sql$, :'org_a', :'operator_a'),
  'a deletion records the code, the action and the operator'
);


ROLLBACK;
