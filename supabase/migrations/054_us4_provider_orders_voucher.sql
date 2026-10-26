-- 054_us4_provider_orders_voucher.sql

CREATE OR REPLACE FUNCTION public.mark_provider_order_sent(
  p_item_id uuid,
  p_channel text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
  v_org := public.require_reservation_operator();
  IF p_channel NOT IN ('whatsapp_copy', 'email_copy', 'print') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.reservation_items i
  SET ops_status = CASE
        WHEN i.ops_status IN (
          'pending_provider'::public.reservation_item_ops_status,
          'provider_failed'::public.reservation_item_ops_status
        ) THEN 'confirmed_with_provider'::public.reservation_item_ops_status
        ELSE i.ops_status
      END,
      provider_notified_at = now(),
      provider_notify_channel = p_channel::public.provider_notify_channel
  WHERE i.id = p_item_id AND i.organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  PERFORM audit.log_event(
    v_org,
    'reservation_provider_notified'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'reservation_item',
    p_item_id,
    jsonb_build_object('channel', p_channel)
  );

  RETURN jsonb_build_object('item_id', p_item_id);
END;
$$;

REVOKE ALL ON FUNCTION public.mark_provider_order_sent(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_provider_order_sent(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reassign_reservation_item_provider(
  p_item_id uuid,
  p_provider_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  v_org := public.require_reservation_operator();
  IF p_provider_id IS NULL OR char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.reservation_items
  SET provider_id = p_provider_id,
      ops_status = 'pending_provider'::public.reservation_item_ops_status,
      reassign_reason = v_reason,
      provider_notified_at = NULL,
      provider_notify_channel = NULL
  WHERE id = p_item_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  PERFORM audit.log_event(
    v_org,
    'reservation_item_reassigned'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'reservation_item',
    p_item_id,
    jsonb_build_object('provider_id', p_provider_id)
  );

  RETURN jsonb_build_object('item_id', p_item_id);
END;
$$;

REVOKE ALL ON FUNCTION public.reassign_reservation_item_provider(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reassign_reservation_item_provider(uuid, uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reservation_provider_order_text(
  p_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_item public.reservation_items%ROWTYPE;
  v_pax jsonb;
BEGIN
  v_org := public.require_reservation_operator();

  SELECT i.* INTO v_item
  FROM public.reservation_items i
  WHERE i.id = p_item_id AND i.organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'first_name', p.first_name,
    'last_name', p.last_name,
    'special_requirements', p.special_requirements
  ) ORDER BY p.position), '[]'::jsonb)
  INTO v_pax
  FROM public.reservation_passengers p
  WHERE p.version_id = v_item.version_id;

  RETURN jsonb_build_object(
    'item_id', v_item.id,
    'item_label', v_item.item_label,
    'start_date', v_item.start_date,
    'end_date', v_item.end_date,
    'quantity', v_item.quantity,
    'passengers', v_pax
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reservation_provider_order_text(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reservation_provider_order_text(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.reservation_whatsapp_text(
  p_version_id uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_ref text;
  v_total numeric;
  v_currency text;
  v_paid numeric;
  v_start date;
  v_end date;
BEGIN
  v_org := public.require_tenant_member();

  SELECT f.reference, v.total, v.currency, v.travel_start_date, v.travel_end_date
  INTO v_ref, v_total, v_currency, v_start, v_end
  FROM public.reservation_versions v
  JOIN public.reservation_families f ON f.id = v.family_id
  WHERE v.id = p_version_id AND v.organization_id = v_org;

  IF v_ref IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT coalesce(sum(p.amount), 0) INTO v_paid
  FROM public.reservation_payments p
  JOIN public.reservation_families f ON f.id = p.family_id
  JOIN public.reservation_versions v ON v.family_id = f.id
  WHERE v.id = p_version_id AND p.organization_id = v_org;

  RETURN format(
    'Reserva %s. Viaje %s – %s. Total %s %s. Saldo %s %s.',
    v_ref, v_start, coalesce(v_end::text, v_start::text),
    v_total, v_currency, (v_total - v_paid), v_currency
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reservation_whatsapp_text(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reservation_whatsapp_text(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_public_voucher(
  p_token text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hash text;
  v_family public.reservation_families%ROWTYPE;
  v_ver public.reservation_versions%ROWTYPE;
BEGIN
  IF p_token IS NULL OR btrim(p_token) = '' THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  v_hash := encode(extensions.digest(p_token, 'sha256'), 'hex');

  SELECT f.* INTO v_family
  FROM public.reservation_families f
  WHERE f.voucher_token_hash = v_hash;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  SELECT v.* INTO v_ver
  FROM public.reservation_versions v
  WHERE v.family_id = v_family.id
    AND v.status <> 'superseded'::public.reservation_status;

  RETURN jsonb_build_object(
    'available', true,
    'reference', v_family.reference,
    'status', v_ver.status,
    'travel_start_date', v_ver.travel_start_date,
    'travel_end_date', v_ver.travel_end_date,
    'terms', v_ver.terms,
    'assistance_phones', v_ver.assistance_phones,
    'passengers', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'first_name', p.first_name,
        'last_name', p.last_name
      ) ORDER BY p.position), '[]'::jsonb)
      FROM public.reservation_passengers p
      WHERE p.version_id = v_ver.id
    ),
    'items', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'title', i.item_label,
        'start_date', i.start_date,
        'end_date', i.end_date,
        'quantity', i.quantity
      ) ORDER BY i.position), '[]'::jsonb)
      FROM public.reservation_items i
      WHERE i.version_id = v_ver.id
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_voucher(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_voucher(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.void_reservation_voucher(
  p_family_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
  v_org := public.require_tenant_admin();

  UPDATE public.reservation_families
  SET voucher_token_hash = NULL
  WHERE id = p_family_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  PERFORM audit.log_event(
    v_org,
    'reservation_voucher_voided'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'reservation_family',
    p_family_id,
    '{}'::jsonb
  );

  RETURN jsonb_build_object('family_id', p_family_id, 'available', false);
END;
$$;

REVOKE ALL ON FUNCTION public.void_reservation_voucher(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.void_reservation_voucher(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rotate_reservation_voucher(
  p_family_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_token text;
BEGIN
  v_org := public.require_tenant_admin();
  v_token := replace(encode(extensions.gen_random_bytes(32), 'base64'), E'\n', '');

  UPDATE public.reservation_families
  SET voucher_token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex')
  WHERE id = p_family_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN jsonb_build_object('family_id', p_family_id, 'voucher_token', v_token);
END;
$$;

REVOKE ALL ON FUNCTION public.rotate_reservation_voucher(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rotate_reservation_voucher(uuid) TO authenticated;

DO $$
BEGIN
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION
  WHEN others THEN
    NULL;
END;
$$;

DROP POLICY IF EXISTS reservation_receipts_select ON storage.objects;
DROP POLICY IF EXISTS reservation_receipts_insert ON storage.objects;

CREATE POLICY reservation_receipts_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'reservation-receipts'
    AND split_part(name, '/', 1) = (auth.jwt() ->> 'organization_id')
  );

CREATE POLICY reservation_receipts_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'reservation-receipts'
    AND split_part(name, '/', 1) = (auth.jwt() ->> 'organization_id')
  );
