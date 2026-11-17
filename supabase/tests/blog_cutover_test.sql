-- blog_cutover_test.sql
-- Feature 013, US6: migrate an existing blog with a manifest and a source switch (FR-030..FR-035).
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/blog_cutover_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a     13300000-0000-4000-a000-000000000001
\set org_b     13300000-0000-4000-a000-000000000002
\set admin_a   13300000-0000-4000-b000-000000000001
\set op_a      13300000-0000-4000-b000-000000000002
\set admin_b   13300000-0000-4000-b000-000000000003
\set op_b      13300000-0000-4000-b000-000000000004

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid, p_organization_id uuid, p_email text, p_role public.app_role
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
    p_email, now(), now());
  INSERT INTO public.user_profiles (id, organization_id, full_name, email, role, status, must_change_password)
  VALUES (p_user_id, p_organization_id, 'Colaborador', p_email, p_role, 'active', false);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user_id uuid, p_organization_id uuid, p_app_role text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_user_id::text, 'role', 'authenticated',
    'app_role', p_app_role, 'organization_id', p_organization_id::text
  )::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.rev(p_id uuid) RETURNS integer LANGUAGE sql AS $$
  SELECT revision FROM public.blog_articles WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION pg_temp.detail_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_detail text;
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
  RETURN v_detail;
END;
$$;

