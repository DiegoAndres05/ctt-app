import type { AppRole } from './user.model';

/**
 * Authentication and identity-context types.
 *
 * Unlike the row models, these describe values derived by the application, so they use
 * the usual camelCase TypeScript conventions.
 */

/** JWT claim carrying the tenant the session belongs to. */
export const ORGANIZATION_ID_CLAIM = 'organization_id';

/**
 * JWT claim carrying the application role.
 *
 * Deliberately not `role`: PostgREST reserves that claim to pick the PostgreSQL role for
 * the request. See `docs/adr/0002-jwt-app-role-claim.md`.
 */
export const APP_ROLE_CLAIM = 'app_role';

/**
 * Claims the application reads out of a Supabase access token.
 *
 * `organization_id` and `app_role` are injected server-side by the
 * `custom_access_token_hook` database function and cannot be influenced by the client.
 * Both are optional because a token issued for a deactivated or profile-less user carries
 * neither, which is exactly the condition the guards must reject.
 */
export interface AccessTokenClaims {
  /** Supabase user id. */
  sub: string;
  email?: string;
  /** Issued-at, seconds since epoch. Anchors the absolute session lifetime. */
  iat: number;
  /** Expiry, seconds since epoch. */
  exp: number;
  session_id?: string;
  [ORGANIZATION_ID_CLAIM]?: string;
  [APP_ROLE_CLAIM]?: AppRole;
}

/**
 * Fully resolved identity context for the current session.
 *
 * Only produced when the token carries both tenant and role, so holding one of these means
 * the session is usable for tenant-scoped work.
 */
export interface AuthenticatedUser {
  id: string;
  email: string;
  organizationId: string;
  role: AppRole;
}

/**
 * Why a session was terminated, as recorded by the `record_session_end` RPC.
 *
 * The database whitelists exactly these two values (migration 008), so this type is the
 * client half of that contract.
 */
export type SessionEndReason = 'logout' | 'session_expired';

/** Payload for the public `register-agency` Edge Function (FR-008). */
export interface RegisterAgencyInput {
  agencyName: string;
  fullName: string;
  email: string;
  password: string;
}

/**
 * Successful body of `register-agency`, matching
 * `specs/001-auth-tenant-access/contracts/api-contracts.md`.
 */
export interface RegisterAgencyResponse {
  data: {
    organization: {
      id: string;
      name: string;
      slug: string;
    };
    user: {
      id: string;
      email: string;
      full_name: string;
      role: 'admin';
    };
    session: {
      access_token: string;
      refresh_token: string;
      expires_in: number;
    };
  };
}

/**
 * Stable error codes shared with the API contracts
 * (`specs/001-auth-tenant-access/contracts/api-contracts.md`).
 *
 * `INVALID_CREDENTIALS` is intentionally coarse: the UI must not reveal whether it was the
 * address or the password that was wrong.
 */
export type AuthErrorCode =
  | 'VALIDATION_ERROR'
  | 'INVALID_CREDENTIALS'
  | 'ACCOUNT_LOCKED'
  | 'ACCOUNT_INACTIVE'
  | 'INVALID_CURRENT_PASSWORD'
  | 'WEAK_PASSWORD'
  | 'PASSWORD_UNCHANGED'
  | 'INSUFFICIENT_PERMISSIONS'
  | 'EMAIL_ALREADY_EXISTS'
  | 'AGENCY_SLUG_EXISTS'
  | 'REGISTRATION_FAILED'
  | 'MISSING_TENANT_CONTEXT'
  | 'SESSION_EXPIRED'
  | 'UNKNOWN_ERROR';
