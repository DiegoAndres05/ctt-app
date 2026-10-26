# Tasks: Solicitud pública desde la ficha

**Input**: `specs/012-public-trip-request/spec.md`. Contrato existente: `docs/modules/customer-requests.md` sección «Public web contract». Códigos ya traducidos en `src/app/core/error/error-handler.ts`.

**Prerequisites**: spec.md y la ruta `/catalogo` de 011. El RPC `submit_public_request` ya está en `supabase/migrations/031_us1_public_request_intake.sql`.

**Tests**: Vitest del armado del payload y del copy de éxito. No hay migración nueva. Los casos SQL de 003 no se reescriben.

**Organization**: Tareas por historia.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Paralelo posible
- **[Story]**: US1, US2, US3

## Path Conventions

`src/app/features/public-request/`, `src/app/core/requests/`

## Design baseline

- Llamar `submit_public_request` con la clave anónima y `environment.publicOrganizationId`.
- Payload como en `docs/modules/customer-requests.md`: `privacy_consent`, `idempotency_key` (un UUID por montaje de la pantalla), `contact`, `items: [{ public_slug, quantity: 1 }]`, fechas, `adults`, `children`, `interest_text`, `locale`, `source_page`, honeypot `website: ''`.
- Generar `idempotency_key` una vez al crear el componente y reutilizarlo en el reintento.
- Éxito: «Solicitud recibida» + referencia. Prohibido «Reserva enviada» y «Reserva confirmada».
- Si `deduplicated` viene verdadero, mostrar la misma referencia y la misma frase.
- Códigos: `CONSENT_REQUIRED`, `CONTACT_REQUIRED`, `INVALID_EMAIL`, `INVALID_PHONE`, `TRAVEL_DATE_IN_PAST`, `INVALID_DATE_RANGE`, `LISTING_NOT_AVAILABLE`, `RATE_LIMITED`, `VALIDATION_ERROR`.
- No crear pre-reserva ni escribir tablas de clientes desde el cliente.

---

## Phase 1: Setup

- [ ] T001 Crear `src/app/features/public-request/` y `src/app/core/requests/public-request.payload.ts`

---

## Phase 2: Foundational

- [ ] T002 Implementar `buildPublicRequestPayload` en `src/app/core/requests/public-request.payload.ts` con los campos del contrato de 003, honeypot vacío y `quantity: 1`
- [ ] T003 [P] Tests en `src/app/core/requests/public-request.payload.spec.ts`: sin consentimiento el builder lo deja en falso para que la pantalla bloquee el envío; fechas invertidas no se envían; el UUID de idempotencia se conserva entre dos armados de la misma visita
- [ ] T004 Implementar `submitPublicRequest` en `src/app/core/requests/public-request.service.ts`. Devuelve `{ reference, deduplicated }`. Traduce los códigos con `toAppError`

**Checkpoint**: El servicio puede llamarse desde un test con el cliente suplantado.

---

## Phase 3: User Story 1 - Enviar la solicitud (Priority: P1)

**Goal**: Formulario con la ficha preseleccionada y referencia visible.

**Independent Test**: Enviar desde `/solicitar/:slug` crea la solicitud web y muestra `SOL-#####`.

- [ ] T005 [US1] `src/app/features/public-request/request-form.component.ts`: resumen de solo lectura de la ficha (nombre según `ctt.public.locale`), campos de contacto, fechas, adultos, niños, nota y casilla de consentimiento
- [ ] T006 [US1] Impedir el envío si falta consentimiento, si adultos es menor que 1, si el fin es anterior al inicio o si la fecha es pasada. Mostrar el mensaje junto al campo
- [ ] T007 [US1] Al éxito, sustituir el formulario por la referencia y la frase «Recibimos tu solicitud. La agencia la va a revisar y te contactará. Todavía no tienes una reserva.»
- [ ] T008 [US1] Ruta pública `solicitar/:slug` en `src/app/app.routes.ts`, enlazada desde el botón de `catalog-detail.component.ts` (011 T015). Si el slug no está en `get_public_site`, mostrar no encontrada y no llamar al RPC

**Checkpoint**: FR-001 a FR-004 y FR-006 en el camino feliz.

---

## Phase 4: User Story 2 - Un solo caso (Priority: P1)

**Goal**: Reintento con la misma clave no duplica y el copy no habla de reserva.

**Independent Test**: Dos submits en la misma visita muestran una sola referencia. El texto no contiene «reserva confirmada».

- [ ] T009 [US2] Deshabilitar el botón mientras la llamada está en curso y, si `deduplicated` es verdadero, reutilizar la pantalla de éxito de T007 sin un segundo mensaje de error
- [ ] T010 [P] [US2] Test de componente o de plantilla en `src/app/features/public-request/request-success.spec.ts`: la frase de éxito incluye la referencia y no incluye «reserva confirmada» ni «reserva enviada»

**Checkpoint**: FR-005 y FR-006.

---

## Phase 5: User Story 3 - Ficha no disponible y límite (Priority: P2)

**Goal**: Fallos honestos, sin caso fantasma.

**Independent Test**: `LISTING_NOT_AVAILABLE` y `RATE_LIMITED` muestran su texto y el formulario no dice que la solicitud entró.

- [ ] T011 [US3] Mapear `LISTING_NOT_AVAILABLE` a «Esta oferta ya no admite solicitudes» con enlace a `/catalogo`
- [ ] T012 [US3] Mapear `RATE_LIMITED` a «Espera un momento antes de enviar otra solicitud» sin mostrar la referencia de otra persona
- [ ] T013 [US3] Dejar el honeypot `website` fuera de la vista. Si por algún motivo trae texto, no llamar al RPC y mostrar el mismo vacío que un envío no aceptado, sin explicar la trampa

**Checkpoint**: FR-007 y FR-008. FR-009 se cumple porque el único RPC es `submit_public_request`.

---

## Phase 6: Polish

- [ ] T014 Documentar la ruta `/solicitar/:slug` en `docs/modules/customer-requests.md`, bajo «Public web contract», como la pantalla que ya usa ese RPC
- [ ] T015 Confirmar que el formulario no importa servicios de cotización, pre-reserva ni reserva

---

## Dependencies

- 011 T005 y T014 (catálogo y ruta de ficha) antes de T008
- Phase 2 antes de US1
- US2 y US3 después de US1

## Parallel example

```text
T002 payload
T010 test de copy, cuando exista el texto de T007
```

## Implementation strategy

1. Payload y servicio
2. Formulario feliz
3. Deduplicación y copy
4. Ficha caída y límite

## Notes

- No modificar `031_us1_public_request_intake.sql`
- No commitear salvo que se pida
- Marcar `[x]` al completar
- Copy en español
