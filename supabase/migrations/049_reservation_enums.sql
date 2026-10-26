-- 049_reservation_enums.sql
-- Enums and audit events for confirmed reservations (feature 006).
-- Source of truth: specs/006-reservation-lifecycle/data-model.md.

CREATE TYPE public.reservation_status AS ENUM (
  'confirmed',
  'in_progress',
  'completed',
  'cancelled',
  'superseded'
);

COMMENT ON TYPE public.reservation_status IS
  'Lifecycle of one reservation version. completed and cancelled are terminal; superseded is historical.';

CREATE TYPE public.reservation_item_ops_status AS ENUM (
  'pending_provider',
  'confirmed_with_provider',
  'in_service',
  'completed',
  'provider_failed'
);

COMMENT ON TYPE public.reservation_item_ops_status IS
  'Operational status of one reserved service line with its provider.';

CREATE TYPE public.payment_method AS ENUM (
  'bank_transfer',
  'cash',
  'card_manual',
  'other'
);

COMMENT ON TYPE public.payment_method IS
  'Manual payment methods. No payment gateway in this feature.';

CREATE TYPE public.id_document_type AS ENUM (
  'cc',
  'ce',
  'passport',
  'ti',
  'other'
);

COMMENT ON TYPE public.id_document_type IS
  'Traveler identity document type on a reservation passenger row.';

CREATE TYPE public.provider_notify_channel AS ENUM (
  'whatsapp_copy',
  'email_copy',
  'print'
);

COMMENT ON TYPE public.provider_notify_channel IS
  'How the operator recorded that a service order was sent. The platform does not send messages.';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'reservation_confirmed';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'reservation_status_changed';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'reservation_cancelled';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'reservation_version_created';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'reservation_payment_recorded';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'reservation_provider_notified';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'reservation_item_reassigned';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'reservation_voucher_voided';
