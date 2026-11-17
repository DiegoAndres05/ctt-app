-- 069_blog_management_rpcs.sql
-- Panel RPCs for blog articles (feature 013, US1–US5 and the migrated-article part of US6).
-- Source of truth: specs/013-editorial-content/contracts/management.md
--
-- ERROR CONTRACT: the exception message is the API code. PUBLISH_INCOMPLETE carries
-- [{field, locale}] as JSON in DETAIL.
-- The agency always comes from the JWT (require_catalog_manager_or_forbidden). An article of
-- another agency is NOT_FOUND, never FORBIDDEN, so ids cannot be probed (FR-019).

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_slugify(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(
    nullif(
      btrim(
        left(
          btrim(
            regexp_replace(
              translate(
                lower(coalesce(p_text, '')),
                'áàâäãéèêëíìîïóòôöõúùûüñç',
                'aaaaaeeeeiiiiooooouuuunc'
              ),
              '[^a-z0-9]+', '-', 'g'
            ),
            '-'
          ),
          110
        ),
        '-'
      ),
      ''
    ),
    'articulo'
  );
$$;

CREATE OR REPLACE FUNCTION public.blog_slug_strict_valid(p_slug text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_slug IS NOT NULL
    AND char_length(p_slug) BETWEEN 1 AND 120
    AND p_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$';
$$;

CREATE OR REPLACE FUNCTION public.blog_slug_legacy_valid(p_slug text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_slug IS NOT NULL
    AND char_length(p_slug) BETWEEN 1 AND 200
    AND p_slug = btrim(p_slug)
    AND p_slug !~ '[[:space:]/?#]';
$$;

CREATE OR REPLACE FUNCTION public.blog_migration_open(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.public_blog_source s
    WHERE s.organization_id = p_organization_id
      AND s.migration_required
      AND s.cutover_completed_at IS NULL
  );
$$;

-- Locks the caller's article and checks the expected revision.
CREATE OR REPLACE FUNCTION public.blog_lock_article(
  p_id uuid,
  p_organization_id uuid,
  p_expected_revision integer
)
RETURNS public.blog_articles
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_article public.blog_articles;
BEGIN
  SELECT a.* INTO v_article
  FROM public.blog_articles a
  WHERE a.id = p_id AND a.organization_id = p_organization_id
  FOR UPDATE;

  IF v_article.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_expected_revision IS NULL OR p_expected_revision <> v_article.revision THEN
    RAISE EXCEPTION 'ARTICLE_CONFLICT' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_article;
END;
$$;

CREATE OR REPLACE FUNCTION public.blog_article_state(p_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'id', a.id,
    'revision', a.revision,
    'status', a.status,
    'hasPendingChanges', a.status <> 'draft' AND EXISTS (
      SELECT 1 FROM public.blog_article_contents c
      WHERE c.article_id = a.id AND c.kind = 'working'
    ),
    'firstPublishedAt', a.first_published_at,
    'publicUpdatedAt', a.public_updated_at
  )
  FROM public.blog_articles a
  WHERE a.id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.blog_content_json(p_content public.blog_article_contents)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE WHEN p_content.article_id IS NULL THEN NULL ELSE jsonb_build_object(
    'coverRef', p_content.cover_ref,
    'updatedAt', p_content.updated_at,
    'es', jsonb_build_object(
      'title', p_content.title_es,
      'summary', p_content.summary_es,
      'coverAlt', p_content.cover_alt_es,
      'body', p_content.body_es,
      'seoTitle', p_content.seo_title_es,
      'seoDescription', p_content.seo_description_es
    ),
    'en', jsonb_build_object(
      'title', p_content.title_en,
      'summary', p_content.summary_en,
      'coverAlt', p_content.cover_alt_en,
      'body', p_content.body_en,
      'seoTitle', p_content.seo_title_en,
      'seoDescription', p_content.seo_description_en
    )
  ) END;
$$;

CREATE OR REPLACE FUNCTION public.blog_audit(
  p_organization_id uuid,
  p_event audit.audit_event_type,
  p_article public.blog_articles,
  p_extra jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  PERFORM audit.log_event(
    p_organization_id,
    p_event,
    'success'::audit.audit_result,
    auth.uid(),
    'blog_article',
    p_article.id,
    jsonb_build_object(
      'articleId', p_article.id,
      'slug', p_article.slug,
      'locales', to_jsonb(public.blog_required_locales(p_organization_id))
    ) || coalesce(p_extra, '{}'::jsonb)
  );
END;
$$;

-- Reads one locale of the payload into trimmed, length-checked values (FR-006).
CREATE OR REPLACE FUNCTION public.blog_payload_text(
  p_locale jsonb,
  p_key text,
  p_max integer
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_value text;
BEGIN
  IF p_locale IS NULL OR jsonb_typeof(p_locale) <> 'object' THEN
    RETURN NULL;
  END IF;
  IF p_locale -> p_key IS NULL OR jsonb_typeof(p_locale -> p_key) = 'null' THEN
    RETURN NULL;
  END IF;
  IF jsonb_typeof(p_locale -> p_key) <> 'string' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_value := nullif(btrim(p_locale ->> p_key), '');
  IF v_value IS NOT NULL AND char_length(v_value) > p_max THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = p_key;
  END IF;
  RETURN v_value;
END;
$$;

-- ---------------------------------------------------------------------------
-- save_blog_article: create, or write the working content (draft or pending revision).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_blog_article(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_user uuid := auth.uid();
  v_article public.blog_articles;
  v_id uuid;
  v_creating boolean;
  v_migrated boolean := false;
  v_original timestamptz;
  v_slug text;
  v_base text;
  v_suffix integer := 1;
  v_es jsonb;
  v_en jsonb;
  v_cover text;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
     OR octet_length(p_payload::text) > 614400
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  BEGIN
    v_id := nullif(p_payload ->> 'id', '')::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  v_creating := v_id IS NULL;
  v_es := p_payload -> 'es';
  v_en := p_payload -> 'en';
  v_cover := nullif(btrim(coalesce(p_payload ->> 'coverRef', '')), '');

  IF v_creating THEN
    -- FR-002: a title in one language is enough to create.
    IF public.blog_payload_text(v_es, 'title', 120) IS NULL
       AND public.blog_payload_text(v_en, 'title', 120) IS NULL
    THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'title';
    END IF;

    v_migrated := coalesce(p_payload -> 'migrated' = 'true'::jsonb, false);
    IF v_migrated AND NOT public.blog_migration_open(v_org) THEN
      RAISE EXCEPTION 'MIGRATION_CLOSED' USING ERRCODE = 'raise_exception';
    END IF;

    IF nullif(p_payload ->> 'originalPublishedAt', '') IS NOT NULL THEN
      IF NOT v_migrated THEN
        RAISE EXCEPTION 'MIGRATION_CLOSED' USING ERRCODE = 'raise_exception';
      END IF;
      BEGIN
        v_original := (p_payload ->> 'originalPublishedAt')::timestamptz;
      EXCEPTION
        WHEN others THEN
          RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'originalPublishedAt';
      END;
      IF v_original > now() THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception', DETAIL = 'originalPublishedAt';
      END IF;
    END IF;

    v_slug := nullif(btrim(coalesce(p_payload ->> 'slug', '')), '');
    IF v_slug IS NULL THEN
      v_base := public.blog_slugify(coalesce(
        public.blog_payload_text(v_es, 'title', 120),
        public.blog_payload_text(v_en, 'title', 120)
      ));
      v_slug := v_base;
      WHILE EXISTS (
        SELECT 1 FROM public.blog_articles a WHERE a.organization_id = v_org AND a.slug = v_slug
      ) LOOP
        v_suffix := v_suffix + 1;
        v_slug := v_base || '-' || v_suffix;
      END LOOP;
    ELSIF v_migrated THEN
      IF NOT public.blog_slug_legacy_valid(v_slug) THEN
        RAISE EXCEPTION 'INVALID_SLUG' USING ERRCODE = 'raise_exception';
      END IF;
    ELSIF NOT public.blog_slug_strict_valid(v_slug) THEN
      RAISE EXCEPTION 'INVALID_SLUG' USING ERRCODE = 'raise_exception';
    END IF;

    IF EXISTS (SELECT 1 FROM public.blog_articles a WHERE a.organization_id = v_org AND a.slug = v_slug) THEN
      RAISE EXCEPTION 'SLUG_TAKEN' USING ERRCODE = 'raise_exception';
    END IF;

    v_id := gen_random_uuid();
    INSERT INTO public.blog_articles (
      id, organization_id, slug, status, migrated, original_published_at, created_by, updated_by
    )
    VALUES (v_id, v_org, v_slug, 'draft', v_migrated, v_original, v_user, v_user)
    RETURNING * INTO v_article;
  ELSE
    v_article := public.blog_lock_article(
      v_id, v_org,
      CASE WHEN jsonb_typeof(p_payload -> 'expectedRevision') = 'number'
           THEN (p_payload ->> 'expectedRevision')::integer END
    );

    v_slug := nullif(btrim(coalesce(p_payload ->> 'slug', '')), '');
    IF v_slug IS NOT NULL AND v_slug <> v_article.slug THEN
      IF v_article.first_published_at IS NOT NULL THEN
        RAISE EXCEPTION 'SLUG_LOCKED' USING ERRCODE = 'raise_exception';
      END IF;
      IF (v_article.migrated AND NOT public.blog_slug_legacy_valid(v_slug))
         OR (NOT v_article.migrated AND NOT public.blog_slug_strict_valid(v_slug))
      THEN
        RAISE EXCEPTION 'INVALID_SLUG' USING ERRCODE = 'raise_exception';
      END IF;
      IF EXISTS (
        SELECT 1 FROM public.blog_articles a
        WHERE a.organization_id = v_org AND a.slug = v_slug AND a.id <> v_id
      ) THEN
        RAISE EXCEPTION 'SLUG_TAKEN' USING ERRCODE = 'raise_exception';
      END IF;
    ELSE
      v_slug := v_article.slug;
    END IF;

    UPDATE public.blog_articles
    SET slug = v_slug,
        revision = revision + 1,
        updated_by = v_user,
        updated_at = now()
    WHERE id = v_id
    RETURNING * INTO v_article;
  END IF;

  IF v_cover IS NOT NULL
     AND NOT public.blog_image_ref_valid(v_cover, v_org, v_id, v_article.migrated)
  THEN
    RAISE EXCEPTION 'INVALID_IMAGE_REF' USING ERRCODE = 'raise_exception';
  END IF;

  -- The payload carries the whole working content; it replaces the previous working row.
  -- Editing a published or retired article never touches the published row (FR-011).
  INSERT INTO public.blog_article_contents AS c (
    article_id, organization_id, kind, cover_ref,
    title_es, title_en, summary_es, summary_en, cover_alt_es, cover_alt_en,
    body_es, body_en, seo_title_es, seo_title_en, seo_description_es, seo_description_en,
    updated_by, updated_at
  )
  VALUES (
    v_id, v_org, 'working', v_cover,
    public.blog_payload_text(v_es, 'title', 120),
    public.blog_payload_text(v_en, 'title', 120),
    public.blog_payload_text(v_es, 'summary', 300),
    public.blog_payload_text(v_en, 'summary', 300),
    public.blog_payload_text(v_es, 'coverAlt', 250),
    public.blog_payload_text(v_en, 'coverAlt', 250),
    public.blog_normalize_body(v_es -> 'body', v_org, v_id, v_article.migrated),
    public.blog_normalize_body(v_en -> 'body', v_org, v_id, v_article.migrated),
    public.blog_payload_text(v_es, 'seoTitle', 70),
    public.blog_payload_text(v_en, 'seoTitle', 70),
    public.blog_payload_text(v_es, 'seoDescription', 160),
    public.blog_payload_text(v_en, 'seoDescription', 160),
    v_user, now()
  )
  ON CONFLICT (article_id, kind) DO UPDATE
  SET cover_ref = EXCLUDED.cover_ref,
      title_es = EXCLUDED.title_es,
      title_en = EXCLUDED.title_en,
      summary_es = EXCLUDED.summary_es,
      summary_en = EXCLUDED.summary_en,
      cover_alt_es = EXCLUDED.cover_alt_es,
      cover_alt_en = EXCLUDED.cover_alt_en,
      body_es = EXCLUDED.body_es,
      body_en = EXCLUDED.body_en,
      seo_title_es = EXCLUDED.seo_title_es,
      seo_title_en = EXCLUDED.seo_title_en,
      seo_description_es = EXCLUDED.seo_description_es,
      seo_description_en = EXCLUDED.seo_description_en,
      updated_by = EXCLUDED.updated_by,
      updated_at = EXCLUDED.updated_at;

  RETURN public.blog_article_state(v_id);
END;
$$;

COMMENT ON FUNCTION public.save_blog_article(jsonb) IS
  'Creates a draft or writes the working content of an article. Never changes the published version.';

-- ---------------------------------------------------------------------------
-- Reads for the panel
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.list_blog_articles(p_status text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_locales text[];
BEGIN
  IF p_status IS NOT NULL AND p_status NOT IN ('draft', 'published', 'retired') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_locales := public.blog_required_locales(v_org);

  RETURN coalesce((
    SELECT jsonb_agg(row_json ORDER BY sort_at DESC, slug)
    FROM (
      SELECT
        a.updated_at AS sort_at,
        a.slug,
        jsonb_build_object(
          'id', a.id,
          'slug', a.slug,
          'status', a.status,
          'hasPendingChanges', a.status <> 'draft' AND w.article_id IS NOT NULL,
          'completeLocales', to_jsonb(ARRAY(
            SELECT l FROM unnest(v_locales) AS l
            WHERE public.blog_locale_errors(coalesce(w, p), l) = '[]'::jsonb
          )),
          'title', coalesce(
            nullif(w.title_es, ''), nullif(p.title_es, ''),
            nullif(w.title_en, ''), nullif(p.title_en, '')
          ),
          'firstPublishedAt', a.first_published_at,
          'updatedAt', a.updated_at,
          'migrated', a.migrated,
          'revision', a.revision
        ) AS row_json
      FROM public.blog_articles a
      LEFT JOIN public.blog_article_contents w ON w.article_id = a.id AND w.kind = 'working'
      LEFT JOIN public.blog_article_contents p ON p.article_id = a.id AND p.kind = 'published'
      WHERE a.organization_id = v_org
        AND (p_status IS NULL OR a.status::text = p_status)
    ) rows
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_blog_article(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_article public.blog_articles;
  v_working public.blog_article_contents;
  v_published public.blog_article_contents;
BEGIN
  SELECT a.* INTO v_article
  FROM public.blog_articles a
  WHERE a.id = p_id AND a.organization_id = v_org;

  IF v_article.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT c.* INTO v_working
  FROM public.blog_article_contents c WHERE c.article_id = p_id AND c.kind = 'working';
  SELECT c.* INTO v_published
  FROM public.blog_article_contents c WHERE c.article_id = p_id AND c.kind = 'published';

  RETURN jsonb_build_object(
    'id', v_article.id,
    'slug', v_article.slug,
    'status', v_article.status,
    'migrated', v_article.migrated,
    'originalPublishedAt', v_article.original_published_at,
    'firstPublishedAt', v_article.first_published_at,
    'publicUpdatedAt', v_article.public_updated_at,
    'updatedAt', v_article.updated_at,
    'revision', v_article.revision,
    'requiredLocales', to_jsonb(public.blog_required_locales(v_org)),
    'migrationOpen', public.blog_migration_open(v_org),
    'working', public.blog_content_json(v_working),
    'published', public.blog_content_json(v_published),
    'publishErrors', CASE
      WHEN v_working.article_id IS NULL THEN '[]'::jsonb
      ELSE public.blog_publish_errors(p_id)
    END
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Transitions
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_raise_if_incomplete(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_errors jsonb := public.blog_publish_errors(p_id);
BEGIN
  IF jsonb_array_length(v_errors) > 0 THEN
    RAISE EXCEPTION 'PUBLISH_INCOMPLETE' USING ERRCODE = 'raise_exception', DETAIL = v_errors::text;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_blog_article(p_id uuid, p_expected_revision integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_article public.blog_articles;
BEGIN
  v_article := public.blog_lock_article(p_id, v_org, p_expected_revision);

  IF v_article.status <> 'draft' THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  PERFORM public.blog_raise_if_incomplete(p_id);

  DELETE FROM public.blog_article_contents WHERE article_id = p_id AND kind = 'published';
  UPDATE public.blog_article_contents SET kind = 'published' WHERE article_id = p_id AND kind = 'working';

  UPDATE public.blog_articles
  SET status = 'published',
      first_published_at = coalesce(first_published_at, original_published_at, now()),
      public_updated_at = now(),
      revision = revision + 1,
      updated_by = auth.uid(),
      updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_article;

  PERFORM public.blog_audit(v_org, 'blog_article_published', v_article);
  RETURN public.blog_article_state(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_blog_article_changes(p_id uuid, p_expected_revision integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_article public.blog_articles;
BEGIN
  v_article := public.blog_lock_article(p_id, v_org, p_expected_revision);

  IF v_article.status NOT IN ('published', 'retired') OR NOT EXISTS (
    SELECT 1 FROM public.blog_article_contents c WHERE c.article_id = p_id AND c.kind = 'working'
  ) THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  PERFORM public.blog_raise_if_incomplete(p_id);

  DELETE FROM public.blog_article_contents WHERE article_id = p_id AND kind = 'published';
  UPDATE public.blog_article_contents SET kind = 'published' WHERE article_id = p_id AND kind = 'working';

  UPDATE public.blog_articles
  SET public_updated_at = now(),
      revision = revision + 1,
      updated_by = auth.uid(),
      updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_article;

  PERFORM public.blog_audit(v_org, 'blog_article_changes_published', v_article);
  RETURN public.blog_article_state(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.discard_blog_article_changes(p_id uuid, p_expected_revision integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_article public.blog_articles;
BEGIN
  v_article := public.blog_lock_article(p_id, v_org, p_expected_revision);

  IF v_article.status NOT IN ('published', 'retired') OR NOT EXISTS (
    SELECT 1 FROM public.blog_article_contents c WHERE c.article_id = p_id AND c.kind = 'working'
  ) THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  DELETE FROM public.blog_article_contents WHERE article_id = p_id AND kind = 'working';

  UPDATE public.blog_articles
  SET revision = revision + 1, updated_by = auth.uid(), updated_at = now()
  WHERE id = p_id;

  RETURN public.blog_article_state(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.retire_blog_article(p_id uuid, p_expected_revision integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_article public.blog_articles;
BEGIN
  v_article := public.blog_lock_article(p_id, v_org, p_expected_revision);

  IF v_article.status <> 'published' THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.blog_articles
  SET status = 'retired', revision = revision + 1, updated_by = auth.uid(), updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_article;

  PERFORM public.blog_audit(v_org, 'blog_article_retired', v_article);
  RETURN public.blog_article_state(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.republish_blog_article(p_id uuid, p_expected_revision integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_article public.blog_articles;
BEGIN
  v_article := public.blog_lock_article(p_id, v_org, p_expected_revision);

  IF v_article.status <> 'retired' THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  -- The published version comes back as it was; a pending revision stays pending (US5).
  UPDATE public.blog_articles
  SET status = 'published', revision = revision + 1, updated_by = auth.uid(), updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_article;

  PERFORM public.blog_audit(v_org, 'blog_article_published', v_article, '{"republished": true}'::jsonb);
  RETURN public.blog_article_state(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_blog_article(p_id uuid, p_expected_revision integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_catalog_manager_or_forbidden();
  v_article public.blog_articles;
BEGIN
  v_article := public.blog_lock_article(p_id, v_org, p_expected_revision);

  -- FR-009: once published, an article keeps its slug and history; it can only be retired.
  IF v_article.status <> 'draft' OR v_article.first_published_at IS NOT NULL THEN
    RAISE EXCEPTION 'NOT_DELETABLE' USING ERRCODE = 'raise_exception';
  END IF;

  DELETE FROM public.blog_articles WHERE id = p_id;
  PERFORM public.blog_audit(v_org, 'blog_article_deleted', v_article);
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.blog_slugify(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_slug_strict_valid(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_slug_legacy_valid(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_migration_open(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_lock_article(uuid, uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_article_state(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_content_json(public.blog_article_contents) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_audit(uuid, audit.audit_event_type, public.blog_articles, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_payload_text(jsonb, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_raise_if_incomplete(uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.blog_slugify(text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_slug_strict_valid(text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_slug_legacy_valid(text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_migration_open(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_lock_article(uuid, uuid, integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_article_state(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_content_json(public.blog_article_contents) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_audit(uuid, audit.audit_event_type, public.blog_articles, jsonb) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_payload_text(jsonb, text, integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_raise_if_incomplete(uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.save_blog_article(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_blog_articles(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_blog_article(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.publish_blog_article(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.publish_blog_article_changes(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.discard_blog_article_changes(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.retire_blog_article(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.republish_blog_article(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_blog_article(uuid, integer) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.save_blog_article(jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_blog_articles(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_blog_article(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.publish_blog_article(uuid, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.publish_blog_article_changes(uuid, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.discard_blog_article_changes(uuid, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.retire_blog_article(uuid, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.republish_blog_article(uuid, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_blog_article(uuid, integer) FROM anon;

GRANT EXECUTE ON FUNCTION public.save_blog_article(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_blog_articles(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_blog_article(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_blog_article(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_blog_article_changes(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.discard_blog_article_changes(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.retire_blog_article(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.republish_blog_article(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_blog_article(uuid, integer) TO authenticated;
