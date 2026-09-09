---
description: "Task list for 002-catalog-pricing implementation"
---

# Tasks: 002-catalog-pricing (Catálogo Turístico & Precios)

**Input**: Design documents from `/specs/002-catalog-pricing/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-contracts.md, quickstart.md. Requiere la feature `001-auth-tenant-access` desplegada (organizaciones, `user_profiles`, claims JWT `organization_id`/`app_role`, esquema `audit`).

**Tech Stack**: Angular 22 (Standalone, Signals, Signal Forms), TypeScript 6.x, Supabase (PostgreSQL + RLS). Extiende la app y el esquema existentes de la feature 001.

**Tests**: Se incluyen solo los tests exigidos por criterios de éxito — aislamiento multi-tenant del catálogo (SC-002), cálculo de precios por temporada/anti-solapamiento (SC-003) y no-retroactividad de precios (SC-002). Migraciones nuevas inician en `011` (001 dejó hasta `010`).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede correr en paralelo (archivos distintos, sin dependencias pendientes)
- **[Story]**: US1–US4 según spec.md
- Rutas de archivo exactas incluidas

## Path Conventions

- **Frontend**: `src/app/core/catalog/`, `src/app/features/catalog/`
- **Backend**: `supabase/migrations/`, `supabase/tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Estructura del módulo de catálogo

- [X] T001 Crear estructura del módulo de catálogo: `src/app/core/catalog/{services,models}/` y `src/app/features/catalog/{products,packages,addons,pricing}/`
- [X] T002 [P] Añadir shell de rutas `/catalog` y entradas de navegación (solo Operador/Admin) en `src/app/app.routes.ts` y `src/app/features/dashboard/dashboard.component.ts`
- [X] T003 [P] Extender `supabase/seed.sql` con categorías y proveedor demo para la organización semilla
- [X] T004 [P] Extender el runner de tests SQL (`supabase/tests/run-sql-tests.sh`) para incluir las nuevas suites de catálogo/precios

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Esquema base de catálogo/precios y modelos Angular requeridos por TODAS las historias

**⚠️ CRITICAL**: Ninguna historia puede comenzar hasta completar esta fase

- [X] T005 Crear enums en `supabase/migrations/011_create_catalog_enums.sql` (`product_type`, `product_status`, `experience_difficulty`, `addon_unit`, `charge_type`)
- [X] T006 Ampliar `audit.audit_event_type` con `price_overridden`, `product_activated`, `product_deactivated` en `supabase/migrations/012_alter_audit_event_types.sql`
- [X] T007 Crear tabla `providers` (organization-scoped) + RLS + `updated_at` en `supabase/migrations/013_create_providers.sql`
- [X] T008 Crear tabla base `products` (+ `organization_id`, índices `(organization_id,status)`/`(organization_id,type)`, RLS por `organization_id`, trigger `updated_at`) en `supabase/migrations/014_create_products.sql`
- [X] T009 Crear subtipos `experiences` y `accommodations` (PK compartida con `products`, `organization_id` denormalizado para RLS) en `supabase/migrations/015_create_product_subtypes.sql`
- [X] T010 Crear `categories` (jerarquía opcional `parent_id`) y `product_categories` (N:M) + RLS en `supabase/migrations/016_create_categories.sql`
- [X] T011 Crear `pricing_schemes` (XOR product/addon, `currency` por esquema con default de organización, `charge_type`, temporada, versionado `valid_from`/`valid_to`, `EXCLUDE USING gist` anti-solapamiento), función `resolve_price()` y trigger `enforce_active_requires_price()` en `supabase/migrations/017_create_pricing.sql`
- [X] T012 [P] Crear modelos de dominio en `src/app/core/catalog/models/product.model.ts`, `category.model.ts`, `addon.model.ts`, `pricing.model.ts`
- [X] T013 Proteger el shell `/catalog` con `roleGuard` (Operador/Admin) reutilizando el guard de la feature 001 en `src/app/app.routes.ts`
- [X] T014 [P] Verificar migraciones foundational contra Postgres 17 dockerizado (extiende harness existente); confirmar RLS habilitado y `EXCLUDE` activa

**Checkpoint**: Esquema base y modelos listos — las historias pueden iniciar

---

## Phase 3: User Story 1 - Gestión de Experiencias y Alojamientos (Priority: P1) 🎯 MVP

**Goal**: Alta, edición, categorización y activación/desactivación lógica de experiencias y alojamientos en el catálogo interno.

**Independent Test**: Crear una experiencia y un alojamiento con sus atributos, editarlos, categorizarlos, activar (con precio válido) y desactivar, y listarlos filtrando por tipo/estado.

