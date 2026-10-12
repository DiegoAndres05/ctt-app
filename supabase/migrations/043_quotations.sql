-- 043_quotations.sql
-- Core tables, triggers, RLS and the list view for quotations.
-- Source of truth: specs/005-quotation-proposals/data-model.md (§1-§6, §RLS, §View),
-- specs/005-quotation-proposals/research.md (R-005, R-007, R-012).
--
-- Creates tables: quotation_families, quotation_versions, quotation_lines,
--                quotation_adjustments, quotation_responses, quotation_defaults
-- Creates view:   quotation_list (security_invoker)
-- Money is never edited here; the pricing core in 044 writes the amounts.

-- ---------------------------------------------------------------------------
-- 1. quotation_families
-- ---------------------------------------------------------------------------

CREATE TABLE public.quotation_families (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  pre_reservation_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  reference text,
  public_token_hash text,
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quotation_families_pre_reservation_fkey FOREIGN KEY (pre_reservation_id, organization_id)
    REFERENCES public.pre_reservations (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT quotation_families_customer_fkey FOREIGN KEY (customer_id, organization_id)
    REFERENCES public.customers (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT quotation_families_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT quotation_families_reference_format CHECK (
    reference IS NULL OR reference ~ '^COT-[0-9]{5}$'
  )
);

COMMENT ON TABLE public.quotation_families IS
  'Groups every version of one proposal: reference, public token hash and the source pre-reservation. Not a version itself.';
COMMENT ON COLUMN public.quotation_families.reference IS
  'Human-readable reference like COT-00001, assigned when version 1 is issued; later versions reuse it.';
COMMENT ON COLUMN public.quotation_families.public_token_hash IS
  'SHA-256 hex of the public link token. NULL until issued; the clear token is never stored.';

-- One reference and one token hash per tenant; both are assigned at issue time.
CREATE UNIQUE INDEX quotation_families_reference_key
  ON public.quotation_families (organization_id, reference)
  WHERE reference IS NOT NULL;

CREATE UNIQUE INDEX quotation_families_token_hash_key
  ON public.quotation_families (public_token_hash)
  WHERE public_token_hash IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Trigger: quotation_families_prevent_identity_change
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_families_prevent_identity_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.pre_reservation_id IS DISTINCT FROM OLD.pre_reservation_id
     OR NEW.customer_id IS DISTINCT FROM OLD.customer_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  -- reference and public_token_hash only ever go from NULL to a value.
  IF NEW.reference IS DISTINCT FROM OLD.reference
     AND NOT (OLD.reference IS NULL AND NEW.reference IS NOT NULL)
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.public_token_hash IS DISTINCT FROM OLD.public_token_hash
     AND NOT (OLD.public_token_hash IS NULL AND NEW.public_token_hash IS NOT NULL)
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.quotation_families_prevent_identity_change() IS
  'Rejects changes to pre_reservation_id, customer_id, created_at; reference and public_token_hash only go from NULL to a value.';

REVOKE ALL ON FUNCTION public.quotation_families_prevent_identity_change() FROM PUBLIC;

CREATE TRIGGER quotation_families_prevent_identity_change
  BEFORE UPDATE ON public.quotation_families
  FOR EACH ROW
  EXECUTE FUNCTION public.quotation_families_prevent_identity_change();

-- ---------------------------------------------------------------------------
-- 2. quotation_versions
-- ---------------------------------------------------------------------------

CREATE TABLE public.quotation_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  family_id uuid NOT NULL,
  version_number smallint NOT NULL,
  status public.quotation_status NOT NULL DEFAULT 'draft',
  currency char(3) NOT NULL,
  subtotal numeric(14, 2) NOT NULL DEFAULT 0,
  tax_total numeric(14, 2) NOT NULL DEFAULT 0,
  adjustment_total numeric(14, 2) NOT NULL DEFAULT 0,
  total numeric(14, 2) NOT NULL DEFAULT 0,
  exchange_rates jsonb NOT NULL DEFAULT '{}'::jsonb,
  party_adults smallint NOT NULL DEFAULT 1,
  party_children smallint NOT NULL DEFAULT 0,
  inclusions text NOT NULL DEFAULT '',
  exclusions text NOT NULL DEFAULT '',
  terms text NOT NULL DEFAULT '',
  commercial_notes text,
  valid_until timestamptz,
  issued_at timestamptz,
  issued_by uuid,
  accepted_at timestamptz,
  rejected_at timestamptz,
  expired_at timestamptz,
  voided_at timestamptz,
  voided_by uuid,
  void_reason text,
  superseded_at timestamptz,
  pre_reservation_fingerprint jsonb,
  response_origin public.quotation_response_origin,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quotation_versions_family_fkey FOREIGN KEY (family_id, organization_id)
    REFERENCES public.quotation_families (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT quotation_versions_issued_by_fkey FOREIGN KEY (issued_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE SET NULL,
  CONSTRAINT quotation_versions_voided_by_fkey FOREIGN KEY (voided_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE SET NULL,
  CONSTRAINT quotation_versions_created_by_fkey FOREIGN KEY (created_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE SET NULL,
  CONSTRAINT quotation_versions_id_organization_id_key UNIQUE (id, organization_id),
  CONSTRAINT quotation_versions_family_version_key UNIQUE (family_id, version_number),
  CONSTRAINT quotation_versions_version_number_positive CHECK (version_number >= 1),
  CONSTRAINT quotation_versions_currency_iso4217 CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT quotation_versions_total_non_negative CHECK (total >= 0),
  CONSTRAINT quotation_versions_party_non_negative CHECK (
    party_adults >= 0 AND party_children >= 0
  ),
  CONSTRAINT quotation_versions_issued_consistent CHECK (
    status <> 'issued'
    OR (issued_at IS NOT NULL AND valid_until IS NOT NULL
        AND pre_reservation_fingerprint IS NOT NULL)
  ),
  CONSTRAINT quotation_versions_voided_consistent CHECK (
    status <> 'voided' OR void_reason IS NOT NULL
  ),
  CONSTRAINT quotation_versions_void_reason_len CHECK (
    void_reason IS NULL OR char_length(btrim(void_reason)) BETWEEN 1 AND 500
  ),
  CONSTRAINT quotation_versions_superseded_consistent CHECK (
    status <> 'superseded' OR superseded_at IS NOT NULL
  ),
  CONSTRAINT quotation_versions_inclusions_len CHECK (char_length(inclusions) <= 4000),
  CONSTRAINT quotation_versions_exclusions_len CHECK (char_length(exclusions) <= 4000),
  CONSTRAINT quotation_versions_terms_len CHECK (char_length(terms) <= 8000),
  CONSTRAINT quotation_versions_commercial_notes_len CHECK (
    commercial_notes IS NULL OR char_length(commercial_notes) <= 2000
  ),
  CONSTRAINT quotation_versions_response_origin_consistent CHECK (
    response_origin IS NULL
    OR status IN ('accepted', 'rejected', 'superseded', 'voided')
  )
);

COMMENT ON TABLE public.quotation_versions IS
  'One version of a commercial proposal. Outside draft a trigger freezes money, texts, exchange_rates and valid_until (QUOTATION_FROZEN).';
COMMENT ON COLUMN public.quotation_versions.exchange_rates IS
  'Map of { "USD": 4100.00 } rates used while drafting; frozen as-is when issued.';
COMMENT ON COLUMN public.quotation_versions.pre_reservation_fingerprint IS
  'JSON snapshot of the main pre-reservation lines, filled when issued and compared on acceptance.';
COMMENT ON COLUMN public.quotation_versions.commercial_notes IS
  'Internal notes for the panel; never shown to the client and never part of the public view.';

-- One open (draft/issued) version and one accepted version per family.
CREATE UNIQUE INDEX quotation_versions_open_family_idx
  ON public.quotation_versions (family_id)
  WHERE status IN ('draft', 'issued');

CREATE UNIQUE INDEX quotation_versions_accepted_family_idx
  ON public.quotation_versions (family_id)
  WHERE status = 'accepted';

CREATE INDEX quotation_versions_org_status_created_idx
  ON public.quotation_versions (organization_id, status, created_at DESC);

CREATE INDEX quotation_versions_family_idx
  ON public.quotation_versions (family_id);

-- ---------------------------------------------------------------------------
-- Triggers: identity and QUOTATION_FROZEN on quotation_versions
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_versions_prevent_identity_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.family_id IS DISTINCT FROM OLD.family_id
     OR NEW.version_number IS DISTINCT FROM OLD.version_number
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.quotation_versions_prevent_identity_change() IS
  'Rejects changes to organization_id, family_id, version_number, created_at.';

REVOKE ALL ON FUNCTION public.quotation_versions_prevent_identity_change() FROM PUBLIC;

CREATE TRIGGER quotation_versions_prevent_identity_change
  BEFORE UPDATE ON public.quotation_versions
  FOR EACH ROW
  EXECUTE FUNCTION public.quotation_versions_prevent_identity_change();

CREATE OR REPLACE FUNCTION public.quotation_versions_freeze()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF OLD.status <> 'draft'::public.quotation_status AND (
       NEW.subtotal IS DISTINCT FROM OLD.subtotal
    OR NEW.tax_total IS DISTINCT FROM OLD.tax_total
    OR NEW.adjustment_total IS DISTINCT FROM OLD.adjustment_total
    OR NEW.total IS DISTINCT FROM OLD.total
    OR NEW.currency IS DISTINCT FROM OLD.currency
    OR NEW.exchange_rates IS DISTINCT FROM OLD.exchange_rates
    OR NEW.inclusions IS DISTINCT FROM OLD.inclusions
    OR NEW.exclusions IS DISTINCT FROM OLD.exclusions
    OR NEW.terms IS DISTINCT FROM OLD.terms
    OR NEW.commercial_notes IS DISTINCT FROM OLD.commercial_notes
    OR NEW.valid_until IS DISTINCT FROM OLD.valid_until
  ) THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.quotation_versions_freeze() IS
  'Outside draft, rejects changes to amounts, currency, commercial texts, exchange_rates and valid_until with QUOTATION_FROZEN.';

REVOKE ALL ON FUNCTION public.quotation_versions_freeze() FROM PUBLIC;

CREATE TRIGGER quotation_versions_freeze
  BEFORE UPDATE ON public.quotation_versions
  FOR EACH ROW
  EXECUTE FUNCTION public.quotation_versions_freeze();

CREATE TRIGGER quotation_versions_set_updated_at
  BEFORE UPDATE ON public.quotation_versions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. quotation_lines
-- ---------------------------------------------------------------------------

CREATE TABLE public.quotation_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  version_id uuid NOT NULL,
  pre_reservation_item_id uuid NOT NULL,
  position smallint NOT NULL,
  item_kind text NOT NULL,
  item_label text NOT NULL,
  product_id uuid,
  addon_id uuid,
  start_date date NOT NULL,
  end_date date,
  adults smallint NOT NULL,
  children smallint NOT NULL,
  quantity smallint NOT NULL,
  charge_type public.charge_type NOT NULL,
  charge_basis numeric(12, 2) NOT NULL,
  tariff_currency char(3) NOT NULL,
  tariff_amount numeric(12, 2) NOT NULL,
  exchange_rate numeric(14, 6),
  unit_price numeric(14, 2) NOT NULL,
  tax_rate numeric(5, 2) NOT NULL DEFAULT 0,
  line_base numeric(14, 2) NOT NULL,
  line_adjustment numeric(14, 2) NOT NULL,
  line_tax numeric(14, 2) NOT NULL,
  line_total numeric(14, 2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quotation_lines_version_fkey FOREIGN KEY (version_id, organization_id)
    REFERENCES public.quotation_versions (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT quotation_lines_item_fkey FOREIGN KEY (pre_reservation_item_id, organization_id)
    REFERENCES public.pre_reservation_items (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT quotation_lines_product_fkey FOREIGN KEY (product_id, organization_id)
    REFERENCES public.products (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT quotation_lines_addon_fkey FOREIGN KEY (addon_id, organization_id)
    REFERENCES public.add_ons (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT quotation_lines_version_item_key UNIQUE (version_id, pre_reservation_item_id),
  CONSTRAINT quotation_lines_target CHECK (num_nonnulls(product_id, addon_id) = 1),
  CONSTRAINT quotation_lines_kind CHECK (
    item_kind IN ('experience', 'accommodation', 'package', 'addon')
    AND (item_kind = 'addon') = (addon_id IS NOT NULL)
  ),
  CONSTRAINT quotation_lines_item_label_len CHECK (char_length(item_label) <= 255),
  CONSTRAINT quotation_lines_date_range CHECK (end_date IS NULL OR end_date >= start_date),
  CONSTRAINT quotation_lines_pax CHECK (
    adults BETWEEN 1 AND 99
    AND children BETWEEN 0 AND 99
    AND quantity BETWEEN 1 AND 99
  ),
  CONSTRAINT quotation_lines_charge_basis_positive CHECK (charge_basis > 0),
  CONSTRAINT quotation_lines_tariff_currency_iso4217 CHECK (tariff_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT quotation_lines_tariff_amount_non_negative CHECK (tariff_amount >= 0),
  CONSTRAINT quotation_lines_exchange_rate_positive CHECK (
    exchange_rate IS NULL OR exchange_rate > 0
  ),
  CONSTRAINT quotation_lines_unit_price_non_negative CHECK (unit_price >= 0),
  CONSTRAINT quotation_lines_tax_rate_range CHECK (tax_rate >= 0 AND tax_rate <= 100)
);

COMMENT ON TABLE public.quotation_lines IS
  'Snapshot of one pre-reservation line in a quotation version: tariff, per-line tax and the server-computed amounts.';
COMMENT ON COLUMN public.quotation_lines.charge_basis IS
  'Quantity multiplier: adults+children for per_person, nights x quantity for per_night, quantity for per_group (1 for per_service add-ons).';
COMMENT ON COLUMN public.quotation_lines.exchange_rate IS
  'Units of the quotation currency per unit of tariff_currency; NULL when the tariff already matches the quotation currency.';

-- ---------------------------------------------------------------------------
-- Trigger: lines only change while the version is a draft
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_draft_only_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_status public.quotation_status;
  v_version_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_version_id := OLD.version_id;
  ELSE
    v_version_id := NEW.version_id;
  END IF;

  SELECT v.status INTO v_status
  FROM public.quotation_versions v
  WHERE v.id = v_version_id;

  IF v_status IS DISTINCT FROM 'draft'::public.quotation_status THEN
    RAISE EXCEPTION 'QUOTATION_FROZEN' USING ERRCODE = 'raise_exception';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.quotation_draft_only_guard() IS
  'Rejects INSERT/UPDATE/DELETE on quotation_lines and quotation_adjustments when the parent version is not a draft (QUOTATION_FROZEN).';

REVOKE ALL ON FUNCTION public.quotation_draft_only_guard() FROM PUBLIC;

CREATE TRIGGER quotation_lines_draft_only
  BEFORE INSERT OR UPDATE OR DELETE ON public.quotation_lines
  FOR EACH ROW
  EXECUTE FUNCTION public.quotation_draft_only_guard();

-- ---------------------------------------------------------------------------
-- 4. quotation_adjustments
-- ---------------------------------------------------------------------------

CREATE TABLE public.quotation_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  version_id uuid NOT NULL,
  pre_reservation_item_id uuid,
  label text NOT NULL,
  direction public.quotation_adjustment_direction NOT NULL,
  kind public.quotation_adjustment_kind NOT NULL,
  value numeric(12, 2) NOT NULL,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quotation_adjustments_version_item_fkey
    FOREIGN KEY (version_id, pre_reservation_item_id)
    REFERENCES public.quotation_lines (version_id, pre_reservation_item_id)
    ON DELETE CASCADE,
  CONSTRAINT quotation_adjustments_organization_fkey FOREIGN KEY (organization_id)
    REFERENCES public.organizations (id) ON DELETE RESTRICT,
  CONSTRAINT quotation_adjustments_created_by_fkey FOREIGN KEY (created_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE SET NULL,
  CONSTRAINT quotation_adjustments_version_item_label_key
    UNIQUE (version_id, pre_reservation_item_id, label),
  CONSTRAINT quotation_adjustments_label_len CHECK (
    char_length(btrim(label)) BETWEEN 1 AND 80
  ),
  CONSTRAINT quotation_adjustments_value_positive CHECK (value > 0),
  CONSTRAINT quotation_adjustments_percent_max CHECK (
    kind <> 'percent' OR value <= 100
  )
);

COMMENT ON TABLE public.quotation_adjustments IS
  'Per-line (pre_reservation_item_id set) or global (NULL) commercial adjustment. Label is mandatory in the row and never audited.';

CREATE TRIGGER quotation_adjustments_draft_only
  BEFORE INSERT OR UPDATE OR DELETE ON public.quotation_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION public.quotation_draft_only_guard();

-- ---------------------------------------------------------------------------
-- 5. quotation_responses (append-only)
-- ---------------------------------------------------------------------------

CREATE TABLE public.quotation_responses (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  version_id uuid NOT NULL,
  kind public.quotation_response_kind NOT NULL,
  origin public.quotation_response_origin NOT NULL,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quotation_responses_version_fkey FOREIGN KEY (version_id, organization_id)
    REFERENCES public.quotation_versions (id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT quotation_responses_created_by_fkey FOREIGN KEY (created_by, organization_id)
    REFERENCES public.user_profiles (id, organization_id) ON DELETE SET NULL,
  CONSTRAINT quotation_responses_customer_has_no_actor CHECK (
    created_by IS NULL OR origin = 'agent'
  )
);

COMMENT ON TABLE public.quotation_responses IS
  'Immutable history of client/agent responses. updates, deletes and truncates are rejected for every role.';

CREATE TRIGGER quotation_responses_reject_mutation
  BEFORE UPDATE OR DELETE ON public.quotation_responses
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_request_note_mutation();

CREATE TRIGGER quotation_responses_reject_truncate
  BEFORE TRUNCATE ON public.quotation_responses
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.reject_request_note_mutation();

CREATE INDEX quotation_responses_version_created_idx
  ON public.quotation_responses (version_id, created_at);

-- ---------------------------------------------------------------------------
-- 6. quotation_defaults
-- ---------------------------------------------------------------------------

CREATE TABLE public.quotation_defaults (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations (id) ON DELETE RESTRICT,
  terms_template text NOT NULL,
  created_by uuid REFERENCES public.user_profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quotation_defaults_terms_len CHECK (char_length(terms_template) <= 8000)
);

COMMENT ON TABLE public.quotation_defaults IS
  'One terms template per organization. Without a row, drafts use the fixed default text from research R-009.';

CREATE TRIGGER quotation_defaults_set_updated_at
  BEFORE UPDATE ON public.quotation_defaults
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS on all six tables
-- ---------------------------------------------------------------------------

ALTER TABLE public.quotation_families ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotation_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotation_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotation_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotation_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotation_defaults ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.quotation_families FROM anon;
REVOKE ALL ON public.quotation_versions FROM anon;
REVOKE ALL ON public.quotation_lines FROM anon;
REVOKE ALL ON public.quotation_adjustments FROM anon;
REVOKE ALL ON public.quotation_responses FROM anon;
REVOKE ALL ON public.quotation_defaults FROM anon;

REVOKE INSERT, UPDATE, DELETE ON public.quotation_families FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.quotation_versions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.quotation_lines FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.quotation_adjustments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.quotation_responses FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.quotation_defaults FROM authenticated;

GRANT SELECT ON public.quotation_families TO authenticated;
GRANT SELECT ON public.quotation_versions TO authenticated;
GRANT SELECT ON public.quotation_lines TO authenticated;
GRANT SELECT ON public.quotation_adjustments TO authenticated;
GRANT SELECT ON public.quotation_responses TO authenticated;
GRANT SELECT ON public.quotation_defaults TO authenticated;

CREATE POLICY tenant_isolation_select ON public.quotation_families
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.quotation_versions
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.quotation_lines
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.quotation_adjustments
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.quotation_responses
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY tenant_isolation_select ON public.quotation_defaults
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- ---------------------------------------------------------------------------
-- View: quotation_list (security_invoker, no email/phone/token)
-- ---------------------------------------------------------------------------

CREATE VIEW public.quotation_list WITH (security_invoker = true) AS
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
  f.pre_reservation_id,
  pr.reference AS pre_reservation_reference,
  v.currency,
  v.total,
  v.valid_until,
  v.issued_at,
  v.created_at,
  v.created_by,
  up.full_name AS agent_name
FROM public.quotation_versions v
JOIN public.quotation_families f
  ON f.id = v.family_id AND f.organization_id = v.organization_id
JOIN public.customers c
  ON c.id = f.customer_id AND c.organization_id = v.organization_id
JOIN public.pre_reservations pr
  ON pr.id = f.pre_reservation_id AND pr.organization_id = v.organization_id
LEFT JOIN public.user_profiles up
  ON up.id = v.created_by AND up.organization_id = v.organization_id;

COMMENT ON VIEW public.quotation_list IS
  'Panel list of quotation versions with customer/pre-reservation references. security_invoker enforces RLS. No email, phone or token.';

REVOKE ALL ON public.quotation_list FROM anon;
GRANT SELECT ON public.quotation_list TO authenticated;
