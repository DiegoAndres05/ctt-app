-- 034_us4_customer_privacy.sql
-- Irreversible anonymization of a customer and the free text they submitted.
-- Source of truth: specs/003-customer-requests-channels/research.md (R-012),
-- specs/003-customer-requests-channels/contracts/api-contracts.md (§3.7).
--
-- Internal notes are kept. The audit event records that a reason was provided,
-- never the reason text or any contact value.

CREATE OR REPLACE FUNCTION public.anonymize_customer(p_customer_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.customers%ROWTYPE;
  v_reason text;
  v_requests integer;
  v_messages integer;
BEGIN
  v_org := public.require_tenant_admin();
  v_reason := btrim(coalesce(p_reason, ''));

  IF v_reason = '' OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT *
  INTO v_row
  FROM public.customers c
  WHERE c.id = p_customer_id
    AND c.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_row.is_anonymized THEN
    RAISE EXCEPTION 'CUSTOMER_ANONYMIZED' USING ERRCODE = 'raise_exception';
  END IF;

  -- 006: rechazar aquí clientes con reservas vigentes cuando exista esa feature.

  UPDATE public.customers
  SET first_name = 'Cliente anonimizado',
      last_name = NULL,
      email = NULL,
      phone_e164 = NULL,
      document_type = NULL,
      document_number = NULL,
      country_code = NULL,
      is_anonymized = true,
      anonymized_at = now()
  WHERE id = p_customer_id;

  UPDATE public.customer_requests
  SET submitted_contact = NULL,
      special_requirements = CASE
        WHEN special_requirements IS NULL THEN NULL
        ELSE '[anonimizado]'
      END
  WHERE customer_id = p_customer_id
    AND organization_id = v_org;
  GET DIAGNOSTICS v_requests = ROW_COUNT;

  UPDATE public.customer_request_items
  SET free_text = '[anonimizado]'
  WHERE organization_id = v_org
    AND free_text IS NOT NULL
    AND request_id IN (
      SELECT r.id
      FROM public.customer_requests r
      WHERE r.customer_id = p_customer_id
        AND r.organization_id = v_org
    );

  UPDATE public.inbound_messages
  SET body = '[anonimizado]',
      from_phone_e164 = NULL,
      profile_name = NULL
  WHERE customer_id = p_customer_id
    AND organization_id = v_org;
  GET DIAGNOSTICS v_messages = ROW_COUNT;

  PERFORM audit.log_event(
    v_org,
    'customer_anonymized'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'customer',
    p_customer_id,
    jsonb_build_object(
      'reason_provided', true,
      'requests_scrubbed', v_requests,
      'messages_scrubbed', v_messages
    )
  );

  RETURN jsonb_build_object(
    'customer_id', p_customer_id,
    'requests_scrubbed', v_requests,
    'messages_scrubbed', v_messages
  );
END;
$$;

COMMENT ON FUNCTION public.anonymize_customer(uuid, text) IS
  'Admin-only. Clears traveler PII and customer-authored free text. Keeps commercial history and internal notes.';

REVOKE ALL ON FUNCTION public.anonymize_customer(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.anonymize_customer(uuid, text) TO authenticated;
