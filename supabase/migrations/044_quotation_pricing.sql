-- 044_quotation_pricing.sql
-- Internal pricing core for quotations: tariff resolution, recalculation,
-- adjustment impact and pre-reservation fingerprint.
-- Source of truth: specs/005-quotation-proposals/data-model.md (§Functions Núcleo, §6),
-- specs/005-quotation-proposals/research.md (R-001..R-005, R-009).
--
-- Every function is SECURITY DEFINER with SET search_path = '' and
-- REVOKE ALL FROM PUBLIC, anon and authenticated. Only RPCs in 045-048 call them.
-- Ordering per line (R-003): line_base, signed adjustments, line_net, line_tax,
-- line_total, then the global adjustment over sum(line_total). Every amount is
-- round(numeric, 2) per line before summing; the header is the sum of rounded lines.

-- ---------------------------------------------------------------------------
-- quotation_default_terms() → text (internal, fixed text of research R-009)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_default_terms()
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT 'Esta propuesta es válida hasta la fecha y hora indicadas y queda sujeta a disponibilidad de servicios y tarifas. Esta cotización no es una reserva ni una factura.'::text;
$$;

COMMENT ON FUNCTION public.quotation_default_terms() IS
  'Fixed conditions text a draft uses when the organization has no quotation_defaults row (research R-009).';

REVOKE ALL ON FUNCTION public.quotation_default_terms() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quotation_default_terms() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- resolve_quotation_tariff(p_org, p_product_id, p_addon_id, p_on_date) → jsonb
-- R-002: current tariff with resolve_price precedence (season covering the date,
-- otherwise base; latest valid_from). Preferred charge type by line kind; fallback
-- to the single current type, else TARIFF_NOT_FOUND / AMBIGUOUS_TARIFF.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resolve_quotation_tariff(
  p_org uuid,
  p_product_id uuid,
  p_addon_id uuid,
  p_on_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_preferred public.charge_type;
  v_types public.charge_type[];
  v_chosen public.charge_type;
  v_unit public.addon_unit;
  v_row record;
BEGIN
  IF p_org IS NULL
     OR p_on_date IS NULL
     OR num_nonnulls(p_product_id, p_addon_id) <> 1
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- Preferred charge type per R-002.
  IF p_product_id IS NOT NULL THEN
    SELECT CASE p.type
             WHEN 'experience'::public.product_type THEN 'per_person'::public.charge_type
             WHEN 'accommodation'::public.product_type THEN 'per_night'::public.charge_type
             ELSE 'per_group'::public.charge_type
           END
    INTO v_preferred
    FROM public.products p
    WHERE p.id = p_product_id AND p.organization_id = p_org;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    -- products.type: experience | accommodation | package
    -- maps 1:1 onto per_person | per_night | per_group.
  ELSE
    SELECT a.unit INTO v_unit
    FROM public.add_ons a
    WHERE a.id = p_addon_id AND a.organization_id = p_org;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
    IF v_unit = 'per_person'::public.addon_unit THEN
      v_preferred := 'per_person'::public.charge_type;
    ELSE
      -- per_unit and per_service add-ons are priced per_group (R-002).
      v_preferred := 'per_group'::public.charge_type;
    END IF;
  END IF;

  -- Charge types with a scheme current on the tariff date.
  SELECT array_agg(DISTINCT ps.charge_type) INTO v_types
  FROM public.pricing_schemes ps
  WHERE ps.organization_id = p_org
    AND (
      (p_product_id IS NOT NULL AND ps.product_id = p_product_id)
      OR (p_addon_id IS NOT NULL AND ps.addon_id = p_addon_id)
    )
    AND ps.valid_from <= p_on_date::timestamptz
    AND (ps.valid_to IS NULL OR ps.valid_to > p_on_date::timestamptz)
    AND (
      (ps.season_start IS NULL AND ps.season_end IS NULL)
      OR (p_on_date BETWEEN ps.season_start AND ps.season_end)
    );

  IF v_types IS NULL OR coalesce(array_length(v_types, 1), 0) = 0 THEN
    RAISE EXCEPTION 'TARIFF_NOT_FOUND' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_preferred = ANY (v_types) THEN
    v_chosen := v_preferred;
  ELSIF array_length(v_types, 1) = 1 THEN
    v_chosen := v_types[1];
  ELSE
    RAISE EXCEPTION 'AMBIGUOUS_TARIFF' USING ERRCODE = 'raise_exception';
  END IF;

  -- Same precedence as public.resolve_price within the chosen charge type.
  SELECT
    ps.currency,
    ps.base_amount,
    CASE WHEN ps.season_start IS NOT NULL THEN 'season' ELSE 'base' END AS source
  INTO v_row
  FROM public.pricing_schemes ps
  WHERE ps.organization_id = p_org
    AND (
      (p_product_id IS NOT NULL AND ps.product_id = p_product_id)
      OR (p_addon_id IS NOT NULL AND ps.addon_id = p_addon_id)
    )
    AND ps.charge_type = v_chosen
    AND ps.valid_from <= p_on_date::timestamptz
    AND (ps.valid_to IS NULL OR ps.valid_to > p_on_date::timestamptz)
    AND (
      (ps.season_start IS NULL AND ps.season_end IS NULL)
      OR (p_on_date BETWEEN ps.season_start AND ps.season_end)
    )
  ORDER BY (ps.season_start IS NOT NULL) DESC, ps.valid_from DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TARIFF_NOT_FOUND' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN jsonb_build_object(
    'currency', v_row.currency::text,
    'amount', v_row.base_amount,
    'charge_type', v_chosen::text,
    'source', v_row.source
  );
