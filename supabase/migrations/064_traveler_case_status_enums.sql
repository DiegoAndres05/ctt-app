-- 064_traveler_case_status_enums.sql
-- Audit event type for feature 015 (traveler case status lookup).
-- Kept in its own migration: a new enum value cannot be used in the transaction that adds it.
-- Source of truth: specs/015-traveler-case-status/tasks.md (Design baseline).

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'traveler_case_lookup';
