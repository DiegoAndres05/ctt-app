# API & UI Contracts: 003-customer-requests-channels

**Date**: 2026-10-04 | **Spec**: [spec.md](../spec.md) | **Data Model**: [data-model.md](../data-model.md)

Superficies:
1. **RPC pública** `submit_public_request` — consumida por el sitio web externo con la anon key.
2. **Webhook** `POST/GET /functions/v1/whatsapp-inbound` — consumido por Meta (WhatsApp Business Cloud API).
3. **RPCs internas** (`/rest/v1/rpc/*`) — panel autenticado y `service_role`.
4. **Lecturas PostgREST + Realtime** — panel autenticado.
5. **Contrato de UI** — rutas, menú, query params, secciones, servicios TS.

**Convención de errores** (heredada de 002/009): las RPCs levantan el código del contrato como mensaje de excepción; PostgREST responde HTTP 400 (o 403 para `insufficient_privilege`) con `{ "code": "P0001", "message": "<CODE>" }`. El panel lo traduce con `toAppError` (`message` contiene el código). La Edge Function responde `{ "code": "<CODE>" }`.

---

## 1. `submit_public_request` (público)

```
POST /rest/v1/rpc/submit_public_request
apikey: <anon key>
Content-Type: application/json
```

```ts
// Sitio externo (supabase-js)
const { data, error } = await supabase.rpc('submit_public_request', {
  p_organization_id: '<uuid de la agencia>',   // el mismo que usa get_public_site
  p_payload: {
    idempotency_key: crypto.randomUUID(),      // uno por montaje del formulario (recomendado)
    locale: 'es',                              // 'es' | 'en'
    source_page: '/experiencias/tour-islas',   // opcional, ≤ 500
    privacy_consent: true,                     // obligatorio
    website: '',                               // honeypot: debe ir vacío
    contact: {
      first_name: 'Ana',                       // obligatorio, ≤ 120
      last_name: 'García',                     // opcional
      email: 'ana@example.com',                // email o phone obligatorio
      phone: '+57 300 123 4567',               // se normaliza a E.164
      country_code: 'CO'                       // opcional, ISO alfa-2
    },
    travel_start_date: '2026-12-20',           // opcional, no pasada
    travel_end_date: '2026-12-27',             // opcional, >= start
    adults: 2,                                 // opcional, 1–99, default 1
    children: 1,                               // opcional, 0–99, default 0
    special_requirements: 'Dieta vegana',      // opcional, ≤ 2000
    items: [                                   // opcional, ≤ 10
      { public_slug: 'tour-islas-del-rosario', quantity: 2 }   // `id` de get_public_site
    ],
    interest_text: 'Algo de buceo'             // opcional, ≤ 500; se guarda como ítem libre
  }
});
```

Se exige al menos un ítem o `interest_text` o `special_requirements` (`VALIDATION_ERROR` si la solicitud no dice nada).

**Response 200**

```json
{ "reference": "SOL-00042", "deduplicated": false }
```

`deduplicated: true` devuelve la referencia de la solicitud ya existente (mismo `idempotency_key`, o misma huella en ≤ 2 min). No se exponen IDs internos.

**Errors**

| Code | Cuándo |
|------|--------|
| `VALIDATION_ERROR` | payload mal formado, > 16 KB, > 10 ítems, textos fuera de límite, honeypot lleno, solicitud vacía, organización inexistente o inactiva |
| `CONSENT_REQUIRED` | `privacy_consent` distinto de `true` |
| `CONTACT_REQUIRED` | falta `first_name` o faltan email y teléfono |
| `INVALID_EMAIL` / `INVALID_PHONE` | no normalizable |
| `TRAVEL_DATE_IN_PAST` | `travel_start_date < current_date` (zona `America/Bogota`) |
| `INVALID_DATE_RANGE` | fin antes del inicio |
| `LISTING_NOT_AVAILABLE` | algún `public_slug` no existe en la organización, no está publicado, está agotado o su producto no está activo |
| `RATE_LIMITED` | > 5 solicitudes web/hora para el mismo email o teléfono, o > 200/hora para la organización |

**Efectos**: cliente creado o vinculado (sin sobrescribir, R-005); solicitud `received`, canal `web`, `privacy_consent_at = now()`; auditoría `request_received`. Nunca crea pre-reservas ni modifica `products`, `public_listings` ni tarifas.

---

## 2. Webhook `whatsapp-inbound` (Edge Function, `verify_jwt = false`)

