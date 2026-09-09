import { inject } from '@angular/core';
import { Router, type CanActivateFn } from '@angular/router';
import { AuthService } from '../services/auth.service';

/**
 * Reason a navigation was turned away, passed to the login screen so it can explain itself.
 */
export type LoginRedirectReason = 'expired' | 'missing-tenant';

/**
 * Allows a navigation only for a session that is signed in, inside its time limits, and
 * carrying a tenant.
 *
 * The guard decides what gets rendered, nothing more. Data access is authorized independently
 * by Row Level Security, so bypassing this check still reaches no row of another organization.
 */
export const authGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);

  // A page reload restores the session asynchronously; without this wait, refreshing a
  // protected page would look exactly like being signed out.
  await auth.whenInitialized();

  if (!auth.session()) {
    return router.createUrlTree(['/login'], { queryParams: { returnUrl: state.url } });
  }

  // Navigation is the coarsest checkpoint the session limits have, and the only one an idle
  // user passes through, so the policy is re-evaluated here rather than trusted.
  if ((await auth.enforceSessionPolicy()) !== 'active') {
    return router.createUrlTree(['/login'], {
      queryParams: { returnUrl: state.url, reason: 'expired' satisfies LoginRedirectReason },
    });
  }

  // A token with no `organization_id` claim belongs to a collaborator whose profile is
  // missing or deactivated (migration 006). It satisfies no RLS policy, so there is nothing
  // such a session could legitimately do; it is ended rather than left half-usable
  // (spec.md edge case: "solicitud sin identificación de organización").
  if (!auth.organizationId() || !auth.role()) {
    await auth.signOut();
    return router.createUrlTree(['/login'], {
      queryParams: { reason: 'missing-tenant' satisfies LoginRedirectReason },
    });
  }

  auth.recordActivity();
  return true;
};