END;
$$;

COMMENT ON FUNCTION public.resolve_quotation_tariff(uuid, uuid, uuid, date) IS
  'Resolves the current tariff for a product or add-on on a date. Returns {currency, amount, charge_type, source: season|base} or raises VALIDATION_ERROR / TARIFF_NOT_FOUND / AMBIGUOUS_TARIFF.';

REVOKE ALL ON FUNCTION public.resolve_quotation_tariff(uuid, uuid, uuid, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_quotation_tariff(uuid, uuid, uuid, date) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- capture_pre_reservation_fingerprint(p_org, p_pre_reservation_id) → jsonb
-- R-004: ordered array of the main active lines with the fields that must not
-- change between issuing and accepting.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.capture_pre_reservation_fingerprint(
  p_org uuid,
  p_pre_reservation_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'product_id', i.product_id,
        'addon_id', i.addon_id,
        'start_date', i.start_date,
        'end_date', i.end_date,
        'adults', i.adults,
        'children', i.children,
        'quantity', i.quantity
      )
      ORDER BY i.id
    ),
    '[]'::jsonb
  )
  FROM public.pre_reservation_items i
  WHERE i.organization_id = p_org
    AND i.pre_reservation_id = p_pre_reservation_id
    AND i.alternative_of_item_id IS NULL
    AND i.withdrawn_at IS NULL;
$$;

COMMENT ON FUNCTION public.capture_pre_reservation_fingerprint(uuid, uuid) IS
  'JSON array ordered by line id with product/addon, dates and passengers of the main active lines. Stored at issue, recomputed at acceptance.';

