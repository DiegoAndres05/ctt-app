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
  | 'PRODUCT_HAS_NO_VALID_PRICE'
  | 'SEASON_OVERLAP'
  | 'INVALID_SEASON_RANGE'
  | 'INVALID_PRICE_TARGET'
  | 'PACKAGE_NESTING_NOT_ALLOWED'
  | 'PUBLIC_LISTING_INCOMPLETE'
  | 'PUBLIC_SLUG_IMMUTABLE'
  | 'PUBLIC_SLUG_TAKEN'
  | 'PLACEMENT_PRODUCT_MISMATCH'
  | 'ORIGINAL_PRICE_NOT_HIGHER'
  | 'BILINGUAL_PAIR_INCOMPLETE'
  | 'PRODUCT_NOT_ACTIVE'
  | 'COVER_REQUIRED'
  | 'IMAGE_TOO_LARGE'
  | 'IMAGE_TYPE_NOT_ALLOWED'
  | 'GALLERY_ONLY_FOR_LODGING'
  | 'CATEGORY_IN_USE'
  | 'CUTOVER_INCOMPLETE'
  | 'CUTOVER_ALREADY_COMPLETED'
  | 'CONSENT_REQUIRED'
  | 'CONTACT_REQUIRED'
  | 'INVALID_EMAIL'
  | 'INVALID_PHONE'
  | 'TRAVEL_DATE_IN_PAST'
  | 'INVALID_DATE_RANGE'
  | 'LISTING_NOT_AVAILABLE'
  | 'RATE_LIMITED'
  | 'INVALID_STATUS_TRANSITION'
  | 'PRE_RESERVATION_REQUIRES_CONVERSION'
  | 'DISCARD_REASON_REQUIRED'
  | 'REQUEST_CLOSED'
  | 'ASSIGNEE_NOT_IN_ORGANIZATION'
  | 'CUSTOMER_ANONYMIZED'
  | 'CUSTOMER_CONTACT_TAKEN'
  | 'PRE_RESERVATION_CLOSED'
  | 'PRE_RESERVATION_REQUIRES_ITEMS'
  | 'PRE_RESERVATION_NOT_VERIFIED'
  | 'PRE_RESERVATION_EXPIRED'
  | 'ITEM_NOT_BOOKABLE'
  | 'ITEM_WITHDRAWN'
  | 'CONTACT_PERSON_REQUIRED'
  | 'HOLD_EXPIRY_IN_PAST'
  | 'ALTERNATIVE_SUGGESTION_REQUIRED'
  | 'CANCEL_REASON_REQUIRED'
  | 'OVERRIDE_REASON_REQUIRED'
  | 'OVERRIDE_NOT_REQUIRED'
  | 'ASSIGNEE_NOT_OPERATOR'
  // Quotations (feature 005, specs/005-quotation-proposals/contracts/api-contracts.md).
  | 'TARIFF_NOT_FOUND'
  | 'AMBIGUOUS_TARIFF'
  | 'EXCHANGE_RATE_REQUIRED'
  | 'EXCHANGE_RATE_INVALID'
  | 'TAX_RATE_OUT_OF_RANGE'
  | 'ADJUSTMENT_REQUIRES_ADMIN'
  | 'ADJUSTMENT_LABEL_REQUIRED'
  | 'QUOTATION_FROZEN'
  | 'QUOTATION_ALREADY_OPEN'
  | 'QUOTATION_ALREADY_ACCEPTED'
  | 'VALIDITY_EXCEEDS_HOLD'
  | 'VALIDITY_EXCEEDS_30_DAYS'
  | 'TERMS_REQUIRED'
  | 'QUOTATION_STALE'
  | 'QUOTATION_NOT_OPEN'
  | 'QUOTATION_TERMINAL'
  | 'QUOTATION_NOT_ACCEPTED'
  | 'QUOTATION_ACCEPTED'
  | 'VOID_REASON_REQUIRED'
  | 'CONFIRMATION_REQUIRED'
  | 'FORBIDDEN'
  | 'UNKNOWN_ERROR';
