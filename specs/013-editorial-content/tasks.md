# Tasks: Contenido editorial del sitio público

**Input**: `specs/013-editorial-content/spec.md`

**Prerequisites**: spec.md. El shell público de 011. WordPress es solo lectura.

**Tests**: Vitest del mapeo de entradas publicadas y del fallo del gestor. No hay migración de negocio.

**Organization**: Tareas por historia.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Paralelo posible
- **[Story]**: US1, US2, US3

## Path Conventions

`src/app/features/public-editorial/`, `src/app/core/editorial/`

## Design baseline

- Leer WordPress por su REST público: `environment.wordpressBaseUrl` + `/wp-json/wp/v2/`.
- Cuatro tipos = cuatro categorías o tipos de contenido con slug fijo: `articulos`, `guias`, `destinos`, `politicas`. Documentar el slug esperado. Si el sitio de WordPress usa otros slugs, se configuran en environment (`wordpressSections`), no se hardcodean en el componente.
- Pedir solo `status=publish`. No enviar usuario ni contraseña de WordPress. No usar la service role.
- Una entrada se muestra con título, extracto, contenido ya saneado como HTML del CMS, imagen destacada si `_embed` la trae, y fecha.
- El panel Angular no escribe en WordPress ni en tablas de catálogo, clientes o reservas desde estas pantallas.
- Textos de interfaz en español. El cuerpo es el que marketing publicó.

---

## Phase 1: Setup

- [ ] T001 Añadir `wordpressBaseUrl: ''` y `wordpressSections` (`articulos`, `guias`, `destinos`, `politicas`) en `src/environments/environment.ts`, `environment.development.ts` y `environment.docker.ts`
- [ ] T002 Crear `src/app/core/editorial/` y `src/app/features/public-editorial/`

---

## Phase 2: Foundational

- [ ] T003 Definir `EditorialEntry` (tipo, slug, título, resumen, html, imagen, fecha) en `src/app/core/editorial/editorial.model.ts`
- [ ] T004 Implementar `EditorialService.list(tipo)` y `EditorialService.bySlug(tipo, slug)` en `src/app/core/editorial/editorial.service.ts`. Solo entradas publicadas. Sin credenciales
- [ ] T005 [P] Tests en `src/app/core/editorial/editorial.service.spec.ts` con respuestas falsas: un publish se mapea; un borrador en el JSON se descarta; falta de imagen no anula el título

**Checkpoint**: El servicio devuelve listas por tipo sin tocar Supabase.

---

## Phase 3: User Story 1 - Leer una publicación (Priority: P1)

**Goal**: Blog con detalle de un artículo publicado.

**Independent Test**: `/blog` lista un publish y `/blog/:slug` muestra título, texto, imagen y fecha. Un slug no publicado da no encontrado.

- [ ] T006 [US1] `src/app/features/public-editorial/editorial-list.component.ts` para artículos: título, resumen, imagen, fecha
- [ ] T007 [US1] `src/app/features/public-editorial/editorial-detail.component.ts` con el texto y la imagen. Sin imagen, el texto igual se lee
- [ ] T008 [US1] Rutas públicas `blog` y `blog/:slug` en `src/app/app.routes.ts`, dentro del shell de 011, sin `authGuard`
- [ ] T009 [US1] Slug desconocido o no publicado: «No encontramos esta página» y enlace a `/blog`

**Checkpoint**: FR-003 y FR-004 para artículos.

---

## Phase 4: User Story 2 - Cuatro secciones (Priority: P1)

**Goal**: Guías, destinos y políticas no se mezclan con el blog.

**Independent Test**: Cada ruta lista solo su tipo. Destino no muestra precio ni cupo.

- [ ] T010 [US2] Reutilizar el listado y el detalle con el tipo de sección para `guias`, `destinos` y `politicas` en `src/app/app.routes.ts`
- [ ] T011 [US2] Enlaces en la cabecera pública de 011: Blog, Guías, Destinos, Políticas, Catálogo
- [ ] T012 [US2] En el detalle de destino, un enlace «Ver experiencias» hacia `/catalogo`. No renderizar precio, cupo ni formulario de reserva dentro del HTML como dato de negocio: el HTML se muestra como contenido, y la pantalla no llama RPCs comerciales

**Checkpoint**: FR-001, FR-002, FR-005 y FR-008 (ocultar es dejar de publicar en WordPress; no hay botón en el panel).

---

## Phase 5: User Story 3 - El gestor caído (Priority: P2)

**Goal**: Catálogo y solicitud siguen. El blog avisa.

**Independent Test**: Si `EditorialService` falla, `/catalogo` y `/solicitar/:slug` cargan. `/blog` muestra el aviso.

- [ ] T013 [US3] En el listado y el detalle, un fallo de red muestra «El contenido no está disponible ahora» y un enlace a `/catalogo`. No redirigir toda la app a una página de error
- [ ] T014 [US3] Test en `editorial.service.spec.ts` o del componente: un rechazo del lector no lanza hacia el catálogo una excepción no capturada. El catálogo no importa `EditorialService`

**Checkpoint**: FR-006 y FR-007.

---

## Phase 6: Polish

- [ ] T015 [P] Añadir en `docs/modules/catalog-pricing.md` un párrafo «Contenido editorial (013)»: el sitio lee WordPress en solo lectura y WordPress no guarda clientes, tarifas ni reservas
- [ ] T016 Revisar que `src/app/features/public-editorial` no importa servicios de productos, precios, solicitudes ni reservas, y que no aparece `service_role`

---

## Dependencies

- Shell público de 011 antes de T008 y T011
- Phase 2 antes de las historias
- US2 después de US1 (reutiliza los componentes)
- US3 después de US1

## Parallel example

```text
T003 modelo
T001 environment
```

## Implementation strategy

1. Lector de publicados
2. Blog
3. Las otras tres secciones
4. Fallo aislado

## Notes

- No crear tablas ni migraciones
- No commitear salvo que se pida
- Marcar `[x]` al completar
- Copy de interfaz en español