- [X] T015 [US1] Crear RPCs `create_product` (base + subtipo atómico, estado `draft`) y `set_product_status` (valida `PRODUCT_HAS_NO_VALID_PRICE`, emite auditoría) en `supabase/migrations/018_us1_product_rpcs.sql`
- [X] T016 [US1] Implementar `ProductService` (crear/listar/editar/estado, filtros por tipo/estado/categoría) en `src/app/core/catalog/services/product.service.ts`
- [X] T017 [P] [US1] Implementar `CategoryService` (CRUD taxonomías + asignación N:M) en `src/app/core/catalog/services/category.service.ts`
- [X] T018 [P] [US1] Implementar `ProductListComponent` (catálogo interno con filtros) en `src/app/features/catalog/products/product-list/product-list.component.ts`
- [X] T019 [P] [US1] Implementar `ProductCreateComponent` con Signal Forms (experiencia/alojamiento) en `src/app/features/catalog/products/product-create/product-create.component.ts`
- [X] T020 [P] [US1] Implementar `ProductDetailComponent` (editar atributos, estado y categorías) en `src/app/features/catalog/products/product-detail/product-detail.component.ts`
- [X] T021 [US1] Cablear rutas `/catalog/products` con `roleGuard('operator')` en `src/app/app.routes.ts`
- [X] T022 [P] [US1] Escribir `supabase/tests/catalog_rls_test.sql` (aislamiento multi-tenant de `products`/subtipos/`categories`; acceso cross-tenant por ID directo vacío) — SC-002

**Checkpoint**: US1 funcional y testeable de forma independiente

---

## Phase 4: User Story 2 - Add-ons y Personalización de Productos (Priority: P1)

**Goal**: Crear complementos independientes y vincularlos como opciones elegibles de productos con reglas de aplicabilidad.

**Independent Test**: Crear un add-on, vincularlo a una experiencia con `is_mandatory`/`max_quantity`, y consultarlo como complemento elegible con sus reglas.

- [X] T023 [US2] Crear tablas `add_ons` y `product_addons` (reglas `is_mandatory`/`max_quantity`, UNIQUE por par) + RLS en `supabase/migrations/019_us2_addons.sql`
- [X] T024 [US2] Implementar `AddonService` (CRUD add-ons + vínculo/consulta por producto) en `src/app/core/catalog/services/addon.service.ts`
- [X] T025 [P] [US2] Implementar `AddonListComponent` en `src/app/features/catalog/addons/addon-list/addon-list.component.ts`
- [X] T026 [P] [US2] Implementar `AddonFormComponent` con Signal Forms en `src/app/features/catalog/addons/addon-form/addon-form.component.ts`
- [X] T027 [US2] Añadir gestión de add-ons elegibles (reglas) en `ProductDetailComponent` (`src/app/features/catalog/products/product-detail/product-detail.component.ts`)
- [X] T028 [US2] Cablear rutas `/catalog/addons` con `roleGuard('operator')` en `src/app/app.routes.ts`

**Checkpoint**: US1 + US2 funcionan de forma independiente (MVP)

---

## Phase 5: User Story 3 - Composición de Paquetes Predefinidos (Priority: P2)

**Goal**: Combinar experiencias/alojamientos/add-ons en un paquete con itinerario y precio explícito; advertir inconsistencias por componentes inactivos.

**Independent Test**: Crear un paquete con una experiencia y dos noches de alojamiento; desactivar un componente y verificar la advertencia de inconsistencia (sin auto-desactivar).

- [X] T029 [US3] Crear `packages` y `package_items` (+ RLS), RPC `create_package` (rechaza anidamiento `PACKAGE_NESTING_NOT_ALLOWED` y componentes de otra org) y `get_package_consistency` en `supabase/migrations/021_us3_packages.sql`
- [X] T030 [US3] Extender `ProductService` con composición de paquetes (crear/listar paquetes, consultar consistencia) en `src/app/core/catalog/services/product.service.ts`
- [X] T031 [P] [US3] Implementar `PackageListComponent` en `src/app/features/catalog/packages/package-list/package-list.component.ts`
- [X] T032 [P] [US3] Implementar `PackageBuilderComponent` con Signal Forms (selección de componentes + itinerario día/noche) en `src/app/features/catalog/packages/package-builder/package-builder.component.ts`
- [X] T033 [US3] Mostrar advertencia de inconsistencia de paquete (usa `get_package_consistency`) en `PackageBuilderComponent`/`PackageListComponent`
- [X] T034 [US3] Cablear rutas `/catalog/packages` con `roleGuard('operator')` en `src/app/app.routes.ts`

**Checkpoint**: US1–US3 funcionan de forma independiente

---

## Phase 6: User Story 4 - Definición y Estructuración de Precios (Priority: P2)

**Goal**: Definir precios base/temporada por producto o add-on (Operador/Admin), con versionado no-retroactivo y sobreescritura manual auditada (solo Admin).

**Independent Test**: Configurar tarifa base y de temporada (rechazando solapamiento); versionar un precio sin alterar históricos; aplicar una sobreescritura manual como Admin y verificar el evento de auditoría; `resolve_price` devuelve la tarifa correcta por fecha.

