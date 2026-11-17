-- 070_blog_public_read.sql
-- Public blog read for the site connected to each agency (feature 013, US2).
-- Source of truth: specs/013-editorial-content/contracts/public-consumer.md
--
-- Agency resolution is the one of 016: public key (*_by_key) or, only for CTT during its
-- transition, the organization identifier. A signed-in caller previews its own agency.
-- Only published articles and their published content are returned. Anything else is the
-- same {"found": false} (FR-022, FR-026). Kept apart from get_public_site (FR-037).

-- ---------------------------------------------------------------------------
-- Internal builders
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_public_source(p_organization_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT CASE WHEN public.blog_migration_open(p_organization_id) THEN 'legacy' ELSE 'panel' END;
$$;

-- Locales of a published content that the agency offers now and that have a title (FR-023).
CREATE OR REPLACE FUNCTION public.blog_public_locales(
  p_organization_id uuid,
  p_content public.blog_article_contents
)
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT ARRAY(
    SELECT l
    FROM unnest(public.blog_required_locales(p_organization_id)) AS l
    WHERE nullif(btrim(coalesce(
      CASE l WHEN 'en' THEN p_content.title_en ELSE p_content.title_es END, ''
    )), '') IS NOT NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.blog_public_body(p_body jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(jsonb_agg(
    CASE
      WHEN b.value ->> 'type' = 'image' THEN jsonb_build_object(
        'type', 'image',
        'src', b.value -> 'ref',
        'alt', CASE WHEN b.value -> 'decorative' = 'true'::jsonb THEN to_jsonb(''::text)
                    ELSE coalesce(b.value -> 'alt', 'null'::jsonb) END,
        'decorative', coalesce(b.value -> 'decorative', 'false'::jsonb)
      )
      ELSE b.value
    END
    ORDER BY b.ordinality
  ), '[]'::jsonb)
  FROM jsonb_array_elements(
    CASE WHEN jsonb_typeof(p_body) = 'array' THEN p_body ELSE '[]'::jsonb END
  ) WITH ORDINALITY AS b(value, ordinality);
$$;

CREATE OR REPLACE FUNCTION public.blog_public_locale_json(
  p_content public.blog_article_contents,
  p_locale text,
  p_full boolean
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_locale = 'en' THEN
      jsonb_build_object(
        'title', p_content.title_en,
        'summary', p_content.summary_en,
        'coverAlt', p_content.cover_alt_en
      ) || CASE WHEN p_full THEN jsonb_build_object(
        'seoTitle', coalesce(p_content.seo_title_en, p_content.title_en),
        'seoDescription', coalesce(p_content.seo_description_en, p_content.summary_en),
        'body', public.blog_public_body(p_content.body_en)
      ) ELSE '{}'::jsonb END
    ELSE
      jsonb_build_object(
        'title', p_content.title_es,
        'summary', p_content.summary_es,
        'coverAlt', p_content.cover_alt_es
      ) || CASE WHEN p_full THEN jsonb_build_object(
        'seoTitle', coalesce(p_content.seo_title_es, p_content.title_es),
        'seoDescription', coalesce(p_content.seo_description_es, p_content.summary_es),
        'body', public.blog_public_body(p_content.body_es)
      ) ELSE '{}'::jsonb END
  END;
$$;

CREATE OR REPLACE FUNCTION public.blog_public_article_json(
  p_organization_id uuid,
  p_article public.blog_articles,
  p_content public.blog_article_contents,
  p_full boolean
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_out jsonb;
  v_locale text;
BEGIN
  v_out := jsonb_build_object(
    'slug', p_article.slug,
    'cover', p_content.cover_ref,
    'publishedAt', p_article.first_published_at,
    'updatedAt', p_article.public_updated_at
  );
  FOREACH v_locale IN ARRAY public.blog_public_locales(p_organization_id, p_content)
  LOOP
    v_out := v_out || jsonb_build_object(v_locale, public.blog_public_locale_json(p_content, v_locale, p_full));
  END LOOP;
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.build_public_blog_list(
  p_organization_id uuid,
  p_page integer,
  p_page_size integer
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_page integer := coalesce(p_page, 1);
  v_size integer := coalesce(p_page_size, 12);
  v_source text := public.blog_public_source(p_organization_id);
  v_total bigint := 0;
  v_articles jsonb := '[]'::jsonb;
BEGIN
  IF v_page < 1 OR v_size < 1 OR v_size > 50 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_source = 'panel' THEN
    SELECT count(*) INTO v_total
    FROM public.blog_articles a
    WHERE a.organization_id = p_organization_id AND a.status = 'published';

    SELECT coalesce(jsonb_agg(item ORDER BY published_at DESC, slug), '[]'::jsonb)
    INTO v_articles
    FROM (
      SELECT
        a.first_published_at AS published_at,
        a.slug,
        public.blog_public_article_json(p_organization_id, a, c, false) AS item
      FROM public.blog_articles a
      JOIN public.blog_article_contents c ON c.article_id = a.id AND c.kind = 'published'
      WHERE a.organization_id = p_organization_id
        AND a.status = 'published'
      ORDER BY a.first_published_at DESC, a.slug
      OFFSET (v_page - 1) * v_size
      LIMIT v_size
    ) page_rows;
  END IF;

  RETURN jsonb_build_object(
    'source', v_source,
    'languages', to_jsonb(public.blog_required_locales(p_organization_id)),
    'page', v_page,
    'pageSize', v_size,
    'total', v_total,
    'generatedAt', now(),
    'articles', v_articles
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.build_public_blog_article(p_organization_id uuid, p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_slug text := btrim(coalesce(p_slug, ''));
  v_article public.blog_articles;
  v_content public.blog_article_contents;
BEGIN
  IF v_slug = '' OR char_length(v_slug) > 200
     OR public.blog_public_source(p_organization_id) <> 'panel'
  THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  SELECT a.* INTO v_article
  FROM public.blog_articles a
  WHERE a.organization_id = p_organization_id
    AND a.slug = v_slug
    AND a.status = 'published';

  IF v_article.id IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  SELECT c.* INTO v_content
  FROM public.blog_article_contents c
  WHERE c.article_id = v_article.id AND c.kind = 'published';

  IF v_content.article_id IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  RETURN jsonb_build_object('found', true)
    || public.blog_public_article_json(p_organization_id, v_article, v_content, true);
END;
$$;

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_resolve_reader_org(p_organization_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RETURN nullif(auth.jwt() ->> 'organization_id', '')::uuid;
  END IF;
  RETURN public.require_organization_identifier_access(p_organization_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_blog_by_key(
  p_key text,
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 12
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.build_public_blog_list(public.resolve_public_access_key(p_key), p_page, p_page_size);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_blog_article_by_key(p_key text, p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.build_public_blog_article(public.resolve_public_access_key(p_key), p_slug);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_blog(
  p_organization_id uuid,
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 12
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.blog_resolve_reader_org(p_organization_id);
BEGIN
  IF v_org IS NULL THEN
    RETURN jsonb_build_object(
      'source', 'panel', 'languages', '[]'::jsonb, 'page', 1, 'pageSize', 12,
      'total', 0, 'generatedAt', now(), 'articles', '[]'::jsonb
    );
  END IF;
  RETURN public.build_public_blog_list(v_org, p_page, p_page_size);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_blog_article(p_organization_id uuid, p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.blog_resolve_reader_org(p_organization_id);
BEGIN
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;
  RETURN public.build_public_blog_article(v_org, p_slug);
END;
$$;

COMMENT ON FUNCTION public.get_public_blog_by_key(text, integer, integer) IS
  'Anon: published blog articles of the agency that owns the key, newest first. Invalid keys get '
  'PUBLIC_ACCESS_UNAVAILABLE.';
COMMENT ON FUNCTION public.get_public_blog_article_by_key(text, text) IS
  'Anon: one published article by slug, or {"found": false}.';
COMMENT ON FUNCTION public.get_public_blog(uuid, integer, integer) IS
  'Authenticated: own agency preview. Anon: CTT transition only; afterwards use get_public_blog_by_key.';
COMMENT ON FUNCTION public.get_public_blog_article(uuid, text) IS
  'Authenticated: own agency preview. Anon: CTT transition only; afterwards use the _by_key variant.';

REVOKE ALL ON FUNCTION public.blog_public_source(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_public_locales(uuid, public.blog_article_contents) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_public_body(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_public_locale_json(public.blog_article_contents, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_public_article_json(uuid, public.blog_articles, public.blog_article_contents, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.build_public_blog_list(uuid, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.build_public_blog_article(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_resolve_reader_org(uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.blog_public_source(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_public_locales(uuid, public.blog_article_contents) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_public_body(jsonb) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_public_locale_json(public.blog_article_contents, text, boolean) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_public_article_json(uuid, public.blog_articles, public.blog_article_contents, boolean) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.build_public_blog_list(uuid, integer, integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.build_public_blog_article(uuid, text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_resolve_reader_org(uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.get_public_blog_by_key(text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_blog_article_by_key(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_blog(uuid, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_blog_article(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_public_blog_by_key(text, integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_blog_article_by_key(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_blog(uuid, integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_blog_article(uuid, text) TO anon, authenticated;