**Entorno** (`supabase/functions/.env`, plantilla `.env.example`; nunca en `src/`):

| Variable | Uso |
|----------|-----|
| `WHATSAPP_VERIFY_TOKEN` | handshake GET |
| `WHATSAPP_APP_SECRET` | HMAC de `X-Hub-Signature-256` |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | inyectadas por Supabase |

**GET** `?hub.mode=subscribe&hub.verify_token=<t>&hub.challenge=<c>` → `200 text/plain <c>` si coincide; `403` si no; `503 {code:'CHANNEL_NOT_CONFIGURED'}` sin token configurado.

**POST** (cuerpo de Meta, ver `fixtures/text-message.json`):

| Respuesta | Cuándo |
|-----------|--------|
| `503 { code: 'CHANNEL_NOT_CONFIGURED' }` | falta `WHATSAPP_APP_SECRET` |
| `401 { code: 'INVALID_SIGNATURE' }` | firma ausente o distinta (comparación en tiempo constante) |
| `400 { code: 'VALIDATION_ERROR' }` | cuerpo no es JSON u `object != 'whatsapp_business_account'` |
| `200 { processed, duplicates, ignored, requests_created, messages_attached }` | firma válida; resultado de `ingest_whatsapp_webhook` |
| `500 { code: 'INGEST_FAILED' }` | error de la RPC (Meta reintentará; la ingesta es idempotente) |

La función no escribe cuerpos, teléfonos ni firmas en logs; solo el código y los contadores.

---

## 3. RPCs internas

Todas `SECURITY DEFINER`. Autorización por `require_tenant_member()` (cualquier colaborador activo) salvo indicación.

### 3.1 `create_assisted_request(p_payload jsonb) → jsonb`

```json
{
  "channel": "whatsapp",                        // whatsapp | phone | in_person
  "customer_id": "uuid",                        // XOR contact
  "contact": { "first_name": "Luis", "phone": "3001234567", "email": null, "last_name": null, "country_code": "CO" },
  "privacy_notice_given": true,
  "idempotency_key": "uuid",                    // opcional, uno por montaje del formulario
  "travel_start_date": "2026-11-02", "travel_end_date": null,
  "adults": 2, "children": 0,
  "special_requirements": "Resumen de la conversación…",
  "items": [ { "product_id": "uuid", "quantity": 1 }, { "free_text": "Cena romántica" } ]
}
```

Returns `{ request_id, reference, customer_id, customer_created, deduplicated, contact_review_required }`. Errors: `VALIDATION_ERROR`, `CONSENT_REQUIRED`, `CONTACT_REQUIRED`, `INVALID_EMAIL`, `INVALID_PHONE`, `TRAVEL_DATE_IN_PAST`, `INVALID_DATE_RANGE`, `CUSTOMER_ANONYMIZED`, `INSUFFICIENT_PERMISSIONS`. Efecto extra: `assigned_to = auth.uid()`.

### 3.2 `ingest_whatsapp_webhook(p_payload jsonb) → jsonb` — solo `service_role`

Entrada: cuerpo crudo de Meta. Reglas en R-007. Returns `{ processed, duplicates, ignored, requests_created, messages_attached }`. `EXECUTE` revocado a `anon` y `authenticated`.

### 3.3 `update_customer(p_customer_id uuid, p_payload jsonb) → jsonb`

Payload: `{ first_name, last_name, email, phone, country_code, document_type, document_number }` (reemplazo completo de los campos editables). Returns la fila actualizada. Errors: `VALIDATION_ERROR`, `CONTACT_REQUIRED`, `INVALID_EMAIL`, `INVALID_PHONE`, `CUSTOMER_CONTACT_TAKEN`, `CUSTOMER_ANONYMIZED`. Audit `customer_updated` `{ fields: [...] }`.

### 3.4 `assign_request(p_request_id uuid, p_assignee_id uuid) → jsonb`

Returns `{ request_id, assigned_to, assigned_at }`. Errors: `VALIDATION_ERROR`, `ASSIGNEE_NOT_IN_ORGANIZATION`, `REQUEST_CLOSED`. Audit `request_assigned` `{ from, to }`.

### 3.5 `set_request_status(p_request_id uuid, p_status request_status, p_reason text DEFAULT NULL) → jsonb`

