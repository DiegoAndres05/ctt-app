-- public_source_transition_test.sql
-- Feature 016, US4 + US5: CTT compatibility (categories, slugs, images, organization-identifier
-- transition) and migration-required vs direct publication.
--
-- The seeded demo agency (00000000-...-0001) stands in for CTT: it carries the cutover manifest.
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/public_source_transition_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set ctt_org      00000000-0000-4000-a000-000000000001
\set ctt_admin    00000000-0000-4000-b000-000000000001
\set ctt_operator 00000000-0000-4000-b000-000000000002
\set new_org      16000000-0000-4000-a000-000000000301
\set new_admin    16000000-0000-4000-b000-000000000311
\set new_operator 16000000-0000-4000-b000-000000000312
\set mig_org      16000000-0000-4000-a000-000000000302
\set mig_admin    16000000-0000-4000-b000-000000000321

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

-- Snapshot of CTT's public identifiers and images before anything in this suite runs.
CREATE TEMP TABLE ctt_before AS
SELECT pl.public_slug, pl.placement, pl.cover_image_ref, pl.status, pl.public_category_id
FROM public.public_listings pl
WHERE pl.organization_id = '00000000-0000-4000-a000-000000000001';

INSERT INTO public.organizations (id, name, slug, status)
VALUES
  (:'new_org'::uuid, 'Agencia Nueva', 'agencia-nueva-016', 'active'),
  (:'mig_org'::uuid, 'Agencia Migrada', 'agencia-migrada-016', 'active');

SELECT pg_temp.add_collaborator(:'new_admin'::uuid, :'new_org'::uuid, 'admin-n@src.invalid', 'Admin Nueva', 'admin');
SELECT pg_temp.add_collaborator(:'new_operator'::uuid, :'new_org'::uuid, 'op-n@src.invalid', 'Operador Nueva', 'operator');
SELECT pg_temp.add_collaborator(:'mig_admin'::uuid, :'mig_org'::uuid, 'admin-m@src.invalid', 'Admin Migrada', 'admin');

-- ===========================================================================
-- 1. CTT keeps its categories, slugs and images (FR-004, FR-025, SC-005)
-- ===========================================================================

\echo '--- CTT compatibility ---'

SELECT tests.assert_true(
  format($sql$SELECT count(*) = 8 AND bool_and(protected) AND bool_and(is_active)
             FROM public.public_categories
             WHERE organization_id = %L
               AND id IN ('islas', 'baru', 'tierra_bomba', 'compartidos', 'cultural', 'aventura', 'baile', 'premium')$sql$,
    :'ctt_org'),
  'CTT keeps its eight protected category identifiers'
);

SELECT tests.assert_true(
  format($sql$SELECT migration_required AND organization_identifier_until > now() + interval '89 days'
             FROM public.public_source_config WHERE organization_id = %L$sql$, :'ctt_org'),
  'CTT is a migrating agency with an open organization-identifier transition'
);

SELECT tests.assert_true(
  $sql$SELECT count(*) >= 3 FROM ctt_before WHERE status = 'published'$sql$,
  'the CTT demo listings are present before the checks'
);

