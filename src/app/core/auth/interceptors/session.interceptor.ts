import { HttpInterceptorFn } from '@angular/common/http';
import { computed, inject, Injectable, signal } from '@angular/core';
import { throwError } from 'rxjs';
import { toAppError } from '../../error/error-handler';

/**
 * Working-day session limits (FR-001, research.md R-005).
 *
 * Two independent clocks: one that a working user keeps resetting, and one that nothing can
 * extend.
 */
export const SESSION_INACTIVITY_LIMIT_MS = 8 * 60 * 60 * 1000;
export const SESSION_ABSOLUTE_LIMIT_MS = 24 * 60 * 60 * 1000;

/**
 * How often activity is written back to `user_profiles.last_activity_at`.
 *
 * The column exists so the inactivity clock survives a reload; it does not need per-request
 * precision, and writing on every request would cost a round trip for nothing.
 */
export const ACTIVITY_PERSIST_INTERVAL_MS = 5 * 60 * 1000;

export type SessionExpiry = 'active' | 'inactivity' | 'absolute';

/**
 * The two session clocks, and the verdict derived from them.
 *
 * This is the single implementation of the timeout rule. It is deliberately dependency-free so
 * that every caller that needs to enforce it — the HTTP interceptor below, the Supabase request
 * gate in `SupabaseService`, and `authGuard` — can consult the same state without a dependency
 * cycle through `AuthService`.
 *
 * Scope note: these limits are enforced in the browser, which makes them a usability and
 * defence-in-depth control rather than a boundary. The authoritative boundaries stay in the
 * database: the access token's own expiry and Row Level Security. See ADR-0003.
 */
@Injectable({ providedIn: 'root' })
export class SessionActivityStore {
  /**
   * Start of the session as the server dated it, not as the current token was issued.
   *
   * Supabase re-issues the access token roughly hourly and each new token carries a fresh
   * `iat`, so anchoring on `iat` would make the absolute limit unreachable.
   */
  private readonly anchorAtMs = signal<number | null>(null);
  private readonly lastActivityAtMs = signal<number | null>(null);
  private readonly expiryState = signal<SessionExpiry>('active');

  readonly expiry = this.expiryState.asReadonly();
  readonly lastActivityAt = this.lastActivityAtMs.asReadonly();
  readonly isTracking = computed<boolean>(() => this.anchorAtMs() !== null);

  /**
   * Begins (or resumes) tracking a session.
   *
   * Repeated calls with the same anchor are ignored, so a token refresh does not silently
   * reset the inactivity clock.
   *
   * @param anchorAtMs Server-issued start of the session.
   * @param lastActivityAtMs Last activity already recorded for this user, when known.
   */
  track(anchorAtMs: number, lastActivityAtMs?: number | null): void {
    if (this.anchorAtMs() === anchorAtMs) {
      return;
    }

    this.anchorAtMs.set(anchorAtMs);
    // A stored timestamp is only useful while it is newer than the session anchor; anything
    // older belongs to a previous session.
    const restored =
      lastActivityAtMs !== null && lastActivityAtMs !== undefined && lastActivityAtMs > anchorAtMs
        ? lastActivityAtMs
        : anchorAtMs;
    this.lastActivityAtMs.set(Math.max(restored, anchorAtMs));
    this.expiryState.set('active');
  }

  clear(): void {
    this.anchorAtMs.set(null);
    this.lastActivityAtMs.set(null);
    this.expiryState.set('active');
  }

  /**
   * Records that the user is still working.
   *
   * An expired session is never revived here: only a fresh sign-in can do that.
   */
  registerActivity(nowMs = Date.now()): void {
    if (!this.isTracking() || this.expiryState() !== 'active') {
      return;
    }
    this.lastActivityAtMs.set(nowMs);
  }

  /**
   * Re-evaluates both clocks and publishes the verdict.
   *
   * Time is an input rather than an ambient read so the rule can be tested directly.
   */
  check(nowMs = Date.now()): SessionExpiry {
    const anchorAt = this.anchorAtMs();
    const lastActivityAt = this.lastActivityAtMs();

    if (anchorAt === null || lastActivityAt === null) {
      return 'active';
    }

    // The absolute limit is reported in preference to inactivity: it is the one a user cannot
    // do anything about, and it is what the audit trail should show.
    let verdict: SessionExpiry = 'active';
    if (nowMs - anchorAt >= SESSION_ABSOLUTE_LIMIT_MS) {
      verdict = 'absolute';
    } else if (nowMs - lastActivityAt >= SESSION_INACTIVITY_LIMIT_MS) {
      verdict = 'inactivity';
    }

    if (verdict !== this.expiryState()) {
      this.expiryState.set(verdict);
    }
    return verdict;
  }
}

/**
 * Applies the session policy to every `HttpClient` request and treats each one as user
 * activity.
 *
 * Supabase traffic does not pass through `HttpClient`; it is gated inside `SupabaseService`
 * against this same store. This interceptor covers the application's own HTTP calls.
 */
export const sessionInterceptor: HttpInterceptorFn = (request, next) => {
  const activity = inject(SessionActivityStore);

  if (activity.check() !== 'active') {
    return throwError(() => toAppError({ code: 'SESSION_EXPIRED' }));
  }

  activity.registerActivity();
  return next(request);
};
