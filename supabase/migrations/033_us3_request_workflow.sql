-- 033_us3_request_workflow.sql
-- Assignment, status transitions, customer edits, and append-only notes.
-- Source of truth: specs/003-customer-requests-channels/data-model.md (§7, state transitions),
-- specs/003-customer-requests-channels/contracts/api-contracts.md (§3.3–§3.6),
-- specs/003-customer-requests-channels/research.md (R-010).
--
-- pre_reservation is not a manual transition. Feature 004 performs it in the same
-- transaction that creates the pre-reservation.

CREATE TABLE public.request_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  request_id uuid,
  customer_id uuid,
  author_id uuid NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT request_notes_request_fkey
    FOREIGN KEY (request_id, organization_id)
    REFERENCES public.customer_requests (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT request_notes_customer_fkey
    FOREIGN KEY (customer_id, organization_id)
    REFERENCES public.customers (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT request_notes_author_fkey
    FOREIGN KEY (author_id, organization_id)
    REFERENCES public.user_profiles (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT request_notes_one_target CHECK (num_nonnulls(request_id, customer_id) = 1),
  CONSTRAINT request_notes_content_bounds CHECK (
    content = btrim(content) AND char_length(content) BETWEEN 1 AND 4000
  )
);

COMMENT ON TABLE public.request_notes IS
  'Append-only internal notes. They are not scrubbed by anonymize_customer.';

CREATE INDEX request_notes_request_created_idx
  ON public.request_notes (request_id, created_at);

CREATE INDEX request_notes_customer_created_idx
  ON public.request_notes (customer_id, created_at);

CREATE OR REPLACE FUNCTION public.reject_request_note_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Request notes are append-only and cannot be modified or deleted.'
    USING ERRCODE = 'insufficient_privilege';
END;
$$;

COMMENT ON FUNCTION public.reject_request_note_mutation() IS
  'Rejects UPDATE, DELETE, and TRUNCATE on request_notes for every role, including the owner.';

REVOKE ALL ON FUNCTION public.reject_request_note_mutation() FROM PUBLIC;

CREATE TRIGGER request_notes_reject_mutation
  BEFORE UPDATE OR DELETE ON public.request_notes
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_request_note_mutation();

CREATE TRIGGER request_notes_reject_truncate
  BEFORE TRUNCATE ON public.request_notes
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.reject_request_note_mutation();

ALTER TABLE public.request_notes ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.request_notes FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.request_notes FROM authenticated;

CREATE POLICY tenant_isolation_select ON public.request_notes
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- ---------------------------------------------------------------------------
-- update_customer
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_customer(p_customer_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.customers%ROWTYPE;
  v_first text;
  v_last text;
  v_email text;
  v_phone text;
  v_country text;
  v_doc_type public.document_type;
  v_doc_number text;
  v_fields jsonb := '[]'::jsonb;
BEGIN
  v_org := public.require_tenant_member();

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
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

  v_first := btrim(coalesce(p_payload ->> 'first_name', ''));
  v_last := nullif(btrim(coalesce(p_payload ->> 'last_name', '')), '');
  v_country := nullif(upper(btrim(coalesce(p_payload ->> 'country_code', ''))), '');
  v_doc_number := nullif(btrim(coalesce(p_payload ->> 'document_number', '')), '');

  IF v_first = '' OR char_length(v_first) > 120
     OR (v_last IS NOT NULL AND char_length(v_last) > 120)
  THEN
    IF v_first = '' THEN
      RAISE EXCEPTION 'CONTACT_REQUIRED' USING ERRCODE = 'raise_exception';
    END IF;
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_country IS NOT NULL AND v_country !~ '^[A-Z]{2}$' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_doc_number IS NOT NULL AND char_length(v_doc_number) > 40 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  BEGIN
    IF nullif(btrim(coalesce(p_payload ->> 'document_type', '')), '') IS NOT NULL THEN
      v_doc_type := (p_payload ->> 'document_type')::public.document_type;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  IF v_doc_number IS NOT NULL AND v_doc_type IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_email := public.normalize_email(p_payload ->> 'email');
  v_phone := public.normalize_phone_e164(
    coalesce(nullif(btrim(coalesce(p_payload ->> 'phone', '')), ''), p_payload ->> 'phone_e164'),
    public.organization_phone_country_code(v_org)
  );

  IF v_email IS NULL AND v_phone IS NULL THEN
    RAISE EXCEPTION 'CONTACT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_email IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.organization_id = v_org
      AND c.email = v_email
      AND c.id <> p_customer_id
      AND c.is_anonymized = false
  ) THEN
    RAISE EXCEPTION 'CUSTOMER_CONTACT_TAKEN' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_phone IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.organization_id = v_org
      AND c.phone_e164 = v_phone
      AND c.id <> p_customer_id
      AND c.is_anonymized = false
  ) THEN
    RAISE EXCEPTION 'CUSTOMER_CONTACT_TAKEN' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_row.first_name IS DISTINCT FROM v_first THEN
    v_fields := v_fields || jsonb_build_array('first_name');
  END IF;
  IF v_row.last_name IS DISTINCT FROM v_last THEN
    v_fields := v_fields || jsonb_build_array('last_name');
  END IF;
  IF v_row.email IS DISTINCT FROM v_email THEN
    v_fields := v_fields || jsonb_build_array('email');
  END IF;
  IF v_row.phone_e164 IS DISTINCT FROM v_phone THEN
    v_fields := v_fields || jsonb_build_array('phone_e164');
  END IF;
  IF v_row.country_code IS DISTINCT FROM v_country THEN
    v_fields := v_fields || jsonb_build_array('country_code');
  END IF;
  IF v_row.document_type IS DISTINCT FROM v_doc_type THEN
    v_fields := v_fields || jsonb_build_array('document_type');
  END IF;
  IF v_row.document_number IS DISTINCT FROM v_doc_number THEN
    v_fields := v_fields || jsonb_build_array('document_number');
  END IF;

  UPDATE public.customers
  SET first_name = v_first,
      last_name = v_last,
      email = v_email,
      phone_e164 = v_phone,
      country_code = v_country,
      document_type = v_doc_type,
      document_number = v_doc_number
  WHERE id = p_customer_id;

  PERFORM audit.log_event(
    v_org,
    'customer_updated'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'customer',
    p_customer_id,
    jsonb_build_object('fields', v_fields)
  );

  SELECT *
  INTO v_row
  FROM public.customers
  WHERE id = p_customer_id;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'organization_id', v_row.organization_id,
    'first_name', v_row.first_name,
    'last_name', v_row.last_name,
    'email', v_row.email,
    'phone_e164', v_row.phone_e164,
    'document_type', v_row.document_type,
    'document_number', v_row.document_number,
    'country_code', v_row.country_code,
    'is_anonymized', v_row.is_anonymized,
    'anonymized_at', v_row.anonymized_at,
    'created_by', v_row.created_by,
    'created_at', v_row.created_at,
    'updated_at', v_row.updated_at
  );
