---
description: "Task list for 006-reservation-lifecycle implementation"
---

# Tasks: 006-reservation-lifecycle (Comercial — Reservas)

**Input**: Design documents from `/specs/006-reservation-lifecycle/`

**Prerequisites**: plan.md, spec.md (clarificado 2026-10-09), research.md, data-model.md, contracts/api-contracts.md, quickstart.md. La feature 005 termina en `048_us4_quotation_responses.sql` y deja `assert_quotation_confirmable`. Esta feature usa `049`–`055`. No renumerar migraciones anteriores. No crear pasarela, factura electrónica ni envío de WhatsApp o correo. No modificar el estado de `pre_reservations` ni de `quotation_versions`.

**Tests**: Suites SQL y Vitest. Ninguna tarea se marca hecha en este archivo.

**Organization**: US1–US4 de spec.md.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Archivo distinto, sin dependencias pendientes
- **[Story]**: US1–US4
- Rutas exactas en cada tarea

## Path Conventions

- **Backend**: `supabase/migrations/049_` … `055_`, `supabase/tests/`
- **Frontend**: `src/app/core/reservations/`, `src/app/features/sales/reservations/`, `src/app/app.routes.ts`
- **Docs**: `docs/modules/reservations.md`

## Conventions every task must follow

- **SQL**: `SECURITY DEFINER`, `SET search_path = ''`, `audit.log_event` sin nombres, documentos, motivos, informes ni referencias de pago (contracts §8). Localizador solo con `allocate_reservation_locator`.
- **Angular**: standalone, OnPush, signals, `form()` de `@angular/forms/signals`, `app-data-table`, `toAppError`, copy de contracts §7.
- **No** service role en `src/`. **No** recalcular tarifas. **No** ruta pública del voucher.

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Crear carpetas con `.gitkeep`: `src/app/core/reservations/models/`, `src/app/core/reservations/services/`, `src/app/features/sales/reservations/reservation-list/`, `src/app/features/sales/reservations/reservation-confirm/`, `src/app/features/sales/reservations/reservation-detail/`

---

## Phase 2: Foundational (Blocking Prerequisites)

- [ ] T002 `supabase/migrations/049_reservation_enums.sql` ya creado según data-model §Enums: reservation_status (confirmed/in_course/completed/cancelled/rescheduled), reservation_item_status (confirmed_in_provider/en_service/completed/incidencia), payment_method (cash/transfer/deposit/credit), reservation_event_kind con `COMMENT ON TYPE` y `ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS` para reservation_confirmed, reservation_status_changed, reservation_cancelled, reservation_rescheduled, reservation_provider_replaced, reservation_payment_recorded, reservation_deposit_waived, service_order_transmitted.
- [ ] T003 Crear `supabase/migrations/050_reservations.sql` según data-model §1–§7, RLS, vista `reservation_list` y bucket `reservation-receipts` (stub de `storage` como `supabase/migrations/026_catalog_media_bucket.sql` si no existe). Índice único parcial de una reserva no cancelada por `quotation_version_id`. `reservation_events` append-only con `reject_request_note_mutation`. `anon` sin privilegios
- [ ] T004 Crear `supabase/migrations/051_reservation_core.sql` con `allocate_reservation_locator`, `reservation_deposit_due` y `assert_passenger_count` internas (`REVOKE ALL` a `PUBLIC`, `anon`, `authenticated`). Alfabeto Crockford de research R-001, prefijo `RSV-`, 6 caracteres, hasta 5 reintentos
- [ ] T005 [P] Crear `supabase/tests/reservation_rls_test.sql`: `anon` no lee las tablas ni la vista; un autenticado de otra organización no ve filas; el bucket `reservation-receipts` no es `public`; las funciones de `051` no tienen `EXECUTE` para `authenticated`
- [ ] T006 [P] Crear `src/app/core/reservations/models/reservation.model.ts` y `reservation.model.spec.ts`: `RESERVATION_STATUS_LABELS` («Confirmada», «En ejecución», «Completada», «Cancelada», «Reprogramada»); `allowedTransition(from, to, role)` según research R-004; `isReservationTerminal` para `completed` y `cancelled`. El spec rechaza que el cliente arme un localizador
- [ ] T007 [P] Registrar en `src/app/core/error/error-handler.ts` y en `error-handler.spec.ts`: `RESERVATION_ALREADY_EXISTS` «Esta cotización ya tiene una reserva activa.», `PASSENGER_COUNT_MISMATCH` «Faltan pasajeros: deben ser exactamente los viajeros de la cotización.», `PASSENGER_NAME_REQUIRED` «Cada pasajero necesita nombre y apellido.», `DEPOSIT_NOT_MET` «El abono no cubre el anticipo.», `WAIVER_REASON_REQUIRED` «La exención del anticipo necesita un motivo.», `PAYMENT_REFERENCE_REQUIRED` «Indique la referencia del pago.», `RESERVATION_CLOSED` «Esta reserva está cerrada.», `RESERVATION_TERMINAL` «Esta reserva está cerrada.», `INVALID_TRANSITION` «Ese cambio de estado no está permitido.», `CANCEL_REASON_REQUIRED` «Indique el motivo de la cancelación.», `REFUND_PERCENT_OUT_OF_RANGE` «El reembolso debe estar entre 0 % y 100 %.», `CONTINGENCY_REQUIRED` «Cancelar un viaje en ejecución exige un informe de contingencia.», `ITEM_ALREADY_CLOSED` «Ese servicio ya está cerrado.», `ITEM_NOT_FAILED` «Solo se reemplaza un servicio marcado como proveedor incumplido.»

