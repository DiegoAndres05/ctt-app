import { Routes, type RedirectFunction } from '@angular/router';
import { authGuard } from './core/auth/guards/auth.guard';
import { passwordChangeGuard } from './core/auth/guards/password-change.guard';
import { roleGuard } from './core/auth/guards/role.guard';
import { unsavedChangesGuard } from './shared/components/unsaved-changes.guard';

/**
 * Application routing shells.
 *
 * Login and register are public. Mandatory password change is authenticated and has no
 * sidebar. Every other authenticated screen renders inside `AdminShellComponent`.
 * `roleGuard` still decides what is rendered; Row Level Security authorizes the data.
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
  // Public proposal link (feature 005): no shell, no authGuard — `get_public_quotation`
  // resolves the opaque token and returns no customer data (contracts §4 and §6).
  {
    path: 'q/:token',
    loadComponent: () =>
      import('./features/public-quotation/public-quotation.component').then(
        (m) => m.PublicQuotationComponent,
      ),
  },
];

const redirectParam =
  (prefix: string): RedirectFunction =>
  ({ params }) =>
    `${prefix}/${params['id']}`;

const protectedRoutes: Routes = [
  {
    path: 'change-password',
    canActivate: [authGuard, passwordChangeGuard],
    loadComponent: () =>
      import('./features/auth/change-password/change-password.component').then(
        (m) => m.ChangePasswordComponent,
      ),
  },
  {
    path: '',
    canActivate: [authGuard, passwordChangeGuard],
    loadComponent: () =>
      import('./shared/layout/admin-shell.component').then((m) => m.AdminShellComponent),
    children: [
      {
        path: 'dashboard',
        loadComponent: () =>
          import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent),
      },
      {
        path: 'sales',
        canActivate: [roleGuard('agent')],
        children: [
          { path: '', pathMatch: 'full', redirectTo: 'requests' },
          {
            path: 'requests',
            children: [
              {
                path: '',
                pathMatch: 'full',
                loadComponent: () =>
                  import('./features/sales/requests/request-list/request-list.component').then(
                    (m) => m.RequestListComponent,
                  ),
              },
              {
                path: 'new',
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/sales/requests/request-intake/request-intake.component').then(
                    (m) => m.RequestIntakeComponent,
                  ),
              },
              {
                path: ':id',
                loadComponent: () =>
                  import('./features/sales/requests/request-detail/request-detail.component').then(
                    (m) => m.RequestDetailComponent,
                  ),
              },
            ],
          },
          {
            path: 'pre-reservations',
            canActivate: [roleGuard('agent')],
            children: [
              {
                path: '',
                pathMatch: 'full',
                loadComponent: () =>
                  import('./features/sales/pre-reservations/pre-reservation-list/pre-reservation-list.component').then(
                    (m) => m.PreReservationListComponent,
                  ),
              },
              {
                path: 'new',
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/sales/pre-reservations/pre-reservation-create/pre-reservation-create.component').then(
                    (m) => m.PreReservationCreateComponent,
                  ),
              },
              {
                path: ':id',
                loadComponent: () =>
                  import('./features/sales/pre-reservations/pre-reservation-detail/pre-reservation-detail.component').then(
                    (m) => m.PreReservationDetailComponent,
                  ),
              },
            ],
          },
          {
            path: 'quotations',
            canActivate: [roleGuard('agent')],
            children: [
              {
                path: '',
                pathMatch: 'full',
                loadComponent: () =>
                  import('./features/sales/quotations/quotation-list/quotation-list.component').then(
                    (m) => m.QuotationListComponent,
                  ),
              },
              {
                path: 'new',
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/sales/quotations/quotation-editor/quotation-editor.component').then(
                    (m) => m.QuotationEditorComponent,
                  ),
              },
              {
                path: ':versionId',
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/sales/quotations/quotation-editor/quotation-editor.component').then(
                    (m) => m.QuotationEditorComponent,
                  ),
              },
            ],
          },
          {
            path: 'verification',
            canActivate: [roleGuard('operator')],
            loadComponent: () =>
              import('./features/sales/verification/verification-queue/verification-queue.component').then(
                (m) => m.VerificationQueueComponent,
              ),
          },
          {
            path: 'customers',
            children: [
              {
                path: '',
                pathMatch: 'full',
                loadComponent: () =>
                  import('./features/sales/customers/customer-list/customer-list.component').then(
                    (m) => m.CustomerListComponent,
                  ),
              },
              {
                path: ':id',
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/sales/customers/customer-detail/customer-detail.component').then(
                    (m) => m.CustomerDetailComponent,
                  ),
              },
            ],
          },
        ],
      },
      {
        path: 'settings',
        canActivate: [roleGuard('admin')],
        children: [
          {
            path: 'users',
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
                canDeactivate: [unsavedChangesGuard],
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
            path: 'roles',
            canActivate: [roleGuard('admin')],
            loadComponent: () =>
              import('./features/users/roles/roles-matrix.component').then(
                (m) => m.RolesMatrixComponent,
              ),
          },
          {
            path: 'audit',
            loadComponent: () =>
              import('./features/audit/audit-log/audit-log.component').then(
                (m) => m.AuditLogComponent,
              ),
          },
        ],
      },
      {
        path: 'cms',
        children: [
          {
            path: 'experiences',
            canActivate: [roleGuard('agent')],
            children: [
              {
                path: '',
                pathMatch: 'full',
                data: { productType: 'experience' },
                loadComponent: () =>
                  import('./features/catalog/products/product-list/product-list.component').then(
                    (m) => m.ProductListComponent,
                  ),
              },
              {
                path: 'new',
                canActivate: [roleGuard('operator')],
                canDeactivate: [unsavedChangesGuard],
                data: { productType: 'experience' },
                loadComponent: () =>
                  import('./features/catalog/products/product-editor/product-editor.component').then(
                    (m) => m.ProductEditorComponent,
                  ),
              },
              {
                path: ':id',
                canDeactivate: [unsavedChangesGuard],
                data: { productType: 'experience' },
                loadComponent: () =>
                  import('./features/catalog/products/product-editor/product-editor.component').then(
                    (m) => m.ProductEditorComponent,
                  ),
              },
            ],
          },
          {
            path: 'accommodations',
            canActivate: [roleGuard('agent')],
            children: [
              {
                path: '',
                pathMatch: 'full',
                data: { productType: 'accommodation' },
                loadComponent: () =>
                  import('./features/catalog/products/product-list/product-list.component').then(
                    (m) => m.ProductListComponent,
                  ),
              },
              {
                path: 'new',
                canActivate: [roleGuard('operator')],
                canDeactivate: [unsavedChangesGuard],
                data: { productType: 'accommodation' },
                loadComponent: () =>
                  import('./features/catalog/products/product-editor/product-editor.component').then(
                    (m) => m.ProductEditorComponent,
                  ),
              },
              {
                path: ':id',
                canDeactivate: [unsavedChangesGuard],
                data: { productType: 'accommodation' },
                loadComponent: () =>
                  import('./features/catalog/products/product-editor/product-editor.component').then(
                    (m) => m.ProductEditorComponent,
                  ),
              },
            ],
          },
          {
            path: 'packages',
            canActivate: [roleGuard('agent')],
            children: [
              {
                path: '',
                pathMatch: 'full',
                loadComponent: () =>
                  import('./features/catalog/packages/package-list/package-list.component').then(
                    (m) => m.PackageListComponent,
                  ),
              },
              {
                path: 'new',
                canActivate: [roleGuard('operator')],
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/catalog/packages/package-builder/package-builder.component').then(
                    (m) => m.PackageBuilderComponent,
                  ),
              },
              {
                path: ':id',
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/catalog/packages/package-builder/package-builder.component').then(
                    (m) => m.PackageBuilderComponent,
                  ),
              },
            ],
          },
          {
            path: 'settings',
            canActivate: [roleGuard('operator')],
            children: [
              {
                path: '',
                pathMatch: 'full',
                loadComponent: () =>
                  import('./features/catalog/catalog-settings/catalog-settings.component').then(
                    (m) => m.CatalogSettingsComponent,
                  ),
              },
              {
                path: 'categories',
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/catalog/categories/category-list.component').then(
                    (m) => m.CategoryListComponent,
                  ),
              },
              {
                path: 'public-categories',
                canDeactivate: [unsavedChangesGuard],
                loadComponent: () =>
                  import('./features/catalog/public-categories/public-categories.component').then(
                    (m) => m.PublicCategoriesComponent,
                  ),
              },
              {
                path: 'addons',
                children: [
                  {
                    path: '',
                    pathMatch: 'full',
                    loadComponent: () =>
                      import('./features/catalog/addons/addon-list/addon-list.component').then(
                        (m) => m.AddonListComponent,
                      ),
                  },
                  {
                    path: 'new',
                    canDeactivate: [unsavedChangesGuard],
                    loadComponent: () =>
                      import('./features/catalog/addons/addon-form/addon-form.component').then(
                        (m) => m.AddonFormComponent,
                      ),
                  },
                  {
                    path: ':id',
                    canDeactivate: [unsavedChangesGuard],
                    loadComponent: () =>
                      import('./features/catalog/addons/addon-form/addon-form.component').then(
                        (m) => m.AddonFormComponent,
                      ),
                  },
                ],
              },
              {
                path: 'cutover',
                canActivate: [roleGuard('admin')],
                loadComponent: () =>
                  import('./features/catalog/public-cutover/public-cutover.component').then(
                    (m) => m.PublicCutoverComponent,
                  ),
              },
            ],
          },
        ],
      },
      { path: 'users', pathMatch: 'full', redirectTo: '/settings/users' },
      { path: 'users/:id', redirectTo: redirectParam('/settings/users') },
      { path: 'audit', pathMatch: 'full', redirectTo: '/settings/audit' },
      { path: 'catalog', pathMatch: 'full', redirectTo: '/cms/experiences' },
      { path: 'catalog/products', pathMatch: 'full', redirectTo: '/cms/experiences' },
      { path: 'catalog/products/new', pathMatch: 'full', redirectTo: '/cms/experiences/new' },
      { path: 'catalog/products/:id', redirectTo: redirectParam('/cms/experiences') },
      { path: 'catalog/packages', pathMatch: 'full', redirectTo: '/cms/packages' },
      { path: 'catalog/packages/:id', redirectTo: redirectParam('/cms/packages') },
      { path: 'catalog/addons', pathMatch: 'full', redirectTo: '/cms/settings/addons' },
      { path: 'catalog/addons/:id', redirectTo: redirectParam('/cms/settings/addons') },
      {
        path: 'catalog/public-categories',
        pathMatch: 'full',
        redirectTo: '/cms/settings/public-categories',
      },
      { path: 'catalog/public-cutover', pathMatch: 'full', redirectTo: '/cms/settings/cutover' },
      { path: '', pathMatch: 'full', redirectTo: 'dashboard' },
    ],
  },
];

export const routes: Routes = [...publicRoutes, ...protectedRoutes, { path: '**', redirectTo: '' }];
