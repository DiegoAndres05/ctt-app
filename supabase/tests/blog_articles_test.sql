-- blog_articles_test.sql
-- Feature 013: article lifecycle in the panel (US1 drafts, US2 publish, US4 revisions, US5 retire).
--
-- RPCs are called as the harness superuser with JWT claims set by pg_temp.act_as: the
-- SECURITY DEFINER functions authorize from the claims and the live profile, not from the SQL
-- role. Role grants and RLS are covered in blog_isolation_test.sql.
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/blog_articles_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a     13000000-0000-4000-a000-000000000001
\set org_b     13000000-0000-4000-a000-000000000002
\set op_a      13000000-0000-4000-b000-000000000001
\set op_b      13000000-0000-4000-b000-000000000002

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

-- Complete content for one article: cover, a paragraph and an image with alt in each locale.
CREATE OR REPLACE FUNCTION pg_temp.payload(
  p_id uuid, p_title text, p_en boolean DEFAULT true, p_extra jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid := (SELECT organization_id FROM public.blog_articles WHERE id = p_id);
  v_prefix text := v_org::text || '/blog/' || p_id::text || '/';
  v_payload jsonb;
BEGIN
  v_payload := jsonb_build_object(
    'id', p_id,
    'expectedRevision', pg_temp.rev(p_id),
    'coverRef', v_prefix || 'cover.webp',
    'es', jsonb_build_object(
      'title', p_title,
      'summary', 'Resumen de ' || p_title,
      'coverAlt', 'Portada',
      'body', jsonb_build_array(
        jsonb_build_object('type', 'paragraph', 'text', jsonb_build_array(jsonb_build_object('text', 'Texto de ' || p_title))),
        jsonb_build_object('type', 'image', 'ref', v_prefix || 'img1.webp', 'alt', 'Foto')
      )
    )
  );
  IF p_en THEN
    v_payload := v_payload || jsonb_build_object('en', jsonb_build_object(
      'title', p_title || ' EN',
      'summary', 'Summary of ' || p_title,
      'coverAlt', 'Cover',
      'body', jsonb_build_array(
        jsonb_build_object('type', 'paragraph', 'text', jsonb_build_array(jsonb_build_object('text', 'Text of ' || p_title))),
        jsonb_build_object('type', 'image', 'ref', v_prefix || 'img1.webp', 'alt', 'Photo')
      )
    ));
  END IF;
  RETURN v_payload || p_extra;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.create_article(p_title text, p_extra jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE sql AS $$
  SELECT (public.save_blog_article(
    jsonb_build_object('es', jsonb_build_object('title', p_title)) || p_extra
  ) ->> 'id')::uuid;
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

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_a'::uuid, 'Blog A', 'blog-a', 'active', '{}'::jsonb),
  (:'org_b'::uuid, 'Blog B', 'blog-b', 'active', '{}'::jsonb);

-- A offers es + en (profile default); B offers only es.
UPDATE public.public_profiles SET languages = ARRAY['es'] WHERE organization_id = :'org_b'::uuid;

SELECT pg_temp.add_collaborator(:'op_a'::uuid, :'org_a'::uuid, 'op-a@blog.invalid', 'operator');
SELECT pg_temp.add_collaborator(:'op_b'::uuid, :'org_b'::uuid, 'op-b@blog.invalid', 'operator');

SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');

-- ---------------------------------------------------------------------------
-- US1: drafts
-- ---------------------------------------------------------------------------

SELECT pg_temp.create_article('Qué ver en Cartagena') AS a1 \gset
SELECT pg_temp.create_article('Qué ver en Cartagena') AS a2 \gset

SELECT tests.assert_equals(
  (SELECT slug FROM public.blog_articles WHERE id = :'a1'::uuid), 'que-ver-en-cartagena',
  'a draft with only a title gets a slug proposed from the title, without accents'
);
SELECT tests.assert_equals(
  (SELECT slug FROM public.blog_articles WHERE id = :'a2'::uuid), 'que-ver-en-cartagena-2',
  'a repeated proposed slug gets a numeric suffix'
);
SELECT tests.assert_equals(
  (SELECT status::text FROM public.blog_articles WHERE id = :'a1'::uuid), 'draft',
  'a new article starts as a draft'
);
SELECT tests.assert_true(
  format($$ EXISTS (SELECT 1 FROM public.blog_article_contents WHERE article_id = %L AND kind = 'working')
            AND NOT EXISTS (SELECT 1 FROM public.blog_article_contents WHERE article_id = %L AND kind = 'published') $$,
         :'a1', :'a1'),
  'a draft has only working content'
);

SELECT tests.assert_raises(
  $$ SELECT public.save_blog_article('{"slug":"Mal Slug","es":{"title":"X"}}'::jsonb) $$,
  'INVALID_SLUG', 'a slug outside the strict format is rejected'
);
SELECT tests.assert_raises(
  $$ SELECT public.save_blog_article('{"slug":"que-ver-en-cartagena","es":{"title":"X"}}'::jsonb) $$,
  'SLUG_TAKEN', 'a slug already used in the agency is rejected'
);
SELECT tests.assert_raises(
  $$ SELECT public.save_blog_article('{"es":{"summary":"sin titulo"}}'::jsonb) $$,
  'VALIDATION_ERROR', 'an article cannot be created without a title in any language'
);
SELECT tests.assert_raises(
  format($$ SELECT public.save_blog_article(%L::jsonb) $$,
         jsonb_build_object('es', jsonb_build_object('title', repeat('x', 121)))),
  'VALIDATION_ERROR', 'a title over 120 characters is rejected'
);
SELECT tests.assert_raises(
  $$ SELECT public.save_blog_article('{"es":{"title":"X"},"originalPublishedAt":"2020-01-01"}'::jsonb) $$,
  'MIGRATION_CLOSED', 'only migrated articles accept an original publication date'
);

-- A full save with a script block and a javascript: link: both are cleaned.
SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Cartagena', true, jsonb_build_object(
  'es', jsonb_build_object(
    'title', 'Cartagena', 'summary', 'Resumen', 'coverAlt', 'Portada',
    'body', jsonb_build_array(
      jsonb_build_object('type', 'script', 'text', 'alert(1)'),
      jsonb_build_object('type', 'html', 'html', '<iframe src=x>'),
      jsonb_build_object('type', 'paragraph', 'text', jsonb_build_array(
        jsonb_build_object('text', 'Haz clic', 'href', 'javascript:alert(1)', 'bold', true),
        jsonb_build_object('text', ' o visita', 'href', 'https://example.com/ok', 'onclick', 'x')
      )),
      jsonb_build_object('type', 'image', 'ref', :'org_a' || '/blog/' || :'a1' || '/img1.webp', 'alt', 'Foto')
    )
  )
)));

