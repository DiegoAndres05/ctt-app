# Validation evidence: 001-auth-tenant-access (T048–T050)

**Date**: 2026-09-08
**Environment**: local PostgreSQL 17 harness (`./supabase/tests/run-sql-tests.sh`) + Angular 22 unit suite (`npm test`). No live Supabase project or browser session was available; UI flows were verified by code review and unit tests, not by clicking through `ng serve`.

---

## T048 — Quickstart scenarios

| # | Scenario | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Registro de nueva agencia | PASS (database + wiring) | `us5_register_agency_test.sql`: org slug `agencia-nueva-turismo`, founding admin with `role = admin` and `must_change_password = false`, `organization_created` + `user_created`. Duplicate email → `EMAIL_ALREADY_EXISTS`. Colliding slug → `AGENCY_SLUG_EXISTS` with no partial profile. `anon` / `authenticated` cannot execute the RPC; `service_role` can. Edge Function `register-agency` creates the auth user, calls the RPC, deletes the auth user on RPC failure, and maps contract codes. `RegisterComponent` + `AuthService.registerAgency` consume that contract. Browser submit against a live stack was not executed. |
| 2 | Login y logout | PASS (automated subset) | `us1_auth_functions_test.sql` records `login_success` / `logout` via `password_verification_hook` and `record_session_end`. JWT claim shape (`organization_id`, `app_role`, reserved `role` = `authenticated`) is what RLS tests set and what `custom_access_token_hook` injects (ADR-0002). `AuthService.signIn` / `signOut` and `LoginComponent` implement the UI. DevTools JWT inspection was not run. |
| 3 | Aislamiento multi-tenant | PASS | `rls_isolation_test.sql` (SC-002): Alpha cannot list, fetch-by-id, update or delete Beta rows in `organizations`, `user_profiles`, `audit_events`. Missing `organization_id` claim reads nothing. `anon` has no table privilege. |
| 4 | RBAC | PASS | `us3_user_management_test.sql`: agent/operator → `INSUFFICIENT_PERMISSIONS` on create/role/status; admin can provision, change role immediately, deactivate. `role.guard.spec.ts`: admin inherits operator/agent; operator/agent denied on admin routes. |
| 5 | Contraseña temporal | PASS | `us1_auth_functions_test.sql`: collaborator cannot clear `must_change_password` on their own row; `change_password` is the only path that clears it after proving the current secret; other sessions are dropped. `passwordChangeGuard` intercepts navigation. |
| 6 | Bloqueo por intentos fallidos | PASS | `us1_auth_functions_test.sql`: fifth failure locks 15 minutes; correct password rejected while locked; expired lock then succeeds; `account_locked` / `account_unlocked` / `login_success`. Hook is not executable by `authenticated`. |
| 7 | Auditoría inmutable | PASS | `audit_immutability_test.sql`: UPDATE/DELETE/TRUNCATE rejected for table owner and authenticated admin, with the specified exception message. Non-admins read zero rows. |

---

## T049 — Security review

Checked against Default Deny, server-side claims, and no hardcoded secrets.

| Check | Result |
| --- | --- |
| RLS enabled at table creation; `anon` revoked | `002`, `003`, `004`, `005`. Isolation suite confirms empty reads without a tenant claim. |
| Application role in `app_role`, never `role` | `006_create_auth_hook.sql` writes `app_role`. Grep of `jwt() ->> 'role'` in SQL is empty. Frontend uses `APP_ROLE_CLAIM`. |
| Claims injected server-side | `custom_access_token_hook` granted only to `supabase_auth_admin`. Browser only decodes the token for display. |
| `register_agency` not callable by `anon`/`authenticated` | Migration 010 + US5 suite. Edge Function uses `SUPABASE_SERVICE_ROLE_KEY` from the runtime env, never from `src/`. |
| No service-role key in the frontend | Grep of `src/**/*.ts` for `service_role` / `SUPABASE_SERVICE` is empty. `environment*.ts` hold URL/anon placeholders only. |
| No hardcoded JWTs / secrets | Grep for `eyJ…` in app source is empty. Seed passwords exist only in `supabase/seed.sql`, labeled local-only. |
| Audit immutability | Trigger + privilege revoke; suite 7. |
| Credential hashing | Admin API / `change_password` / `create_internal_user` write bcrypt into `auth.users.encrypted_password`. Edge Function does not log the password. |

Residual (already in ADR-0003): 8h/24h session limits are enforced in the browser as defence-in-depth; RLS and token expiry remain the server boundary.

---

## T050 — Performance (SC-003 / SC-004)

**Method**

- Auth / onboarding RPC: `clock_timestamp()` around `public.register_agency` in `performance_probe_test.sql` on PostgreSQL 17 in Docker. This is the database half of registration; GoTrue `signInWithPassword` is not in the harness.
- Audit persist: `clock_timestamp()` around `audit.log_event` in the same probe.
- Session check: `SessionActivityStore.check()` × 10 000 in `session.interceptor.spec.ts` (in-memory; this is the actual implementation used by the interceptor, fetch gate and `authGuard`).

**Results (2026-09-08, local Docker / Vitest)**

| Operation | Budget | Measured | Verdict |
| --- | --- | --- | --- |
| `register_agency` (auth/onboarding path in DB) | < 2000 ms | **9.793 ms** (full-suite run; 18.711 ms on a prior isolated run) | PASS |
| `audit.log_event` | < 500 ms | **0.520 ms** (full-suite run; 1.323 ms on a prior isolated run) | PASS |
| Session clock evaluation (`check` × 10 000) | < 500 ms for a check | 10 000 iterations finished under 500 ms (suite `evaluates the session clocks well under the 500ms budget`) | PASS |

End-to-end HTTP login against a hosted Supabase project was not measured.

---

## Frontend quality gates

| Command | Outcome |
| --- | --- |
| `npm run lint` | Pass |
| `npm run format:check` | Pass |
| `npm test` | 4 files, 26 tests pass |
| `npm run build` | Pass, with budget **warning**: initial bundle 504.15 kB vs 500 kB (`maximumWarning`). Not an error. |
