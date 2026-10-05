# Customers & Requests (003-customer-requests-channels)

Module that owns traveler profiles and multichannel requests (web, WhatsApp, phone, in person).
The external site submits through one RPC. WhatsApp arrives only after the Edge Function
checks the Meta signature. The panel never stores provider secrets.

**Spec**: `specs/003-customer-requests-channels/`
**Plan**: `specs/003-customer-requests-channels/plan.md`

## What lives where

| Concern | Location |
| --- | --- |
| Enums, tables, RLS, RPCs | `supabase/migrations/028_…` … `034_…` |
| WhatsApp webhook | `supabase/functions/whatsapp-inbound/` |
| Local webhook simulation | `scripts/simulate-whatsapp-inbound.sh` |
| SQL verification | `supabase/tests/customer_intake_core_test.sql`, `customer_requests_rls_test.sql`, `public_request_intake_test.sql`, `whatsapp_intake_test.sql`, `request_workflow_test.sql`, `customer_privacy_test.sql` |
| Domain models and services | `src/app/core/customers/` |
| Panel UI | `src/app/features/sales/` |

## Entities

| Entity | Table | Notes |
| --- | --- | --- |
| Customer | `customers` | One traveler profile per organization. Email and phone are unique among non-anonymized rows. |
| Request | `customer_requests` | Reference `SOL-#####`. Channel and customer are immutable. |
| Request item | `customer_request_items` | Catalog product and/or free text. |
| Sequence | `organization_sequences` | Per-tenant counters. No policies; `anon` and `authenticated` have no privileges. |
| Channel connection | `channel_connections` | Maps a Meta `phone_number_id` to a tenant. No secrets. |
| Inbound message | `inbound_messages` | WhatsApp messages. Scrubbed by anonymization, otherwise append-only. |
| Note | `request_notes` | Internal, append-only, not scrubbed. |

`customer_request_list` and `customer_list` are `security_invoker` views. `anon` cannot select them.

## RPCs

| RPC | Who | Behavior |
| --- | --- | --- |
| `submit_public_request` | `anon`, authenticated | Public web intake. Returns only `{reference, deduplicated}`. |
| `create_assisted_request` | Authenticated member | WhatsApp, phone, or in person. Assigns the caller. |
| `ingest_whatsapp_webhook` | `service_role` only | Parses a verified Meta payload. |
| `update_customer` | Authenticated member | Full replace of editable profile fields. |
| `assign_request` | Authenticated member | Assigns or clears the collaborator. |
| `set_request_status` | Authenticated member | `received → in_review`, or either open state → `discarded` with a reason. |
| `add_request_note` | Authenticated member | Appends one note to a request or a customer. |
| `anonymize_customer` | Admin | Clears traveler PII and customer-authored text. |

`capture_request_core`, `match_or_create_customer`, and the normalizers are not executable by `anon` or `authenticated`.

## Public web contract

The site calls `submit_public_request(organization_id, payload)` with the anon key.

```ts
const { data, error } = await supabase.rpc('submit_public_request', {
  p_organization_id: organizationId,
  p_payload: {
    privacy_consent: true,
    idempotency_key: idempotencyKey, // one UUID per form mount
    contact: { first_name, last_name, email, phone, country_code },
    items: [{ public_slug, quantity }],
    interest_text,
    special_requirements,
    travel_start_date,
    travel_end_date,
    adults,
    children,
    locale,
    source_page,
    website: '', // honeypot; must stay empty
  },
});
```

`privacy_consent: true` is required. Generate `idempotency_key` once per mount and reuse it on retry. A repeated key, or the same content within two minutes, returns the existing `reference` with `deduplicated: true`.

Error messages are stable codes: `CONSENT_REQUIRED`, `CONTACT_REQUIRED`, `INVALID_EMAIL`, `INVALID_PHONE`, `TRAVEL_DATE_IN_PAST`, `INVALID_DATE_RANGE`, `LISTING_NOT_AVAILABLE`, `RATE_LIMITED`, `VALIDATION_ERROR`. The sixth web request in an hour for the same email or phone, or the 200th for the organization, is `RATE_LIMITED`.