SELECT tests.assert_true(
  format($$ (SELECT body_es::text FROM public.blog_article_contents WHERE article_id = %L AND kind = 'working')
            NOT LIKE '%%script%%' $$, :'a1'),
  'unknown block types (script, html) are dropped on save'
);
SELECT tests.assert_true(
  format($$ (SELECT body_es::text FROM public.blog_article_contents WHERE article_id = %L AND kind = 'working')
            NOT LIKE '%%javascript%%'
         AND (SELECT body_es::text FROM public.blog_article_contents WHERE article_id = %L AND kind = 'working')
            NOT LIKE '%%onclick%%'
         AND (SELECT body_es::text FROM public.blog_article_contents WHERE article_id = %L AND kind = 'working')
            LIKE '%%https://example.com/ok%%' $$, :'a1', :'a1', :'a1'),
  'a javascript: href and unknown inline keys are removed; an https link stays'
);
SELECT tests.assert_equals(
  (SELECT jsonb_array_length(body_es)::bigint FROM public.blog_article_contents WHERE article_id = :'a1'::uuid AND kind = 'working'),
  2::bigint, 'the cleaned body keeps only the paragraph and the image'
);

SELECT tests.assert_raises(
  format($$ SELECT public.save_blog_article(%L::jsonb) $$,
         jsonb_build_object('id', :'a1', 'expectedRevision', 1, 'es', jsonb_build_object('title', 'Viejo'))),
  'ARTICLE_CONFLICT', 'saving with a stale revision is a conflict and does not overwrite'
);
SELECT tests.assert_raises(
  format($$ SELECT public.save_blog_article(%L::jsonb) $$,
         pg_temp.payload(:'a1'::uuid, 'Cartagena') || jsonb_build_object('coverRef', :'org_b' || '/blog/' || :'a1' || '/x.webp')),
  'INVALID_IMAGE_REF', 'a cover outside the article folder of the agency is rejected'
);
SELECT tests.assert_raises(
  format($$ SELECT public.save_blog_article(%L::jsonb) $$,
         pg_temp.payload(:'a1'::uuid, 'Cartagena') || jsonb_build_object('coverRef', 'https://cdn.example.com/x.jpg')),
  'INVALID_IMAGE_REF', 'an external image URL is rejected for a non-migrated article'
);
SELECT tests.assert_raises(
  format($$ SELECT public.save_blog_article(%L::jsonb) $$,
         pg_temp.payload(:'a1'::uuid, 'Cartagena') || jsonb_build_object('es', jsonb_build_object(
           'title', 'X', 'body', jsonb_build_array(jsonb_build_object('type', 'image', 'ref', '../../etc/passwd'))))),
  'INVALID_IMAGE_REF', 'a body image outside the article folder is rejected'
);