**Checkpoint**: Esquema y localizador listos. Aún no se confirma.

---

## Phase 3: User Story 1 - Confirmación (Priority: P1) 🎯 MVP

**Goal**: Una cotización aceptada se vuelve una reserva con localizador, pasajeros y anticipo manual, sin recalcular ni tocar la pre-reserva.

**Independent Test**: Escenario 1 de quickstart.md y `reservation_confirm_test.sql`.

### Tests for User Story 1

- [ ] T008 [P] [US1] Crear `supabase/tests/reservation_confirm_test.sql`: confirmar copia `total` aunque después cambie la tarifa; no actualiza `pre_reservations.status` ni `quotation_versions.status`; pasajeros de menos → `PASSENGER_COUNT_MISMATCH`; abono bajo el 30 % → `DEPOSIT_NOT_MET`; exención sin admin → `INSUFFICIENT_PERMISSIONS`; exención admin con motivo crea la reserva y audita `reservation_deposit_waived` con `{ waived: true }` y sin el motivo; segunda confirmación → `RESERVATION_ALREADY_EXISTS`; `receipt_path` null devuelve `receipt_stored: false`; localizador cumple `^RSV-[0-9A-HJKMNP-TV-Z]{6}$`; cotización no aceptada → `QUOTATION_NOT_ACCEPTED`

### Implementation for User Story 1

