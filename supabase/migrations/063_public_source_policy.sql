-- 063_public_source_policy.sql
-- Migration-required vs direct publication, and the CTT identifier transition (feature 016,
-- US4 and US5). Source of truth: specs/016-multiagency-public-cms/data-model.md
--
-- ERROR CONTRACT: FORBIDDEN, VALIDATION_ERROR, CUTOVER_ALREADY_COMPLETED, CUTOVER_INCOMPLETE

-- Administrator chooses whether the agency must copy an existing site before cutover.
-- Turning migration on never opens the organization-identifier path: that stays CTT-only.
CREATE OR REPLACE FUNCTION public.set_public_source_migration(p_migration_required boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_source public.public_source;
  v_row public.public_source_config;
BEGIN
  v_organization_id := public.require_tenant_admin_or_forbidden();

  IF p_migration_required IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT ps.source INTO v_source
  FROM public.public_sites ps
  WHERE ps.organization_id = v_organization_id;

  IF v_source = 'panel'::public.public_source THEN
    RAISE EXCEPTION 'CUTOVER_ALREADY_COMPLETED' USING ERRCODE = 'raise_exception';
  END IF;

  PERFORM public.ensure_public_agency_config(v_organization_id);

  UPDATE public.public_source_config
  SET migration_required = p_migration_required, updated_at = now()
  WHERE organization_id = v_organization_id
  RETURNING * INTO v_row;

  PERFORM audit.log_event(
    v_organization_id,
    'public_source_config_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_site',
    NULL,
    jsonb_build_object('action', 'migration_mode', 'migration_required', p_migration_required)
  );

  RETURN jsonb_build_object(
    'migration_required', v_row.migration_required,
    'organization_identifier_until', v_row.organization_identifier_until
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_public_source_migration(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_public_source_migration(boolean) TO authenticated;

-- Closes the organization-identifier access now (FR-017). One-way.
CREATE OR REPLACE FUNCTION public.end_organization_identifier_transition()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_row public.public_source_config;
BEGIN
  v_organization_id := public.require_tenant_admin_or_forbidden();

  UPDATE public.public_source_config
  SET organization_identifier_until = now(), updated_at = now()
  WHERE organization_id = v_organization_id
    AND organization_identifier_until > now()
  RETURNING * INTO v_row;

  IF v_row.organization_id IS NOT NULL THEN
    PERFORM audit.log_event(
      v_organization_id,
      'public_source_config_changed'::audit.audit_event_type,
      'success'::audit.audit_result,
      auth.uid(),
      'public_site',
      NULL,
      jsonb_build_object('action', 'organization_identifier_closed')
    );
  ELSE
    SELECT * INTO v_row
    FROM public.public_source_config sc
    WHERE sc.organization_id = v_organization_id;
  END IF;

  RETURN jsonb_build_object(
    'organization_identifier_until', v_row.organization_identifier_until,
    'identifier_access_open', coalesce(v_row.organization_identifier_until > now(), false)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.end_organization_identifier_transition() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_organization_identifier_transition() TO authenticated;

-- Cutover keeps the manifest gate for migrating agencies and skips it for the rest (FR-026..028).
CREATE OR REPLACE FUNCTION public.complete_public_cutover()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid;
  v_site public.public_sites;
  v_migration_required boolean;
  v_missing text[] := '{}'::text[];
  v_completed_at timestamptz;
BEGIN
  v_organization_id := public.require_tenant_admin_or_forbidden();

  SELECT * INTO v_site
  FROM public.public_sites ps
  WHERE ps.organization_id = v_organization_id
  FOR UPDATE;

  IF v_site.organization_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_site.source = 'panel'::public.public_source THEN
    RAISE EXCEPTION 'CUTOVER_ALREADY_COMPLETED' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT coalesce(sc.migration_required, false) INTO v_migration_required
  FROM public.public_source_config sc
  WHERE sc.organization_id = v_organization_id;

  IF coalesce(v_migration_required, false) THEN
    SELECT coalesce(array_agg(ci.public_slug ORDER BY ci.public_slug), '{}'::text[])
    INTO v_missing
    FROM public.public_cutover_items ci
    WHERE ci.organization_id = v_organization_id
      AND NOT EXISTS (
        SELECT 1
        FROM public.public_listings pl
        JOIN public.products p
          ON p.id = pl.product_id
         AND p.organization_id = pl.organization_id
        WHERE pl.organization_id = ci.organization_id
          AND pl.public_slug = ci.public_slug
          AND pl.status = 'published'::public.public_listing_status
          AND p.status = 'active'::public.product_status
      );

    IF cardinality(v_missing) > 0 THEN
      RAISE EXCEPTION 'CUTOVER_INCOMPLETE'
        USING ERRCODE = 'raise_exception',
              DETAIL = array_to_json(v_missing)::text;
    END IF;
  END IF;

  v_completed_at := now();

  UPDATE public.public_sites
  SET
    source = 'panel'::public.public_source,
    cutover_completed_at = v_completed_at,
    cutover_completed_by = auth.uid(),
    updated_at = now()
  WHERE organization_id = v_organization_id;

  PERFORM audit.log_event(
    v_organization_id,
    'public_cutover_completed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'public_site',
    NULL,
    jsonb_build_object('source', 'panel', 'migration_required', coalesce(v_migration_required, false))
  );

  RETURN jsonb_build_object(
    'source', 'panel',
    'cutover_completed_at', v_completed_at
  );
END;
$$;

COMMENT ON FUNCTION public.complete_public_cutover() IS
  'Admin: switch the public source to panel. Migrating agencies need every manifest item published.';

REVOKE EXECUTE ON FUNCTION public.complete_public_cutover() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_public_cutover() TO authenticated;
