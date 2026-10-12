-- 047_us3_quotation_delivery.sql
-- US3 public RPCs: read-only client link and the WhatsApp copy body.
-- Source of truth: specs/005-quotation-proposals/contracts/api-contracts.md (§4, §8),
-- specs/005-quotation-proposals/data-model.md (§Functions US3),
-- specs/005-quotation-proposals/research.md (R-006, R-008, R-009).
--
-- get_public_quotation is the only read path for the client: it looks the
-- family up by SHA-256 token hash and returns the frozen breakdown with
-- can_accept. It never exposes customer_id, email, phone, notes, the
-- pre-reservation or the token itself. quotation_whatsapp_text builds the copy
-- body without any URL: the clear token is not stored anywhere.

-- ---------------------------------------------------------------------------
-- quotation_family_id_by_token(p_token text) → uuid (internal)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_family_id_by_token(
  p_token text
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT f.id
  FROM public.quotation_families f
  WHERE nullif(btrim(coalesce(p_token, '')), '') IS NOT NULL
    AND f.public_token_hash = encode(
      extensions.digest(btrim(p_token), 'sha256'), 'hex'
    );
$$;

COMMENT ON FUNCTION public.quotation_family_id_by_token(text) IS
  'Resolves a family by the SHA-256 hash of the public token; NULL for an empty or unknown token. Internal.';

REVOKE ALL ON FUNCTION public.quotation_family_id_by_token(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quotation_family_id_by_token(text) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- quotation_current_version_id(p_family_id uuid) → uuid (internal)
-- The version the public link shows: the highest version_number that is neither
-- superseded nor draft (research R-008).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_current_version_id(
  p_family_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT v.id
  FROM public.quotation_versions v
  WHERE v.family_id = p_family_id
    AND v.status <> ALL (ARRAY['draft', 'superseded']::public.quotation_status[])
  ORDER BY v.version_number DESC
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.quotation_current_version_id(uuid) IS
  'The family version the public link shows: highest version_number outside draft/superseded. Internal.';

REVOKE ALL ON FUNCTION public.quotation_current_version_id(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quotation_current_version_id(uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- get_public_quotation(p_token text) → jsonb
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_public_quotation(
  p_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_family_id uuid;
  v_organization_id uuid;
  v_version public.quotation_versions%ROWTYPE;
  v_reference text;
BEGIN
  v_family_id := public.quotation_family_id_by_token(p_token);
  IF v_family_id IS NULL THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  SELECT f.organization_id, f.reference
  INTO v_organization_id, v_reference
  FROM public.quotation_families f
  WHERE f.id = v_family_id;

  -- Read-time sweep (R-006/R-004): an out-of-date or stale issued link shows
  -- as expired; this call commits, so the flip and its audit survive.
  PERFORM public.expire_due_quotations_core(v_organization_id, true);

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = public.quotation_current_version_id(v_family_id);

  -- Unknown current version (draft-only family) or a voided link: no data at all.
  IF NOT FOUND OR v_version.status = 'voided'::public.quotation_status THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  RETURN jsonb_build_object(
    'available', true,
    'status', v_version.status,
    'reference', v_reference,
    'version_number', v_version.version_number,
    'currency', v_version.currency::text,
    'valid_until', v_version.valid_until,
    'party_adults', v_version.party_adults,
    'party_children', v_version.party_children,
    'inclusions', v_version.inclusions,
    'exclusions', v_version.exclusions,
    'terms', v_version.terms,
    'subtotal', v_version.subtotal,
    'tax_total', v_version.tax_total,
    'adjustment_total', v_version.adjustment_total,
    'total', v_version.total,
    'lines', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'label', l.item_label,
        'kind', l.item_kind,
        'start_date', l.start_date,
        'end_date', l.end_date,
        'charge_basis', l.charge_basis,
        'unit_price', l.unit_price,
        'tax_rate', l.tax_rate,
        'line_total', l.line_total
      ) ORDER BY l.position, l.created_at, l.id), '[]'::jsonb)
      FROM public.quotation_lines l
      WHERE l.version_id = v_version.id
    ),
    'adjustments', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'label', a.label,
        'direction', a.direction,
        'kind', a.kind,
        'value', a.value
      ) ORDER BY a.created_at, a.id), '[]'::jsonb)
      FROM public.quotation_adjustments a
      WHERE a.version_id = v_version.id
    ),
    'can_accept', v_version.status = 'issued'::public.quotation_status
                  AND v_version.valid_until > now()
  );
