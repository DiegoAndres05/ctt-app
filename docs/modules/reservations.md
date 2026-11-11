# Reservations (006-reservation-lifecycle)

Module that turns an **accepted** quotation into a confirmed reservation (`RSV-#####`),
records manual deposits, runs the operator lifecycle, versions date/passenger changes,
and exposes a hashed public voucher. The UI never sums money: it paints `paid_total` and
`balance` from `reservation_list`. There is no payment gateway and no outbound WhatsApp
or email.

**Spec**: `specs/006-reservation-lifecycle/`
**Plan**: `specs/006-reservation-lifecycle/plan.md`

## What lives where

| Concern | Location |
| --- | --- |
| Enums and audit event values | `supabase/migrations/049_reservation_enums.sql` |
| Tables, freeze trigger, RLS, `reservation_list`, receipts bucket | `supabase/migrations/050_reservations.sql` |
| Confirm + first/extra payment | `supabase/migrations/051_us1_confirm_reservation.sql` |
| Status transitions | `supabase/migrations/052_us2_reservation_lifecycle.sql` |
| Cancel and new version | `supabase/migrations/053_us3_cancel_and_version.sql` |
| Provider orders and public voucher | `supabase/migrations/054_us4_provider_orders_voucher.sql` |
| Voucher token base64url (fix D2, 2026-11-11) | `supabase/migrations/057_fix_voucher_token_base64url.sql` |
| SQL verification | `supabase/tests/reservation_rls_test.sql`, `reservation_confirm_test.sql`, `reservation_lifecycle_test.sql`, `reservation_changes_test.sql`, `service_orders_test.sql`, `reservation_public_voucher_test.sql`, `reservation_voucher_token_test.sql` |
| Domain models and services | `src/app/core/reservations/` |
| Panel UI | `src/app/features/sales/reservations/` |
| Public voucher | `src/app/features/public-voucher/` (`/r/:token`) |

## Entities

| Entity | Table | Notes |
| --- | --- | --- |
| Family | `reservation_families` | Locator `RSV-#####`, unique `quotation_version_id`, SHA-256 voucher hash. |
| Version | `reservation_versions` | One non-`superseded` version per family. Terminal: `completed`, `cancelled`. |
| Passengers | `reservation_passengers` | Count must match quotation party (adults + children). |
| Items | `reservation_items` | Snapshot of quotation lines plus ops status per provider. |
| Payments | `reservation_payments` | Append-only, on the family. |

`reservation_list` is `security_invoker` and excludes email, phone, token and documents.
`anon` has no `SELECT` on tables or the view.

## RPCs

| RPC | Who | Behavior |
| --- | --- | --- |
| `confirm_reservation` | member | Calls `assert_quotation_confirmable` (005/048). Returns voucher token once: 32 random bytes in base64url without padding (43 chars, `[A-Za-z0-9_-]`, since 057); only its SHA-256 is stored. |
| `record_reservation_payment` | member | Extra deposit; `CURRENCY_MISMATCH` / `DEPOSIT_REQUIRED`. |
| `transition_reservation_status` | operator/admin | `confirmed` → `in_progress` → `completed`. |
| `cancel_reservation` | member; `in_progress` needs admin + contingency | Reason 1–500. |
| `create_reservation_version` | member | New version; previous `superseded`; payments stay on the family. |
| `mark_provider_order_sent` / `reassign_reservation_item_provider` | operator/admin | Copy-only notify; reassignment resets to `pending_provider`. |
| `reservation_provider_order_text` | operator/admin | No sale prices, no other providers. |
| `reservation_whatsapp_text` | member | Copy body; no API send. |
| `get_public_voucher` | `anon` + authenticated | Hash lookup; `{ available: false }` if unknown/voided. |
| `void_reservation_voucher` / `rotate_reservation_voucher` | admin | Rotate returns a new clear token once (base64url since 057) and revokes the previous one. Tokens issued before 057 are standard base64 and still resolve, but only through a percent-encoded link (`publicVoucherUrl` uses `encodeURIComponent`). |

## State machine

```
confirmed → in_progress → completed
confirmed → cancelled
in_progress → cancelled (admin + informe)
any open version → superseded (new version)
```

## Boundary with 005

006 does not reopen quotations. It only confirms `accepted` versions via
`assert_quotation_confirmable`. The quotation editor links «Confirmar reserva» when
status is `accepted`.

## Routes

| Path | Who | Screen |
| --- | --- | --- |
| `/sales/reservations` | agent+ | List |
| `/sales/reservations/new?quotationVersionId=` | agent+ | Confirm |
| `/sales/reservations/:id` | agent+ | Detail |
| `/r/:token` | public | Voucher |

## Seed

`supabase/seed.sql` verifies Laura Gómez's PRE-00002, then issues and accepts `COT-00001` as the demo operator. It does **not** call `confirm_reservation`, so `/sales/reservations/new?quotationVersionId=` can still confirm. Idempotent if an accepted version already exists.

## Quickstart mapping

Pass of 2026-10-22 (after seed change + `db reset`). SQL: six 006 suites previously green. Browser as `operador@demo-turismo.test`.

| Scenario | Result |
| --- | --- |
| 1 Confirm | SQL + browser: COT-00001 · 2 pax · depósito 1 001 900 COP → `RSV-00001` y token de voucher una vez. |
| 2 Lifecycle | SQL. Browser: detalle `RSV-00001` muestra «Pasar a en ejecución»; no se pulsó (control bloqueado a mitad de la pasada). |
| 3–4 Cancel / version | SQL. Browser: secciones «Cancelar» y «Nueva versión (fechas)» visibles; no se enviaron. |
| 5 Provider orders | SQL. Browser: «Copiar orden» / «Marcar enviada» en Islas Capri Premium. |
| 6 Public voucher | SQL + `/r/invalid-token`. Tras confirmar, el detalle muestra el enlace `/r/<token>` (`encodeURIComponent`). |
| 7 Extra payment | SQL. Browser: formulario «Abono extra» con saldo pintado por el servidor; no se subió comprobante. |
