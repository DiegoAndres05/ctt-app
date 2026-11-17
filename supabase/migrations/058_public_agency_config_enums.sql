-- 058_public_agency_config_enums.sql
-- Audit event types for feature 016 (multi-agency public CMS).
-- Kept in its own migration: a new enum value cannot be used in the transaction that adds it.
-- Source of truth: specs/016-multiagency-public-cms/data-model.md

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_taxonomy_changed';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_profile_updated';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_key_generated';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_key_revoked';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_source_config_changed';
