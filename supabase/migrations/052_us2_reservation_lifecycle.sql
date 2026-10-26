-- 052_us2_reservation_lifecycle.sql

CREATE OR REPLACE FUNCTION public.require_reservation_operator()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_role text := auth.jwt() ->> 'app_role';
BEGIN
  v_org := public.require_tenant_member();
  IF v_role NOT IN ('operator', 'admin') THEN
    RAISE EXCEPTION 'INSUFFICIENT_PERMISSIONS' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_org;
END;
$$;

REVOKE ALL ON FUNCTION public.require_reservation_operator() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.require_reservation_operator() FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.transition_reservation_status(
  p_version_id uuid,
  p_to text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.reservation_versions%ROWTYPE;
  v_to public.reservation_status;
BEGIN
  v_org := public.require_reservation_operator();
  IF p_version_id IS NULL OR p_to IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.* INTO v_row
  FROM public.reservation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  BEGIN
    v_to := p_to::public.reservation_status;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END;

  IF NOT (
    (v_row.status = 'confirmed'::public.reservation_status
      AND v_to = 'in_progress'::public.reservation_status)
    OR (v_row.status = 'in_progress'::public.reservation_status
      AND v_to = 'completed'::public.reservation_status)
  ) THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.reservation_versions
  SET status = v_to,
      status_changed_at = now(),
      status_changed_by = auth.uid()
  WHERE id = p_version_id;

  PERFORM audit.log_event(
    v_org,
    'reservation_status_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'reservation_version',
    p_version_id,
    jsonb_build_object('from', v_row.status::text, 'to', v_to::text)
  );

  RETURN jsonb_build_object('version_id', p_version_id, 'status', v_to);
END;
$$;

REVOKE ALL ON FUNCTION public.transition_reservation_status(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_reservation_status(uuid, text) TO authenticated;