- [ ] T009 [US1] Crear `supabase/migrations/052_us1_reservation_confirm.sql` con `confirm_reservation`, `register_reservation_payment`, `upsert_reservation_settings` y `update_reservation_passengers` según contracts §2 y data-model §US1. `confirm_reservation` llama a `assert_quotation_confirmable`, inserta ítems copiados, pasajeros, pago o exención, evento `confirmed` y auditoría `reservation_confirmed` sin PII. `GRANT EXECUTE` a `authenticated`
- [ ] T010 [US1] Crear `src/app/core/reservations/services/reservation.service.ts` con `listPage` (`reservation_list`, `range` + `count: 'exact'`), `confirm`, `registerPayment`, `saveSettings`, `updatePassengers`, `getDetail`. La subida del comprobante usa el bucket `reservation-receipts` con prefijo `<organizationId>/<reservationId>/`. Si `storage.upload` falla, llamar `confirm` sin `receipt_path` y devolver `{ receiptStored: false }`
- [ ] T011 [P] [US1] Crear `src/app/features/sales/reservations/reservation-list/reservation-list.component.ts`: `app-data-table`, título «Reservas», vacío «Todavía no hay reservas.», columnas Localizador, Cliente, Estado, Inicio, Total, Saldo
- [ ] T012 [US1] Crear `src/app/features/sales/reservations/reservation-confirm/reservation-confirm.component.ts` (OnPush, `unsavedChangesGuard`): lee `quotationVersionId`, muestra el total congelado sin recalcular, formulario de pasajeros (nombre y apellido obligatorios; documento, nacimiento y requisitos opcionales), pago con método Transferencia/Efectivo/Tarjeta/Otro, monto, fecha y referencia, archivo opcional. Botón «Confirmar reserva». Errores con los textos de T007. Si el archivo falla: «No se pudo guardar el archivo. La referencia queda registrada.» Sección admin «Anticipo y teléfono de asistencia» que llama `upsert_reservation_settings`. Checkbox «Eximir anticipo» solo admin, con «La exención del anticipo necesita un motivo.»
- [ ] T013 [US1] En `src/app/app.routes.ts`, bajo `sales` y `roleGuard('agent')`, agregar `reservations`, `reservations/new` (`unsavedChangesGuard`, antes de `:id`) y `reservations/:id`. En `src/app/shared/layout/nav-items.ts` agregar `{ id: 'sales-reservations', label: 'Reservas', path: '/sales/reservations', minRole: 'agent' }` dentro de Comercial. Actualizar `src/app/shared/layout/nav-items.spec.ts`
- [ ] T014 [US1] En `src/app/features/sales/quotations/quotation-editor/quotation-editor.component.ts`, si el estado es `accepted`, mostrar el enlace «Confirmar reserva» hacia `/sales/reservations/new?quotationVersionId=<id>`. No llamar a `confirm_reservation` desde el módulo de cotizaciones

**Checkpoint**: Existe la reserva y el listado. El ciclo operativo todavía no.

---

## Phase 4: User Story 2 - Ciclo de vida (Priority: P1)

**Goal**: Operador pasa Confirmada → En ejecución → Completada. Esas transiciones rechazan a un agente. Completada es terminal.

**Independent Test**: Escenario 2 de quickstart.md y `reservation_lifecycle_test.sql`.

### Tests for User Story 2

- [ ] T015 [P] [US2] Crear `supabase/tests/reservation_lifecycle_test.sql`: agente en `start_reservation` → `INSUFFICIENT_PERMISSIONS`; operador `confirmed` → `in_progress` → `completed`; desde `completed`, `cancel_reservation` (aunque la RPC llegue en US3, este test solo cubre `start` y `complete`) → `INVALID_TRANSITION` o `RESERVATION_TERMINAL` si ya se valida aquí; saltar de `confirmed` a `completed` → `INVALID_TRANSITION`; cada paso escribe `reservation_events` y audita `reservation_status_changed` con `{ from, to }` sin nombres

### Implementation for User Story 2

- [ ] T016 [US2] Crear `supabase/migrations/053_us2_reservation_lifecycle.sql` con `start_reservation` y `complete_reservation` (`require_catalog_manager`, `GRANT EXECUTE` a `authenticated`) según contracts §3
- [ ] T017 [US2] Extender `reservation.service.ts` con `start` y `complete`. En `src/app/features/sales/reservations/reservation-detail/reservation-detail.component.ts` mostrar localizador, estado, viajeros, saldo y botones «Pasar a en ejecución» y «Marcar completada» solo si `allowedTransition` lo permite para el rol. Al rechazarse, «Ese cambio de estado no está permitido.» o «Esta reserva está cerrada.»

**Checkpoint**: El viaje se puede cerrar como completado. Cancelar y reprogramar llegan en US3.

---

## Phase 5: User Story 3 - Cancelaciones y cambios (Priority: P2)

