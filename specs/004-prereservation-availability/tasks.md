---
description: "Task list for 004-prereservation-availability implementation"
---

# Tasks: 004-prereservation-availability (Comercial — Pre-Reservas y Verificación de Disponibilidad)

**Input**: Design documents from `/specs/004-prereservation-availability/`

**Prerequisites**: plan.md, spec.md (clarificado 2026-10-04), research.md, data-model.md, contracts/api-contracts.md, quickstart.md. Features 001, 002, 003, 009 y 010 ya implementadas; última migración existente `034_us4_customer_privacy.sql`.

**Tests**: Incluidos por convención del proyecto: suites SQL (`supabase/tests/*_test.sql`, harness Postgres 17 vía `./supabase/tests/run-sql-tests.sh`) para RLS y reglas de RPC, y Vitest (`npm test`) para lógica TypeScript pura.

**Organization**: Tareas agrupadas por historia de usuario (US1–US4 de spec.md) para implementar y probar cada una por separado.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede ejecutarse en paralelo (archivo distinto, sin dependencias pendientes)
- **[Story]**: US1–US4 según spec.md
- Rutas exactas de archivo en cada tarea

## Path Conventions

- **Backend**: `supabase/migrations/` (desde `035_`), `supabase/tests/`, `supabase/seed.sql`
- **Frontend**: `src/app/core/pre-reservations/`, `src/app/features/sales/`, `src/app/shared/`, `src/app/app.routes.ts`
- **Docs**: `docs/modules/`

## Conventions every task must follow

- **SQL**: copiar el estilo de `supabase/migrations/030_customer_intake_core.sql` y `033_us3_request_workflow.sql`: cabecera con propósito y fuente de verdad, `SECURITY DEFINER`, `SET search_path = ''`, nombres totalmente calificados (`public.`, `audit.`), `RAISE EXCEPTION '<CODE>' USING ERRCODE = 'raise_exception'` (o `insufficient_privilege` en permisos), `REVOKE ALL ON FUNCTION … FROM PUBLIC` y luego `GRANT EXECUTE` explícito. Auditoría solo con `audit.log_event(org, event_type, result, actor, resource_type, resource_id, metadata)` y **sin PII en `metadata`**. Fechas "hoy" = `(now() AT TIME ZONE 'America/Bogota')::date`.
- **Suites SQL**: copiar la estructura de `supabase/tests/request_workflow_test.sql` (`BEGIN; … ROLLBACK;`, helpers `pg_temp.add_collaborator` y `pg_temp.act_as`, `tests.assert_true`, `tests.assert_equals`, `tests.assert_raises`, `SET LOCAL ROLE anon|authenticated|service_role`). Usar UUIDs fijos propios de la suite.
- **Angular**: standalone + `ChangeDetectionStrategy.OnPush` + signals; formularios con `form()` de `@angular/forms/signals` (ADR-0001) como `src/app/features/sales/requests/request-intake/request-intake.component.ts`; listados con paginación en servidor como `RequestService.listPage` (`src/app/core/customers/services/request.service.ts`, `range` + `count: 'exact'`); secciones con `<section class="section">` + `<h2>` y clases `.incomplete` / `.is-disabled` de `src/styles.scss`; errores con `toAppError`; textos de UI en español.
- **No** referenciar la service role key desde `src/`. **No** revertir los cambios locales existentes en `supabase/config.toml` ni `src/environments/environment.development.ts`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Carpetas de la capacidad nueva

