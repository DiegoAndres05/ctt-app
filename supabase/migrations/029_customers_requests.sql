-- 029_customers_requests.sql
-- Customers, requests, request items, per-organization sequences, list views, and RLS.
-- Source of truth: specs/003-customer-requests-channels/data-model.md (§1–§4, §8, Views).
--
-- Writes are not granted to authenticated. Capture and later RPCs are SECURITY DEFINER.
-- anon has no table or view privileges (Default Deny).

-- Composite key so assigned_to and note authors can pin the tenant (data-model §8).
ALTER TABLE public.user_profiles
  ADD CONSTRAINT user_profiles_id_organization_id_key UNIQUE (id, organization_id);

-- ---------------------------------------------------------------------------
-- customers
-- ---------------------------------------------------------------------------

CREATE TABLE public.customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  first_name text NOT NULL,
  last_name text,
  email text,
  phone_e164 text,
  document_type public.document_type,
  document_number text,
  country_code char(2),
  is_anonymized boolean NOT NULL DEFAULT false,
  anonymized_at timestamptz,
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customers_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT customers_first_name_bounds CHECK (
    first_name = btrim(first_name)
    AND char_length(first_name) BETWEEN 1 AND 120
  ),
  CONSTRAINT customers_last_name_bounds CHECK (
    last_name IS NULL
    OR (last_name = btrim(last_name) AND char_length(last_name) BETWEEN 1 AND 120)
  ),
  CONSTRAINT customers_contact_required CHECK (
    is_anonymized OR email IS NOT NULL OR phone_e164 IS NOT NULL
  ),
  CONSTRAINT customers_email_normalized CHECK (
    email IS NULL OR (email = lower(btrim(email)) AND char_length(email) <= 254)
  ),
  CONSTRAINT customers_phone_e164_format CHECK (
    phone_e164 IS NULL OR phone_e164 ~ '^\+[1-9][0-9]{7,14}$'
  ),
  CONSTRAINT customers_country_code_format CHECK (
    country_code IS NULL OR country_code ~ '^[A-Z]{2}$'
  ),
  CONSTRAINT customers_document_pair CHECK (
    document_number IS NULL OR document_type IS NOT NULL
  ),
  CONSTRAINT customers_document_number_bounds CHECK (
    document_number IS NULL
    OR (document_number = btrim(document_number) AND char_length(document_number) BETWEEN 1 AND 40)
  ),
  CONSTRAINT customers_anonymized_consistent CHECK (
    is_anonymized = (anonymized_at IS NOT NULL)
  )
);

COMMENT ON TABLE public.customers IS
  'Traveler who requests or buys services. Single source of traveler PII for the tenant.';

CREATE UNIQUE INDEX customers_org_email_key
  ON public.customers (organization_id, email)
  WHERE email IS NOT NULL;

CREATE UNIQUE INDEX customers_org_phone_key
  ON public.customers (organization_id, phone_e164)
  WHERE phone_e164 IS NOT NULL;

CREATE INDEX customers_organization_id_created_at_idx
  ON public.customers (organization_id, created_at DESC);

CREATE INDEX customers_organization_id_name_idx
  ON public.customers (organization_id, lower(first_name), lower(last_name));

-- ---------------------------------------------------------------------------
-- customer_requests
-- ---------------------------------------------------------------------------