**Goal**: Cancelar, reprogramar sin nuevo localizador, marcar proveedor incumplido y reemplazar sin cambiar el total salvo un administrador.

**Independent Test**: Escenario 3 de quickstart.md y `reservation_changes_test.sql`.

### Tests for User Story 3

- [ ] T018 [P] [US3] Crear `supabase/tests/reservation_changes_test.sql`: cancelar `confirmed` guarda `refund_amount = round(total * percent / 100, 2)` y el localizador no cambia; la auditoría `reservation_cancelled` no contiene el motivo; cancelar `in_progress` como operador → `INSUFFICIENT_PERMISSIONS`; como admin sin informe → `CONTINGENCY_REQUIRED`; `completed` → `RESERVATION_TERMINAL`; tras cancelar, `confirm_reservation` de la misma cotización crea otro localizador; `reschedule_reservation` deja `rescheduled` y `accept_reschedule` vuelve a `confirmed` con el mismo locator; `add_replacement_item` no cambia `reservations.total`; `adjust_reservation_total` como agente → `INSUFFICIENT_PERMISSIONS` y como admin audita `previous_total` y `new_total` sin el motivo

### Implementation for User Story 3

- [ ] T019 [US3] Crear `supabase/migrations/054_us3_reservation_changes.sql` con `cancel_reservation`, `reschedule_reservation`, `accept_reschedule`, `mark_item_provider_failed`, `add_replacement_item` y `adjust_reservation_total` según contracts §4
- [ ] T020 [US3] En `reservation-detail.component.ts` y `reservation.service.ts` agregar «Cancelar reserva» (motivo, «Porcentaje de reembolso», y «Informe de contingencia» si el estado es `in_progress`), «Reprogramar», «El proveedor aceptó las nuevas fechas», «Marcar proveedor incumplido», «Agregar servicio de reemplazo» y, solo admin, el ajuste de total. Tras reemplazar, el total mostrado sigue siendo el de la reserva hasta que un admin lo cambie

**Checkpoint**: La misma reserva absorbe cancelación y cambio de fechas.

---

## Phase 6: User Story 4 - Órdenes de servicio (Priority: P2)

**Goal**: Ficha por proveedor, sin precios ni otros prestadores, copiable e imprimible, marcada transmitida a mano.

**Independent Test**: Escenario 4 de quickstart.md y `service_orders_test.sql`.

### Tests for User Story 4

- [ ] T021 [P] [US4] Crear `supabase/tests/service_orders_test.sql`: con dos proveedores, cada `build_service_order` incluye sus servicios y los nombres de pasajeros, y no incluye `total`, la moneda, `line_total` ni el nombre del otro proveedor; `mark_service_order_transmitted` escribe `transmitted_at` y audita `service_order_transmitted` con `{ provider_id }`; un agente recibe `INSUFFICIENT_PERMISSIONS`; no existe ninguna función de envío

### Implementation for User Story 4

- [ ] T022 [US4] Crear `supabase/migrations/055_us4_service_orders.sql` con `build_service_order` y `mark_service_order_transmitted` (`require_catalog_manager`) según contracts §5. El texto lo arma SQL
- [ ] T023 [US4] En `reservation-detail.component.ts` agregar la sección «Orden de servicio» por proveedor, con «Copiar orden», «Imprimir» (`window.print()` sobre el voucher y sobre la orden) y «Marcar como transmitida». Aviso fijo: «La orden no se envía sola. Cópiela o imprímala.» Sección «Voucher de reserva» con localizador, itinerario y políticas. Si no hay teléfono de asistencia: «La agencia indicará el teléfono de asistencia.» El voucher no muestra pagos. No abrir `wa.me` ni `mailto`

