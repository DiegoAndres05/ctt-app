---
description: "Task list for 006-reservation-lifecycle implementation"
---

# Tasks: 006-reservation-lifecycle (Comercial — Reservas)

**Input**: Design documents from `/specs/006-reservation-lifecycle/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-contracts.md, quickstart.md. Features 001–005 implementadas. Última migración de 005: `048_us4_quotation_responses.sql`. Esta feature empieza en `049`. No editar `042`–`048`. No llamar pasarelas ni APIs de WhatsApp/email. No revertir `supabase/config.toml` ni `src/environments/environment.development.ts`.

**Tests**: Suites SQL (convención del repo + plan.md) y Vitest de modelos/errores. Quedan sin marcar: las ejecuta quien implemente.

**Organization**: Tareas por historia (US1–US4 de spec.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede ejecutarse en paralelo (archivo distinto, sin dependencias pendientes)
- **[Story]**: US1–US4 según spec.md
- Rutas exactas de archivo en cada tarea

## Path Conventions

- **Backend**: `supabase/migrations/` desde `049_`, `supabase/tests/`, `supabase/seed.sql`
- **Frontend**: `src/app/core/reservations/`, `src/app/features/sales/reservations/`, `src/app/features/public-voucher/`, `src/app/app.routes.ts`
- **Docs**: `docs/modules/reservations.md`

## Conventions every task must follow

- **SQL**: estilo de `supabase/migrations/045_us1_quotation_draft.sql`: cabecera, `SECURITY DEFINER`, `SET search_path = ''`, nombres calificados, `RAISE EXCEPTION '<CODE>' USING ERRCODE = 'raise_exception'`, `REVOKE ALL` a `PUBLIC` y `GRANT EXECUTE` explícito. Auditoría solo con `audit.log_event` y sin PII, documentos, referencias bancarias ni token en `metadata`. Fechas de calendario en `America/Bogota`.
- **Suites SQL**: estructura de `supabase/tests/quotation_issue_test.sql` (`BEGIN`/`ROLLBACK`, `pg_temp.act_as`, `tests.assert_*`, `SET LOCAL ROLE`).
- **Angular**: standalone, `ChangeDetectionStrategy.OnPush`, signals, `form()` de `@angular/forms/signals`, listados con `app-data-table` y paginación `range` + `count: 'exact'`, `toAppError`, textos en español de contracts §4. La UI no suma pagos ni totales: pinta `paid_total` y `balance` del servidor.
- **No** referenciar la service role key desde `src/`. **No** llamar a la API de WhatsApp. **No** editar migraciones `042`–`048` (sí invocar `assert_quotation_confirmable` desde 006).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Carpetas de la capacidad nueva.

- [X] T001 Crear carpetas con `.gitkeep`: `src/app/core/reservations/models/`, `src/app/core/reservations/services/`, `src/app/features/sales/reservations/reservation-list/`, `src/app/features/sales/reservations/reservation-confirm/`, `src/app/features/sales/reservations/reservation-detail/`, `src/app/features/public-voucher/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Enums, tablas, RLS, modelos y códigos de error. Ninguna historia empieza antes.

