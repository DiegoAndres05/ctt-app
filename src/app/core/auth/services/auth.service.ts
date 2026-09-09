import { computed, DestroyRef, inject, Injectable, signal } from '@angular/core';
import type { Session } from '@supabase/supabase-js';
import { redact, toAppError } from '../../error/error-handler';
import {
  ACTIVITY_PERSIST_INTERVAL_MS,
  SessionActivityStore,
  type SessionExpiry,
} from '../interceptors/session.interceptor';
import {
  APP_ROLE_CLAIM,
  ORGANIZATION_ID_CLAIM,
  type AccessTokenClaims,
  type AuthenticatedUser,
  type RegisterAgencyInput,
  type RegisterAgencyResponse,
  type SessionEndReason,
} from '../models/auth.model';
import type { AppRole, UserProfile } from '../models/user.model';
import { SupabaseService } from './supabase.service';

/** How often the session policy is re-evaluated for a tab nobody is touching. */
const SESSION_POLICY_POLL_MS = 60 * 1000;

/**
 * Reactive source of truth for the current session and the identity derived from it.
 *
 * Everything exposed here is read-only and reflects claims the database put into the access
 * token via `custom_access_token_hook`. It exists to drive the UI; it is not an authorization
 * boundary. The enforcement boundary is Row Level Security, which re-derives tenant and role
 * from the same token on every statement and does not trust the browser.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly supabase = inject(SupabaseService);
  private readonly activity = inject(SessionActivityStore);

  private readonly sessionState = signal<Session | null>(null);

  /** Current Supabase session, or null when signed out. */
  readonly session = this.sessionState.asReadonly();

  /**
   * True once the initial session restore has settled. Guards must wait for this, otherwise
   * a page reload would be indistinguishable from being signed out.
   */
  private readonly initializedState = signal(false);
  readonly initialized = this.initializedState.asReadonly();

  /**
   * The caller's own `user_profiles` row.
   *
   * `must_change_password` lives here rather than in the token because it changes during a
   * session and the guard has to see the change without waiting for a token refresh.
   */
  private readonly profileState = signal<UserProfile | null>(null);
  readonly profile = this.profileState.asReadonly();

  /** Claims decoded from the access token, or null when there is no session. */
  readonly claims = computed<AccessTokenClaims | null>(() => {
    const accessToken = this.sessionState()?.access_token;
    return accessToken ? decodeAccessToken(accessToken) : null;
  });

  /**
   * Identity context, resolved only when the token carries both tenant and role.
   *
   * A token missing `organization_id` belongs to a user whose profile is inactive or absent.
   * Such a session can reach no tenant data, so it is surfaced as "not a usable identity"
   * rather than as a partially authenticated user.
   */
  readonly user = computed<AuthenticatedUser | null>(() => {
    const claims = this.claims();
    if (!claims) {
      return null;
    }

    const organizationId = claims[ORGANIZATION_ID_CLAIM];
    const role = claims[APP_ROLE_CLAIM];
    if (!organizationId || !role) {
      return null;
    }

    return {
      id: claims.sub,
      email: claims.email ?? '',
      organizationId,
      role,
    };
  });

  readonly isAuthenticated = computed<boolean>(() => this.user() !== null);

  /** Tenant of the current session; null when there is no usable identity. */
  readonly organizationId = computed<string | null>(() => this.user()?.organizationId ?? null);

  /** Application role of the current session; null when there is no usable identity. */
  readonly role = computed<AppRole | null>(() => this.user()?.role ?? null);

  /**
   * Whether the collaborator still holds the temporary password an administrator assigned.
   *
   * Defaults to false while the profile is unknown so that a failed profile read cannot lock a
   * user into the change-password screen; the flag is authoritative in the database, and
   * `change_password` is the only thing that can clear it.
   */
  readonly mustChangePassword = computed<boolean>(
    () => this.profileState()?.must_change_password ?? false,
  );

  private initializedPromise?: Promise<void>;
  private resolveInitialized?: () => void;
  private endSessionInFlight?: Promise<void>;
  private lastActivityPersistedAtMs = 0;
  private syncedAccessToken: string | null = null;

  constructor() {
    this.initializedPromise = new Promise((resolve) => {
      this.resolveInitialized = resolve;
    });

    const subscription = this.supabase.onAuthStateChange((_event, session) => {
      // Deferred on purpose: the Supabase client holds its auth lock while this callback runs,
      // and the profile read below goes back through the same client.
      setTimeout(() => void this.syncSession(session), 0);
    });

    const policyTimer = setInterval(() => {
      void this.enforceSessionPolicy();
    }, SESSION_POLICY_POLL_MS);

    inject(DestroyRef).onDestroy(() => {
      subscription.unsubscribe();
      clearInterval(policyTimer);
    });

    void this.restoreSession();
  }

  /** Resolves once the session and profile have been read at least once. */
  whenInitialized(): Promise<void> {
    return this.initializedState()
      ? Promise.resolve()
      : (this.initializedPromise ?? Promise.resolve());
  }

  /**
   * Signs a collaborator in.
   *
   * Failures are surfaced through {@link toAppError}, which collapses a wrong address and a
   * wrong password into the same `INVALID_CREDENTIALS` code so the response cannot be used to
   * discover which accounts exist. Lockout and deactivation come back as their own codes
   * because the database only reveals those once the password has been proven, or once the
   * account is already locked (migration 008).
   *
   * @throws AppError
   */
  async signIn(email: string, password: string): Promise<void> {
    const { data, error } = await this.supabase.client.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    });

    if (error) {
      throw toAppError(error);
    }

    await this.syncSession(data.session);

    // Authenticated but with nothing to authenticate *for*: the profile is missing or the
    // access token carries no tenant. Default Deny, and do not leave a half-usable session
    // lying around.
    if (!this.isAuthenticated()) {
      await this.endSession('logout');
      throw toAppError({ code: 'MISSING_TENANT_CONTEXT' });
    }
  }

  /**
   * Registers a new agency and signs the founding administrator in (FR-008).
   *
   * The browser only talks to the public `register-agency` Edge Function. That function
   * creates the auth user, calls `register_agency` (which is not executable by `anon`), and
   * rolls the auth user back if the RPC fails. Duplicate emails and colliding slugs come back
   * as the contract codes `EMAIL_ALREADY_EXISTS` and `AGENCY_SLUG_EXISTS`.
   *
   * @throws AppError
   */
  async registerAgency(input: RegisterAgencyInput): Promise<void> {
    const { data, error } = await this.supabase.client.functions.invoke('register-agency', {
      body: {
        agency_name: input.agencyName.trim(),
        full_name: input.fullName.trim(),
        email: input.email.trim().toLowerCase(),
        password: input.password,
      },
    });

    if (error) {
      throw await registrationError(error, data);
    }

    const payload = data as RegisterAgencyResponse | null;
    const session = payload?.data?.session;
    if (!session?.access_token || !session.refresh_token) {
      throw toAppError({ code: 'REGISTRATION_FAILED' });
    }

    const { error: sessionError } = await this.supabase.client.auth.setSession({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
    });

    if (sessionError) {
      throw toAppError(sessionError);
    }

    await this.syncSession(await this.supabase.getSession());

    if (!this.isAuthenticated()) {
      await this.endSession('logout');
      throw toAppError({ code: 'MISSING_TENANT_CONTEXT' });
    }
  }

  /** Signs the current collaborator out and records the event. */
  async signOut(): Promise<void> {
    await this.endSession('logout');
  }

  /**
   * Rotates the caller's own password through the `change_password` RPC.
   *
   * The current password, the strength rules and the mandatory-change flag are all checked
   * inside a single database transaction, so the flag cannot end up cleared without the
   * credential actually having changed.
   *
   * @throws AppError
   */
  async changePassword(currentPassword: string, newPassword: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('change_password', {
      p_current_password: currentPassword,
      p_new_password: newPassword,
    });

    if (error) {
      throw toAppError(error);
    }

    await this.loadProfile();
  }

  /**
   * Marks the user as active and, at most once every
   * {@link ACTIVITY_PERSIST_INTERVAL_MS}, persists it to `user_profiles.last_activity_at` so
   * the inactivity clock survives a reload.
   */
  recordActivity(): void {
    this.activity.registerActivity();

    const userId = this.user()?.id;
    const now = Date.now();
    if (!userId || now - this.lastActivityPersistedAtMs < ACTIVITY_PERSIST_INTERVAL_MS) {
      return;
    }
    this.lastActivityPersistedAtMs = now;

    void this.supabase.client
      .from('user_profiles')
      .update({ last_activity_at: new Date(now).toISOString() })
      .eq('id', userId)
      .then(({ error }) => {
        if (error) {
          // Losing the write costs precision in the inactivity clock, nothing more, but it
          // must not pass unnoticed.
          console.warn('[cttadmin] could not persist last_activity_at', redact(error));
        }
      });
  }

  /**
   * Re-evaluates the session limits and terminates the session when either has been reached.
   *
   * Called from `authGuard` on every navigation and from a timer for tabs left alone.
   */
  async enforceSessionPolicy(): Promise<SessionExpiry> {
    const verdict = this.activity.check();
    if (verdict !== 'active' && this.sessionState() !== null) {
      await this.endSession('session_expired');
    }
    return verdict;
  }

  /** Current session verdict without re-evaluating the clocks. */
  readonly sessionExpiry = computed<SessionExpiry>(() => this.activity.expiry());

  private async restoreSession(): Promise<void> {
    try {
      await this.syncSession(await this.supabase.getSession());
    } catch (error) {
      console.error('[cttadmin] could not restore the session', redact(error));
      this.markInitialized();
    }
  }

  /**
   * Brings every piece of session-derived state in line with `session`.
   *
   * Ordered so that nothing observes a session without its profile: the profile is read first,
   * and only then do the session clocks start.
   *
   * Supabase reports the restored session both through `getSession()` at startup and through an
   * `INITIAL_SESSION` event, and re-reports the current one on unrelated auth events. Keying on
   * the access token collapses those into one profile read, while still re-reading it whenever
   * a new token arrives.
   */
  private async syncSession(session: Session | null): Promise<void> {
    const accessToken = session?.access_token ?? null;
    if (this.initializedState() && accessToken === this.syncedAccessToken) {
      return;
    }
    this.syncedAccessToken = accessToken;

    this.sessionState.set(session);

    if (!session) {
      this.profileState.set(null);
      this.activity.clear();
      this.markInitialized();
      return;
    }

    await this.loadProfile();
    this.activity.track(
      resolveSessionAnchorMs(session, this.claims()),
      parseTimestamp(this.profileState()?.last_activity_at),
    );
    this.markInitialized();
  }

  private async loadProfile(): Promise<void> {
    const userId = this.claims()?.sub;
    if (!userId) {
      this.profileState.set(null);
      return;
    }

    const { data, error } = await this.supabase.client
      .from('user_profiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle<UserProfile>();

    if (error) {
      // Row Level Security hides the row from a session with no tenant claim, which is a
      // legitimate outcome rather than a fault; either way the profile stays unknown.
      console.warn('[cttadmin] could not read the current profile', redact(error));
      this.profileState.set(null);
      return;
    }

    this.profileState.set(data ?? null);
  }

  /**
   * Terminates the session once, however many callers ask for it.
   *
   * The audit event is written before Supabase Auth is asked to sign out, because the token is
   * what authorizes recording it.
   */
  private endSession(reason: SessionEndReason): Promise<void> {
    this.endSessionInFlight ??= this.terminate(reason).finally(() => {
      this.endSessionInFlight = undefined;
    });
    return this.endSessionInFlight;
  }

  private async terminate(reason: SessionEndReason): Promise<void> {
    if (this.sessionState() !== null) {
      const { error } = await this.supabase.client.rpc('record_session_end', {
        p_reason: reason,
      });
      if (error) {
        // Never a reason to keep a session alive; the sign-out below still happens.
        console.warn('[cttadmin] could not record the end of the session', redact(error));
      }
    }

    const { error: signOutError } = await this.supabase.client.auth.signOut();
    if (signOutError) {
      console.error('[cttadmin] sign-out failed', redact(signOutError));
    }

    this.sessionState.set(null);
    this.profileState.set(null);
    this.activity.clear();
    this.lastActivityPersistedAtMs = 0;
    this.syncedAccessToken = null;
  }

  private markInitialized(): void {
    this.initializedState.set(true);
    this.resolveInitialized?.();
    this.resolveInitialized = undefined;
  }
}

