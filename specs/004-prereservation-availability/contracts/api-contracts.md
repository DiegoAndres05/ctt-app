# API & UI Contracts: 004-prereservation-availability

**Date**: 2026-10-04 | **Data model**: [../data-model.md](../data-model.md) | **Research**: [../research.md](../research.md)

Todas las RPCs son `SECURITY DEFINER` con `SET search_path = ''`, `REVOKE ALL … FROM PUBLIC` y `GRANT EXECUTE … TO authenticated`, salvo las internas. `anon` no ejecuta ninguna. El código de error del contrato viaja como mensaje de la excepción: el cliente lo resuelve con `toAppError`. Cualquier fila inexistente o de otra organización devuelve `VALIDATION_ERROR`.

Llamada desde Angular, igual que en 003:

```ts
const { data, error } = await this.supabase.client.rpc('create_pre_reservation', {
  p_request_id: requestId,
  p_payload: payload,
});
if (error) throw toAppError(error);
```

---

## 1. Payload de línea (`PreReservationItemInput`)

Lo usan `create_pre_reservation` (en `items[]`) y `add_pre_reservation_item`.

```jsonc
{
  "product_id": "uuid",              // XOR addon_id
  "addon_id": null,
  "start_date": "2027-03-15",        // >= hoy (America/Bogota)
  "end_date": "2027-03-18",          // opcional; obligatorio y > start_date para alojamientos
  "adults": 2,                       // 1–99
  "children": 0,                     // 0–99
  "quantity": 1,                     // 1–99
  "source_request_item_id": "uuid",  // opcional; debe pertenecer a la solicitud origen
  "provider_name": "Lanchas Barú",   // opcional; solo se usa si el producto no tiene proveedor activo
  "provider_phone": "+57 300 1112233",
  "provider_email": null,
  "alternative_of": 0                // SOLO en create: índice 0-based de una principal del mismo array
  // "alternative_of_item_id": "uuid" // SOLO en add_pre_reservation_item
}
```

Errores de línea: `VALIDATION_ERROR` (XOR, rangos, más de 30 líneas, alternativa inválida, `source_request_item_id` ajeno), `ITEM_NOT_BOOKABLE`, `TRAVEL_DATE_IN_PAST`, `INVALID_DATE_RANGE`.

---

## 2. US1 — Conversión (`038_us1_pre_reservation_conversion.sql`)

### 2.1 `create_pre_reservation(p_request_id uuid, p_payload jsonb) → jsonb` — `require_tenant_member()`

```jsonc
{ "items": [ /* PreReservationItemInput, al menos una principal */ ], "assigned_operator_id": null }
```

Returns `{ pre_reservation_id, reference, status: 'pending_verification', request_status }`.

| Estado de la solicitud | Resultado |
|------------------------|-----------|
| `received`, `in_review` | Crea la pre-reserva. La solicitud pasa a `pre_reservation`, con `closed_at = now()` y `first_handled_at = coalesce(…, now())`. Auditoría `request_status_changed` `{from, to, pre_reservation_id}` |
| `pre_reservation` | Crea una pre-reserva adicional. La solicitud no cambia |
| `discarded` | `REQUEST_CLOSED` |
| cliente anonimizado | `CUSTOMER_ANONYMIZED` |

Otros errores: `VALIDATION_ERROR` (sin ítems o sin principal), `ASSIGNEE_NOT_OPERATOR`, los errores de línea, `INSUFFICIENT_PERMISSIONS`, `SESSION_EXPIRED`. Auditoría `pre_reservation_created` `{request_id, item_count}`. Escribe un evento `item_added` por línea.

### 2.2 `cancel_pre_reservation(p_pre_reservation_id uuid, p_reason text) → jsonb` — `require_tenant_member()`

Returns `{ pre_reservation_id, status: 'cancelled', cancelled_at }`. Errores: `CANCEL_REASON_REQUIRED` (vacío), `VALIDATION_ERROR` (> 500), `PRE_RESERVATION_CLOSED`. Auditoría `pre_reservation_cancelled` `{from}`, sin el motivo. La solicitud origen **no** cambia.

---

## 3. US2 — Verificación (`039_us2_availability_verification.sql`)

### 3.1 `assign_pre_reservation_operator(p_pre_reservation_id uuid, p_operator_id uuid) → jsonb` — `require_tenant_member()`

