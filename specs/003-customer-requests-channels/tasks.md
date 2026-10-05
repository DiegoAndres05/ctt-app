---
description: "Task list for 003-customer-requests-channels implementation"
---

# Tasks: 003-customer-requests-channels (Comercial — Clientes y Solicitudes)

**Input**: Design documents from `/specs/003-customer-requests-channels/`

**Prerequisites**: plan.md, spec.md (clarificado 2026-10-04), research.md, data-model.md, contracts/api-contracts.md, quickstart.md. Features 001, 002, 009 y 010 ya implementadas; última migración existente `027_public_catalog_seed.sql`.

**Tests**: Incluidos por convención del proyecto: suites SQL (`supabase/tests/*_test.sql`, harness Postgres 17 vía `./supabase/tests/run-sql-tests.sh`) para RLS y reglas de RPC, y Vitest (`npm test`) para lógica TypeScript pura.

**Organization**: Tareas agrupadas por historia de usuario (US1–US4 de spec.md) para implementar y probar cada una por separado.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede ejecutarse en paralelo (archivo distinto, sin dependencias pendientes)
- **[Story]**: US1–US4 según spec.md
- Rutas exactas de archivo en cada tarea

## Path Conventions

- **Backend**: `supabase/migrations/` (desde `028_`), `supabase/functions/`, `supabase/tests/`, `supabase/seed.sql`
- **Frontend**: `src/app/core/customers/`, `src/app/features/sales/`, `src/app/shared/`, `src/app/app.routes.ts`
- **Scripts/Docs**: `scripts/`, `docs/modules/`

## Conventions every task must follow

- **SQL**: copiar el estilo de `supabase/migrations/018_us1_product_rpcs.sql` y `024_public_listing_rpcs.sql`: cabecera con propósito y fuente de verdad, `SECURITY DEFINER`, `SET search_path = ''`, nombres totalmente calificados (`public.`, `audit.`), `RAISE EXCEPTION '<CODE>' USING ERRCODE = 'raise_exception'` (o `insufficient_privilege` en permisos), `REVOKE ALL ON FUNCTION … FROM PUBLIC` y luego `GRANT EXECUTE` explícito. Auditoría solo con `audit.log_event(org, event_type, result, actor, resource_type, resource_id, metadata)` y **sin PII en `metadata`**. Fechas "hoy" = `(now() AT TIME ZONE 'America/Bogota')::date`.
- **Suites SQL**: copiar la estructura de `supabase/tests/public_sold_out_test.sql` (`BEGIN; … ROLLBACK;`, helpers `pg_temp.add_collaborator` y `pg_temp.act_as`, `tests.assert_true`, `tests.assert_equals`, `tests.assert_raises`, `SET LOCAL ROLE anon|authenticated|service_role`). Usar UUIDs fijos propios de la suite.
- **Angular**: standalone + `ChangeDetectionStrategy.OnPush` + signals; formularios con `form()` de `@angular/forms/signals` (ADR-0001) como `src/app/features/catalog/addons/addon-form/addon-form.component.ts`; listados como `src/app/features/users/user-list/user-list.component.ts` pero con paginación en servidor como `ProductService.listPage` (`src/app/core/catalog/services/product.service.ts`, `range` + `count: 'exact'`); secciones con `<section class="section">` + `<h2>` y clases `.incomplete` / `.is-disabled` de `src/styles.scss`; errores con `toAppError`; textos de UI en español.
- **No** referenciar la service role key desde `src/`. **No** revertir los cambios locales existentes en `supabase/config.toml` ni `src/environments/environment.development.ts`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Carpetas, configuración de la Edge Function y plantilla de secretos

- [x] T001 Crear la estructura de carpetas con `.gitkeep`: `src/app/core/customers/models/`, `src/app/core/customers/services/`, `src/app/features/sales/requests/request-list/`, `src/app/features/sales/requests/request-detail/`, `src/app/features/sales/requests/request-intake/`, `src/app/features/sales/customers/customer-list/`, `src/app/features/sales/customers/customer-detail/`, `src/app/features/sales/shared/`, `supabase/functions/whatsapp-inbound/fixtures/`, `scripts/`
- [x] T002 [P] Crear `supabase/functions/.env.example` con `WHATSAPP_VERIFY_TOKEN=local-verify-token` y `WHATSAPP_APP_SECRET=local-dev-secret` y un comentario indicando copiarlo a `supabase/functions/.env` (ya ignorado por `.gitignore` vía el patrón `.env`) y que en producción se configuran con `supabase secrets set`
- [x] T003 [P] Agregar al final de `supabase/config.toml` el bloque `[functions.whatsapp-inbound]` con `verify_jwt = false` y un comentario: "Webhook de Meta; la autorización es la firma X-Hub-Signature-256 verificada en la función" (mismo formato que `[functions.register-agency]`; no tocar el resto del archivo)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Esquema base, núcleo único de captura, modelos y piezas compartidas de UI que usan todas las historias

**⚠️ CRITICAL**: Ninguna historia comienza hasta cerrar esta fase

