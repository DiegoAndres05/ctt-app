# Quickstart & Validation: 004-prereservation-availability

**Date**: 2026-10-04 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Guía para comprobar la feature de punta a punta. RPCs, payloads y códigos en [contracts/api-contracts.md](./contracts/api-contracts.md); entidades en [data-model.md](./data-model.md).

## Prerrequisitos

- Docker (suite SQL) y Supabase CLI (stack local con Realtime).
- Migraciones `001`–`041` y `supabase/seed.sql` aplicados. El seed deja la organización demo `00000000-0000-4000-a000-000000000001` con usuarios `admin@`, `operador@`, `agente@demo-turismo.test` (`DemoPass123!`), catálogo activo (experiencias, alojamientos con proveedor, paquetes, complementos), clientes y solicitudes demo (algunas en `received` y `in_review`), y pre-reservas demo en varios estados.
- Para el escenario 6: `psql` conectado a la base local para adelantar una retención.

## Setup

```bash
# Backend: migraciones + seed + todas las suites SQL en Postgres 17 desechable
./supabase/tests/run-sql-tests.sh

# Stack local (PostgREST, Realtime)
supabase start
supabase db reset                                   # aplica migraciones + seed

# Frontend
npm install
npm start                                           # http://127.0.0.1:4200
npm test && npm run lint && npm run format:check && npm run build
```

---

## Escenario 1 — Conversión de solicitud a pre-reserva (US1, FR-001, FR-003, FR-012)

1. Entrar como `agente@demo-turismo.test` → **Comercial → Solicitudes** → abrir una solicitud en `Recibida` con intereses de catálogo.
2. Pulsar **«Crear pre-reserva»**. El formulario se abre con los servicios precargados desde los intereses, fechas y pasajeros de la solicitud. Ajustar fechas (futuras) y guardar.

**Esperado**: se abre el detalle de la pre-reserva nueva con referencia `PRE-#####`, estado «Pendiente de verificación», el aviso «Esta pre-reserva no es una reserva confirmada…», todas las líneas en «Pendiente» y, para los productos con proveedor, el proveedor ya diligenciado. La solicitud queda en «En Pre-Reserva» y su sección «Pre-reservas» enlaza a la creada. Eventos `item_added` y auditoría `pre_reservation_created` + `request_status_changed`.

**Negativos**: sobre una solicitud `Descartada` la RPC devuelve `REQUEST_CLOSED`; con el cliente anonimizado, `CUSTOMER_ANONYMIZED`; sin líneas o con una fecha pasada, `VALIDATION_ERROR` / `TRAVEL_DATE_IN_PAST`. Crear una **segunda** pre-reserva desde la misma solicitud (ya «En Pre-Reserva») funciona y no altera la solicitud.

Automatizado en `supabase/tests/pre_reservation_core_test.sql`.

---

## Escenario 2 — Cola de verificación y resultado disponible (US2, FR-004, FR-005, SC-004)

1. Como `operador@demo-turismo.test`, menú **Comercial → Verificación**: la cola muestra las líneas que requieren acción ordenadas por fecha de servicio.
2. Filtrar por un proveedor (2.º clic) y pulsar **«Registrar resultado»** en una línea (3.º clic): Disponible, persona de contacto, medio WhatsApp, retención futura, notas. Guardar.

**Esperado**: la línea queda «Disponible» con la retención; la pre-reserva pasa a «Parcialmente verificada» o «Totalmente verificada» según el resto de líneas; el evento `outcome_recorded` y la auditoría `availability_recorded` quedan registrados con el operador. Los enlaces «Llamar / WhatsApp / Correo» abren `tel:`, `wa.me` y `mailto:` con los datos del proveedor.

**Roles**: como `agente@…` el menú no muestra «Verificación», la ruta `/sales/verification` redirige y las RPC `start_item_verification` / `record_item_verification` responden `INSUFFICIENT_PERMISSIONS`.

**Negativos**: sin persona de contacto → `CONTACT_PERSON_REQUIRED`; retención en el pasado → `HOLD_EXPIRY_IN_PAST`; «Alternativa sugerida» sin texto → `ALTERNATIVE_SUGGESTION_REQUIRED`.

Automatizado en `supabase/tests/availability_verification_test.sql`.

---

## Escenario 3 — Consolidación, alternativas y aviso al agente (US3, FR-006, FR-008, FR-010)

1. Con dos terminales/navegadores: agente en cualquier pantalla del panel; operador registrando resultados.
2. Operador marca «No disponible» una línea → la pre-reserva pasa a «Requiere ajuste».
3. Agente abre el detalle: agrega una línea **alternativa** a esa principal; operador la verifica como «Disponible»; agente la **promueve a principal** (la original queda retirada con el motivo automático).
4. Operador verifica la última línea pendiente.

**Esperado**: tras (2) el detalle muestra «No elegible para cotizar». Tras (4), la pre-reserva queda «Totalmente verificada», `verified_at` y `first_verified_at` fijados, la sección «Cotización» muestra «Lista para cotizar.» y **el agente ve el aviso global** «La pre-reserva PRE-##### quedó totalmente verificada.» en ≤ 10 s sin recargar (Realtime). El historial muestra `item_added`, `outcome_recorded`, `alternative_promoted`, `item_withdrawn` con actor y hora.

