# Data Model: 006-reservation-lifecycle

**Feature**: 006-reservation-lifecycle  
**Date**: 2026-10-22  
**Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

Migraciones desde `049_`. 005 termina en `048`. No editar `042`–`048`.

## Enums

| Enum | Values |
|------|--------|
| `reservation_status` | `confirmed`, `in_progress`, `completed`, `cancelled`, `superseded` |
| `reservation_item_ops_status` | `pending_provider`, `confirmed_with_provider`, `in_service`, `completed`, `provider_failed` |
| `payment_method` | `bank_transfer`, `cash`, `card_manual`, `other` |
| `id_document_type` | `cc`, `ce`, `passport`, `ti`, `other` |
| `provider_notify_channel` | `whatsapp_copy`, `email_copy`, `print` |

Audit (ampliar `audit.audit_event_type`): `reservation_confirmed`, `reservation_status_changed`, `reservation_cancelled`, `reservation_version_created`, `reservation_payment_recorded`, `reservation_provider_notified`, `reservation_item_reassigned`, `reservation_voucher_voided`.

## Tables

### `reservation_families`

Identity of the trip. One row per confirmed quotation version.

| Column | Type | Notes |
|--------|------|--------|
| `id` | uuid PK | |
| `organization_id` | uuid NOT NULL | FK organizations |
| `reference` | text NOT NULL | `RSV-#####`, unique per org |
| `quotation_version_id` | uuid NOT NULL | FK `quotation_versions`; **UNIQUE** |
| `quotation_family_id` | uuid NOT NULL | denormalized from 005 |
| `pre_reservation_id` | uuid NOT NULL | snapshot |
| `customer_id` | uuid NOT NULL | titular |
| `voucher_token_hash` | bytea | SHA-256; null after void until rotated |
| `created_at` | timestamptz | |
| `created_by` | uuid | |

`organization_id` + `reference` unique. `anon` sin SELECT.

### `reservation_versions`

Mutable operational record. One open version (`status` not in `superseded`).

| Column | Type | Notes |
|--------|------|--------|
| `id` | uuid PK | |
| `organization_id` | uuid | |
| `family_id` | uuid | |
| `version_number` | int | 1..n |
| `status` | `reservation_status` | |
| `currency` | existing money enum | copied from quotation |
| `total` | numeric(14,2) | frozen from `assert_quotation_confirmable` |
| `travel_start_date` | date | min line start (version 1) or new dates |
| `travel_end_date` | date | max line end |
| `party_adults` / `party_children` | int | frozen then replaced on new version |
| `terms` | text | copy of quotation terms at confirm |
| `assistance_phones` | text | org phones at confirm, 1–200 |
| `contingency_report` | text | required when cancelling `in_progress` |
| `cancelled_at` / `cancel_reason` | | |
| `status_changed_at` / `status_changed_by` | | |
| `created_at` / `created_by` | | |

Partial unique: one non-superseded version per family.

Trigger: `completed` and `cancelled` reject money/date/passenger mutations (`RESERVATION_FROZEN`). `superseded` is immutable.

### `reservation_passengers`

| Column | Notes |
|--------|--------|
| `id`, `organization_id`, `version_id` | |
| `first_name`, `last_name` | 1–120 |
| `document_type` | enum |
| `document_number` | 1–40 |
| `date_of_birth` | date, optional |
| `special_requirements` | ≤ 500, optional |
| `position` | order |

No UPDATE/DELETE except via replacing the whole version (delete only in the same transaction that supersedes — prefer insert-only on new versions; old passengers stay on old versions).

### `reservation_items`

Copied from quotation lines (+ provider from pre-reservation item when present).

| Column | Notes |
|--------|--------|
| `quotation_line` snapshot fields | product/addon, dates, pax, quantity, `line_total` (needed for agency, **not** in provider text) |
| `provider_id` | nullable; reassignable |
| `ops_status` | enum |
| `provider_notified_at` | |
| `provider_notify_channel` | |
| `reassign_reason` | last reason, 1–500 |

### `reservation_payments`

Append-only. `UPDATE`/`DELETE`/`TRUNCATE` rejected (reuse `reject_request_note_mutation` or sibling trigger).

| Column | Notes |
|--------|--------|
| `amount` | > 0, same currency as version |
| `currency` | |
| `paid_on` | date, not future (Bogotá) |
| `method` | enum |
| `transfer_reference` | 1–80 |
| `receipt_path` | optional storage object key |
| `recorded_by` | uuid |
| `created_at` | |

`paid_total` and `balance` are computed in RPCs/views, not stored (avoids drift). View `reservation_list` exposes them.

## Views

`reservation_list` (`security_invoker`): reference, current version, status, customer display name (no email/phone), travel dates, currency, total, paid_total, balance, quotation reference. `anon` without privileges.

`reservation_item_orders` (optional helper): per-item fields for the operator, still RLS'd; provider RPC returns a **filtered** jsonb without other providers' rows and without `line_total`.

## State transitions (version)

See [research.md](./research.md) §4. Implemented in `transition_reservation_status` and `cancel_reservation`.

## Relationships

```
quotation_versions (accepted)
        │ 1
        │ confirm_reservation
        ▼
reservation_families 1──n reservation_versions
                          ├── n reservation_passengers
                          ├── n reservation_items
                          └── n reservation_payments  (tied to family or current version; tie to family so payments survive versioning)
```

**Payments belong to the family**, not the version: money already received stays if dates change.

## Validation rules

| Code | Rule |
|------|------|
| `QUOTATION_NOT_ACCEPTED` | from 005 boundary |
| `RESERVATION_ALREADY_EXISTS` | unique quotation_version_id |
| `DEPOSIT_REQUIRED` | first payment amount ≤ 0 or missing |
| `CURRENCY_MISMATCH` | payment currency ≠ snapshot |
| `PASSENGER_COUNT_MISMATCH` | passenger rows ≠ adults+children |
| `INVALID_TRANSITION` | illegal status move |
| `ADMIN_REQUIRED` | cancel in_progress, or void voucher |
| `CONTINGENCY_REQUIRED` | cancel in_progress without report |
| `RESERVATION_FROZEN` | mutate terminal/superseded |
| `VALIDATION_ERROR` | nulls, dates, text lengths |

## RLS

All tables: `organization_id = jwt org`. SELECT for members; writes only through RPCs (`SECURITY DEFINER`, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE` to `authenticated` except `get_public_voucher` → `anon` + `authenticated`).
