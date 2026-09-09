import { inject } from '@angular/core';
import { Router, type CanActivateFn } from '@angular/router';
import { AuthService } from '../services/auth.service';

/** The one destination a collaborator holding a temporary password may reach. */
export const CHANGE_PASSWORD_PATH = '/change-password';

/**
 * Holds a collaborator on the change-password screen until they have retired the temporary
 * password an administrator assigned them (FR-006, research.md R-007).
 *
 * Only navigation is blocked. The flag itself is cleared exclusively by the `change_password`
 * database function, which will not do so without the current password, so a collaborator who
 * works around this guard still cannot get out of the mandatory change.
 */
export const passwordChangeGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);

  await auth.whenInitialized();

  // Whether an anonymous visitor may be here is `authGuard`'s decision, not this one's.
  if (!auth.session() || !auth.mustChangePassword()) {
    return true;
  }

  return state.url.startsWith(CHANGE_PASSWORD_PATH)
    ? true
    : router.createUrlTree([CHANGE_PASSWORD_PATH]);
};