- [x] T001 Crear la estructura de carpetas con `.gitkeep`: `src/app/core/pre-reservations/models/`, `src/app/core/pre-reservations/services/`, `src/app/features/sales/pre-reservations/pre-reservation-list/`, `src/app/features/sales/pre-reservations/pre-reservation-create/`, `src/app/features/sales/pre-reservations/pre-reservation-detail/`, `src/app/features/sales/verification/verification-queue/`, `src/app/features/sales/verification/verification-outcome-form/`, `src/app/shared/layout/verified-notice/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Esquema base, núcleo único de estado y creación, modelos y piezas compartidas de UI que usan todas las historias

**⚠️ CRITICAL**: Ninguna historia comienza hasta cerrar esta fase

- [x] T002 `supabase/migrations/035_pre_reservation_enums.sql` ya existe (enums: pre_reservation_status, availability_status, provider_contact_method, availability_event_kind; valores audit_event_type). Source: data-model.md §Enums + research.md R-003, R-007.
- [x] T003 `supabase/migrations/036_pre_reservations.sql` ya existe (tablas: pre_reservations, pre_reservation_items, availability_verification_events; vistas pre_reservation_list, availability_verification_queue; RLS, Realtime). Source: data-model.md §0-§3 + §Views.
- [x] T004 `supabase/migrations/036_pre_reservations.sql` completado (vistas Realtime, RLS, UNIQUE en providers). Reutiliza 035.
- [x] T005 `supabase/migrations/037_pre_reservation_core.sql` ya existe (núcleo: require_availability_verifier, resolve_pre_reservation_item, log_availability_event, insert_pre_reservation_item, refresh_pre_reservation_status, create_pre_reservation_core). Source: data-model.md §Functions + research R-002/R-003/R-005/R-006.
- [x] T006 [P] `supabase/tests/pre_reservation_core_test.sql` ya creado por el subagent previo (pruebas de núcleo: conversión, validaciones, refresh, referencias PRE-#####, estado derivado). Source: tasks.md T006.
- [x] T007 [P] Crear `supabase/tests/pre_reservation_rls_test.sql` (parte fundacional): como `anon`, `SELECT` sobre las tres tablas y las dos vistas falla por privilegios; como `authenticated` de la org A: ve solo filas de A, `INSERT`/`UPDATE`/`DELETE` directos rechazados en las tres tablas; `UPDATE`/`DELETE`/`TRUNCATE` sobre `availability_verification_events` fallan incluso como superusuario (append-only); `EXECUTE` de `require_availability_verifier`, `resolve_pre_reservation_item`, `insert_pre_reservation_item`, `refresh_pre_reservation_status`, `create_pre_reservation_core` denegado para `anon` y `authenticated` (`has_function_privilege`); cambiar `reference` de una pre-reserva o `start_date` de una línea como superusuario lanza `VALIDATION_ERROR`
- [x] T008 Extender `supabase/seed.sql` con un bloque `DO $$` nuevo (idempotente: termina si ya existen `pre_reservations` para la org demo `00000000-0000-4000-a000-000000000001`) que, vía `public.create_pre_reservation_core`, cree: (a) una pre-reserva desde la solicitud demo en `in_review` de 003 con dos líneas principales (un alojamiento con proveedor y una experiencia) y una alternativa; (b) otra desde una solicitud `received` nueva del cliente Laura Gómez con una línea; y deje (a) con una línea `available` (vía `UPDATE` directo con `verified_by` del operador demo) para mostrar «Parcialmente verificada»
- [x] T009 [P] Crear `src/app/core/pre-reservations/models/pre-reservation.model.ts`: tipos `PreReservationStatus`, `PreReservationListRow` (columnas de `pre_reservation_list`), `PreReservation` (cabecera), `PreReservationDetail` (cabecera + `request`, `customer`, `agent`, `operator` + `items` + `quote_eligible`/`has_quote_override`), `VerificationTimes`; `PRE_RESERVATION_STATUS_LABELS` (data-model §Enums); `ITEM_KIND_LABELS`; `isPreReservationClosed(status)` (`cancelled`); `quoteEligibilityReason(detail): string | null` (texto de no elegibilidad por estado: pendiente/parcial → «aún no está totalmente verificada», requiere ajuste → «tiene servicios por ajustar», expirada → «la disponibilidad confirmada venció», cancelada → «está cancelada»)
- [x] T010 [P] Crear `src/app/core/pre-reservations/models/verification.model.ts`: tipos `AvailabilityStatus`, `ProviderContactMethod`, `AvailabilityEventKind`, `VerificationQueueRow` (columnas de `availability_verification_queue`), `VerificationEvent` (columnas de `availability_verification_history`), `VerificationOutcomePayload`, `RecordOutcomeResult`; `AVAILABILITY_STATUS_LABELS`, `CONTACT_METHOD_LABELS`, `AVAILABILITY_EVENT_KIND_LABELS` (data-model §Enums)
- [x] T011 [P] Crear `src/app/core/pre-reservations/models/pre-reservation.model.spec.ts` (Vitest) cubriendo `isPreReservationClosed`, `quoteEligibilityReason` para los seis estados (con y sin excepción), y que todas las claves de `PreReservationStatus`, `AvailabilityStatus`, `ProviderContactMethod` y `AvailabilityEventKind` tienen etiqueta
- [x] T012 [P] Crear `src/app/core/pre-reservations/provider-contact-links.ts` con `providerContactLinks(p: { provider_phone?: string | null; provider_email?: string | null }): { tel?: string; whatsapp?: string; mailto?: string }` (`tel:` con el teléfono sin espacios; `https://wa.me/` solo con los dígitos; `mailto:` con el correo; omite lo que falte) y `src/app/core/pre-reservations/provider-contact-links.spec.ts` (Vitest) con teléfono `+57 300 111 2233` → `wa.me/573001112233`, sin teléfono → sin `tel`/`whatsapp`, sin correo → sin `mailto`
- [x] T013 [P] Ampliar `src/app/shared/components/data-table/list-query.ts`: agregar `providerId` y `group` a `ListQuery`, `emptyListQuery`, `parseListQuery`, `listQueryToParams`, `FILTER_KEYS` y `hasActiveListFilters` (mismo tratamiento que `channel`/`assignee`); actualizar `src/app/shared/components/data-table/list-query.spec.ts` con parseo, omisión de vacíos y reinicio de página al cambiar `providerId`/`group`
- [x] T014 [P] Agregar los 13 códigos de contracts §7 a `AuthErrorCode` en `src/app/core/auth/models/auth.model.ts` y sus mensajes exactos a `USER_FACING_MESSAGES` en `src/app/core/error/error-handler.ts`; agregar a `src/app/core/error/error-handler.spec.ts` casos que mapean `{ message: 'PRE_RESERVATION_REQUIRES_ITEMS' }`, `{ message: 'HOLD_EXPIRY_IN_PAST' }` y `{ message: 'OVERRIDE_NOT_REQUIRED' }` a su código y mensaje
- [x] T015 [P] Crear `src/app/core/pre-reservations/services/pre-reservation.service.ts` (parte de lectura, patrón de `RequestService`): `sweepExpired()` (RPC `expire_due_pre_reservations`; si falla solo `console.warn` y la lectura sigue, research R-004), `listPage({ q, status, responsibleId, page })` (vista `pre_reservation_list`, `count: 'exact'`, `range` de 20, orden `created_at desc`, filtros de contracts §5), `listForRequest(requestId)`, `getById(id)` (cabecera + relaciones + líneas incluidas retiradas + elegibilidad, selects exactos de contracts §5), `listBookables()` (productos activos con `provider` y complementos activos), `listOperators()` (`user_profiles` activos con rol `operator`/`admin`)
- [x] T016 Agregar el grupo de rutas de pre-reservas a `src/app/app.routes.ts` dentro de `sales.children`: `{ path: 'pre-reservations', canActivate: [roleGuard('agent')], children: [ { path: '', pathMatch: 'full', redirectTo: 'list' } ] }` (placeholder que las historias reemplazan); agregar `{ id: 'sales-pre-reservations', label: 'Pre-reservas', path: '/sales/pre-reservations', minRole: 'agent' }` como segundo hijo de `sales` (tras `sales-requests`) en `src/app/shared/layout/nav-items.ts` y actualizar `src/app/shared/layout/nav-items.spec.ts`