SELECT tests.assert_equals(
  jsonb_array_length(public.list_blog_articles('draft'))::bigint, 2::bigint,
  'the panel lists the two drafts of the agency'
);
SELECT tests.assert_raises(
  $$ SELECT public.list_blog_articles('borrador') $$, 'VALIDATION_ERROR', 'an unknown status filter is rejected'
);

SELECT public.delete_blog_article(:'a2'::uuid, pg_temp.rev(:'a2'::uuid));
SELECT tests.assert_true(
  format($$ NOT EXISTS (SELECT 1 FROM public.blog_articles WHERE id = %L) $$, :'a2'),
  'a draft that was never published can be deleted'
);
SELECT tests.assert_true(
  $$ EXISTS (SELECT 1 FROM audit.audit_events WHERE event_type = 'blog_article_deleted') $$,
  'deleting a draft is audited'
);

-- ---------------------------------------------------------------------------
-- US2: publish
-- ---------------------------------------------------------------------------

SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Cartagena', false));

SELECT pg_temp.detail_of(format($$ SELECT public.publish_blog_article(%L, %s) $$, :'a1', pg_temp.rev(:'a1'::uuid))) AS missing \gset
SELECT tests.assert_raises(
  format($$ SELECT public.publish_blog_article(%L, %s) $$, :'a1', pg_temp.rev(:'a1'::uuid)),
  'PUBLISH_INCOMPLETE', 'an article without the English version cannot be published in an es+en agency'
);
SELECT tests.assert_true(
  format($$ %L::jsonb @> '[{"field":"title","locale":"en"},{"field":"body","locale":"en"}]'::jsonb
            AND NOT %L::jsonb @> '[{"locale":"es"}]'::jsonb $$, :'missing', :'missing'),
  'PUBLISH_INCOMPLETE lists the missing fields per language in DETAIL'
);
SELECT tests.assert_equals(
  (SELECT status::text FROM public.blog_articles WHERE id = :'a1'::uuid), 'draft',
  'a rejected publication leaves the article in draft'
);

-- An image without alt also blocks publishing; a decorative one does not.
SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Cartagena', true) || jsonb_build_object(
  'es', (pg_temp.payload(:'a1'::uuid, 'Cartagena') -> 'es') || jsonb_build_object('body', jsonb_build_array(
    jsonb_build_object('type', 'paragraph', 'text', jsonb_build_array(jsonb_build_object('text', 'Hola'))),
    jsonb_build_object('type', 'image', 'ref', :'org_a' || '/blog/' || :'a1' || '/img2.webp')
  ))
));
SELECT tests.assert_true(
  format($$ %L::jsonb @> '[{"field":"imageAlt","locale":"es"}]'::jsonb $$,
         pg_temp.detail_of(format($$ SELECT public.publish_blog_article(%L, %s) $$, :'a1', pg_temp.rev(:'a1'::uuid)))),
  'an image without alt text blocks publishing in that language'
);

SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Cartagena', true));
SELECT public.publish_blog_article(:'a1'::uuid, pg_temp.rev(:'a1'::uuid)) AS published \gset