`p_operator_id = NULL` desasigna. Returns `{ pre_reservation_id, assigned_operator_id }`. Errores: `ASSIGNEE_NOT_OPERATOR`, `PRE_RESERVATION_CLOSED`. Auditoría `pre_reservation_assigned` `{from, to}`.

### 3.2 `start_item_verification(p_item_id uuid) → jsonb` — `require_availability_verifier()` (operator/admin)

Idempotente. Returns `{ item_id, verification_started_at, assigned_operator_id }`. Errores: `ITEM_WITHDRAWN`, `PRE_RESERVATION_CLOSED`, `INSUFFICIENT_PERMISSIONS` (agente).

### 3.3 `record_item_verification(p_item_id uuid, p_payload jsonb) → jsonb` — `require_availability_verifier()`

```jsonc
{
  "status": "available",                    // available | unavailable | alternative_suggested
  "contact_person": "Carlos (recepción)",   // 1–120, obligatorio
  "contact_method": "whatsapp",             // phone | whatsapp | email | other
  "hold_expires_at": "2026-10-06T17:00:00-05:00", // solo con available; > now()
  "alternative_suggestion": null,           // obligatorio con alternative_suggested, ≤ 1000
  "notes": "Confirma 2 cabañas"             // ≤ 2000
}
```

Returns `{ item_id, verification_status, pre_reservation_status, expires_at }`.

| Condición | Error |
|-----------|-------|
| `status` ausente, `pending` o inválido, o `contact_method` inválido | `VALIDATION_ERROR` |
| `contact_person` vacío | `CONTACT_PERSON_REQUIRED` |
| `hold_expires_at` con un estado distinto de `available` | `VALIDATION_ERROR` |
| `hold_expires_at <= now()` | `HOLD_EXPIRY_IN_PAST` |
| `alternative_suggested` sin texto | `ALTERNATIVE_SUGGESTION_REQUIRED` |
| línea retirada | `ITEM_WITHDRAWN` |
| pre-reserva cancelada | `PRE_RESERVATION_CLOSED` |
| rol agent | `INSUFFICIENT_PERMISSIONS` |

Se puede registrar un nuevo resultado sobre una línea ya verificada (re-verificación); cada registro agrega un evento `outcome_recorded`. Auditoría `availability_recorded` `{item_id, from, to, has_hold}`.

---

## 4. US3 — Consolidación y ajuste (`040_us3_pre_reservation_consolidation.sql`)

| RPC | Acceso | Returns | Errores |
|-----|--------|---------|---------|
| `add_pre_reservation_item(p_pre_reservation_id uuid, p_item jsonb)` | member | `{ item_id, pre_reservation_status }` | errores de línea, `PRE_RESERVATION_CLOSED` |
| `withdraw_pre_reservation_item(p_item_id uuid, p_reason text)` | member | `{ withdrawn_item_ids, pre_reservation_status }` | `VALIDATION_ERROR` (motivo 1–500), `ITEM_WITHDRAWN`, `PRE_RESERVATION_REQUIRES_ITEMS`, `PRE_RESERVATION_CLOSED` |
| `promote_alternative_item(p_item_id uuid)` | member | `{ item_id, replaced_item_id, pre_reservation_status }` | `VALIDATION_ERROR` (no es alternativa), `ITEM_WITHDRAWN`, `PRE_RESERVATION_CLOSED` |
| `expire_due_pre_reservations()` | member | `integer` (pre-reservas que cambiaron) | — |
| `authorize_quotation_override(p_pre_reservation_id uuid, p_reason text)` | **admin** (`require_tenant_admin`) | `{ pre_reservation_id, quote_override_at }` | `OVERRIDE_REASON_REQUIRED`, `VALIDATION_ERROR` (> 500), `OVERRIDE_NOT_REQUIRED` (ya `verified`), `PRE_RESERVATION_CLOSED`, `INSUFFICIENT_PERMISSIONS` |

Agregar, retirar o promover una **principal** limpia `quote_override_*`, y la auditoría lo indica con `override_cleared: true`.

### 4.1 Punto de integración para 005 (interno)

`public.assert_pre_reservation_quotable(p_org uuid, p_pre_reservation_id uuid) → jsonb`, con `REVOKE` a `anon` y `authenticated`. La RPC de creación de cotización de 005 lo llamará dentro de su transacción.