- [X] T035 [US4] Crear RPCs `upsert_pricing_scheme` (Operador/Admin; versiona append-only, `SEASON_OVERLAP`/`INVALID_SEASON_RANGE`/`INVALID_PRICE_TARGET`) y `apply_price_override` (solo Admin) + `audit_price_override()` en `supabase/migrations/020_us4_pricing_rpcs.sql`
- [X] T036 [US4] Implementar `PricingService` (definir/versionar precio, override, `resolve_price`) en `src/app/core/catalog/services/pricing.service.ts`
- [X] T037 [P] [US4] Implementar `PricingEditorComponent` con Signal Forms (base/temporada, `charge_type`, moneda) en `src/app/features/catalog/pricing/pricing-editor/pricing-editor.component.ts`
- [X] T038 [US4] Integrar el editor de precios en `ProductDetailComponent` (definición Operador/Admin) y acción de sobreescritura manual visible solo para Admin
- [X] T039 [P] [US4] Escribir `supabase/tests/pricing_rules_test.sql` (`resolve_price` temporada vs base + anti-solapamiento `EXCLUDE`) — SC-003
- [X] T040 [P] [US4] Escribir `supabase/tests/price_freeze_test.sql` (versionado no-retroactivo: históricos inmutables al cambiar tarifa) — SC-002
- [X] T041 [US4] Verificar generación del evento `price_overridden` (actor, org, previous/new, motivo) tras `apply_price_override` en `supabase/tests/pricing_rules_test.sql`

**Checkpoint**: US1–US4 funcionan de forma independiente

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Mejoras transversales

- [X] T042 [P] Reutilizar componentes compartidos `alert`/`spinner` (feature 001) en las pantallas de catálogo (`src/app/features/catalog/**`)
- [X] T043 Ejecutar validación completa de `specs/002-catalog-pricing/quickstart.md` (8 escenarios)
- [X] T044 [P] Revisión de seguridad: Default Deny + RLS por `organization_id`, definición de precios Operador/Admin, sobreescritura solo Admin, claims server-side
- [X] T045 [P] Verificar rendimiento: listado de catálogo < 1s para 5,000 ítems (SC-004) y cálculo de precios (SC-003)
- [X] T046 Actualizar documentación del módulo (`docs/modules/catalog-pricing.md`) y sincronizar `AGENTS.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Sin dependencias
- **Foundational (Phase 2)**: Depende de Setup — BLOQUEA todas las historias (incluye la tabla `pricing_schemes`, de la que depende la activación de productos por R-008)
- **User Stories (Phase 3–6)**: Dependen de Foundational
  - US1 (P1) y US2 (P1) forman el MVP
  - US3 y US4 (P2) pueden desarrollarse en paralelo tras Foundational
- **Polish (Phase 7)**: Depende de las historias entregadas

### User Story Dependencies

- **US1 (P1)**: Foundational. La activación de producto requiere un `pricing_scheme` vigente (tabla foundational; el flujo completo de definición de precios es US4).
- **US2 (P1)**: Foundational. Los add-ons se tarifan con `pricing_schemes` (foundational).
- **US3 (P2)**: Foundational + productos existentes (componentes). Precio de paquete explícito vía US4.
- **US4 (P2)**: Foundational. Provee la UI/RPCs de precios que completan la activación de US1/US2/US3.

### Parallel Opportunities

- Setup: T002, T003, T004 en paralelo
- Foundational: T012, T014 en paralelo (tras migraciones)
- US1: T017, T018, T019, T020, T022 en paralelo (tras T015/T016)
- US2: T025, T026 en paralelo
- US3: T031, T032 en paralelo
- US4: T037, T039, T040 en paralelo
- Con equipo: US3 y US4 en paralelo por desarrolladores distintos tras Foundational

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Completar Phase 1 (Setup) y Phase 2 (Foundational)
2. Completar US1 → validar alta/edición/estado de productos
3. Completar US2 → validar add-ons y personalización
4. **STOP y VALIDAR**: catálogo base con complementos

### Incremental Delivery

1. Foundational listo
2. US1 → demo (catálogo de experiencias/alojamientos)
3. US2 → demo (add-ons)
4. US4 → demo (precios y temporadas) — habilita activación comercial completa
5. US3 → demo (paquetes)

---

## Notes

- `[P]` = archivos distintos, sin dependencias pendientes
- Todos los formularios usan **Signal Forms** (Angular 22, ADR-0001)
- Roles: gestión de catálogo y definición de precios → Operador/Admin; sobreescritura manual de precio → solo Admin (ver Clarifications del spec, FR-008/FR-009)
- Migraciones SQL secuenciales desde `011`; respetar orden de archivos
- Validar tests de aislamiento (T022), reglas de precio (T039) y no-retroactividad (T040) antes de cerrar US1/US4
- Reutiliza claims JWT, RLS helpers, `audit.audit_events` y componentes compartidos de la feature 001 (Composition Over Duplication)