REVOKE ALL ON FUNCTION public.capture_pre_reservation_fingerprint(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.capture_pre_reservation_fingerprint(uuid, uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- quotation_adjustment_impact(p_org, p_version_id) → jsonb
-- R-005: absolute money of every adjustment vs round(sum(line_base) * 0.15, 2).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_adjustment_impact(
  p_org uuid,
  p_version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_version public.quotation_versions%ROWTYPE;
  v_line_base_sum numeric(14, 2);
  v_sum_line_total numeric(14, 2);
  v_adj record;
  v_base numeric(14, 2);
  v_money numeric(14, 2);
  v_impact numeric(14, 2) := 0;
  v_total numeric(14, 2) := 0;
  v_cap numeric(14, 2);
BEGIN
  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = p_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT
    coalesce(sum(l.line_base), 0),
    coalesce(sum(l.line_total), 0)
  INTO v_line_base_sum, v_sum_line_total
  FROM public.quotation_lines l
  WHERE l.version_id = p_version_id;

  FOR v_adj IN
    SELECT
      a.*,
      coalesce(l.line_base, 0) AS line_base
    FROM public.quotation_adjustments a
    LEFT JOIN public.quotation_lines l
      ON l.version_id = a.version_id
     AND l.pre_reservation_item_id = a.pre_reservation_item_id
    WHERE a.version_id = p_version_id
  LOOP
    IF v_adj.pre_reservation_item_id IS NULL THEN
      -- Global adjustment applies over sum(line_total) (R-003 step 6).
      v_base := v_sum_line_total;
    ELSE
      v_base := v_adj.line_base;
    END IF;

    IF v_adj.kind = 'percent'::public.quotation_adjustment_kind THEN
      v_money := round(v_base * v_adj.value / 100, 2);
    ELSE
      v_money := v_adj.value;
    END IF;

    IF v_adj.direction = 'discount'::public.quotation_adjustment_direction THEN
      v_money := -v_money;
    END IF;

    v_impact := v_impact + abs(v_money);
    v_total := v_total + v_money;
  END LOOP;

  v_cap := round(v_line_base_sum * 0.15, 2);

  RETURN jsonb_build_object(
    'line_base_sum', v_line_base_sum,
    'cap', v_cap,
    'impact', v_impact,
    'adjustment_total', v_total,
    'requires_admin', v_impact > v_cap
  );
END;
$$;

COMMENT ON FUNCTION public.quotation_adjustment_impact(uuid, uuid) IS
  'Computes {line_base_sum, cap, impact, adjustment_total, requires_admin} for a version. Cap is round(sum(line_base) * 0.15, 2); with a zero base any impact requires an admin.';

REVOKE ALL ON FUNCTION public.quotation_adjustment_impact(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quotation_adjustment_impact(uuid, uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- recalculate_quotation_core(p_org, p_version_id) → jsonb
-- R-001..R-005: the single pricing authority. Draft only; re-reads active main
-- lines of the source pre-reservation, re-resolves tariffs, applies the stored
-- rates, line adjustments, per-line tax and the global adjustment, persists the
-- header and returns the breakdown. Missing rates leave the line at 0 and report
-- the currency in pending_currencies instead of inventing a conversion.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.recalculate_quotation_core(
  p_org uuid,
  p_version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_version public.quotation_versions%ROWTYPE;
  v_pre_reservation_id uuid;
  v_rates jsonb;
  v_rate numeric(14, 6);
  v_tariff jsonb;
  v_charge_type public.charge_type;
  v_unit public.addon_unit;
  v_is_pending boolean;
  v_pending text[] := '{}';
  v_unit_price numeric(14, 2);
  v_basis numeric(12, 2);
  v_line_base numeric(14, 2);
  v_line_adjustment numeric(14, 2);
  v_line_net numeric(14, 2);
  v_line_tax numeric(14, 2);
  v_line_total numeric(14, 2);
  v_money numeric(14, 2);
  v_old_tax numeric(5, 2);
  v_adj public.quotation_adjustments%ROWTYPE;
  v_sum_line_base numeric(14, 2) := 0;
  v_sum_line_adjustment numeric(14, 2) := 0;
  v_sum_line_tax numeric(14, 2) := 0;
  v_sum_line_total numeric(14, 2) := 0;
  v_global numeric(14, 2) := 0;
  v_adjustment_total numeric(14, 2);
  v_total numeric(14, 2);
  v_adults smallint;
  v_children smallint;
  r record;
BEGIN
  SELECT v.* INTO v_version
  FROM public.quotation_versions v
  WHERE v.id = p_version_id AND v.organization_id = p_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_version.status <> 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT f.pre_reservation_id INTO v_pre_reservation_id
  FROM public.quotation_families f
  WHERE f.id = v_version.family_id AND f.organization_id = p_org;

  IF v_pre_reservation_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- R-004: recalculation revalidates the source pre-reservation (feature 004).
  PERFORM public.assert_pre_reservation_quotable(p_org, v_pre_reservation_id);

  v_rates := coalesce(v_version.exchange_rates, '{}'::jsonb);

  -- Drop lines whose item is no longer a main active line.
  DELETE FROM public.quotation_lines l
  WHERE l.version_id = p_version_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.pre_reservation_items i
      WHERE i.id = l.pre_reservation_item_id
        AND i.organization_id = p_org
        AND i.pre_reservation_id = v_pre_reservation_id
        AND i.alternative_of_item_id IS NULL
        AND i.withdrawn_at IS NULL
    );

  -- Rebuild the money for every active main line (R-002, R-003).
  FOR r IN
    SELECT
      i.id AS item_id,
      i.position,
      i.item_kind,
      i.product_id,
      i.addon_id,
      i.item_label,
      i.start_date,
      i.end_date,
      i.adults,
      i.children,
      i.quantity,
      coalesce(l.tax_rate, 0) AS tax_rate
    FROM public.pre_reservation_items i
    LEFT JOIN public.quotation_lines l
      ON l.version_id = p_version_id
     AND l.pre_reservation_item_id = i.id
    WHERE i.organization_id = p_org
      AND i.pre_reservation_id = v_pre_reservation_id
      AND i.alternative_of_item_id IS NULL
      AND i.withdrawn_at IS NULL
    ORDER BY i.position, i.id
  LOOP
    v_tariff := public.resolve_quotation_tariff(
      p_org, r.product_id, r.addon_id, r.start_date
    );
    v_charge_type := (v_tariff ->> 'charge_type')::public.charge_type;

    -- Rate for a tariff currency different from the quotation currency (R-003).
    v_is_pending := false;
    v_rate := NULL;
    IF (v_tariff ->> 'currency') <> v_version.currency THEN
      IF v_rates ? (v_tariff ->> 'currency') THEN
        v_rate := (v_rates ->> (v_tariff ->> 'currency'))::numeric;
      ELSE
        v_is_pending := true;
        IF NOT ((v_tariff ->> 'currency') = ANY (v_pending)) THEN
          v_pending := array_append(v_pending, v_tariff ->> 'currency');
        END IF;
      END IF;
    END IF;

    IF v_is_pending THEN
      -- No invented conversion: the line is reported with a zero amount.
      v_unit_price := 0;
      v_rate := NULL;
    ELSE
      v_unit_price := round((v_tariff ->> 'amount')::numeric * coalesce(v_rate, 1), 2);
    END IF;

    -- Quantity basis (R-002).
    IF v_charge_type = 'per_person'::public.charge_type THEN
      v_basis := r.adults + r.children;
    ELSIF v_charge_type = 'per_night'::public.charge_type THEN
      IF r.end_date IS NULL OR r.end_date <= r.start_date THEN
        RAISE EXCEPTION 'INVALID_DATE_RANGE' USING ERRCODE = 'raise_exception';
      END IF;
      v_basis := r.quantity * (r.end_date - r.start_date);
    ELSE
      -- per_group: quantity, except a per_service add-on whose base is 1.
      v_basis := r.quantity;
      IF r.item_kind = 'addon' AND r.addon_id IS NOT NULL THEN
        SELECT a.unit INTO v_unit
        FROM public.add_ons a
        WHERE a.id = r.addon_id AND a.organization_id = p_org;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
        END IF;
        IF v_unit = 'per_service'::public.addon_unit THEN
          v_basis := 1;
        END IF;
      END IF;
    END IF;

    IF v_basis IS NULL OR v_basis <= 0 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    -- 1. line_base, 2. signed line adjustments (rounded each).
    v_line_base := round(v_unit_price * v_basis, 2);

    v_line_adjustment := 0;
    FOR v_adj IN
      SELECT a.*
      FROM public.quotation_adjustments a
      WHERE a.version_id = p_version_id
        AND a.pre_reservation_item_id = r.item_id
    LOOP
      IF v_adj.kind = 'percent'::public.quotation_adjustment_kind THEN
        v_money := round(v_line_base * v_adj.value / 100, 2);
      ELSE
        v_money := v_adj.value;
      END IF;
      IF v_adj.direction = 'discount'::public.quotation_adjustment_direction THEN
        v_money := -v_money;
      END IF;
      v_line_adjustment := v_line_adjustment + v_money;
    END LOOP;

    -- 3-5. net, tax, total.
    v_line_net := v_line_base + v_line_adjustment;
    v_line_tax := round(v_line_net * r.tax_rate / 100, 2);
    v_line_total := v_line_net + v_line_tax;

    INSERT INTO public.quotation_lines (
      organization_id, version_id, pre_reservation_item_id, position,
      item_kind, item_label, product_id, addon_id, start_date, end_date,
      adults, children, quantity, charge_type, charge_basis,
      tariff_currency, tariff_amount, exchange_rate, unit_price, tax_rate,
      line_base, line_adjustment, line_tax, line_total
    ) VALUES (
      p_org, p_version_id, r.item_id, r.position,
      r.item_kind, left(r.item_label, 255), r.product_id, r.addon_id,
      r.start_date, r.end_date, r.adults, r.children, r.quantity,
      v_charge_type, v_basis,
      (v_tariff ->> 'currency')::char(3), (v_tariff ->> 'amount')::numeric,
      v_rate, v_unit_price, r.tax_rate,
      v_line_base, v_line_adjustment, v_line_tax, v_line_total
    )
    ON CONFLICT (version_id, pre_reservation_item_id)
    DO UPDATE SET
      position = EXCLUDED.position,
      item_label = EXCLUDED.item_label,
      start_date = EXCLUDED.start_date,
      end_date = EXCLUDED.end_date,
      adults = EXCLUDED.adults,
      children = EXCLUDED.children,
      quantity = EXCLUDED.quantity,
      charge_type = EXCLUDED.charge_type,
      charge_basis = EXCLUDED.charge_basis,
      tariff_currency = EXCLUDED.tariff_currency,
      tariff_amount = EXCLUDED.tariff_amount,
      exchange_rate = EXCLUDED.exchange_rate,
      unit_price = EXCLUDED.unit_price,
      line_base = EXCLUDED.line_base,
      line_adjustment = EXCLUDED.line_adjustment,
      line_tax = EXCLUDED.line_tax,
      line_total = EXCLUDED.line_total;

    v_sum_line_adjustment := v_sum_line_adjustment + v_line_adjustment;
    v_sum_line_tax := v_sum_line_tax + v_line_tax;
  END LOOP;

  SELECT
    coalesce(sum(l.line_base), 0),
    coalesce(sum(l.line_total), 0),
    coalesce(max(l.adults), 1),
    coalesce(max(l.children), 0)
  INTO v_sum_line_base, v_sum_line_total, v_adults, v_children
  FROM public.quotation_lines l
  WHERE l.version_id = p_version_id;

  -- 6. Global adjustment over sum(line_total).
  FOR v_adj IN
    SELECT a.*
    FROM public.quotation_adjustments a
    WHERE a.version_id = p_version_id
      AND a.pre_reservation_item_id IS NULL
  LOOP
    IF v_adj.kind = 'percent'::public.quotation_adjustment_kind THEN
      v_money := round(v_sum_line_total * v_adj.value / 100, 2);
    ELSE
      v_money := v_adj.value;
    END IF;
    IF v_adj.direction = 'discount'::public.quotation_adjustment_direction THEN
      v_money := -v_money;
    END IF;
    v_global := v_global + v_money;
  END LOOP;

  -- 7. Header. Subtotals are sums of already-rounded lines (R-003).
  v_adjustment_total := v_sum_line_adjustment + v_global;
  v_total := v_sum_line_total + v_global;

  IF v_total < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.quotation_versions
  SET subtotal = v_sum_line_base,
      tax_total = v_sum_line_tax,
      adjustment_total = v_adjustment_total,
      total = v_total,
      party_adults = v_adults,
      party_children = v_children
  WHERE id = p_version_id;

  RETURN jsonb_build_object(
    'family_id', v_version.family_id,
    'version_id', v_version.id,
    'version_number', v_version.version_number,
    'status', v_version.status,
    'currency', v_version.currency::text,
    'subtotal', v_sum_line_base,
    'tax_total', v_sum_line_tax,
    'adjustment_total', v_adjustment_total,
    'total', v_total,
    'party_adults', v_adults,
    'party_children', v_children,
    'pending_currencies', (
      SELECT coalesce(jsonb_agg(c ORDER BY c), '[]'::jsonb)
      FROM unnest(v_pending) AS u(c)
    ),
    'lines', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'line_id', l.id,
        'pre_reservation_item_id', l.pre_reservation_item_id,
        'position', l.position,
        'item_kind', l.item_kind,
        'item_label', l.item_label,
        'product_id', l.product_id,
        'addon_id', l.addon_id,
        'start_date', l.start_date,
        'end_date', l.end_date,
        'adults', l.adults,
        'children', l.children,
        'quantity', l.quantity,
        'charge_type', l.charge_type,
        'charge_basis', l.charge_basis,
        'tariff_currency', l.tariff_currency::text,
        'tariff_amount', l.tariff_amount,
        'exchange_rate', l.exchange_rate,
        'unit_price', l.unit_price,
        'tax_rate', l.tax_rate,
        'line_base', l.line_base,
        'line_adjustment', l.line_adjustment,
        'line_tax', l.line_tax,
        'line_total', l.line_total,
        'currency_pending', l.exchange_rate IS NULL AND l.tariff_currency <> v_version.currency
      ) ORDER BY l.position, l.created_at, l.id), '[]'::jsonb)
      FROM public.quotation_lines l
      WHERE l.version_id = p_version_id
    )
  );
END;
$$;

COMMENT ON FUNCTION public.recalculate_quotation_core(uuid, uuid) IS
  'Single pricing authority for a draft version: revalidates the pre-reservation, rebuilds lines from active items, resolves tariffs, applies rates/adjustments/tax, persists the header and returns the breakdown with pending_currencies.';

REVOKE ALL ON FUNCTION public.recalculate_quotation_core(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recalculate_quotation_core(uuid, uuid) FROM anon, authenticated;
