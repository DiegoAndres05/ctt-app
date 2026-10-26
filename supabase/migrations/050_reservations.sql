-- 050_reservations.sql
-- Tables, RLS, view and freeze trigger for reservations.
-- Source of truth: specs/006-reservation-lifecycle/data-model.md.

CREATE TABLE public.reservation_families (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  reference text NOT NULL,
  quotation_version_id uuid NOT NULL,
  quotation_family_id uuid NOT NULL,
  pre_reservation_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  voucher_token_hash text,
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reservation_families_quotation_version_fkey
    FOREIGN KEY (quotation_version_id, organization_id)
    REFERENCES public.quotation_versions (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_families_quotation_family_fkey
    FOREIGN KEY (quotation_family_id, organization_id)
    REFERENCES public.quotation_families (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_families_pre_reservation_fkey
    FOREIGN KEY (pre_reservation_id, organization_id)
    REFERENCES public.pre_reservations (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_families_customer_fkey
    FOREIGN KEY (customer_id, organization_id)
    REFERENCES public.customers (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_families_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT reservation_families_quotation_version_key UNIQUE (quotation_version_id),
  CONSTRAINT reservation_families_reference_format CHECK (reference ~ '^RSV-[0-9]{5}$')
);

CREATE UNIQUE INDEX reservation_families_reference_key
  ON public.reservation_families (organization_id, reference);

CREATE UNIQUE INDEX reservation_families_token_hash_key
  ON public.reservation_families (voucher_token_hash)
  WHERE voucher_token_hash IS NOT NULL;

CREATE TABLE public.reservation_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  family_id uuid NOT NULL,
  version_number smallint NOT NULL,
  status public.reservation_status NOT NULL DEFAULT 'confirmed',
  currency char(3) NOT NULL,
  total numeric(14, 2) NOT NULL,
  travel_start_date date NOT NULL,
  travel_end_date date,
  party_adults smallint NOT NULL,
  party_children smallint NOT NULL DEFAULT 0,
  terms text NOT NULL DEFAULT '',
  assistance_phones text NOT NULL DEFAULT '',
  contingency_report text,
  cancelled_at timestamptz,
  cancel_reason text,
  cancelled_by uuid,
  status_changed_at timestamptz,
  status_changed_by uuid,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reservation_versions_family_fkey
    FOREIGN KEY (family_id, organization_id)
    REFERENCES public.reservation_families (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_versions_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT reservation_versions_family_version_key UNIQUE (family_id, version_number),
  CONSTRAINT reservation_versions_version_positive CHECK (version_number >= 1),
  CONSTRAINT reservation_versions_currency_iso CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT reservation_versions_total_non_negative CHECK (total >= 0),
  CONSTRAINT reservation_versions_party CHECK (
    party_adults >= 0 AND party_children >= 0
  ),
  CONSTRAINT reservation_versions_terms_len CHECK (char_length(terms) <= 8000),
  CONSTRAINT reservation_versions_phones_len CHECK (char_length(assistance_phones) <= 200),
  CONSTRAINT reservation_versions_cancel_reason_len CHECK (
    cancel_reason IS NULL OR char_length(btrim(cancel_reason)) BETWEEN 1 AND 500
  ),
  CONSTRAINT reservation_versions_contingency_len CHECK (
    contingency_report IS NULL OR char_length(btrim(contingency_report)) BETWEEN 1 AND 2000
  ),
  CONSTRAINT reservation_versions_cancel_consistent CHECK (
    (status = 'cancelled') = (cancelled_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX reservation_versions_open_family_idx
  ON public.reservation_versions (family_id)
  WHERE status <> 'superseded'::public.reservation_status;

CREATE TABLE public.reservation_passengers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  version_id uuid NOT NULL,
  position smallint NOT NULL,
  first_name text NOT NULL,
  last_name text NOT NULL,
  document_type public.id_document_type NOT NULL,
  document_number text NOT NULL,
  date_of_birth date,
  special_requirements text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reservation_passengers_version_fkey
    FOREIGN KEY (version_id, organization_id)
    REFERENCES public.reservation_versions (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_passengers_position_key UNIQUE (version_id, position),
  CONSTRAINT reservation_passengers_name_len CHECK (
    char_length(btrim(first_name)) BETWEEN 1 AND 120
    AND char_length(btrim(last_name)) BETWEEN 1 AND 120
  ),
  CONSTRAINT reservation_passengers_document_len CHECK (
    char_length(btrim(document_number)) BETWEEN 1 AND 40
  ),
  CONSTRAINT reservation_passengers_req_len CHECK (
    special_requirements IS NULL OR char_length(special_requirements) <= 500
  )
);

CREATE TABLE public.reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  version_id uuid NOT NULL,
  quotation_line_ref uuid,
  pre_reservation_item_id uuid,
  position smallint NOT NULL,
  item_kind text NOT NULL,
  item_label text NOT NULL,
  product_id uuid,
  addon_id uuid,
  start_date date NOT NULL,
  end_date date,
  adults smallint NOT NULL,
  children smallint NOT NULL DEFAULT 0,
  quantity smallint NOT NULL DEFAULT 1,
  line_total numeric(14, 2) NOT NULL DEFAULT 0,
  provider_id uuid,
  ops_status public.reservation_item_ops_status NOT NULL DEFAULT 'pending_provider',
  provider_notified_at timestamptz,
  provider_notify_channel public.provider_notify_channel,
  reassign_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reservation_items_version_fkey
    FOREIGN KEY (version_id, organization_id)
    REFERENCES public.reservation_versions (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_items_provider_fkey
    FOREIGN KEY (provider_id, organization_id)
    REFERENCES public.providers (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_items_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT reservation_items_position_key UNIQUE (version_id, position),
  CONSTRAINT reservation_items_kind CHECK (
    item_kind IN ('experience', 'accommodation', 'package', 'addon')
  ),
  CONSTRAINT reservation_items_label_len CHECK (char_length(item_label) <= 255),
  CONSTRAINT reservation_items_reassign_len CHECK (
    reassign_reason IS NULL OR char_length(btrim(reassign_reason)) BETWEEN 1 AND 500
  )
);

CREATE TABLE public.reservation_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  family_id uuid NOT NULL,
  amount numeric(14, 2) NOT NULL,
  currency char(3) NOT NULL,
  paid_on date NOT NULL,
  method public.payment_method NOT NULL,
  transfer_reference text NOT NULL,
  receipt_path text,
  recorded_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reservation_payments_family_fkey
    FOREIGN KEY (family_id, organization_id)
    REFERENCES public.reservation_families (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT reservation_payments_amount_positive CHECK (amount > 0),
  CONSTRAINT reservation_payments_currency_iso CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT reservation_payments_ref_len CHECK (
    char_length(btrim(transfer_reference)) BETWEEN 1 AND 80
  )
);

CREATE TRIGGER reservation_payments_no_update
  BEFORE UPDATE OR DELETE ON public.reservation_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_request_note_mutation();

CREATE OR REPLACE FUNCTION public.reservation_versions_freeze()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF OLD.status IN (
       'completed'::public.reservation_status,
       'cancelled'::public.reservation_status,
       'superseded'::public.reservation_status
     )
     AND (
       NEW.total IS DISTINCT FROM OLD.total
       OR NEW.currency IS DISTINCT FROM OLD.currency
       OR NEW.travel_start_date IS DISTINCT FROM OLD.travel_start_date
       OR NEW.travel_end_date IS DISTINCT FROM OLD.travel_end_date
       OR NEW.party_adults IS DISTINCT FROM OLD.party_adults
       OR NEW.party_children IS DISTINCT FROM OLD.party_children
       OR NEW.terms IS DISTINCT FROM OLD.terms
     )
  THEN
    RAISE EXCEPTION 'RESERVATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.reservation_versions_freeze() FROM PUBLIC;

CREATE TRIGGER reservation_versions_freeze
  BEFORE UPDATE ON public.reservation_versions
  FOR EACH ROW
  EXECUTE FUNCTION public.reservation_versions_freeze();

ALTER TABLE public.reservation_families ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservation_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservation_passengers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservation_payments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.reservation_families FROM anon;
REVOKE ALL ON public.reservation_versions FROM anon;
REVOKE ALL ON public.reservation_passengers FROM anon;
REVOKE ALL ON public.reservation_items FROM anon;
REVOKE ALL ON public.reservation_payments FROM anon;

REVOKE INSERT, UPDATE, DELETE ON public.reservation_families FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.reservation_versions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.reservation_passengers FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.reservation_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.reservation_payments FROM authenticated;

GRANT SELECT ON public.reservation_families TO authenticated;
GRANT SELECT ON public.reservation_versions TO authenticated;
GRANT SELECT ON public.reservation_passengers TO authenticated;
GRANT SELECT ON public.reservation_items TO authenticated;
GRANT SELECT ON public.reservation_payments TO authenticated;

CREATE POLICY tenant_isolation_select ON public.reservation_families
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.reservation_versions
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.reservation_passengers
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.reservation_items
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.reservation_payments
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE VIEW public.reservation_list WITH (security_invoker = true) AS
SELECT
  v.id AS version_id,
  f.id AS family_id,
  v.organization_id,
  f.reference,
  v.version_number,
  v.status,
  f.customer_id,
  c.first_name AS customer_first_name,
  c.last_name AS customer_last_name,
  c.is_anonymized AS customer_is_anonymized,
  f.quotation_version_id,
  qf.reference AS quotation_reference,
  v.currency,
  v.total,
  coalesce((
    SELECT sum(p.amount)
    FROM public.reservation_payments p
    WHERE p.family_id = f.id AND p.organization_id = f.organization_id
  ), 0)::numeric(14, 2) AS paid_total,
  (v.total - coalesce((
    SELECT sum(p.amount)
    FROM public.reservation_payments p
    WHERE p.family_id = f.id AND p.organization_id = f.organization_id
  ), 0))::numeric(14, 2) AS balance,
  v.travel_start_date,
  v.travel_end_date,
  v.created_at,
  v.created_by
FROM public.reservation_versions v
JOIN public.reservation_families f
  ON f.id = v.family_id AND f.organization_id = v.organization_id
JOIN public.customers c
  ON c.id = f.customer_id AND c.organization_id = v.organization_id
JOIN public.quotation_families qf
  ON qf.id = f.quotation_family_id AND qf.organization_id = v.organization_id
WHERE v.status <> 'superseded'::public.reservation_status;

COMMENT ON VIEW public.reservation_list IS
  'Current reservation version per family. security_invoker. No email, phone, token or documents.';

REVOKE ALL ON public.reservation_list FROM anon;
GRANT SELECT ON public.reservation_list TO authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'reservation-receipts',
  'reservation-receipts',
  false,
  10485760,
  ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types,
  updated_at = now();
