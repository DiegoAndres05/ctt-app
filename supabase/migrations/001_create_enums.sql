-- 001_create_enums.sql
-- Domain enumerations for identity, tenancy and auditing.
-- Source of truth: specs/001-auth-tenant-access/data-model.md ("Enums").

-- The audit schema is declared here because the audit enumerations live inside it.
-- Migration 004 owns the schema's tables and privileges.
CREATE SCHEMA IF NOT EXISTS audit;

-- Application roles, hierarchical: admin > operator > agent.
CREATE TYPE public.app_role AS ENUM ('admin', 'operator', 'agent');

-- Tenant lifecycle.
CREATE TYPE public.organization_status AS ENUM ('active', 'suspended', 'inactive');

-- Internal collaborator lifecycle.
CREATE TYPE public.user_status AS ENUM ('active', 'inactive');

-- Security events captured in the immutable audit log.
CREATE TYPE audit.audit_event_type AS ENUM (
  'login_success', 'login_failure', 'logout', 'session_expired',
  'user_created', 'user_updated', 'user_activated', 'user_deactivated',
  'role_changed', 'password_changed', 'password_reset_forced',
  'organization_created', 'account_locked', 'account_unlocked'
);

-- Outcome of an audited operation.
CREATE TYPE audit.audit_result AS ENUM ('success', 'failure', 'error');