| Situación tras `refresh` | Resultado |
|--------------------------|-----------|
| `verified` | `{ eligible: true, basis: 'verified', status, expires_at }` |
| excepción vigente y no `cancelled` | `{ eligible: true, basis: 'override', status, expires_at }` |
| `cancelled` | `PRE_RESERVATION_CLOSED` |
| `expired` sin excepción | `PRE_RESERVATION_EXPIRED` |
| cualquier otro | `PRE_RESERVATION_NOT_VERIFIED` |

---

## 5. Lecturas PostgREST y Realtime (autenticado, RLS)

| Uso | Consulta |
|-----|----------|
| Lista de pre-reservas | `from('pre_reservation_list').select('*', { count: 'exact' }).order('created_at', { ascending: false }).range(from, to)` + `.eq('status')`, `.eq('responsible_agent_id')` (`assignee=me` o uuid), `.or(toSearchOrFilter(q, ['reference','request_reference','customer_first_name','customer_last_name']))` |
| Pre-reservas de una solicitud | `from('pre_reservation_list').select('*').eq('request_id', id).order('created_at')` |
| Detalle | `from('pre_reservations').select('*, request:customer_requests!pre_reservations_request_fkey(id, reference, status), customer:customers!pre_reservations_customer_fkey(id, first_name, last_name, is_anonymized), agent:user_profiles!pre_reservations_responsible_agent_fkey(id, full_name), operator:user_profiles!pre_reservations_assigned_operator_fkey(id, full_name)').eq('id', id).maybeSingle()` + líneas, incluidas las retiradas (por eso no se usa la vista de la cola): `from('pre_reservation_items').select('*, verifier:user_profiles!pre_reservation_items_verified_by_fkey(full_name)').eq('pre_reservation_id', id).order('position')` |
| Elegibilidad en detalle | `from('pre_reservation_list').select('quote_eligible, has_quote_override').eq('id', id).maybeSingle()` |
| Cola | `from('availability_verification_queue').select('*', { count: 'exact' }).range(from, to)`; filtros: `status=''` → `.eq('needs_action', true)`; `status=all` → sin filtro; otro → `.eq('verification_status', status)`; `providerId=<uuid>` → `.eq('provider_id')`, `providerId=none` → `.is('provider_id', null)`; `assignee=me\|uuid` → `.eq('assigned_operator_id')`, `assignee=none` → `.is('assigned_operator_id', null)`; `q` → `.or(toSearchOrFilter(q, ['reference','item_label','provider_name','customer_first_name','customer_last_name']))`. Orden: `group=provider` → `.order('provider_name', { nullsFirst: false }).order('start_date').order('item_created_at')`; si no → `.order('start_date').order('item_created_at')` |
| Historial (US4) | `from('availability_verification_history').select('*').eq('pre_reservation_id', id).order('created_at', { ascending: false })` |
| Tiempos (US4) | `from('pre_reservation_verification_times').select('*').eq('id', id).maybeSingle()` |
| Catálogo para líneas | `from('products').select('id, name, type, provider_id, provider:providers(id, name, contact_phone, contact_email, is_active)').eq('status', 'active').order('name')` y `from('add_ons').select('id, name').eq('is_active', true).order('name')` |
| Proveedores (filtro de cola) | `from('providers').select('id, name').eq('is_active', true).order('name')` |
| Operadores asignables | `from('user_profiles').select('id, full_name').eq('status', 'active').in('role', ['operator','admin']).order('full_name')` |

**Realtime**: `channel('pre-reservations:<org>').on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'pre_reservations', filter: 'organization_id=eq.<org>' }, (p) => …)`. Solo se avisa si `p.new.status === 'verified'` y `p.new.responsible_agent_id === userId`, y una sola vez por id. Si el canal falla, se consulta cada 30 s `from('pre_reservations').select('id, reference, verified_at').eq('responsible_agent_id', userId).eq('status', 'verified').gt('verified_at', since)`.

**Privacidad**: con anon key, toda lectura devuelve `permission denied` o vacío. Las vistas no exponen el correo ni el teléfono del viajero.

---

## 6. Contrato de UI

### 6.1 Menú (`src/app/shared/layout/nav-items.ts`)

```ts
{
  id: 'sales', label: 'Comercial', path: null, minRole: 'agent',
  children: [
    { id: 'sales-requests',         label: 'Solicitudes',  path: '/sales/requests',         minRole: 'agent' },
    { id: 'sales-pre-reservations', label: 'Pre-reservas', path: '/sales/pre-reservations', minRole: 'agent' },
    { id: 'sales-verification',     label: 'Verificación', path: '/sales/verification',     minRole: 'operator', hideForAgent: true },
    { id: 'sales-customers',        label: 'Clientes',     path: '/sales/customers',        minRole: 'agent' },
  ],
}
```

