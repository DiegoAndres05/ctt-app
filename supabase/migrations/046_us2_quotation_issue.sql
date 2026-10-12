-- 046_us2_quotation_issue.sql
-- US2 public RPCs: terms and validity, issuing, expiry sweep and org defaults.
-- Source of truth: specs/005-quotation-proposals/contracts/api-contracts.md (§3, §8),
-- specs/005-quotation-proposals/data-model.md (§Functions US2),
-- specs/005-quotation-proposals/research.md (R-006, R-008, R-011).
--
-- Every RPC is SECURITY DEFINER with SET search_path = '', authorizes with
-- require_tenant_member() (require_tenant_admin() for the template) and is
-- GRANT EXECUTE only to authenticated. The public token is 32 random bytes in
-- base64url; only its SHA-256 hex is stored, and the clear token travels once in
-- the issue_quotation response. Audit metadata carries ids, version numbers,
-- currency and reason codes only: never terms, notes or the token.

-- ---------------------------------------------------------------------------
-- assert_quotation_validity(p_org, p_pre_reservation_id, p_requested) → timestamptz (internal)
-- R-006: between now + 1 hour and now + 30 days, never past the pre-reservation
-- hold (pre_reservations.expires_at). NULL p_requested restores the default
-- least(now + 48 hours, cap). 30-day cap is checked before the hold so a request
-- beyond both reports the general cap.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assert_quotation_validity(
  p_org uuid,
  p_pre_reservation_id uuid,
  p_requested timestamptz
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now timestamptz := now();
  v_min timestamptz;
  v_max timestamptz;
  v_hold timestamptz;
  v_target timestamptz;
BEGIN
  IF p_org IS NULL OR p_pre_reservation_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT pr.expires_at INTO v_hold
  FROM public.pre_reservations pr
  WHERE pr.id = p_pre_reservation_id AND pr.organization_id = p_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  v_min := v_now + interval '1 hour';
  v_max := v_now + interval '30 days';

  -- A hold ending before the minimum window leaves no validity to honour.
  IF v_hold IS NOT NULL AND v_hold < v_min THEN
    RAISE EXCEPTION 'VALIDITY_EXCEEDS_HOLD' USING ERRCODE = 'raise_exception';
  END IF;

  v_target := coalesce(
    p_requested,
    least(v_now + interval '48 hours', coalesce(v_hold, v_max))
  );

  IF v_target < v_min THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_target > v_max THEN
    RAISE EXCEPTION 'VALIDITY_EXCEEDS_30_DAYS' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_hold IS NOT NULL AND v_target > v_hold THEN
    RAISE EXCEPTION 'VALIDITY_EXCEEDS_HOLD' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN v_target;
END;
$$;

COMMENT ON FUNCTION public.assert_quotation_validity(uuid, uuid, timestamptz) IS
  'R-006 validity gate: returns the requested instant (or the least(now+48h, cap) default) within [now+1h, min(now+30d, pre-reservation hold)]; raises VALIDITY_EXCEEDS_30_DAYS / VALIDITY_EXCEEDS_HOLD. Internal.';

REVOKE ALL ON FUNCTION public.assert_quotation_validity(uuid, uuid, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_quotation_validity(uuid, uuid, timestamptz) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- expire_due_quotations_core(p_org uuid, p_check_fingerprint boolean) → integer (internal)
-- Tenant sweep without an auth guard so the public read and the acceptance
-- paths can run it for anon callers too (research R-006: no pg_cron).
-- Expires issued versions past their validity (reason_code due). With
-- p_check_fingerprint it also expires issued versions whose frozen fingerprint
-- no longer describes the pre-reservation's main lines (reason_code stale,
-- research R-004); the panel list and the public read run that variant so the
-- flip is committed by a statement that does not raise.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.expire_due_quotations_core(
  p_org uuid,
  p_check_fingerprint boolean DEFAULT false
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count integer := 0;
  r record;
BEGIN
  IF p_org IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  FOR r IN
    SELECT v.id, v.family_id, v.version_number
    FROM public.quotation_versions v
    WHERE v.organization_id = p_org
      AND v.status = 'issued'::public.quotation_status
      AND v.valid_until IS NOT NULL
      AND v.valid_until <= now()
    ORDER BY v.id
    FOR UPDATE
  LOOP
    UPDATE public.quotation_versions v
    SET status = 'expired'::public.quotation_status,
        expired_at = now()
    WHERE v.id = r.id;

    PERFORM audit.log_event(
      p_org,
      'quotation_expired'::audit.audit_event_type,
      'success'::audit.audit_result,
      auth.uid(),
      'quotation_version',
      r.id,
      jsonb_build_object(
        'family_id', r.family_id,
        'version_number', r.version_number,
        'reason_code', 'due'
      )
    );

    v_count := v_count + 1;
  END LOOP;

  IF coalesce(p_check_fingerprint, false) THEN
    FOR r IN
      SELECT v.id, v.family_id, v.version_number, f.pre_reservation_id,
             v.pre_reservation_fingerprint
      FROM public.quotation_versions v
      JOIN public.quotation_families f
        ON f.id = v.family_id AND f.organization_id = v.organization_id
      WHERE v.organization_id = p_org
        AND v.status = 'issued'::public.quotation_status
      ORDER BY v.id
      FOR UPDATE OF v
    LOOP
      IF public.capture_pre_reservation_fingerprint(p_org, r.pre_reservation_id)
         IS DISTINCT FROM r.pre_reservation_fingerprint
      THEN
        UPDATE public.quotation_versions v
        SET status = 'expired'::public.quotation_status,
            expired_at = now()
        WHERE v.id = r.id;

        PERFORM audit.log_event(
          p_org,
          'quotation_expired'::audit.audit_event_type,
          'success'::audit.audit_result,
          auth.uid(),
          'quotation_version',
          r.id,
          jsonb_build_object(
            'family_id', r.family_id,
            'version_number', r.version_number,
            'reason_code', 'stale'
          )
        );

        v_count := v_count + 1;
      END IF;
    END LOOP;
  END IF;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.expire_due_quotations_core(uuid, boolean) IS
  'Moves the tenant''s issued versions with valid_until <= now() to expired (reason_code due) and, when p_check_fingerprint, also those whose pre-reservation fingerprint changed (reason_code stale). Audits quotation_expired. Returns the count. Internal.';

REVOKE ALL ON FUNCTION public.expire_due_quotations_core(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_due_quotations_core(uuid, boolean) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- set_quotation_terms(p_version_id uuid, p_terms text, p_valid_until timestamptz) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_quotation_terms(
  p_version_id uuid,
  p_terms text,
  p_valid_until timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_version public.quotation_versions%ROWTYPE;
  v_pre_reservation_id uuid;
  v_terms text;
  v_effective timestamptz;
BEGIN
  v_org := public.require_tenant_member();

  IF p_version_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT f.pre_reservation_id INTO v_pre_reservation_id
  FROM public.quotation_families f
  WHERE f.id = v_version.family_id AND f.organization_id = v_org;

  v_terms := nullif(btrim(coalesce(p_terms, '')), '');
  IF v_terms IS NULL THEN
    RAISE EXCEPTION 'TERMS_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;
  IF char_length(v_terms) > 8000 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- p_valid_until NULL restores the default: least(now + 48 hours, cap) (R-006).
  v_effective := public.assert_quotation_validity(v_org, v_pre_reservation_id, p_valid_until);

  UPDATE public.quotation_versions v
  SET terms = v_terms,
      valid_until = v_effective
  WHERE v.id = p_version_id;

  RETURN jsonb_build_object(
    'version_id', p_version_id,
    'valid_until', v_effective,
    'terms', v_terms
  );
END;
$$;

COMMENT ON FUNCTION public.set_quotation_terms(uuid, text, timestamptz) IS
  'Draft-only terms (1-8000, mandatory) and validity within R-006 bounds. NULL valid_until restores the default least(now + 48h, cap).';

REVOKE ALL ON FUNCTION public.set_quotation_terms(uuid, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_quotation_terms(uuid, text, timestamptz) TO authenticated;

-- ---------------------------------------------------------------------------
-- issue_quotation(p_version_id uuid) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.issue_quotation(
  p_version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_version public.quotation_versions%ROWTYPE;
  v_family public.quotation_families%ROWTYPE;
  v_pre_reservation_id uuid;
  v_valid_until timestamptz;
  v_reference text;
  v_token text;
  v_breakdown jsonb;
BEGIN
  v_org := public.require_tenant_member();

  IF p_version_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Only a draft can be issued; anything else is frozen (FR-008/FR-011).
  IF v_version.status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  IF btrim(v_version.terms) = '' THEN
    RAISE EXCEPTION 'TERMS_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT f.* INTO v_family
  FROM public.quotation_families f
  WHERE f.id = v_version.family_id AND f.organization_id = v_org
  FOR UPDATE;

  v_pre_reservation_id := v_family.pre_reservation_id;

  -- Feature 004 eligibility gate (research R-004): raises PRE_RESERVATION_*.
  PERFORM public.assert_pre_reservation_quotable(v_org, v_pre_reservation_id);

  -- Validity within R-006 bounds; default least(now + 48h, cap).
  v_valid_until := public.assert_quotation_validity(
    v_org, v_pre_reservation_id, v_version.valid_until
  );

  -- Reprice before freezing: TARIFF_NOT_FOUND / AMBIGUOUS_TARIFF surface here
  -- and a still-missing exchange rate blocks issuing (contracts §2/§3).
  v_breakdown := public.recalculate_quotation_core(v_org, p_version_id);

  IF jsonb_array_length(v_breakdown -> 'pending_currencies') > 0 THEN
    RAISE EXCEPTION 'EXCHANGE_RATE_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  -- COT-##### reference on the family's first issue (R-007); later versions reuse it.
  IF v_family.reference IS NULL THEN
    v_reference := 'COT-' || lpad(
      public.next_organization_sequence(v_org, 'quotation')::text, 5, '0'
    );
    UPDATE public.quotation_families f
    SET reference = v_reference
    WHERE f.id = v_family.id;
  ELSE
    v_reference := v_family.reference;
  END IF;

  -- Public token (R-008): 32 random bytes in base64url; only the SHA-256 hex is
  -- stored. The clear token travels once in this response and is never persisted.
  IF v_family.public_token_hash IS NULL THEN
    v_token := rtrim(
      translate(
        replace(encode(extensions.gen_random_bytes(32), 'base64'), E'\n', ''),
        '+/', '-_'
      ),
      '='
    );
    UPDATE public.quotation_families f
    SET public_token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex')
    WHERE f.id = v_family.id;
  ELSE
    -- A later version reuses the family token; the clear token is not stored.
    v_token := NULL;
  END IF;

  UPDATE public.quotation_versions v
  SET status = 'issued'::public.quotation_status,
      issued_at = now(),
      issued_by = auth.uid(),
      valid_until = v_valid_until,
      pre_reservation_fingerprint = public.capture_pre_reservation_fingerprint(
        v_org, v_pre_reservation_id
      )
  WHERE v.id = p_version_id;

  PERFORM audit.log_event(
    v_org,
    'quotation_issued'::audit.audit_event_type,
    'success'::audit.audit_result,
    auth.uid(),
    'quotation_version',
    p_version_id,
    jsonb_build_object(
      'family_id', v_version.family_id,
      'version_number', v_version.version_number,
      'currency', v_version.currency::text
    )
  );

  RETURN jsonb_build_object(
    'version_id', p_version_id,
    'reference', v_reference,
    'version_number', v_version.version_number,
    'status', 'issued',
    'valid_until', v_valid_until,
    'public_token', v_token,
    'total', v_breakdown -> 'total',
    'currency', v_version.currency::text
  );
END;
$$;

COMMENT ON FUNCTION public.issue_quotation(uuid) IS
  'Freezes a draft: reprices, assigns COT-##### on the first issue, stores the pre-reservation fingerprint, sets the R-006 validity and generates the public token (only its SHA-256 hex is stored). The clear token returns once. Audit quotation_issued carries version_number/currency, never the token.';

REVOKE ALL ON FUNCTION public.issue_quotation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.issue_quotation(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- expire_due_quotations() → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.expire_due_quotations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_count integer;
BEGIN
  v_org := public.require_tenant_member();
  v_count := public.expire_due_quotations_core(v_org, true);
  RETURN jsonb_build_object('expired_count', v_count);
END;
$$;

COMMENT ON FUNCTION public.expire_due_quotations() IS
  'Tenant sweep that expires issued versions past their validity or with a changed pre-reservation fingerprint and returns { expired_count }. Invoked before list/detail reads and by the public paths.';

REVOKE ALL ON FUNCTION public.expire_due_quotations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.expire_due_quotations() TO authenticated;

-- ---------------------------------------------------------------------------
-- upsert_quotation_defaults(p_terms text) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.upsert_quotation_defaults(
  p_terms text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_terms text;
BEGIN
  v_org := public.require_tenant_admin();

  v_terms := nullif(btrim(coalesce(p_terms, '')), '');
  IF v_terms IS NULL THEN
    RAISE EXCEPTION 'TERMS_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;
  IF char_length(v_terms) > 8000 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.quotation_defaults (organization_id, terms_template, created_by)
  VALUES (v_org, v_terms, auth.uid())
  ON CONFLICT (organization_id)
  DO UPDATE SET terms_template = EXCLUDED.terms_template,
                created_by = EXCLUDED.created_by;

  RETURN jsonb_build_object('organization_id', v_org);
END;
$$;

COMMENT ON FUNCTION public.upsert_quotation_defaults(text) IS
  'Admin-only upsert of the organization terms template (1-8000). Drafts without a row use the fixed R-009 text.';

REVOKE ALL ON FUNCTION public.upsert_quotation_defaults(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_quotation_defaults(text) TO authenticated;