**Checkpoint**: US1–US4 listas. No hay envío saliente ni pasarela.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T024 [P] Crear `docs/modules/reservations.md` al estilo de `docs/modules/customer-requests.md`: propósito; migraciones `049`–`055`; RPCs y roles; localizador; anticipo 30 % y degradación del archivo; estados; orden sin envío; voucher autenticado; qué no hace (pasarela, factura, WhatsApp, cambio de pre-reserva)
- [ ] T025 [P] En `AGENTS.md`, antes de `<!-- SPECKIT START -->`, agregar `Reservations (confirmed trips, manual deposit, service orders): see docs/modules/reservations.md.` sin borrar los párrafos ya existentes
- [ ] T026 [P] Documentar `/sales/reservations`, `/sales/reservations/new` y `/sales/reservations/:id` en `docs/modules/identity-access.md` y en `specs/010-admin-layout-navigation/contracts/ui-contracts.md` (agent y superiores). Árbol: «Comercial / Reservas»
- [ ] T027 [P] En el comentario de `supabase/tests/run-sql-tests.sh` listar `reservation_confirm_test.sql`, `reservation_rls_test.sql`, `reservation_lifecycle_test.sql`, `reservation_changes_test.sql` y `service_orders_test.sql`. No cambiar la lógica
- [ ] T028 Revisar que `049`–`055` no escriban PII en `audit.log_event` y que confirmar no haga `UPDATE` de `pre_reservations` ni `quotation_versions`

---

## Phase 8: Verification

- [ ] T029 Ejecutar `npm test -- --watch=false`
- [ ] T030 Ejecutar `npm run lint`
- [ ] T031 Ejecutar `npm run build`
- [ ] T032 Ejecutar `./supabase/tests/run-sql-tests.sh`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup**: ninguna.
- **Foundational**: T002 → T003 → T004. T005 después de T004. T006 y T007 en paralelo con las migraciones.
- **US1**: T008 antes de T009. T011 en paralelo con T010 tras T009. T012 después de T010. T013 después de T011 y T012. T014 después de T013 y del editor de 005.
- **US2**: depende de US1 (hace falta una reserva). T015 antes de T016. T017 después de T016.
- **US3**: depende de US1. Puede seguir a US2 porque cancela también `in_progress`. T018 antes de T019.
- **US4**: depende de US1. T021 antes de T022. T023 después de T022 y de T017 (mismo componente de detalle: T023 después de T017).
- **Polish** y **Verification** al final. Verification no se marca hecha aquí.

### User Story Dependencies

- **US1 (P1)**: MVP. Confirmar y listar.
- **US2 (P1)**: US1. Transiciones de operador.
- **US3 (P2)**: US1. Cancelar una confirmada no necesita US2; cancelar en ejecución sí, y el test cubre ambos.
- **US4 (P2)**: US1. La UI espera el detalle de US2 para no pisar el mismo archivo: T023 va después de T017.

### Parallel Opportunities

- T006 y T007 con las migraciones de fundación.
- T011 junto con T010.
- Tras US1, las suites T015, T018 y T021 pueden escribirse en paralelo. Las migraciones de US3 y US4 también, si no tocan el mismo archivo. La UI de US3 y US4 es secuencial sobre `reservation-detail.component.ts`.

---

## Parallel Example: User Story 1

```bash
# Tras T009:
Task: "T010 [US1] ReservationService en src/app/core/reservations/services/reservation.service.ts"
Task: "T011 [US1] ReservationListComponent en src/app/features/sales/reservations/reservation-list/"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 y 2.
2. US1: confirmar con anticipo y localizador.
3. Parar. Aún no hay ciclo ni órdenes.

### Incremental Delivery

1. US1 demo de confirmación.
2. US2 demo de en ejecución y completada.
3. US3 demo de cancelación y reprogramación.
4. US4 demo de orden copiada, sin envío.
5. Polish y Phase 8.

---

## Notes

- Última migración: `055_us4_service_orders.sql`. La feature 007 empieza en `056`.
- El voucher no tiene ruta anónima.
- El archivo del comprobante es opcional. La referencia no lo es, salvo exención de administrador.
- No marcar tareas como hechas en este archivo.