SELECT pg_temp.act_as(:'ctt_operator'::uuid, :'ctt_org'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises(
  $sql$SELECT public.delete_public_category('islas')$sql$,
  'CATEGORY_PROTECTED', 'a CTT category cannot be deleted'
);
RESET ROLE;

-- During the transition the organization identifier still works for reads and requests.
SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;

SELECT tests.assert_true(
  format($sql$SELECT public.get_public_site(%L) ->> 'source' = 'legacy'$sql$, :'ctt_org'),
  'CTT reads with its organization identifier during the transition (still legacy until cutover)'
);

SELECT public.submit_public_request(:'ctt_org'::uuid, jsonb_build_object(
  'privacy_consent', true,
  'contact', jsonb_build_object('first_name', 'Pedro', 'email', 'pedro@viajero.invalid'),
  'interest_text', 'Transición CTT'
)) ->> 'reference' AS ctt_ref \gset

RESET ROLE;

SELECT tests.assert_true(
  format($sql$SELECT EXISTS (SELECT 1 FROM public.customer_requests
               WHERE organization_id = %L AND reference = %L)$sql$, :'ctt_org', :'ctt_ref'),
  'CTT receives requests sent with its organization identifier during the transition'
);

-- ===========================================================================
-- 2. The identifier path is CTT-only (FR-016, edge case 9)
-- ===========================================================================

\echo '--- identifier path is not general ---'

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT tests.assert_raises(
  format('SELECT public.get_public_site(%L)', :'new_org'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'a new agency cannot be read by organization identifier'
);
SELECT tests.assert_raises(
  format($sql$SELECT public.submit_public_request(%L, '{"privacy_consent":true}'::jsonb)$sql$, :'new_org'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'a new agency cannot receive requests by organization identifier'
);
RESET ROLE;

-- Turning migration on does not open the identifier path either.
SELECT pg_temp.act_as(:'mig_admin'::uuid, :'mig_org'::uuid, 'admin');
SET LOCAL ROLE authenticated;
SELECT public.set_public_source_migration(true);
RESET ROLE;

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT tests.assert_raises(
  format('SELECT public.get_public_site(%L)', :'mig_org'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'marking an agency as migrated does not open the identifier path'
);
RESET ROLE;

-- ===========================================================================
-- 3. Ending the transition (FR-017)
-- ===========================================================================

\echo '--- end of transition ---'

SELECT pg_temp.act_as(:'ctt_operator'::uuid, :'ctt_org'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises(
  'SELECT public.end_organization_identifier_transition()',
  'FORBIDDEN', 'an operator cannot end the transition'
);
RESET ROLE;

SELECT pg_temp.act_as(:'ctt_admin'::uuid, :'ctt_org'::uuid, 'admin');
SET LOCAL ROLE authenticated;
SELECT public.generate_public_access_key() ->> 'key' AS ctt_key \gset
SELECT tests.assert_true(
  $sql$SELECT NOT (public.end_organization_identifier_transition() ->> 'identifier_access_open')::boolean$sql$,
  'the administrator closes the organization-identifier access'
);
RESET ROLE;

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT tests.assert_raises(
  format('SELECT public.get_public_site(%L)', :'ctt_org'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'after the transition the organization identifier is rejected'
);
SELECT tests.assert_raises(
  format($sql$SELECT public.submit_public_request(%L, '{"privacy_consent":true}'::jsonb)$sql$, :'ctt_org'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'after the transition requests by organization identifier are rejected'
);
SELECT tests.assert_true(
  format($sql$SELECT public.get_public_site_by_key(%L) #>> '{catalog,source}' = 'legacy'$sql$, :'ctt_key'),
  'the public key keeps working after the transition'
);
RESET ROLE;

SELECT tests.assert_true(
  $sql$SELECT NOT EXISTS (
         (SELECT public_slug, placement, cover_image_ref, status, public_category_id FROM ctt_before)
         EXCEPT
         (SELECT public_slug, placement, cover_image_ref, status, public_category_id
          FROM public.public_listings WHERE organization_id = '00000000-0000-4000-a000-000000000001'))$sql$,
  'CTT slugs, images, categories and statuses are unchanged by the transition'
);

-- ===========================================================================
-- 4. Migrating agency: manifest gate (FR-026, FR-027)
-- ===========================================================================

\echo '--- migration gate ---'

INSERT INTO public.public_cutover_items (organization_id, public_slug, placement)
VALUES (:'mig_org'::uuid, 'oferta-existente', 'catalog');

SELECT pg_temp.act_as(:'mig_admin'::uuid, :'mig_org'::uuid, 'admin');
SET LOCAL ROLE authenticated;
SELECT tests.assert_raises(
  'SELECT public.complete_public_cutover()',
  'CUTOVER_INCOMPLETE', 'a migrating agency cannot cut over with a manifest item missing'
);
SELECT tests.assert_true(
  $sql$SELECT source = 'legacy' FROM public.public_sites$sql$,
  'its current site keeps the legacy source'
);
SELECT public.generate_public_access_key() ->> 'key' AS mig_key \gset
RESET ROLE;

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT tests.assert_true(
  format($sql$SELECT public.get_public_site_by_key(%L) #> '{catalog,offers}' = '[]'::jsonb
               AND public.get_public_site_by_key(%L) #>> '{catalog,source}' = 'legacy'$sql$, :'mig_key', :'mig_key'),
  'before cutover a migrating agency shows the preparing state'
);
RESET ROLE;

-- ===========================================================================
-- 5. New agency: direct publication (FR-028)
-- ===========================================================================

\echo '--- direct publication ---'

SELECT pg_temp.act_as(:'new_operator'::uuid, :'new_org'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.create_product(
  'experience', 'Tour Directo', NULL, NULL, '{}'::uuid[],
  jsonb_build_object(
    'duration_minutes', 180, 'difficulty', 'easy', 'meeting_point', 'Muelle',
    'min_capacity', 1, 'max_capacity', 10
  ),
  NULL
) ->> 'id') AS offer_product_id \gset

RESET ROLE;
SELECT pg_temp.price_and_activate(:'new_org'::uuid, :'offer_product_id'::uuid, 150000, 'per_person');
SELECT pg_temp.act_as(:'new_operator'::uuid, :'new_org'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT (public.save_public_listing(jsonb_build_object(
  'product_id', :'offer_product_id'::uuid,
  'placement', 'catalog',
  'public_slug', 'tour-directo',
  'name_es', 'Tour directo', 'name_en', 'Direct tour',
  'description_es', 'Desc', 'description_en', 'Desc',
  'public_category_id', 'tours',
  'location', 'Centro',
  'display_price', 150000, 'currency', 'COP',
  'includes', jsonb_build_array(jsonb_build_object('es', 'Guía', 'en', 'Guide'))
)) ->> 'id') AS offer_listing_id \gset

SELECT public.attach_public_image(:'offer_listing_id'::uuid, 'cover', NULL, '/images/tour-directo.jpg', 0);
SELECT public.publish_public_listing(:'offer_listing_id'::uuid);
RESET ROLE;

SELECT pg_temp.act_as(:'new_admin'::uuid, :'new_org'::uuid, 'admin');
SET LOCAL ROLE authenticated;
SELECT public.generate_public_access_key() ->> 'key' AS new_key \gset
RESET ROLE;

SELECT pg_temp.act_anon();
SET LOCAL ROLE anon;
SELECT tests.assert_true(
  format($sql$SELECT public.get_public_site_by_key(%L) #>> '{catalog,offers,0,id}' = 'tour-directo'
               AND public.get_public_site_by_key(%L) #>> '{catalog,source}' = 'panel'$sql$, :'new_key', :'new_key'),
  'a new agency''s published listing is public without any copy or cutover step'
);
RESET ROLE;

SELECT pg_temp.act_as(:'new_admin'::uuid, :'new_org'::uuid, 'admin');
SET LOCAL ROLE authenticated;
SELECT tests.assert_true(
  $sql$SELECT public.complete_public_cutover() ->> 'source' = 'panel'$sql$,
  'a migration-free agency can mark its source as panel without a manifest'
);
SELECT tests.assert_raises(
  'SELECT public.set_public_source_migration(true)',
  'CUTOVER_ALREADY_COMPLETED', 'the migration mode cannot change after cutover'
);
RESET ROLE;

-- ===========================================================================
-- 6. Audit
-- ===========================================================================

SELECT tests.assert_true(
  format($sql$SELECT EXISTS (SELECT 1 FROM audit.audit_events
               WHERE organization_id = %L AND event_type = 'public_source_config_changed'
                 AND actor_id = %L AND metadata ->> 'action' = 'organization_identifier_closed')$sql$,
    :'ctt_org', :'ctt_admin'),
  'closing the transition is audited with the administrator'
);

ROLLBACK;