/**
 * Start of the session as the server dated it.
 *
 * `last_sign_in_at` is set by Supabase Auth when the password is verified and is not touched
 * by a token refresh, which is what makes it usable as the anchor for the absolute limit. The
 * token's `iat` is only a fallback: it moves forward on every refresh, so on its own it would
 * push the 24-hour ceiling permanently out of reach.
 */
function resolveSessionAnchorMs(session: Session, claims: AccessTokenClaims | null): number {
  return (
    parseTimestamp(session.user.last_sign_in_at) ??
    (claims ? claims.iat * 1000 : null) ??
    Date.now()
  );
}

function parseTimestamp(value: string | null | undefined): number | null {
  if (!value) {
    return null;
  }
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

/**
 * Reads a Functions error (and any body that arrived with it) into a contract AppError.
 *
 * `functions.invoke` often puts the JSON body in `data` even on a non-2xx, and otherwise
 * stashes the Response on `error.context`. Either way the `code` field is the contract.
 */
async function registrationError(
  error: unknown,
  data: unknown,
): Promise<ReturnType<typeof toAppError>> {
  const fromBody = contractErrorFrom(data);
  if (fromBody) {
    return fromBody;
  }

  if (typeof error === 'object' && error !== null && 'context' in error) {
    const context = (error as { context?: unknown }).context;
    if (context instanceof Response) {
      try {
        const fromResponse = contractErrorFrom(await context.clone().json());
        if (fromResponse) {
          return fromResponse;
        }
      } catch {
        // The body was not JSON; fall through to the generic mapper.
      }
    }
  }

  const mapped = toAppError(error);
  return mapped.code === 'UNKNOWN_ERROR' || mapped.code === 'INVALID_CREDENTIALS'
    ? toAppError({ code: 'REGISTRATION_FAILED' })
    : mapped;
}

function contractErrorFrom(value: unknown): ReturnType<typeof toAppError> | null {
  if (typeof value !== 'object' || value === null) {
    return null;
  }
  const candidate = value as { code?: unknown };
  if (typeof candidate.code === 'string' && candidate.code.length > 0) {
    return toAppError({ code: candidate.code, message: candidate.code });
  }
  return null;
}

/**
 * Reads the payload of a Supabase access token.
 *
 * The signature is not verified here and must not be: this is a convenience for rendering,
 * and the database performs the authoritative verification on every request.
 */
function decodeAccessToken(accessToken: string): AccessTokenClaims | null {
  const payload = accessToken.split('.')[1];
  if (!payload) {
    return null;
  }

  try {
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes)) as AccessTokenClaims;
  } catch {
    return null;
  }
}
