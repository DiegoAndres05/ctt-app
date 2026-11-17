-- 065_traveler_case_status.sql
-- Traveler case stage lookup (feature 015): a traveler with a SOL- reference and the email or
-- phone stored on that case sees the most advanced stage, the dates and the public offer name.
-- Source of truth: specs/015-traveler-case-status/tasks.md (Design baseline).
--
-- ERROR CONTRACT: the exception message is the API code.
--   RATE_LIMITED is the only case-related error. Unknown reference, foreign contact,
--   unparseable contact and anonymized customer all return the same {"found": false}.
--   PUBLIC_ACCESS_UNAVAILABLE comes from the agency resolution (feature 016), not the case.
--
-- The lookup never writes requests, pre-reservations, quotations, reservations or payments.
-- It only appends an attempt row (rate limit) and one audit event without contact data.

-- ---------------------------------------------------------------------------
-- Attempt counter. Stores a per-agency SHA-256 fingerprint of the normalized contact, never
-- the contact itself. Rows older than one day are pruned on each lookup of that agency.
-- ---------------------------------------------------------------------------

CREATE TABLE public.traveler_case_lookups (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  contact_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT traveler_case_lookups_fingerprint_format CHECK (contact_fingerprint ~ '^[0-9a-f]{64}$')
);

COMMENT ON TABLE public.traveler_case_lookups IS
  'Rate-limit ledger for get_traveler_case_status. Fingerprint only; no email, phone or reference.';

CREATE INDEX traveler_case_lookups_org_time_idx
  ON public.traveler_case_lookups (organization_id, created_at);

CREATE INDEX traveler_case_lookups_contact_time_idx
  ON public.traveler_case_lookups (organization_id, contact_fingerprint, created_at);