| Item | admin | operator | agent |
|------|-------|----------|-------|
| Comercial / Pre-reservas | ✓ | ✓ | ✓ |
| Comercial / Verificación | ✓ | ✓ | — |

### 6.2 Rutas (hijas de `sales`, que ya tiene `roleGuard('agent')`)

| Path | Guards | Pantalla | Query |
|------|--------|----------|-------|
| `/sales/pre-reservations` | — | `PreReservationListComponent` | `?q&page&status&assignee` (`assignee` = `me` \| uuid del agente responsable) |
| `/sales/pre-reservations/new` | `canDeactivate: unsavedChangesGuard` | `PreReservationCreateComponent` | `?requestId=<uuid>` (obligatorio) |
| `/sales/pre-reservations/:id` | — | `PreReservationDetailComponent` | — |
| `/sales/verification` | `roleGuard('operator')` | `VerificationQueueComponent` | `?q&page&status&providerId&assignee&group` |

`new` se declara antes de `:id`.

### 6.3 `ListQuery` (`src/app/shared/components/data-table/list-query.ts`)

Agrega `providerId: string` y `group: string`, con el mismo tratamiento que `channel`/`assignee`: `emptyListQuery`, `parseListQuery`, `listQueryToParams` (omite vacíos), `FILTER_KEYS` y `hasActiveListFilters`. Para la cola, `status` lleva el estado de verificación de la línea (`''` = «Requieren acción», `pending`, `available`, `unavailable`, `alternative_suggested`, `all`).

### 6.4 Pantallas (copy en español; reutilizar `.section`, `app-alert`, `app-spinner`, `app-data-table`)

- **Detalle de solicitud (003, modificado)**: en «Gestión», el texto fijo se reemplaza por el botón «Crear pre-reserva» (enlace a `/sales/pre-reservations/new?requestId=<id>`). Se muestra si el estado es `received`, `in_review` o `pre_reservation` y el cliente no está anonimizado. Nueva sección «Pre-reservas», con la lista de las vinculadas (referencia con enlace, estado, fecha) o «Esta solicitud todavía no tiene pre-reservas.».
- **Nueva pre-reserva**: encabezado «Nueva pre-reserva para SOL-00001». Aviso fijo: «Una pre-reserva no es una reserva confirmada: requiere verificar disponibilidad con los proveedores.». La sección «Servicios» se precarga con los intereses de la solicitud que tienen producto; las fechas y los pasajeros vienen de la solicitud. Cada fila tiene «Tipo» (Producto / Complemento), el selector, «Desde»* (`min` = hoy), «Hasta» (obligatoria en alojamientos: «Indica la fecha de salida»), «Adultos»*, «Niños», «Cantidad», y «Proveedor» de solo lectura si el producto lo tiene; si no, los campos «Proveedor», «Teléfono del proveedor» y «Correo del proveedor». También «Es alternativa de» (otra fila principal; aclaración: «Las alternativas se verifican, pero no cuentan para el estado de la pre-reserva»). Botones «Agregar servicio» y «Quitar». La sección «Verificación» tiene «Operador asignado» (opcional). Acciones: «Crear pre-reserva» / «Cancelar». Al crear navega al detalle. Sin `requestId`: «Abre una solicitud y usa “Crear pre-reserva”.» con un enlace a la bandeja.
- **Pre-reservas (lista)**: `app-data-table` con el título «Pre-reservas», sin botón de crear (se crean desde una solicitud). Filtros: «Buscar» (referencia, solicitud o cliente), «Estado», «Responsable» (Todas / Mías / colaborador). Columnas: Referencia (enlace), Solicitud (enlace), Cliente, Estado, Primer servicio, Verificadas (`available_item_count/primary_item_count`), Vence (`expires_at`), Responsable, Creada. Vacío: «Todavía no hay pre-reservas.».
- **Detalle de pre-reserva**: encabezado con la referencia y el estado. Siempre muestra la alerta informativa «Esta pre-reserva no es una reserva confirmada. Requiere verificación de disponibilidad con los proveedores.». Secciones:
  - «Resumen»: solicitud con enlace, cliente con enlace, responsable, creada, vence. Selector «Operador asignado» con «Asignarme» si el rol es operador o admin.
  - «Servicios»: tabla de principales, con sus alternativas indentadas y la etiqueta «Alternativa». Columnas: servicio, fechas, pasajeros, proveedor con enlaces «Llamar» / «WhatsApp» / «Correo», estado, retención, verificado por. Acciones por fila: «Iniciar gestión» y «Registrar resultado» (solo operador o admin), «Promover a principal» (alternativas), «Retirar» (pide motivo). Las retiradas aparecen en gris con «Retirado: <motivo>».
  - «Agregar servicio»: el mismo formulario de línea.
  - «Cotización»: si `quote_eligible`, «Lista para cotizar.»; si no, «No elegible para cotizar: <motivo según estado>». En ambos casos, «La cotización se genera desde el módulo de cotizaciones.». Solo para admin y estados no `verified`/`cancelled`: «Autorizar excepción» con «Motivo de la excepción»* y la confirmación «La excepción quedará registrada en la auditoría.». Con excepción vigente: «Excepción autorizada por <nombre> el <fecha>.».
  - «Historial»: eventos con fecha, actor, acción, estado anterior → nuevo, contacto del proveedor y notas.
  - «Tiempos»: «Tiempo hasta verificación total: X h» o «Aún no se verifica totalmente.».
  - «Cancelar pre-reserva»: motivo obligatorio y confirmación «¿Cancelar esta pre-reserva? No se podrá reactivar.».

  Con la pre-reserva cancelada, todo queda en solo lectura con el aviso «Pre-reserva cancelada: <motivo>».
