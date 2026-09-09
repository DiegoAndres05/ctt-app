-- 004_create_audit_schema.sql
-- Immutable security audit log, isolated in its own schema so its privileges can be
-- managed independently from business data.
-- Source of truth: specs/001-auth-tenant-access/data-model.md ("3. Audit Event").

CREATE SCHEMA IF NOT EXISTS audit;

COMMENT ON SCHEMA audit IS
  'Append-only security audit log. UPDATE and DELETE are rejected by trigger (migration 007).';

CREATE TABLE audit.audit_events (
  id bigserial PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE RESTRICT,
  -- RESTRICT rather than SET NULL: rewriting an audit row would be blocked by the
  -- immutability trigger anyway, and history must survive collaborator lifecycle changes.
  actor_id uuid REFERENCES public.user_profiles (id) ON DELETE RESTRICT,
  event_type audit.audit_event_type NOT NULL,
  resource_type text,
  resource_id uuid,
  result audit.audit_result NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE audit.audit_events IS
  'Immutable record of security and access-control events, scoped to one organization.';
COMMENT ON COLUMN audit.audit_events.actor_id IS
  'Collaborator who performed the action; NULL for system-originated events.';
COMMENT ON COLUMN audit.audit_events.metadata IS
  'Contextual detail. Must never contain credentials or other secrets.';

-- Time-range queries over an append-only, chronologically clustered table: BRIN gives
-- almost all of the benefit of a btree at a fraction of the size.
CREATE INDEX audit_events_created_at_brin_idx
  ON audit.audit_events USING brin (created_at);

CREATE INDEX audit_events_organization_id_idx
  ON audit.audit_events (organization_id);

CREATE INDEX audit_events_organization_id_event_type_idx
  ON audit.audit_events (organization_id, event_type);

CREATE INDEX audit_events_actor_id_idx
  ON audit.audit_events (actor_id);

-- Default Deny: enabled at creation so the table is never reachable without an explicit
-- policy. Policies are granted in migration 005.
ALTER TABLE audit.audit_events ENABLE ROW LEVEL SECURITY;

-- Privilege layer, independent of RLS. Reading is the only capability ever granted to a
-- browser session; writes arrive exclusively through SECURITY DEFINER triggers and functions.
REVOKE ALL ON SCHEMA audit FROM PUBLIC;
REVOKE ALL ON audit.audit_events FROM PUBLIC;

GRANT USAGE ON SCHEMA audit TO authenticated, service_role;
GRANT SELECT ON audit.audit_events TO authenticated;
GRANT SELECT, INSERT ON audit.audit_events TO service_role;
GRANT USAGE, SELECT ON SEQUENCE audit.audit_events_id_seq TO service_role;