- [x] T004 Crear `supabase/migrations/028_customer_request_enums.sql`: tipos `public.request_channel ('web','whatsapp','phone','in_person')`, `public.request_status ('received','in_review','discarded','pre_reservation')`, `public.document_type ('cc','ce','passport','nit','other')` con `COMMENT ON TYPE`; y una sentencia `ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS …` por cada valor: `request_received`, `request_assigned`, `request_status_changed`, `customer_updated`, `customer_anonymized` (los valores nuevos no se usan en este archivo)
- [x] T005 Crear `supabase/migrations/029_customers_requests.sql` (parte tablas) según data-model §1–§4 y §8: `ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_id_organization_id_key UNIQUE (id, organization_id)`; tablas `public.customers`, `public.customer_requests` (FK `customer_requests_assigned_to_fkey` compuesta a `user_profiles`, FK compuesta a `customers`, todos los CHECK listados incluidos `customer_requests_closed_at`, `customer_requests_discard_reason`, `customer_requests_first_handled`, `customer_requests_web_consent`, **sin** CHECK sobre fecha pasada), `public.customer_request_items` (FK compuesta a `products(id, organization_id)` y a `customer_requests` con `ON DELETE CASCADE`), `public.organization_sequences`; únicos parciales `customers_org_email_key`, `customers_org_phone_key`, `(organization_id, idempotency_key) WHERE idempotency_key IS NOT NULL`; todos los índices del data-model; triggers `set_updated_at` (función existente de `007`) en `customers` y `customer_requests`; función + trigger `public.prevent_customer_request_identity_change()` BEFORE UPDATE que rechaza (`VALIDATION_ERROR`) cambios de `channel`, `customer_id`, `reference`, `created_at`; RLS habilitado en las cuatro tablas, `REVOKE ALL … FROM anon`, `REVOKE INSERT, UPDATE, DELETE … FROM authenticated`, política `tenant_isolation_select` `FOR SELECT TO authenticated USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid)` en `customers`, `customer_requests`, `customer_request_items` y ninguna política en `organization_sequences` (además `REVOKE ALL … FROM authenticated`)
- [x] T006 Completar `supabase/migrations/029_customers_requests.sql` (parte vistas y Realtime): vistas `public.customer_request_list` y `public.customer_list` con `WITH (security_invoker = true)` y exactamente las columnas de data-model §Views (`item_count` vía subconsulta a `customer_request_items`; `request_count`/`last_request_at` vía subconsulta a `customer_requests`); `REVOKE ALL … FROM anon`, `GRANT SELECT … TO authenticated`; bloque `DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN ALTER PUBLICATION supabase_realtime ADD TABLE public.customer_requests; END IF; END $$;`
- [x] T007 Crear `supabase/migrations/030_customer_intake_core.sql` (parte utilidades): `public.normalize_email(text)` y `public.normalize_phone_e164(p_raw text, p_default_country_code text)` (`IMMUTABLE`, reglas de research R-004: quitar `[\s\-().]`, `+`/`00` internacional, quitar un `0` troncal, anteponer código por defecto, validar `^\+[1-9][0-9]{7,14}$`, NULL para vacío, `INVALID_PHONE`/`INVALID_EMAIL`); `public.organization_phone_country_code(uuid)` (`settings ->> 'default_phone_country_code'`, por defecto `'57'`); `public.next_organization_sequence(p_org uuid, p_scope text) → bigint` (`INSERT … ON CONFLICT (organization_id, scope) DO UPDATE SET last_value = organization_sequences.last_value + 1 RETURNING last_value`); `public.require_tenant_member() → uuid` copiando `require_catalog_manager()` de `018` pero aceptando `app_role IN ('agent','operator','admin')` y perfil vivo `status = 'active'`. Todas internas: `REVOKE ALL … FROM PUBLIC, anon, authenticated`
- [x] T008 Completar `supabase/migrations/030_customer_intake_core.sql` (parte núcleo): `public.match_or_create_customer(p_org uuid, p_contact jsonb, p_actor uuid) → jsonb` con las reglas exactas de research R-005 (email primero, luego teléfono, solo clientes `is_anonymized = false`; completar solo campos vacíos si el valor no pertenece a otro cliente; `contact_review_required` y `submitted_contact` cuando nombre/email/teléfono difieren o email y teléfono apuntan a clientes distintos; `CONTACT_REQUIRED` sin `first_name` o sin email y teléfono; normaliza con T007 usando el código de país de la organización); y `public.capture_request_core(p_org uuid, p_channel public.request_channel, p_customer_id uuid, p_contact jsonb, p_request jsonb, p_items jsonb, p_actor uuid) → jsonb` según data-model §Functions y research R-006: validar fechas (`TRAVEL_DATE_IN_PAST`, `INVALID_DATE_RANGE`), `adults` 1–99 y `children` 0–99 (`VALIDATION_ERROR`), textos acotados; resolver cliente (`p_customer_id` de la org y no anonimizado, si no `VALIDATION_ERROR` / `CUSTOMER_ANONYMIZED`); idempotencia por `idempotency_key` (capturar `unique_violation` y releer); huella `md5` de canal + customer_id + fechas + pasajeros + ítems ordenados + texto libre en minúsculas, ventana de 2 minutos; `reference = 'SOL-' || lpad(next_organization_sequence(p_org, 'customer_request')::text, 5, '0')`; insertar solicitud `status = 'received'` con `privacy_consent_at` tomado de `p_request ->> 'privacy_consent_at'`, ítems en orden (`position`), `created_by = p_actor`, `assigned_to`/`assigned_at` si `p_request ->> 'assign_to'` viene; `audit.log_event(..., 'request_received', 'success', p_actor, 'customer_request', id, jsonb_build_object('channel', p_channel, 'deduplicated', false))`; devolver `{request_id, reference, customer_id, customer_created, deduplicated, contact_review_required}`. Ambas internas (`REVOKE ALL … FROM PUBLIC, anon, authenticated`)
- [x] T009 [P] Crear `supabase/tests/customer_intake_core_test.sql` (ejecutado como superusuario, llamando funciones internas directamente): `normalize_phone_e164('+57 300 123 4567','57') = '+573001234567'`, `('0300 1234567','57')`, `('3001234567','57')`, `('0057 3001234567','57')` dan el mismo valor; `('+1 (305) 555-0123','57') = '+13055550123'`; `('123','57')` y `('abc','57')` lanzan `INVALID_PHONE`; `normalize_email(' Ana@Example.COM ') = 'ana@example.com'`, `'no-at'` lanza `INVALID_EMAIL`; `next_organization_sequence` devuelve 1, 2 para una org y 1 para otra; `match_or_create_customer` crea, luego vincula por email, luego por teléfono, completa un teléfono vacío, no sobrescribe un nombre distinto (marca revisión y guarda `submitted_contact`), vincula al cliente del email cuando email y teléfono apuntan a clientes distintos, ignora clientes anonimizados; `capture_request_core` crea `received` con referencia `SOL-00001`, deduplica por `idempotency_key` y por huella dentro de 2 minutos (simular antigüedad con `UPDATE created_at = now() - interval '3 minutes'` → ya no deduplica), rechaza `TRAVEL_DATE_IN_PAST` e `INVALID_DATE_RANGE`, escribe un `request_received` sin claves de PII en `metadata`
- [x] T010 [P] Crear `supabase/tests/customer_requests_rls_test.sql` (parte fundacional): dos organizaciones con un cliente y una solicitud cada una (insertados como superusuario vía `capture_request_core`); como `anon`: `SELECT` sobre `customers`, `customer_requests`, `customer_request_items`, `customer_request_list`, `customer_list` falla por privilegios; como `authenticated` de la org A: ve solo filas de A en tablas y vistas, `INSERT`/`UPDATE`/`DELETE` directos sobre `customers` y `customer_requests` fallan; `EXECUTE` de `capture_request_core`, `match_or_create_customer`, `normalize_phone_e164`, `require_tenant_member` está denegado para `anon` y `authenticated` (`has_function_privilege`); cambiar `channel` de una solicitud como superusuario lanza `VALIDATION_ERROR`
- [x] T011 Extender `supabase/seed.sql` con un bloque `DO $$` nuevo (idempotente: termina si ya existen `customers` para la org demo `00000000-0000-4000-a000-000000000001`) que: hace `UPDATE public.organizations SET settings = coalesce(settings,'{}'::jsonb) || '{"default_phone_country_code":"57"}'` para la org demo; crea vía `public.capture_request_core` dos clientes demo con solicitudes (`Laura Gómez`, `laura@example.com`, `+573001112233`, canal `web`, ítem `public_slug = 'islas-capri-premium'` resuelto a su `product_id`, `privacy_consent_at = now()`; `John Smith`, `+13055550123`, canal `phone`, ítem libre «Tour gastronómico», asignada al agente demo `00000000-0000-4000-b000-000000000003` y pasada a `in_review` con `first_handled_at = now()` mediante `UPDATE` directo)
- [x] T012 [P] Crear `src/app/core/customers/models/customer.model.ts`: tipos `DocumentType`, `Customer` (columnas de `customers`), `CustomerListRow` (columnas de `customer_list`), `CustomerContactInput`, `DOCUMENT_TYPE_LABELS` (data-model §Enums) y `customerDisplayName(c: { first_name: string; last_name: string | null; is_anonymized: boolean }): string` que devuelve `'Cliente anonimizado'` si `is_anonymized` o `first_name + ' ' + last_name` recortado
- [x] T013 [P] Crear `src/app/core/customers/models/request.model.ts`: tipos `RequestChannel`, `RequestStatus`, `ManualRequestStatus = 'in_review' | 'discarded'`, `RequestListRow` (columnas de `customer_request_list`), `RequestItem`, `RequestDetail` (fila + `customer`, `items`, `assignee`), `InboundMessage`, `RequestNote`, `CaptureResult`; `REQUEST_CHANNEL_LABELS`, `REQUEST_STATUS_LABELS` (data-model §Enums), `ASSISTED_CHANNELS = ['whatsapp','phone','in_person'] as const`; `isRequestClosed(status)` (`discarded` | `pre_reservation`) y `availableStatusActions(status): ManualRequestStatus[]` (`received` → `['in_review','discarded']`, `in_review` → `['discarded']`, resto `[]`), con comentario de que es solo affordance y la RPC `set_request_status` es la autoridad
- [x] T014 [P] Crear `src/app/core/customers/models/request.model.spec.ts` (Vitest) cubriendo `availableStatusActions` para los cuatro estados (nunca devuelve `pre_reservation`), `isRequestClosed`, que todas las claves de `RequestStatus`/`RequestChannel` tienen etiqueta, y crear `src/app/core/customers/models/customer.model.spec.ts` para `customerDisplayName` (anonimizado, sin apellido, con espacios)
- [x] T015 [P] Crear `src/app/core/customers/search-pattern.ts` con `toSearchOrFilter(q: string, columns: readonly string[], phoneColumns: readonly string[] = []): string | null` (contrato §4: quita `, ( ) * % \ : " '`, colapsa espacios, recorta a 80, devuelve `null` si queda vacío, produce `col.ilike.*term*` unidos por coma; para columnas de teléfono usa solo los dígitos del término y omite la columna si no hay dígitos) y `src/app/core/customers/search-pattern.spec.ts` (Vitest) con casos: vacío → null, inyección `a,b),or(id.eq.1` saneada, teléfono `300 123` → `*300123*`, texto sin dígitos omite columna de teléfono, recorte a 80
- [x] T016 [P] Ampliar `src/app/shared/components/data-table/list-query.ts`: agregar `channel` y `assignee` a `ListQuery`, `emptyListQuery`, `parseListQuery`, `listQueryToParams`, `FILTER_KEYS` y `hasActiveListFilters`; actualizar `src/app/shared/components/data-table/list-query.spec.ts` con casos de parseo, omisión de vacíos y reinicio de página al cambiar `channel`/`assignee`
- [x] T017 [P] Agregar los 15 códigos de contracts §6 a `AuthErrorCode` en `src/app/core/auth/models/auth.model.ts` y sus mensajes exactos a `USER_FACING_MESSAGES` en `src/app/core/error/error-handler.ts`; agregar a `src/app/core/error/error-handler.spec.ts` casos que mapean `{ message: 'CUSTOMER_CONTACT_TAKEN' }`, `{ message: 'CONTACT_REQUIRED' }`, `{ message: 'PRE_RESERVATION_REQUIRES_CONVERSION' }` y `{ message: 'LISTING_NOT_AVAILABLE' }` a su código
- [x] T018 Agregar a `src/app/app.routes.ts`, dentro de `children` del shell y antes de `settings`, el nodo `{ path: 'sales', children: [ { path: '', pathMatch: 'full', redirectTo: 'requests' } ] }` (las historias agregan sus hijos aquí)

