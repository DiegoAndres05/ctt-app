---
description: "Task list for 009-catalog-site-cms implementation"
---

# Tasks: 009-catalog-site-cms (Contenido público del catálogo)

**Input**: Design documents from `/specs/009-catalog-site-cms/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-contracts.md, quickstart.md. Requiere `001-auth-tenant-access` y `002-catalog-pricing` desplegados (productos, tarifas, `require_catalog_manager`, `upsert_pricing_scheme`, `set_product_status`, `audit.audit_events`).

**Tech Stack**: Angular 22 (Standalone, Signals, Signal Forms), TypeScript 6.x, Supabase (PostgreSQL + RLS + Storage). Extiende el módulo Catálogo; migraciones nuevas desde `022`.

**Tests**: Se incluyen las suites SQL del quickstart (reglas, RLS, cutover, agotado). No se añaden suites Vitest salvo las necesarias para validar formularios de ficha si ya existen patrones en el módulo.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede correr en paralelo (archivos distintos, sin dependencias pendientes)
- **[Story]**: US1–US5 según spec.md (orden de fases por prioridad P1 → P2)
- Rutas de archivo exactas incluidas

## Path Conventions

- **Frontend**: `src/app/core/catalog/`, `src/app/features/catalog/`
- **Backend**: `supabase/migrations/`, `supabase/tests/`
- **Docs**: `docs/modules/catalog-pricing.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Carpetas y cables mínimos del módulo público sobre el catálogo existente

- [X] T001 Crear carpetas `src/app/features/catalog/public-categories/` y `src/app/features/catalog/public-cutover/` según `specs/009-catalog-site-cms/plan.md`
- [X] T002 [P] Extender `supabase/tests/run-sql-tests.sh` para incluir `public_listing_rules_test.sql`, `public_listing_rls_test.sql`, `public_cutover_test.sql` y `public_sold_out_test.sql`
- [X] T003 [P] Añadir entradas de navegación placeholder (Categorías públicas, Cambio de fuente) en `src/app/features/catalog/catalog-shell/catalog-shell.component.ts` protegidas con el mismo `roleGuard('operator')` del catálogo

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Esquema, Storage, lectura pública y modelos compartidos por todas las historias

**⚠️ CRITICAL**: Ninguna historia puede comenzar hasta completar esta fase

- [X] T004 Crear enums `public_placement`, `public_listing_status`, `public_source`, `public_image_role`, `lodging_type`, `yacht_icon`, `lodging_amenity` en `supabase/migrations/022_public_listing_enums.sql`
- [X] T005 Ampliar `audit.audit_event_type` con `public_listing_published`, `public_listing_unpublished`, `public_image_replaced`, `public_listing_sold_out_changed`, `public_cutover_completed` en `supabase/migrations/022_public_listing_enums.sql` (o migración `022` adjunta si el proyecto separa enums/audit)
- [X] T006 Crear tablas `public_sites`, `public_categories`, `public_listings`, `public_images`, `guest_reviews`, `public_cutover_items` + índices, RLS por `organization_id` y `REVOKE` de `anon` en `supabase/migrations/023_public_listings.sql` según `specs/009-catalog-site-cms/data-model.md`
- [X] T007 Sembrar las ocho categorías públicas protegidas (`islas`, `baru`, `tierra_bomba`, `compartidos`, `cultural`, `aventura`, `baile`, `premium`) y fila `public_sites` (`source = legacy`) por organización en `supabase/migrations/023_public_listings.sql` o seed dedicado
- [X] T008 Crear trigger de desactivación de producto: ficha `published` → `unpublished` al pasar `products.status` a `inactive` en `supabase/migrations/023_public_listings.sql`
- [X] T009 Crear bucket `catalog-media` (público lectura, 10 MB, MIME jpeg/png/webp) y políticas de escritura `operator`/`admin` por prefijo `organization_id` en `supabase/migrations/026_catalog_media_bucket.sql`
- [X] T010 Crear RPC `get_public_site(organization_id)` ejecutable por `anon`/`authenticated` (arreglos vacíos si `source = legacy`; proyección Offer/Lodging/Yacht si `panel`) en `supabase/migrations/025_public_site_read.sql`
- [X] T011 [P] Crear modelos TypeScript en `src/app/core/catalog/models/public-listing.model.ts` (listing, placement, bilingual pair, lodging, yacht line, guest review, public category, public site)
- [X] T012 Crear `PublicListingService` base (lectura de ficha por `product_id`, llamada a `get_public_site`, tipos de error) en `src/app/core/catalog/services/public-listing.service.ts`
- [X] T013 Verificar migraciones foundational contra Postgres 17 dockerizado con el harness existente y confirmar RLS + `anon` sin acceso a `products`/`pricing_schemes`

**Checkpoint**: Esquema, Storage y modelos listos — las historias pueden iniciar