END;
$$;

COMMENT ON FUNCTION public.get_public_quotation(text) IS
  'Public read-only proposal by token hash (R-008). Unknown/empty token, draft-only family or current version voided → { available: false } with no lines. Otherwise the frozen breakdown with can_accept = (issued and not past validity). Never returns customer_id, email, phone, notes, pre-reservation or the token.';

REVOKE ALL ON FUNCTION public.get_public_quotation(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_quotation(text) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- quotation_whatsapp_text(p_version_id uuid) → text
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_whatsapp_text(
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
  v_version public.quotation_versions%ROWTYPE;
  v_reference text;
  v_amount text;
  v_line_parts text[] := '{}';
  v_local timestamp;
  v_date text;
  v_months text[] := ARRAY[
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  r record;
BEGIN
  v_org := public.require_tenant_member();

  IF p_version_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Only a delivered proposal has a final body (data-model §US3).
  IF v_version.status <> ALL (ARRAY['issued', 'accepted', 'rejected', 'expired']::public.quotation_status[]) THEN
    RAISE EXCEPTION 'QUOTATION_NOT_OPEN' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT f.reference INTO v_reference
  FROM public.quotation_families f
  WHERE f.id = v_version.family_id;

  -- Colombian separators; whole amounts drop the cents (1.000, not 1.000.00).
  v_amount := to_char(v_version.total, 'FM999G999G999D00');
  IF v_version.total = trunc(v_version.total) THEN
    v_amount := split_part(v_amount, '.', 1);
  END IF;
  v_amount := replace(replace(replace(v_amount, '.', '@'), ',', '.'), '@', ',');

  FOR r IN
    SELECT l.item_label, l.start_date, (l.adults + l.children) AS pax
    FROM public.quotation_lines l
    WHERE l.version_id = p_version_id
    ORDER BY l.position, l.created_at, l.id
  LOOP
    v_line_parts := array_append(
      v_line_parts,
      r.item_label
        || ' · ' || (extract(day from r.start_date))::int::text || ' '
        || v_months[(extract(month from r.start_date))::int] || ' '
        || (extract(year from r.start_date))::int::text
        || ' · ' || r.pax::text
        || CASE WHEN r.pax = 1 THEN ' viajero' ELSE ' viajeros' END
    );
  END LOOP;

  v_local := coalesce(v_version.valid_until, v_version.created_at)
             AT TIME ZONE 'America/Bogota';
  v_date := (extract(day from v_local))::int::text || ' '
            || v_months[(extract(month from v_local))::int] || ' '
            || (extract(year from v_local))::int::text;

  -- No URL and no token here (R-009): the screen appends the link with the
  -- token it kept in memory when the quotation was issued.
  RETURN '✨ Propuesta ' || coalesce(v_reference, '')
    || E'\n' || coalesce(array_to_string(v_line_parts, E'\n'), '')
    || E'\n' || 'Total: ' || v_version.currency::text || ' ' || v_amount
    || E'\n' || 'Vigente hasta: ' || v_date
    || ', ' || lpad(((extract(hour from v_local))::int)::text, 2, '0')
    || ':' || lpad(((extract(minute from v_local))::int)::text, 2, '0');
END;
$$;

COMMENT ON FUNCTION public.quotation_whatsapp_text(uuid) IS
  'Server-built WhatsApp body for issued/accepted/rejected/expired versions: reference, line summaries, frozen total and validity in America/Bogota. Contains no URL and no token; the screen appends the link.';

REVOKE ALL ON FUNCTION public.quotation_whatsapp_text(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quotation_whatsapp_text(uuid) TO authenticated;