- [X] T002 Crear `supabase/migrations/049_reservation_enums.sql` según data-model §Enums: `reservation_status`, `reservation_item_ops_status`, `payment_method`, `id_document_type`, `provider_notify_channel`; `ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS` para `reservation_confirmed`, `reservation_status_changed`, `reservation_cancelled`, `reservation_version_created`, `reservation_payment_recorded`, `reservation_provider_notified`, `reservation_item_reassigned`, `reservation_voucher_voided`
- [X] T003 Crear `supabase/migrations/050_reservations.sql` según data-model: tablas `reservation_families`, `reservation_versions`, `reservation_passengers`, `reservation_items`, `reservation_payments` (append-only), FKs, unique de `quotation_version_id` y `reference` por org, índice único parcial de una versión no `superseded` por familia, trigger `RESERVATION_FROZEN`, RLS SELECT por `organization_id`, `REVOKE ALL` a `anon`, vista `reservation_list` `security_invoker` sin email/teléfono/token/documentos, stub de bucket `reservation-receipts` (patrón `026_catalog_media_bucket.sql`)
- [X] T004 [P] Crear `supabase/tests/reservation_rls_test.sql`: `anon` no hace SELECT de tablas ni de la vista; otra organización no ve filas; `assert_quotation_confirmable` sigue sin `EXECUTE` para `anon`/`authenticated`; las funciones internas de 050 no tienen GRANT a esos roles
- [X] T005 [P] Crear `src/app/core/reservations/models/reservation.model.ts` y `reservation.model.spec.ts`: estados, etiquetas (`Confirmada`, `En ejecución`, `Completada`, `Cancelada`, `Superada`), `isReservationTerminal`, `canClientSumPayments = false`, tipos de depósito/pasajero/ítem alineados a `reservation_list` y contracts §1
- [X] T006 [P] Registrar en `src/app/core/error/error-handler.ts` y cubrir en `error-handler.spec.ts`: `QUOTATION_NOT_ACCEPTED` «Solo se confirma una cotización aceptada.» (si ya existe, no cambiar el texto), `RESERVATION_ALREADY_EXISTS` «Esta cotización ya tiene una reserva.», `DEPOSIT_REQUIRED` «Registra un depósito mayor que cero.», `CURRENCY_MISMATCH` «La moneda del pago debe coincidir con la cotización.», `PASSENGER_COUNT_MISMATCH` «El número de pasajeros debe coincidir con la cotización.», `INVALID_TRANSITION` «Ese cambio de estado no está permitido.», `ADMIN_REQUIRED` «Hace falta un administrador y un informe de contingencia.», `CONTINGENCY_REQUIRED` «Indique el informe de contingencia.», `RESERVATION_FROZEN` «Esta reserva no se edita.», `VOID_REASON_REQUIRED` reutilizar si existe

**Checkpoint**: Tablas, vista y etiquetas listas. Las RPC de historias todavía no existen.

---

## Phase 3: User Story 1 - Confirmación formal (Priority: P1) 🎯 MVP

**Goal**: El agente confirma una cotización aceptada con depósito y pasajeros, obtiene `RSV-#####` y un token de voucher una vez.

**Independent Test**: Escenario 1 de `quickstart.md` y `reservation_confirm_test.sql`.

### Tests for User Story 1

- [X] T007 [P] [US1] Crear `supabase/tests/reservation_confirm_test.sql`: cotización `accepted` + depósito + pax correctos crea `RSV-00001` y un pago; `issued`/`expired` levantan `QUOTATION_NOT_ACCEPTED`; segunda confirmación de la misma versión `RESERVATION_ALREADY_EXISTS`; pax de menos `PASSENGER_COUNT_MISMATCH`; depósito 0 `DEPOSIT_REQUIRED`; `anon` no ejecuta `confirm_reservation`; el token no queda en `audit.metadata`

### Implementation for User Story 1

- [X] T008 [US1] Crear `supabase/migrations/051_us1_confirm_reservation.sql` con `confirm_reservation` y `record_reservation_payment` según contracts §1: llama `assert_quotation_confirmable`, secuencia `reservation`, hash SHA-256 del token, copia ítems del snapshot, audita `reservation_confirmed` y `reservation_payment_recorded` sin PII. `GRANT EXECUTE` a `authenticated`
- [X] T009 [US1] Crear `src/app/core/reservations/services/reservation.service.ts`: `listPage` sobre `reservation_list`, `confirm(...)`, `recordPayment(...)`. Tras confirmar, guardar token en `sessionStorage` clave `reservation-token:<familyId>`. No sumar importes
- [X] T010 [P] [US1] Crear `src/app/features/sales/reservations/reservation-list/reservation-list.component.ts`: `app-data-table` título «Reservas», vacío «Todavía no hay reservas.», columnas Localizador, Cliente, Estado, Viaje, Total, Saldo; búsqueda
- [X] T011 [US1] Crear `src/app/features/sales/reservations/reservation-confirm/reservation-confirm.component.ts`: lee `quotationVersionId`, formulario de depósito y lista de pasajeros, textos de contracts §4, éxito «Reserva RSV-00001 confirmada. El voucher se muestra una sola vez.»
- [X] T012 [US1] Registrar en `src/app/app.routes.ts` bajo `sales` las rutas `reservations`, `reservations/new` (`unsavedChangesGuard`, antes de `:id`) y `reservations/:id` (detalle placeholder hasta US2). `roleGuard('agent')`. En `nav-items.ts` hijo `{ id: 'sales-reservations', label: 'Reservas', path: '/sales/reservations', minRole: 'agent' }` después de Cotizaciones. Actualizar `nav-items.spec.ts`
- [X] T013 [US1] En `quotation-editor.component.ts` (005, no reescribir el resto), si status `accepted`, enlace «Confirmar reserva» a `/sales/reservations/new?quotationVersionId=<id>`

