-- 012_alter_audit_event_types.sql
-- Extends the immutable audit log with catalog/pricing events.
-- Source of truth: specs/002-catalog-pricing/data-model.md ("Triggers & Functions").
--
-- Each ADD VALUE is its own statement. PostgreSQL forbids using a newly added enum label
-- in the same transaction that created it; later migrations and RPCs consume these values.

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'price_overridden';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'product_activated';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'product_deactivated';
