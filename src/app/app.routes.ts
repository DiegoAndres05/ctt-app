import { Routes } from '@angular/router';
import { authGuard } from './core/auth/guards/auth.guard';
import { passwordChangeGuard } from './core/auth/guards/password-change.guard';
import { roleGuard } from './core/auth/guards/role.guard';

/**
 * Application routing shells.
 *
 * The split below is the security boundary of the router: a route is either reachable
 * without a session or it is not, and there is no third category. Feature routes are
 * appended to one of the two arrays so that adding a screen forces that choice explicitly
 * rather than defaulting to "public".
 */

/**
 * Reachable without a session: login and public agency registration (T045).
 */
const publicRoutes: Routes = [
  {
    path: 'login',
    loadComponent: () =>
      import('./features/auth/login/login.component').then((m) => m.LoginComponent),
  },
  {
    path: 'register',
    loadComponent: () =>
      import('./features/auth/register/register.component').then((m) => m.RegisterComponent),
  },
];

/**
 * Requires an authenticated session with a tenant claim.
 *
 * Both guards hang off the shell, so every child inherits them and a new screen cannot forget
 * one; `roleGuard` is applied per route for the administration screens and the audit log.
 *
 * `change-password` sits inside the shell on purpose: it needs a session, and
 * `passwordChangeGuard` lets it through as the one destination reachable while the mandatory
 * change is pending.
 *
 * Guards only decide what to render. Data access is authorized independently by Row Level
 * Security, so a bypassed guard still cannot read another organization's rows.
 */
const protectedRoutes: Routes = [
  {
    path: '',
    canActivate: [authGuard, passwordChangeGuard],
    children: [
      {
        path: 'dashboard',
        loadComponent: () =>
          import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent),
      },
      {
        path: 'change-password',
        loadComponent: () =>
          import('./features/auth/change-password/change-password.component').then(
            (m) => m.ChangePasswordComponent,
          ),
      },
      {
        path: 'users',
        canActivate: [roleGuard('admin')],
        children: [
          {
            path: '',
            pathMatch: 'full',
            loadComponent: () =>
              import('./features/users/user-list/user-list.component').then(
                (m) => m.UserListComponent,
              ),
          },
          {
            path: 'new',
            loadComponent: () =>
              import('./features/users/user-create/user-create.component').then(
                (m) => m.UserCreateComponent,
              ),
          },
          {
            path: ':id',
            loadComponent: () =>
              import('./features/users/user-detail/user-detail.component').then(
                (m) => m.UserDetailComponent,
              ),
          },
        ],
      },
      {
        path: 'audit',
        canActivate: [roleGuard('admin')],
        loadComponent: () =>
          import('./features/audit/audit-log/audit-log.component').then((m) => m.AuditLogComponent),
      },
      { path: '', pathMatch: 'full', redirectTo: 'dashboard' },
    ],
  },
];

export const routes: Routes = [
  ...publicRoutes,
  ...protectedRoutes,
  // An unknown path is not a hint that something exists elsewhere: it lands on the protected
  // shell and is answered by the guards. The not-found screen arrives with T047.
  { path: '**', redirectTo: '' },
];