**Checkpoint**: `./supabase/tests/run-sql-tests.sh customer_intake_core_test.sql customer_requests_rls_test.sql` y `npm test` en verde; el núcleo de captura existe pero ningún canal está expuesto todavía

---

## Phase 3: User Story 1 - Recepción de Solicitud vía Web (Priority: P1) 🎯 MVP

**Goal**: El sitio público externo envía solicitudes a `submit_public_request`; quedan en `received`, vinculadas a un cliente, y el equipo las ve en la bandeja **Comercial → Solicitudes**.

**Independent Test**: Ejecutar el escenario 1–4 de quickstart.md (curl a la RPC con anon key) y verificar la fila en `/sales/requests` y su detalle; `public_request_intake_test.sql` en verde.

### Tests for User Story 1

- [x] T019 [P] [US1] Crear `supabase/tests/public_request_intake_test.sql`: como `anon` (`SET LOCAL ROLE anon`, `request.jwt.claims` vacío) llamar `public.submit_public_request(org, payload)` y verificar: éxito devuelve solo `reference` y `deduplicated`; solicitud `received`, canal `web`, `privacy_consent_at` no nulo, cliente creado con email/teléfono normalizados, ítem con `product_id` y `public_slug` de una ficha publicada creada en la suite; errores `CONSENT_REQUIRED`, `CONTACT_REQUIRED`, `INVALID_EMAIL`, `INVALID_PHONE`, `TRAVEL_DATE_IN_PAST`, `INVALID_DATE_RANGE`, `VALIDATION_ERROR` (honeypot lleno, > 10 ítems, solicitud vacía, organización inexistente, organización `inactive`), `LISTING_NOT_AVAILABLE` (slug inexistente, ficha `draft`, ficha `sold_out = true`, producto `inactive`) sin filas creadas en cada caso; idempotencia por `idempotency_key` y por ventana de 2 min; `RATE_LIMITED` en la 6.ª solicitud de la misma hora para el mismo email; conflicto de contacto (escenario 4 de quickstart) marca `contact_review_required` sin cambiar el perfil; ninguna fila de `products`, `public_listings` o `pricing_schemes` cambia (comparar `count(*)` y `max(updated_at)` antes/después); un evento `request_received` por solicitud nueva y ninguno por deduplicada

### Implementation for User Story 1

