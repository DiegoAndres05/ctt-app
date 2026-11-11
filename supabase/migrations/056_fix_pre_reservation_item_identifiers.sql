-- 056_fix_pre_reservation_item_identifiers.sql
-- Corrective migration (stabilization 2026-11-11, defect D1).
--
-- resolve_pre_reservation_item (037) validated "exactly one of product_id / addon_id" with
-- the JSONB key-existence operator `?`. The panel sends both keys with the unused one set to
-- null ({"product_id": "<uuid>", "addon_id": null}), so create_pre_reservation and
-- add_pre_reservation_item always failed with VALIDATION_ERROR.
--
-- This migration redefines only resolve_pre_reservation_item: the rule is now evaluated on the
-- effective values (absent, JSON null or blank = not provided) and a malformed uuid raises
-- VALIDATION_ERROR instead of an unhandled cast error. Same signature, volatility,
-- SECURITY DEFINER, search_path, comment and grants (internal: no EXECUTE for PUBLIC, anon,
-- authenticated). Every other rule of the function is unchanged. 037 is not edited.

CREATE OR REPLACE FUNCTION public.resolve_pre_reservation_item(
  p_org uuid,
  p_request_id uuid,
  p_item jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item jsonb := p_item;
  v_product_text text;
  v_addon_text text;
  v_product_id uuid;
  v_addon_id uuid;
  v_start_date date;
  v_end_date date;
  v_adults integer;
  v_children integer;
  v_quantity integer;
  v_source_request_item_id uuid;
  v_provider_name text;
  v_provider_phone text;
  v_provider_email text;
  v_item_kind text;
  v_item_label text;
  v_provider_id uuid;
  v_product public.products%ROWTYPE;
  v_addon public.add_ons%ROWTYPE;
  v_today date;
BEGIN
  IF p_org IS NULL OR p_request_id IS NULL OR v_item IS NULL OR jsonb_typeof(v_item) <> 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- XOR product_id / addon_id on the *effective* identifiers (056): a key that is absent,
  -- JSON null or blank counts as "not provided". The previous check used the key-existence
  -- operator `?`, so {"product_id": "<uuid>", "addon_id": null} was rejected.
  v_product_text := NULLIF(btrim(coalesce(v_item ->> 'product_id', '')), '');
  v_addon_text := NULLIF(btrim(coalesce(v_item ->> 'addon_id', '')), '');
  IF (v_product_text IS NULL) = (v_addon_text IS NULL) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- A malformed identifier is a validation error, not an unhandled cast failure.
  BEGIN
    v_product_id := v_product_text::uuid;
    v_addon_id := v_addon_text::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  IF v_product_id IS NOT NULL THEN
    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_product_id AND organization_id = p_org;
    IF NOT FOUND OR v_product.status <> 'active' THEN
      RAISE EXCEPTION 'ITEM_NOT_BOOKABLE' USING ERRCODE = 'raise_exception';
    END IF;
    v_item_kind := v_product.type;
    v_item_label := v_product.name;
    v_provider_id := v_product.provider_id;
  ELSE
    SELECT * INTO v_addon
    FROM public.add_ons
    WHERE id = v_addon_id AND organization_id = p_org;
    IF NOT FOUND OR v_addon.is_active <> true THEN
      RAISE EXCEPTION 'ITEM_NOT_BOOKABLE' USING ERRCODE = 'raise_exception';
    END IF;
    v_item_kind := 'addon';
    v_item_label := v_addon.name;
    v_provider_id := NULL;
  END IF;

  -- Dates
  BEGIN
    v_start_date := (v_item ->> 'start_date')::date;
    IF v_item ? 'end_date' AND v_item ->> 'end_date' <> '' THEN
      v_end_date := (v_item ->> 'end_date')::date;
    ELSE
      v_end_date := NULL;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;

  v_today := (now() AT TIME ZONE 'America/Bogota')::date;
  IF v_start_date < v_today THEN
    RAISE EXCEPTION 'TRAVEL_DATE_IN_PAST' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_end_date IS NOT NULL AND v_end_date < v_start_date THEN
    RAISE EXCEPTION 'INVALID_DATE_RANGE' USING ERRCODE = 'raise_exception';
  END IF;
  IF v_item_kind = 'accommodation' AND (v_end_date IS NULL OR v_end_date <= v_start_date) THEN
    RAISE EXCEPTION 'INVALID_DATE_RANGE' USING ERRCODE = 'raise_exception';
  END IF;

  -- Passengers
  BEGIN
    v_adults := COALESCE(NULLIF(v_item ->> 'adults', '')::integer, 1);
    v_children := COALESCE(NULLIF(v_item ->> 'children', '')::integer, 0);
    v_quantity := COALESCE(NULLIF(v_item ->> 'quantity', '')::integer, 1);
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END;
  IF v_adults < 1 OR v_adults > 99
     OR v_children < 0 OR v_children > 99
     OR v_quantity < 1 OR v_quantity > 99
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- source_request_item_id
  IF v_item ? 'source_request_item_id' AND v_item ->> 'source_request_item_id' <> '' THEN
    v_source_request_item_id := (v_item ->> 'source_request_item_id')::uuid;
    IF NOT EXISTS (
      SELECT 1 FROM public.customer_request_items
      WHERE id = v_source_request_item_id
        AND request_id = p_request_id
    ) THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;
  ELSE
    v_source_request_item_id := NULL;
  END IF;

  -- Provider snapshot or manual fields
  IF v_provider_id IS NOT NULL THEN
    SELECT name, contact_phone, contact_email
    INTO v_provider_name, v_provider_phone, v_provider_email
    FROM public.providers
    WHERE id = v_provider_id AND organization_id = p_org AND is_active = true;
    IF NOT FOUND THEN
      v_provider_id := NULL;
      v_provider_name := NULL;
      v_provider_phone := NULL;
      v_provider_email := NULL;
    END IF;
  ELSE
    v_provider_name := nullif(btrim(coalesce(v_item ->> 'provider_name', '')), '');
    v_provider_phone := nullif(btrim(coalesce(v_item ->> 'provider_phone', '')), '');
    v_provider_email := nullif(btrim(coalesce(v_item ->> 'provider_email', '')), '');
    IF v_provider_name IS NOT NULL AND char_length(v_provider_name) > 255 THEN
      v_provider_name := left(v_provider_name, 255);
    END IF;
    IF v_provider_phone IS NOT NULL AND char_length(v_provider_phone) > 40 THEN
      v_provider_phone := left(v_provider_phone, 40);
    END IF;
    IF v_provider_email IS NOT NULL AND char_length(v_provider_email) > 254 THEN
      v_provider_email := left(v_provider_email, 254);
    END IF;
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'item_kind', v_item_kind,
    'item_label', v_item_label,
    'product_id', v_product_id,
    'addon_id', v_addon_id,
    'source_request_item_id', v_source_request_item_id,
    'start_date', v_start_date,
    'end_date', v_end_date,
    'adults', v_adults,
    'children', v_children,
    'quantity', v_quantity,
    'provider_id', v_provider_id,
    'provider_name', v_provider_name,
    'provider_phone', v_provider_phone,
    'provider_email', v_provider_email
  ));
END;
$$;

COMMENT ON FUNCTION public.resolve_pre_reservation_item(uuid, uuid, jsonb) IS
  'Validates and normalizes a pre-reservation item payload. Returns normalized item with item_kind, item_label, and provider snapshot.';

REVOKE ALL ON FUNCTION public.resolve_pre_reservation_item(uuid, uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_pre_reservation_item(uuid, uuid, jsonb) FROM anon, authenticated;