**Checkpoint**: Se confirma una cotización aceptada y aparece en el listado. Aún no hay transiciones ni voucher público.

---

## Phase 4: User Story 2 - Ciclo de vida (Priority: P1)

**Goal**: Operador pasa Confirmada → En ejecución → Completada; las transiciones ilegales se rechazan.

**Independent Test**: Escenario 2 de `quickstart.md` y `reservation_lifecycle_test.sql`.

### Tests for User Story 2

- [X] T014 [P] [US2] Crear `supabase/tests/reservation_lifecycle_test.sql`: `confirmed`→`in_progress`→`completed` ok; `completed`→`confirmed` `INVALID_TRANSITION`; agente no operador según research §9 (si el guard es operador, el agente recibe `INSUFFICIENT_PERMISSIONS`); audita `reservation_status_changed` sin PII

### Implementation for User Story 2

- [X] T015 [US2] Crear `supabase/migrations/052_us2_reservation_lifecycle.sql` con `transition_reservation_status` según contracts §1 y research §4
- [X] T016 [US2] Crear `src/app/features/sales/reservations/reservation-detail/reservation-detail.component.ts` y métodos `get`/`transition` en `reservation.service.ts`: muestra estado, fechas, totales del servidor, pasajeros (sin editar), botones de transición visibles para operador/admin. Completar el load de `reservations/:id`

**Checkpoint**: El ciclo Confirmada → En ejecución → Completada funciona. Cancelar y versiones todavía no.

---

## Phase 5: User Story 3 - Cancelaciones y versiones (Priority: P2)

**Goal**: Cancelar con motivo; en curso solo admin + informe; nueva versión de fechas/pax conservando pagos.

**Independent Test**: Escenarios 3–4 de `quickstart.md` y `reservation_changes_test.sql`.

### Tests for User Story 3

- [X] T017 [P] [US3] Crear `supabase/tests/reservation_changes_test.sql`: cancelar `confirmed` con motivo; agente en `in_progress` `ADMIN_REQUIRED` o `CONTINGENCY_REQUIRED`; admin con informe ok; `create_reservation_version` deja v1 `superseded` y v2 abierta; pagos de familia intactos; terminal `RESERVATION_FROZEN`

### Implementation for User Story 3

- [X] T018 [US3] Crear `supabase/migrations/053_us3_cancel_and_version.sql` con `cancel_reservation` y `create_reservation_version` según contracts §1
- [X] T019 [US3] Extender `reservation.service.ts` y `reservation-detail.component.ts`: cancelar, informe de contingencia, formulario de nueva versión; no mutar v1 in-place

**Checkpoint**: Cancelar y reprogramar (versión nueva) quedan auditados. Órdenes a proveedor todavía no.

---

## Phase 6: User Story 4 - Proveedores y voucher (Priority: P2)

**Goal**: Orden por prestador sin precios de venta ni otros proveedores; voucher imprimible y `/r/:token`.

**Independent Test**: Escenarios 5–6 de `quickstart.md`, `service_orders_test.sql` y `reservation_public_voucher_test.sql`.

### Tests for User Story 4

- [X] T020 [P] [US4] Crear `supabase/tests/service_orders_test.sql`: texto de orden del ítem A no incluye prestador B ni `line_total`; `mark_provider_order_sent` pasa a `confirmed_with_provider`; `reassign_reservation_item_provider` vuelve a `pending_provider`
- [X] T021 [P] [US4] Crear `supabase/tests/reservation_public_voucher_test.sql`: token válido sin `customer_id`/email/documentos/totales; desconocido `{ available: false }`; `anon` ejecuta `get_public_voucher` y no SELECT tablas; void deja unavailable

### Implementation for User Story 4

