# Tasks: Portal público del catálogo

**Input**: `specs/011-public-catalog-browse/spec.md`. Diseño de apoyo: `docs/modules/catalog-pricing.md` (RPC `get_public_site`) y `src/app/core/catalog/models/public-listing.model.ts`.

**Prerequisites**: spec.md. No hace falta plan.md nuevo: la proyección pública ya existe en 009.

**Tests**: Vitest del mapeo de proyección y de las reglas de vacío. No hay migración nueva.

**Organization**: Tareas por historia de usuario.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede ir en paralelo (archivos distintos, sin dependencia)
- **[Story]**: US1, US2, US3
- Rutas relativas al repositorio

## Path Conventions

Angular: `src/app/features/public-catalog/`, `src/app/core/catalog/`, `src/app/app.routes.ts`

## Design baseline

- El visitante usa la clave anónima. No entra al shell de `AdminShellComponent`.
- La organización pública sale de `environment.publicOrganizationId`. Una sola agencia.
- Leer con `get_public_site`. No consultar `public_listings` desde el navegador anónimo.
- `source = legacy` es el aviso de preparación (FR-007). `offers`, `lodgings` y `yachts` son los tres grupos.
- Tipar la proyección que hoy está como `unknown[]` en `PublicSiteProjection`, sin cambiar el JSON que ya devuelve 009.
- Textos de interfaz en español. El contenido de la ficha sigue el idioma elegido (es/en), guardado en `localStorage` como `ctt.public.locale`.
- El botón de US3 navega a `/solicitar/:slug`. La pantalla de esa ruta la construye 012; hasta entonces la ruta puede existir como destino. No implementar el formulario aquí.
- No editar migraciones 022–027.

---

## Phase 1: Setup

**Purpose**: Sitio público separado del panel

- [ ] T001 Añadir `publicOrganizationId: ''` en `src/environments/environment.ts`, `environment.development.ts` y `environment.docker.ts`
- [ ] T002 Crear `src/app/features/public-catalog/` con el shell público (cabecera, idioma, enlace al catálogo, sin menú de operador)

---

## Phase 2: Foundational

**Purpose**: Tipos y lectura anónima. Bloquea las tres historias.

- [ ] T003 Tipar ofertas, alojamientos y yates de `get_public_site` en `src/app/core/catalog/models/public-site-projection.ts` con los campos que ya arma `supabase/migrations/025_public_site_read.sql`: `id` (slug), `name`/`nameEn`, `description`/`descriptionEn`, `image`, `includes`/`includesEn`, `warnings`/`warningsEn`, `price` o `pricePerNight`, `soldOut`, `acceptsRequests`, más galería, amenities y líneas de yate cuando existan
- [ ] T004 [P] Cubrir ese mapeo en `src/app/core/catalog/models/public-site-projection.spec.ts`: legacy sin fichas, panel con una oferta, agotado visible, borrador ausente del JSON
- [ ] T005 Añadir `getPublicCatalog()` en `src/app/core/catalog/services/public-catalog.service.ts` que llame a `get_public_site` con `environment.publicOrganizationId` y devuelva la proyección tipada. No usar el cliente con sesión de operador para decidir qué se lista

**Checkpoint**: Un test puede pedir el catálogo y distinguir `legacy` de `panel`.

---

## Phase 3: User Story 1 - Recorrer el catálogo (Priority: P1)

**Goal**: Tres grupos, solo lo publicado, agotado visible, legacy en preparación.

**Independent Test**: Con la vitrina en `panel`, el catálogo muestra tarjetas. Con `legacy`, solo el aviso.

- [ ] T006 [US1] Implementar `src/app/features/public-catalog/catalog-home.component.ts` con secciones Experiencias, Alojamientos y Yates, tarjeta (foto, nombre, resumen, precio de vitrina) y vacío por sección
- [ ] T007 [US1] En esa misma pantalla, si `source` es `legacy`, mostrar «Estamos preparando el catálogo» y ninguna tarjeta
- [ ] T008 [US1] Marcar la tarjeta agotada con el texto «Agotado» sin ocultarla
- [ ] T009 [US1] Registrar `catalogo` en las rutas públicas de `src/app/app.routes.ts`, fuera de `authGuard` y fuera del shell admin

**Checkpoint**: `/catalogo` cumple FR-002, FR-003, FR-006 y FR-007.

---

## Phase 4: User Story 2 - Ficha e idioma (Priority: P1)

**Goal**: Detalle bilingüe y dirección desconocida.

**Independent Test**: `/catalogo/experiencias/:slug` cambia de idioma y un slug ausente muestra «no encontrada».

- [ ] T010 [US2] Guardar el idioma en `src/app/features/public-catalog/public-locale.ts` (`es` | `en`, clave `ctt.public.locale`) y usarlo en la cabecera
- [ ] T011 [P] [US2] Tests de `public-locale.ts`: valor inicial español, cambio a inglés, valor inválido vuelve a español
- [ ] T012 [US2] Implementar `src/app/features/public-catalog/catalog-detail.component.ts`: galería, descripción, inclusiones, advertencias, datos de alojamiento o yate, precio de vitrina, todo en el idioma activo
- [ ] T013 [US2] Si el slug no está en la proyección, mostrar no encontrado y un enlace a `/catalogo`. No distinguir borrador de inexistente
- [ ] T014 [US2] Rutas `catalogo/experiencias/:slug`, `catalogo/hospedaje/:slug` y `catalogo/yates/:slug` en `src/app/app.routes.ts`

**Checkpoint**: FR-004 y FR-005 quedan cubiertos en la ficha.

---

## Phase 5: User Story 3 - Llamado a solicitar (Priority: P2)

**Goal**: El botón no dice que la reserva quedó hecha.

**Independent Test**: El botón de una ficha con `acceptsRequests` navega a `/solicitar/:slug`. Una ficha agotada no muestra el botón.

- [ ] T015 [US3] Añadir el llamado en `catalog-detail.component.ts` solo cuando `acceptsRequests` es verdadero. Copy: «Solicitar información». Si `soldOut` es verdadero, no hay botón y el texto es «Esta oferta no admite solicitudes ahora.»
- [ ] T016 [US3] El enlace apunta a `/solicitar/:slug` con el slug de la ficha. No crear el formulario en esta iteración

**Checkpoint**: FR-008. FR-009 se cumple porque la proyección de 009 no trae costos ni clientes; no añadir campos.

---

## Phase 6: Polish

- [ ] T017 [P] Documentar las rutas públicas y `publicOrganizationId` en `docs/modules/catalog-pricing.md`, sección breve «Sitio del viajero (011)»
- [ ] T018 Revisar que `rg -n "service_role|SERVICE_ROLE" src/app/features/public-catalog` no devuelva nada

---

## Dependencies

- Phase 2 antes de US1, US2 y US3
- US2 después de US1 (la ficha se abre desde el listado; la ruta puede probarse sola con un slug)
- US3 después de US2
- 012 implementa `/solicitar/:slug`

## Parallel example

```text
T003 tipos de proyección
T001 environment
```

Después T005, luego T006–T009, luego T010–T014.

## Implementation strategy

1. Phase 1–2
2. US1 listado
3. US2 ficha e idioma
4. US3 llamado, sin formulario
5. Nota en el módulo

## Notes

- No reabrir el editor de 009 ni el cutover
- No commitear salvo que se pida
- Marcar `[x]` en este archivo al completar cada tarea
- Copy en español