**Checkpoint**: `./supabase/tests/run-sql-tests.sh pre_reservation_core_test.sql pre_reservation_rls_test.sql` y `npm test` en verde; el núcleo y las lecturas existen pero no hay UI todavía

---

## Phase 3: User Story 1 - Conversión de Solicitud a Pre-Reserva (Priority: P1) 🎯 MVP

**Goal**: El agente/operador convierte una solicitud en una pre-reserva con líneas concretas desde el detalle de la solicitud, y consulta el detalle y la lista de pre-reservas.

**Independent Test**: Escenario 1 de quickstart.md; suite `pre_reservation_core_test.sql` en verde y recorrido manual de creación → detalle → lista.

### Tests for User Story 1

- [x] T017 [P] [US1] Extender `supabase/tests/pre_reservation_core_test.sql` cubriendo `create_pre_reservation` como `authenticated`: agente, operador y admin pueden crear; `anon` no tiene `EXECUTE`; una solicitud de la org B devuelve `VALIDATION_ERROR` a un usuario de la org A; `assigned_operator_id` que no es operator/admin activo → `ASSIGNEE_NOT_OPERATOR`; la respuesta trae `{pre_reservation_id, reference, status: 'pending_verification', request_status}`; y `cancel_pre_reservation`: sin motivo → `CANCEL_REASON_REQUIRED`, motivo > 500 → `VALIDATION_ERROR`, doble cancelación → `PRE_RESERVATION_CLOSED`, escribe el evento `pre_reservation_cancelled` con el motivo en `notes` y la auditoría `pre_reservation_cancelled {from}` sin el motivo, y la solicitud origen conserva `pre_reservation`

### Implementation for User Story 1

