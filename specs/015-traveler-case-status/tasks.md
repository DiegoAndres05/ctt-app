# Tasks: Etapa del caso para el viajero

**Input**: `specs/015-traveler-case-status/spec.md`. Expedientes de 003–006. Enlaces secretos actuales: `/q/:token` y `/r/:token`, que esta pantalla no revela.

**Prerequisites**: spec.md. La última migración del repo es `055_analytics_rpcs.sql`. Esta feature empieza en `056`.

**Tests**: SQL del RPC y Vitest del formulario. La consulta no escribe expediente.

**Organization**: Tareas por historia.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Paralelo posible
- **[Story]**: US1, US2, US3

## Design baseline

- RPC `get_traveler_case_status(p_organization_id uuid, p_reference text, p_contact text)` `SECURITY DEFINER`, `search_path = ''`, ejecutable por `anon` y `authenticated`.
- `p_organization_id` solo se acepta si el llamador es anónimo. Si hay JWT, se usa la organización del JWT y se ignora el argumento, igual que `get_public_site`.
- Normalizar correo y teléfono con las funciones ya existentes de 003 (`normalize_email`, `normalize_phone_e164`). Un contacto que no normaliza devuelve el mismo JSON de «no encontrado», no un error distinto.
- Buscar la solicitud por referencia de la organización (`SOL-#####` y el formato que ya emite 003). El contacto debe coincidir con el correo o el teléfono del cliente vinculado, y el cliente no puede estar anonimizado.
- Etapa más avanzada, en este orden: reserva (`completed`, `in_progress`, `confirmed`, `cancelled`) por encima de cotización emitida o aceptada, por encima de pre-reserva no cancelada, por encima de la solicitud (`received`, `in_review`, `discarded`). `superseded` de reserva no se muestra: se sigue a la reserva vigente si existe.
- JSON de éxito: `found: true`, `stage` (uno de `request_received`, `request_in_review`, `request_closed`, `checking_availability`, `proposal_ready`, `reservation_confirmed`, `trip_in_progress`, `trip_completed`, `reservation_cancelled`), `reference`, `travel_start`, `travel_end`, `offer_name`. Nada más.
- JSON neutro: `found: false`. Mismo cuerpo si no hay referencia, si el contacto no coincide o si el cliente fue anonimizado.
- No incluir precio, notas, motivo de descarte, token, proveedor, documentos ni teléfono.
- Límite: 8 intentos por hora y por contacto normalizado, y 30 por hora y por organización, contados también los `found: false`. Al pasar el límite, error `RATE_LIMITED` (el único error distinguible, porque si no se podría usar el límite para saber que el caso existe). Documentar esta excepción en el test.
- `GRANT EXECUTE` a `anon` y `authenticated`. `REVOKE ALL` de `PUBLIC`.
- Auditoría: un evento con la referencia y `found` booleano. Sin correo, teléfono ni nombre en `metadata`.

---

## Phase 1: Setup

- [ ] T001 Crear `supabase/tests/traveler_case_status_test.sql` y `src/app/features/public-case/`
- [ ] T002 Reservar la migración `supabase/migrations/056_traveler_case_status.sql` sin editar `049`–`055`

---

## Phase 2: Foundational

**Purpose**: El RPC es la única puerta. Bloquea las tres historias.

- [ ] T003 En `056_traveler_case_status.sql`, crear `get_traveler_case_status` con la firma, `search_path`, grants y la respuesta `found: false` por defecto
- [ ] T004 Resolver la solicitud de la organización por referencia y exigir contacto normalizado igual al del cliente no anonimizado
- [ ] T005 Calcular `stage` con el orden de la línea base y devolver solo los campos permitidos
- [ ] T006 Contar intentos y lanzar `RATE_LIMITED` al superar 8 por contacto u hora, o 30 por organización u hora
- [ ] T007 [P] Escribir `supabase/tests/traveler_case_status_test.sql`: contacto correcto en solicitud recibida; correo ajeno y referencia inventada devuelven el mismo JSON; anonimizado devuelve `found: false`; descarte no incluye el motivo; cotización no incluye precio ni token; reserva confirmada no incluye documento; el RPC no cambia estados

