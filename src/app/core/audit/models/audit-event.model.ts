/**
 * Audit log domain types.
 *
 * Row shapes mirror `audit.audit_events` column-for-column. The log is append-only: there is
 * deliberately no update or delete shape, because the database rejects both.
 */

/** Mirrors the `audit.audit_event_type` enum. */
export type AuditEventType =
  | 'login_success'
  | 'login_failure'
  | 'logout'
  | 'session_expired'
  | 'user_created'
  | 'user_updated'
  | 'user_activated'
  | 'user_deactivated'
  | 'role_changed'
  | 'password_changed'
  | 'password_reset_forced'
  | 'organization_created'
  | 'account_locked'
  | 'account_unlocked';

/** Mirrors the `audit.audit_result` enum. */
export type AuditResult = 'success' | 'failure' | 'error';

/** A row of `audit.audit_events`. */
export interface AuditEvent {
  /** bigserial; serialized as a number by PostgREST. */
  id: number;
  organization_id: string;
  /** Null for system-originated events. */
  actor_id: string | null;
  event_type: AuditEventType;
  resource_type: string | null;
  resource_id: string | null;
  result: AuditResult;
  metadata: Record<string, unknown> | null;
  ip_address: string | null;
  user_agent: string | null;
  created_at: string;
}

/** Audit event as shown in the admin viewer, with the actor display name resolved. */
export interface AuditLogEntry extends AuditEvent {
  actor_name: string | null;
}

/** Query contract for the audit log viewer. Tenant scope comes from the JWT, never a filter. */
export interface AuditEventFilter {
  eventType?: AuditEventType;
  actorId?: string;
  /** Inclusive lower bound, ISO 8601. */
  from?: string;
  /** Inclusive upper bound, ISO 8601. */
  to?: string;
  limit?: number;
  offset?: number;
}

/** Default and maximum page sizes defined by the API contract. */
export const AUDIT_PAGE_SIZE_DEFAULT = 50;
export const AUDIT_PAGE_SIZE_MAX = 200;
