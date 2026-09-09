import { inject } from '@angular/core';
import { Router, type CanActivateFn } from '@angular/router';
import { hasRoleAtLeast, type AppRole } from '../models/user.model';
import { AuthService } from '../services/auth.service';

/**
 * Allows a navigation only when the session's application role ranks at least `required`.
 *
 * Hierarchy is Admin > Operator > Agent (`ROLE_RANK` in `user.model.ts`). The guard decides
 * what gets rendered. Data access is authorized independently by Row Level Security and by
 * the admin-only RPCs, so bypassing this check still cannot create users or rewrite roles.
 */
export function roleGuard(required: AppRole): CanActivateFn {
  return async () => {
    const auth = inject(AuthService);
    const router = inject(Router);

    await auth.whenInitialized();

    if (!hasRoleAtLeast(auth.role(), required)) {
      return router.createUrlTree(['/dashboard'], { queryParams: { denied: '1' } });
    }

    return true;
  };
}
