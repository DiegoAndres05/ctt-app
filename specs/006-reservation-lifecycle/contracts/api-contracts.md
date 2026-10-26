# API & UI Contracts: 006-reservation-lifecycle

**Date**: 2026-10-22 | **Spec**: [spec.md](../spec.md) | **Data Model**: [data-model.md](../data-model.md)

Errores: el RPC lanza el código como mensaje; PostgREST `{ "code": "P0001", "message": "<CODE>" }`; el panel usa `toAppError`. Fechas de calendario en `America/Bogota`. Auditoría sin PII ni token.

---

## 1. Panel RPCs (`GRANT EXECUTE` to `authenticated`)

### `confirm_reservation(p_quotation_version_id uuid, p_deposit jsonb, p_passengers jsonb, p_assistance_phones text)`

Llama `assert_quotation_confirmable`. Inserta familia v1 `confirmed`, ítems, pasajeros, primer pago. Genera `RSV-#####` y token de voucher.

`p_deposit`: `{ amount, currency, paid_on, method, transfer_reference, receipt_path? }`

**200** (una vez): `{ family_id, version_id, reference, voucher_token, total, currency }`

| Code | Cuándo |
|------|--------|
| `QUOTATION_NOT_ACCEPTED` | frontera 005 |
| `RESERVATION_ALREADY_EXISTS` | esa versión ya tiene reserva |
| `DEPOSIT_REQUIRED` / `CURRENCY_MISMATCH` | depósito |
| `PASSENGER_COUNT_MISMATCH` | conteo |
| `VALIDATION_ERROR` | payload |

Audita `reservation_confirmed` `{ reference, currency, total }`.

### `transition_reservation_status(p_version_id uuid, p_to text)`

`confirmed` → `in_progress`; `in_progress` → `completed`. Operador o admin.

`INVALID_TRANSITION` en cualquier otro caso.

### `cancel_reservation(p_version_id uuid, p_reason text, p_contingency_report text)`

`confirmed`: miembro, motivo 1–500. `in_progress`: admin, motivo + informe 1–2000. Libera compromisos operativos poniendo ítems no terminales en `provider_failed` (no borra filas).

### `create_reservation_version(p_version_id uuid, p_items jsonb, p_passengers jsonb)`

Nueva versión con fechas/ítems/pasajeros. Versión previa `superseded`. Pagos de familia se conservan. Exige reserva `confirmed` o `in_progress`. Recalcula `travel_*` y party counts desde el payload (party must still match passenger count).

### `record_reservation_payment(p_family_id uuid, p_payment jsonb)`

Abono extra. Misma validación de depósito. Audita `reservation_payment_recorded` `{ amount, currency }` (sin referencia bancaria).

### `mark_provider_order_sent(p_item_id uuid, p_channel text)`

Pasa ítem a `confirmed_with_provider` si estaba `pending_provider` o `provider_failed`.

### `reassign_reservation_item_provider(p_item_id uuid, p_provider_id uuid, p_reason text)`

Operador/admin. `ops_status = pending_provider`.

### `reservation_provider_order_text(p_item_id uuid)`

JSON/text para copiar: nombres de pax de **ese** ítem (sin documentos), fechas, producto, notas de requerimientos. **Sin** `line_total`, **sin** otros ítems.

### `reservation_whatsapp_text(p_version_id uuid)`

Cuerpo para el cliente: localizador, fechas, total, saldo. Sin URL, sin token, sin `https://`. El panel concatena `Detalle: ${origin}/r/${token}` desde `sessionStorage`.

### `expire` N/A — no hay vigencia de reserva.

### `void_reservation_voucher(p_family_id uuid)`

Admin. Anula hash, audita `reservation_voucher_voided`. El público ve `{ available: false }`. Para reemitir: `rotate_reservation_voucher` (admin) genera token nuevo una vez.

### `list` reads

Antes de `reservation_list`, no hay sweep obligatorio. El servicio pagina `range` + `count: 'exact'`.

---

## 2. Público

### `get_public_voucher(p_token text)`

`GRANT` a `anon` y `authenticated`. Lookup por SHA-256.

**200 available**: `{ available: true, reference, status, travel_start_date, travel_end_date, terms, assistance_phones, passengers: [{ first_name, last_name }], items: [{ title, start_date, end_date, quantity }] }`

Sin `customer_id`, email, teléfono, documentos, montos, `provider_id`.

Token vacío/desconocido/voided: `{ available: false }` sin listas.

---

## 3. Storage

Bucket `reservation-receipts`, no público. Upload desde el panel autenticado al prefijo `{orgId}/{familyId}/`. El RPC solo guarda el `receipt_path`; no lee bytes.

---

## 4. UI

| Path | Quién | Pantalla |
|------|--------|----------|
| `/sales/reservations` | agent+ | Listado 20/página, búsqueda por RSV-/COT-/cliente |
| `/sales/reservations/new?quotationVersionId=` | agent+ | Confirmar (depósito + pasajeros) |
| `/sales/reservations/:id` | agent+ | Detalle: ciclo, pagos, pax, ítems, voucher, órdenes |
| `/r/:token` | público | Voucher de solo lectura |

Menú Comercial: **Reservas** después de Cotizaciones (`minRole: 'agent'`).

Cotización `accepted`: botón «Confirmar reserva» → `/sales/reservations/new?quotationVersionId=`.

Textos ES (mínimo):

| Situación | Texto |
|-----------|--------|
| Éxito confirmación | `Reserva RSV-00001 confirmada. El voucher se muestra una sola vez.` |
| Cotización no aceptada | `Solo se confirma una cotización aceptada.` |
| Ya existe | `Esta cotización ya tiene una reserva.` |
| Conteo pax | `El número de pasajeros debe coincidir con la cotización.` |
| Transición ilegal | `Ese cambio de estado no está permitido.` |
| Cancelar en curso | `Hace falta un administrador y un informe de contingencia.` |
| Token perdido | `El voucher se mostró al confirmar. Un administrador puede reemitirlo.` |
| Público no disponible | `Este voucher ya no está disponible.` |

La UI **no** suma pagos: pinta `paid_total` y `balance` del servidor. Imprimir = `window.print()`. WhatsApp = copiar texto, no API.

---

## 5. TypeScript

`src/app/core/reservations/` modelos + `ReservationService`.  
`src/app/features/sales/reservations/` list + confirm + detail.  
`src/app/features/public-voucher/` ruta `/r/:token`.
