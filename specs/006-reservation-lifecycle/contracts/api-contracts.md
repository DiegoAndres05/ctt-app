# API Contracts: 006-reservation-lifecycle

El navegador no envía `organization_id`. Errores con `RAISE EXCEPTION '<CODE>'`. Otra organización: `VALIDATION_ERROR`.

## 1. Lecturas

`reservation_list` paginada. Detalle: `reservations`, `reservation_passengers`, `reservation_items`, `reservation_payments`, `service_orders`, `reservation_events` por `id`. El voucher usa esas filas; no hay RPC de precio.

## 2. US1 — Confirmar (`052_us1_reservation_confirm.sql`)

`confirm_reservation(p_quotation_version_id uuid, p_passengers jsonb, p_payment jsonb) → jsonb`

`p_passengers`: `[{ first_name, last_name, document_type?, document_number?, birth_date?, special_requirements? }]`.

`p_payment`: `{ method, amount, paid_on, reference, receipt_path?, waive? , waiver_reason? }`.

Éxito:

```json
{
  "reservation_id": "…",
  "locator": "RSV-7K3MQP",
  "status": "confirmed",
  "total": 1000,
  "currency": "COP",
  "deposit_due": 300,
  "balance": 700,
  "receipt_stored": true
}
```

`receipt_stored` es false si `receipt_path` vino null.

Errores: `QUOTATION_NOT_ACCEPTED`, `RESERVATION_ALREADY_EXISTS`, `PASSENGER_COUNT_MISMATCH`, `PASSENGER_NAME_REQUIRED`, `DEPOSIT_NOT_MET`, `WAIVER_REASON_REQUIRED`, `PAYMENT_REFERENCE_REQUIRED`, `INSUFFICIENT_PERMISSIONS`.

`register_reservation_payment` devuelve `{ paid_amount, balance }`. Sobre completada o cancelada: `RESERVATION_CLOSED`.

`upsert_reservation_settings` devuelve `{ deposit_percent, assistance_phone }`. Porcentaje fuera de 0–100: `VALIDATION_ERROR`.

## 3. US2 — Ciclo (`053_us2_reservation_lifecycle.sql`)

| RPC | Éxito | Errores |
|-----|-------|---------|
| `start_reservation(p_reservation_id uuid)` | `{ status: 'in_progress' }` | `INVALID_TRANSITION`, `INSUFFICIENT_PERMISSIONS`, `RESERVATION_TERMINAL` |
| `complete_reservation(p_reservation_id uuid)` | `{ status: 'completed' }` | igual |

Un agente recibe `INSUFFICIENT_PERMISSIONS`.

## 4. US3 — Cambios (`054_us3_reservation_changes.sql`)

| RPC | Errores propios |
|-----|-----------------|
| `cancel_reservation(p_reservation_id uuid, p_reason text, p_refund_percent numeric, p_contingency text)` | `CANCEL_REASON_REQUIRED`, `REFUND_PERCENT_OUT_OF_RANGE`, `CONTINGENCY_REQUIRED`, `RESERVATION_TERMINAL` |
| `reschedule_reservation(...)` | `INVALID_DATE_RANGE`, `INVALID_TRANSITION` |
| `accept_reschedule(p_reservation_id uuid)` | `INVALID_TRANSITION` |
| `mark_item_provider_failed(p_item_id uuid, p_note text)` | `ITEM_ALREADY_CLOSED` |
| `add_replacement_item(...)` | `ITEM_NOT_FAILED`, `VALIDATION_ERROR` |
| `adjust_reservation_total(p_reservation_id uuid, p_total numeric, p_reason text)` | `INSUFFICIENT_PERMISSIONS`, `VALIDATION_ERROR` si total < 0 |

Cancelar en ejecución sin ser admin: `INSUFFICIENT_PERMISSIONS`. Completada: `RESERVATION_TERMINAL`.

`add_replacement_item` no modifica `reservations.total`.

## 5. US4 — Órdenes (`055_us4_service_orders.sql`)

`build_service_order` devuelve `{ order_id, body }`. `body` no contiene `total`, `currency`, `line_total` ni el nombre de otro proveedor. Incluye el localizador, las etiquetas de servicio de ese proveedor, las fechas y los pasajeros (nombre, apellido, requisitos).

`mark_service_order_transmitted` devuelve `{ order_id, transmitted_at }`. No envía mensajes.

## 6. Rutas y menú

| Ruta | Guard | Pantalla |
|------|-------|----------|
| `/sales/reservations` | `roleGuard('agent')` | Listado |
| `/sales/reservations/new` | `roleGuard('agent')`, `unsavedChangesGuard` | Confirmación. Query `quotationVersionId` |
| `/sales/reservations/:id` | `roleGuard('agent')` | Detalle, voucher, órdenes |

Menú Comercial en `nav-items.ts`:

```ts
{ id: 'sales-reservations', label: 'Reservas', path: '/sales/reservations', minRole: 'agent' }
```

En el editor de cotización de 005, si `status === 'accepted'`, enlace «Confirmar reserva» a `/sales/reservations/new?quotationVersionId=`. No confirmar desde una RPC de 005.

## 7. Copy (español)

| Situación | Texto |
|-----------|-------|
| Listado vacío | Todavía no hay reservas. |
| Título | Reservas |
| Confirmar | Confirmar reserva |
| Anticipo corto | El abono no cubre el anticipo. |
| Exención | Eximir anticipo |
| Archivo fallido | No se pudo guardar el archivo. La referencia queda registrada. |
| Pasajeros | Faltan pasajeros: deben ser exactamente los viajeros de la cotización. |
| Duplicada | Esta cotización ya tiene una reserva activa. |
| En ejecución | Pasar a en ejecución |
| Completar | Marcar completada |
| Cancelar | Cancelar reserva |
| Motivo | Motivo de la cancelación |
| Reembolso | Porcentaje de reembolso |
| Contingencia | Informe de contingencia |
| Reprogramar | Reprogramar |
| Proveedor aceptó | El proveedor aceptó las nuevas fechas |
| Incumplido | Marcar proveedor incumplido |
| Reemplazo | Agregar servicio de reemplazo |
| Orden | Orden de servicio |
| Copiar orden | Copiar orden |
| Transmitida | Marcar como transmitida |
| Sin envío | La orden no se envía sola. Cópiela o imprímala. |
| Voucher | Voucher de reserva |
| Sin teléfono | La agencia indicará el teléfono de asistencia. |
| Terminal | Esta reserva está cerrada. |
| Ajustes | Anticipo y teléfono de asistencia |

## 8. Auditoría

`resource_type = 'reservation'`. Metadata permitida: `quotation_version_id`, `from`, `to`, `refund_percent`, `waived`, `previous_total`, `new_total`, `provider_id`. Prohibido: nombres, documentos, `cancel_reason`, `contingency_report`, `waiver_reason`, `reference` del pago, teléfono.
