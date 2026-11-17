-- 068_blog_content_validation.sql
-- Block document normalization and publish validation for the blog (feature 013).
-- Source of truth: specs/013-editorial-content/data-model.md («Documento de bloques»,
-- «Validación de publicación») and research.md (Decisión 1).
--
-- The body is never HTML. Unknown block types and marks are dropped on save, so nothing
-- executable can reach a public site (FR-007). Every function here is internal.

-- ---------------------------------------------------------------------------
-- Inline runs: { text, bold?, italic?, href? }
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_href_allowed(p_href text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_href IS NOT NULL
    AND char_length(p_href) <= 2000
    AND p_href ~* '^(https?://[^[:space:]<>"]+|mailto:[^[:space:]<>"]+)$';
$$;

CREATE OR REPLACE FUNCTION public.blog_normalize_inline(p_runs jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_run jsonb;
  v_out jsonb := '[]'::jsonb;
  v_clean jsonb;
BEGIN
  IF p_runs IS NULL OR jsonb_typeof(p_runs) <> 'array' THEN
    RETURN '[]'::jsonb;
  END IF;

  FOR v_run IN SELECT value FROM jsonb_array_elements(p_runs)
  LOOP
    IF jsonb_typeof(v_run) <> 'object' OR jsonb_typeof(v_run -> 'text') IS DISTINCT FROM 'string' THEN
      CONTINUE;
    END IF;

    v_clean := jsonb_build_object('text', v_run ->> 'text');
    IF v_run -> 'bold' = 'true'::jsonb THEN
      v_clean := v_clean || jsonb_build_object('bold', true);
    END IF;
    IF v_run -> 'italic' = 'true'::jsonb THEN
      v_clean := v_clean || jsonb_build_object('italic', true);
    END IF;
    IF jsonb_typeof(v_run -> 'href') = 'string' AND public.blog_href_allowed(v_run ->> 'href') THEN
      v_clean := v_clean || jsonb_build_object('href', v_run ->> 'href');
    END IF;

    v_out := v_out || jsonb_build_array(v_clean);
  END LOOP;

  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.blog_inline_has_text(p_runs jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(p_runs) = 'array' THEN p_runs ELSE '[]'::jsonb END
    ) AS r(value)
    WHERE btrim(coalesce(r.value ->> 'text', '')) <> ''
  );
$$;

-- ---------------------------------------------------------------------------
-- Image references: storage path of this agency and article, or https for migrated articles.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_image_ref_valid(
  p_ref text,
  p_organization_id uuid,
  p_article_id uuid,
  p_allow_external boolean
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_ref IS NOT NULL
    AND char_length(p_ref) <= 2000
    AND (
      p_ref ~ (
        '^' || p_organization_id::text || '/blog/' || p_article_id::text
        || '/[A-Za-z0-9_-]{1,100}\.(jpg|jpeg|png|webp)$'
      )
      OR (coalesce(p_allow_external, false) AND p_ref ~* '^https://[^[:space:]<>"]+$')
    );
$$;

-- ---------------------------------------------------------------------------
-- blog_normalize_body: keeps only allowed blocks, cleans inline marks, checks image refs.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_normalize_body(
  p_body jsonb,
  p_organization_id uuid,
  p_article_id uuid,
  p_allow_external boolean
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_block jsonb;
  v_type text;
  v_out jsonb := '[]'::jsonb;
  v_items jsonb;
  v_item jsonb;
  v_clean_items jsonb;
  v_alt text;
BEGIN
  IF p_body IS NULL OR jsonb_typeof(p_body) = 'null' THEN
    RETURN '[]'::jsonb;
  END IF;

  IF jsonb_typeof(p_body) <> 'array' OR jsonb_array_length(p_body) > 500 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  FOR v_block IN SELECT value FROM jsonb_array_elements(p_body)
  LOOP
    IF jsonb_typeof(v_block) <> 'object' THEN
      CONTINUE;
    END IF;

    v_type := v_block ->> 'type';

    IF v_type IN ('paragraph', 'quote') THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'type', v_type,
        'text', public.blog_normalize_inline(v_block -> 'text')
      ));

    ELSIF v_type = 'heading' THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'type', 'heading',
        'level', CASE WHEN v_block ->> 'level' = '3' THEN 3 ELSE 2 END,
        'text', public.blog_normalize_inline(v_block -> 'text')
      ));

    ELSIF v_type = 'list' THEN
      v_items := v_block -> 'items';
      IF jsonb_typeof(v_items) IS DISTINCT FROM 'array' OR jsonb_array_length(v_items) = 0 THEN
        CONTINUE;
      END IF;
      IF jsonb_array_length(v_items) > 100 THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END IF;
      v_clean_items := '[]'::jsonb;
      FOR v_item IN SELECT value FROM jsonb_array_elements(v_items)
      LOOP
        v_clean_items := v_clean_items || jsonb_build_array(public.blog_normalize_inline(v_item));
      END LOOP;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'type', 'list',
        'ordered', v_block -> 'ordered' = 'true'::jsonb,
        'items', v_clean_items
      ));

    ELSIF v_type = 'image' THEN
      IF NOT public.blog_image_ref_valid(v_block ->> 'ref', p_organization_id, p_article_id, p_allow_external) THEN
        RAISE EXCEPTION 'INVALID_IMAGE_REF' USING ERRCODE = 'raise_exception';
      END IF;
      v_alt := nullif(btrim(coalesce(v_block ->> 'alt', '')), '');
      IF v_alt IS NOT NULL AND char_length(v_alt) > 250 THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END IF;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'type', 'image',
        'ref', v_block ->> 'ref',
        'alt', v_alt,
        'decorative', v_block -> 'decorative' = 'true'::jsonb
      ));
    END IF;
    -- Anything else (script, iframe, html, unknown) is dropped.
  END LOOP;

  IF octet_length(v_out::text) > 204800 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_out;