- [x] T018 [US1] Crear `supabase/migrations/038_us1_pre_reservation_conversion.sql` con `public.create_pre_reservation(p_request_id uuid, p_payload jsonb) → jsonb` (`require_tenant_member()`, `GRANT EXECUTE … TO authenticated`; valida `assigned_operator_id` si viene: operator/admin activo de la org o `ASSIGNEE_NOT_OPERATOR`; delega en `create_pre_reservation_core`) y `public.cancel_pre_reservation(p_pre_reservation_id uuid, p_reason text) → jsonb` (`require_tenant_member()`; motivo 1–500 `CANCEL_REASON_REQUIRED`/`VALIDATION_ERROR`; `SELECT … FOR UPDATE`; ya cancelada → `PRE_RESERVATION_CLOSED`; fija `cancelled_at`, `cancel_reason`, `cancelled_by`; evento `pre_reservation_cancelled` con el motivo en `notes`; auditoría `pre_reservation_cancelled {from}` sin el motivo; la solicitud **no** cambia; devuelve `{pre_reservation_id, status: 'cancelled', cancelled_at}`)
- [x] T019 [P] [US1] Crear `src/app/features/sales/pre-reservations/pre-reservation-create/pre-reservation-payload.ts` con tipos `PreReservationItemDraft` (`kind: 'product' | 'addon'`, `productId`, `addonId`, `startDate`, `endDate`, `adults`, `children`, `quantity`, `providerName/Phone/Email`, `alternativeOf: number | null`, `sourceRequestItemId`), `validateItemDrafts(items, today: string): PreReservationIssue[]` (affordance: producto o complemento según `kind`; `startDate >= today`; alojamiento exige `endDate > startDate`; rangos 1–99/0–99/1–99; `alternativeOf` apunta a una fila principal anterior; al menos una principal) y `buildCreatePayload(items, assignedOperatorId): { items: PreReservationItemInput[]; assigned_operator_id: string | null }` (recorta textos, vacíos → `null`, `alternative_of` solo en filas alternativas, omite proveedor manual si el producto tiene proveedor); y `src/app/features/sales/pre-reservations/pre-reservation-create/pre-reservation-payload.spec.ts` (Vitest) con un caso por regla
- [x] T020 [US1] Extender `src/app/core/pre-reservations/services/pre-reservation.service.ts` con `create(requestId, payload): Promise<CreatePreReservationResult>` (RPC `create_pre_reservation`) y `cancel(id, reason): Promise<void>` (RPC `cancel_pre_reservation`), traduciendo errores con `toAppError`
- [x] T021 [US1] Crear `src/app/features/sales/pre-reservations/pre-reservation-create/pre-reservation-create.component.ts` (implementa `UnsavedChangesHost`, lee `requestId` de la query): carga la solicitud con `RequestService.getById`; encabezado «Nueva pre-reserva para SOL-#####»; aviso fijo «Una pre-reserva no es una reserva confirmada: requiere verificar disponibilidad con los proveedores.»; sección «Servicios» precargada desde los intereses de la solicitud que tienen producto (fechas y pasajeros de la solicitud), con el formulario de línea de contracts §6.4 (selector producto/complemento de `listBookables()`, «Desde»* con `min` = hoy, «Hasta» obligatoria en alojamientos, pasajeros, proveedor de solo lectura o campos manuales, «Es alternativa de», «Agregar servicio»/«Quitar»); sección «Verificación» con «Operador asignado» opcional (`listOperators()`); errores de `validateItemDrafts` junto a cada campo; al guardar llama `create`, marca `allowLeave` y navega a `/sales/pre-reservations/:id`; sin `requestId`: mensaje «Abre una solicitud y usa “Crear pre-reserva”.» con enlace a `/sales/requests`
- [x] T022 [P] [US1] Crear `src/app/features/sales/pre-reservations/pre-reservation-detail/pre-reservation-detail.component.ts` (input `id`, parte base): carga con `PreReservationService.getById` (llama antes a `sweepExpired()`); encabezado con `reference` + etiqueta de estado; alerta informativa fija «Esta pre-reserva no es una reserva confirmada. Requiere verificación de disponibilidad con los proveedores.»; secciones «Resumen» (solicitud enlazada, cliente enlazado a `/sales/customers/:id`, responsable, creada, vence) y «Servicios» (tabla de principales con sus alternativas indentadas y etiqueta «Alternativa»: servicio, fechas, pasajeros, proveedor con enlaces de `providerContactLinks`, estado, retención, verificado por; las retiradas en gris con «Retirado: <motivo>»); con la pre-reserva cancelada, todo en solo lectura con aviso «Pre-reserva cancelada: <motivo>»
- [x] T023 [P] [US1] Crear `src/app/features/sales/pre-reservations/pre-reservation-list/pre-reservation-list.component.ts`: `app-data-table` título «Pre-reservas», sin botón de crear; estado en query string con `parseListQuery`/`listQueryToParams`/`withListFilterChange`; filtros «Buscar» (referencia, solicitud o cliente), «Estado» (Todos + 6 etiquetas), «Responsable» (Todas / Mías / colaboradores de `listOperators()` + agentes); columnas de contracts §6.4 (referencia enlazada, solicitud enlazada, cliente, estado, primer servicio, verificadas `available/primary`, vence, responsable, creada); `emptyMessage` «Todavía no hay pre-reservas.»; datos desde `PreReservationService.listPage` (que barre expiradas antes)
- [x] T024 [US1] Actualizar `src/app/app.routes.ts` en `sales.pre-reservations.children`: `{ path: '', pathMatch: 'full', loadComponent: PreReservationListComponent }`, `{ path: 'new', canDeactivate: [unsavedChangesGuard], loadComponent: PreReservationCreateComponent }` **antes** de `{ path: ':id', loadComponent: PreReservationDetailComponent }`; actualizar el `redirectTo` del placeholder de T016 quitándolo
- [x] T025 [US1] Modificar `src/app/features/sales/requests/request-detail/request-detail.component.ts`: en la sección «Gestión», reemplazar el texto fijo «La pre-reserva se crea desde el módulo de pre-reservas.» por el botón «Crear pre-reserva» (`routerLink` a `/sales/pre-reservations/new?requestId=<id>`) visible si el estado es `received`, `in_review` o `pre_reservation` y el cliente no está anonimizado; agregar la sección «Pre-reservas» (tras «Gestión») con `PreReservationService.listForRequest(id)`: tabla con referencia enlazada, estado, fecha; texto «Esta solicitud todavía no tiene pre-reservas.» si está vacía

**Checkpoint**: US1 completa — una solicitud se convierte en pre-reserva, la solicitud pasa a «En Pre-Reserva», y la lista y el detalle se consultan

---

## Phase 4: User Story 2 - Cola Operativa de Verificación de Disponibilidad (Priority: P1)