- [x] T020 [US1] Crear `supabase/migrations/031_us1_public_request_intake.sql` con `public.submit_public_request(p_organization_id uuid, p_payload jsonb) → jsonb` (`SECURITY DEFINER`, `GRANT EXECUTE … TO anon, authenticated`), siguiendo contracts §1 y research R-001–R-003 en este orden: `octet_length(p_payload::text) <= 16384`; `jsonb_typeof` objeto; organización existe y `status = 'active'`; honeypot `website` vacío; `privacy_consent = true` (`CONSENT_REQUIRED`); ítems ≤ 10, cada `public_slug` resuelto en `public_listings` de la org con `status = 'published'`, `sold_out = false` y `products.status = 'active'` (si no `LISTING_NOT_AVAILABLE`); `interest_text` como ítem `free_text`; al menos un ítem, `interest_text` o `special_requirements`; si viene `idempotency_key` existente, devolver esa solicitud antes del throttling; throttling: > 5 solicitudes `web` en la última hora con el mismo email o teléfono normalizado del cliente, o > 200 `web` en la última hora para la org → `RATE_LIMITED`; luego `capture_request_core(org, 'web', NULL, contact, request{…, privacy_consent_at: now(), locale, source_page}, items, NULL)`; devolver `jsonb_build_object('reference', …, 'deduplicated', …)`
- [x] T021 [P] [US1] Crear `src/app/core/customers/services/request.service.ts` con `listPage(...)` (lee `customer_request_list`, `count: 'exact'`, `range` de 20 con `LIST_PAGE_SIZE`, orden `created_at desc`, filtros `status`, `channel`, `assignee` (uuid → `.eq('assigned_to')`, `'none'` → `.is('assigned_to', null)`), `customerId`, y búsqueda con `toSearchOrFilter(q, ['reference','customer_first_name','customer_last_name','customer_email'], ['customer_phone_e164'])`) y `getById(id)` con el select de contracts §4 (detalle con `customer`, `items` + `product`, `assignee` por `customer_requests_assigned_to_fkey`); patrón de `AddonService` (`inject(SupabaseService)`, `throw toAppError(error)`)
- [x] T022 [P] [US1] Crear `src/app/features/sales/requests/request-list/request-list.component.ts`: `app-data-table` título «Solicitudes», estado en query string con `parseListQuery`/`listQueryToParams`/`withListFilterChange` y búsqueda con `debounce(…, LIST_SEARCH_DEBOUNCE_MS)` como `UserListComponent`, pero recargando desde `RequestService.listPage` en cada cambio de query; filtros Buscar («Referencia, nombre, correo o teléfono»), Estado (Todos + 4 etiquetas), Canal (Todos + 4 etiquetas), Responsable (Todos / Mías → `assignee=me` resuelto a `AuthService.user().id` / Sin asignar → `none`; la lista de colaboradores se agrega en US3); columnas de contracts §5.4 con referencia enlazada a `/sales/requests/:id`, etiqueta «Datos a revisar» si `contact_review_required`, nombre vía `customerDisplayName`, «—» para vacíos; `emptyMessage` «Todavía no hay solicitudes.»; dejar un slot `dataTableCreate` vacío (US2 agrega el botón)
- [x] T023 [P] [US1] Crear `src/app/features/sales/requests/request-detail/request-detail.component.ts` (input `id` desde la ruta): carga con `RequestService.getById`, spinner/alerta de error/«No encontramos esta solicitud.»; encabezado `reference` + etiqueta de estado; secciones `.section` en orden: «Resumen» (canal, recibida, fechas de viaje, adultos/niños, consentimiento registrado sí/no, página de origen), «Cliente» (nombre enlazado a `/sales/customers/:id` como texto plano hasta US3, correo, teléfono; si `contact_review_required`, `app-alert kind="warning"` «Datos de contacto a revisar» con los valores de `submitted_contact`), «Intereses» (producto por nombre o texto libre, cantidad, slug público si existe), «Requerimientos del cliente» (`special_requirements`); enlace «Volver a solicitudes» que conserva la query previa (`history.back()` si viene de la lista, si no `/sales/requests`)
- [x] T024 [US1] Agregar a `src/app/app.routes.ts` dentro de `sales.children`: `{ path: 'requests', canActivate: [roleGuard('agent')], children: [ { path: '', pathMatch: 'full', loadComponent: RequestListComponent }, { path: ':id', loadComponent: RequestDetailComponent } ] }`
- [x] T025 [US1] Agregar el grupo «Comercial» a `NAV_TREE` en `src/app/shared/layout/nav-items.ts` justo después de `dashboard`: `{ id: 'sales', label: 'Comercial', path: null, minRole: 'agent', children: [{ id: 'sales-requests', label: 'Solicitudes', path: '/sales/requests', minRole: 'agent' }] }`; actualizar `src/app/shared/layout/nav-items.spec.ts`: árbol de admin y de agente incluyen `sales`, `sales-requests` tras `dashboard`; operador también; `activeNavItemId(items, '/sales/requests/abc') === 'sales-requests'`; `parentIdsForActive(items, 'sales-requests')` → `['sales']`

**Checkpoint**: US1 completa — una solicitud web aparece en la bandeja y su detalle sin código de WhatsApp ni de gestión

---

## Phase 4: User Story 2 - Captura y Registro de Solicitudes vía WhatsApp (Priority: P1)

**Goal**: El agente registra solicitudes de WhatsApp/teléfono/presencial desde el panel, y el adaptador de entrada convierte mensajes de WhatsApp en solicitudes o los agrega a una abierta, probable localmente sin credenciales.

**Independent Test**: Escenarios 5 y 6 de quickstart.md (alta asistida en `/sales/requests/new` y `scripts/simulate-whatsapp-inbound.sh`); `whatsapp_intake_test.sql` en verde.

### Tests for User Story 2

- [x] T026 [P] [US2] Crear `supabase/tests/whatsapp_intake_test.sql`: (a) `create_assisted_request` como agente: canal `whatsapp` con teléfono local `3001234567` vincula al cliente existente `+573001234567` sin duplicarlo (US2 esc. 2), asigna al agente, exige `privacy_notice_given` (`CONSENT_REQUIRED`), rechaza canal `web` (`VALIDATION_ERROR`), `customer_id` de otra org (`VALIDATION_ERROR`), producto `inactive` o de otra org (`VALIDATION_ERROR`), `anon` sin `EXECUTE`; (b) `ingest_whatsapp_webhook` como `service_role` con el JSON de `supabase/functions/whatsapp-inbound/fixtures/text-message.json` pegado inline: crea cliente por teléfono con nombre de perfil, solicitud `received` canal `whatsapp` con `special_requirements` = texto y un `inbound_messages`; reenviar el mismo payload → `duplicates = 1` sin filas nuevas; mensaje con otro `wamid` del mismo número → `messages_attached = 1` sobre la misma solicitud; tras descartar esa solicitud, un mensaje nuevo crea otra; `phone_number_id` desconocido o conexión `inactive` → `ignored`; mensaje `image` se guarda con cuerpo `[mensaje no soportado: image]`; `authenticated` y `anon` no pueden ejecutar `ingest_whatsapp_webhook`; `inbound_messages` y `channel_connections` aisladas por tenant y sin privilegios para `anon`

### Implementation for User Story 2