END;
$$;

COMMENT ON FUNCTION public.update_customer(uuid, jsonb) IS
  'Replaces editable customer fields. Audit metadata lists field names only.';

REVOKE ALL ON FUNCTION public.update_customer(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_customer(uuid, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- assign_request
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assign_request(p_request_id uuid, p_assignee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.customer_requests%ROWTYPE;
  v_assigned_at timestamptz;
BEGIN
  v_org := public.require_tenant_member();

  SELECT *
  INTO v_row
  FROM public.customer_requests r
  WHERE r.id = p_request_id
    AND r.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_row.status IN ('discarded', 'pre_reservation') THEN
    RAISE EXCEPTION 'REQUEST_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_assignee_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_profiles p
    WHERE p.id = p_assignee_id
      AND p.organization_id = v_org
      AND p.status = 'active'
  ) THEN
    RAISE EXCEPTION 'ASSIGNEE_NOT_IN_ORGANIZATION' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_assignee_id IS NULL THEN
    v_assigned_at := NULL;
  ELSE
    v_assigned_at := now();
  END IF;

  UPDATE public.customer_requests
  SET assigned_to = p_assignee_id,
      assigned_at = v_assigned_at
  WHERE id = p_request_id;

  PERFORM audit.log_event(
    v_org,
    'request_assigned'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'customer_request',
    p_request_id,
    jsonb_build_object('from', v_row.assigned_to, 'to', p_assignee_id)
  );

  RETURN jsonb_build_object(
    'request_id', p_request_id,
    'assigned_to', p_assignee_id,
    'assigned_at', v_assigned_at
  );
END;
$$;

COMMENT ON FUNCTION public.assign_request(uuid, uuid) IS
  'Assigns or clears the collaborator on an open request. Audit stores ids only.';

REVOKE ALL ON FUNCTION public.assign_request(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_request(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_request_status
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_request_status(
  p_request_id uuid,
  p_status public.request_status,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_row public.customer_requests%ROWTYPE;
  v_reason text;
  v_first timestamptz;
  v_closed timestamptz;
BEGIN
  v_org := public.require_tenant_member();

  SELECT *
  INTO v_row
  FROM public.customer_requests r
  WHERE r.id = p_request_id
    AND r.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_status = 'pre_reservation' THEN
    RAISE EXCEPTION 'PRE_RESERVATION_REQUIRES_CONVERSION' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_row.status IN ('discarded', 'pre_reservation') THEN
    RAISE EXCEPTION 'REQUEST_CLOSED' USING ERRCODE = 'raise_exception';
  END IF;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  v_first := v_row.first_handled_at;
  v_closed := NULL;

  IF v_row.status = 'received' AND p_status = 'in_review' THEN
    v_first := coalesce(v_first, now());
  ELSIF v_row.status IN ('received', 'in_review') AND p_status = 'discarded' THEN
    IF v_reason IS NULL THEN
      RAISE EXCEPTION 'DISCARD_REASON_REQUIRED' USING ERRCODE = 'raise_exception';
    END IF;
    IF char_length(v_reason) > 500 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    v_first := coalesce(v_first, now());
    v_closed := now();
  ELSE
    RAISE EXCEPTION 'INVALID_STATUS_TRANSITION' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.customer_requests
  SET status = p_status,
      discard_reason = CASE WHEN p_status = 'discarded' THEN v_reason ELSE NULL END,
      first_handled_at = v_first,
      closed_at = v_closed
  WHERE id = p_request_id;

  PERFORM audit.log_event(
    v_org,
    'request_status_changed'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'customer_request',
    p_request_id,
    jsonb_build_object('from', v_row.status, 'to', p_status)
  );

  RETURN jsonb_build_object(
    'request_id', p_request_id,
    'status', p_status,
    'first_handled_at', v_first,
    'closed_at', v_closed
  );
END;
$$;

COMMENT ON FUNCTION public.set_request_status(uuid, public.request_status, text) IS
  'Manual transitions: received to in_review or discarded, and in_review to discarded.';

REVOKE ALL ON FUNCTION public.set_request_status(uuid, public.request_status, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_request_status(uuid, public.request_status, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- add_request_note
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.add_request_note(
  p_request_id uuid,
  p_customer_id uuid,
  p_content text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_author uuid := auth.uid();
  v_content text;
  v_note_id uuid;
  v_created timestamptz;
BEGIN
  v_org := public.require_tenant_member();
  v_content := btrim(coalesce(p_content, ''));

  IF num_nonnulls(p_request_id, p_customer_id) <> 1
     OR v_content = ''
     OR char_length(v_content) > 4000
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_request_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.customer_requests r
    WHERE r.id = p_request_id
      AND r.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_customer_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = p_customer_id
      AND c.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.request_notes (organization_id, request_id, customer_id, author_id, content)
  VALUES (v_org, p_request_id, p_customer_id, v_author, v_content)
  RETURNING id, created_at INTO v_note_id, v_created;

  RETURN jsonb_build_object('note_id', v_note_id, 'created_at', v_created);
END;
$$;

COMMENT ON FUNCTION public.add_request_note(uuid, uuid, text) IS
  'Appends one internal note to either a request or a customer. The author is auth.uid().';

REVOKE ALL ON FUNCTION public.add_request_note(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_request_note(uuid, uuid, text) TO authenticated;