| Desde → hacia | Resultado |
|---------------|-----------|
| `received → in_review` | ok; `first_handled_at` |
| `received → discarded`, `in_review → discarded` | ok con `p_reason` (1–500); `first_handled_at`, `closed_at` |
| `* → pre_reservation` | `PRE_RESERVATION_REQUIRES_CONVERSION` |
| desde `discarded` / `pre_reservation` | `REQUEST_CLOSED` |
| cualquier otra | `INVALID_STATUS_TRANSITION` |
| descarte sin motivo | `DISCARD_REASON_REQUIRED` |

Returns `{ request_id, status, first_handled_at, closed_at }`. Audit `request_status_changed` `{ from, to }` (el motivo no se copia a auditoría).

### 3.6 `add_request_note(p_request_id uuid, p_customer_id uuid, p_content text) → jsonb`

Exactamente uno de los dos destinos. Returns `{ note_id, created_at }`. Errors: `VALIDATION_ERROR`.

### 3.7 `anonymize_customer(p_customer_id uuid, p_reason text) → jsonb` — `require_tenant_admin()`

Returns `{ customer_id, requests_scrubbed, messages_scrubbed }`. Errors: `VALIDATION_ERROR` (sin motivo), `CUSTOMER_ANONYMIZED`, `INSUFFICIENT_PERMISSIONS`. Audit `customer_anonymized`.

### 3.8 Contrato reservado para 004 (no implementado aquí)

La RPC de conversión de 004 hará, en su transacción, `received|in_review → pre_reservation` con `closed_at = now()` y `first_handled_at = coalesce(first_handled_at, now())`, y emitirá `request_status_changed`. 003 no expone esa transición.

---

## 4. Lecturas PostgREST y Realtime (autenticado, RLS)

| Uso | Consulta |
|-----|----------|
| Bandeja | `from('customer_request_list').select('*', { count: 'exact' }).order('created_at', { ascending: false }).range(from, to)` + `.eq('status')`, `.eq('channel')`, `.eq('assigned_to')` o `.is('assigned_to', null)` (`assignee=none`), `.or(searchFilter)` sobre `reference, customer_first_name, customer_last_name, customer_email, customer_phone_e164` |
| Detalle | `from('customer_requests').select('*, customer:customers(*), items:customer_request_items(*, product:products(id, name, product_type)), assignee:user_profiles!customer_requests_assigned_to_fkey(id, full_name)').eq('id', id).maybeSingle()` |
| Conversación | `from('inbound_messages').select('id, profile_name, message_type, body, provider_timestamp').eq('request_id', id).order('provider_timestamp')` |
| Notas | `from('request_notes').select('*, author:user_profiles(full_name)').eq('request_id' \| 'customer_id', id).order('created_at', { ascending: false })` |
| Clientes | `from('customer_list').select('*', { count: 'exact' }).order('last_request_at', { ascending: false, nullsFirst: false }).range(...)` + `.or(searchFilter)` sobre `first_name, last_name, email, phone_e164` |
| Ficha | `from('customers').select('*').eq('id', id).maybeSingle()` + historial `from('customer_request_list').eq('customer_id', id).order('created_at', { ascending: false })` |
| Colaboradores asignables | `from('user_profiles').select('id, full_name').eq('status', 'active').order('full_name')` |
| Productos para alta asistida | `from('products').select('id, name, product_type').eq('status', 'active').order('name')` |

`searchFilter` lo construye `toSearchOrFilter(q, columns)` (`src/app/core/customers/search-pattern.ts`): quita `, ( ) * % \ :` y comillas, colapsa espacios, recorta a 80 caracteres y produce `col.ilike.*q*` por columna; si `q` contiene dígitos y la columna es de teléfono, busca solo los dígitos.

**Realtime**: `supabase.client.channel('sales-requests:<org>').on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'customer_requests', filter: 'organization_id=eq.<org>' }, () => refresh())`. Solo se usa como señal; la UI no muestra el payload.

**Privacidad**: con anon key, toda lectura de estas tablas y vistas responde `permission denied` o vacío.

---

## 5. Contrato de UI

### 5.1 Menú (`src/app/shared/layout/nav-items.ts`)

Orden resultante de `NAV_TREE`: Dashboard → **Comercial** → Configuración → CMS. *(Se inserta tras Dashboard; el resto conserva su orden de 010.)*

```ts
{
  id: 'sales', label: 'Comercial', path: null, minRole: 'agent',
  children: [
    { id: 'sales-requests',  label: 'Solicitudes', path: '/sales/requests',  minRole: 'agent' },
    { id: 'sales-customers', label: 'Clientes',    path: '/sales/customers', minRole: 'agent' },
  ],
}
```