**Checkpoint**: La suite SQL cubre FR-005, FR-007 y FR-008 antes de haber pantalla.

---

## Phase 3: User Story 1 - Consultar con la referencia (Priority: P1)

**Goal**: El viajero ve la etapa de una solicitud.

**Independent Test**: Referencia más correo de una solicitud recibida muestra «Solicitud recibida», fechas y nombre de la oferta.

- [ ] T008 [US1] `TravelerCaseService` en `src/app/core/requests/traveler-case.service.ts` llama al RPC con `environment.publicOrganizationId` y el contacto tal como lo escribió el viajero
- [ ] T009 [US1] `src/app/features/public-case/case-status.component.ts`: campos referencia, correo o teléfono, y resultado con etapa, fechas y nombre de la oferta
- [ ] T010 [US1] Ruta pública `mi-solicitud` en `src/app/app.routes.ts` y enlace «Consultar mi solicitud» en la cabecera del shell público y en la pantalla de éxito de 012

**Checkpoint**: FR-001 y el camino de solicitud de FR-002.

---

## Phase 4: User Story 2 - El nombre de la etapa (Priority: P1)

**Goal**: Nueve etapas, y la solicitud no se llama reserva.

**Independent Test**: El mapa de etiquetas cubre los nueve `stage`. `request_received` no contiene «confirmada».

- [ ] T011 [US2] Mapa de copy en `src/app/features/public-case/case-stage.copy.ts`. Textos: «Solicitud recibida», «La estamos revisando», «Esta solicitud no continuó», «Estamos comprobando disponibilidad; aún no está confirmado», «Hay una propuesta. Ábrela con el enlace que te enviamos», «Reserva confirmada. El comprobante está en el enlace que te enviamos», «Viaje en curso», «Viaje completado», «Reserva cancelada»
- [ ] T012 [P] [US2] Test en `case-stage.copy.spec.ts`: las nueve claves tienen frase; las tres primeras no contienen «reserva confirmada»; ninguna frase contiene un precio ni la palabra «token»
- [ ] T013 [US2] La pantalla de propuesta y de reserva no pinta botones de aceptar, pagar ni cancelar, ni un campo de precio

**Checkpoint**: FR-002, FR-003 y FR-004.

---

## Phase 5: User Story 3 - El mismo silencio (Priority: P1)

**Goal**: Quien no es el contacto no aprende nada, salvo el límite de intentos.

**Independent Test**: Dos consultas fallidas muestran el mismo texto. La novena en una hora muestra espera.

- [ ] T014 [US3] Si `found` es falso, mostrar «No hay un caso con esos datos» sin decir si falló la referencia o el contacto
- [ ] T015 [US3] Si el error es `RATE_LIMITED`, mostrar «Espera un momento antes de consultar de nuevo» y no conservar en pantalla un resultado anterior
- [ ] T016 [P] [US3] Test de componente: `found: false` y un error genérico de red no muestran fechas ni nombres; `RATE_LIMITED` tampoco

**Checkpoint**: FR-005 y FR-006.

---

## Phase 6: Polish

- [ ] T017 Documentar el RPC, los nueve `stage` y lo que no devuelve en `docs/modules/customer-requests.md`
- [ ] T018 Revisión: `rg -n "service_role|SERVICE_ROLE" src/app/features/public-case src/app/core/requests/traveler-case.service.ts` vacío; la migración tiene `search_path = ''` y no mete correo ni teléfono en `audit.log_event`

---

## Dependencies

- Phase 2 antes de la UI
- US1 antes de US2 y US3
- El enlace desde el éxito de 012 (T010) espera que 012 T007 exista; si 012 no está, el enlace de la cabecera basta para probar

## Parallel example

```text
T007 SQL
T011 copy
```

cuando T005 ya definió los nombres de `stage`.

## Implementation strategy

1. RPC y tests SQL
2. Pantalla de la solicitud
3. Las nueve frases
4. Silencio y límite

## Notes

- No devolver el token de `/q/` ni de `/r/`
- No commitear salvo que se pida
- Marcar `[x]` al completar
- Copy en español