---

## Phase 3: User Story 1 - Publicar una oferta (Priority: P1) 🎯 MVP

**Goal**: Completar, guardar borrador y publicar la ficha pública de una experiencia o paquete (`placement = catalog`) con la estructura bilingüe de la página.

**Independent Test**: En una experiencia `active` con tarifa, completar slug, textos ES/EN, categoría pública, ubicación, inclusiones y precio de vitrina; publicar; rechazar publicación incompleta o con listas bilingües desiguales; editar precio de vitrina sin versionar `pricing_schemes`.

### Implementation for User Story 1

- [X] T014 [US1] Implementar RPC `save_public_listing` (validación placement/tipo, slug único, pares bilingües, `ORIGINAL_PRICE_NOT_HIGHER`, inmutabilidad de slug/placement tras primera publicación) en `supabase/migrations/024_public_listing_rpcs.sql`
- [X] T015 [US1] Implementar RPC `publish_public_listing` (`PUBLIC_LISTING_INCOMPLETE`, `PRODUCT_NOT_ACTIVE`, `PRODUCT_HAS_NO_VALID_PRICE`, evento `public_listing_published`) en `supabase/migrations/024_public_listing_rpcs.sql`
- [X] T016 [US1] Extender `PublicListingService` con `saveListing` y `publishListing` en `src/app/core/catalog/services/public-listing.service.ts`
- [X] T017 [US1] Añadir sección «Ficha pública» (placement catalog) con Signal Forms en `src/app/features/catalog/products/product-detail/product-detail.component.ts` (campos Offer + categoría pública + precio de vitrina; botones Guardar borrador / Publicar)
- [X] T018 [P] [US1] Escribir `supabase/tests/public_listing_rules_test.sql` (pares bilingües, precio anterior, slug inmutable, `PLACEMENT_PRODUCT_MISMATCH`, vitrina no versiona tarifa)

**Checkpoint**: US1 funcional y testeable de forma independiente (MVP)

---

## Phase 4: User Story 2 - Cargar y reemplazar imágenes (Priority: P1)

**Goal**: Subir, reemplazar y rechazar la imagen principal de una ficha; conservar referencia externa en copias.

**Independent Test**: Subir JPEG &lt; 10 MB como portada; reemplazarla y ver `public_image_replaced`; rechazar PDF y archivo &gt; 10 MB sin perder la portada anterior; impedir quitar la única portada de una ficha publicada.

### Implementation for User Story 2

- [X] T019 [US2] Implementar RPC `attach_public_image` (`storage_path` XOR `external_ref`, `COVER_REQUIRED`, `IMAGE_*`, evento `public_image_replaced`) en `supabase/migrations/024_public_listing_rpcs.sql`
- [X] T020 [US2] Extender `PublicListingService` con upload a `catalog-media` y `attachImage` en `src/app/core/catalog/services/public-listing.service.ts`
- [X] T021 [US2] Añadir control de carga/reemplazo de portada (y mensajes de error de MIME/tamaño) en la sección Ficha pública de `src/app/features/catalog/products/product-detail/product-detail.component.ts`
- [X] T022 [US2] Exigir `cover_image_ref` en `publish_public_listing` y actualizar proyección `image` de `get_public_site` en `supabase/migrations/025_public_site_read.sql`

**Checkpoint**: US1 + US2 funcionan de forma independiente

---

## Phase 5: User Story 5 - Conservar el catálogo vigente al cambiar la fuente (Priority: P1)

**Goal**: Copiar ofertas, alojamientos y yates vigentes; crear tarifa inicial desde el precio actual; bloquear el cutover hasta completar el manifiesto; pasar `source` a `panel`.

**Independent Test**: Manifiesto incompleto → `CUTOVER_INCOMPLETE` y `source = legacy`. Con todo publicado y activo → `complete_public_cutover` deja `source = panel` y `get_public_site` proyecta solo panel. Tarifas iniciales = precio actual (no tachado). Yates sin precio inventado.

### Implementation for User Story 5

