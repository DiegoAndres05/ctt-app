# Pre-Reservations & Availability (004-prereservation-availability)

Module that turns customer requests into pre-reservations and runs the human availability
verification queue with providers. A pre-reservation is an operational grouping of service
lines to verify — never a booking, never an inventory hold, never a price. Feature 005
quotes only what this module declares eligible.

**Spec**: `specs/004-prereservation-availability/`
**Plan**: `specs/004-prereservation-availability/plan.md`

## What lives where

| Concern | Location |
| --- | --- |
| Enums, tables, RLS, views, RPCs | `supabase/migrations/035_…` … `041_…` |
| SQL verification | `supabase/tests/pre_reservation_core_test.sql`, `pre_reservation_rls_test.sql`, `availability_verification_test.sql`, `pre_reservation_consolidation_test.sql`, `verification_traceability_test.sql` |
| Domain models and services | `src/app/core/pre-reservations/` |
| Panel UI | `src/app/features/sales/pre-reservations/`, `src/app/features/sales/verification/` |
| "Totally verified" shell notice | `src/app/shared/layout/verified-notice/` |
| Demo data | `supabase/seed.sql` (idempotent block for the demo tenant) |

## Entities

| Entity | Table | Notes |
| --- | --- | --- |
| Pre-Reservation | `pre_reservations` | Reference `PRE-#####` per organization. Responsible agent plus optional assigned operator. Status is derived (see below); only `cancelled` is manual and terminal. `expires_at` is the nearest provider hold among available main lines. |
| Pre-reservation item | `pre_reservation_items` | Main or alternative line. Product XOR add-on, provider snapshot (from the product's provider or written manually), dates, passengers, quantity. Dates, product and passengers are immutable: lines are withdrawn and added, never edited in place. |
| Verification event | `availability_verification_events` | Append-only history per line: start, each outcome, withdrawals, promotions, cancellation, quotation override. Stores provider contact data and notes, never traveler PII. |

Views (all `security_invoker`, `anon` without privileges): `pre_reservation_list` and
`availability_verification_queue` (`036`), `availability_verification_history` and
`pre_reservation_verification_times` (`041`).

## RPCs

| RPC | Who | Behavior |
| --- | --- | --- |
| `create_pre_reservation` | authenticated member | Converts a `received`/`in_review` request (or adds another pre-reservation to one already in `pre_reservation`) atomically via `create_pre_reservation_core`. Discarded requests and anonymized customers are rejected. |
| `cancel_pre_reservation` | authenticated member | Requires a 1–500 reason. Terminal; the source request keeps its status. |
| `assign_pre_reservation_operator` | authenticated member | Assigns or clears an active operator/admin. |
| `start_item_verification` | operator or admin | Idempotent first start; auto-assigns the caller as operator. |
| `record_item_verification` | operator or admin | Records `available` / `unavailable` / `alternative_suggested` with contact person, method, hold expiry, suggestion and notes; recalculates the global status. |
| `add_pre_reservation_item` | authenticated member | Adds a main or alternative line; a main line clears any quotation override. |
| `withdraw_pre_reservation_item` | authenticated member | Withdraws a main line with its active alternatives, reason required; never leaves zero main lines. |
| `promote_alternative_item` | authenticated member | Retires the original main line ("Reemplazada por alternativa") and promotes the alternative. |
| `expire_due_pre_reservations` | authenticated member | Idempotent tenant sweep of overdue holds; returns how many pre-reservations changed. |
| `authorize_quotation_override` | admin only | Reason required; audited without the reason. Invalidated by any main-line change. |
| `assert_pre_reservation_quotable` | internal (feature 005) | See "Quote eligibility" below. |

`create_pre_reservation_core`, `refresh_pre_reservation_status`,
`resolve_pre_reservation_item`, `insert_pre_reservation_item`, `log_availability_event`
and `require_availability_verifier` are internal: `anon` and `authenticated` cannot
execute them. All RPCs are `SECURITY DEFINER` with `set search_path = ''`.

## State machine

Six states: `pending_verification` (Pendiente de verificación),
`partially_verified` (Parcialmente verificada), `verified` (Totalmente verificada),
`requires_adjustment` (Requiere Ajuste), `expired` (Expirada), `cancelled` (Cancelada).

Every state except `cancelled` is derived by `refresh_pre_reservation_status` from the
active main lines, with the precedence of FR-006: **expired** (an available line with an
overdue hold) > **requires_adjustment** (any line `unavailable` or
`alternative_suggested`) > **verified** (all lines `available`) > **partially_verified**
(some line `available`) > **pending_verification**. `cancelled` is manual, requires a
reason and is terminal. Alternative lines are verified the same way but never count
towards the global status. Entering `verified` sets `verified_at` and the one-time
`first_verified_at`, and raises the in-panel notice for the responsible agent (Realtime,
with a 30-second polling fallback).

There is no "set status" RPC and the panel never recomputes state in TypeScript: the UI
only reads `status` and `quote_eligible`.

## Quote eligibility (contract for feature 005)

A pre-reservation is eligible for a binding quote only when it is `verified`, or when an
admin exception (`quote_override_at/by/reason`, all-or-nothing) is in force — the
exception is cleared whenever a main line is added, withdrawn or promoted. `cancelled` is
never eligible; `expired` is eligible only while an exception stands.

Feature 005 must call `assert_pre_reservation_quotable(organization_id,
pre_reservation_id)` inside its quotation-creation RPC. It refreshes first, then returns
`{eligible: true, basis: 'verified' | 'override', status, expires_at}`. When not eligible
it raises `PRE_RESERVATION_CLOSED`, `PRE_RESERVATION_EXPIRED` or
`PRE_RESERVATION_NOT_VERIFIED`; a missing or foreign pre-reservation is
`VALIDATION_ERROR`. `expires_at` is the validity cap for the quote.

## Expiry sweep

Holds are provider-imposed time limits recorded on available lines. There is no cron:
`PreReservationService.sweepExpired()` calls `expire_due_pre_reservations()` before list
and detail reads (a failure only logs a warning; the read continues), and the queue
view flags `hold_expired` rows. A hold in the past is rejected at recording time
(`HOLD_EXPIRY_IN_PAST`). Re-verifying with a future hold recomputes `expires_at`.
Without holds a pre-reservation never expires.

## RBAC

| Action | Agent | Operator | Admin |
| --- | --- | --- | --- |
| Read pre-reservations and the queue data of the tenant | Yes | Yes | Yes |
| Create, adjust and cancel pre-reservations | Yes | Yes | Yes |
| Open `/sales/verification`, start verification, record outcomes | No | Yes | Yes |
| Authorize the quotation exception | No | No | Yes |

`roleGuard` only hides routes. RLS (tenant `SELECT`) and the RPCs are the authorization
boundary: the tables are SELECT-only for `authenticated`, and the verification RPCs
require an active operator/admin profile.

## Security invariants (do not regress)

- RLS is by `organization_id`. `anon` has no access. Authenticated roles cannot insert,
  update or delete `pre_reservations`, `pre_reservation_items` or
  `availability_verification_events` directly.
- `availability_verification_events` is append-only: `UPDATE`, `DELETE` and `TRUNCATE`
  are rejected even for superusers.
- Identity fields are immutable at the database level (`request_id`, `reference`,
  dates, product, passengers): changing them raises `VALIDATION_ERROR` even as a
  superuser. Lines are withdrawn and added instead.
- Audit metadata records ids, statuses and counts. It does not record cancellation
  reasons, override reasons, provider contact names or traveler PII; reasons travel in
  the events table `notes` column.
- The queue and history views expose the traveler's first and last name only — never
  `email` or `phone_e164`.
- All writes go through `SECURITY DEFINER` RPCs with `set search_path = ''` that raise
  contract codes; a missing or foreign row answers `VALIDATION_ERROR`.
- The service role key is never referenced from `src/`.

## Routes

| Path | Who | Screen |
| --- | --- | --- |
| `/sales/pre-reservations` | any collaborator | Pre-reservation list |
| `/sales/pre-reservations/new` | any collaborator | Create from a request (`?requestId=`) |
| `/sales/pre-reservations/:id` | any collaborator | Pre-reservation detail |
| `/sales/verification` | operator and above | Availability verification queue |

Navigation sits inside Comercial: Pre-reservas (all roles), Verificación (hidden from
agents).

## Quickstart mapping

Scenarios 1–7 of `specs/004-prereservation-availability/quickstart.md` have **not** been
run in the browser yet; the browser column is completed by the manual validation pass.

| Scenario | Automated evidence | Browser |
| --- | --- | --- |
| 1. Request → pre-reservation conversion | `pre_reservation_core_test.sql` | Not verified |
| 2. Verification queue and "available" outcome | `availability_verification_test.sql` | Not verified |
| 3. Consolidation, alternatives, realtime notice | `pre_reservation_consolidation_test.sql` (Realtime notice is manual) | Not verified |
| 4. Expiry by hold | `pre_reservation_consolidation_test.sql` (`expire_due_pre_reservations`) | Not verified |
| 5. Quotation exception | `pre_reservation_consolidation_test.sql` | Not verified |
| 6. Cancellation, immutability, privacy | `pre_reservation_rls_test.sql`, `verification_traceability_test.sql` | Not verified |
| 7. History and verification times | `verification_traceability_test.sql` | Not verified |

The realtime "totally verified" notice (`PreReservationRealtimeService`,
`VerifiedNoticeComponent`) and the 30-second polling fallback are TypeScript and are not
covered by the SQL harness.
