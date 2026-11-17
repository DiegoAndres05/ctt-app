-- 067_blog_tables.sql
-- Tables, RLS and immutability triggers for the multi-agency blog (feature 013).
-- Source of truth: specs/013-editorial-content/data-model.md
--
-- Every write goes through the SECURITY DEFINER RPCs of 069 and 071. authenticated may only
-- read its own agency's rows, and only as operator or admin (Agent does not see the blog).

-- ---------------------------------------------------------------------------
-- blog_articles: identity, state and dates. One row per article.
-- ---------------------------------------------------------------------------

CREATE TABLE public.blog_articles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  slug text NOT NULL,
  status public.blog_article_status NOT NULL DEFAULT 'draft',
  migrated boolean NOT NULL DEFAULT false,
  original_published_at timestamptz,
  first_published_at timestamptz,
  public_updated_at timestamptz,
  revision integer NOT NULL DEFAULT 1,
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  updated_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT blog_articles_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT blog_articles_slug_key UNIQUE (organization_id, slug),
  -- New articles use the strict slug; a migrated article keeps its legacy slug (FR-015, FR-031).
  CONSTRAINT blog_articles_slug_format CHECK (
    (
      NOT migrated
      AND char_length(slug) BETWEEN 1 AND 120
      AND slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    )
    OR (
      migrated
      AND char_length(slug) BETWEEN 1 AND 200
      AND slug = btrim(slug)
      AND slug !~ '[[:space:]/?#]'
    )
  ),
  CONSTRAINT blog_articles_original_date_migrated CHECK (original_published_at IS NULL OR migrated),
  CONSTRAINT blog_articles_published_has_date CHECK (
    status = 'draft' OR first_published_at IS NOT NULL
  ),
  CONSTRAINT blog_articles_revision_positive CHECK (revision >= 1)
);

COMMENT ON TABLE public.blog_articles IS
  'Blog article identity per agency. Content lives in blog_article_contents (published / working).';
COMMENT ON COLUMN public.blog_articles.original_published_at IS
  'Migrated articles only: the publication date on the previous blog, used as first_published_at.';
COMMENT ON COLUMN public.blog_articles.revision IS
  'Optimistic concurrency counter. Every write RPC requires the current value (ARTICLE_CONFLICT).';

CREATE INDEX blog_articles_public_list_idx
  ON public.blog_articles (organization_id, status, first_published_at DESC);

-- ---------------------------------------------------------------------------
-- blog_article_contents: bilingual content, at most one published and one working row.
-- ---------------------------------------------------------------------------

CREATE TABLE public.blog_article_contents (
  article_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  kind public.blog_content_kind NOT NULL,
  cover_ref text,
  title_es text,
  title_en text,
  summary_es text,
  summary_en text,
  cover_alt_es text,
  cover_alt_en text,
  body_es jsonb NOT NULL DEFAULT '[]'::jsonb,
  body_en jsonb NOT NULL DEFAULT '[]'::jsonb,
  seo_title_es text,
  seo_title_en text,
  seo_description_es text,
  seo_description_en text,
  updated_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (article_id, kind),
  CONSTRAINT blog_article_contents_article_fkey
    FOREIGN KEY (article_id, organization_id)
    REFERENCES public.blog_articles (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT blog_article_contents_title_len CHECK (
    coalesce(char_length(title_es), 0) <= 120 AND coalesce(char_length(title_en), 0) <= 120
  ),
  CONSTRAINT blog_article_contents_summary_len CHECK (
    coalesce(char_length(summary_es), 0) <= 300 AND coalesce(char_length(summary_en), 0) <= 300
  ),
  CONSTRAINT blog_article_contents_cover_alt_len CHECK (
    coalesce(char_length(cover_alt_es), 0) <= 250 AND coalesce(char_length(cover_alt_en), 0) <= 250
  ),
  CONSTRAINT blog_article_contents_seo_title_len CHECK (
    coalesce(char_length(seo_title_es), 0) <= 70 AND coalesce(char_length(seo_title_en), 0) <= 70
  ),
  CONSTRAINT blog_article_contents_seo_description_len CHECK (
    coalesce(char_length(seo_description_es), 0) <= 160
    AND coalesce(char_length(seo_description_en), 0) <= 160
  ),
  CONSTRAINT blog_article_contents_body_shape CHECK (
    jsonb_typeof(body_es) = 'array' AND jsonb_typeof(body_en) = 'array'
    AND octet_length(body_es::text) <= 204800 AND octet_length(body_en::text) <= 204800
  ),
  CONSTRAINT blog_article_contents_cover_ref_len CHECK (
    cover_ref IS NULL OR char_length(cover_ref) <= 2000
  )
);

COMMENT ON TABLE public.blog_article_contents IS
  'Article content per language. kind published is what the site reads; kind working is the '
  'draft or pending revision and is never returned publicly (FR-013).';

-- ---------------------------------------------------------------------------
-- public_blog_source and public_blog_cutover_items: migration from a previous blog (US6).
-- ---------------------------------------------------------------------------

CREATE TABLE public.public_blog_source (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations (id) ON DELETE RESTRICT,
  migration_required boolean NOT NULL DEFAULT false,
  cutover_completed_at timestamptz,
  marked_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  marked_at timestamptz,
  completed_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT public_blog_source_cutover_requires_migration CHECK (
    cutover_completed_at IS NULL OR migration_required
  )
);

COMMENT ON TABLE public.public_blog_source IS
  'Blog source per agency. migration_required and no cutover: the public read answers legacy so '
  'the site keeps reading its previous blog. No row: the agency publishes directly.';

CREATE TABLE public.public_blog_cutover_items (
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  slug text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, slug),
  CONSTRAINT public_blog_cutover_items_slug CHECK (
    char_length(slug) BETWEEN 1 AND 200 AND slug = btrim(slug)
  )
);