- **Verificación (cola)**: `app-data-table` con el título «Verificación de disponibilidad». Filtros: «Estado» (Requieren acción [default] / Pendientes / Disponibles / No disponibles / Alternativa sugerida / Todas), «Proveedor» (Todos / Sin proveedor / proveedores activos), «Operador» (Todos / Mías / Sin asignar / operador), «Buscar», y la casilla «Agrupar por proveedor». Columnas: Fecha servicio, Servicio (con la etiqueta «Alternativa» si aplica), Pasajeros, Proveedor (con enlaces de contacto; «Sin proveedor» si falta), Pre-reserva (enlace), Cliente, Estado (con «Retención vencida» si `hold_expired`, o «En gestión por <operador>» si se inició), Acciones («Iniciar gestión», «Registrar resultado»). «Registrar resultado» despliega, debajo de la fila, el formulario `VerificationOutcomeFormComponent`:
  - «Resultado»*: radio Disponible / No disponible / Alternativa sugerida.
  - «Persona de contacto en el proveedor»*.
  - «Medio de contacto»*.
  - «Retención hasta» (solo si Disponible; `datetime-local`, futura).
  - «Alternativa sugerida»* (solo si Alternativa sugerida).
  - «Notas».
  - Acciones «Guardar resultado» / «Cancelar».

  Vacío: «No hay servicios pendientes de verificación.». Con el grupo activo, cada cambio de proveedor inserta una fila de encabezado con el nombre del proveedor. SC-004: menú «Verificación» (1), filtro «Proveedor» (2), «Registrar resultado» (3).
- **Aviso global (shell)**: `VerifiedNoticeComponent` muestra `app-alert kind="success"` con «La pre-reserva PRE-00001 quedó totalmente verificada.», el enlace «Ver pre-reserva» y un botón para cerrar.

### 6.5 Servicios TS (`src/app/core/pre-reservations/services/`)

```ts
PreReservationService.listPage(q: { q?: string; status?: PreReservationStatus | ''; responsibleId?: string; page: number })
  : Promise<{ rows: PreReservationListRow[]; total: number }>;
PreReservationService.listForRequest(requestId: string): Promise<PreReservationListRow[]>;
PreReservationService.getById(id: string): Promise<PreReservationDetail | null>;     // cabecera + líneas + elegibilidad
PreReservationService.listHistory(id: string): Promise<VerificationEvent[]>;
PreReservationService.getTimes(id: string): Promise<VerificationTimes | null>;
PreReservationService.create(requestId: string, payload: CreatePreReservationPayload): Promise<CreatePreReservationResult>;
PreReservationService.addItem(id: string, item: PreReservationItemInput): Promise<void>;
PreReservationService.withdrawItem(itemId: string, reason: string): Promise<void>;
PreReservationService.promoteItem(itemId: string): Promise<void>;
PreReservationService.cancel(id: string, reason: string): Promise<void>;
PreReservationService.assignOperator(id: string, operatorId: string | null): Promise<void>;
PreReservationService.authorizeOverride(id: string, reason: string): Promise<void>;
PreReservationService.sweepExpired(): Promise<number>;                               // expire_due_pre_reservations
PreReservationService.listBookables(): Promise<BookableOption[]>;                    // productos activos + complementos activos
PreReservationService.listOperators(): Promise<AssigneeOption[]>;

AvailabilityVerificationService.queuePage(q: VerificationQueueQuery): Promise<{ rows: VerificationQueueRow[]; total: number }>;
AvailabilityVerificationService.listProviders(): Promise<{ id: string; name: string }[]>;
AvailabilityVerificationService.start(itemId: string): Promise<void>;
AvailabilityVerificationService.record(itemId: string, payload: VerificationOutcomePayload): Promise<RecordOutcomeResult>;

PreReservationRealtimeService.watchVerified(organizationId: string, userId: string,
  onVerified: (row: { id: string; reference: string }) => void): () => void;         // devuelve unsubscribe
```

