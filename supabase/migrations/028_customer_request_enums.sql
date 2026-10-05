-- 028_customer_request_enums.sql
-- Enums for customers and requests, plus audit event labels consumed from 029 onward.
-- Source of truth: specs/003-customer-requests-channels/data-model.md ("Enums").
--
-- Each ADD VALUE is its own statement. PostgreSQL forbids using a newly added enum label
-- in the same transaction that created it; later migrations consume these values.

CREATE TYPE public.request_channel AS ENUM ('web', 'whatsapp', 'phone', 'in_person');

COMMENT ON TYPE public.request_channel IS
  'How a customer request arrived: web, whatsapp, phone, or in_person.';

CREATE TYPE public.request_status AS ENUM ('received', 'in_review', 'discarded', 'pre_reservation');

COMMENT ON TYPE public.request_status IS
  'Lifecycle of a customer request. pre_reservation is assigned only by feature 004.';

CREATE TYPE public.document_type AS ENUM ('cc', 'ce', 'passport', 'nit', 'other');

COMMENT ON TYPE public.document_type IS
  'Traveler identity document. cc/ce are Colombian; nit is a tax id.';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'request_received';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'request_assigned';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'request_status_changed';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'customer_updated';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'customer_anonymized';
