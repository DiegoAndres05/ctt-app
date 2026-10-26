# Tasks: Frescura de lo que ve el viajero

**Input**: `specs/014-public-freshness/spec.md`

**Prerequisites**: spec.md, catálogo 011, solicitud 012 y editorial 013.

**Tests**: Vitest del reloj de la copia en memoria. No hay migración. No se cachea la bandeja ni las cotizaciones.

**Organization**: Tareas por historia.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Paralelo posible
- **[Story]**: US1, US2, US3

## Design baseline

- Copia en memoria del navegador, como máximo 60 segundos, para la proyección de `get_public_site` y para las listas editoriales. Sesenta segundos cumple la ventana de cinco minutos y deja la segunda apertura por debajo de un segundo.
- La copia no se escribe en `localStorage` ni en una tabla. Al cerrar la pestaña desaparece.
- La clave de catálogo incluye `publicOrganizationId`. La clave editorial incluye tipo, slug e idioma de interfaz si aplica.
- `submit_public_request`, `get_public_quotation` y el comprobante público no leen esa copia para decidir precio, cupo o estado.
- Si WordPress falla y hay una copia de menos de 60 segundos, se puede mostrar con el aviso «Puede no estar al día». Si no hay copia, se usa el aviso de 013.
- No añadir TTL en Postgres ni un worker de invalidación: la visita nueva después de 60 segundos vuelve a leer la fuente.

---

## Phase 1: Setup

- [ ] T001 Crear `src/app/core/public/fresh-read.ts` con un almacén en memoria genérico: `read(key, maxAgeMs, loader)`

---

## Phase 2: Foundational

- [ ] T002 Implementar el almacén: si la entrada existe y no superó `maxAgeMs`, devolverla; si no, ejecutar `loader`, guardar instante y valor, y devolver el valor. Un `loader` que falle no debe dejar guardado un valor nuevo
- [ ] T003 [P] Tests en `src/app/core/public/fresh-read.spec.ts`: segunda lectura dentro del plazo no llama al loader; lectura pasados 60 segundos sí llama; un fallo conserva el valor viejo solo si el caller lo pide de forma explícita (método `readStale`) y lo marca `stale: true`; sin valor previo el fallo se propaga

**Checkpoint**: El reloj está probado sin UI.

---

## Phase 3: User Story 1 - Cambio de catálogo en cinco minutos (Priority: P1)

**Goal**: Publicar, despublicar, agotar o cambiar el precio de vitrina se ve en una visita nueva antes de cinco minutos.

**Independent Test**: Tras 60 segundos la siguiente llamada a `getPublicCatalog` vuelve a invocar `get_public_site`.

- [ ] T004 [US1] Hacer que `PublicCatalogService.getPublicCatalog` en `src/app/core/catalog/services/public-catalog.service.ts` pase por `fresh-read` con 60 segundos
- [ ] T005 [US1] Test del servicio: dos llamadas inmediatas producen una sola RPC; una llamada con el reloj avanzado 61 segundos produce una segunda RPC y el JSON nuevo (ficha nueva presente, ficha retirada ausente, `soldOut` actualizado)

**Checkpoint**: FR-001 y FR-002. El detalle usa el mismo almacén, así la dirección directa tampoco sirve una ficha ya fuera de la proyección.

---

## Phase 4: User Story 2 - Repetir sin esperar (Priority: P2)

**Goal**: La segunda apertura de la misma visita no vuelve a pedir la fuente.

**Independent Test**: Abrir ficha, volver al listado y abrir la misma ficha no dispara otra RPC dentro del minuto.

- [ ] T006 [US2] Pasar `EditorialService.list` y `bySlug` por el mismo almacén, clave `editorial:{tipo}:{slug|list}`, 60 segundos
- [ ] T007 [P] [US2] Test: la segunda lectura editorial no llama a WordPress dentro del plazo

**Checkpoint**: FR-003.

---

## Phase 5: User Story 3 - La copia no vende (Priority: P1)

**Goal**: Cotización, solicitud y comprobante ignoran la copia. El blog caído no bloquea el catálogo.

**Independent Test**: `submitPublicRequest` y la página `/q/:token` no importan `fresh-read`. Con WordPress caído y copia vigente, el blog muestra el aviso de desactualizado.

- [ ] T008 [US3] En el listado editorial, si el loader falla y `readStale` devuelve valor, mostrar el contenido y la frase «Puede no estar al día». Si no hay valor, mantener el aviso de 013
- [ ] T009 [US3] Test de que `src/app/core/requests/public-request.service.ts` y `src/app/features/public-quotation/` no referencian `fresh-read` ni `PublicCatalogService` para armar el precio
- [ ] T010 [US3] Dejar escrito en un comentario corto de `fresh-read.ts` que esta copia no es disponibilidad, precio final ni estado de reserva. La solicitud sigue yendo a `submit_public_request` aunque la ficha se haya leído de la copia

**Checkpoint**: FR-004, FR-005, FR-006 y FR-007.

---

## Phase 6: Polish

- [ ] T011 Anotar la ventana de 60 segundos y el límite de producto de 5 minutos en `docs/modules/catalog-pricing.md`, junto a la nota de 011
- [ ] T012 Revisar que ninguna pantalla de `/sales` ni `/reports` use `fresh-read`

---

## Dependencies

- 011, 012 y 013 antes de cablear servicios
- Phase 2 antes de las historias
- US2 puede ir en paralelo con US1 después de Phase 2
- US3 después de que el catálogo y el editorial usen el almacén

## Parallel example

```text
T005 test de catálogo
T007 test editorial
```

después de T002.

## Implementation strategy

1. Almacén con tests
2. Catálogo
3. Editorial
4. Avisos y la prohibición de usar la copia para vender

## Notes

- No cachear RPCs de escritura ni de bandeja
- No commitear salvo que se pida
- Marcar `[x]` al completar