**Goal**: El operador/admin trabaja la cola de verificación: inicia gestión, contacta al proveedor con los enlaces del dispositivo y registra el resultado (disponible / no disponible / alternativa sugerida, con retención).

**Independent Test**: Escenario 2 de quickstart.md; `availability_verification_test.sql` en verde.

### Tests for User Story 2

- [x] T026 [P] [US2] Crear `supabase/tests/availability_verification_test.sql`: `assign_pre_reservation_operator` a operator/admin activo (audita `pre_reservation_assigned {from, to}`), a NULL, a agente → `ASSIGNEE_NOT_OPERATOR`, sobre cancelada → `PRE_RESERVATION_CLOSED`; `start_item_verification` idempotente (segunda llamada no cambia `verification_started_at` ni agrega evento), autoasigna al operador si la pre-reserva no tenía, como agente → `INSUFFICIENT_PERMISSIONS`, sobre línea retirada → `ITEM_WITHDRAWN`; `record_item_verification`: los tres estados válidos, `pending` → `VALIDATION_ERROR`, sin `contact_person` → `CONTACT_PERSON_REQUIRED`, `hold_expires_at` pasada → `HOLD_EXPIRY_IN_PAST`, retención con `unavailable` → `VALIDATION_ERROR`, `alternative_suggested` sin texto → `ALTERNATIVE_SUGGESTION_REQUIRED`; re-verificación sobre una línea `available` (nuevo evento, limpia retención si el nuevo estado no es `available`); autoasignación en el primer resultado; cada resultado escribe `outcome_recorded` y la auditoría `availability_recorded {item_id, from, to, has_hold}` sin notas; el estado global se recalcula (pendiente → parcial → verificada; no disponible → requiere ajuste); `expire_due_pre_reservations` con retención vencida marca `expired` y devuelve el conteo; `anon` sin `EXECUTE` en las tres RPC

### Implementation for User Story 2

- [x] T027 [US2] Crear `supabase/migrations/039_us2_availability_verification.sql` con `public.assign_pre_reservation_operator`, `public.start_item_verification` y `public.record_item_verification` según data-model §US2 y contracts §3 (con `require_availability_verifier()` las dos últimas; `SELECT … FOR UPDATE` de la pre-reserva y luego de la línea; llamada final a `refresh_pre_reservation_status`; `GRANT EXECUTE … TO authenticated`)
- [x] T028 [P] [US2] Crear `src/app/core/pre-reservations/services/availability-verification.service.ts`: `queuePage({ q, status, providerId, assignee, group, page })` (vista `availability_verification_queue` con los filtros y órdenes exactos de contracts §5, `count: 'exact'`, 20/página; llama antes a `PreReservationService.sweepExpired()`), `listProviders()` (activos `id, name`), `start(itemId)` (RPC `start_item_verification`), `record(itemId, payload): Promise<RecordOutcomeResult>` (RPC `record_item_verification`); errores con `toAppError`
- [x] T029 [P] [US2] Crear `src/app/features/sales/verification/verification-outcome-form/verification-outcome-form.component.ts` (`app-verification-outcome-form`, inputs `item: VerificationQueueRow`, outputs `saved`, `cancelled`): Signal Form con los campos de contracts §6.4 (radio resultado, persona de contacto*, medio*, «Retención hasta» `datetime-local` solo visible con Disponible, «Alternativa sugerida»* solo con Alternativa sugerida, notas; validaciones de affordance); al guardar llama `AvailabilityVerificationService.record` y emite `saved` con el resultado; errores con `toAppError`
- [x] T030 [US2] Crear `src/app/features/sales/verification/verification-queue/verification-queue.component.ts`: `app-data-table` título «Verificación de disponibilidad» con los filtros, columnas y estados de contracts §6.4 («Estado» default «Requieren acción», «Proveedor» con Todos/Sin proveedor/activos, «Operador» Todos/Mías/Sin asignar/lista, «Buscar», casilla «Agrupar por proveedor» que activa `group=provider` e inserta filas de encabezado por proveedor); acciones por fila «Iniciar gestión» (`AvailabilityVerificationService.start`, deshabilitada si ya inició) y «Registrar resultado» que despliega `app-verification-outcome-form` bajo la fila; `emptyMessage` «No hay servicios pendientes de verificación.»
- [x] T031 [US2] Agregar en `src/app/app.routes.ts` dentro de `sales.children`: `{ path: 'verification', canActivate: [roleGuard('operator')], loadComponent: VerificationQueueComponent }`; agregar `{ id: 'sales-verification', label: 'Verificación', path: '/sales/verification', minRole: 'operator', hideForAgent: true }` como tercer hijo de `sales` en `src/app/shared/layout/nav-items.ts` y actualizar `src/app/shared/layout/nav-items.spec.ts` (agente no lo ve; operador y admin sí; `activeNavItemId(items, '/sales/verification') === 'sales-verification'`)

**Checkpoint**: US1 + US2 forman el MVP operativo — la cola muestra líneas, el operador registra resultados y el estado global se consolida

---

## Phase 5: User Story 3 - Consolidación del Estado de la Pre-Reserva (Priority: P2)