- [x] T027 [US2] Crear `supabase/migrations/032_us2_whatsapp_intake.sql` (parte tablas): `public.channel_connections` e `public.inbound_messages` según data-model §5–§6 (FKs compuestas, `UNIQUE (provider, external_account_id)`, `UNIQUE (provider, provider_message_id)`, CHECKs de `channel`, `provider`, `status`, longitudes), trigger `set_updated_at` en `channel_connections`, RLS + `tenant_isolation_select` + `REVOKE ALL … FROM anon` + `REVOKE INSERT, UPDATE, DELETE … FROM authenticated` en ambas
- [x] T028 [US2] Completar `supabase/migrations/032_us2_whatsapp_intake.sql` con `public.create_assisted_request(p_payload jsonb) → jsonb` (`require_tenant_member()`, `GRANT EXECUTE … TO authenticated`) según contracts §3.1: canal en `whatsapp|phone|in_person`; XOR `customer_id`/`contact`; `privacy_notice_given = true`; ítems `product_id` (producto `active` de la org) o `free_text`, ≤ 20; llama `capture_request_core(org, channel, customer_id, contact, request{…, privacy_consent_at: now(), assign_to: auth.uid()}, items, auth.uid())` y devuelve su resultado completo
- [x] T029 [US2] Completar `supabase/migrations/032_us2_whatsapp_intake.sql` con `public.ingest_whatsapp_webhook(p_payload jsonb) → jsonb` (`REVOKE … FROM PUBLIC, anon, authenticated`; `GRANT EXECUTE … TO service_role`) según research R-007: `object = 'whatsapp_business_account'` o `VALIDATION_ERROR`; por cada `entry[].changes[]` con `field = 'messages'`: resolver conexión activa por `value.metadata.phone_number_id` (si no, sumar `ignored` por mensaje); por cada `value.messages[]`: si `(provider, id)` existe sumar `duplicates`; normalizar `'+' || from`; nombre de `value.contacts[]` con `wa_id = from` o «Contacto WhatsApp»; `match_or_create_customer` (contacto solo con teléfono y nombre); buscar la solicitud más reciente del cliente con `channel = 'whatsapp'` y `status IN ('received','in_review')`: si existe adjuntar (`messages_attached`), si no `capture_request_core(org, 'whatsapp', customer_id, NULL, request{special_requirements: left(body, 2000)}, '[]', NULL)` (`requests_created`); insertar `inbound_messages` (`provider_timestamp = to_timestamp((timestamp)::bigint)`, `body` = `text.body` o `[mensaje no soportado: <type>]`, máx. 4096); ignorar `value.statuses[]`; devolver los cinco contadores
- [x] T030 [P] [US2] Crear `supabase/functions/whatsapp-inbound/fixtures/text-message.json`: payload de Meta Cloud API con `object: 'whatsapp_business_account'`, un `entry` con un `changes` `field: 'messages'`, `value.metadata.phone_number_id = 'local-dev-phone-number-id'`, `contacts: [{ profile: { name: 'María Pérez' }, wa_id: '573009998877' }]`, `messages: [{ from: '573009998877', id: 'wamid.local-1', timestamp: '1790000000', type: 'text', text: { body: 'Hola, quiero info del tour a Islas del Rosario para 2 personas' } }]`
- [x] T031 [US2] Extender `supabase/seed.sql` (bloque idempotente propio con `ON CONFLICT (provider, external_account_id) DO NOTHING`) insertando en `public.channel_connections` la conexión de la org demo: `channel 'whatsapp'`, `provider 'meta_cloud'`, `external_account_id 'local-dev-phone-number-id'`, `display_phone '+57 300 000 0000'`, `status 'active'`
- [x] T032 [P] [US2] Crear `supabase/functions/whatsapp-inbound/index.ts` según contracts §2, con la cabecera explicativa y estructura de `supabase/functions/register-agency/index.ts`: `GET` handshake con `WHATSAPP_VERIFY_TOKEN` (503 si no está configurado); `POST`: 503 `CHANNEL_NOT_CONFIGURED` sin `WHATSAPP_APP_SECRET`; leer cuerpo crudo con `await request.text()`; HMAC-SHA256 con `crypto.subtle` y comparación en tiempo constante contra `X-Hub-Signature-256` (`sha256=<hex>`) → 401 `INVALID_SIGNATURE`; `JSON.parse` y `object` → 400 `VALIDATION_ERROR`; `createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } }).rpc('ingest_whatsapp_webhook', { p_payload })` → 200 con contadores o 500 `INGEST_FAILED`; otros métodos 405; `console.log` solo de código de resultado y contadores, nunca cuerpo, teléfonos ni firma
- [x] T033 [P] [US2] Crear `scripts/simulate-whatsapp-inbound.sh` (ejecutable, `set -euo pipefail`): lee `WHATSAPP_APP_SECRET` de `supabase/functions/.env` salvo que venga `SECRET`; `URL` por defecto `http://127.0.0.1:54321/functions/v1/whatsapp-inbound`; copia el fixture a un temporal reemplazando `wamid.local-1` por `${WAMID:-wamid.local-1}` y `local-dev-phone-number-id` por `${PHONE_NUMBER_ID:-local-dev-phone-number-id}` con `sed`; firma con `openssl dgst -sha256 -hmac "$SECRET" -hex`; envía con `curl --data-binary @file -H "X-Hub-Signature-256: sha256=<hex>" -H 'Content-Type: application/json'` e imprime la respuesta; comentario de uso con los casos del escenario 6 de quickstart
- [x] T034 [P] [US2] Crear `src/app/features/sales/requests/request-intake/intake-payload.ts` con tipos `IntakeDraft` (canal, `customerId | null`, contacto, fechas `string`, adultos, niños, ítems `{ productId | null, freeText, quantity }[]`, requerimientos, `privacyNoticeGiven`), `validateIntakeDraft(draft, today: string): IntakeIssue[]` (affordance: nombre y correo-o-teléfono si no hay `customerId`; `privacyNoticeGiven`; inicio ≥ `today`; fin ≥ inicio; adultos 1–99; al menos un ítem o requerimiento; cada ítem con producto o texto) y `buildAssistedRequestPayload(draft, idempotencyKey): AssistedRequestPayload` (recorta textos, vacíos → `null`, omite `contact` si hay `customerId`, descarta filas de ítems vacías, conserva el teléfono tal cual para que lo normalice el servidor); y `src/app/features/sales/requests/request-intake/intake-payload.spec.ts` (Vitest) con un caso por regla y por transformación
- [x] T035 [US2] Extender `src/app/core/customers/services/request.service.ts` con `createAssisted(payload): Promise<CaptureResult>` (RPC `create_assisted_request`) y `listMessages(requestId)` (lee `inbound_messages` ordenado por `provider_timestamp`), y crear `src/app/core/customers/services/customer.service.ts` con `search(q, limit = 10)` sobre `customer_list` usando `toSearchOrFilter(q, ['first_name','last_name','email'], ['phone_e164'])` y excluyendo `is_anonymized = true`
- [x] T036 [US2] Crear `src/app/features/sales/requests/request-intake/request-intake.component.ts` (implementa `UnsavedChangesHost`): lee `channel` (por defecto `whatsapp`) y `customerId` de la query; Signal Form sobre `IntakeDraft`; secciones `.section` de contracts §5.4 («Canal», «Cliente» con buscador `CustomerService.search` y alternativa «Cliente nuevo», «Viaje» con `min` = hoy, «Intereses» con selector de productos activos `from('products').select('id, name, product_type').eq('status','active')` y texto libre, filas agregables/eliminables, «Notas del cliente», «Privacidad» con casilla obligatoria); errores de `validateIntakeDraft` junto a cada campo y `.incomplete` en la sección; `idempotencyKey = crypto.randomUUID()` por montaje; al guardar llama `createAssisted(buildAssistedRequestPayload(…))`, marca `allowLeave` y navega a `/sales/requests/:id`; si `deduplicated` muestra `app-alert` «Ya existía una solicitud igual; se abrió la existente.» en el detalle vía `history.state`; errores con `toAppError`
- [x] T037 [US2] Agregar en `src/app/app.routes.ts`, dentro de `sales.requests.children` y **antes** de `':id'`, `{ path: 'new', canDeactivate: [unsavedChangesGuard], loadComponent: RequestIntakeComponent }`; agregar en `src/app/features/sales/requests/request-list/request-list.component.ts` el botón `dataTableCreate` «Nueva solicitud» (`routerLink="/sales/requests/new"`, visible para todos los roles)
- [x] T038 [US2] Agregar a `src/app/features/sales/requests/request-detail/request-detail.component.ts` la sección «Conversación» (solo si `channel === 'whatsapp'`, tras «Requerimientos del cliente»): mensajes de `RequestService.listMessages` en orden cronológico con nombre de perfil, fecha/hora y cuerpo; estado vacío «No hay mensajes recibidos por WhatsApp para esta solicitud.»; y la alerta de solicitud deduplicada recibida por `history.state`

