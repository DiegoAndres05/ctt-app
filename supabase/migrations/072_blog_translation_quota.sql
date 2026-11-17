-- 072_blog_translation_quota.sql
-- Feature 017 (blog translation): hourly per-agency character quota for translate-blog.
--
-- The panel sends an article in parts; the Edge Function calls
-- consume_blog_translation_quota(characters) with the user's session before each part goes to
-- the self-hosted translator (ADR-0005). The RPC is also the role check (FR-001): Operator and
-- Administrator only. No article text is stored here (FR-014).

CREATE TABLE public.blog_translation_usage (
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  window_start timestamptz NOT NULL,
  characters integer NOT NULL DEFAULT 0 CHECK (characters >= 0),
  PRIMARY KEY (organization_id, window_start)
);

COMMENT ON TABLE public.blog_translation_usage IS
  'Characters sent to the blog translator per agency and hour (spec 017 FR-012). Written only by consume_blog_translation_quota.';

ALTER TABLE public.blog_translation_usage ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.blog_translation_usage FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.consume_blog_translation_quota(p_characters integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_limit CONSTANT integer := 150000;      -- about fifteen long articles per hour
  c_max_request CONSTANT integer := 5000;  -- one part, as capped by the Edge Function
  v_organization_id uuid;
  v_window timestamptz := date_trunc('hour', now());
  v_used integer;
BEGIN
  v_organization_id := public.require_catalog_manager_or_forbidden();

  IF p_characters IS NULL OR p_characters < 1 OR p_characters > c_max_request THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  DELETE FROM public.blog_translation_usage
  WHERE organization_id = v_organization_id
    AND window_start < now() - interval '1 day';

  -- Atomic under concurrency: the row lock of ON CONFLICT serializes requests of one agency.
  INSERT INTO public.blog_translation_usage AS u (organization_id, window_start, characters)
  VALUES (v_organization_id, v_window, p_characters)
  ON CONFLICT (organization_id, window_start)
  DO UPDATE SET characters = u.characters + p_characters
  WHERE u.characters + p_characters <= c_limit
  RETURNING u.characters INTO v_used;

  IF v_used IS NULL THEN
    RAISE EXCEPTION 'TRANSLATION_RATE_LIMITED' USING
      ERRCODE = 'raise_exception',
      DETAIL = jsonb_build_object(
        'retry_at', to_char((v_window + interval '1 hour') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
      )::text;
  END IF;

  RETURN jsonb_build_object(
    'remaining', c_limit - v_used,
    'reset_at', to_char((v_window + interval '1 hour') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.consume_blog_translation_quota(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_blog_translation_quota(integer) TO authenticated;
