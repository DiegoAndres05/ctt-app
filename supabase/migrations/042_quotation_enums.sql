-- 042_quotation_enums.sql
-- Enums for quotations (commercial proposals).
-- Source of truth: specs/005-quotation-proposals/data-model.md (Enums),
-- specs/005-quotation-proposals/research.md (R-011, R-012).
--
-- These are base types; the tables and functions that use them live in 043-045.
-- The audit event values added at the end of this file are NOT used here.

-- ---------------------------------------------------------------------------
-- quotation_status
-- ---------------------------------------------------------------------------

CREATE TYPE public.quotation_status AS ENUM (
  'draft',
  'issued',
  'accepted',
  'rejected',
  'expired',
  'voided',
  'superseded'
);

COMMENT ON TYPE public.quotation_status IS
  'Lifecycle of one quotation version. accepted and voided are terminal; superseded is read-only.';

-- ---------------------------------------------------------------------------
-- quotation_adjustment_direction
-- ---------------------------------------------------------------------------

CREATE TYPE public.quotation_adjustment_direction AS ENUM ('discount', 'surcharge');

COMMENT ON TYPE public.quotation_adjustment_direction IS
  'Commercial adjustment direction: discount lowers the amount, surcharge raises it.';

-- ---------------------------------------------------------------------------
-- quotation_adjustment_kind
-- ---------------------------------------------------------------------------

CREATE TYPE public.quotation_adjustment_kind AS ENUM ('percent', 'amount');

COMMENT ON TYPE public.quotation_adjustment_kind IS
  'How an adjustment value is interpreted: percentage of the base, or absolute amount.';

-- ---------------------------------------------------------------------------
-- quotation_response_kind
-- ---------------------------------------------------------------------------

CREATE TYPE public.quotation_response_kind AS ENUM ('accepted', 'rejected', 'changes_requested');

COMMENT ON TYPE public.quotation_response_kind IS
  'Recorded client/agent response. changes_requested is not a status; the version stays issued.';

-- ---------------------------------------------------------------------------
-- quotation_response_origin
-- ---------------------------------------------------------------------------

CREATE TYPE public.quotation_response_origin AS ENUM ('customer', 'agent');

COMMENT ON TYPE public.quotation_response_origin IS
  'Who recorded the response: the client through the public link, or an agent in the panel.';

-- ---------------------------------------------------------------------------
-- Audit event types (extend the existing enum from 001)
-- Added only; none of these values is used in this file.
-- ---------------------------------------------------------------------------

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'quotation_created';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'quotation_issued';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'quotation_adjustment_applied';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'quotation_response_recorded';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'quotation_superseded';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'quotation_voided';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'quotation_expired';