| Item | admin | operator | agent |
|------|-------|----------|-------|
| Comercial / Solicitudes | ✓ | ✓ | ✓ |
| Comercial / Clientes | ✓ | ✓ | ✓ |

### 5.2 Rutas (hijas de `AdminShellComponent`)

| Path | Guards | Pantalla | Query |
|------|--------|----------|-------|
| `/sales` | — | redirige a `/sales/requests` | — |
| `/sales/requests` | `roleGuard('agent')` | `RequestListComponent` | `?q&page&status&channel&assignee` (`assignee` = uuid \| `me` \| `none`) |
| `/sales/requests/new` | `roleGuard('agent')`, `canDeactivate: unsavedChangesGuard` | `RequestIntakeComponent` | `?channel=whatsapp\|phone\|in_person&customerId=<uuid>` |
| `/sales/requests/:id` | `roleGuard('agent')` | `RequestDetailComponent` | — |
| `/sales/customers` | `roleGuard('agent')` | `CustomerListComponent` | `?q&page` |
| `/sales/customers/:id` | `roleGuard('agent')`, `canDeactivate: unsavedChangesGuard` | `CustomerDetailComponent` | — |

`/sales/requests/new` debe declararse antes de `:id`.

### 5.3 `ListQuery` (`list-query.ts`)

Agrega `channel: string` y `assignee: string`, con el mismo tratamiento que los filtros existentes (`parseListQuery`, `listQueryToParams` omite vacíos, `FILTER_KEYS`, `hasActiveListFilters`). `assignee=me` se resuelve en el componente al `user().id`.

### 5.4 Pantallas

- **Solicitudes (lista)** — `app-data-table` título «Solicitudes», botón «Nueva solicitud» (`dataTableCreate`, todos los roles). Filtros: Buscar (referencia, nombre, correo o teléfono), Estado, Canal, Responsable (Todos / Mías / Sin asignar / colaborador). Columnas: Referencia (enlace), Cliente, Canal, Estado (+ «Datos a revisar»), Fechas de viaje, Viajeros, Responsable, Recibida. Vacío: «Todavía no hay solicitudes.». Aviso Realtime: «Llegó una solicitud nueva.».
- **Nueva solicitud** — secciones `.section`: «Canal» (WhatsApp/Teléfono/Presencial); «Cliente» (buscar existente o datos de contacto: nombre*, apellido, correo, teléfono, país; regla visible «Ingresa correo o teléfono»); «Viaje» (inicio ≥ hoy con `min`, fin ≥ inicio, adultos*, niños); «Intereses» (productos activos + texto libre, filas agregables); «Notas del cliente» (`special_requirements`); «Privacidad» (casilla obligatoria «Informé al cliente sobre el tratamiento de sus datos»). Acciones al final: «Guardar solicitud» / «Cancelar». Al guardar navega a `/sales/requests/:id`; si `deduplicated` muestra «Ya existía una solicitud igual; se abrió la existente.».
- **Detalle de solicitud** — encabezado `reference` + estado. Secciones: «Resumen» (canal, recibida, fechas, viajeros, consentimiento); «Cliente» (nombre con enlace a la ficha, contacto; si `contact_review_required`, alerta «Datos de contacto a revisar» con los datos enviados); «Intereses»; «Conversación» (solo `whatsapp`, mensajes entrantes cronológicos); «Gestión» (Responsable con «Asignarme»; acciones según estado: «Pasar a En gestión», «Descartar» con motivo obligatorio; texto fijo «La pre-reserva se crea desde el módulo de pre-reservas.» y sin acción manual); «Notas» (agregar + listado, aviso «No escribas datos personales sensibles en las notas.»). Cerrada: sección Gestión en solo lectura.
- **Clientes (lista)** — `app-data-table` título «Clientes», sin botón de creación. Filtro Buscar (nombre, correo o teléfono). Columnas: Nombre (enlace), Correo, Teléfono, País, Solicitudes, Última solicitud. Anonimizados: «Cliente anonimizado».
- **Ficha de cliente** — secciones: «Datos de contacto» (editable, Signal Forms, guardar con `update_customer`); «Documento»; «Historial de solicitudes» (cronológico desc., enlace a cada una, botón «Nueva solicitud para este cliente» → `/sales/requests/new?customerId=`); «Notas»; «Privacidad» (solo admin: «Anonimizar cliente», motivo obligatorio + confirmación «Esta acción no se puede deshacer»). Anonimizado: todo en solo lectura con aviso.

### 5.5 Servicios TS (`src/app/core/customers/services/`)

