-- 032_us2_whatsapp_intake.sql
-- Assisted capture and the WhatsApp webhook parser.
-- Source of truth: specs/003-customer-requests-channels/data-model.md (§5–§6),
-- specs/003-customer-requests-channels/contracts/api-contracts.md (§3.1–§3.2),
-- specs/003-customer-requests-channels/research.md (R-007).
--
-- ingest_whatsapp_webhook is executable only by service_role. The Edge Function
-- verifies the Meta signature before calling it. No credentials are stored here.

-- ---------------------------------------------------------------------------
-- channel_connections, inbound_messages
-- ---------------------------------------------------------------------------

CREATE TABLE public.channel_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  channel public.request_channel NOT NULL,
  provider text NOT NULL,
  external_account_id text NOT NULL,
  display_phone text,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT channel_connections_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT channel_connections_provider_account_key UNIQUE (provider, external_account_id),
  CONSTRAINT channel_connections_channel_check CHECK (channel = 'whatsapp'),
  CONSTRAINT channel_connections_provider_check CHECK (provider IN ('meta_cloud')),
  CONSTRAINT channel_connections_status_check CHECK (status IN ('active', 'inactive')),
  CONSTRAINT channel_connections_external_len CHECK (
    char_length(btrim(external_account_id)) BETWEEN 1 AND 128
  ),
  CONSTRAINT channel_connections_display_len CHECK (
    display_phone IS NULL OR char_length(display_phone) <= 40
  )
);

COMMENT ON TABLE public.channel_connections IS
  'Maps a provider account (Meta phone_number_id) to a tenant. Secrets stay in the function environment.';