Todos traducen los errores con `toAppError`. `listPage`, `getById` y `queuePage` llaman antes a `sweepExpired()`; si el barrido falla, la lectura sigue y el error queda solo en consola (R-004).

---

## 7. Códigos de error nuevos (UI)

Se agregan a `AuthErrorCode` (`src/app/core/auth/models/auth.model.ts`) y a `USER_FACING_MESSAGES` (`src/app/core/error/error-handler.ts`):

| Code | Mensaje |
|------|---------|
| `PRE_RESERVATION_CLOSED` | La pre-reserva está cancelada y ya no admite cambios. |
| `PRE_RESERVATION_REQUIRES_ITEMS` | La pre-reserva debe conservar al menos un servicio principal. |
| `PRE_RESERVATION_NOT_VERIFIED` | La pre-reserva aún no está totalmente verificada. |
| `PRE_RESERVATION_EXPIRED` | La disponibilidad confirmada venció. Vuelve a verificar con el proveedor. |
| `ITEM_NOT_BOOKABLE` | El producto o complemento no está activo en el catálogo. |
| `ITEM_WITHDRAWN` | Ese servicio fue retirado de la pre-reserva. |
| `CONTACT_PERSON_REQUIRED` | Indica con quién hablaste en el proveedor. |
| `HOLD_EXPIRY_IN_PAST` | La fecha límite de retención debe ser futura. |
| `ALTERNATIVE_SUGGESTION_REQUIRED` | Describe la alternativa que sugirió el proveedor. |
| `CANCEL_REASON_REQUIRED` | Indica el motivo para cancelar la pre-reserva. |
| `OVERRIDE_REASON_REQUIRED` | Indica el motivo de la excepción. |
| `OVERRIDE_NOT_REQUIRED` | La pre-reserva ya está totalmente verificada; no necesita excepción. |
| `ASSIGNEE_NOT_OPERATOR` | Solo un operador o administrador activo puede verificar disponibilidad. |

Reutilizados de 003: `REQUEST_CLOSED`, `CUSTOMER_ANONYMIZED`, `TRAVEL_DATE_IN_PAST`, `INVALID_DATE_RANGE`, `VALIDATION_ERROR`, `INSUFFICIENT_PERMISSIONS`, `SESSION_EXPIRED`. `MESSAGE_CODES` ordena por longitud, así que `PRE_RESERVATION_REQUIRES_ITEMS` y `PRE_RESERVATION_REQUIRES_CONVERSION` no se opacan entre sí.

---

## Trazabilidad

| Contrato | Requisitos |
|----------|-----------|
| `create_pre_reservation` + detalle de solicitud | FR-001, FR-002, FR-003, FR-011, FR-012, US1 |
| `cancel_pre_reservation` | FR-006 (Cancelada), edge case de cancelada |
| Cola + `start_item_verification` + `record_item_verification` | FR-004, FR-005, US2, SC-004 |
| `refresh_pre_reservation_status`, `expire_due_pre_reservations` | FR-006, US3 esc. 1–3, edge case time-limit |
| `add`/`withdraw`/`promote` | FR-008, edge case alternativas |
| `authorize_quotation_override`, `assert_pre_reservation_quotable`, `quote_eligible` | FR-007, US3 esc. 4, SC-001 |
| Realtime + `VerifiedNoticeComponent` | FR-010 |
| `availability_verification_events` + vistas de historial y tiempos | FR-009, US4, SC-002 |