**Goal**: Ajustes de líneas (agregar/retirar/promover), expiración visible, excepción de admin para cotizar, elegibilidad en el detalle y aviso global al agente cuando la pre-reserva queda totalmente verificada.

**Independent Test**: Escenarios 3, 4 y 5 de quickstart.md; `pre_reservation_consolidation_test.sql` en verde.

### Tests for User Story 3

- [x] T032 [P] [US3] Crear `supabase/tests/pre_reservation_consolidation_test.sql`: `add_pre_reservation_item` principal y alternativa (limpia la excepción si es principal y audita `pre_reservation_items_changed {action:'added', override_cleared}`), sobre cancelada → `PRE_RESERVATION_CLOSED`; `withdraw_pre_reservation_item` retira la principal con sus alternativas vigentes (un evento `item_withdrawn` por línea), dejar cero principales → `PRE_RESERVATION_REQUIRES_ITEMS`, sin motivo → `VALIDATION_ERROR`, línea ya retirada → `ITEM_WITHDRAWN`; `promote_alternative_item` retira la principal original con motivo «Reemplazada por alternativa», recoloca las alternativas hermanas, escribe `alternative_promoted` con `metadata.replaced_item_id`, limpia la excepción; `authorize_quotation_override` como admin (audita `quotation_override_authorized {status}` sin motivo, evento `quote_override_authorized` con el motivo en `notes`), sin motivo → `OVERRIDE_REASON_REQUIRED`, sobre `verified` → `OVERRIDE_NOT_REQUIRED`, como operador → `INSUFFICIENT_PERMISSIONS`; `assert_pre_reservation_quotable`: `verified` → `{eligible, basis:'verified'}`, excepción vigente → `basis:'override'` (incluso `expired`), `cancelled` → `PRE_RESERVATION_CLOSED`, `expired` sin excepción → `PRE_RESERVATION_EXPIRED`, otro → `PRE_RESERVATION_NOT_VERIFIED`, y es inaccesible para `anon` y `authenticated`; la vista `pre_reservation_list.quote_eligible` coincide con la regla en cada caso

### Implementation for User Story 3

- [x] T033 [US3] Crear `supabase/migrations/040_us3_pre_reservation_consolidation.sql` con `public.add_pre_reservation_item`, `public.withdraw_pre_reservation_item`, `public.promote_alternative_item`, `public.expire_due_pre_reservations` (barrido idempotente del tenant del llamador, research R-004), `public.authorize_quotation_override` (`require_tenant_admin()`) y `public.assert_pre_reservation_quotable` (interna, `REVOKE ALL … FROM PUBLIC, anon, authenticated`) según data-model §US3 y contracts §4 (`GRANT EXECUTE … TO authenticated` salvo la interna)
- [x] T034 [P] [US3] Extender `src/app/core/pre-reservations/services/pre-reservation.service.ts` con `addItem(id, item)`, `withdrawItem(itemId, reason)`, `promoteItem(itemId)`, `assignOperator(id, operatorId | null)`, `authorizeOverride(id, reason)` (contracts §6.5), errores con `toAppError`
- [x] T035 [US3] Extender `src/app/features/sales/pre-reservations/pre-reservation-detail/pre-reservation-detail.component.ts` con: acciones por fila de la tabla «Servicios» («Iniciar gestión» y «Registrar resultado» solo si `hasRoleAtLeast(auth.role(), 'operator')` reutilizando `app-verification-outcome-form`, «Promover a principal» en alternativas vigentes, «Retirar» con campo de motivo obligatorio); sección «Agregar servicio» con el mismo formulario de línea de US1 (llama `addItem` con `buildCreatePayload` de una sola fila, incluida `alternative_of_item_id`); sección «Resumen» con selector «Operador asignado» (`assignOperator`, más botón «Asignarme» si operator/admin); sección «Cotización» con `quoteEligibilityReason`: «Lista para cotizar.» o «No elegible para cotizar: <motivo>», siempre con «La cotización se genera desde el módulo de cotizaciones.»; para admin y estados no `verified`/`cancelled`, «Autorizar excepción» con motivo obligatorio y confirmación «La excepción quedará registrada en la auditoría.»; con excepción vigente, «Excepción autorizada por <nombre> el <fecha>.»; sección «Cancelar pre-reserva» con motivo obligatorio y confirmación; recargar el detalle tras cada acción
- [x] T036 [P] [US3] Crear `src/app/core/pre-reservations/services/pre-reservation-realtime.service.ts`: `watchVerified(organizationId, userId, onVerified): () => void` abre `supabase.client.channel('pre-reservations:' + organizationId)` con `postgres_changes` `UPDATE` filtrado por `organization_id=eq.<org>`; avisa solo si `new.status === 'verified'` y `new.responsible_agent_id === userId`, una vez por id; si el estado de suscripción es `CHANNEL_ERROR` o `TIMED_OUT`, consulta cada 30 s `pre_reservations` propias `status = 'verified'` con `verified_at >` última consulta; la función devuelta desuscribe y limpia el intervalo
- [x] T037 [US3] Crear `src/app/shared/layout/verified-notice/verified-notice.component.ts` (`app-verified-notice`) e integrarlo en `src/app/shared/layout/admin-shell/admin-shell.component.ts`: al montar el shell, `PreReservationRealtimeService.watchVerified(auth.organizationId(), auth.user().id, …)` muestra `app-alert kind="success"` «La pre-reserva PRE-##### quedó totalmente verificada.» con enlace «Ver pre-reserva» al detalle y botón cerrar; desuscribir en `DestroyRef.onDestroy`

