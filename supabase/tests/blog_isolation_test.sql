-- blog_isolation_test.sql
-- Feature 013, US3: tenant isolation and role permissions for the blog (FR-014, FR-018, FR-019).
--
-- Run with: ./supabase/tests/run-sql-tests.sh supabase/tests/blog_isolation_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_a     13200000-0000-4000-a000-000000000001
\set org_b     13200000-0000-4000-a000-000000000002
\set op_a      13200000-0000-4000-b000-000000000001
\set agent_a   13200000-0000-4000-b000-000000000002
\set op_b      13200000-0000-4000-b000-000000000003

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

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (:'org_a'::uuid, 'Aislada A', 'aislada-a', 'active', '{}'::jsonb),
  (:'org_b'::uuid, 'Aislada B', 'aislada-b', 'active', '{}'::jsonb);

SELECT pg_temp.add_collaborator(:'op_a'::uuid, :'org_a'::uuid, 'op-a@iso.invalid', 'operator');
SELECT pg_temp.add_collaborator(:'agent_a'::uuid, :'org_a'::uuid, 'agent-a@iso.invalid', 'agent');
SELECT pg_temp.add_collaborator(:'op_b'::uuid, :'org_b'::uuid, 'op-b@iso.invalid', 'operator');

SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SELECT (public.save_blog_article('{"slug":"que-ver-en-cartagena","es":{"title":"A"}}'::jsonb) ->> 'id') AS art_a \gset
SELECT pg_temp.act_as(:'op_b'::uuid, :'org_b'::uuid, 'operator');
SELECT (public.save_blog_article('{"slug":"que-ver-en-cartagena","es":{"title":"B"}}'::jsonb) ->> 'id') AS art_b \gset

SELECT tests.assert_true(
  format($$ %L::uuid <> %L::uuid $$, :'art_a', :'art_b'),
  'two agencies can use the same slug as separate articles'
);

-- ---------------------------------------------------------------------------
-- Table access
-- ---------------------------------------------------------------------------

SET LOCAL ROLE anon;
SELECT tests.assert_raises($$ SELECT count(*) FROM public.blog_articles $$, 'permission denied', 'anon cannot read blog_articles');
SELECT tests.assert_raises($$ SELECT count(*) FROM public.blog_article_contents $$, 'permission denied', 'anon cannot read blog_article_contents');
SELECT tests.assert_raises($$ SELECT count(*) FROM public.public_blog_source $$, 'permission denied', 'anon cannot read public_blog_source');
SELECT tests.assert_raises($$ SELECT count(*) FROM public.public_blog_cutover_items $$, 'permission denied', 'anon cannot read public_blog_cutover_items');
RESET ROLE;

SELECT pg_temp.act_as(:'agent_a'::uuid, :'org_a'::uuid, 'agent');
SET LOCAL ROLE authenticated;
SELECT tests.assert_equals((SELECT count(*) FROM public.blog_articles), 0::bigint, 'an Agent sees no articles, not even of its own agency');
SELECT tests.assert_equals((SELECT count(*) FROM public.blog_article_contents), 0::bigint, 'an Agent sees no article content');
RESET ROLE;

SELECT pg_temp.act_as(:'op_a'::uuid, :'org_a'::uuid, 'operator');
SET LOCAL ROLE authenticated;
SELECT tests.assert_equals((SELECT count(*) FROM public.blog_articles), 1::bigint, 'an Operator sees only the articles of its agency');
SELECT tests.assert_raises(
  format($$ INSERT INTO public.blog_articles (organization_id, slug) VALUES (%L, 'directo') $$, :'org_a'),
  'permission denied', 'authenticated cannot insert articles directly'
);
SELECT tests.assert_raises(
  format($$ UPDATE public.blog_articles SET status = 'published' WHERE id = %L $$, :'art_a'),
  'permission denied', 'authenticated cannot update articles directly'
);
SELECT tests.assert_raises(
  format($$ DELETE FROM public.blog_article_contents WHERE article_id = %L $$, :'art_a'),
  'permission denied', 'authenticated cannot delete content directly'
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- Agent: FORBIDDEN on every blog RPC
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'agent_a'::uuid, :'org_a'::uuid, 'agent');
SELECT tests.assert_raises($$ SELECT public.list_blog_articles(NULL) $$, 'FORBIDDEN', 'an Agent cannot list articles');
SELECT tests.assert_raises($$ SELECT public.save_blog_article('{"es":{"title":"X"}}'::jsonb) $$, 'FORBIDDEN', 'an Agent cannot create articles');
SELECT tests.assert_raises(format($$ SELECT public.get_blog_article(%L) $$, :'art_a'), 'FORBIDDEN', 'an Agent cannot open an article');
SELECT tests.assert_raises(format($$ SELECT public.publish_blog_article(%L, 1) $$, :'art_a'), 'FORBIDDEN', 'an Agent cannot publish');
SELECT tests.assert_raises(format($$ SELECT public.retire_blog_article(%L, 1) $$, :'art_a'), 'FORBIDDEN', 'an Agent cannot retire');
SELECT tests.assert_raises(format($$ SELECT public.delete_blog_article(%L, 1) $$, :'art_a'), 'FORBIDDEN', 'an Agent cannot delete');
SELECT tests.assert_raises($$ SELECT public.get_blog_source() $$, 'FORBIDDEN', 'an Agent cannot read the blog source');

