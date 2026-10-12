# Research: 006-reservation-lifecycle

Decisiones de Phase 0 a partir de la sesión 2026-10-09.

## R-001 — Localizador opaco

**Decision**: `RSV-` + 6 caracteres del alfabeto Crockford `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (sin I, L, O, U). Se genera con `extensions.gen_random_bytes` y hasta 5 reintentos ante choque de `UNIQUE (organization_id, locator)`. No usa `organization_sequences`.

**Rationale**: El spec pide un código que no se pueda adivinar. La secuencia `RSV-00001` filtraría el volumen de ventas.

**Alternatives considered**: UUID visible. Se rechaza porque no se dicta por teléfono. Ocho caracteres. Seis alcanzan (32^6) para el volumen del MVP y se leen mejor.

## R-002 — Confirmación sin recalcular

**Decision**: `confirm_reservation` llama a `assert_quotation_confirmable` y copia `total`, `currency`, `party_adults`, `party_children` y las líneas de esa instantánea. No lee `pricing_schemes`. No hace `UPDATE` de `pre_reservations` ni de `quotation_versions`. Índice único parcial: una sola reserva con estado distinto de `cancelled` por `quotation_version_id`. Si la anterior está cancelada, se puede confirmar otra con otro localizador.

**Rationale**: FR-001 y la frontera explícita con 004 y 005.

**Alternatives considered**: Recalcular por si la tarifa cambió. Lo prohíbe el congelado de 005.

## R-003 — Anticipo manual

**Decision**: `reservation_settings.deposit_percent` numeric(5,2), default 30, rango 0–100, una fila por organización. El mínimo es `round(total * deposit_percent / 100, 2)`. Métodos: `transfer`, `cash`, `card`, `other`. Un administrador puede confirmar con `p_waive_deposit = true` y motivo de 1 a 500 caracteres guardado en `reservation_payments.waiver_reason`, no en la auditoría. La auditoría de la exención lleva `{ waived: true }` sin el texto.

El comprobante es opcional. El cliente sube a `reservation-receipts` bajo `{organization_id}/{reservation_id}/` y pasa `receipt_path`. Si la subida falla, confirma con `receipt_path` null y la UI muestra «No se pudo guardar el archivo. La referencia queda registrada.» No hay pasarela ni factura.

**Rationale**: El usuario dejó pagos y factura fuera o degradados. El 30 % es el default clarificado.

**Alternatives considered**: Bloquear la confirmación si no hay archivo. Se rechaza: el spec dice que la referencia alcanza.

## R-004 — Estados de una sola reserva

**Decision**: Enum `confirmed`, `in_progress`, `completed`, `cancelled`, `rescheduled`. El localizador no cambia.

| Desde | Hacia | Quién | Extra |
|-------|--------|-------|-------|
| confirmed | in_progress | operador o admin | — |
| confirmed | completed | — | prohibido; hay que pasar por en ejecución |
| confirmed | cancelled | miembro | motivo 1–500 y reembolso 0–100 |
| confirmed | rescheduled | operador o admin | nuevas fechas |
| rescheduled | confirmed | operador o admin | el proveedor aceptó |
| rescheduled | cancelled | miembro | igual que confirmed |
| in_progress | completed | operador o admin | — |
| in_progress | cancelled | admin | informe 1–2000 |
| completed, cancelled | cualquiera | — | `RESERVATION_TERMINAL` |

`refund_amount = round(total * refund_percent / 100, 2)` se guarda en la reserva. No sale dinero.

**Rationale**: «Reprogramada» es estado, no otra reserva. Completada y cancelada son terminales.

**Alternatives considered**: Versionar la reserva como la cotización. Duplicaría localizadores, y el spec eligió uno solo.

## R-005 — Pasajeros

**Decision**: Antes de confirmar, el arreglo de pasajeros debe tener longitud `party_adults + party_children`. Nombre y apellido obligatorios (1–80). Documento, tipo, nacimiento y requisitos opcionales. Después de confirmar se pueden corregir datos, no la cantidad (`PASSENGER_COUNT_MISMATCH`). La orden de servicio incluye nombre, apellido y requisitos de los pasajeros de la reserva, porque el proveedor los necesita; no incluye documentos.

**Rationale**: SC-004 habla de viajeros, no de habitaciones. El documento es PII más sensible que el nombre que ya va en la orden operativa.

**Alternatives considered**: Exigir documento para confirmar. El spec lo dejó opcional.

## R-006 — Contingencia de proveedor

**Decision**: `mark_item_provider_failed` (operador) pone el ítem en `provider_failed` y no cancela la reserva. `add_replacement_item` agrega un ítem ligado con `replaces_item_id`. El `total` de la reserva no cambia. `adjust_reservation_total` es solo admin, exige motivo y audita montos anterior y nuevo (no son PII) sin el motivo.

**Rationale**: El edge case pide reasignar sin cancelar la reserva ni tocar el precio por el mero reemplazo.

**Alternatives considered**: Abrir otra cotización. Eso devuelve el caso a 005 y deja el viaje sin localizador. Se puede hacer aparte; esta feature no lo exige.

## R-007 — Órdenes sin envío

**Decision**: `build_service_order(reservation_id, provider_id)` arma el texto en SQL: localizador, servicios de ese proveedor, fechas, pasajeros (nombre y requisitos). Sin precios, sin otros proveedores. `mark_service_order_transmitted` registra actor y fecha. No hay Edge Function ni `mailto` obligatorio. El panel copia e imprime.

**Rationale**: El WhatsApp saliente está fuera de alcance. Copiar se degrada sin configuración.

**Alternatives considered**: `wa.me` con el texto ya cargado. Abre la app del operador y no envía solo, pero mete PII de pasajeros en una URL. Se rechaza. Copiar al portapapeles es suficiente.

## R-008 — Voucher autenticado

**Decision**: El voucher es una sección del detalle, con CSS de impresión. Muestra localizador, itinerario, políticas (`terms` copiados de la cotización al confirmar) y `assistance_phone` de `reservation_settings`. Si el teléfono está vacío: «La agencia indicará el teléfono de asistencia.» No muestra pagos ni costos. No hay ruta `/v/:token` para `anon`, porque el voucher lleva nombres.

**Rationale**: FR-006 pide el documento para el cliente. Publicarlo por token expondría PII con un secreto de un solo factor. El agente lo imprime o lo guarda como PDF del navegador.

**Alternatives considered**: Token público como la cotización. La cotización no lleva documentos ni la lista nominativa completa; el voucher sí.

## R-009 — Auditoría e historial

**Decision**: `reservation_events` es append-only y puede guardar el motivo operativo (lo lee el panel de la reserva, con RLS). `audit.log_event` solo recibe códigos: `reservation_confirmed`, `reservation_status_changed`, `reservation_cancelled`, `reservation_rescheduled`, `reservation_provider_replaced`, `reservation_payment_recorded`, `reservation_deposit_waived`, `service_order_transmitted`. Metadata: ids, estados, `refund_percent`, `waived`, montos. Nunca nombres, documentos, motivos, informes ni referencias bancarias.

**Rationale**: El historial de negocio explica el caso. La auditoría de seguridad no debe filtrar PII si se exporta.

**Alternatives considered**: Un solo registro. Mezcla el informe de contingencia con la bitácora de seguridad.