- [X] T022 [US4] Crear `supabase/migrations/054_us4_provider_orders_voucher.sql` con `mark_provider_order_sent`, `reassign_reservation_item_provider`, `reservation_provider_order_text`, `reservation_whatsapp_text`, `get_public_voucher`, `void_reservation_voucher`, `rotate_reservation_voucher` según contracts §1–§2. Políticas del bucket privado
- [X] T023 [US4] Extender `reservation.service.ts` y `reservation-detail.component.ts`: copiar orden, marcar enviada, reasignar, «Copiar para WhatsApp», «Imprimir» (`window.print()`), aviso si no hay token
- [X] T024 [P] [US4] Crear `src/app/features/public-voucher/public-voucher.component.ts` y ruta pública `r/:token` en `app.routes.ts` (fuera del shell, sin `authGuard`). Textos contracts §4. CSS usable a 360 px

**Checkpoint**: US1–US4 independientes. Falta documentación y seed.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Módulo documentado, seed demo, comentario de suites, abonos extra y comprobante.

- [X] T025 [P] Crear `docs/modules/reservations.md` (tablas, RPCs, estados, rutas, frontera 005, sección Quickstart mapping vacía/Not verified)
- [X] T026 [P] Extender `supabase/seed.sql` con una reserva demo idempotente del tenant semilla **solo si** ya hay cotización aceptada de 005; si no hay, documentar el orden en el módulo y no fallar el seed
- [X] T027 Actualizar el comentario de suites 006 en `supabase/tests/run-sql-tests.sh` para incluir `reservation_public_voucher_test.sql` (el glob ya las ejecuta)
- [X] T028 En `reservation-detail` permitir `record_reservation_payment` (abono extra) y mostrar `balance` del servidor; subir comprobante al prefijo `{orgId}/{familyId}/` del bucket `reservation-receipts`
- [X] T029 Añadir puntero en `docs/modules/quotations.md` (Boundary with 006) a `docs/modules/reservations.md` y en `AGENTS.md` el párrafo de reservas si aún apunta a un archivo inexistente
- [X] T030 Anotar en `docs/modules/reservations.md` §Quickstart mapping el resultado de los escenarios 1–7 cuando se corran (browser vs SQL). No marcar este ítem hasta esa pasada

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: inmediata
- **Foundational (Phase 2)**: bloquea todas las historias
- **US1 (Phase 3)**: MVP; US2–US4 asumen que existe al menos una reserva `confirmed`
- **US2**: detalle de reserva
- **US3**: cancela/versiona sobre el detalle de US2
- **US4**: órdenes y voucher sobre el mismo detalle
- **Polish**: tras las historias deseadas

### User Story Dependencies

- **US1 (P1)**: tras Phase 2 — MVP
- **US2 (P1)**: tras US1 (necesita `reservations/:id`)
- **US3 (P2)**: tras US2 (mismos botones de detalle)
- **US4 (P2)**: tras US1 (token); el detalle de US2 es el lugar natural de las acciones

### Parallel Opportunities

- T004, T005, T006 en paralelo tras T003
- T007 en paralelo a T008 una vez definidos los contratos (el test puede escribirse contra el contrato y fallar hasta T008)
- T010 en paralelo a T011
- T014 / T017 / T020 / T021 en paralelo cuando existan las migraciones correspondientes
- T024 en paralelo a T023
- T025 / T026 en paralelo

---

## Parallel Example: User Story 1

```bash
Task: "T007 reservation_confirm_test.sql"
Task: "T010 reservation-list.component.ts"
# Tras T008:
Task: "T009 reservation.service.ts"
Task: "T011 reservation-confirm.component.ts"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 y Phase 2.
2. US1 hasta listado + confirmación + token.
3. Parar y validar escenario 1. Aún no hay ciclo ni voucher público.

### Incremental Delivery

1. US1 → demo de confirmación.
2. US2 → demo de estados.
3. US3 → demo de cancelar / nueva versión.
4. US4 → demo de órdenes y `/r/:token`.
5. Polish.

---

## Notes

- Última migración de esta feature: `054_us4_provider_orders_voucher.sql`. 007/008 no dependen de un número concreto.
- `assert_quotation_confirmable` (048) no se altera; `RESERVATION_ALREADY_EXISTS` se lanza en `confirm_reservation`.
- El token en claro vive en la respuesta de `confirm_reservation` y en `sessionStorage`. La base guarda el hash.
- No marcar ninguna tarea como hecha en este archivo hasta implementar.
