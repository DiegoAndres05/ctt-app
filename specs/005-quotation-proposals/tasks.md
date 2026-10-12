---
description: "Task list for 005-quotation-proposals implementation"
---

# Tasks: 005-quotation-proposals (Comercial — Cotizaciones)

**Input**: Design documents from `/specs/005-quotation-proposals/`

**Prerequisites**: plan.md, spec.md (clarificado 2026-10-04), research.md, data-model.md, contracts/api-contracts.md, quickstart.md. Features 001, 002, 003 y 009 implementadas. Feature 004 reserva migraciones `035`–`041` y `assert_pre_reservation_quotable`. Esta feature empieza en `042`. No renumerar 004. No editar `supabase/migrations/035_pre_reservation_enums.sql` ni las carpetas vacías de pre-reservas. No crear reservas, pagos ni factura. No revertir `supabase/config.toml` ni `src/environments/environment.development.ts`.

**Tests**: Suites SQL y Vitest, pedidas por el spec y por la convención del repo. Quedan sin marcar: las ejecuta quien implemente.

**Organization**: Tareas por historia (US1–US4 de spec.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede ejecutarse en paralelo (archivo distinto, sin dependencias pendientes)
- **[Story]**: US1–US4 según spec.md
- Rutas exactas de archivo en cada tarea

## Path Conventions

- **Backend**: `supabase/migrations/` desde `042_`, `supabase/tests/`, `supabase/seed.sql`
- **Frontend**: `src/app/core/quotations/`, `src/app/features/sales/quotations/`, `src/app/features/public-quotation/`, `src/app/app.routes.ts`
- **Docs**: `docs/modules/quotations.md`

## Conventions every task must follow

- **SQL**: estilo de `supabase/migrations/030_customer_intake_core.sql`: cabecera, `SECURITY DEFINER`, `SET search_path = ''`, nombres calificados, `RAISE EXCEPTION '<CODE>' USING ERRCODE = 'raise_exception'`, `REVOKE ALL` a `PUBLIC` y `GRANT EXECUTE` explícito. Auditoría solo con `audit.log_event` y sin PII, etiquetas, términos, motivos ni token en `metadata` (contracts §8). Fechas de calendario en `America/Bogota`.
- **Suites SQL**: estructura de `supabase/tests/request_workflow_test.sql` (`BEGIN`/`ROLLBACK`, `pg_temp.act_as`, `tests.assert_*`, `SET LOCAL ROLE`).
- **Angular**: standalone, `ChangeDetectionStrategy.OnPush`, signals, `form()` de `@angular/forms/signals`, listados con `app-data-table` y paginación `range` + `count: 'exact'`, `toAppError`, textos en español de contracts §7. La UI no multiplica ni suma importes: pinta los campos del RPC.
- **No** referenciar la service role key desde `src/`. **No** llamar a la API de WhatsApp. **No** insertar en tablas de reserva.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Carpetas de la capacidad nueva

- [x] T001 Crear carpetas con `.gitkeep`: `src/app/core/quotations/models/`, `src/app/core/quotations/services/`, `src/app/features/sales/quotations/quotation-list/`, `src/app/features/sales/quotations/quotation-editor/`, `src/app/features/public-quotation/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Enums, tablas, RLS, motor de precio y modelos compartidos. Ninguna historia empieza antes.

- [ ] T002 `supabase/migrations/042_quotation_enums.sql` creado según data-model §Enums: tipos quotation_status (draft/issued/accepted/rejected/expired/superseded), quotation_adjustment_direction (increase/decrease), quotation_adjustment_kind (percentage/fixed), quotation_response_kind (accept/reject/modifications), quotation_response_origin (client/agent) con `COMMENT ON TYPE` y `ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS` por cada valor: quotation_created, quotation_issued, quotation_adjustment_applied, quotation_response_recorded, quotation_superseded, quotation_voided, quotation_expired.
- [ ] T003 `supabase/migrations/043_quotations.sql` creado según data-model §1–§6 y §RLS y §View: tablas quotation_families, quotation_versions, quotation_lines, quotation_adjustments, quotation_responses (append-only con reject_request_note_mutation), quotation_defaults; FKs compuestas; índices únicos parciales de referencia, token, una versión abierta y una aceptada por familia; triggers de identidad y QUOTATION_FROZEN; RLS SELECT por organization_id; REVOKE ALL a anon; vista quotation_list security_invoker con columnas data-model sin correo/telefono/token.
- [ ] T004 `supabase/migrations/044_quotation_pricing.sql` creado según data-model §Núcleo y research R-001–R-005: funciones internas resolve_quotation_tariff, recalculate_quotation_core, quotation_adjustment_impact, capture_pre_reservation_fingerprint (REVOKE ALL a PUBLIC, anon, authenticated). Tipo preferido experiencia per_person, alojamiento per_night, paquete per_group sin sumar componentes, complemento según add_ons.unit. Redondeo numeric(14,2) por línea antes de sumar. Tope agente round(sum(line_base) * 0.15, 2).
- [ ] T005 [P] `supabase/tests/quotation_rls_test.sql` creado: anon no puede SELECT las seis tablas ni la vista; authenticated de otra organización no ve filas; get_public_quotation aún no existe en esta fase; las funciones de 044 no tienen EXECUTE para anon ni authenticated.
- [ ] T006 [P] `src/app/core/quotations/models/quotation.model.ts` creado con tipos QuotationStatus, QuotationAdjustmentDirection, QuotationAdjustmentKind, QuotationResponseKind, QuotationResponseOrigin alineados a data-model §Enums y contracts §2; QUOTATION_STATUS_LABELS; isQuotationTerminal (accepted/voided); canClientComputeTotals = false. Source: spec.md + data-model.md.
- [ ] T007 [P] `src/app/core/error/error-handler.ts` actualizado con 31 códigos de error quotation (TARIFF_NOT_FOUND, ADJUSTMENT_REQUIRES_ADMIN, QUOTATION_FROZEN, etc.) y `src/app/core/error/error-handler.spec.ts` cubierto con casos de cada mensaje. Source: spec.md §Requirements + contracts §8.
- [ ] T008 [P] [US1] `supabase/tests/quotation_pricing_test.sql` creado: perí_person usa adults+children; per_night usa noches por quantity; paquete no suma componentes; complemento per_service usa base 1; impuesto 19% redondeado por línea; descuento agente al 10% pasa y al 16% levanta ADJUSTMENT_REQUIRES_ADMIN; mismo 16% pasa con admin; moneda distinta sin tasa deja pending_currencies y no inventa total convertido; anon no ejecuta create_quotation_draft. Source: quickstart.md esc. 1 + spec.md FR-002/FR-009.
- [ ] T009 [US1] `supabase/migrations/045_us1_quotation_draft.sql` creado con create_quotation_draft, recalculate_quotation, set_quotation_line_tax, set_quotation_exchange_rate, set_quotation_texts, upsert_quotation_adjustment y delete_quotation_adjustment según contracts §2 y data-model §US1 (require_tenant_member, GRANT EXECUTE a authenticated, llamada a assert_pre_reservation_quotable, auditoría quotation_created y quotation_adjustment_applied sin etiqueta). Inclusiones en español de ficha pública publicada si existe; texto de condiciones por defecto research R-009 si no hay quotation_defaults.
- [ ] T006 [P] Crear `src/app/core/quotations/models/quotation.model.ts` y `quotation.model.spec.ts`: tipos de estado y de desglose alineados a `quotation_list` y al JSON de contracts §2; `QUOTATION_STATUS_LABELS` (data-model §Enums); `isQuotationTerminal` (`accepted` y `voided`); `canClientComputeTotals` exportada como constante `false`. El spec afirma las etiquetas «Borrador», «Emitida», «Aceptada», «Rechazada», «Expirada», «Anulada», «Superada por nueva versión» y que no existe una función de suma
- [ ] T007 [P] Registrar en `src/app/core/error/error-handler.ts` y cubrir en `src/app/core/error/error-handler.spec.ts` los mensajes: `TARIFF_NOT_FOUND` «No hay tarifa vigente para este servicio.», `AMBIGUOUS_TARIFF` «Hay más de una tarifa vigente y ninguna coincide con el tipo de cobro.», `EXCHANGE_RATE_REQUIRED` «Falta la tasa de cambio para emitir.», `EXCHANGE_RATE_INVALID` «La tasa de cambio debe ser mayor que cero.», `TAX_RATE_OUT_OF_RANGE` «El impuesto debe estar entre 0 % y 100 %.», `ADJUSTMENT_REQUIRES_ADMIN` «Este ajuste supera el 15 % y requiere un administrador.», `ADJUSTMENT_LABEL_REQUIRED` «El ajuste necesita una etiqueta.», `QUOTATION_FROZEN` «La cotización emitida no se edita. Cree una versión nueva.», `QUOTATION_ALREADY_OPEN` «Ya hay una cotización abierta para esta pre-reserva.», `QUOTATION_ALREADY_ACCEPTED` «Esta pre-reserva ya tiene una cotización aceptada.», `VALIDITY_EXCEEDS_HOLD` «La vigencia no puede pasar de la retención de la pre-reserva.», `VALIDITY_EXCEEDS_30_DAYS` «La vigencia no puede pasar de 30 días.», `TERMS_REQUIRED` «Faltan las condiciones de la propuesta.», `QUOTATION_STALE` «La pre-reserva cambió después de emitir. Hay que crear una versión nueva.», `QUOTATION_NOT_OPEN` «Esta propuesta ya no admite esa respuesta.», `QUOTATION_TERMINAL` «Esta cotización está cerrada.», `QUOTATION_NOT_ACCEPTED` «Solo una cotización aceptada puede confirmarse como reserva.», `QUOTATION_ACCEPTED` «Una cotización aceptada no se anula.», `VOID_REASON_REQUIRED` «Indique el motivo de la anulación.», `CONFIRMATION_REQUIRED` «Confirme la aceptación para continuar.», `PRE_RESERVATION_NOT_VERIFIED` reutilizar el mensaje ya existente si está; si no, «La pre-reserva todavía no se puede cotizar.»

**Checkpoint**: Tablas, precio interno y etiquetas listos. Las RPC de historias todavía no existen.

---

## Phase 3: User Story 1 - Generación y cálculo (Priority: P1) 🎯 MVP

**Goal**: El agente crea un borrador desde una pre-reserva elegible y ve el desglose del servidor, con tope de ajuste del 15 %.

**Independent Test**: Escenario 1 de quickstart.md y `quotation_pricing_test.sql` en verde.

### Tests for User Story 1

- [ ] T008 [P] [US1] Crear `supabase/tests/quotation_pricing_test.sql`: `per_person` usa `adults + children`; `per_night` usa noches por `quantity`; paquete no suma componentes; complemento `per_service` usa base 1; impuesto 19 % redondeado por línea; descuento de agente al 10 % pasa y al 16 % levanta `ADJUSTMENT_REQUIRES_ADMIN`; el mismo 16 % pasa con admin; moneda distinta sin tasa deja `pending_currencies` y no inventa un total convertido; `anon` no ejecuta `create_quotation_draft`

### Implementation for User Story 1

- [ ] T009 [US1] Crear `supabase/migrations/045_us1_quotation_draft.sql` con `create_quotation_draft`, `recalculate_quotation`, `set_quotation_line_tax`, `set_quotation_exchange_rate`, `set_quotation_texts`, `upsert_quotation_adjustment` y `delete_quotation_adjustment` según contracts §2 y data-model §US1 (`require_tenant_member`, `GRANT EXECUTE` a `authenticated`, llamada a `assert_pre_reservation_quotable`, auditoría `quotation_created` y `quotation_adjustment_applied` sin etiqueta). Copiar inclusiones en español de la ficha pública publicada si existe. Texto de condiciones por defecto el de research R-009 si no hay `quotation_defaults`
- [ ] T010 [US1] Crear `src/app/core/quotations/services/quotation.service.ts`: `listPage` sobre `quotation_list` (primero `expire_due_quotations` cuando exista; hasta US2, listar sin barrido), `createDraft(preReservationId)`, `recalculate`, `setTax`, `setExchangeRate`, `setTexts`, `saveAdjustment`, `deleteAdjustment`. Devolver el JSON del RPC sin recomputar
- [ ] T011 [P] [US1] Crear `src/app/features/sales/quotations/quotation-list/quotation-list.component.ts`: `app-data-table` título «Cotizaciones», vacío «Todavía no hay cotizaciones.», columnas Referencia, Cliente, Estado (`QUOTATION_STATUS_LABELS`), Vigencia, Total y moneda, Versión; botón «Nueva cotización»
- [ ] T012 [US1] Crear `src/app/features/sales/quotations/quotation-editor/quotation-editor.component.ts` (OnPush, signals, `unsavedChangesGuard` solo en `draft`): selector de pre-reserva cotizable, desglose de líneas (tipo de cobro, base, precio unitario, «Impuesto (%)», ajustes, total de línea), formulario de ajuste con etiqueta, dirección Descuento/Suplemento, tipo Porcentaje/Monto, textos Inclusiones, Exclusiones y notas internas, botón «Recalcular». Mostrar «Este ajuste supera el 15 % y requiere un administrador.» ante `ADJUSTMENT_REQUIRES_ADMIN`. No calcular totales en el componente
- [ ] T013 [US1] Registrar en `src/app/app.routes.ts` bajo `sales` las rutas `quotations` (listado), `quotations/new` (editor, `canDeactivate: [unsavedChangesGuard]`, declarada antes de `:versionId`) y `quotations/:versionId` (editor, `canDeactivate: [unsavedChangesGuard]`), todas con `roleGuard('agent')`. En `src/app/shared/layout/nav-items.ts` agregar el hijo `{ id: 'sales-quotations', label: 'Cotizaciones', path: '/sales/quotations', minRole: 'agent' }` dentro de Comercial sin quitar ítems existentes. Actualizar `src/app/shared/layout/nav-items.spec.ts` para esperar «Cotizaciones»
- [ ] T014 [US1] En `src/app/features/sales/pre-reservations/pre-reservation-detail/pre-reservation-detail.component.ts` (lo crea 004; no reescribir el resto de la pantalla) agregar, cuando `quote_eligible` sea true, el enlace «Crear cotización» hacia `/sales/quotations/new?preReservationId=<id>`. Registrar esa ruta `quotations/new` en `src/app/app.routes.ts` (`roleGuard('agent')`, `unsavedChangesGuard`) cargando el mismo `quotation-editor`. Al iniciar con `preReservationId`, el editor llama `createDraft` y reemplaza la URL por `/sales/quotations/<versionId>`. No crear el módulo de pre-reservas en esta feature: si el archivo de 004 todavía no existe, implementar el enlace cuando ese archivo ya esté, sin tocar `035_pre_reservation_enums.sql`

**Checkpoint**: Un agente obtiene un borrador con desglose de servidor. Aún no se emite.

---

## Phase 4: User Story 2 - Vigencia y emisión (Priority: P1)

**Goal**: Emitir congela importes, asigna `COT-#####` y fija la vigencia dentro de los topes.

**Independent Test**: Escenario 2 de quickstart.md y `quotation_issue_test.sql`.

### Tests for User Story 2

- [ ] T015 [P] [US2] Crear `supabase/tests/quotation_issue_test.sql`: default `valid_until` a 48 horas; rechazo si pasa de `expires_at` (`VALIDITY_EXCEEDS_HOLD`) o de 30 días; emisión asigna `COT-00001` y llena `pre_reservation_fingerprint`; un `UPDATE` de `unit_price` con la versión `issued` falla por el trigger `QUOTATION_FROZEN`; cambiar la tarifa del catálogo no altera `total`; `expire_due_quotations` pasa a `expired` una emitida vencida y audita `quotation_expired` sin notas; términos vacíos → `TERMS_REQUIRED`

### Implementation for User Story 2

- [ ] T016 [US2] Crear `supabase/migrations/046_us2_quotation_issue.sql` con `set_quotation_terms`, `issue_quotation`, `expire_due_quotations` y `upsert_quotation_defaults` según contracts §3. `issue_quotation` asigna la referencia con `next_organization_sequence(org, 'quotation')` y `lpad` a 5, genera 32 bytes con `extensions.gen_random_bytes`, guarda solo el SHA-256 en `public_token_hash` y devuelve `public_token` una vez. Auditar `quotation_issued` con `{ version_number, currency }` sin token
- [ ] T017 [US2] Extender `src/app/core/quotations/services/quotation.service.ts` con `setTerms`, `issue`, `expireDue` y `saveDefaults`. Tras `issue`, guardar el token en `sessionStorage` con clave `quotation-token:<versionId>`
- [ ] T018 [US2] En `src/app/features/sales/quotations/quotation-editor/quotation-editor.component.ts` agregar «Plantilla de condiciones» solo si el rol es admin (llama `upsert_quotation_defaults`), campos de condiciones y vigencia, botón «Emitir cotización», y el aviso «Cotización COT-00001 emitida. El enlace público se muestra una sola vez.» más el enlace `/q/<token>`. Si la vigencia es inválida, mostrar «La vigencia no puede pasar de la retención ni de 30 días.»
- [ ] T019 [US2] Hacer que `listPage` en `quotation.service.ts` llame a `expire_due_quotations` antes de leer `quotation_list`

**Checkpoint**: La cotización emitida queda congelada y numerada. La vista pública todavía no existe.

---

## Phase 5: User Story 3 - Entrega al cliente (Priority: P2)

**Goal**: Enlace público de solo lectura, texto para WhatsApp e impresión, sin envío saliente.

**Independent Test**: Escenario 3 de quickstart.md y `quotation_public_test.sql`.

### Tests for User Story 3

- [ ] T020 [P] [US3] Crear `supabase/tests/quotation_public_test.sql`: `get_public_quotation` con token válido devuelve desglose y `can_accept: true` sin claves `customer_id`, `email`, `phone` ni `commercial_notes`; token desconocido devuelve `{ available: false }` sin líneas; tras `void_quotation` (la RPC llega en US4: este test puede llamar el update de estado solo cuando `048` exista — escribir el caso de anulación en `quotation_version_test.sql` y aquí solo token inválido, emitida y campos prohibidos). `anon` puede ejecutar `get_public_quotation` y no puede `SELECT quotation_versions`. `quotation_whatsapp_text` incluye la referencia y el total y no incluye `https://` ni el token

### Implementation for User Story 3

- [ ] T021 [US3] Crear `supabase/migrations/047_us3_quotation_delivery.sql` con `get_public_quotation(p_token text)` (`GRANT` a `anon` y `authenticated`) y `quotation_whatsapp_text(p_version_id uuid)` (`GRANT` a `authenticated`) según contracts §4. Buscar por hash. No devolver datos si el token no existe
- [ ] T022 [P] [US3] Crear `src/app/features/public-quotation/public-quotation.component.ts`: página sin shell, título con la referencia, líneas, inclusiones, exclusiones, desglose, condiciones, vigencia. Textos de contracts §7. Si `available` es false: «Esta propuesta ya no está disponible.» Si `status` es `expired`: «Esta propuesta expiró. Hay que emitir una versión nueva.» Botón «Aceptar propuesta» visible solo si `can_accept` (la acción se conecta en US4). CSS legible a 360 px de ancho
- [ ] T023 [US3] En `quotation-editor.component.ts` agregar «Copiar para WhatsApp» (cuerpo del RPC más `Detalle: ${location.origin}/q/${token}` desde `sessionStorage`) y «Imprimir» (`window.print()`). Si no hay token: «El enlace se mostró al emitir. Si se perdió, anule y emita una versión nueva.»
- [ ] T024 [US3] En `src/app/app.routes.ts`, dentro de `publicRoutes` y fuera del shell, agregar `q/:token` cargando `PublicQuotationComponent` sin `authGuard`

**Checkpoint**: El cliente abre la propuesta sin sesión. Aún no puede aceptarla.

---

## Phase 6: User Story 4 - Respuesta y versionado (Priority: P3)

**Goal**: Aceptar con revalidación, versionar sin perder la anterior, anular el enlace. No crear reservas.

**Independent Test**: Escenario 4 de quickstart.md y `quotation_version_test.sql`.

### Tests for User Story 4

- [ ] T025 [P] [US4] Crear `supabase/tests/quotation_version_test.sql`: `accept_public_quotation` sin `p_confirmed` → `CONFIRMATION_REQUIRED` y el estado sigue `issued`; con `p_confirmed` pasa a `accepted`, origen `customer`, auditoría `quotation_response_recorded` con `{ response: 'accepted', origin: 'customer' }` y sin nombres; segunda aceptación → `QUOTATION_NOT_OPEN`; `changes_requested` deja `issued` y escribe `quotation_responses`; `create_quotation_version` marca la anterior `superseded`, abre `draft` con tarifas nuevas (no copia el total viejo si la tarifa cambió) y el token de la familia se conserva; aceptar tras cambiar una línea principal → estado `expired` y `QUOTATION_STALE`; versionar una `accepted` → `QUOTATION_TERMINAL`; `void_quotation` sin motivo → `VOID_REASON_REQUIRED`; sobre `accepted` → `QUOTATION_ACCEPTED`; como agente → `INSUFFICIENT_PERMISSIONS`; tras anular, `get_public_quotation` devuelve `{ available: false }` sin `lines`; `assert_quotation_confirmable` no es ejecutable por `authenticated` y, llamada como owner sobre una aceptada, devuelve `total` y `party_adults` sin correo

### Implementation for User Story 4

- [ ] T026 [US4] Crear `supabase/migrations/048_us4_quotation_responses.sql` con `record_quotation_response`, `accept_public_quotation`, `create_quotation_version`, `void_quotation` y `assert_quotation_confirmable` según contracts §5 y data-model §US4. `assert_quotation_confirmable` queda interna. Ninguna función inserta reservas ni pagos. `void_quotation` usa `require_tenant_admin` y guarda el motivo en `void_reason`, no en metadata
- [ ] T027 [US4] Extender `quotation.service.ts` con `recordResponse`, `acceptPublic`, `createVersion` y `voidQuotation`. En `public-quotation.component.ts` el botón «Aceptar propuesta» revela «Confirmar aceptación», que llama `accept_public_quotation` con `p_confirmed: true`. Tras el éxito mostrar «Propuesta aceptada. La reserva se confirma en el módulo de reservas.» y no navegar a ninguna ruta de reservas
- [ ] T028 [US4] En `quotation-editor.component.ts` agregar «Registrar respuesta» con opciones Aceptada, Rechazada y «Registrar “Requiere modificaciones”»; «Crear nueva versión» cuando el estado sea `issued`, `rejected` o `expired`; «Anular cotización» solo admin, con campo «Motivo de la anulación». En estado `superseded` mostrar «Superada por nueva versión» y deshabilitar edición y aceptación. No agregar botón de crear reserva

**Checkpoint**: US1–US4 cerradas. Aceptar no crea una reserva.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T029 [P] Crear `docs/modules/quotations.md` con el formato de `docs/modules/customer-requests.md`: propósito; spec/plan; tabla de ubicaciones (migraciones `042`–`048`, suites, `src/app/core/quotations/`, pantallas); estados; RPCs y quién las llama; regla de huella; token hasheado; frontera `assert_quotation_confirmable` para 006; qué no hace (reserva, pago, WhatsApp saliente, factura); rutas
- [ ] T030 [P] En `AGENTS.md`, antes de `<!-- SPECKIT START -->`, agregar el párrafo `Quotations (commercial proposals, server-side pricing, public token): see docs/modules/quotations.md.` sin borrar los párrafos de Identity, Catalog y Customers
- [ ] T031 [P] Documentar las rutas en `docs/modules/identity-access.md` (sección de layout 010) y en `specs/010-admin-layout-navigation/contracts/ui-contracts.md`: `/sales/quotations`, `/sales/quotations/:versionId` (agent y superiores) y `/q/:token` (pública, sin shell). En el árbol de navegación, «Comercial / Cotizaciones» visible para agent, operator y admin
- [ ] T032 [P] Actualizar el comentario de cabecera de `supabase/tests/run-sql-tests.sh` listando `quotation_pricing_test.sql`, `quotation_rls_test.sql`, `quotation_issue_test.sql`, `quotation_public_test.sql` y `quotation_version_test.sql`. No cambiar la lógica del script
- [ ] T033 Revisar que ninguna llamada a `audit.log_event` en `042`–`048` incluya etiqueta, términos, notas, motivo, token, nombre, correo o teléfono, y que `src/` no mencione `service_role`

---

## Phase 8: Verification

**Purpose**: Comandos que debe ejecutar quien implemente. No marcarlos hasta tener la salida.

- [ ] T034 Ejecutar `npm test -- --watch=false`
- [ ] T035 Ejecutar `npm run lint`
- [ ] T036 Ejecutar `npm run build`
- [ ] T037 Ejecutar `./supabase/tests/run-sql-tests.sh`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias.
- **Foundational (Phase 2)**: depende de Setup. Orden de migraciones: T002 → T003 → T004. T005 después de T004. T006 y T007 en paralelo con las migraciones.
- **US1 (Phase 3)**: depende de Foundational. T008 antes de T009. T011 en paralelo con T010 tras T009. T012 después de T010. T013 después de T011 y T012. T014 después de T013 y del detalle de 004.
- **US2 (Phase 4)**: depende de US1 (el editor existe). T015 antes de T016. T019 después de T016.
- **US3 (Phase 5)**: depende de US2 (hace falta una emitida y el token). T020 antes de T021. T022 y T023 en paralelo tras T021. T024 tras T022.
- **US4 (Phase 6)**: depende de US3 para el botón público. T025 antes de T026. T027 y T028 tras T026.
- **Polish (Phase 7)**: tras las historias que se entreguen.
- **Verification (Phase 8)**: al final, sin marcar las tareas como hechas en este documento.

### User Story Dependencies

- **US1 (P1)**: solo Foundational. MVP: borrador con precio de servidor.
- **US2 (P1)**: US1. Emisión y vigencia.
- **US3 (P2)**: US2. El enlace existe porque emitir devuelve el token.
- **US4 (P3)**: US2 para respuestas de agente; US3 para la aceptación pública.

### Parallel Opportunities

- Foundational: T006 y T007 mientras se escriben T002–T004.
- US1: T011 junto con T010 después de T009.
- US3: T022 y T023 después de T021.
- Polish: T029–T032 en paralelo.

---

## Parallel Example: User Story 1

```bash
# Tras T009 (migración 045) y T010 (servicio):
Task: "T011 [US1] QuotationListComponent en src/app/features/sales/quotations/quotation-list/"
Task: "T012 [US1] QuotationEditorComponent en src/app/features/sales/quotations/quotation-editor/"
```

## Parallel Example: User Story 3

```bash
# Tras T021 (migración 047):
Task: "T022 [US3] PublicQuotationComponent en src/app/features/public-quotation/"
Task: "T023 [US3] Copiar para WhatsApp e Imprimir en quotation-editor.component.ts"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 y Phase 2.
2. US1 hasta un borrador con desglose.
3. Parar y validar el escenario 1. Aún no hay enlace público ni reserva.

### Incremental Delivery

1. US1 → demo de cálculo.
2. US2 → demo de emisión y vigencia.
3. US3 → demo del enlace y del texto de WhatsApp.
4. US4 → demo de aceptación y versión, sin reserva.
5. Polish y Phase 8.

### Parallel Team Strategy

Tras Foundational: una persona en el editor (US1/US2) y otra en las suites SQL de US2–US4. La página pública espera el token de US2.

---

## Notes

- Última migración de esta feature: `048_us4_quotation_responses.sql`. La feature 006 empieza en `049`.
- `assert_pre_reservation_quotable` (004, migración `040`) es la elegibilidad. La huella congelada al emitir cubre el cambio de líneas.
- `assert_quotation_confirmable` no crea reservas. 006 la invocará.
- El token en claro vive en la respuesta de `issue_quotation` y en `sessionStorage`. La base guarda el hash.
- No marcar ninguna tarea como hecha en este archivo.