```ts
RequestService.listPage(q: { q?: string; status?: RequestStatus; channel?: RequestChannel;
  assignee?: string /* uuid | 'none' */; customerId?: string; page: number })
  : Promise<{ rows: RequestListRow[]; total: number }>;
RequestService.getById(id: string): Promise<RequestDetail | null>;
RequestService.listMessages(requestId: string): Promise<InboundMessage[]>;
RequestService.listNotes(target: { requestId: string } | { customerId: string }): Promise<RequestNote[]>;
RequestService.createAssisted(payload: AssistedRequestPayload): Promise<CaptureResult>;
RequestService.assign(requestId: string, assigneeId: string | null): Promise<void>;
RequestService.setStatus(requestId: string, status: 'in_review' | 'discarded', reason?: string): Promise<void>;
RequestService.addNote(target: { requestId: string } | { customerId: string }, content: string): Promise<void>;

CustomerService.listPage(q: { q?: string; page: number }): Promise<{ rows: CustomerListRow[]; total: number }>;
CustomerService.getById(id: string): Promise<Customer | null>;
CustomerService.search(q: string, limit?: number): Promise<CustomerListRow[]>;   // selector del alta asistida
CustomerService.update(id: string, input: CustomerContactInput): Promise<Customer>;
CustomerService.anonymize(id: string, reason: string): Promise<void>;

RequestRealtimeService.watchNewRequests(organizationId: string, onInsert: () => void): () => void; // devuelve unsubscribe
```

Todos traducen errores con `toAppError`.

---

## 6. Códigos de error nuevos (UI)

Se agregan a `AuthErrorCode` (`src/app/core/auth/models/auth.model.ts`) y a `USER_FACING_MESSAGES` (`src/app/core/error/error-handler.ts`):

| Code | Mensaje |
|------|---------|
| `CONSENT_REQUIRED` | Debes confirmar que el cliente fue informado sobre el tratamiento de sus datos. |
| `CONTACT_REQUIRED` | Ingresa el nombre y al menos un correo o un teléfono. |
| `INVALID_EMAIL` | El correo no tiene un formato válido. |
| `INVALID_PHONE` | El teléfono no es válido. Incluye el indicativo del país si no es de Colombia. |
| `TRAVEL_DATE_IN_PAST` | La fecha de inicio del viaje no puede estar en el pasado. |
| `INVALID_DATE_RANGE` | La fecha de fin no puede ser anterior a la de inicio. |
| `LISTING_NOT_AVAILABLE` | Uno de los productos no está disponible para solicitudes. |
| `RATE_LIMITED` | Se recibieron demasiadas solicitudes. Inténtalo más tarde. |
| `INVALID_STATUS_TRANSITION` | Ese cambio de estado no está permitido. |
| `PRE_RESERVATION_REQUIRES_CONVERSION` | La pre-reserva se crea desde el módulo de pre-reservas. |
| `DISCARD_REASON_REQUIRED` | Indica el motivo para descartar la solicitud. |
| `REQUEST_CLOSED` | La solicitud está cerrada y ya no admite cambios de gestión. |
| `ASSIGNEE_NOT_IN_ORGANIZATION` | El colaborador elegido no está activo en tu organización. |
| `CUSTOMER_ANONYMIZED` | El cliente fue anonimizado y no admite cambios. |
| `CUSTOMER_CONTACT_TAKEN` | Ese correo o teléfono ya pertenece a otro cliente. |

`MESSAGE_CODES` ya ordena por longitud, por lo que `CUSTOMER_CONTACT_TAKEN` no queda opacado por `CONTACT_REQUIRED` ni viceversa.

---

## Trazabilidad

| Contrato | Requisitos |
|----------|-----------|
| `submit_public_request` | FR-001, FR-002, FR-003, FR-004, US1, SC-001, SC-002, SC-003, edge cases (doble envío, fecha pasada, agotado, conflicto de contacto) |
| `create_assisted_request` | FR-002, FR-003, US2 esc. 1–2 |
| `whatsapp-inbound` + `ingest_whatsapp_webhook` | FR-002, FR-009, US2 esc. 1–4, edge case reintento |
| `assign_request`, `set_request_status`, `add_request_note` | FR-005, FR-010 (`first_handled_at`) |
| `customer_list`, `customers`, `update_customer`, historial | US3, FR-007 |
| RLS + grants + `anonymize_customer` | FR-006, FR-008, US4 |
| Realtime en la bandeja | FR-010, SC-004 |
