# Identity & Access (001-auth-tenant-access)

Module that authenticates internal collaborators, isolates every row by organization,
enforces hierarchical RBAC, and records an immutable security audit trail.

**Spec**: `specs/001-auth-tenant-access/`
**ADRs**: `docs/adr/0001-signal-forms-over-reactive-forms.md`,
`docs/adr/0002-jwt-app-role-claim.md`,
`docs/adr/0003-server-side-credential-and-lockout-enforcement.md`

## What lives where

| Concern | Location |
| --- | --- |
| Schema, RLS, Auth Hooks, RPCs | `supabase/migrations/` |
| Public agency onboarding | `supabase/functions/register-agency/` |
| SQL verification (RLS, US1, US3, US4, US5, perf) | `supabase/tests/` |
| Session, guards, identity | `src/app/core/auth/` |
| Audit query surface | `src/app/core/audit/` |
| Login / register / change-password | `src/app/features/auth/` |
| Collaborator admin UI | `src/app/features/users/` |
| Audit viewer | `src/app/features/audit/` |
| Shared banners and spinners | `src/app/shared/components/` |

## Security invariants (do not regress)

- Application role travels in the JWT claim `app_role`, never in `role` (ADR-0002).
- Row Level Security is the authorization boundary. Angular guards only decide what to render.
- Passwords are hashed and stored by Supabase Auth (`auth.users.encrypted_password`). The
  browser never persists them. `change_password` and collaborator provisioning hash with
  bcrypt in PostgreSQL using the same column (ADR-0003, FR-007).
- `register_agency` is executable only by `service_role`. The public form calls the Edge
  Function, which creates the auth user, invokes the RPC, and deletes the auth user if the
  RPC fails.
- `must_change_password` is not self-writable. Only `change_password` clears it for a
  collaborator; the founding admin is created with the flag already false.
- Audit rows cannot be updated, deleted or truncated. Appends go through `audit.log_event`.
- The service role key is never referenced from `src/`. Environment files hold the public
  anon key only.

## Local commands

```bash
npm install
npm start                          # Angular on http://127.0.0.1:4200
./supabase/tests/run-sql-tests.sh  # PostgreSQL 17 harness (Docker)
npm test && npm run lint && npm run format:check && npm run build
```

Public routes: `/login`, `/register`. Mandatory password change is `/change-password`
and has no sidebar. Everything else requires a session with `organization_id` and
`app_role` in the access token and renders inside the admin shell.

## Admin layout (010)

| Path | Who | Screen |
| --- | --- | --- |
| `/dashboard` | any collaborator | Greeting; indicators come later |
| `/sales/requests` | any collaborator | Request inbox |
| `/sales/requests/new` | any collaborator | Assisted request intake |
| `/sales/requests/:id` | any collaborator | Request detail |
| `/sales/customers` | any collaborator | Customer directory |
| `/sales/customers/:id` | any collaborator | Customer profile |
| `/sales/pre-reservations` | any collaborator | Pre-reservation list |
| `/sales/pre-reservations/new` | any collaborator | Pre-reservation create (from a request) |
| `/sales/pre-reservations/:id` | any collaborator | Pre-reservation detail |
| `/sales/verification` | operator and above | Availability verification queue |
| `/sales/quotations` | agent and above | Quotation list |
| `/sales/quotations/new` | agent and above | Quotation draft create (`?preReservationId=`) |
| `/sales/quotations/:versionId` | agent and above | Quotation detail / editor |
| `/q/:token` | public, no session | Client quotation view, outside the shell |
| `/settings/users` | admin | Collaborator list (`?q&page&role&status`) |
| `/settings/roles` | admin | Read-only role matrix |
| `/settings/audit` | admin | Audit log |
| `/change-password` | session | No sidebar |

`/users` and `/audit` redirect to the settings paths. Last access on the user list is the
latest `login_success` in `audit.audit_events`, not a new column. `/q/:token` (quotation
proposals, feature 005) is public like `/login`: no session, no sidebar, no `authGuard`;
it renders outside the admin shell.

## Onboarding flow (US5)

1. `RegisterComponent` posts `{ agency_name, full_name, email, password }` to
   `register-agency`.
2. The Edge Function creates the user via the Admin API (`email_confirm: true`).
3. It calls `public.register_agency(p_agency_name, p_admin_user_id, p_full_name, p_email)`.
4. On RPC failure it deletes the auth user and returns `EMAIL_ALREADY_EXISTS`,
   `AGENCY_SLUG_EXISTS`, `VALIDATION_ERROR` or `REGISTRATION_FAILED`.
5. On success it signs the founder in (so `custom_access_token_hook` injects claims and
   `password_verification_hook` records `login_success`) and returns the session.
6. `AuthService.registerAgency` installs that session and navigates to `/dashboard`.