**Checkpoint**: US1–US3 operativas: ajuste de líneas, elegibilidad con excepción auditada y aviso al agente en tiempo real

---

## Phase 6: User Story 4 - Trazabilidad y Tiempos de Verificación (Priority: P3)

**Goal**: El detalle muestra el historial inalterable por línea y los tiempos de verificación por pre-reserva.

**Independent Test**: Escenarios 6 y 7 de quickstart.md; `verification_traceability_test.sql` en verde.

### Tests for User Story 4

- [x] T038 [P] [US4] Crear `supabase/tests/verification_traceability_test.sql`: la vista `availability_verification_history` muestra los eventos con nombre del actor y etiqueta de la línea, ordenados, solo del tenant; `pre_reservation_verification_times` calcula `first_started_at`, `hours_to_first_start`, `hours_to_verified` e `item_count`/`verifier_count` correctos para una pre-reserva con dos verificadores; ambas vistas sin privilegios para `anon`; la secuencia completa crear → iniciar → resultados → retirar → promover deja un evento por acción con `from_status`/`to_status` coherentes (cadena verificada con `count(*)` y orden por `created_at, id`)

### Implementation for User Story 4

- [x] T039 [US4] Crear `supabase/migrations/041_us4_verification_traceability.sql` con las vistas `public.availability_verification_history` y `public.pre_reservation_verification_times` (data-model §Views, `security_invoker`, `REVOKE ALL … FROM anon`, `GRANT SELECT … TO authenticated`)
- [x] T040 [P] [US4] Extender `src/app/core/pre-reservations/services/pre-reservation.service.ts` con `listHistory(id): Promise<VerificationEvent[]>` (vista `availability_verification_history`, orden `created_at desc`) y `getTimes(id): Promise<VerificationTimes | null>` (vista `pre_reservation_verification_times`)
- [x] T041 [US4] Agregar a `src/app/features/sales/pre-reservations/pre-reservation-detail/pre-reservation-detail.component.ts` las secciones «Historial» (eventos con fecha, actor, acción vía `AVAILABILITY_EVENT_KIND_LABELS`, estado anterior → nuevo vía `AVAILABILITY_STATUS_LABELS`, contacto del proveedor y notas; vacío: «Todavía no hay eventos.») y «Tiempos» («Tiempo hasta verificación total: X h» con `hours_to_verified`, o «Aún no se verifica totalmente.», más «Primera gestión: X h desde la creación»)

**Checkpoint**: US1–US4 completas y verificadas

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T042 [P] Crear `docs/modules/pre-reservations.md` con la estructura de `docs/modules/customer-requests.md`: propósito; spec/plan; tabla "What lives where" (migraciones `035`–`041`, suites SQL, `src/app/core/pre-reservations/`, `src/app/features/sales/pre-reservations/` y `verification/`); entidades y máquina de estados con la precedencia; RPCs con quién puede llamarlas; regla de elegibilidad y contrato `assert_pre_reservation_quotable` para 005; expiración por barrido; RBAC; invariantes de seguridad (no regresar); tabla de rutas `/sales/*` nuevas; mapeo quickstart → evidencia automatizada
- [x] T043 [P] Enlazar el módulo en `AGENTS.md` agregando, antes de `<!-- SPECKIT START -->`, el párrafo "Pre-Reservations & Availability (pre-reservations, human availability verification queue, quote eligibility): see `docs/modules/pre-reservations.md`." con el mismo formato de los párrafos existentes
- [x] T044 [P] Actualizar la navegación documentada por 010: en `docs/modules/identity-access.md` (sección "Admin layout (010)") agregar filas `/sales/pre-reservations`, `/sales/pre-reservations/new`, `/sales/pre-reservations/:id` («any collaborator») y `/sales/verification` («operator and above»), y en `specs/010-admin-layout-navigation/contracts/ui-contracts.md` agregar al "Route map" esas rutas y al "Navigation tree contract" las filas «Comercial / Pre-reservas» (✓ los tres roles) y «Comercial / Verificación» (solo operator/admin)
- [x] T045 [P] Actualizar el comentario de cabecera de `supabase/tests/run-sql-tests.sh` listando las suites de 004 (`pre_reservation_core_test.sql`, `pre_reservation_rls_test.sql`, `availability_verification_test.sql`, `pre_reservation_consolidation_test.sql`, `verification_traceability_test.sql`); no cambiar la lógica del script
- [x] T046 Revisión de seguridad con evidencia en la descripción del PR: `rg -n "service_role|SERVICE_ROLE" src/` sin resultados; todas las funciones de `035`–`041` tienen `SET search_path = ''` y `REVOKE ALL … FROM PUBLIC`; ninguna llamada a `audit.log_event` pasa notas, motivos, nombres, teléfonos ni correos en `metadata`; las vistas no exponen `email` ni `phone_e164` del viajero
- [x] T047 Ejecutar `./supabase/tests/run-sql-tests.sh` (todas las suites, incluidas las de 001/002/003/009), `npm test`, `npm run lint`, `npm run format:check` y `npm run build`; corregir cualquier fallo
- [ ] T048 Ejecutar manualmente los escenarios 1–7 de `specs/004-prereservation-availability/quickstart.md` con `supabase start` y `npm start`, y anotar en `docs/modules/pre-reservations.md` (sección "Quickstart mapping") cuáles quedaron verificados en navegador y cuáles solo por SQL

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias.
- **Foundational (Phase 2)**: depende de Setup. Bloquea todas las historias. Orden interno obligatorio de migraciones: T002 → T003 → T004 → T005. T006/T007 tras T005. T008 tras T005. T009–T015 en paralelo en cualquier momento. T016 tras T015.
- **US1 (Phase 3)**: depende de Foundational.
- **US2 (Phase 4)**: depende de Foundational y de T015 (servicio compartido de barrido). Independiente de US1 salvo que la cola se alimenta de pre-reservas creadas por US1/seed.
- **US3 (Phase 5)**: depende de Foundational, de T018 (cancelación vive en el detalle), T022 (detalle base) y T029 (formulario de resultado reutilizado).
- **US4 (Phase 6)**: depende de Foundational y de T022.
- **Polish (Phase 7)**: tras las historias que se entreguen.

