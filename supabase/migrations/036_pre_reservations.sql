-- 036_pre_reservations.sql
-- Core tables for pre-reservations and human availability verification.
-- Source of truth: specs/004-prereservation-availability/data-model.md (§0–§3, §Views, §RLS & Privileges),
-- specs/004-prereservation-availability/research.md (R-001..R-013).
--
-- Creates tables: pre_reservations, pre_reservation_items, availability_verification_events
-- Creates views: pre_reservation_list, availability_verification_queue
-- Adds table to Realtime publication if it exists.

-- ---------------------------------------------------------------------------
-- 0. Supporting change: public.providers UNIQUE (id, organization_id)
-- ---------------------------------------------------------------------------

ALTER TABLE public.providers
ADD CONSTRAINT providers_id_organization_id_key UNIQUE (id, organization_id);

COMMENT ON CONSTRAINT providers_id_organization_id_key ON public.providers IS
  'Allows composite FK from pre_reservation_items to providers. id is already PK, so this cannot fail.';

-- ---------------------------------------------------------------------------
-- 1. pre_reservations
-- ---------------------------------------------------------------------------

CREATE TABLE public.pre_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  reference text NOT NULL,
  request_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  responsible_agent_id uuid NOT NULL,
  assigned_operator_id uuid,
  status public.pre_reservation_status NOT NULL DEFAULT 'pending_verification',
  expires_at timestamptz,
  verified_at timestamptz,
  first_verified_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  cancelled_by uuid,
  quote_override_at timestamptz,
  quote_override_by uuid,
  quote_override_reason text,
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pre_reservations_request_fkey FOREIGN KEY (request_id, organization_id)
    REFERENCES public.customer_requests (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservations_customer_fkey FOREIGN KEY (customer_id, organization_id)
    REFERENCES public.customers (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservations_responsible_agent_fkey FOREIGN KEY (responsible_agent_id, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservations_assigned_operator_fkey FOREIGN KEY (assigned_operator_id, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservations_cancelled_by_fkey FOREIGN KEY (cancelled_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservations_quote_override_by_fkey FOREIGN KEY (quote_override_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservations_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT pre_reservations_reference_key UNIQUE (organization_id, reference),
  CONSTRAINT pre_reservations_cancel_consistent CHECK (
    (status = 'cancelled') = (cancelled_at IS NOT NULL)
    AND (cancelled_at IS NULL) = (cancel_reason IS NULL)
  ),
  CONSTRAINT pre_reservations_cancel_reason_len CHECK (
    cancel_reason IS NULL OR char_length(btrim(cancel_reason)) BETWEEN 1 AND 500
  ),
  CONSTRAINT pre_reservations_verified_consistent CHECK (
    (status = 'verified') = (verified_at IS NOT NULL)
  ),
  CONSTRAINT pre_reservations_first_verified CHECK (
    verified_at IS NULL OR first_verified_at IS NOT NULL
  ),
  CONSTRAINT pre_reservations_override_all_or_none CHECK (
    num_nulls(quote_override_at, quote_override_by, quote_override_reason) IN (0, 3)
  ),
  CONSTRAINT pre_reservations_override_reason_len CHECK (
    quote_override_reason IS NULL OR char_length(btrim(quote_override_reason)) BETWEEN 1 AND 500
  )
);

COMMENT ON TABLE public.pre_reservations IS
  'Operational grouping of services to verify for a customer. Not a confirmed reservation; does not block inventory.';

COMMENT ON COLUMN public.pre_reservations.reference IS
  'Human-readable reference like PRE-00001, per organization sequence.';

COMMENT ON COLUMN public.pre_reservations.expires_at IS
  'Derived: min(hold_expires_at) of main available lines.';

COMMENT ON COLUMN public.pre_reservations.verified_at IS
  'Set to now() when entering verified; NULL outside verified.';

COMMENT ON COLUMN public.pre_reservations.first_verified_at IS
  'First time entering verified; never cleared (SC-002).';

-- ---------------------------------------------------------------------------
-- Trigger: prevent identity change on pre_reservations
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.pre_reservations_prevent_identity_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.request_id IS DISTINCT FROM OLD.request_id
     OR NEW.customer_id IS DISTINCT FROM OLD.customer_id
     OR NEW.reference IS DISTINCT FROM OLD.reference
     OR NEW.responsible_agent_id IS DISTINCT FROM OLD.responsible_agent_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.pre_reservations_prevent_identity_change() IS
  'Rejects changes to request_id, customer_id, reference, responsible_agent_id, created_at.';

REVOKE ALL ON FUNCTION public.pre_reservations_prevent_identity_change() FROM PUBLIC;

CREATE TRIGGER pre_reservations_prevent_identity_change
  BEFORE UPDATE ON public.pre_reservations
  FOR EACH ROW
  EXECUTE FUNCTION public.pre_reservations_prevent_identity_change();

-- ---------------------------------------------------------------------------
-- Trigger: set_updated_at on pre_reservations
-- ---------------------------------------------------------------------------

CREATE TRIGGER pre_reservations_set_updated_at
  BEFORE UPDATE ON public.pre_reservations
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes on pre_reservations
-- ---------------------------------------------------------------------------

CREATE INDEX pre_reservations_org_status_created_idx
  ON public.pre_reservations (organization_id, status, created_at DESC);

CREATE INDEX pre_reservations_request_created_idx
  ON public.pre_reservations (request_id, created_at);

CREATE INDEX pre_reservations_org_responsible_created_idx
  ON public.pre_reservations (organization_id, responsible_agent_id, created_at DESC);

CREATE INDEX pre_reservations_org_assigned_idx
  ON public.pre_reservations (organization_id, assigned_operator_id);

-- ---------------------------------------------------------------------------
-- 2. pre_reservation_items
-- ---------------------------------------------------------------------------

CREATE TABLE public.pre_reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  pre_reservation_id uuid NOT NULL,
  position smallint NOT NULL,
  alternative_of_item_id uuid,
  item_kind text NOT NULL,
  product_id uuid,
  addon_id uuid,
  source_request_item_id uuid,
  item_label text NOT NULL,
  start_date date NOT NULL,
  end_date date,
  adults smallint NOT NULL DEFAULT 1,
  children smallint NOT NULL DEFAULT 0,
  quantity smallint NOT NULL DEFAULT 1,
  provider_id uuid,
  provider_name text,
  provider_phone text,
  provider_email text,
  verification_status public.availability_status NOT NULL DEFAULT 'pending',
  verification_started_at timestamptz,
  verified_by uuid,
  verified_at timestamptz,
  provider_contact_person text,
  contact_method public.provider_contact_method,
  hold_expires_at timestamptz,
  alternative_suggestion text,
  operator_notes text,
  withdrawn_at timestamptz,
  withdrawn_reason text,
  withdrawn_by uuid,
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pre_reservation_items_org_fkey FOREIGN KEY (organization_id)
    REFERENCES public.organizations (id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservation_items_pre_reservation_fkey FOREIGN KEY (pre_reservation_id, organization_id)
    REFERENCES public.pre_reservations (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservation_items_alternative_fkey FOREIGN KEY (alternative_of_item_id, organization_id)
    REFERENCES public.pre_reservation_items (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservation_items_product_fkey FOREIGN KEY (product_id, organization_id)
    REFERENCES public.products (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservation_items_addon_fkey FOREIGN KEY (addon_id, organization_id)
    REFERENCES public.add_ons (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservation_items_source_request_fkey FOREIGN KEY (source_request_item_id)
    REFERENCES public.customer_request_items (id) ON DELETE SET NULL,
  CONSTRAINT pre_reservation_items_verified_by_fkey FOREIGN KEY (verified_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservation_items_withdrawn_by_fkey FOREIGN KEY (withdrawn_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservation_items_provider_fkey FOREIGN KEY (provider_id, organization_id)
    REFERENCES public.providers (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT pre_reservation_items_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT pre_reservation_items_position_key UNIQUE (pre_reservation_id, position),
  CONSTRAINT pre_reservation_items_target CHECK (num_nonnulls(product_id, addon_id) = 1),
  CONSTRAINT pre_reservation_items_kind CHECK (
    item_kind IN ('experience','accommodation','package','addon')
    AND (item_kind = 'addon') = (addon_id IS NOT NULL)
  ),
  CONSTRAINT pre_reservation_items_date_range CHECK (end_date IS NULL OR end_date >= start_date),
  CONSTRAINT pre_reservation_items_nights CHECK (
    item_kind <> 'accommodation' OR (end_date IS NOT NULL AND end_date > start_date)
  ),
  CONSTRAINT pre_reservation_items_pax CHECK (
    adults BETWEEN 1 AND 99
    AND children BETWEEN 0 AND 99
    AND quantity BETWEEN 1 AND 99
  ),
  CONSTRAINT pre_reservation_items_not_self_alternative CHECK (
    alternative_of_item_id IS NULL OR alternative_of_item_id <> id
  ),
  CONSTRAINT pre_reservation_items_outcome_complete CHECK (
    verification_status = 'pending'
    OR (verified_at IS NOT NULL AND verified_by IS NOT NULL
        AND provider_contact_person IS NOT NULL AND contact_method IS NOT NULL)
  ),
  CONSTRAINT pre_reservation_items_hold_only_available CHECK (
    hold_expires_at IS NULL OR verification_status = 'available'
  ),
  CONSTRAINT pre_reservation_items_alternative_text CHECK (
    verification_status <> 'alternative_suggested' OR alternative_suggestion IS NOT NULL
  ),
  CONSTRAINT pre_reservation_items_withdrawn_consistent CHECK (
    num_nulls(withdrawn_at, withdrawn_reason, withdrawn_by) IN (0, 3)
  ),
  CONSTRAINT pre_reservation_items_provider_name_len CHECK (
    provider_name IS NULL OR char_length(provider_name) <= 255
  ),
  CONSTRAINT pre_reservation_items_provider_phone_len CHECK (
    provider_phone IS NULL OR char_length(provider_phone) <= 40
  ),
  CONSTRAINT pre_reservation_items_provider_email_len CHECK (
    provider_email IS NULL OR char_length(provider_email) <= 254
  ),
  CONSTRAINT pre_reservation_items_item_label_len CHECK (
    char_length(item_label) <= 255
  ),
  CONSTRAINT pre_reservation_items_provider_contact_person_len CHECK (
    provider_contact_person IS NULL OR char_length(provider_contact_person) <= 120
  ),
  CONSTRAINT pre_reservation_items_alternative_suggestion_len CHECK (
    alternative_suggestion IS NULL OR char_length(alternative_suggestion) <= 1000
  ),
  CONSTRAINT pre_reservation_items_operator_notes_len CHECK (
    operator_notes IS NULL OR char_length(operator_notes) <= 2000
  ),
  CONSTRAINT pre_reservation_items_withdrawn_reason_len CHECK (
    withdrawn_reason IS NULL OR char_length(btrim(withdrawn_reason)) BETWEEN 1 AND 500
  )
);

COMMENT ON TABLE public.pre_reservation_items IS
  'Individual service line in a pre-reservation. Immutable dates/product/passengers; adjustments via withdraw + add.';

COMMENT ON COLUMN public.pre_reservation_items.position IS
  '0-based order of insertion within the pre-reservation.';

COMMENT ON COLUMN public.pre_reservation_items.alternative_of_item_id IS
  'NULL for main lines; points to a main line of the same pre-reservation for alternatives.';

COMMENT ON COLUMN public.pre_reservation_items.item_kind IS
  'experience | accommodation | package | addon. Matches product/addon type.';

COMMENT ON COLUMN public.pre_reservation_items.item_label IS
  'Snapshot of product/addon name at creation time (<= 255).';

COMMENT ON COLUMN public.pre_reservation_items.hold_expires_at IS
  'Provider hold expiry; only allowed when verification_status = available.';

COMMENT ON COLUMN public.pre_reservation_items.provider_contact_person IS
  'Who the operator spoke with at the provider (1–120 chars).';

COMMENT ON COLUMN public.pre_reservation_items.operator_notes IS
  'Free-form notes from the operator (<= 2000 chars).';

-- ---------------------------------------------------------------------------
-- Trigger: prevent identity change on pre_reservation_items
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.pre_reservation_items_prevent_identity_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.pre_reservation_id IS DISTINCT FROM OLD.pre_reservation_id
     OR NEW.position IS DISTINCT FROM OLD.position
     OR NEW.item_kind IS DISTINCT FROM OLD.item_kind
     OR NEW.product_id IS DISTINCT FROM OLD.product_id
     OR NEW.addon_id IS DISTINCT FROM OLD.addon_id
     OR NEW.start_date IS DISTINCT FROM OLD.start_date
     OR NEW.end_date IS DISTINCT FROM OLD.end_date
     OR NEW.adults IS DISTINCT FROM OLD.adults
     OR NEW.children IS DISTINCT FROM OLD.children
     OR NEW.quantity IS DISTINCT FROM OLD.quantity
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.pre_reservation_items_prevent_identity_change() IS
  'Rejects changes to pre_reservation_id, position, item_kind, product_id, addon_id, start_date, end_date, adults, children, quantity, created_at.';

REVOKE ALL ON FUNCTION public.pre_reservation_items_prevent_identity_change() FROM PUBLIC;

CREATE TRIGGER pre_reservation_items_prevent_identity_change
  BEFORE UPDATE ON public.pre_reservation_items
  FOR EACH ROW
  EXECUTE FUNCTION public.pre_reservation_items_prevent_identity_change();

-- ---------------------------------------------------------------------------
-- Trigger: set_updated_at on pre_reservation_items
-- ---------------------------------------------------------------------------

CREATE TRIGGER pre_reservation_items_set_updated_at
  BEFORE UPDATE ON public.pre_reservation_items
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes on pre_reservation_items
-- ---------------------------------------------------------------------------

CREATE INDEX pre_reservation_items_org_status_start_idx
  ON public.pre_reservation_items (organization_id, verification_status, start_date)
  WHERE withdrawn_at IS NULL;

CREATE INDEX pre_reservation_items_org_provider_start_idx
  ON public.pre_reservation_items (organization_id, provider_id, start_date)
  WHERE withdrawn_at IS NULL;

CREATE INDEX pre_reservation_items_org_hold_idx
  ON public.pre_reservation_items (organization_id, hold_expires_at)
  WHERE verification_status = 'available' AND withdrawn_at IS NULL;

CREATE INDEX pre_reservation_items_alternative_idx
  ON public.pre_reservation_items (alternative_of_item_id);

-- ---------------------------------------------------------------------------
-- 3. availability_verification_events (append-only)
-- ---------------------------------------------------------------------------

CREATE TABLE public.availability_verification_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  pre_reservation_id uuid NOT NULL,
  item_id uuid,
  event_kind public.availability_event_kind NOT NULL,
  from_status public.availability_status,
  to_status public.availability_status,
  provider_contact_person text,
  contact_method public.provider_contact_method,
  hold_expires_at timestamptz,
  notes text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT availability_verification_events_pre_reservation_fkey FOREIGN KEY (pre_reservation_id, organization_id)
    REFERENCES public.pre_reservations (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT availability_verification_events_item_fkey FOREIGN KEY (item_id, organization_id)
    REFERENCES public.pre_reservation_items (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT availability_verification_events_actor_fkey FOREIGN KEY (actor_id, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT availability_verification_events_item_or_global CHECK (
    item_id IS NOT NULL
    OR event_kind IN ('pre_reservation_cancelled', 'quote_override_authorized')
  ),
  CONSTRAINT availability_verification_events_provider_contact_person_len CHECK (
    provider_contact_person IS NULL OR char_length(provider_contact_person) <= 120
  ),
  CONSTRAINT availability_verification_events_notes_len CHECK (
    notes IS NULL OR char_length(notes) <= 2000
  )
);

COMMENT ON TABLE public.availability_verification_events IS
  'Immutable history of every verification action. Contains provider contact data; never traveler PII.';

COMMENT ON COLUMN public.availability_verification_events.metadata IS
  'Structured extras, e.g., {override_cleared: true} or {replaced_item_id: "uuid"}.';

-- ---------------------------------------------------------------------------
-- Triggers: reject mutations on availability_verification_events (reuse function from 033)
-- ---------------------------------------------------------------------------

CREATE TRIGGER availability_verification_events_reject_mutation
  BEFORE UPDATE OR DELETE ON public.availability_verification_events
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_request_note_mutation();

CREATE TRIGGER availability_verification_events_reject_truncate
  BEFORE TRUNCATE ON public.availability_verification_events
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.reject_request_note_mutation();

-- ---------------------------------------------------------------------------
-- Indexes on availability_verification_events
-- ---------------------------------------------------------------------------

CREATE INDEX availability_verification_events_pre_reservation_created_idx
  ON public.availability_verification_events (pre_reservation_id, created_at);

CREATE INDEX availability_verification_events_item_created_idx
  ON public.availability_verification_events (item_id, created_at);

-- ---------------------------------------------------------------------------
-- RLS on all three tables
-- ---------------------------------------------------------------------------

ALTER TABLE public.pre_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pre_reservation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.availability_verification_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.pre_reservations FROM anon;
REVOKE ALL ON public.pre_reservation_items FROM anon;
REVOKE ALL ON public.availability_verification_events FROM anon;

REVOKE INSERT, UPDATE, DELETE ON public.pre_reservations FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.pre_reservation_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.availability_verification_events FROM authenticated;

CREATE POLICY tenant_isolation_select ON public.pre_reservations
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.pre_reservation_items
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.availability_verification_events
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- ---------------------------------------------------------------------------
-- 4. Views (security_invoker)
-- ---------------------------------------------------------------------------

-- pre_reservation_list
CREATE VIEW public.pre_reservation_list WITH (security_invoker = true) AS
SELECT
  pr.id,
  pr.organization_id,
  pr.reference,
  pr.status,
  pr.request_id,
  cr.reference AS request_reference,
  pr.customer_id,
  c.first_name AS customer_first_name,
  c.last_name AS customer_last_name,
  c.is_anonymized AS customer_is_anonymized,
  pr.responsible_agent_id,
  ra.full_name AS responsible_agent_name,
  pr.assigned_operator_id,
  oa.full_name AS assigned_operator_name,
  pr.created_at,
  pr.verified_at,
  pr.first_verified_at,
  pr.expires_at,
  pr.cancelled_at,
  (pr.quote_override_at IS NOT NULL) AS has_quote_override,
  (pr.status = 'verified' OR (pr.quote_override_at IS NOT NULL AND pr.status <> 'cancelled')) AS quote_eligible,
  (
    SELECT min(pri.start_date)
    FROM public.pre_reservation_items pri
    WHERE pri.pre_reservation_id = pr.id
      AND pri.organization_id = pr.organization_id
      AND pri.alternative_of_item_id IS NULL
      AND pri.withdrawn_at IS NULL
  ) AS first_service_date,
  (
    SELECT count(*)
    FROM public.pre_reservation_items pri
    WHERE pri.pre_reservation_id = pr.id
      AND pri.organization_id = pr.organization_id
      AND pri.alternative_of_item_id IS NULL
      AND pri.withdrawn_at IS NULL
  ) AS primary_item_count,
  (
    SELECT count(*)
    FROM public.pre_reservation_items pri
    WHERE pri.pre_reservation_id = pr.id
      AND pri.organization_id = pr.organization_id
      AND pri.alternative_of_item_id IS NULL
      AND pri.withdrawn_at IS NULL
      AND pri.verification_status = 'available'
  ) AS available_item_count
FROM public.pre_reservations pr
JOIN public.customer_requests cr ON cr.id = pr.request_id AND cr.organization_id = pr.organization_id
JOIN public.customers c ON c.id = pr.customer_id AND c.organization_id = pr.organization_id
JOIN public.user_profiles ra ON ra.id = pr.responsible_agent_id AND ra.organization_id = pr.organization_id
LEFT JOIN public.user_profiles oa ON oa.id = pr.assigned_operator_id AND oa.organization_id = pr.organization_id;

COMMENT ON VIEW public.pre_reservation_list IS
  'List of pre-reservations with derived fields for the UI. security_invoker enforces RLS.';

-- availability_verification_queue
CREATE VIEW public.availability_verification_queue WITH (security_invoker = true) AS
SELECT
  pri.id AS item_id,
  pri.organization_id,
  pri.pre_reservation_id,
  pr.reference,
  pr.status AS pre_reservation_status,
  (pri.alternative_of_item_id IS NOT NULL) AS is_alternative,
  pri.alternative_of_item_id,
  pri.item_kind,
  pri.item_label,
  pri.start_date,
  pri.end_date,
  pri.adults,
  pri.children,
  pri.quantity,
  pri.provider_id,
  pri.provider_name,
  pri.provider_phone,
  pri.provider_email,
  pri.verification_status,
  pri.verification_started_at,
  pri.verified_at,
  pv.full_name AS verified_by_name,
  pri.provider_contact_person,
  pri.hold_expires_at,
  (pri.verification_status = 'available' AND pri.hold_expires_at <= now()) AS hold_expired,
  (pri.verification_status = 'pending' OR (pri.verification_status = 'available' AND pri.hold_expires_at <= now())) AS needs_action,
  pr.assigned_operator_id,
  po.full_name AS assigned_operator_name,
  c.first_name AS customer_first_name,
  c.last_name AS customer_last_name,
  c.is_anonymized AS customer_is_anonymized,
  pri.created_at AS item_created_at
FROM public.pre_reservation_items pri
JOIN public.pre_reservations pr ON pr.id = pri.pre_reservation_id AND pr.organization_id = pri.organization_id
JOIN public.customers c ON c.id = pr.customer_id AND c.organization_id = pr.organization_id
LEFT JOIN public.user_profiles pv ON pv.id = pri.verified_by AND pv.organization_id = pri.organization_id
LEFT JOIN public.user_profiles po ON po.id = pr.assigned_operator_id AND po.organization_id = pr.organization_id
WHERE pri.withdrawn_at IS NULL
  AND pr.status <> 'cancelled';

COMMENT ON VIEW public.availability_verification_queue IS
  'Queue of active lines needing verification action. One row per non-withdrawn line of non-cancelled pre-reservations. security_invoker enforces RLS.';

-- ---------------------------------------------------------------------------
-- Grants on views
-- ---------------------------------------------------------------------------

REVOKE ALL ON public.pre_reservation_list FROM anon;
REVOKE ALL ON public.availability_verification_queue FROM anon;

GRANT SELECT ON public.pre_reservation_list TO authenticated;
GRANT SELECT ON public.availability_verification_queue TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Realtime: add pre_reservations to supabase_realtime publication if it exists
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pre_reservations;
  END IF;
END $$;