SELECT tests.assert_equals(:'published'::jsonb ->> 'status', 'published', 'a complete article is published');
SELECT tests.assert_true(
  format($$ (SELECT first_published_at IS NOT NULL AND public_updated_at IS NOT NULL FROM public.blog_articles WHERE id = %L) $$, :'a1'),
  'publishing assigns the publication and public update dates'
);
SELECT tests.assert_true(
  format($$ EXISTS (SELECT 1 FROM public.blog_article_contents WHERE article_id = %L AND kind = 'published')
            AND NOT EXISTS (SELECT 1 FROM public.blog_article_contents WHERE article_id = %L AND kind = 'working') $$,
         :'a1', :'a1'),
  'publishing moves the working content to published'
);
SELECT tests.assert_true(
  $$ EXISTS (
       SELECT 1 FROM audit.audit_events
       WHERE event_type = 'blog_article_published'
         AND metadata ->> 'slug' = 'que-ver-en-cartagena'
         AND metadata -> 'locales' = '["es","en"]'::jsonb
         AND metadata::text NOT LIKE '%Cartagena EN%'
         AND metadata::text NOT LIKE '%Texto%'
     ) $$,
  'publishing is audited with slug and locales, never title or body'
);
SELECT tests.assert_raises(
  format($$ SELECT public.publish_blog_article(%L, %s) $$, :'a1', pg_temp.rev(:'a1'::uuid)),
  'INVALID_TRANSITION', 'a published article cannot be published again'
);

-- Agency B only offers Spanish: no English needed.
SELECT pg_temp.act_as(:'op_b'::uuid, :'org_b'::uuid, 'operator');
SELECT pg_temp.create_article('Solo español') AS b1 \gset
SELECT public.save_blog_article(pg_temp.payload(:'b1'::uuid, 'Solo español', false));
SELECT public.publish_blog_article(:'b1'::uuid, pg_temp.rev(:'b1'::uuid)) AS b_published \gset
SELECT tests.assert_equals(:'b_published'::jsonb ->> 'status', 'published', 'an es-only agency publishes without English');
SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');

-- ---------------------------------------------------------------------------
-- US4: pending revision
-- ---------------------------------------------------------------------------

SELECT first_published_at AS first_pub, public_updated_at AS first_updated
FROM public.blog_articles WHERE id = :'a1'::uuid \gset

SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Cartagena renovada', true)) AS pending \gset

SELECT tests.assert_equals(:'pending'::jsonb ->> 'hasPendingChanges', 'true', 'editing a published article creates a pending revision');
SELECT tests.assert_equals(
  (SELECT title_es FROM public.blog_article_contents WHERE article_id = :'a1'::uuid AND kind = 'published'),
  'Cartagena', 'the published version is untouched by a pending revision'
);
SELECT tests.assert_raises(
  format($$ SELECT public.save_blog_article(%L::jsonb) $$,
         pg_temp.payload(:'a1'::uuid, 'Cartagena renovada') || '{"slug":"otro-slug"}'::jsonb),
  'SLUG_LOCKED', 'the slug cannot change after the first publication'
);

-- An incomplete revision can be saved but not published.
SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Cartagena renovada', true)
  || jsonb_build_object('es', jsonb_build_object('title', 'Cartagena renovada')));
SELECT tests.assert_raises(
  format($$ SELECT public.publish_blog_article_changes(%L, %s) $$, :'a1', pg_temp.rev(:'a1'::uuid)),
  'PUBLISH_INCOMPLETE', 'an incomplete revision cannot be published'
);
SELECT tests.assert_equals(
  (SELECT title_es FROM public.blog_article_contents WHERE article_id = :'a1'::uuid AND kind = 'published'),
  'Cartagena', 'a rejected revision leaves the published version as it was'
);

SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Cartagena renovada', true));
SELECT pg_sleep(0.01);
SELECT public.publish_blog_article_changes(:'a1'::uuid, pg_temp.rev(:'a1'::uuid)) AS changed \gset

SELECT tests.assert_equals(
  (SELECT title_es FROM public.blog_article_contents WHERE article_id = :'a1'::uuid AND kind = 'published'),
  'Cartagena renovada', 'publishing changes replaces the published version'
);
SELECT tests.assert_true(
  format($$ (SELECT first_published_at = %L::timestamptz AND slug = 'que-ver-en-cartagena'
             FROM public.blog_articles WHERE id = %L) $$, :'first_pub', :'a1'),
  'publishing changes keeps the slug and the original publication date'
);
SELECT tests.assert_equals(:'changed'::jsonb ->> 'hasPendingChanges', 'false', 'no revision is pending after publishing it');
SELECT tests.assert_true(
  $$ EXISTS (SELECT 1 FROM audit.audit_events WHERE event_type = 'blog_article_changes_published') $$,
  'publishing changes is audited'
);

SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Borrador descartable', true));
SELECT public.discard_blog_article_changes(:'a1'::uuid, pg_temp.rev(:'a1'::uuid));
SELECT tests.assert_true(
  format($$ NOT EXISTS (SELECT 1 FROM public.blog_article_contents WHERE article_id = %L AND kind = 'working')
            AND (SELECT title_es FROM public.blog_article_contents WHERE article_id = %L AND kind = 'published') = 'Cartagena renovada' $$,
         :'a1', :'a1'),
  'discarding changes removes the revision and keeps the published version'
);
SELECT tests.assert_raises(
  format($$ SELECT public.discard_blog_article_changes(%L, %s) $$, :'a1', pg_temp.rev(:'a1'::uuid)),
  'INVALID_TRANSITION', 'there is nothing to discard without a pending revision'
);

-- ---------------------------------------------------------------------------
-- US5: retire and republish
-- ---------------------------------------------------------------------------

SELECT public.save_blog_article(pg_temp.payload(:'a1'::uuid, 'Revisión pendiente', true));
SELECT public.retire_blog_article(:'a1'::uuid, pg_temp.rev(:'a1'::uuid)) AS retired \gset

SELECT tests.assert_equals(:'retired'::jsonb ->> 'status', 'retired', 'a published article can be retired');
SELECT tests.assert_equals(:'retired'::jsonb ->> 'hasPendingChanges', 'true', 'retiring keeps a pending revision');
SELECT tests.assert_raises(
  format($$ SELECT public.delete_blog_article(%L, %s) $$, :'a1', pg_temp.rev(:'a1'::uuid)),
  'NOT_DELETABLE', 'an article that was published cannot be deleted, only retired'
);
SELECT tests.assert_raises(
  format($$ SELECT public.retire_blog_article(%L, %s) $$, :'a1', pg_temp.rev(:'a1'::uuid)),
  'INVALID_TRANSITION', 'a retired article cannot be retired again'
);
SELECT tests.assert_true(
  $$ EXISTS (SELECT 1 FROM audit.audit_events WHERE event_type = 'blog_article_retired') $$,
  'retiring is audited'
);

SELECT public.republish_blog_article(:'a1'::uuid, pg_temp.rev(:'a1'::uuid)) AS republished \gset
SELECT tests.assert_true(
  format($$ (SELECT status = 'published' AND first_published_at = %L::timestamptz AND slug = 'que-ver-en-cartagena'
             FROM public.blog_articles WHERE id = %L) $$, :'first_pub', :'a1'),
  'republishing restores the article with the same slug and publication date'
);
SELECT tests.assert_equals(
  (SELECT title_es FROM public.blog_article_contents WHERE article_id = :'a1'::uuid AND kind = 'published'),
  'Cartagena renovada', 'republishing shows the published version, not the pending revision'
);

SELECT pg_temp.create_article('Otro borrador') AS a3 \gset
SELECT tests.assert_raises(
  format($$ SELECT public.retire_blog_article(%L, %s) $$, :'a3', pg_temp.rev(:'a3'::uuid)),
  'INVALID_TRANSITION', 'a draft cannot be retired'
);
SELECT tests.assert_raises(
  format($$ SELECT public.republish_blog_article(%L, %s) $$, :'a3', pg_temp.rev(:'a3'::uuid)),
  'INVALID_TRANSITION', 'a draft cannot be republished'
);

SELECT public.get_blog_article(:'a1'::uuid) AS detail \gset
SELECT tests.assert_true(
  format($$ (%L::jsonb -> 'requiredLocales') = '["es","en"]'::jsonb
            AND (%L::jsonb -> 'published' -> 'es' ->> 'title') = 'Cartagena renovada'
            AND (%L::jsonb -> 'working' -> 'es' ->> 'title') = 'Revisión pendiente' $$,
         :'detail', :'detail', :'detail'),
  'the panel detail returns required locales, the published version and the pending revision'
);

ROLLBACK;
