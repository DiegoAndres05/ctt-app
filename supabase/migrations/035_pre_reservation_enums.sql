-- 035_pre_reservation_enums.sql
-- Enums for pre-reservations and human availability verification.
-- Source of truth: specs/004-prereservation-availability/data-model.md (Enums),
-- specs/004-prereservation-availability/research.md (R-001..R-013).
--
-- These are base types; the tables and functions that use them are in later migrations.

-- ---------------------------------------------------------------------------
-- pre_reservation_status
-- ---------------------------------------------------------------------------

CREATE TYPE public.pre_reservation_status AS ENUM (
  'pending_verification',
  'partially_verified',
  'verified',
  'requires_adjustment',
  'expired',
  'cancelled'
);

COMMENT ON TYPE public.pre_reservation_status IS
  'Global state of a pre-reservation. Only cancelled is manual; the rest are derived from main line verification states.';

-- ---------------------------------------------------------------------------
-- availability_status
-- ---------------------------------------------------------------------------

CREATE TYPE public.availability_status AS ENUM (
  'pending',
  'available',
  'unavailable',
  'alternative_suggested'
);

COMMENT ON TYPE public.availability_status IS
  'Verification state of a single pre-reservation line.';

-- ---------------------------------------------------------------------------
-- provider_contact_method
-- ---------------------------------------------------------------------------

CREATE TYPE public.provider_contact_method AS ENUM (
  'phone',
  'whatsapp',
  'email',
  'other'
);

COMMENT ON TYPE public.provider_contact_method IS
  'How the operator contacted the provider to verify availability.';

-- ---------------------------------------------------------------------------
-- availability_event_kind
-- ---------------------------------------------------------------------------

CREATE TYPE public.availability_event_kind AS ENUM (
  'item_added',
  'verification_started',
  'outcome_recorded',
  'item_withdrawn',
  'alternative_promoted',
  'pre_reservation_cancelled',
  'quote_override_authorized'
);

COMMENT ON TYPE public.availability_event_kind IS
  'Kind of event recorded in the availability verification history.';

-- ---------------------------------------------------------------------------
-- Audit event types (extend the existing enum from 001)
-- ---------------------------------------------------------------------------

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'pre_reservation_created';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'pre_reservation_status_changed';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'pre_reservation_items_changed';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'pre_reservation_assigned';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'availability_recorded';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'pre_reservation_cancelled';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'quotation_override_authorized';