## WhatsApp boundary

`whatsapp-inbound` has `verify_jwt = false`. Authorization is the `X-Hub-Signature-256` HMAC of the raw body with `WHATSAPP_APP_SECRET`. The GET handshake uses `WHATSAPP_VERIFY_TOKEN`. Without those variables the function answers 503 and does not call the database. Placeholders live in `supabase/functions/.env.example`; they are not production secrets.

Register the tenant with a `channel_connections` row (`provider = meta_cloud`, `external_account_id` = Meta `phone_number_id`). `scripts/simulate-whatsapp-inbound.sh` posts the fixture with a local HMAC. The adapter does not send messages, store media, or read a service-role key from Angular.

## State machine

`received → in_review → discarded`. `received` can also go straight to `discarded`. Discard requires a reason of 1–500 characters. `pre_reservation` is reserved for feature 004 and returns `PRE_RESERVATION_REQUIRES_CONVERSION` from every state, including discarded. A discarded request returns `REQUEST_CLOSED` for any other change. Leaving `received` sets `first_handled_at`. Discard sets `closed_at`.

## RBAC

| Action | Agent | Operator | Admin |
| --- | --- | --- | --- |
| Read and work requests of the tenant | Yes | Yes | Yes |
| Assisted intake, assign, discard, notes, edit customer | Yes | Yes | Yes |
| Anonymize a customer | No | No | Yes |

`roleGuard('agent')` only hides `/sales/*`. RLS and the RPCs are the authorization boundary.

## Security invariants (do not regress)

- RLS is by `organization_id`. `anon` has no table access. Authenticated roles cannot insert, update, or delete the customer tables directly.
- Writes go through `SECURITY DEFINER` functions with `search_path = ''`. They check the JWT role and the live `user_profiles` row.
- Audit metadata records channel, status ids, and field names. It does not record email, phone, name, discard reason, or message body.
- Anonymization keeps commercial history and internal notes. It does not delete requests.

## Routes

| Path | Who | Screen |
| --- | --- | --- |
| `/sales/requests` | any collaborator | Inbox |
| `/sales/requests/new` | any collaborator | Assisted intake |
| `/sales/requests/:id` | any collaborator | Request detail |
| `/sales/customers` | any collaborator | Customer directory |
| `/sales/customers/:id` | any collaborator | Customer profile |

Navigation order: Dashboard → Comercial → Configuración → CMS.

## Quickstart mapping

Scenarios 1–9 of `specs/003-customer-requests-channels/quickstart.md` were **not** run in the browser. The implementation session was told not to start the dev server, and the Docker daemon was not running, so `./supabase/tests/run-sql-tests.sh` was not executed here either.

| Scenario | Automated evidence | Browser |
| --- | --- | --- |
| 1. Web intake happy path | `public_request_intake_test.sql` | Not verified |
| 2. Validation and honeypot | `public_request_intake_test.sql` | Not verified |
| 3. Idempotency and fingerprint | `customer_intake_core_test.sql`, `public_request_intake_test.sql` | Not verified |
| 4. Contact conflict | `public_request_intake_test.sql` | Not verified |
| 5. Assisted WhatsApp intake | `whatsapp_intake_test.sql` | Not verified |
| 6. Signed webhook | `whatsapp_intake_test.sql` (RPC). The Edge Function signature check is in `supabase/functions/whatsapp-inbound/index.ts`; the SQL harness does not execute Deno. | Not verified |
| 7. Inbox, assignment, discard | `request_workflow_test.sql` | Not verified |
| 8. Customer edit | `request_workflow_test.sql` | Not verified |
| 9. Anonymization | `customer_privacy_test.sql` | Not verified |

Realtime delivery and the 10-second fallback are implemented in `RequestRealtimeService` and are not covered by the SQL harness.
