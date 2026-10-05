# Quickstart & Validation: 003-customer-requests-channels

**Date**: 2026-10-04 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Guía para comprobar la feature de punta a punta. Payloads y códigos en [contracts/api-contracts.md](./contracts/api-contracts.md); entidades en [data-model.md](./data-model.md).

## Prerrequisitos

- Docker (suite SQL) y Supabase CLI (stack local con Edge Runtime y Realtime).
- Migraciones `001`–`034` y `supabase/seed.sql` aplicados. El seed deja la organización demo `00000000-0000-4000-a000-000000000001` con `settings.default_phone_country_code = '57'`, usuarios `admin@`, `operador@`, `agente@demo-turismo.test` (`DemoPass123!`), fichas públicas publicadas de 009, clientes y solicitudes demo, y una `channel_connections` WhatsApp con `external_account_id = 'local-dev-phone-number-id'`.
- Para el adaptador WhatsApp local: `supabase/functions/.env` creado desde `supabase/functions/.env.example` con valores de desarrollo (`WHATSAPP_VERIFY_TOKEN=local-verify-token`, `WHATSAPP_APP_SECRET=local-dev-secret`). **No se necesitan credenciales reales de Meta.**

## Setup

```bash
# Backend: migraciones + seed + todas las suites SQL en Postgres 17 desechable
./supabase/tests/run-sql-tests.sh

# Stack local (PostgREST, Realtime, Edge Runtime)
supabase start
supabase db reset                                   # aplica migraciones + seed
supabase functions serve whatsapp-inbound --env-file supabase/functions/.env

# Frontend
npm install
npm start                                           # http://127.0.0.1:4200
npm test && npm run lint && npm run format:check && npm run build
```

Variables usadas abajo: `API=http://127.0.0.1:54321`, `ANON=<anon key de supabase status>`, `ORG=00000000-0000-4000-a000-000000000001`, `SLUG=islas-capri-premium` (ficha publicada que siembra `027_public_catalog_seed.sql`).

---

## Escenario 1 — Solicitud web desde el sitio público (US1)

**Objetivo**: FR-001, FR-003, FR-004, SC-001, SC-002, SC-003.

```bash
curl -s "$API/rest/v1/rpc/submit_public_request" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"p_organization_id":"'$ORG'","p_payload":{"idempotency_key":"6f1c2e3a-0000-4000-8000-000000000001","locale":"es","privacy_consent":true,"website":"","contact":{"first_name":"Ana","email":"Ana@Example.com","phone":"+57 300 123 4567"},"travel_start_date":"2026-12-20","adults":2,"items":[{"public_slug":"'$SLUG'"}]}}'
```

**Esperado**: `{"reference":"SOL-…","deduplicated":false}` en < 2 s. En el panel (`/sales/requests`) aparece la solicitud con canal Web, estado Recibida, cliente «Ana» con correo `ana@example.com` y teléfono `+573001234567`. No cambia ninguna fila de `products`, `public_listings` ni `pricing_schemes`.

**Negativos** (misma llamada cambiando un campo): sin `privacy_consent` → `CONSENT_REQUIRED`; sin email ni teléfono → `CONTACT_REQUIRED`; `"website":"x"` → `VALIDATION_ERROR`; `travel_start_date` de ayer → `TRAVEL_DATE_IN_PAST`. Ninguno crea filas.

Automatizado en `supabase/tests/public_request_intake_test.sql`.

---

## Escenario 2 — Doble envío e idempotencia (edge case)

Repetir la llamada del escenario 1 con el mismo `idempotency_key` y, aparte, sin `idempotency_key` dos veces seguidas.

**Esperado**: `deduplicated: true` y la misma `reference`; la bandeja muestra una sola solicitud por caso.

---

## Escenario 3 — Ficha agotada o no publicada (consistencia con 009)

Como operador, marcar agotada la ficha `islas-capri-premium` (CMS → Experiencias → la experiencia → sección Publicación). Repetir el escenario 1 con otro `idempotency_key`.

**Esperado**: `LISTING_NOT_AVAILABLE`; ninguna fila nueva. Al quitar la marca, la solicitud vuelve a aceptarse.

---

## Escenario 4 — Conflicto de contacto sin sobrescritura (R-005)

1. Enviar una solicitud web con `email` de Ana y `first_name: "Otra Persona"` y un teléfono nuevo.
2. Enviar otra con el email de un cliente B del seed y el teléfono de Ana.

**Esperado**: (1) vinculada a Ana; el perfil de Ana conserva su nombre; se completa el teléfono solo si Ana no tenía; la solicitud muestra «Datos de contacto a revisar» con lo enviado. (2) vinculada a B (coincidencia por email), marcada para revisión; ni A ni B cambian.

---

## Escenario 5 — Captura asistida de WhatsApp (US2, sin credenciales)

1. Entrar como `agente@demo-turismo.test` → menú **Comercial → Solicitudes** → «Nueva solicitud».
2. Canal WhatsApp, teléfono `300 123 4567` (sin indicativo), interés libre «Cena romántica», marcar la casilla de privacidad, guardar.

**Esperado**: se abre el detalle de la nueva solicitud, canal WhatsApp, vinculada a Ana (mismo `+573001234567`), responsable = el agente. Salir del formulario con cambios sin guardar pide confirmación.

---

## Escenario 6 — Adaptador WhatsApp con simulación local (US2, FR-009)

```bash
# Handshake de verificación
curl -s "$API/functions/v1/whatsapp-inbound?hub.mode=subscribe&hub.verify_token=local-verify-token&hub.challenge=42"   # → 42

# Mensaje entrante firmado con el secreto local
./scripts/simulate-whatsapp-inbound.sh                      # usa fixtures/text-message.json
./scripts/simulate-whatsapp-inbound.sh                      # mismo wamid: reintento
WAMID=wamid.local-2 ./scripts/simulate-whatsapp-inbound.sh  # mensaje nuevo, mismo número
```