COMMENT ON TABLE public.public_blog_cutover_items IS
  'Manifest of the slugs the previous blog shows. Every one needs a published article before cutover.';

-- ---------------------------------------------------------------------------
-- Immutability triggers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.blog_articles_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.migrated IS DISTINCT FROM OLD.migrated
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.slug IS DISTINCT FROM OLD.slug AND OLD.first_published_at IS NOT NULL THEN
    RAISE EXCEPTION 'SLUG_LOCKED' USING ERRCODE = 'raise_exception';
  END IF;

  IF OLD.first_published_at IS NOT NULL
     AND NEW.first_published_at IS DISTINCT FROM OLD.first_published_at
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.blog_articles_guard() FROM PUBLIC;

CREATE TRIGGER blog_articles_guard
  BEFORE UPDATE ON public.blog_articles
  FOR EACH ROW
  EXECUTE FUNCTION public.blog_articles_guard();

CREATE OR REPLACE FUNCTION public.public_blog_source_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF OLD.cutover_completed_at IS NOT NULL
     AND (
       NEW.cutover_completed_at IS DISTINCT FROM OLD.cutover_completed_at
       OR NEW.migration_required IS DISTINCT FROM OLD.migration_required
     )
  THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.public_blog_source_guard() FROM PUBLIC;

CREATE TRIGGER public_blog_source_guard
  BEFORE UPDATE ON public.public_blog_source
  FOR EACH ROW
  EXECUTE FUNCTION public.public_blog_source_guard();

-- ---------------------------------------------------------------------------
-- RLS: tenant-scoped reads for operator/admin; no direct writes for API roles.
-- ---------------------------------------------------------------------------

ALTER TABLE public.blog_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blog_article_contents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_blog_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_blog_cutover_items ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.blog_articles FROM anon;
REVOKE ALL ON public.blog_article_contents FROM anon;
REVOKE ALL ON public.public_blog_source FROM anon;
REVOKE ALL ON public.public_blog_cutover_items FROM anon;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.blog_articles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.blog_article_contents FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.public_blog_source FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.public_blog_cutover_items FROM authenticated;

GRANT SELECT ON public.blog_articles TO authenticated;
GRANT SELECT ON public.blog_article_contents TO authenticated;
GRANT SELECT ON public.public_blog_source TO authenticated;
GRANT SELECT ON public.public_blog_cutover_items TO authenticated;

CREATE POLICY blog_manager_select ON public.blog_articles
  FOR SELECT TO authenticated
  USING (
    organization_id = nullif(auth.jwt() ->> 'organization_id', '')::uuid
    AND (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
  );

CREATE POLICY blog_manager_select ON public.blog_article_contents
  FOR SELECT TO authenticated
  USING (
    organization_id = nullif(auth.jwt() ->> 'organization_id', '')::uuid
    AND (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
  );

CREATE POLICY blog_manager_select ON public.public_blog_source
  FOR SELECT TO authenticated
  USING (
    organization_id = nullif(auth.jwt() ->> 'organization_id', '')::uuid
    AND (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
  );

CREATE POLICY blog_manager_select ON public.public_blog_cutover_items
  FOR SELECT TO authenticated
  USING (
    organization_id = nullif(auth.jwt() ->> 'organization_id', '')::uuid
    AND (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
  );