### User Story Dependencies

- **US1 (P1)**: solo Foundational. MVP mínimo: conversión y consulta.
- **US2 (P1)**: Foundational + servicio base. Cola y resultados.
- **US3 (P2)**: US1 (detalle) + US2 (formulario de resultado). Ajustes, excepción y aviso.
- **US4 (P3)**: Foundational + detalle de US1.

### Within Each User Story

- La suite SQL de la historia se escribe primero y debe fallar antes de crear la migración de la historia.
- Migración → servicio TS → componentes → rutas/menú.
- Las tareas sobre el mismo archivo (`pre-reservation-detail.component.ts`, `pre-reservation.service.ts`, `app.routes.ts`, `nav-items.ts`, migraciones partidas en dos tareas) son secuenciales.

### Parallel Opportunities

- Foundational: T006, T007 (tras T005); T009–T015 en paralelo entre sí y con las migraciones.
- US1: T017 primero; T019 y T022/T023 en paralelo tras T018/T020.
- US2: T026, T028, T029 en paralelo tras T027.
- US3: T032 primero; T034 y T036 en paralelo tras T033.
- US4: T038 y T040 en paralelo tras T039.
- Polish: T042–T045 en paralelo.

---

## Parallel Example: User Story 1

```bash
# Tras T018 (migración 038) y T020 (servicio):
Task: "T021 [US1] PreReservationCreateComponent en src/app/features/sales/pre-reservations/pre-reservation-create/"
Task: "T022 [US1] PreReservationDetailComponent base en src/app/features/sales/pre-reservations/pre-reservation-detail/"
Task: "T023 [US1] PreReservationListComponent en src/app/features/sales/pre-reservations/pre-reservation-list/"
```

## Parallel Example: User Story 2

```bash
# Tras T027 (migración 039):
Task: "T028 [US2] AvailabilityVerificationService en src/app/core/pre-reservations/services/availability-verification.service.ts"
Task: "T029 [US2] VerificationOutcomeFormComponent en src/app/features/sales/verification/verification-outcome-form/"
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Phase 1 + Phase 2 (checkpoint: suites de núcleo y RLS en verde).
2. US1 → validar escenario 1 de quickstart. **Punto de demo**: conversión solicitud → pre-reserva.
3. US2 → validar escenario 2 (cola y resultados con roles).
4. **STOP y VALIDAR**: verificación humana de disponibilidad operativa.

### Incremental Delivery

1. Foundational.
2. US1 → demo (conversión).
3. US2 → demo (cola y resultados).
4. US3 → demo (ajustes, excepción, aviso Realtime).
5. US4 → demo (historial y tiempos).
6. Polish → documentación y verificación completa.

### Parallel Team Strategy

Tras Foundational: dev A en US1 (pantallas de pre-reservas); dev B en US2 (cola); dev C en las suites SQL de US3/US4. La UI de US3 espera a que US1 y US2 cierren sus archivos.

---

## Notes

- Una pre-reserva nunca bloquea inventario, calcula precios ni se convierte en reserva; la cotización la genera 005 consultando `assert_pre_reservation_quotable` (contracts §4.1).
- Toda escritura pasa por RPC; las tablas son SELECT-only para `authenticated` y opacas para `anon`.
- Una sola autoridad para el estado global (`refresh_pre_reservation_status`, migración `037`): no recalcular estados en TypeScript; la UI solo lee `status` y `quote_eligible`.
- Las líneas son inmutables en fechas/producto/pasajeros: se retiran y se agregan (preserva el historial de verificación).