Automatizado (salvo el aviso Realtime, manual) en `supabase/tests/pre_reservation_consolidation_test.sql`.

---

## Escenario 4 — Expiración por retención (edge case time-limit, FR-006)

1. Registrar «Disponible» con «Retención hasta» dentro de 5 minutos (o adelantar `hold_expires_at` con `psql` en el entorno local).
2. Esperar el vencimiento y recargar la lista de pre-reservas o la cola.

**Esperado**: la pre-reserva aparece como «Expirada»; la línea vencida vuelve a la cola con la marca «Retención vencida»; la sección «Cotización» pasa a no elegible. Re-verificar la línea con una retención futura reactiva el cálculo (vuelve a «Totalmente verificada» si el resto sigue disponible).

---

## Escenario 5 — Excepción de cotización (US3 esc. 4, FR-007, SC-001)

1. Como admin, sobre una pre-reserva «Requiere ajuste»: **«Autorizar excepción»** sin motivo → error; con motivo → autorizada.
2. Verificar la sección «Cotización»: «Excepción autorizada por … el …» y elegible.
3. Agregar o retirar una línea principal.

**Esperado**: (1) `OVERRIDE_REASON_REQUIRED` sin motivo; con motivo queda la auditoría `quotation_override_authorized` **sin** el motivo en metadata. (3) La excepción se invalida (`override_cleared: true` en el evento y en la auditoría `pre_reservation_items_changed`) y la pre-reserva deja de ser elegible. Sobre una pre-reserva ya «Totalmente verificada» → `OVERRIDE_NOT_REQUIRED`. Como operador/agente la RPC responde `INSUFFICIENT_PERMISSIONS`.

---

## Escenario 6 — Cancelación, inmutabilidad y privacidad (FR-006, FR-009)

1. `curl "$API/rest/v1/pre_reservations?select=*" -H "apikey: $ANON"` y lo mismo para `pre_reservation_items`, `availability_verification_events`, `pre_reservation_list`, `availability_verification_queue`.
2. Intentar `UPDATE`/`DELETE` sobre `availability_verification_events` como `postgres` → rechazado (append-only).
3. Como agente, cancelar una pre-reserva sin motivo → error; con motivo → «Cancelada», todo en solo lectura y la solicitud origen conserva «En Pre-Reserva».
4. Revisar la cola de una pre-reserva de cliente: no aparece el correo ni el teléfono del viajero.

**Esperado**: (1) `permission denied` o vacío. (2) excepción `insufficient_privilege`. (3) `CANCEL_REASON_REQUIRED`; cancelada terminal (`PRE_RESERVATION_CLOSED` ante cualquier cambio). (4) solo nombre y apellido.

Automatizado en `supabase/tests/pre_reservation_rls_test.sql` y `supabase/tests/verification_traceability_test.sql`.

---

## Escenario 7 — Trazabilidad y tiempos (US4, FR-009, SC-002)

1. Como admin, abrir el detalle de una pre-reserva «Totalmente verificada» → secciones «Historial» y «Tiempos».

**Esperado**: historial cronológico con acción, actor, estado anterior → nuevo, contacto del proveedor y notas; «Tiempo hasta verificación total: X h» calculado desde la creación hasta `first_verified_at`. En una no verificada: «Aún no se verifica totalmente.».

Automatizado en `supabase/tests/verification_traceability_test.sql`.

---

## Cobertura de criterios de éxito

| Criterio | Escenarios | Evidencia |
|----------|-----------|-----------|
| SC-001 (elegibilidad 100 % verificada o excepción) | 3, 5 | `pre_reservation_consolidation_test.sql` (`assert_pre_reservation_quotable`, `quote_eligible`) |
| SC-002 (tiempos de verificación medibles) | 7 | `pre_reservation_verification_times` + `verification_traceability_test.sql` |
| SC-003 (0 sobreventa por omisión) | 3, 4, 5 | Regla FR-007 en SQL; `PRE_RESERVATION_NOT_VERIFIED` / `PRE_RESERVATION_EXPIRED` |
| SC-004 (≤ 3 clics cola → resultado) | 2 | Validación manual de la cola |
| FR-010 (aviso al agente) | 3 | Realtime manual; sondeo de respaldo automático en `pre-reservation-realtime.service.ts` |

## Suites SQL

- `pre_reservation_core_test.sql` — conversión atómica, referencias `PRE-#####`, validaciones de línea (XOR producto/complemento, fechas, rangos, tope 30, proveedor instantánea/manual), estado derivado y precedencia, ciclo de la solicitud.
- `pre_reservation_rls_test.sql` — aislamiento multi-tenant, Default Deny para `anon`, escrituras directas rechazadas, grants de RPC.
- `availability_verification_test.sql` — US2: cola, inicio idempotente, resultados y re-verificación, retenciones, roles (agente rechazado), autoasignación de operador.
- `pre_reservation_consolidation_test.sql` — US3: agregar/retirar/promover, mínimo una principal, expiración y barrido, excepción e invalidación, `assert_pre_reservation_quotable`.
- `verification_traceability_test.sql` — US4: historial append-only (UPDATE/DELETE/TRUNCATE rechazados), eventos completos, vistas de historial y tiempos.
