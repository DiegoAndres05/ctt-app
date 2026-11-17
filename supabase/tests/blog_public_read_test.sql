-- blog_public_read_test.sql
-- Feature 013: public blog read for the site of each agency (US2, US5, FR-021..FR-028).
--
-- Panel RPCs run as the harness superuser with JWT claims (see blog_articles_test.sql). Public
-- reads run under SET LOCAL ROLE anon / authenticated so grants are exercised too.
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/blog_public_read_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a     13100000-0000-4000-a000-000000000001
\set org_b     13100000-0000-4000-a000-000000000002
\set op_a      13100000-0000-4000-b000-000000000001
\set admin_a   13100000-0000-4000-b000-000000000002
\set op_b      13100000-0000-4000-b000-000000000003
\set admin_b   13100000-0000-4000-b000-000000000004

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

-- Creates and publishes an article with complete es/en content; returns its id.
CREATE OR REPLACE FUNCTION pg_temp.publish_article(
  p_slug text, p_title text, p_seo boolean DEFAULT false
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
  v_org uuid;
  v_prefix text;
BEGIN
  v_id := (public.save_blog_article(jsonb_build_object('slug', p_slug, 'es', jsonb_build_object('title', p_title))) ->> 'id')::uuid;
  v_org := (SELECT organization_id FROM public.blog_articles WHERE id = v_id);
  v_prefix := v_org::text || '/blog/' || v_id::text || '/';
  PERFORM public.save_blog_article(jsonb_build_object(
    'id', v_id, 'expectedRevision', pg_temp.rev(v_id),
    'coverRef', v_prefix || 'cover.webp',
    'es', jsonb_build_object(
      'title', p_title, 'summary', 'Resumen ' || p_title, 'coverAlt', 'Portada ' || p_title,
      'seoTitle', CASE WHEN p_seo THEN 'SEO ' || p_title END,
      'seoDescription', CASE WHEN p_seo THEN 'Descripción SEO' END,
      'body', jsonb_build_array(
        jsonb_build_object('type', 'heading', 'level', 2, 'text', jsonb_build_array(jsonb_build_object('text', 'Intro'))),
        jsonb_build_object('type', 'paragraph', 'text', jsonb_build_array(jsonb_build_object('text', 'Texto ' || p_title))),
        jsonb_build_object('type', 'image', 'ref', v_prefix || 'a.webp', 'alt', 'Foto'),
        jsonb_build_object('type', 'image', 'ref', v_prefix || 'b.webp', 'decorative', true)
      )
    ),
    'en', jsonb_build_object(
      'title', p_title || ' EN', 'summary', 'Summary ' || p_title, 'coverAlt', 'Cover',
      'body', jsonb_build_array(
        jsonb_build_object('type', 'paragraph', 'text', jsonb_build_array(jsonb_build_object('text', 'Text ' || p_title)))
      )
    )
  ));
  PERFORM public.publish_blog_article(v_id, pg_temp.rev(v_id));
  RETURN v_id;
END;
$$;

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_a'::uuid, 'Lectura A', 'lectura-a', 'active', '{}'::jsonb),
  (:'org_b'::uuid, 'Lectura B', 'lectura-b', 'active', '{}'::jsonb);

-- A models CTT during the identifier transition; B does not.
SELECT public.mark_public_site_as_migrated(:'org_a'::uuid);
UPDATE public.public_profiles SET languages = ARRAY['es'] WHERE organization_id = :'org_b'::uuid;

SELECT pg_temp.add_collaborator(:'op_a'::uuid, :'org_a'::uuid, 'op-a@read.invalid', 'operator');
SELECT pg_temp.add_collaborator(:'admin_a'::uuid, :'org_a'::uuid, 'admin-a@read.invalid', 'admin');
SELECT pg_temp.add_collaborator(:'op_b'::uuid, :'org_b'::uuid, 'op-b@read.invalid', 'operator');
SELECT pg_temp.add_collaborator(:'admin_b'::uuid, :'org_b'::uuid, 'admin-b@read.invalid', 'admin');

SELECT pg_temp.act_as(:'admin_a'::uuid, :'org_a'::uuid, 'admin');
SELECT (public.generate_public_access_key() ->> 'key') AS key_a \gset
SELECT pg_temp.act_as(:'admin_b'::uuid, :'org_b'::uuid, 'admin');
SELECT (public.generate_public_access_key() ->> 'key') AS key_b \gset

-- Agency A: three published, one draft, one retired.
SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT pg_temp.publish_article('playas', 'Playas', true) AS p1 \gset
SELECT pg_temp.publish_article('murallas', 'Murallas') AS p2 \gset
SELECT pg_temp.publish_article('comida', 'Comida') AS p3 \gset
SELECT pg_temp.publish_article('retirado', 'Retirado') AS p4 \gset
SELECT public.retire_blog_article(:'p4'::uuid, pg_temp.rev(:'p4'::uuid));
SELECT (public.save_blog_article('{"slug":"borrador","es":{"title":"Borrador"}}'::jsonb) ->> 'id') AS d1 \gset

-- Agency B publishes the same slug as A.
SELECT pg_temp.act_as(:'op_b'::uuid, :'org_b'::uuid, 'operator');
SELECT pg_temp.publish_article('playas', 'Playas de B') AS b1 \gset

-- Spread publication dates (inside one transaction now() is constant).
ALTER TABLE public.blog_articles DISABLE TRIGGER blog_articles_guard;
UPDATE public.blog_articles SET first_published_at = now() - interval '3 days' WHERE id = :'p1'::uuid;
UPDATE public.blog_articles SET first_published_at = now() - interval '1 day' WHERE id = :'p2'::uuid;
UPDATE public.blog_articles SET first_published_at = now() - interval '2 days' WHERE id = :'p3'::uuid;
ALTER TABLE public.blog_articles ENABLE TRIGGER blog_articles_guard;

-- A pending revision on a published article must never leak.
SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT public.save_blog_article(jsonb_build_object(
  'id', :'p2', 'expectedRevision', pg_temp.rev(:'p2'::uuid),
  'es', jsonb_build_object('title', 'SECRETO EN CURSO')
));

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

SELECT tests.assert_true(
  $$ has_function_privilege('anon', 'public.get_public_blog_by_key(text, integer, integer)', 'EXECUTE')
     AND has_function_privilege('anon', 'public.get_public_blog_article_by_key(text, text)', 'EXECUTE')
     AND has_function_privilege('anon', 'public.get_public_blog(uuid, integer, integer)', 'EXECUTE')
     AND has_function_privilege('anon', 'public.get_public_blog_article(uuid, text)', 'EXECUTE') $$,
  'anon may call the four public blog entry points'
);
SELECT tests.assert_true(
  $$ NOT has_function_privilege('anon', 'public.build_public_blog_list(uuid, integer, integer)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.build_public_blog_article(uuid, text)', 'EXECUTE')
     AND NOT has_function_privilege('anon', 'public.save_blog_article(jsonb)', 'EXECUTE')
     AND NOT has_function_privilege('anon', 'public.blog_publish_errors(uuid)', 'EXECUTE') $$,
  'internal builders and panel RPCs are not callable by anon'
);

-- ---------------------------------------------------------------------------
-- Reads as anon
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;

SELECT public.get_public_blog_by_key(:'key_a') AS list_a \gset
SELECT public.get_public_blog_by_key(:'key_a', 2, 2) AS page_2 \gset
SELECT public.get_public_blog_article_by_key(:'key_a', 'playas') AS art_a \gset
SELECT public.get_public_blog_article_by_key(:'key_b', 'playas') AS art_b \gset
SELECT public.get_public_blog_article_by_key(:'key_a', 'murallas') AS art_pending \gset
SELECT public.get_public_blog_article_by_key(:'key_a', 'borrador') AS miss_draft \gset
SELECT public.get_public_blog_article_by_key(:'key_a', 'retirado') AS miss_retired \gset
SELECT public.get_public_blog_article_by_key(:'key_a', 'no-existe') AS miss_unknown \gset
SELECT public.get_public_blog_article_by_key(:'key_b', 'murallas') AS miss_other \gset
SELECT public.get_public_blog(:'org_a'::uuid) AS transition_list \gset

SELECT tests.assert_raises(
  $$ SELECT public.get_public_blog_by_key('ctt_pk_inventada') $$,
  'PUBLIC_ACCESS_UNAVAILABLE', 'an unknown key gets the generic denial'
);
SELECT tests.assert_raises(
  format($$ SELECT public.get_public_blog(%L::uuid) $$, :'org_b'),
  'PUBLIC_ACCESS_UNAVAILABLE', 'the organization identifier only works for an agency in transition'
);
SELECT tests.assert_raises(
  format($$ SELECT public.get_public_blog_by_key(%L, 1, 51) $$, :'key_a'),
  'VALIDATION_ERROR', 'a page size over 50 is rejected'
);

RESET ROLE;

SELECT tests.assert_equals(:'list_a'::jsonb ->> 'source', 'panel', 'an agency without migration reads from the panel');
SELECT tests.assert_equals(:'list_a'::jsonb ->> 'total', '3', 'the list counts only published articles');
SELECT tests.assert_equals(:'list_a'::jsonb ->> 'pageSize', '12', 'the default page size is 12');
SELECT tests.assert_true(
  format($$ (SELECT array_agg(a ->> 'slug' ORDER BY o) FROM jsonb_array_elements(%L::jsonb -> 'articles') WITH ORDINALITY AS t(a, o))
            = ARRAY['murallas', 'comida', 'playas'] $$, :'list_a'),
  'articles come newest first by publication date'
);
SELECT tests.assert_true(
  format($$ jsonb_array_length(%1$L::jsonb -> 'articles') = 1
            AND (%1$L::jsonb -> 'articles' -> 0 ->> 'slug') = 'playas' $$, :'page_2'),
  'the list paginates'
);
SELECT tests.assert_true(
  format($$ (%1$L::jsonb -> 'articles' -> 0) ?& ARRAY['slug', 'cover', 'publishedAt', 'updatedAt', 'es', 'en']
            AND NOT ((%1$L::jsonb -> 'articles' -> 0 -> 'es') ? 'body') $$, :'list_a'),
  'list items carry slug, cover, dates and per-language title/summary, without the body'
);

SELECT tests.assert_equals(:'art_a'::jsonb ->> 'found', 'true', 'a published article is found by slug');
SELECT tests.assert_equals(:'art_a'::jsonb -> 'es' ->> 'title', 'Playas', 'the article of the key''s agency is returned');
SELECT tests.assert_equals(:'art_b'::jsonb -> 'es' ->> 'title', 'Playas de B', 'the same slug resolves to the other agency''s article with its key');
SELECT tests.assert_equals(:'art_a'::jsonb -> 'es' ->> 'seoTitle', 'SEO Playas', 'a written SEO title is returned');
SELECT tests.assert_equals(:'art_a'::jsonb -> 'en' ->> 'seoTitle', 'Playas EN', 'a missing SEO title falls back to the title');
SELECT tests.assert_equals(:'art_a'::jsonb -> 'en' ->> 'seoDescription', 'Summary Playas', 'a missing SEO description falls back to the summary');
SELECT tests.assert_true(
  format($$ (%1$L::jsonb -> 'es' -> 'body' -> 2 ->> 'src') LIKE '%%/blog/%%/a.webp'
            AND (%1$L::jsonb -> 'es' -> 'body' -> 2 ->> 'alt') = 'Foto'
            AND NOT ((%1$L::jsonb -> 'es' -> 'body' -> 2) ? 'ref')
            AND (%1$L::jsonb -> 'es' -> 'body' -> 3 ->> 'alt') = ''
            AND (%1$L::jsonb -> 'es' -> 'body' -> 3 ->> 'decorative') = 'true' $$, :'art_a'),
  'image blocks expose src and alt; a decorative image has an empty alt'
);
SELECT tests.assert_true(
  format($$ NOT ((%1$L::jsonb) ? 'en') $$, :'art_b'),
  'an es-only agency does not return English even if the article has it'
);
SELECT tests.assert_true(
  format($$ position('SECRETO' IN %1$L) = 0 AND position('revision' IN %1$L) = 0
            AND position('working' IN %1$L) = 0 AND position('updatedBy' IN %1$L) = 0
            AND (%1$L::jsonb -> 'es' ->> 'title') = 'Murallas' $$, :'art_pending'),
  'a pending revision, the revision counter and authors never reach the public read'
);

SELECT tests.assert_equals(:'miss_unknown', '{"found": false}', 'an unknown slug returns found false');
SELECT tests.assert_equals(:'miss_draft', :'miss_unknown', 'a draft returns the same body as an unknown slug');
SELECT tests.assert_equals(:'miss_retired', :'miss_unknown', 'a retired article returns the same body as an unknown slug');
SELECT tests.assert_equals(:'miss_other', :'miss_unknown', 'another agency''s slug returns the same body as an unknown slug');

SELECT tests.assert_equals(:'transition_list'::jsonb ->> 'total', '3', 'CTT can read its blog with the organization identifier during the transition');

-- Signed-in preview: the JWT agency wins over the argument.
SELECT pg_temp.act_as(:'op_b'::uuid, :'org_b'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT public.get_public_blog(:'org_a'::uuid) AS preview_b \gset
RESET ROLE;
SELECT tests.assert_true(
  format($$ (%1$L::jsonb ->> 'total') = '1' AND (%1$L::jsonb -> 'articles' -> 0 -> 'es' ->> 'title') = 'Playas de B' $$, :'preview_b'),
  'a signed-in caller previews its own agency and the argument is ignored'
);

-- ---------------------------------------------------------------------------
-- Republish and offered languages (FR-023)
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT public.republish_blog_article(:'p4'::uuid, pg_temp.rev(:'p4'::uuid));
UPDATE public.public_profiles SET languages = ARRAY['es'] WHERE organization_id = :'org_a'::uuid;

SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;
SELECT public.get_public_blog_article_by_key(:'key_a', 'retirado') AS back \gset
SELECT public.get_public_blog_by_key(:'key_a') AS list_es \gset
RESET ROLE;

SELECT tests.assert_equals(:'back'::jsonb ->> 'found', 'true', 'a republished article is readable again');
SELECT tests.assert_true(
  format($$ (%1$L::jsonb -> 'languages') = '["es"]'::jsonb
            AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(%1$L::jsonb -> 'articles') a WHERE a ? 'en') $$, :'list_es'),
  'when the agency stops offering English, the public read stops returning it'
);

-- ---------------------------------------------------------------------------
-- Performance probe (T057): the list uses the (organization_id, status, first_published_at) index.
-- ---------------------------------------------------------------------------

INSERT INTO public.blog_articles (organization_id, slug, status, first_published_at, public_updated_at)
SELECT :'org_b'::uuid, 'probe-' || g, 'published', now() - (g || ' minutes')::interval, now()
FROM generate_series(1, 1000) g;
ANALYZE public.blog_articles;

CREATE OR REPLACE FUNCTION pg_temp.list_plan(p_org uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_line text;
  v_plan text := '';
BEGIN
  FOR v_line IN EXECUTE format(
    'EXPLAIN SELECT id FROM public.blog_articles WHERE organization_id = %L AND status = %L '
    'ORDER BY first_published_at DESC LIMIT 12', p_org, 'published')
  LOOP
    v_plan := v_plan || v_line || E'\n';
  END LOOP;
  RETURN v_plan;
END;
$$;

SELECT tests.assert_true(
  format($$ position('blog_articles_public_list_idx' IN %L) > 0 $$, pg_temp.list_plan(:'org_b'::uuid)),
  'the public list query of an agency with 1000 articles uses the publication index'
);

ROLLBACK;