END;
$$;

COMMENT ON FUNCTION public.blog_normalize_body(jsonb, uuid, uuid, boolean) IS
  'Normalizes a block document: allowed block types only, clean inline marks, image refs inside '
  '{org}/blog/{article}/ (or https when external is allowed). Raises VALIDATION_ERROR / INVALID_IMAGE_REF.';

CREATE OR REPLACE FUNCTION public.blog_body_is_empty(p_body jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(p_body) = 'array' THEN p_body ELSE '[]'::jsonb END
    ) AS b(value)
    WHERE (
      b.value ->> 'type' IN ('paragraph', 'heading', 'quote')
      AND public.blog_inline_has_text(b.value -> 'text')
    )
    OR (
      b.value ->> 'type' = 'list'
      AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(b.value -> 'items') AS i(value)
        WHERE public.blog_inline_has_text(i.value)
      )
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Publish validation (FR-004)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_required_locales(p_organization_id uuid)
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT coalesce(
    (
      SELECT ARRAY(
        SELECT l FROM unnest(p.languages) AS l
        ORDER BY CASE l WHEN 'es' THEN 0 ELSE 1 END
      )
      FROM public.public_profiles p
      WHERE p.organization_id = p_organization_id
    ),
    ARRAY['es']
  );
$$;

COMMENT ON FUNCTION public.blog_required_locales(uuid) IS
  'Languages the agency offers in its public profile (016), es first; {es} without a profile.';

-- Errors of one locale of a content row: [{field, locale}].
CREATE OR REPLACE FUNCTION public.blog_locale_errors(
  p_content public.blog_article_contents,
  p_locale text
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_title text;
  v_summary text;
  v_cover_alt text;
  v_body jsonb;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  IF p_locale = 'en' THEN
    v_title := p_content.title_en;
    v_summary := p_content.summary_en;
    v_cover_alt := p_content.cover_alt_en;
    v_body := p_content.body_en;
  ELSE
    v_title := p_content.title_es;
    v_summary := p_content.summary_es;
    v_cover_alt := p_content.cover_alt_es;
    v_body := p_content.body_es;
  END IF;

  IF nullif(btrim(coalesce(v_title, '')), '') IS NULL THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('field', 'title', 'locale', p_locale));
  END IF;
  IF nullif(btrim(coalesce(v_summary, '')), '') IS NULL THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('field', 'summary', 'locale', p_locale));
  END IF;
  IF nullif(btrim(coalesce(v_cover_alt, '')), '') IS NULL THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('field', 'coverAlt', 'locale', p_locale));
  END IF;
  IF public.blog_body_is_empty(v_body) THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('field', 'body', 'locale', p_locale));
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(v_body, '[]'::jsonb)) AS b(value)
    WHERE b.value ->> 'type' = 'image'
      AND b.value -> 'decorative' IS DISTINCT FROM 'true'::jsonb
      AND nullif(btrim(coalesce(b.value ->> 'alt', '')), '') IS NULL
  ) THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('field', 'imageAlt', 'locale', p_locale));
  END IF;

  RETURN v_errors;
END;
$$;

-- Errors that block publishing the working content of an article. Empty array = publishable.
CREATE OR REPLACE FUNCTION public.blog_publish_errors(p_article_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_article public.blog_articles;
  v_content public.blog_article_contents;
  v_locale text;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  SELECT a.* INTO v_article FROM public.blog_articles a WHERE a.id = p_article_id;
  SELECT c.* INTO v_content
  FROM public.blog_article_contents c
  WHERE c.article_id = p_article_id AND c.kind = 'working';

  IF v_article.id IS NULL OR v_content.article_id IS NULL THEN
    RETURN jsonb_build_array(jsonb_build_object('field', 'content', 'locale', NULL));
  END IF;

  IF nullif(v_content.cover_ref, '') IS NULL THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('field', 'cover', 'locale', NULL));
  END IF;

  FOREACH v_locale IN ARRAY public.blog_required_locales(v_article.organization_id)
  LOOP
    v_errors := v_errors || public.blog_locale_errors(v_content, v_locale);
  END LOOP;

  RETURN v_errors;
END;
$$;

COMMENT ON FUNCTION public.blog_publish_errors(uuid) IS
  'FR-004: [{field, locale}] that block publishing the working content; [] when publishable.';

REVOKE ALL ON FUNCTION public.blog_href_allowed(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_normalize_inline(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_inline_has_text(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_image_ref_valid(text, uuid, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_normalize_body(jsonb, uuid, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_body_is_empty(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_required_locales(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_locale_errors(public.blog_article_contents, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.blog_publish_errors(uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.blog_href_allowed(text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_normalize_inline(jsonb) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_inline_has_text(jsonb) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_image_ref_valid(text, uuid, uuid, boolean) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_normalize_body(jsonb, uuid, uuid, boolean) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_body_is_empty(jsonb) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_required_locales(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_locale_errors(public.blog_article_contents, text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.blog_publish_errors(uuid) FROM anon, authenticated;