-- Copies one legacy article (es only agency) and publishes it. Images stay on the old blog.
CREATE OR REPLACE FUNCTION pg_temp.migrate(p_slug text, p_date text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  v_id := (public.save_blog_article(jsonb_build_object(
    'slug', p_slug, 'migrated', true, 'originalPublishedAt', p_date,
    'es', jsonb_build_object('title', 'Legado ' || p_slug)
  )) ->> 'id')::uuid;
  PERFORM public.save_blog_article(jsonb_build_object(
    'id', v_id, 'expectedRevision', pg_temp.rev(v_id),
    'coverRef', 'https://blog-anterior.example/wp-content/uploads/' || p_slug || '.jpg',
    'es', jsonb_build_object(
      'title', 'Legado ' || p_slug, 'summary', 'Resumen', 'coverAlt', 'Portada',
      'body', jsonb_build_array(
        jsonb_build_object('type', 'paragraph', 'text', jsonb_build_array(jsonb_build_object('text', 'Texto'))),
        jsonb_build_object('type', 'image', 'ref', 'https://blog-anterior.example/wp-content/uploads/x.jpg', 'alt', 'Foto')
      )
    )
  ));
  PERFORM public.publish_blog_article(v_id, pg_temp.rev(v_id));
  RETURN v_id;
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_a'::uuid, 'Migrada A', 'migrada-a', 'active', '{}'::jsonb),
  (:'org_b'::uuid, 'Nueva B', 'nueva-b', 'active', '{}'::jsonb);

UPDATE public.public_profiles SET languages = ARRAY['es'] WHERE organization_id IN (:'org_a'::uuid, :'org_b'::uuid);

SELECT pg_temp.add_collaborator(:'admin_a'::uuid, :'org_a'::uuid, 'admin-a@cut.invalid', 'admin');
SELECT pg_temp.add_collaborator(:'op_a'::uuid, :'org_a'::uuid, 'op-a@cut.invalid', 'operator');
SELECT pg_temp.add_collaborator(:'admin_b'::uuid, :'org_b'::uuid, 'admin-b@cut.invalid', 'admin');
SELECT pg_temp.add_collaborator(:'op_b'::uuid, :'org_b'::uuid, 'op-b@cut.invalid', 'operator');

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SELECT (public.generate_public_access_key() ->> 'key') AS key_a \gset
SELECT pg_temp.act_as(:'admin_b'::uuid, :'org_b'::uuid, 'admin');
SELECT (public.generate_public_access_key() ->> 'key') AS key_b \gset

-- ---------------------------------------------------------------------------
-- Before marking: migration options are closed.
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT tests.assert_raises(
  $$ SELECT public.save_blog_article('{"slug":"viejo","migrated":true,"es":{"title":"X"}}'::jsonb) $$,
  'MIGRATION_CLOSED', 'a migrated article cannot be created without an open migration'
);

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SELECT tests.assert_raises(
  $$ SELECT public.replace_blog_cutover_manifest(ARRAY['a']) $$,
  'MIGRATION_CLOSED', 'the manifest cannot be loaded without an open migration'
);

SELECT public.set_blog_migration_required(true) AS marked \gset
SELECT tests.assert_equals(:'marked'::jsonb ->> 'migrationRequired', 'true', 'the Administrator marks the blog as migrated');

SELECT tests.assert_raises(
  format($$ SELECT public.replace_blog_cutover_manifest(%L::text[]) $$,
         (SELECT array_agg('s-' || g) FROM generate_series(1, 2001) g)),
  'VALIDATION_ERROR', 'a manifest over 2000 slugs is rejected'
);
SELECT public.replace_blog_cutover_manifest(ARRAY['Mi_Post-2019', 'guia-islas', 'guia-islas', ' playa-blanca ']) AS manifest \gset
SELECT tests.assert_equals(
  jsonb_array_length(:'manifest'::jsonb -> 'manifest')::bigint, 3::bigint,
  'the manifest is trimmed and deduplicated'
);

-- ---------------------------------------------------------------------------
-- Copy two of three, try to switch.
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT pg_temp.migrate('Mi_Post-2019', '2019-05-01T10:00:00Z') AS m1 \gset
SELECT pg_temp.migrate('guia-islas', '2021-02-03T10:00:00Z') AS m2 \gset

SELECT tests.assert_true(
  format($$ (SELECT migrated AND slug = 'Mi_Post-2019' AND first_published_at = '2019-05-01T10:00:00Z'::timestamptz
             FROM public.blog_articles WHERE id = %L) $$, :'m1'),
  'a migrated article keeps its legacy slug and its original publication date'
);
SELECT tests.assert_raises(
  $$ SELECT public.save_blog_article('{"slug":"con espacio","migrated":true,"es":{"title":"X"}}'::jsonb) $$,
  'INVALID_SLUG', 'a legacy slug with spaces is still rejected'
);
SELECT tests.assert_raises(
  $$ SELECT public.save_blog_article('{"es":{"title":"X"},"migrated":true,"originalPublishedAt":"2999-01-01"}'::jsonb) $$,
  'VALIDATION_ERROR', 'an original publication date in the future is rejected'
);

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;
SELECT public.get_public_blog_by_key(:'key_a') AS legacy_list \gset
SELECT public.get_public_blog_article_by_key(:'key_a', 'guia-islas') AS legacy_article \gset
RESET ROLE;

SELECT tests.assert_true(
  format($$ (%1$L::jsonb ->> 'source') = 'legacy' AND (%1$L::jsonb ->> 'total') = '0'
            AND jsonb_array_length(%1$L::jsonb -> 'articles') = 0 $$, :'legacy_list'),
  'while migrating, the public read answers legacy so the site keeps its previous blog'
);
SELECT tests.assert_equals(:'legacy_article', '{"found": false}', 'while migrating, articles are not served by slug');

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SELECT pg_temp.detail_of($$ SELECT public.complete_blog_cutover() $$) AS missing \gset
SELECT tests.assert_raises(
  $$ SELECT public.complete_blog_cutover() $$,
  'BLOG_CUTOVER_INCOMPLETE', 'the cutover is rejected while a manifest slug has no published article'
);
SELECT tests.assert_equals(:'missing', '["playa-blanca"]', 'DETAIL lists exactly the missing slugs');
SELECT tests.assert_equals(
  public.get_blog_source() ->> 'cutoverCompletedAt', NULL, 'a rejected cutover leaves the source unchanged'
);

-- ---------------------------------------------------------------------------
-- Copy the last one and switch.
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT pg_temp.migrate('playa-blanca', '2022-07-08T10:00:00Z') AS m3 \gset

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SELECT public.complete_blog_cutover() AS done \gset
SELECT tests.assert_true(
  format($$ (%1$L::jsonb ->> 'cutoverCompletedAt') IS NOT NULL AND (%1$L::jsonb -> 'missing') = '[]'::jsonb $$, :'done'),
  'the cutover completes when every manifest slug is published'
);

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;
SELECT public.get_public_blog_by_key(:'key_a') AS panel_list \gset
SELECT public.get_public_blog_article_by_key(:'key_a', 'Mi_Post-2019') AS panel_article \gset
RESET ROLE;

SELECT tests.assert_true(
  format($$ (%1$L::jsonb ->> 'source') = 'panel' AND (%1$L::jsonb ->> 'total') = '3'
            AND (%1$L::jsonb -> 'articles' -> 0 ->> 'slug') = 'playa-blanca' $$, :'panel_list'),
  'after the cutover the site reads the panel, newest original date first'
);
SELECT tests.assert_true(
  format($$ (%1$L::jsonb ->> 'found') = 'true'
            AND (%1$L::jsonb ->> 'publishedAt')::timestamptz = '2019-05-01T10:00:00Z'::timestamptz
            AND (%1$L::jsonb ->> 'cover') LIKE 'https://blog-anterior.example/%%' $$, :'panel_article'),
  'an old address resolves with its original date and its external image'
);

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SELECT tests.assert_raises(
  $$ SELECT public.set_blog_migration_required(false) $$,
  'INVALID_TRANSITION', 'the migration flag cannot change after the cutover'
);
SELECT tests.assert_raises(
  $$ SELECT public.complete_blog_cutover() $$,
  'INVALID_TRANSITION', 'the cutover cannot be completed twice'
);
SELECT tests.assert_raises(
  $$ SELECT public.replace_blog_cutover_manifest(ARRAY['otro']) $$,
  'MIGRATION_CLOSED', 'the manifest is closed after the cutover'
);
SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT tests.assert_raises(
  $$ SELECT public.save_blog_article('{"slug":"tarde","migrated":true,"es":{"title":"X"}}'::jsonb) $$,
  'MIGRATION_CLOSED', 'no migrated article can be created after the cutover'
);

SELECT tests.assert_true(
  $$ (SELECT count(*) FROM audit.audit_events WHERE event_type = 'blog_source_changed') >= 2
     AND EXISTS (SELECT 1 FROM audit.audit_events WHERE event_type = 'blog_cutover_manifest_changed'
                 AND metadata ->> 'count' = '3') $$,
  'marking, the manifest and the cutover are audited'
);

-- ---------------------------------------------------------------------------
-- A new agency without a previous blog publishes directly (FR-034).
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'op_b'::uuid, :'org_b'::uuid, 'operator');
SELECT (public.save_blog_article('{"slug":"bienvenidos","es":{"title":"Bienvenidos"}}'::jsonb) ->> 'id') AS nb \gset
SELECT public.save_blog_article(jsonb_build_object(
  'id', :'nb', 'expectedRevision', pg_temp.rev(:'nb'::uuid),
  'coverRef', :'org_b' || '/blog/' || :'nb' || '/c.webp',
  'es', jsonb_build_object('title', 'Bienvenidos', 'summary', 'Hola', 'coverAlt', 'Portada',
    'body', jsonb_build_array(jsonb_build_object('type', 'paragraph', 'text', jsonb_build_array(jsonb_build_object('text', 'Hola')))))
));
SELECT public.publish_blog_article(:'nb'::uuid, pg_temp.rev(:'nb'::uuid));

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;
SELECT public.get_public_blog_by_key(:'key_b') AS new_list \gset
RESET ROLE;

SELECT tests.assert_true(
  format($$ (%1$L::jsonb ->> 'source') = 'panel' AND (%1$L::jsonb ->> 'total') = '1' $$, :'new_list'),
  'an agency without a previous blog publishes directly, with no copy rule'
);

ROLLBACK;