CREATE TABLE public.customer_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  reference text NOT NULL,
  customer_id uuid NOT NULL,
  channel public.request_channel NOT NULL,
  status public.request_status NOT NULL DEFAULT 'received',
  assigned_to uuid,
  assigned_at timestamptz,
  travel_start_date date,
  travel_end_date date,
  adults smallint NOT NULL DEFAULT 1,
  children smallint NOT NULL DEFAULT 0,
  special_requirements text,
  locale text,
  source_page text,
  submitted_contact jsonb,
  contact_review_required boolean NOT NULL DEFAULT false,
  privacy_consent_at timestamptz,
  idempotency_key uuid,
  dedup_fingerprint text NOT NULL,
  discard_reason text,
  first_handled_at timestamptz,
  closed_at timestamptz,
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customer_requests_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT customer_requests_reference_key UNIQUE (organization_id, reference),
  CONSTRAINT customer_requests_customer_fkey
    FOREIGN KEY (customer_id, organization_id)
    REFERENCES public.customers (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT customer_requests_assigned_to_fkey
    FOREIGN KEY (assigned_to, organization_id)
    REFERENCES public.user_profiles (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT customer_requests_reference_not_blank CHECK (btrim(reference) <> ''),
  CONSTRAINT customer_requests_fingerprint_not_blank CHECK (btrim(dedup_fingerprint) <> ''),
  CONSTRAINT customer_requests_adults_range CHECK (adults BETWEEN 1 AND 99),
  CONSTRAINT customer_requests_children_range CHECK (children BETWEEN 0 AND 99),
  CONSTRAINT customer_requests_date_range CHECK (
    travel_end_date IS NULL
    OR travel_start_date IS NULL
    OR travel_end_date >= travel_start_date
  ),
  CONSTRAINT customer_requests_special_requirements_len CHECK (
    special_requirements IS NULL OR char_length(special_requirements) <= 2000
  ),
  CONSTRAINT customer_requests_locale CHECK (locale IS NULL OR locale IN ('es', 'en')),
  CONSTRAINT customer_requests_source_page_len CHECK (
    source_page IS NULL OR char_length(source_page) <= 500
  ),
  CONSTRAINT customer_requests_discard_reason CHECK (
    (status = 'discarded') = (discard_reason IS NOT NULL)
  ),
  CONSTRAINT customer_requests_discard_reason_len CHECK (
    discard_reason IS NULL OR char_length(btrim(discard_reason)) BETWEEN 1 AND 500
  ),
  CONSTRAINT customer_requests_closed_at CHECK (
    (status IN ('discarded', 'pre_reservation')) = (closed_at IS NOT NULL)
  ),
  CONSTRAINT customer_requests_first_handled CHECK (
    status = 'received' OR first_handled_at IS NOT NULL
  ),
  CONSTRAINT customer_requests_web_consent CHECK (
    channel <> 'web' OR privacy_consent_at IS NOT NULL
  )
);

COMMENT ON TABLE public.customer_requests IS
  'Non-binding commercial intent. Never blocks inventory and never creates a reservation.';
COMMENT ON COLUMN public.customer_requests.submitted_contact IS
  'Normalized contact as submitted, stored only when it differs from the customer profile.';

CREATE UNIQUE INDEX customer_requests_org_idempotency_key
  ON public.customer_requests (organization_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX customer_requests_org_status_created_idx
  ON public.customer_requests (organization_id, status, created_at DESC);

CREATE INDEX customer_requests_org_channel_created_idx
  ON public.customer_requests (organization_id, channel, created_at DESC);

CREATE INDEX customer_requests_customer_created_idx
  ON public.customer_requests (customer_id, created_at DESC);

CREATE INDEX customer_requests_org_assignee_idx
  ON public.customer_requests (organization_id, assigned_to);

CREATE INDEX customer_requests_org_fingerprint_created_idx
  ON public.customer_requests (organization_id, dedup_fingerprint, created_at DESC);

-- ---------------------------------------------------------------------------
-- customer_request_items
-- ---------------------------------------------------------------------------

CREATE TABLE public.customer_request_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  request_id uuid NOT NULL,
  product_id uuid,
  public_slug text,
  free_text text,
  quantity smallint NOT NULL DEFAULT 1,
  position smallint NOT NULL,
  CONSTRAINT customer_request_items_request_fkey
    FOREIGN KEY (request_id, organization_id)
    REFERENCES public.customer_requests (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT customer_request_items_product_fkey
    FOREIGN KEY (product_id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE RESTRICT,
  CONSTRAINT customer_request_items_position_key UNIQUE (request_id, position),
  CONSTRAINT customer_request_items_target CHECK (
    product_id IS NOT NULL OR free_text IS NOT NULL
  ),
  CONSTRAINT customer_request_items_quantity_range CHECK (quantity BETWEEN 1 AND 99),
  CONSTRAINT customer_request_items_position_non_negative CHECK (position >= 0),
  CONSTRAINT customer_request_items_free_text_len CHECK (
    free_text IS NULL OR char_length(free_text) <= 500
  ),
  CONSTRAINT customer_request_items_slug_len CHECK (
    public_slug IS NULL OR char_length(public_slug) <= 200
  )
);

COMMENT ON TABLE public.customer_request_items IS
  'What the traveler asked about: a catalog product, free text, or both.';

CREATE INDEX customer_request_items_org_product_idx
  ON public.customer_request_items (organization_id, product_id);

-- ---------------------------------------------------------------------------
-- organization_sequences
-- ---------------------------------------------------------------------------

CREATE TABLE public.organization_sequences (
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  scope text NOT NULL,
  last_value bigint NOT NULL,
  PRIMARY KEY (organization_id, scope),
  CONSTRAINT organization_sequences_scope_not_blank CHECK (btrim(scope) <> ''),
  CONSTRAINT organization_sequences_last_value_non_negative CHECK (last_value >= 0)
);

COMMENT ON TABLE public.organization_sequences IS
  'Per-tenant counters. scope customer_request numbers SOL- references; later features reuse it.';

-- ---------------------------------------------------------------------------
-- Identity of a request cannot change after insert
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_customer_request_identity_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.channel IS DISTINCT FROM OLD.channel
     OR NEW.customer_id IS DISTINCT FROM OLD.customer_id
     OR NEW.reference IS DISTINCT FROM OLD.reference
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.prevent_customer_request_identity_change() IS
  'Rejects changes to channel, customer, reference, or created_at on a customer request.';

REVOKE ALL ON FUNCTION public.prevent_customer_request_identity_change() FROM PUBLIC;

CREATE TRIGGER customer_requests_prevent_identity_change
  BEFORE UPDATE ON public.customer_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_customer_request_identity_change();

CREATE TRIGGER customers_set_updated_at
  BEFORE UPDATE ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER customer_requests_set_updated_at
  BEFORE UPDATE ON public.customer_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: SELECT-only for the tenant. No policies on organization_sequences.
-- ---------------------------------------------------------------------------

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_request_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_sequences ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.customers FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.customers FROM authenticated;

REVOKE ALL ON public.customer_requests FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.customer_requests FROM authenticated;

REVOKE ALL ON public.customer_request_items FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.customer_request_items FROM authenticated;

REVOKE ALL ON public.organization_sequences FROM anon;
REVOKE ALL ON public.organization_sequences FROM authenticated;

CREATE POLICY tenant_isolation_select ON public.customers
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.customer_requests
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.customer_request_items
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- ---------------------------------------------------------------------------
-- List views (security_invoker so the caller's RLS applies)
-- ---------------------------------------------------------------------------

CREATE VIEW public.customer_request_list
WITH (security_invoker = true) AS
SELECT
  r.id,
  r.organization_id,
  r.reference,
  r.channel,
  r.status,
  r.created_at,
  r.travel_start_date,
  r.travel_end_date,
  r.adults,
  r.children,
  r.contact_review_required,
  r.assigned_to,
  up.full_name AS assignee_name,
  r.customer_id,
  c.first_name AS customer_first_name,
  c.last_name AS customer_last_name,
  c.email AS customer_email,
  c.phone_e164 AS customer_phone_e164,
  c.is_anonymized AS customer_is_anonymized,
  (
    SELECT count(*)::integer
    FROM public.customer_request_items i
    WHERE i.request_id = r.id
  ) AS item_count
FROM public.customer_requests r
JOIN public.customers c
  ON c.id = r.customer_id
 AND c.organization_id = r.organization_id
LEFT JOIN public.user_profiles up
  ON up.id = r.assigned_to
 AND up.organization_id = r.organization_id;

COMMENT ON VIEW public.customer_request_list IS
  'Request inbox. security_invoker: the caller''s RLS on the base tables still applies.';

CREATE VIEW public.customer_list
WITH (security_invoker = true) AS
SELECT
  c.id,
  c.organization_id,
  c.first_name,
  c.last_name,
  c.email,
  c.phone_e164,
  c.country_code,
  c.is_anonymized,
  c.created_at,
  (
    SELECT count(*)::integer
    FROM public.customer_requests r
    WHERE r.customer_id = c.id
  ) AS request_count,
  (
    SELECT max(r.created_at)
    FROM public.customer_requests r
    WHERE r.customer_id = c.id
  ) AS last_request_at
FROM public.customers c;

COMMENT ON VIEW public.customer_list IS
  'Customer directory with request counts. security_invoker applies customers RLS.';

REVOKE ALL ON public.customer_request_list FROM anon;
GRANT SELECT ON public.customer_request_list TO authenticated;

REVOKE ALL ON public.customer_list FROM anon;
GRANT SELECT ON public.customer_list TO authenticated;

-- Realtime is optional: the SQL harness has no supabase_realtime publication.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.customer_requests;
  END IF;
END $$;
