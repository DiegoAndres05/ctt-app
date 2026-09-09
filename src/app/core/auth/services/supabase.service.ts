import { inject, Injectable } from '@angular/core';
import {
  createClient,
  type AuthChangeEvent,
  type Session,
  type Subscription,
  type SupabaseClient,
} from '@supabase/supabase-js';
import { environment } from '../../../../environments/environment';
import { SessionActivityStore } from '../interceptors/session.interceptor';

/**
 * Owns the single Supabase client for the application.
 *
 * Credential handling is delegated entirely to Supabase Auth (FR-007): passwords are hashed
 * with bcrypt and stored in `auth.users.encrypted_password`. Nothing in this codebase hashes,
 * persists, or logs a password.
 *
 * Only the public anon key is used here. Every request it authorizes is still evaluated by
 * Row Level Security, and the service role key is never referenced from the browser.
 */
@Injectable({ providedIn: 'root' })
export class SupabaseService {
  // Declared before the client because the client is built with a fetch that closes over it.
  private readonly activity = inject(SessionActivityStore);

  private readonly supabase: SupabaseClient = createClient(
    environment.supabaseUrl,
    environment.supabaseAnonKey,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        // No OAuth or magic-link flows in this module, so there is never a session to
        // recover from the URL; leaving it off avoids parsing untrusted fragments.
        detectSessionInUrl: false,
        flowType: 'pkce',
        storageKey: 'cttadmin.auth',
      },
      global: {
        fetch: (input, init) => this.gatedFetch(input, init),
      },
    },
  );

  /** Escape hatch for callers that need PostgREST, RPC or storage access. */
  get client(): SupabaseClient {
    return this.supabase;
  }

  /**
   * Subscribes to session lifecycle changes (sign in, sign out, token refresh).
   *
   * The caller owns the returned subscription and must unsubscribe.
   */
  onAuthStateChange(
    callback: (event: AuthChangeEvent, session: Session | null) => void,
  ): Subscription {
    const {
      data: { subscription },
    } = this.supabase.auth.onAuthStateChange(callback);
    return subscription;
  }

  /** Session restored from storage at startup, if any. */
  async getSession(): Promise<Session | null> {
    const {
      data: { session },
    } = await this.supabase.auth.getSession();
    return session;
  }

  /**
   * Refuses data requests once the session policy has expired (FR-001).
   *
   * The Supabase client uses `fetch` directly, so an Angular HTTP interceptor never sees this
   * traffic; wrapping `fetch` is what makes the timeout apply to it.
   *
   * Two paths stay open on an expired session, and only these two: Supabase Auth itself, so
   * that signing out still works, and the RPC that records the expiry in the audit log. Both
   * are how a session ends, not a way to keep using one.
   */
  private gatedFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    const isSessionTeardown = url.includes('/auth/v1/') || url.includes('/rpc/record_session_end');
    // Public onboarding must work even if a stale expired session is still in this tab.
    const isPublicOnboarding = url.includes('/functions/v1/register-agency');

    if (!isSessionTeardown && !isPublicOnboarding && this.activity.check() !== 'active') {
      return Promise.reject(new Error('SESSION_EXPIRED'));
    }

    return fetch(input, init);
  }
}