**Checkpoint**: US1 + US2 forman el MVP de captación multicanal

---

## Phase 5: User Story 3 - Gestión Centralizada de Perfiles de Clientes (Priority: P2)

**Goal**: El equipo gestiona solicitudes (asignación, estados, notas), recibe solicitudes nuevas sin recargar, y consulta/edita la ficha de cliente con su historial.

**Independent Test**: Escenarios 7 y 8 de quickstart.md; `request_workflow_test.sql` en verde.

### Tests for User Story 3

- [x] T039 [P] [US3] Crear `supabase/tests/request_workflow_test.sql`: `set_request_status` acepta `received→in_review` (fija `first_handled_at`), `received→discarded` e `in_review→discarded` con motivo (fija `closed_at`), rechaza descarte sin motivo (`DISCARD_REASON_REQUIRED`), `pre_reservation` desde cualquier estado (`PRE_RESERVATION_REQUIRES_CONVERSION`), `in_review→received` (`INVALID_STATUS_TRANSITION`), cambios desde `discarded` (`REQUEST_CLOSED`); `assign_request` a colaborador activo de la org (fija `assigned_at`), a NULL, a colaborador inactivo o de otra org (`ASSIGNEE_NOT_IN_ORGANIZATION`), sobre solicitud cerrada (`REQUEST_CLOSED`); auditoría `request_status_changed` y `request_assigned` con `from`/`to` y sin motivo ni PII; `add_request_note` exige exactamente un destino, fija `author_id = auth.uid()`, y `UPDATE`/`DELETE` sobre `request_notes` fallan incluso como superusuario (trigger append-only); `update_customer` normaliza, rechaza `CUSTOMER_CONTACT_TAKEN`, `CONTACT_REQUIRED`, audita `customer_updated` con `metadata.fields` y sin valores; los tres roles internos pueden ejecutar las cuatro RPCs; una solicitud de la org B devuelve `VALIDATION_ERROR` a un usuario de la org A; ninguna RPC crea filas fuera de las tablas de 003

### Implementation for User Story 3

- [x] T040 [US3] Crear `supabase/migrations/033_us3_request_workflow.sql`: tabla `public.request_notes` (data-model §7, FKs compuestas, CHECK `num_nonnulls`, RLS + `tenant_isolation_select` + revocaciones), función + trigger `public.reject_request_note_mutation()` BEFORE UPDATE OR DELETE (copiar el patrón de `audit.reject_audit_mutation` en `007`); RPCs `update_customer`, `assign_request`, `set_request_status`, `add_request_note` según contracts §3.3–§3.6 con `require_tenant_member()`, `SELECT … FOR UPDATE` sobre la solicitud antes de transicionar, y `GRANT EXECUTE … TO authenticated`
- [x] T041 [P] [US3] Crear `src/app/core/customers/services/request-realtime.service.ts`: `watchNewRequests(organizationId, onInsert): () => void` abre `supabase.client.channel('sales-requests:' + organizationId)` con `postgres_changes` `INSERT` filtrado por `organization_id=eq.<org>`; si el estado de suscripción es `CHANNEL_ERROR` o `TIMED_OUT`, activa `setInterval(onInsert, 10_000)`; la función devuelta llama `removeChannel` y limpia el intervalo
- [x] T042 [US3] Extender `src/app/core/customers/services/request.service.ts` con `assign`, `setStatus`, `addNote`, `listNotes` (contracts §5.5; notas con `author:user_profiles(full_name)` ordenadas desc.) y `listAssignees()` (`user_profiles` activos `id, full_name` ordenados); extender `src/app/core/customers/services/customer.service.ts` con `listPage({ q, page })` (vista `customer_list`, 20/página, orden `last_request_at desc nulls last`), `getById`, `update(id, input)` (RPC `update_customer`)
- [x] T043 [P] [US3] Crear `src/app/features/sales/shared/notes-section.component.ts` (`app-notes-section`, inputs `target: { requestId } | { customerId }` y `readonly`): carga `listNotes`, textarea + «Agregar nota» con Signal Form (requerido, ≤ 4000), aviso «No escribas datos personales sensibles en las notas.», listado con autor y fecha
- [x] T044 [US3] Agregar a `src/app/features/sales/requests/request-detail/request-detail.component.ts` la sección «Gestión» (responsable actual + selector de `listAssignees()` + botón «Asignarme»; botones de `availableStatusActions(status)`: «Pasar a En gestión», «Descartar» con campo de motivo obligatorio y confirmación; texto fijo «La pre-reserva se crea desde el módulo de pre-reservas.»; solo lectura si `isRequestClosed`) y la sección «Notas» con `app-notes-section`; recargar el detalle tras cada acción y mostrar errores con `toAppError`; convertir el nombre del cliente en enlace a `/sales/customers/:id`
- [x] T045 [US3] Conectar Realtime y filtro de responsables en `src/app/features/sales/requests/request-list/request-list.component.ts`: al montar, `RequestRealtimeService.watchNewRequests(auth.organizationId(), …)` que recarga la página actual y muestra `app-alert kind="info"` «Llegó una solicitud nueva.» por 5 s; desuscribir en `DestroyRef.onDestroy`; agregar al filtro Responsable las opciones de `listAssignees()`
- [x] T046 [P] [US3] Crear `src/app/features/sales/customers/customer-list/customer-list.component.ts`: `app-data-table` título «Clientes», sin botón de creación, filtro Buscar («Nombre, correo o teléfono») con debounce y query string, columnas de contracts §5.4 (nombre vía `customerDisplayName` enlazado a `/sales/customers/:id`), 20/página desde `CustomerService.listPage`, `emptyMessage` «Todavía no hay clientes. Se crean al registrar solicitudes.»
- [x] T047 [US3] Crear `src/app/features/sales/customers/customer-detail/customer-detail.component.ts` (implementa `UnsavedChangesHost`, input `id`): secciones «Datos de contacto» (Signal Form: nombre*, apellido, correo, teléfono, país; regla «Ingresa correo o teléfono»; guardar con `CustomerService.update`), «Documento» (tipo + número, mismo formulario), «Historial de solicitudes» (`RequestService.listPage({ customerId, page })` en una tabla simple: referencia enlazada, canal, estado, fecha; botón «Nueva solicitud para este cliente» → `/sales/requests/new?customerId=<id>`), «Notas» (`app-notes-section` con `customerId`); si `is_anonymized`, todo en solo lectura con `app-alert` «Este cliente fue anonimizado.»; deja preparado un hueco al final para la sección «Privacidad» (US4)
- [x] T048 [US3] Agregar en `src/app/app.routes.ts` dentro de `sales.children`: `{ path: 'customers', canActivate: [roleGuard('agent')], children: [ { path: '', pathMatch: 'full', loadComponent: CustomerListComponent }, { path: ':id', canDeactivate: [unsavedChangesGuard], loadComponent: CustomerDetailComponent } ] }`; agregar `{ id: 'sales-customers', label: 'Clientes', path: '/sales/customers', minRole: 'agent' }` como segundo hijo de `sales` en `src/app/shared/layout/nav-items.ts` y actualizar las expectativas de `src/app/shared/layout/nav-items.spec.ts` (incluye `activeNavItemId(items, '/sales/customers/abc') === 'sales-customers'`)