- [X] T023 [US5] Extender `save_public_listing` / `publish_public_listing` para `placement = yacht` (líneas capacity/feature, sin precio/categoría obligatorios) en `supabase/migrations/024_public_listing_rpcs.sql`
- [X] T024 [US5] Implementar RPC `complete_public_cutover` (admin, `CUTOVER_INCOMPLETE` con slugs faltantes, `CUTOVER_ALREADY_COMPLETED`, evento `public_cutover_completed`) en `supabase/migrations/024_public_listing_rpcs.sql`
- [X] T025 [US5] Crear semilla del manifiesto (29 ofertas, 6 alojamientos, 4 yates), productos experiencia/alojamiento, fichas publicadas, tarifas iniciales `per_person`/`per_night` y referencias de imagen existentes en `supabase/migrations/027_public_catalog_seed.sql`
- [X] T026 [US5] Extender `PublicListingService` con `completeCutover` y `getCutoverStatus` en `src/app/core/catalog/services/public-listing.service.ts`
- [X] T027 [P] [US5] Implementar UI de ficha yate (capacidades/características/iconos, precio opcional) en `src/app/features/catalog/products/product-detail/product-detail.component.ts` cuando el producto sea experiencia elegible como yate o tenga `placement = yacht`
- [X] T028 [P] [US5] Implementar pantalla de cambio de fuente (estado legacy/panel, lista de slugs faltantes, acción Completar) en `src/app/features/catalog/public-cutover/public-cutover.component.ts` y cablear ruta en `src/app/app.routes.ts`
- [X] T029 [US5] Escribir `supabase/tests/public_cutover_test.sql` (compuerta, cutover exitoso, tarifa inicial ≠ cambio posterior de vitrina, yates sin precio inventado)

**Checkpoint**: Cutover y manifiesto verificables; US1/US2 siguen válidos

---

## Phase 6: User Story 3 - Publicar alojamientos (Priority: P2)

**Goal**: Publicar alojamientos con la ficha de hospedaje (tipo, barrio, galería, amenidades, opiniones).

**Independent Test**: Publicar un alojamiento `active` con galería y dos opiniones; aparece en `lodgings` y no en `offers`; `reviewCount = 2`; reordenar galería; rechazo de galería fuera de lodging.

### Implementation for User Story 3

- [X] T030 [US3] Completar validación `placement = lodging` en `save_public_listing` / `publish_public_listing` (tipo, barrio bilingüe, habitaciones/baños, amenidades, galería con portada) en `supabase/migrations/024_public_listing_rpcs.sql`
- [X] T031 [US3] Implementar RPCs `reorder_public_gallery` y `save_guest_review` en `supabase/migrations/024_public_listing_rpcs.sql`
- [X] T032 [US3] Extender `PublicListingService` con `reorderGallery` y `saveGuestReview` en `src/app/core/catalog/services/public-listing.service.ts`
- [X] T033 [US3] Añadir UI de ficha lodging (campos hospedaje, galería, opiniones) en `src/app/features/catalog/products/product-detail/product-detail.component.ts` para productos `accommodation`
- [X] T034 [US3] Completar proyección `lodgings` (gallery, amenities, reviews, `reviewCount`) en `supabase/migrations/025_public_site_read.sql`

**Checkpoint**: US3 independiente; alojamientos no contaminan ofertas ni yates

---

## Phase 7: User Story 4 - Categorías y visibilidad pública (Priority: P2)

**Goal**: Categorías públicas adicionales, destacada, despublicar, agotado, solo lectura de agente y aislamiento entre agencias.

**Independent Test**: Crear categoría nueva; destacar/despublicar; marcar agotado (`soldOut` + `acceptsRequests: false`); agente no publica; otra org no ve la ficha; historial de auditoría consultable.

### Implementation for User Story 4

- [X] T035 [US4] Implementar RPCs `unpublish_public_listing`, `set_public_listing_sold_out` y `save_public_category` (`CATEGORY_IN_USE`, categorías protegidas no eliminables) en `supabase/migrations/024_public_listing_rpcs.sql`
- [X] T036 [US4] Extender `PublicListingService` con `unpublish`, `setSoldOut` y CRUD de categorías públicas en `src/app/core/catalog/services/public-listing.service.ts`
- [X] T037 [P] [US4] Implementar listado/alta/desactivación de categorías públicas en `src/app/features/catalog/public-categories/public-categories.component.ts` y cablear ruta en `src/app/app.routes.ts`
- [X] T038 [US4] Añadir controles Destacada / Despublicar / Agotado y vista de solo lectura para `agent` en `src/app/features/catalog/products/product-detail/product-detail.component.ts`
- [X] T039 [US4] Incluir `soldOut` y `acceptsRequests` en la proyección de `get_public_site` en `supabase/migrations/025_public_site_read.sql`
- [X] T040 [P] [US4] Escribir `supabase/tests/public_listing_rls_test.sql` (anon sin borradores/tarifas; cross-tenant vacío; agent `FORBIDDEN` al publicar)
- [X] T041 [P] [US4] Escribir `supabase/tests/public_sold_out_test.sql` (visible, sin solicitudes, sin cambio de tarifa ni de `products.status`)

**Checkpoint**: Visibilidad y RBAC públicos cerrados

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentación del módulo, validación quickstart y consistencia del contrato