-- ---------------------------------------------------------------------------
-- Operator of another agency: NOT_FOUND, as if the article did not exist
-- ---------------------------------------------------------------------------

SELECT pg_temp.act_as(:'op_b'::uuid, :'org_b'::uuid, 'operator');
SELECT tests.assert_raises(format($$ SELECT public.get_blog_article(%L) $$, :'art_a'), 'NOT_FOUND', 'another agency cannot open the article');
SELECT tests.assert_raises(
  format($$ SELECT public.save_blog_article(%L::jsonb) $$,
         jsonb_build_object('id', :'art_a', 'expectedRevision', 1, 'es', jsonb_build_object('title', 'Hackeado'))),
  'NOT_FOUND', 'another agency cannot edit the article'
);
SELECT tests.assert_raises(format($$ SELECT public.publish_blog_article(%L, 1) $$, :'art_a'), 'NOT_FOUND', 'another agency cannot publish the article');
SELECT tests.assert_raises(format($$ SELECT public.publish_blog_article_changes(%L, 1) $$, :'art_a'), 'NOT_FOUND', 'another agency cannot publish changes');
SELECT tests.assert_raises(format($$ SELECT public.discard_blog_article_changes(%L, 1) $$, :'art_a'), 'NOT_FOUND', 'another agency cannot discard changes');
SELECT tests.assert_raises(format($$ SELECT public.retire_blog_article(%L, 1) $$, :'art_a'), 'NOT_FOUND', 'another agency cannot retire the article');
SELECT tests.assert_raises(format($$ SELECT public.republish_blog_article(%L, 1) $$, :'art_a'), 'NOT_FOUND', 'another agency cannot republish the article');
SELECT tests.assert_raises(format($$ SELECT public.delete_blog_article(%L, 1) $$, :'art_a'), 'NOT_FOUND', 'another agency cannot delete the article');
SELECT tests.assert_equals(
  jsonb_array_length(public.list_blog_articles(NULL))::bigint, 1::bigint,
  'the list of an agency only contains its own articles'
);

-- An image path of another agency is rejected even inside one's own article.
SELECT tests.assert_raises(
  format($$ SELECT public.save_blog_article(%L::jsonb) $$,
         jsonb_build_object('id', :'art_b', 'expectedRevision', pg_temp.rev(:'art_b'::uuid),
           'coverRef', :'org_a' || '/blog/' || :'art_b' || '/x.webp', 'es', jsonb_build_object('title', 'B'))),
  'INVALID_IMAGE_REF', 'an image path under another agency''s folder is rejected'
);

-- Operator cannot manage the blog source (Administrator only).
SELECT tests.assert_raises($$ SELECT public.set_blog_migration_required(true) $$, 'FORBIDDEN', 'an Operator cannot mark the blog as migrated');
SELECT tests.assert_raises($$ SELECT public.complete_blog_cutover() $$, 'FORBIDDEN', 'an Operator cannot complete the cutover');

SELECT tests.assert_equals(
  (SELECT title_es FROM public.blog_article_contents WHERE article_id = :'art_a'::uuid AND kind = 'working'),
  'A', 'none of the rejected operations changed the article of agency A'
);

ROLLBACK;
