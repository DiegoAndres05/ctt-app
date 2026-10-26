# Research: 006-reservation-lifecycle

**Feature**: 006-reservation-lifecycle  
**Date**: 2026-10-22

## 1. Frontera con 005: solo cotización aceptada

**Decision**: `confirm_reservation(quotation_version_id, deposit, passengers)` llama internamente a `assert_quotation_confirmable(org, version_id)` (migración `048`). Si el status no es `accepted`, el código es `QUOTATION_NOT_ACCEPTED` (cubre expirada, rechazada, anulada, emitida, borrador). Una versión aceptada produce **como máximo una reserva** (`UNIQUE` sobre `quotation_version_id`). 006 no recalcula tarifas ni reabre la cotización.

**Rationale**: El contrato de 005 ya congeló importes, pasajeros por línea y huella de pre-reserva. Confirmar es un acto operativo + financiero, no comercial.

**Alternatives considered**:
- Revalidar disponibilidad al confirmar: viola el congelamiento de 005 y duplica 004.
- Permitir confirmar una emitida sin aceptación: contradice FR-001 y el escenario 2.

## 2. Localizador RSV-##### más token de voucher

**Decision**: Referencia operativa `RSV-` + `lpad(next_organization_sequence(org, 'reservation'), 5, '0')`, única por organización (mismo patrón que `SOL-` / `PRE-` / `COT-`). El voucher público usa un token de 32 bytes (`extensions.gen_random_bytes`); la base guarda solo SHA-256 (`voucher_token_hash`). El token en claro se devuelve una vez al confirmar y se guarda en `sessionStorage` (`reservation-token:<id>`), igual que el enlace de cotización.

**Rationale**: FR-002 pide unicidad y que el localizador no sea trivialmente adivinable para ver el viaje de otro cliente. La secuencia cubre unicidad operativa (SC-001); el token cubre el acceso público. “No predecible” no obliga a abandonar el consecutivo que el equipo ya usa en Comercial.

**Alternatives considered**:
- Solo UUID: ilegible en WhatsApp y en el mostrador.
- Solo RSV-##### público: enumerable entre reservas de la misma agencia.

## 3. Versiones en lugar de estado «Reprogramada» / «Modificada»

**Decision**: Familia `reservation_families` (localizador, cotización origen, cliente) + versiones `reservation_versions` (una abierta). Estados vivos de la versión actual: `confirmed`, `in_progress`, `completed`, `cancelled`. Un cambio de fechas o pasajeros (US3) crea versión `n+1` en `confirmed` (o `in_progress` si el viaje ya había empezado) y deja la anterior en `superseded`. «Reprogramada» es el historial, no un estado que el listado filtre como ciclo de vida. «Modificada» del spec de entidades no se usa como status.

**Rationale**: Copia el patrón de 005 (familia + versión). FR-003 lista Reprogramada; el escenario 2 de US3 pide “nueva versión con historial auditado”. Un sexto estado vivo duplicaría filtros y rompería transiciones.

**Alternatives considered**:
- Mutar fechas in-place + bitácora: más simple, pierde el itinerario anterior que el voucher ya mostró.
- Estado `reprogrammed` permanente: el viaje sigue siendo una reserva confirmada o en curso.

## 4. Máquina de estados

**Decision**:

```
confirmed → in_progress → completed
confirmed → cancelled          (agente o admin; motivo 1–500)
in_progress → cancelled        (solo admin + informe de contingencia 1–2000)
cualquier vivo → superseded    (solo al crear versión)
completed y cancelled son terminales (no vuelven atrás)
```

`in_progress` lo marca el operador/admin cuando el viaje empieza (no hay job que lo haga por fecha). Completar exige `in_progress`. Sustituir un proveedor no cambia el estado de la reserva; cambia el estado operativo del ítem.

**Rationale**: Escenarios US2 + edge “cancelar en ejecución = admin”. Evita cron (igual que la expiración de cotizaciones, que barre al leer).

**Alternatives considered**:
- Auto-transición por `start_date`: frágil con husos y no-shows.

## 5. Pagos: depósito manual, sin pasarela

**Decision**: Tabla append-only `reservation_payments`. Confirmar exige un depósito `amount > 0` en la moneda congelada, método (`bank_transfer` | `cash` | `card_manual` | `other`), fecha, referencia 1–80, y opcionalmente ruta de comprobante en bucket privado `reservation-receipts` (`{organization_id}/{reservation_id}/{uuid}`). `verified_by` = caller. Saldos: `total` (snapshot), `paid_total` (suma de pagos), `balance = total - paid_total`. Se pueden registrar abonos posteriores. Sin Stripe/Wompi, sin asiento contable, sin factura electrónica.