**Checkpoint**: US1–US3 operativas: captación, gestión del ciclo de la solicitud y ficha de cliente

---

## Phase 6: User Story 4 - Protección de Datos Personales y Privacidad (Priority: P2)

**Goal**: La PII no se expone fuera del tenant ni a `anon`, y el administrador puede anonimizar un cliente preservando el historial.

**Independent Test**: Escenario 9 de quickstart.md; `customer_privacy_test.sql` y `customer_requests_rls_test.sql` completos en verde.

### Tests for User Story 4

- [x] T049 [P] [US4] Crear `supabase/tests/customer_privacy_test.sql`: `anonymize_customer` como `agent` y `operator` → `INSUFFICIENT_PERMISSIONS`; como admin sin motivo → `VALIDATION_ERROR`; como admin con motivo: `first_name = 'Cliente anonimizado'`, `last_name`, `email`, `phone_e164`, `document_*`, `country_code` NULL, `is_anonymized = true`, `anonymized_at` no nulo; sus solicitudes conservan canal, estado, fechas, pasajeros e ítems de catálogo, con `submitted_contact` NULL, `special_requirements` y `free_text` = `'[anonimizado]'`; sus `inbound_messages` con `body = '[anonimizado]'`, `from_phone_e164` y `profile_name` NULL; notas internas intactas; segunda anonimización → `CUSTOMER_ANONYMIZED`; `update_customer` sobre el anonimizado → `CUSTOMER_ANONYMIZED`; una nueva `submit_public_request` con el email original crea un cliente nuevo; un único evento `customer_anonymized` cuya `metadata::text` no contiene el email, teléfono ni nombre originales; anonimizar un cliente de otra org → `VALIDATION_ERROR`
- [x] T050 [P] [US4] Completar `supabase/tests/customer_requests_rls_test.sql` con las tablas de US2/US3: `inbound_messages`, `channel_connections`, `request_notes` sin privilegios para `anon`, aisladas por tenant para `authenticated` y sin escrituras directas; matriz de `has_function_privilege`: `anon` solo puede ejecutar `submit_public_request` (y `get_public_site` de 009); `authenticated` ejecuta `create_assisted_request`, `update_customer`, `assign_request`, `set_request_status`, `add_request_note`, `anonymize_customer`; solo `service_role` ejecuta `ingest_whatsapp_webhook`

### Implementation for User Story 4

- [x] T051 [US4] Crear `supabase/migrations/034_us4_customer_privacy.sql` con `public.anonymize_customer(p_customer_id uuid, p_reason text) → jsonb` (`require_tenant_admin()`, `GRANT EXECUTE … TO authenticated`) según research R-012 y contracts §3.7: motivo 1–500 obligatorio; `SELECT … FOR UPDATE` del cliente de la org; limpieza de `customers`, `customer_requests` (`submitted_contact`, `special_requirements`), `customer_request_items.free_text`, `inbound_messages` en una transacción; `audit.log_event(..., 'customer_anonymized', 'success', auth.uid(), 'customer', id, jsonb_build_object('reason_provided', true, 'requests_scrubbed', n, 'messages_scrubbed', m))`; devolver `{customer_id, requests_scrubbed, messages_scrubbed}`; comentario `-- 006: rechazar aquí clientes con reservas vigentes cuando exista esa feature.`
- [x] T052 [US4] Agregar `anonymize(id, reason)` (RPC `anonymize_customer`) a `src/app/core/customers/services/customer.service.ts` y la sección «Privacidad» al final de `src/app/features/sales/customers/customer-detail/customer-detail.component.ts`, renderizada solo si `hasRoleAtLeast(auth.role(), 'admin')` y el cliente no está anonimizado: texto explicativo, motivo obligatorio, botón «Anonimizar cliente» con `window.confirm('Esta acción no se puede deshacer. ¿Anonimizar este cliente?')`; tras éxito recargar la ficha en solo lectura