**Esperado**: 1.ª llamada `200` con `requests_created: 1`; 2.ª `duplicates: 1` y nada nuevo; 3.ª `messages_attached: 1` y la sección «Conversación» de esa solicitud muestra los dos mensajes. Con un `phone_number_id` desconocido en el fixture → `ignored: 1`. Una firma incorrecta (`SECRET=otro ./scripts/simulate-whatsapp-inbound.sh`) → `401 INVALID_SIGNATURE`. Sin `WHATSAPP_APP_SECRET` en el entorno → `503 CHANNEL_NOT_CONFIGURED`.

Sin Edge Runtime, la misma lógica queda cubierta por `supabase/tests/whatsapp_intake_test.sql`, que invoca `ingest_whatsapp_webhook` con el fixture.

**Con credenciales reales** (fuera del MVP local): registrar la URL pública de la función en la app de Meta, configurar `WHATSAPP_VERIFY_TOKEN` y `WHATSAPP_APP_SECRET` como secretos de la función (`supabase secrets set …`) e insertar en `channel_connections` el `phone_number_id` real de la agencia. No hay cambios de código.

---

## Escenario 7 — Bandeja, gestión y notificación (US3, FR-005, FR-010, SC-004)

1. Abrir `/sales/requests` como agente en una ventana. Desde otra terminal ejecutar el escenario 1 con un `idempotency_key` nuevo.
2. Abrir la solicitud → «Asignarme» → «Pasar a En gestión» → agregar una nota.
3. «Descartar» sin motivo; luego con motivo.

**Esperado**: (1) la fila nueva y el aviso «Llegó una solicitud nueva.» aparecen en ≤ 10 s sin recargar. (2) responsable y estado cambian; la nota aparece con autor y hora; auditoría `request_assigned` y `request_status_changed`. (3) sin motivo → «Indica el motivo para descartar la solicitud.»; con motivo → Descartada y Gestión en solo lectura. No existe acción manual «En pre-reserva». Filtros, búsqueda y página sobreviven a volver desde el detalle y a recargar.

Reglas automatizadas en `supabase/tests/request_workflow_test.sql`.

---

## Escenario 8 — Ficha de cliente (US3, FR-007)

1. **Comercial → Clientes**, buscar `300 123` y luego `ana@`.
2. Abrir la ficha: historial de solicitudes de más reciente a más antigua (web y WhatsApp), notas, editar el apellido y guardar.
3. Cambiar el correo por el de otro cliente y guardar.

**Esperado**: (1) Ana aparece en ambas búsquedas. (2) historial completo; el cambio se guarda y audita `customer_updated` sin valores personales. (3) «Ese correo o teléfono ya pertenece a otro cliente.».

---

## Escenario 9 — Privacidad y anonimización (US4, FR-006, FR-008)

1. `curl "$API/rest/v1/customers?select=*" -H "apikey: $ANON"` y lo mismo para `customer_requests`, `customer_list`, `inbound_messages`.
2. Como agente u operador, abrir la ficha de Ana: no hay sección «Privacidad».
3. Como admin, «Anonimizar cliente» con motivo y confirmar.
4. Repetir el escenario 1 con el email original de Ana.

**Esperado**: (1) `permission denied` o lista vacía. (2) la acción no existe y la RPC responde `INSUFFICIENT_PERMISSIONS` si se invoca directamente. (3) la ficha muestra «Cliente anonimizado», sin correo, teléfono ni documento; sus solicitudes siguen en el historial con datos enviados, notas del cliente y mensajes reemplazados por `[anonimizado]`; evento `customer_anonymized`. (4) se crea un cliente nuevo; el anonimizado no se reutiliza.

Automatizado en `supabase/tests/customer_privacy_test.sql` y `supabase/tests/customer_requests_rls_test.sql`.

---

## Cobertura de criterios de éxito

| Criterio | Escenarios | Evidencia |
|----------|-----------|-----------|
| SC-001 (< 2 s) | 1 | Medición manual con `curl -w '%{time_total}'`; una sola RPC |
| SC-002 (100 % vinculadas con canal) | 1, 4, 5, 6 | `public_request_intake_test.sql`, `whatsapp_intake_test.sql` (NOT NULL + FK) |
| SC-003 (0 reservas desde solicitud) | 1, 7 | `public_request_intake_test.sql`, `request_workflow_test.sql` (`PRE_RESERVATION_REQUIRES_CONVERSION`) |
| SC-004 (≤ 10 s, primera gestión registrada) | 7 | Manual (Realtime); `first_handled_at` en `request_workflow_test.sql` |
| FR-006 / US4 | 9 | `customer_requests_rls_test.sql`, `customer_privacy_test.sql` |

## Suites SQL

- `customer_intake_core_test.sql` — núcleo compartido: normalización de email/teléfono, matching de clientes, idempotencia/dedup, referencias `SOL-#####`.
- `customer_requests_rls_test.sql` — aislamiento multi-tenant, Default Deny para `anon`, escrituras directas rechazadas, grants de RPC.
- `public_request_intake_test.sql` — US1: validación, normalización, matching, dedup, agotado, throttling, auditoría.
- `whatsapp_intake_test.sql` — US2: captura asistida, ingesta del webhook, idempotencia, agrupación, tenant por conexión.
- `request_workflow_test.sql` — US3: transiciones, asignación, notas append-only, edición de cliente, marcas de tiempo.
- `customer_privacy_test.sql` — US4: anonimización solo admin, limpieza, historial preservado, auditoría sin PII.