**Rationale**: Assumption del spec. FR-005 pide comprobante; 005 ya prohibió pasarelas.

**Alternatives considered**:
- Confirmar sin dinero y pagar después: el spec amarra confirmación al anticipo.

## 6. Pasajeros vs cupos de la cotización

**Decision**: Al confirmar, el agente envía la lista de pasajeros. `count(passengers) = party_adults + party_children` del snapshot (`PASSENGER_COUNT_MISMATCH` si no). Campos: nombres, apellidos, tipo de documento (`cc` | `ce` | `passport` | `ti` | `other`), documento, fecha de nacimiento opcional, requerimientos ≤ 500. En una nueva versión se reenvía la lista completa (no se edita in-place). Los documentos no van a `audit.metadata`.

**Rationale**: SC-004. La cotización solo tiene conteos; la reserva es el primer sitio con identidad de viajeros.

## 7. Ítems y órdenes a proveedor

**Decision**: Los ítems se copian del snapshot de líneas (producto/add-on, fechas, pax, quantity, proveedor de la pre-reserva si existe). Estado operativo por ítem: `pending_provider` → `confirmed_with_provider` → `in_service` | `completed` | `provider_failed`. `mark_provider_order_sent` registra canal (`whatsapp_copy` | `email_copy` | `print`) y timestamp; no envía mensajes. El texto de orden lo arma el servidor **sin** precios de venta ni datos de otros prestadores. Reasignar proveedor (`reassign_reservation_item_provider`) exige operador/admin, motivo, y pone el ítem en `pending_provider` otra vez; no cancela la reserva.

**Rationale**: US4 + edge de proveedor incumplido. Misma frontera de “copiar, no enviar” que 005.

## 8. Voucher del cliente

**Decision**: Vista de impresión en el panel (`window.print()`) y ruta pública `/r/:token` (sin shell, sin sesión) vía `get_public_voucher(token)`. Muestra localizador, itinerario, pax (nombre, no documento), teléfonos de asistencia de la org, políticas copiadas de los términos de la cotización. No muestra desglose comercial interno ni datos de otros clientes. SC-002 se cumple porque es HTML ya en pantalla, no un PDF generado.

**Rationale**: 005 no tiene generador PDF; el spec pide voucher en < 3 s.

## 9. Autorización y menú

**Decision**: Agente+ confirma, lista, detalla, registra pagos, cancela en `confirmed`, imprime voucher. Operador+ transiciona ciclo de vida, emite órdenes, reasigna proveedor. Admin cancela `in_progress` y anula voucher (rota el hash, `void_voucher`). RLS: colaborador del tenant. `anon` solo `get_public_voucher`. Menú Comercial: **Reservas** (`/sales/reservations`, `minRole: agent`). Enlace desde cotización aceptada: «Confirmar reserva».

**Rationale**: Roles de 001; el spec reparte US1 (agente/admin), US2 (operador), US3 (admin/agente), US4 (operador).

## 10. Auditoría y PII

**Decision**: Eventos: `reservation_confirmed`, `reservation_status_changed`, `reservation_cancelled`, `reservation_version_created`, `reservation_payment_recorded`, `reservation_provider_notified`, `reservation_item_reassigned`, `reservation_voucher_voided`. `metadata` solo ids, localizador, status, montos, moneda — nunca documento, nombre de pasajero, referencia bancaria completa ni token.

**Rationale**: Constitución + convención 003/005.

## 11. Storage de comprobantes

**Decision**: Bucket privado `reservation-receipts`. Políticas: `authenticated` lee/escribe solo prefijo `organization_id/` del JWT; `anon` no. El harness SQL stubbea `storage` como 026.

**Rationale**: FR-005 pide archivo; el catálogo ya usa storage con prefijo de org.

## 12. Qué queda fuera

Pagos automáticos, facturación, email/WhatsApp saliente, cron de estados, inventario, cupos en catálogo, WordPress, analítica (008). `assert_quotation_confirmable` no se altera salvo, si hiciera falta en implementación, un guard `RESERVATION_ALREADY_EXISTS` **dentro de 006** (no reabrir 048).