- [X] T042 [P] Actualizar `docs/modules/catalog-pricing.md` con fichas públicas, Storage, `get_public_site` y cutover
- [X] T043 [P] Actualizar `.specify/feature.json` si hace falta y confirmar que `AGENTS.md` / contexto Spec Kit apuntan a `specs/009-catalog-site-cms/plan.md` tras el siguiente agent-context update
- [X] T044 Ejecutar `./supabase/tests/run-sql-tests.sh` y recorrer los escenarios 1–9 de `specs/009-catalog-site-cms/quickstart.md` en el panel local
- [X] T045 [P] Documentar el escenario 10 del consumidor (página externa + `source` legacy/panel) en `specs/009-catalog-site-cms/quickstart.md` si faltan pasos operativos concretos (URL RPC, org id de CTT)
- [X] T046 Revisar que la proyección Offer/Lodging/Yacht en `supabase/migrations/025_public_site_read.sql` coincida con los nombres de campo de `specs/009-catalog-site-cms/contracts/api-contracts.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Sin dependencias
- **Foundational (Phase 2)**: Depende de Setup — **bloquea** todas las historias
- **US1 (Phase 3)**: Después de Foundational — MVP
- **US2 (Phase 4)**: Después de Foundational; se integra en la misma UI de detalle que US1
- **US5 (Phase 5)**: Después de US1 (publicar oferta) y US2 (portada); idealmente tras poder publicar lodging mínimamente, pero la semilla SQL puede crear lodging/yacht sin UI completa — la UI lodging completa es US3
- **US3 (Phase 6)**: Después de Foundational + US2 (galería/portada)
- **US4 (Phase 7)**: Después de Foundational; se beneficia de US1 para tener fichas publicables
- **Polish (Phase 8)**: Después de las historias deseadas

### User Story Dependencies

- **US1 (P1)**: Tras Foundational — sin dependencia de otras historias
- **US2 (P1)**: Tras Foundational — amplía la ficha de US1; testeable con una ficha draft
- **US5 (P1)**: Depende de publicar + imagen; la semilla SQL cubre lodging/yacht del manifiesto
- **US3 (P2)**: Tras Foundational + capacidad de imagen (US2)
- **US4 (P2)**: Tras Foundational; categorías y agotado/despublicar sobre fichas existentes

### Within Each User Story

- RPCs antes que servicio Angular
- Servicio antes que UI
- SQL tests de la historia al cerrar la fase (o en paralelo [P] cuando el archivo es independiente)

### Parallel Opportunities

- T002 || T003 en Setup
- T011 en paralelo una vez definidos los enums/tablas (tras T006)
- T018 en paralelo al cerrar RPCs US1
- T027 || T028 en US5
- T037 || T040 || T041 en US4
- T042 || T043 || T045 en Polish
- Con equipo: tras Foundational, un dev en US1→US2 y otro preparando seed/cutover (US5) en migraciones distintas con cuidado de merge en `024`/`025`

---

## Parallel Example: User Story 1

```bash
# Tras T015 (RPCs save/publish listas):
Task: "Extender PublicListingService save/publish en src/app/core/catalog/services/public-listing.service.ts"
Task: "Escribir supabase/tests/public_listing_rules_test.sql"
# Luego UI en product-detail (comparte archivo: no paralelizar T017 con otro edit del mismo componente)
```

---

## Parallel Example: User Story 4

```bash
Task: "Implementar public-categories.component.ts"
Task: "Escribir public_listing_rls_test.sql"
Task: "Escribir public_sold_out_test.sql"
```

---

## Implementation Strategy

### MVP First (User Story 1 + imagen mínima)

1. Phase 1 Setup
2. Phase 2 Foundational
3. Phase 3 US1 (publicar oferta)
4. Phase 4 US2 (portada) — necesario para publicar de verdad
5. **STOP**: Validar quickstart escenarios 1–4 en panel
6. Demo: operador publica una experiencia activa y ve errores de validación claros

### Incremental Delivery

1. Setup + Foundational
2. US1 + US2 → MVP de oferta publicada con imagen
3. US5 → cutover y semilla de la página real
4. US3 → hospedaje completo
5. US4 → categorías, agotado, RBAC fino
6. Polish → docs + quickstart completo

### Parallel Team Strategy

1. Equipo cierra Setup + Foundational junto
2. Dev A: US1 → US2 → UI lodging (US3)
3. Dev B: seed + cutover RPCs/UI (US5) + categorías/agotado (US4)
4. Integrar en `product-detail` con PRs pequeños por sección de placement

---

## Notes

- Migraciones nuevas empiezan en `022` (002 terminó en `021`)
- No abrir `products` ni `pricing_schemes` a `anon`
- Editar precio de vitrina **nunca** llama a `upsert_pricing_scheme` salvo la semilla inicial de cutover
- Yates = `experience` + `placement = yacht`; no crear `product_type` nuevo
- La página externa no se reescribe en este repo; solo el contrato `get_public_site`
- Evitar editar el mismo `product-detail.component.ts` en paralelo sin coordinación
