-- 071_blog_source_cutover.sql
-- Blog migration from a previous blog with a source switch (feature 013, US6).
-- Source of truth: specs/013-editorial-content/contracts/management.md («Blog source»).
--
-- Administrator only. While migration is open (migration_required and no cutover), the public
-- read answers source "legacy" and no articles, so the site keeps reading its previous blog.
-- The migrated-article options of save_blog_article (legacy slug, original date, external
-- images) are implemented in 069 and gated by blog_migration_open().

CREATE OR REPLACE FUNCTION public.get_blog_source()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_tenant_admin_or_forbidden();
  v_source public.public_blog_source;
BEGIN
  SELECT s.* INTO v_source FROM public.public_blog_source s WHERE s.organization_id = v_org;

  RETURN jsonb_build_object(
    'migrationRequired', coalesce(v_source.migration_required, false),
    'cutoverCompletedAt', v_source.cutover_completed_at,
    'markedAt', v_source.marked_at,
    'manifest', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', i.slug,
        'articleId', a.id,
        'published', coalesce(a.status = 'published', false)
      ) ORDER BY i.slug)
      FROM public.public_blog_cutover_items i
      LEFT JOIN public.blog_articles a
        ON a.organization_id = i.organization_id AND a.slug = i.slug
      WHERE i.organization_id = v_org
    ), '[]'::jsonb),
    'missing', coalesce((
      SELECT jsonb_agg(i.slug ORDER BY i.slug)
      FROM public.public_blog_cutover_items i
      WHERE i.organization_id = v_org
        AND NOT EXISTS (
          SELECT 1 FROM public.blog_articles a
          WHERE a.organization_id = i.organization_id
            AND a.slug = i.slug
            AND a.status = 'published'
        )
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_blog_migration_required(p_required boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_tenant_admin_or_forbidden();
  v_source public.public_blog_source;
BEGIN
  IF p_required IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT s.* INTO v_source FROM public.public_blog_source s WHERE s.organization_id = v_org FOR UPDATE;

  IF v_source.cutover_completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.public_blog_source AS s (
    organization_id, migration_required, marked_by, marked_at
  )
  VALUES (
    v_org, p_required,
    CASE WHEN p_required THEN auth.uid() END,
    CASE WHEN p_required THEN now() END
  )
  ON CONFLICT (organization_id) DO UPDATE
  SET migration_required = EXCLUDED.migration_required,
      marked_by = coalesce(EXCLUDED.marked_by, s.marked_by),
      marked_at = coalesce(EXCLUDED.marked_at, s.marked_at),
      updated_at = now();

  PERFORM audit.log_event(
    v_org, 'blog_source_changed'::audit.audit_event_type, 'success'::audit.audit_result,
    auth.uid(), 'public_blog_source', NULL,
    jsonb_build_object('action', 'set_migration_required', 'migrationRequired', p_required)
  );

  RETURN public.get_blog_source();
END;
$$;

CREATE OR REPLACE FUNCTION public.replace_blog_cutover_manifest(p_slugs text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_tenant_admin_or_forbidden();
  v_count integer;
BEGIN
  IF NOT public.blog_migration_open(v_org) THEN
    RAISE EXCEPTION 'MIGRATION_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_slugs IS NULL OR cardinality(p_slugs) > 2000 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(p_slugs) AS s(slug)
    WHERE s.slug IS NULL
       OR btrim(s.slug) = ''
       OR char_length(btrim(s.slug)) > 200
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  DELETE FROM public.public_blog_cutover_items WHERE organization_id = v_org;

  INSERT INTO public.public_blog_cutover_items (organization_id, slug)
  SELECT DISTINCT v_org, btrim(s.slug) FROM unnest(p_slugs) AS s(slug);

  GET DIAGNOSTICS v_count = ROW_COUNT;

  PERFORM audit.log_event(
    v_org, 'blog_cutover_manifest_changed'::audit.audit_event_type, 'success'::audit.audit_result,
    auth.uid(), 'public_blog_source', NULL,
    jsonb_build_object('count', v_count)
  );

  RETURN public.get_blog_source();
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_blog_cutover()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.require_tenant_admin_or_forbidden();
  v_missing jsonb;
BEGIN
  PERFORM 1 FROM public.public_blog_source s WHERE s.organization_id = v_org FOR UPDATE;

  IF NOT public.blog_migration_open(v_org) THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT coalesce(jsonb_agg(i.slug ORDER BY i.slug), '[]'::jsonb)
  INTO v_missing
  FROM public.public_blog_cutover_items i
  WHERE i.organization_id = v_org
    AND NOT EXISTS (
      SELECT 1 FROM public.blog_articles a
      WHERE a.organization_id = i.organization_id
        AND a.slug = i.slug
        AND a.status = 'published'
    );

  -- FR-032: the switch never completes with content missing; the site keeps its old blog.
  IF jsonb_array_length(v_missing) > 0 THEN
    RAISE EXCEPTION 'BLOG_CUTOVER_INCOMPLETE' USING ERRCODE = 'raise_exception', DETAIL = v_missing::text;
  END IF;

  UPDATE public.public_blog_source
  SET cutover_completed_at = now(), completed_by = auth.uid(), updated_at = now()
  WHERE organization_id = v_org;

  PERFORM audit.log_event(
    v_org, 'blog_source_changed'::audit.audit_event_type, 'success'::audit.audit_result,
    auth.uid(), 'public_blog_source', NULL,
    jsonb_build_object('action', 'complete_cutover')
  );

  RETURN public.get_blog_source();
END;
$$;

REVOKE ALL ON FUNCTION public.get_blog_source() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_blog_migration_required(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.replace_blog_cutover_manifest(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_blog_cutover() FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.get_blog_source() FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_blog_migration_required(boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.replace_blog_cutover_manifest(text[]) FROM anon;
REVOKE EXECUTE ON FUNCTION public.complete_blog_cutover() FROM anon;

GRANT EXECUTE ON FUNCTION public.get_blog_source() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_blog_migration_required(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_blog_cutover_manifest(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_blog_cutover() TO authenticated;