CREATE TABLE public.inbound_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  connection_id uuid NOT NULL,
  channel public.request_channel NOT NULL,
  provider text NOT NULL,
  provider_message_id text NOT NULL,
  from_phone_e164 text,
  profile_name text,
  message_type text NOT NULL,
  body text NOT NULL,
  provider_timestamp timestamptz NOT NULL,
  customer_id uuid NOT NULL,
  request_id uuid NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inbound_messages_connection_fkey
    FOREIGN KEY (connection_id, organization_id)
    REFERENCES public.channel_connections (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT inbound_messages_customer_fkey
    FOREIGN KEY (customer_id, organization_id)
    REFERENCES public.customers (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT inbound_messages_request_fkey
    FOREIGN KEY (request_id, organization_id)
    REFERENCES public.customer_requests (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT inbound_messages_provider_message_key UNIQUE (provider, provider_message_id),
  CONSTRAINT inbound_messages_channel_check CHECK (channel = 'whatsapp'),
  CONSTRAINT inbound_messages_provider_check CHECK (provider IN ('meta_cloud')),
  CONSTRAINT inbound_messages_provider_message_len CHECK (
    char_length(btrim(provider_message_id)) BETWEEN 1 AND 256
  ),
  CONSTRAINT inbound_messages_phone_format CHECK (
    from_phone_e164 IS NULL OR from_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'
  ),
  CONSTRAINT inbound_messages_profile_len CHECK (
    profile_name IS NULL OR char_length(profile_name) <= 120
  ),
  CONSTRAINT inbound_messages_type_len CHECK (
    char_length(btrim(message_type)) BETWEEN 1 AND 40
  ),
  CONSTRAINT inbound_messages_body_len CHECK (char_length(body) BETWEEN 1 AND 4096)
);

COMMENT ON TABLE public.inbound_messages IS
  'Append-only WhatsApp messages, except the scrub performed by anonymize_customer.';

CREATE INDEX inbound_messages_request_timestamp_idx
  ON public.inbound_messages (request_id, provider_timestamp);

CREATE TRIGGER channel_connections_set_updated_at
  BEFORE UPDATE ON public.channel_connections
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.channel_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inbound_messages ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.channel_connections FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.channel_connections FROM authenticated;

REVOKE ALL ON public.inbound_messages FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.inbound_messages FROM authenticated;

CREATE POLICY tenant_isolation_select ON public.channel_connections
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.inbound_messages
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- ---------------------------------------------------------------------------
-- create_assisted_request
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_assisted_request(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_channel public.request_channel;
  v_customer_id uuid;
  v_has_customer boolean;
  v_has_contact boolean;
  v_items jsonb := '[]'::jsonb;
  v_raw_items jsonb;
  v_item jsonb;
  v_product_id uuid;
  v_product_status public.product_status;
  v_free text;
  v_qty integer;
  v_request jsonb;
BEGIN
  v_org := public.require_tenant_member();

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_payload ->> 'channel' IS NULL
     OR p_payload ->> 'channel' NOT IN ('whatsapp', 'phone', 'in_person')
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  v_channel := (p_payload ->> 'channel')::public.request_channel;

  IF p_payload -> 'privacy_notice_given' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'CONSENT_REQUIRED' USING ERRCODE = 'raise_exception';
  END IF;

  v_has_customer := nullif(btrim(coalesce(p_payload ->> 'customer_id', '')), '') IS NOT NULL;
  v_has_contact := jsonb_typeof(p_payload -> 'contact') = 'object';
  IF v_has_customer = v_has_contact THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF v_has_customer THEN
    BEGIN
      v_customer_id := (p_payload ->> 'customer_id')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;
  END IF;

  v_raw_items := p_payload -> 'items';
  IF v_raw_items IS NULL OR jsonb_typeof(v_raw_items) = 'null' THEN
    v_raw_items := '[]'::jsonb;
  ELSIF jsonb_typeof(v_raw_items) <> 'array' OR jsonb_array_length(v_raw_items) > 20 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  FOR v_item IN
    SELECT value FROM jsonb_array_elements(v_raw_items)
  LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    v_free := nullif(btrim(coalesce(v_item ->> 'free_text', '')), '');
    IF v_free IS NOT NULL AND char_length(v_free) > 500 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    v_product_id := NULL;
    IF nullif(btrim(coalesce(v_item ->> 'product_id', '')), '') IS NOT NULL THEN
      BEGIN
        v_product_id := (v_item ->> 'product_id')::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END;

      SELECT p.status
      INTO v_product_status
      FROM public.products p
      WHERE p.id = v_product_id
        AND p.organization_id = v_org;

      IF v_product_status IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
      END IF;
    END IF;

    IF v_product_id IS NULL AND v_free IS NULL THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    BEGIN
      IF v_item ? 'quantity' AND jsonb_typeof(v_item -> 'quantity') = 'number' THEN
        v_qty := (v_item ->> 'quantity')::integer;
      ELSE
        v_qty := 1;
      END IF;
    EXCEPTION
      WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;

    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END IF;

    v_items := v_items || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'product_id', v_product_id,
      'free_text', v_free,
      'quantity', v_qty
    )));
  END LOOP;

  v_request := jsonb_strip_nulls(jsonb_build_object(
    'travel_start_date', nullif(p_payload ->> 'travel_start_date', ''),
    'travel_end_date', nullif(p_payload ->> 'travel_end_date', ''),
    'adults', CASE WHEN jsonb_typeof(p_payload -> 'adults') = 'number' THEN p_payload -> 'adults' END,
    'children', CASE WHEN jsonb_typeof(p_payload -> 'children') = 'number' THEN p_payload -> 'children' END,
    'special_requirements', nullif(btrim(coalesce(p_payload ->> 'special_requirements', '')), ''),
    'idempotency_key', nullif(btrim(coalesce(p_payload ->> 'idempotency_key', '')), ''),
    'privacy_consent_at', now(),
    'assign_to', auth.uid()
  ));

  RETURN public.capture_request_core(
    v_org,
    v_channel,
    v_customer_id,
    CASE WHEN v_has_contact THEN p_payload -> 'contact' ELSE NULL END,
    v_request,
    v_items,
    auth.uid()
  );
END;
$$;

COMMENT ON FUNCTION public.create_assisted_request(jsonb) IS
  'Panel intake for WhatsApp, phone, and in-person. Assigns the request to the caller.';