ALTER TABLE public.traveler_case_lookups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.traveler_case_lookups FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Internal implementation for one resolved agency.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.traveler_case_status_for_org(
  p_organization_id uuid,
  p_reference text,
  p_contact text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_not_found constant jsonb := jsonb_build_object('found', false);
  v_reference text := upper(btrim(coalesce(p_reference, '')));
  v_raw_contact text := left(btrim(coalesce(p_contact, '')), 254);
  v_email text;
  v_phone text;
  v_fingerprint text;
  v_contact_recent bigint;
  v_org_recent bigint;
  v_request public.customer_requests;
  v_reservation record;
  v_stage text;
  v_start date;
  v_end date;
  v_offer_name text;
BEGIN
  IF p_organization_id IS NULL THEN
    RETURN v_not_found;
  END IF;

  IF char_length(v_reference) > 32 THEN
    v_reference := '';
  END IF;

  -- Same normalization as intake (003). A contact that does not normalize is not an error:
  -- it simply cannot match, and the caller gets the neutral answer.
  IF position('@' IN v_raw_contact) > 0 THEN
    BEGIN
      v_email := public.normalize_email(v_raw_contact);
    EXCEPTION
      WHEN others THEN
        v_email := NULL;
    END;
  ELSIF v_raw_contact <> '' THEN
    BEGIN
      v_phone := public.normalize_phone_e164(
        v_raw_contact,
        public.organization_phone_country_code(p_organization_id)
      );
    EXCEPTION
      WHEN others THEN
        v_phone := NULL;
    END;
  END IF;

  v_fingerprint := encode(
    extensions.digest(
      p_organization_id::text || ':' || coalesce(v_email, v_phone, 'raw:' || lower(v_raw_contact)),
      'sha256'
    ),
    'hex'
  );

  -- Rate limit: every attempt counts, found or not (FR-006). RATE_LIMITED is deliberately the
  -- only distinguishable outcome, and it does not depend on whether the case exists.
  DELETE FROM public.traveler_case_lookups l
  WHERE l.organization_id = p_organization_id
    AND l.created_at < now() - interval '1 day';

  SELECT
    count(*) FILTER (WHERE l.contact_fingerprint = v_fingerprint),
    count(*)
  INTO v_contact_recent, v_org_recent
  FROM public.traveler_case_lookups l
  WHERE l.organization_id = p_organization_id
    AND l.created_at >= now() - interval '1 hour';

  IF v_contact_recent >= 8 OR v_org_recent >= 30 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.traveler_case_lookups (organization_id, contact_fingerprint)
  VALUES (p_organization_id, v_fingerprint);

  IF v_reference <> '' AND (v_email IS NOT NULL OR v_phone IS NOT NULL) THEN
    SELECT r.*
    INTO v_request
    FROM public.customer_requests r
    JOIN public.customers c
      ON c.id = r.customer_id
     AND c.organization_id = r.organization_id
    WHERE r.organization_id = p_organization_id
      AND r.reference = v_reference
      AND NOT c.is_anonymized
      AND (
        (v_email IS NOT NULL AND c.email = v_email)
        OR (v_phone IS NOT NULL AND c.phone_e164 = v_phone)
      );
  END IF;

  IF v_request.id IS NULL THEN
    PERFORM audit.log_event(
      p_organization_id,
      'traveler_case_lookup'::audit.audit_event_type,
      'failure'::audit.audit_result,
      NULL,
      'customer_request',
      NULL,
      jsonb_build_object(
        'reference', CASE WHEN v_reference ~ '^SOL-[0-9]{5,}$' THEN v_reference END,
        'found', false
      )
    );
    RETURN v_not_found;
  END IF;

  -- Most advanced stage: reservation > issued/accepted quotation > live pre-reservation >
  -- request. A superseded reservation version is history; the open version of the family wins.
  SELECT rv.status, rv.travel_start_date, rv.travel_end_date
  INTO v_reservation
  FROM public.pre_reservations pr
  JOIN public.reservation_families rf
    ON rf.pre_reservation_id = pr.id
   AND rf.organization_id = pr.organization_id
  JOIN public.reservation_versions rv
    ON rv.family_id = rf.id
   AND rv.organization_id = rf.organization_id
   AND rv.status <> 'superseded'::public.reservation_status
  WHERE pr.organization_id = p_organization_id
    AND pr.request_id = v_request.id
  ORDER BY
    CASE rv.status
      WHEN 'completed' THEN 4
      WHEN 'in_progress' THEN 3
      WHEN 'confirmed' THEN 2
      ELSE 1
    END DESC,
    rf.created_at DESC
  LIMIT 1;

  IF FOUND THEN
    v_stage := CASE v_reservation.status
      WHEN 'completed' THEN 'trip_completed'
      WHEN 'in_progress' THEN 'trip_in_progress'
      WHEN 'confirmed' THEN 'reservation_confirmed'
      ELSE 'reservation_cancelled'
    END;
    v_start := v_reservation.travel_start_date;
    v_end := v_reservation.travel_end_date;
  ELSIF EXISTS (
    SELECT 1
    FROM public.pre_reservations pr
    JOIN public.quotation_families qf
      ON qf.pre_reservation_id = pr.id
     AND qf.organization_id = pr.organization_id
    JOIN public.quotation_versions qv
      ON qv.family_id = qf.id
     AND qv.organization_id = qf.organization_id
    WHERE pr.organization_id = p_organization_id
      AND pr.request_id = v_request.id
      AND qv.status IN ('issued'::public.quotation_status, 'accepted'::public.quotation_status)
  ) THEN
    v_stage := 'proposal_ready';
  ELSIF EXISTS (
    SELECT 1
    FROM public.pre_reservations pr
    WHERE pr.organization_id = p_organization_id
      AND pr.request_id = v_request.id
      AND pr.status <> 'cancelled'::public.pre_reservation_status
  ) THEN
    v_stage := 'checking_availability';
  ELSE
    -- status pre_reservation with every pre-reservation cancelled: the case did not continue.
    v_stage := CASE v_request.status
      WHEN 'received' THEN 'request_received'
      WHEN 'in_review' THEN 'request_in_review'
      ELSE 'request_closed'
    END;
  END IF;

  IF v_start IS NULL THEN
    v_start := v_request.travel_start_date;
    v_end := v_request.travel_end_date;
  END IF;

  -- Public name only: the published listing of the first catalog item, in the request locale.
  SELECT CASE
           WHEN v_request.locale = 'en' THEN coalesce(pl.name_en, pl.name_es)
           ELSE coalesce(pl.name_es, pl.name_en)
         END
  INTO v_offer_name
  FROM public.customer_request_items i
  JOIN public.public_listings pl
    ON pl.product_id = i.product_id
   AND pl.organization_id = i.organization_id
   AND pl.status = 'published'
  WHERE i.request_id = v_request.id
    AND i.organization_id = p_organization_id
    AND i.product_id IS NOT NULL
  ORDER BY i.position
  LIMIT 1;

  PERFORM audit.log_event(
    p_organization_id,
    'traveler_case_lookup'::audit.audit_event_type,
    'success'::audit.audit_result,
    NULL,
    'customer_request',
    v_request.id,
    jsonb_build_object('reference', v_request.reference, 'found', true)
  );

  RETURN jsonb_build_object(
    'found', true,
    'stage', v_stage,
    'reference', v_request.reference,
    'travel_start', v_start,
    'travel_end', v_end,
    'offer_name', v_offer_name
  );
END;
$$;

COMMENT ON FUNCTION public.traveler_case_status_for_org(uuid, text, text) IS
  'Internal. Stage of one traveler case for a resolved agency. Not callable by API roles.';

REVOKE ALL ON FUNCTION public.traveler_case_status_for_org(uuid, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.traveler_case_status_for_org(uuid, text, text) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Public entry points (same agency resolution as get_public_site / submit_public_request).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_traveler_case_status(
  p_organization_id uuid,
  p_reference text,
  p_contact text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_jwt_org uuid;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    v_jwt_org := nullif(auth.jwt() ->> 'organization_id', '')::uuid;
    IF v_jwt_org IS NULL THEN
      RETURN jsonb_build_object('found', false);
    END IF;
    RETURN public.traveler_case_status_for_org(v_jwt_org, p_reference, p_contact);
  END IF;

  RETURN public.traveler_case_status_for_org(
    public.require_organization_identifier_access(p_organization_id),
    p_reference,
    p_contact
  );
END;
$$;

COMMENT ON FUNCTION public.get_traveler_case_status(uuid, text, text) IS
  'Traveler case stage. Authenticated: JWT agency, argument ignored. Anon: CTT transition only; '
  'after the transition use get_traveler_case_status_by_key. Read-only on the case.';

REVOKE ALL ON FUNCTION public.get_traveler_case_status(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_traveler_case_status(uuid, text, text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_traveler_case_status_by_key(
  p_key text,
  p_reference text,
  p_contact text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.traveler_case_status_for_org(
    public.resolve_public_access_key(p_key),
    p_reference,
    p_contact
  );
END;
$$;

COMMENT ON FUNCTION public.get_traveler_case_status_by_key(text, text, text) IS
  'Traveler case stage for the agency that owns the public key. Read-only on the case.';

REVOKE ALL ON FUNCTION public.get_traveler_case_status_by_key(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_traveler_case_status_by_key(text, text, text) TO anon, authenticated;