**Checkpoint**: US1–US4 completas y verificadas

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T053 [P] Crear `docs/modules/customer-requests.md` con la estructura de `docs/modules/catalog-pricing.md`: propósito; spec/plan; tabla "What lives where" (migraciones `028`–`034`, `supabase/functions/whatsapp-inbound/`, `scripts/simulate-whatsapp-inbound.sh`, suites SQL, `src/app/core/customers/`, `src/app/features/sales/`); entidades; RPCs con quién puede llamarlas; contrato de `submit_public_request` para el sitio externo (ejemplo supabase-js, códigos de error, `idempotency_key` por montaje, consentimiento obligatorio); frontera WhatsApp (variables de entorno, alta de `channel_connections`, simulación, qué queda fuera); máquina de estados y contrato reservado para 004; RBAC; invariantes de seguridad (no regresar); tabla de rutas `/sales/*`; mapeo quickstart → evidencia automatizada
- [x] T054 [P] Enlazar el módulo en `AGENTS.md` agregando, antes de `<!-- SPECKIT START -->`, el párrafo "Customers & Requests (customer profiles, multichannel requests, WhatsApp intake boundary): see `docs/modules/customer-requests.md`." con el mismo formato de los dos párrafos existentes
- [x] T055 [P] Actualizar la navegación documentada por 010: en `docs/modules/identity-access.md` (sección "Admin layout (010)") agregar filas `/sales/requests`, `/sales/requests/new`, `/sales/requests/:id`, `/sales/customers`, `/sales/customers/:id` (todas «any collaborator»), y en `specs/010-admin-layout-navigation/contracts/ui-contracts.md` agregar al "Route map" esas rutas y al "Navigation tree contract" las filas «Comercial / Solicitudes» y «Comercial / Clientes» (✓ para los tres roles) con la nota "Agregado por 003 (orden: Dashboard → Comercial → Configuración → CMS)"
- [x] T056 [P] Actualizar el comentario de cabecera de `supabase/tests/run-sql-tests.sh` listando las suites de 003 (`customer_intake_core_test.sql`, `customer_requests_rls_test.sql`, `public_request_intake_test.sql`, `whatsapp_intake_test.sql`, `request_workflow_test.sql`, `customer_privacy_test.sql`); no cambiar la lógica del script
- [x] T057 Revisión de seguridad con evidencia en la descripción del PR: `rg -n "service_role|SERVICE_ROLE" src/` sin resultados; `rg -n "console\.(log|error)" supabase/functions/whatsapp-inbound/index.ts` solo imprime códigos y contadores; todas las funciones de `028`–`034` tienen `SET search_path = ''` y `REVOKE ALL … FROM PUBLIC`; ninguna llamada a `audit.log_event` de `030`–`034` pasa email, teléfono, nombre, motivo ni cuerpo de mensaje en `metadata`
- [x] T058 Ejecutar `./supabase/tests/run-sql-tests.sh` (todas las suites, incluidas las de 001/002/009), `npm test`, `npm run lint`, `npm run format:check` y `npm run build`; corregir cualquier fallo
- [x] T059 Ejecutar manualmente los escenarios 1–9 de `specs/003-customer-requests-channels/quickstart.md` con `supabase start` y `npm start`, y anotar en `docs/modules/customer-requests.md` (sección "Quickstart mapping") cuáles quedaron verificados en navegador y cuáles solo por SQL

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias.
- **Foundational (Phase 2)**: depende de Setup. Bloquea todas las historias. Orden interno obligatorio de migraciones: T004 → T005 → T006 → T007 → T008. T009/T010 tras T008. T011 tras T008. T012–T017 en paralelo en cualquier momento. T018 independiente.
- **US1 (Phase 3)**: depende de Foundational.
- **US2 (Phase 4)**: depende de Foundational y de las pantallas de US1 (T022–T024) porque agrega botón, ruta y sección a esos archivos. La parte SQL (T026–T031) solo depende de Foundational.
- **US3 (Phase 5)**: depende de Foundational y de T021–T024 (servicio y detalle de solicitud). Independiente de US2.
- **US4 (Phase 6)**: SQL (T049–T051) depende de Foundational, de `032` (T027) y de `033` (T040) porque limpia `inbound_messages` y verifica `request_notes`; UI (T052) depende de T047.
- **Polish (Phase 7)**: tras las historias que se entreguen.

### User Story Dependencies

- **US1 (P1)**: solo Foundational. MVP mínimo: captación web visible en el panel.
- **US2 (P1)**: Foundational + archivos de pantalla de US1. Comparte el núcleo de captura.
- **US3 (P2)**: Foundational + servicio/detalle de US1.
- **US4 (P2)**: Foundational + tablas de US2/US3.

### Within Each User Story

- La suite SQL de la historia se escribe primero y debe fallar antes de crear la migración de la historia.
- Migración → servicio TS → componentes → rutas/menú.
- Las tareas sobre el mismo archivo (`request-detail.component.ts`, `request-list.component.ts`, `app.routes.ts`, `nav-items.ts`, migraciones partidas en dos tareas) son secuenciales.

### Parallel Opportunities

- Setup: T002, T003.
- Foundational: T009, T010 (tras T008); T012, T013, T014, T015, T016, T017 en paralelo entre sí y con las migraciones.
- US1: T019 primero; luego T021, T022, T023 en paralelo tras T020.
- US2: T026, T030, T032, T033, T034 en paralelo; T027 → T028 → T029 secuenciales (mismo archivo).
- US3: T039, T041, T043, T046 en paralelo; T040 antes de T042.
- US4: T049, T050 en paralelo.
- Polish: T053–T056 en paralelo.

---

## Parallel Example: User Story 1

```bash
# Tras T020 (migración 031):
Task: "T021 [US1] RequestService.listPage/getById en src/app/core/customers/services/request.service.ts"
Task: "T022 [US1] RequestListComponent en src/app/features/sales/requests/request-list/request-list.component.ts"
Task: "T023 [US1] RequestDetailComponent en src/app/features/sales/requests/request-detail/request-detail.component.ts"
```

## Parallel Example: User Story 2

```bash
Task: "T030 [US2] Fixture en supabase/functions/whatsapp-inbound/fixtures/text-message.json"
Task: "T032 [US2] Edge Function en supabase/functions/whatsapp-inbound/index.ts"
Task: "T033 [US2] Script en scripts/simulate-whatsapp-inbound.sh"
Task: "T034 [US2] intake-payload.ts + spec en src/app/features/sales/requests/request-intake/"
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Phase 1 + Phase 2 (checkpoint: suites de núcleo y RLS en verde).
2. US1 → validar escenarios 1–4 de quickstart. **Punto de demo**: el sitio externo ya puede enviar solicitudes.
3. US2 → validar escenarios 5–6 (sin credenciales de Meta).
4. **STOP y VALIDAR**: captación multicanal centralizada.

### Incremental Delivery

1. Foundational.
2. US1 → demo (web → bandeja).
3. US2 → demo (alta asistida + simulación WhatsApp).
4. US3 → demo (gestión, Realtime, ficha de cliente).
5. US4 → demo (anonimización).
6. Polish → documentación y verificación completa.

### Parallel Team Strategy

Tras Foundational: dev A en US1 → US2 (pantallas de solicitudes); dev B en la parte SQL de US2 (T026–T031) y la Edge Function; dev C en US3 SQL (T039–T040) y luego US4 SQL. La UI de US3/US4 espera a que US1 cierre sus archivos.

---

## Notes

- Una solicitud nunca crea pre-reservas, cotizaciones ni toca `products`/`public_listings`/`pricing_schemes`; `pre_reservation` solo lo asignará 004 (contracts §3.8).
- Toda escritura pasa por RPC; las tablas son SELECT-only para `authenticated` y opacas para `anon`.
- Una sola normalización de teléfono/email y un solo núcleo de captura (`030`): no reimplementar reglas en TypeScript más allá de validaciones de affordance (`intake-payload.ts`, `availableStatusActions`).
- El adaptador WhatsApp debe funcionar sin cambios de código al pasar de la simulación local a credenciales reales: solo variables de entorno y una fila en `channel_connections`.
- Riesgos conocidos (ver research): sin captcha en el canal web (R-002); normalización E.164 simplificada para números nacionales no colombianos sin `+` (R-004); notas internas no se anonimizan (R-012); Realtime no existe en el harness Docker (solo validación manual, con respaldo por consulta).