REVOKE ALL ON FUNCTION public.create_assisted_request(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_assisted_request(jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- ingest_whatsapp_webhook
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ingest_whatsapp_webhook(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_processed integer := 0;
  v_duplicates integer := 0;
  v_ignored integer := 0;
  v_created integer := 0;
  v_attached integer := 0;
  v_entry jsonb;
  v_change jsonb;
  v_value jsonb;
  v_msg jsonb;
  v_conn public.channel_connections%ROWTYPE;
  v_phone_number_id text;
  v_wamid text;
  v_from text;
  v_type text;
  v_body text;
  v_name text;
  v_phone text;
  v_match jsonb;
  v_customer_id uuid;
  v_request_id uuid;
  v_captured jsonb;
BEGIN
  IF p_payload IS NULL
     OR jsonb_typeof(p_payload) <> 'object'
     OR p_payload ->> 'object' IS DISTINCT FROM 'whatsapp_business_account'
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  FOR v_entry IN
    SELECT value FROM jsonb_array_elements(coalesce(p_payload -> 'entry', '[]'::jsonb))
  LOOP
    FOR v_change IN
      SELECT value FROM jsonb_array_elements(coalesce(v_entry -> 'changes', '[]'::jsonb))
    LOOP
      IF v_change ->> 'field' IS DISTINCT FROM 'messages' THEN
        CONTINUE;
      END IF;

      v_value := v_change -> 'value';
      v_phone_number_id := v_value -> 'metadata' ->> 'phone_number_id';

      SELECT *
      INTO v_conn
      FROM public.channel_connections c
      WHERE c.provider = 'meta_cloud'
        AND c.external_account_id = v_phone_number_id
        AND c.status = 'active';

      IF NOT FOUND THEN
        v_ignored := v_ignored + coalesce(jsonb_array_length(v_value -> 'messages'), 0);
        CONTINUE;
      END IF;

      FOR v_msg IN
        SELECT value FROM jsonb_array_elements(coalesce(v_value -> 'messages', '[]'::jsonb))
      LOOP
        v_wamid := nullif(btrim(coalesce(v_msg ->> 'id', '')), '');
        IF v_wamid IS NULL THEN
          v_ignored := v_ignored + 1;
          CONTINUE;
        END IF;

        IF EXISTS (
          SELECT 1
          FROM public.inbound_messages m
          WHERE m.provider = 'meta_cloud'
            AND m.provider_message_id = v_wamid
        ) THEN
          v_duplicates := v_duplicates + 1;
          CONTINUE;
        END IF;

        v_type := coalesce(nullif(btrim(coalesce(v_msg ->> 'type', '')), ''), 'unknown');
        IF v_type = 'text' THEN
          v_body := left(coalesce(v_msg -> 'text' ->> 'body', ''), 4096);
          IF btrim(v_body) = '' THEN
            v_body := '[mensaje no soportado: text]';
          END IF;
        ELSE
          v_body := left('[mensaje no soportado: ' || v_type || ']', 4096);
        END IF;

        v_from := coalesce(v_msg ->> 'from', '');
        v_phone := public.normalize_phone_e164(
          CASE WHEN left(v_from, 1) = '+' THEN v_from ELSE '+' || v_from END,
          public.organization_phone_country_code(v_conn.organization_id)
        );

        SELECT left(btrim(c.elem -> 'profile' ->> 'name'), 120)
        INTO v_name
        FROM jsonb_array_elements(coalesce(v_value -> 'contacts', '[]'::jsonb)) AS c(elem)
        WHERE c.elem ->> 'wa_id' = v_from
        LIMIT 1;

        IF v_name IS NULL OR v_name = '' THEN
          v_name := 'Contacto WhatsApp';
        END IF;

        v_match := public.match_or_create_customer(
          v_conn.organization_id,
          jsonb_build_object('first_name', v_name, 'phone', v_phone),
          NULL
        );
        v_customer_id := (v_match ->> 'customer_id')::uuid;

        SELECT r.id
        INTO v_request_id
        FROM public.customer_requests r
        WHERE r.organization_id = v_conn.organization_id
          AND r.customer_id = v_customer_id
          AND r.channel = 'whatsapp'
          AND r.status IN ('received', 'in_review')
        ORDER BY r.created_at DESC
        LIMIT 1;

        IF v_request_id IS NOT NULL THEN
          v_attached := v_attached + 1;
        ELSE
          v_captured := public.capture_request_core(
            v_conn.organization_id,
            'whatsapp',
            v_customer_id,
            NULL,
            jsonb_build_object('special_requirements', left(v_body, 2000)),
            '[]'::jsonb,
            NULL
          );
          v_request_id := (v_captured ->> 'request_id')::uuid;
          IF coalesce((v_captured ->> 'deduplicated')::boolean, false) THEN
            v_attached := v_attached + 1;
          ELSE
            v_created := v_created + 1;
          END IF;
        END IF;

        INSERT INTO public.inbound_messages (
          organization_id, connection_id, channel, provider, provider_message_id,
          from_phone_e164, profile_name, message_type, body, provider_timestamp,
          customer_id, request_id
        )
        VALUES (
          v_conn.organization_id,
          v_conn.id,
          'whatsapp',
          'meta_cloud',
          v_wamid,
          v_phone,
          v_name,
          left(v_type, 40),
          v_body,
          to_timestamp(coalesce(v_msg ->> 'timestamp', '0')::double precision),
          v_customer_id,
          v_request_id
        );

        v_processed := v_processed + 1;
      END LOOP;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'processed', v_processed,
    'duplicates', v_duplicates,
    'ignored', v_ignored,
    'requests_created', v_created,
    'messages_attached', v_attached
  );
END;
$$;

COMMENT ON FUNCTION public.ingest_whatsapp_webhook(jsonb) IS
  'Parses a Meta WhatsApp payload into customers, requests, and inbound messages. service_role only.';

REVOKE ALL ON FUNCTION public.ingest_whatsapp_webhook(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_whatsapp_webhook(jsonb) TO service_role;
