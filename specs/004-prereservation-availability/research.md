# Research: 004-prereservation-availability

**Date**: 2026-10-04 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Fase 0 del plan. No quedan `NEEDS CLARIFICATION`: las cinco decisiones de negocio se resolvieron en la sesión de clarificación 2026-10-04 del spec. Este documento fija las decisiones técnicas para implementar 004 **como incremento** sobre lo que ya existe:

- **001**: `organizations`, `user_profiles`, claims `organization_id`/`app_role`, `audit.log_event`, `set_updated_at()`, `require_tenant_admin()`.
- **002/009**: `products` (`UNIQUE (id, organization_id)`, `provider_id`, `status`), `add_ons` (`UNIQUE (id, organization_id)`, `is_active`), `providers` (`name`, `contact_email`, `contact_phone`, `is_active`; **sin** `UNIQUE (id, organization_id)`), `require_catalog_manager()`.
- **003**: `customers`, `customer_requests` (`UNIQUE (id, organization_id)`, estado `pre_reservation` reservado, `customer_requests_closed_at` CHECK), `customer_request_items`, `organization_sequences` + `next_organization_sequence()`, `require_tenant_member()`, `set_request_status` (rechaza `pre_reservation` con `PRE_RESERVATION_REQUIRES_CONVERSION`), vistas `security_invoker`, Realtime opcional, pantallas `/sales/*`.
- **010**: `NAV_TREE` (`nav-items.ts`), `app-data-table`, `list-query.ts`, `unsavedChangesGuard`, `roleGuard`.

Migraciones nuevas desde `035`.

---

## R-001 — Capacidad y ubicación: Pre-Reservas dentro de «Comercial»

**Decision**: Nueva capacidad `src/app/core/pre-reservations/` (modelos, servicios, lógica pura) y pantallas en `src/app/features/sales/pre-reservations/` y `src/app/features/sales/verification/`. Rutas bajo `/sales/*` (ya protegidas por `roleGuard('agent')`): `/sales/pre-reservations`, `/sales/pre-reservations/new`, `/sales/pre-reservations/:id` y `/sales/verification` (esta con `roleGuard('operator')`). Menú «Comercial»: Solicitudes → Pre-reservas → Verificación (operador/admin, `hideForAgent`) → Clientes.

**Rationale**: El embudo Solicitud → Pre-Reserva → Cotización es comercial y lo trabajan los mismos colaboradores (spec US1 «agente u operador»). Un grupo «Operaciones» con un único ítem agrega navegación sin valor (Simplicity). La cola sí se restringe a operador/admin (clarificación 5).

**Alternatives considered**: Grupo de menú «Operaciones» (rechazado: un solo hijo; se puede crear cuando 006 traiga más pantallas operativas). Ubicar la cola dentro de `/cms` (rechazado: el CMS es catálogo, no operación).

---

## R-002 — Conversión atómica y frontera con 003

**Decision**: `create_pre_reservation(p_request_id, p_payload)` (`SECURITY DEFINER`, `require_tenant_member()`) delega en el núcleo interno `create_pre_reservation_core(p_org, p_request_id, p_payload, p_actor)`. En **una transacción**: bloquea la solicitud `FOR UPDATE`; rechaza `discarded` (`REQUEST_CLOSED`) y clientes anonimizados (`CUSTOMER_ANONYMIZED`); inserta la pre-reserva y sus líneas; si la solicitud estaba en `received` o `in_review`, la actualiza directamente a `pre_reservation` con `closed_at = now()` y `first_handled_at = coalesce(first_handled_at, now())` (satisface los CHECK `customer_requests_closed_at` y `customer_requests_first_handled` de `029`) y emite `request_status_changed` `{from, to, pre_reservation_id}`. Si ya estaba en `pre_reservation`, no la toca (pre-reservas adicionales, clarificación 1).

`set_request_status` **no cambia**: sigue rechazando `pre_reservation` con `PRE_RESERVATION_REQUIRES_CONVERSION`. Así se cumple el contrato reservado de 003 (§3.8 de sus contracts) sin reabrir esa RPC.

**Rationale**: Un único camino de conversión (Explicit State Transitions). El núcleo interno permite que `supabase/seed.sql` cree datos demo igual que 003 usa `capture_request_core`.

**Alternatives considered**: Exponer `pre_reservation` en `set_request_status` con un flag (rechazado: dos caminos para la misma transición). Trigger `AFTER INSERT ON pre_reservations` que cambie la solicitud (rechazado: comportamiento oculto).

---

## R-003 — Estado global derivado y persistido por una sola función

**Decision**: La única autoridad del estado global es `refresh_pre_reservation_status(p_pre_reservation_id uuid) → pre_reservation_status` (interna). Considera solo **líneas principales vigentes** (`alternative_of_item_id IS NULL AND withdrawn_at IS NULL`) y aplica la precedencia del spec FR-006:

1. `cancelled` se conserva (terminal; la función no lo recalcula).
2. `expired` si alguna línea principal `available` tiene `hold_expires_at <= now()`.
3. `requires_adjustment` si alguna es `unavailable` o `alternative_suggested`.
4. `verified` si todas son `available`.
5. `partially_verified` si alguna es `available`.
6. `pending_verification` en otro caso.

Además persiste `expires_at = min(hold_expires_at)` de las líneas principales `available` con retención, y `verified_at` (se fija al entrar en `verified` y se limpia al salir). Si el estado cambia, emite `pre_reservation_status_changed` `{from, to}`. Toda RPC que modifica líneas la llama al final. Las líneas alternativas no influyen (clarificación 3).

**Rationale**: Una sola implementación de la regla (Business Rules: single authoritative implementation). El estado se guarda (no solo se calcula en una vista) para que la lista filtre y ordene con índice, y para que Realtime notifique el paso a `verified`.

**Alternatives considered**: Estado solo calculado en una vista (rechazado: no dispara Realtime y obliga a recalcular en cada lectura). Recalcular en TypeScript (rechazado: duplica la regla en la UI).

---

## R-004 — Expiración por retención sin planificador

**Decision**: La expiración depende del tiempo, así que además del recálculo en cada RPC hay un barrido idempotente `expire_due_pre_reservations() → integer` (`SECURITY DEFINER`, `require_tenant_member()`, solo el tenant del llamador). Recalcula las pre-reservas no canceladas que tengan alguna línea principal `available` con `hold_expires_at <= now()` y estado distinto de `expired`. El panel lo invoca antes de cargar la lista de pre-reservas, la cola y el detalle. Las vistas exponen además `hold_expired` por línea, para que una línea vencida vuelva a la cola aunque nadie haya barrido todavía. Re-verificar la línea con una retención futura vuelve a derivar el estado (clarificación 4).

**Rationale**: El proyecto no usa `pg_cron` y el harness SQL (Postgres 17 sin extensiones de Supabase) no lo tendría. El barrido al leer es simple, determinista y testeable. `assert_pre_reservation_quotable` (R-008) recalcula antes de responder, así que 005 nunca cotiza sobre una retención vencida.

**Alternatives considered**: `pg_cron` o Edge Function programada (rechazado por ahora: infraestructura nueva para un MVP de un tenant; queda como mejora si la operación lo exige). Calcular `expired` solo en la vista (rechazado: ver R-003).

---

## R-005 — Líneas, alternativas y ajustes sin edición en el lugar

**Decision**: `pre_reservation_items` guarda cada línea con `product_id` XOR `addon_id` (FK compuestas a `products` y `add_ons`) y `alternative_of_item_id` (FK compuesta a la misma tabla; una alternativa siempre apunta a una principal de la misma pre-reserva, sin cadenas). Los ajustes son RPCs explícitas:

- `add_pre_reservation_item(p_pre_reservation_id, p_item)`: principal o alternativa.
- `withdraw_pre_reservation_item(p_item_id, p_reason)`: retiro lógico (`withdrawn_at`, `withdrawn_reason`). Si se retira una principal, sus alternativas se retiran también. No se permite dejar cero principales vigentes (`PRE_RESERVATION_REQUIRES_ITEMS`).
- `promote_alternative_item(p_item_id)`: la alternativa pasa a principal (`alternative_of_item_id = NULL`) y la principal original se retira con motivo `Reemplazada por alternativa`. Las demás alternativas de esa principal pasan a colgar de la promovida.

Fechas, producto y pasajeros no se editan (clarificación 3): se retira la línea y se agrega otra. Cada ajuste deja un evento en el historial (R-007). Si había una excepción de cotización (R-008), se invalida.

Validaciones de línea (`resolve_pre_reservation_item`, interna): el producto debe ser `active` y el complemento `is_active`, ambos de la organización (`ITEM_NOT_BOOKABLE`). `start_date` no puede ser anterior a hoy en `America/Bogota` (`TRAVEL_DATE_IN_PAST`, mismo criterio que `capture_request_core`). Además `end_date >= start_date` (`INVALID_DATE_RANGE`); un alojamiento exige `end_date > start_date`, es decir, al menos una noche. Rangos: `adults` 1–99, `children` 0–99, `quantity` 1–99. Máximo 30 líneas por pre-reserva (`VALIDATION_ERROR`).

**Rationale**: Las líneas inmutables conservan intacto el historial de verificación: un resultado nunca queda asociado a fechas que cambiaron después. Una tabla con autorreferencia es más simple que una entidad «opción».

**Alternatives considered**: Editar la línea y reiniciar su verificación (rechazado: el historial pierde contexto). Expandir los paquetes en sus componentes (rechazado: el spec dice que un paquete se verifica como una línea).

---

## R-006 — Proveedor de la línea: instantánea con respaldo manual

**Decision**: Al crear la línea se toma una instantánea del proveedor del producto (`products.provider_id → providers`): `provider_id`, `provider_name`, `provider_phone` y `provider_email`. Si el producto no tiene proveedor, o si la línea es un complemento, el payload puede traer `provider_name`/`provider_phone`/`provider_email` escritos a mano (FR-011). La migración `036` agrega `providers_id_organization_id_key UNIQUE (id, organization_id)`, que no puede fallar porque `id` ya es PK, para que la FK de la línea sea compuesta y fije el tenant.

El panel no llama a ningún proveedor. `provider-contact-links.ts` construye `tel:`, `https://wa.me/<dígitos>` y `mailto:` para abrir las aplicaciones del dispositivo. No hay integración de servidor que configurar: la verificación es humana (spec, Assumptions).

**Rationale**: La instantánea conserva el dato con el que se contactó al proveedor aunque cambie el catálogo. Si a futuro se automatiza la verificación con *channel managers* (mainspec Cap. 31), el adaptador registraría resultados por la misma regla de `record_item_verification` con un actor de sistema, sin tocar el modelo. Hoy no se crea ninguna interfaz de adaptador (Evolution Over Prediction).

**Alternatives considered**: Leer el proveedor en vivo por join (rechazado: el historial mostraría datos que no fueron los usados). Crear una pantalla de gestión de proveedores (fuera de alcance; los proveedores se cargan hoy por seed/SQL, como en 002).

---

## R-007 — Historial de verificación inmutable y auditoría sin datos personales

**Decision**: Tabla `availability_verification_events` en modo append-only. Un trigger rechaza `UPDATE`, `DELETE` y `TRUNCATE`, igual que `request_notes` en `033`. Una fila por acción: `created`, `started`, `outcome`, `withdrawn` o `promoted`. Cada fila guarda el estado anterior y el nuevo, la persona y el medio de contacto del proveedor, la retención, las notas y el actor. La alimentan las RPCs de las historias 1 a 3. La historia 4 agrega vistas de lectura: `availability_verification_history`, con el nombre del actor y la etiqueta de la línea, y `pre_reservation_verification_times`, con los tiempos por pre-reserva para SC-002.

`audit.audit_events` recibe los eventos de negocio: `pre_reservation_created`, `pre_reservation_status_changed`, `pre_reservation_items_changed`, `pre_reservation_assigned`, `availability_recorded`, `pre_reservation_cancelled` y `quotation_override_authorized`. Su metadata lleva solo ids, estados y banderas, como `has_hold` o `override_cleared`. Nunca lleva nombres, teléfonos, correos, notas ni motivos: el mismo criterio de 003.

**Rationale**: El historial operativo, que necesita la persona de contacto y las notas, queda separado de la auditoría de seguridad, que no debe llevar PII. US4 y el mainspec 11.1 («preservar el historial») quedan cubiertos.

**Alternatives considered**: Solo `audit.audit_events` (rechazado: metadata con PII de terceros y lectura restringida a admin). Columnas «último resultado» sin historial (rechazado: incumple US4).

---

## R-008 — Elegibilidad para cotizar y excepción de Administrador (frontera con 005)

**Decision**:

- `authorize_quotation_override(p_pre_reservation_id, p_reason)` usa `require_tenant_admin()`. El motivo es obligatorio, de 1 a 500 caracteres (`OVERRIDE_REASON_REQUIRED`). Una pre-reserva `cancelled` devuelve `PRE_RESERVATION_CLOSED` y una `verified` devuelve `OVERRIDE_NOT_REQUIRED`. La RPC guarda `quote_override_at`, `quote_override_by` y `quote_override_reason`, y emite `quotation_override_authorized` sin el motivo.
- `add_pre_reservation_item`, `withdraw_pre_reservation_item` y `promote_alternative_item` limpian la excepción si cambian las líneas principales (clarificación 5) y lo registran en el evento como `override_cleared: true`.
- `assert_pre_reservation_quotable(p_org uuid, p_pre_reservation_id uuid) → jsonb` es interna (`REVOKE` a `anon` y `authenticated`) y es el **punto de integración para 005**. Primero recalcula el estado. Devuelve `{eligible: true, basis: 'verified'|'override', expires_at}`. Si no es elegible, levanta `PRE_RESERVATION_CLOSED`, `PRE_RESERVATION_EXPIRED` (expirada y sin excepción) o `PRE_RESERVATION_NOT_VERIFIED`.
- La vista `pre_reservation_list` expone `quote_eligible`, calculado con la misma expresión SQL (`status = 'verified' OR (quote_override_at IS NOT NULL AND status <> 'cancelled')`). La UI solo lee ese booleano.

Una excepción vigente también vuelve elegible una pre-reserva `expired`: es la decisión explícita de un Administrador y queda auditada. En 004 no se crea ninguna cotización. El detalle muestra «Lista para cotizar» o el motivo de no elegibilidad, junto con el texto «La cotización se genera desde el módulo de cotizaciones».

**Rationale**: FR-007 se cumple sin adelantar 005. La regla vive en una sola función SQL que 005 llamará dentro de su RPC de creación de cotización.

**Alternatives considered**: Implementar un borrador de cotización (rechazado: es alcance de 005). Calcular la elegibilidad en TypeScript (rechazado: duplicaría la regla).

---

## R-009 — Roles y helpers de autorización

**Decision**:

| Acción | Helper | Roles |
|--------|--------|-------|
| Crear, agregar/retirar/promover líneas, cancelar, asignar operador, barrer expiradas | `require_tenant_member()` (003) | agent, operator, admin |
| Iniciar gestión, registrar resultado | `require_availability_verifier()` (nuevo) | operator, admin |
| Autorizar excepción de cotización | `require_tenant_admin()` (001) | admin |

`require_availability_verifier()` es un envoltorio interno con nombre de dominio que delega en `require_catalog_manager()` (`018`, que exige JWT y perfil vivo con rol operator o admin). No duplica la comprobación. El operador asignado (`assigned_operator_id`) debe ser un `user_profiles` activo con rol `operator` o `admin` de la organización (`ASSIGNEE_NOT_OPERATOR`). Si la pre-reserva no tiene operador, el primer `start_item_verification` o `record_item_verification` asigna al operador que lo ejecuta.

**Rationale**: Se reutilizan los helpers existentes (Composition Over Duplication). RLS y las RPCs son la frontera; `roleGuard('operator')` en `/sales/verification` y `hideForAgent` en el menú son solo una ayuda visual (convención de 010).

**Alternatives considered**: Llamar directamente a `require_catalog_manager()` (rechazado: el nombre es engañoso en este contexto). Permitir que el agente registre resultados (rechazado por la clarificación 5).

---

## R-010 — Lectura por vistas `security_invoker` y escritura solo por RPC

**Decision**: Igual que en 003 (R-009 de 003), las tablas nuevas tienen RLS de solo `SELECT` por `organization_id`. `INSERT`, `UPDATE` y `DELETE` están revocados a `authenticated`, y `anon` no tiene ningún privilegio. Vistas `WITH (security_invoker = true)`:

- `pre_reservation_list`: la lista de pre-reservas y las pre-reservas vinculadas a una solicitud.
- `availability_verification_queue`: una fila por línea vigente de las pre-reservas no canceladas, con `needs_action = (verification_status = 'pending' OR hold_expired)`. Orden por defecto: `start_date`, luego `created_at`.
- `availability_verification_history` y `pre_reservation_verification_times` (historia 4).

Las vistas muestran del cliente solo `first_name`, `last_name` e `is_anonymized`; la cola no expone el correo ni el teléfono del viajero (Data Minimization).

**Rationale**: Es el patrón probado de 003 y no abre tablas a `anon`.

---

## R-011 — Aviso al agente responsable (FR-010)

**Decision**: `PreReservationRealtimeService.watchVerified(organizationId, userId, onVerified)` se suscribe a `UPDATE` de `public.pre_reservations` (`filter: organization_id=eq.<org>`). Avisa cuando `new.status = 'verified'` y `new.responsible_agent_id = userId`, y no repite el aviso para el mismo id. Si Realtime falla (`CHANNEL_ERROR` o `TIMED_OUT`), consulta cada 30 s las pre-reservas propias con `verified_at > última consulta`. El componente `VerifiedNoticeComponent` va dentro del shell (`admin-shell.component.ts`) y muestra «La pre-reserva PRE-00001 quedó totalmente verificada.» con un enlace al detalle. La migración `036` añade `pre_reservations` a `supabase_realtime` solo si la publicación existe, como hace `029`.

**Rationale**: El aviso tiene que llegar aunque el agente esté en otra pantalla. Sin correo ni push (clarificación 2). Si Realtime no está disponible, el aviso llega más tarde pero llega (Graceful Degradation).

**Alternatives considered**: Aviso solo en la lista (rechazado: el agente no lo ve si está en otra pantalla). Correo (fuera del MVP).

---

## R-012 — Referencia legible `PRE-#####`

**Decision**: `reference = 'PRE-' || lpad(next_organization_sequence(org, 'pre_reservation')::text, 5, '0')`, con `UNIQUE (organization_id, reference)`. Es el mismo mecanismo que `SOL-` en 003.

---

## R-013 — Fuera de alcance y puntos de integración

| Tema | Decisión en 004 | Dueño |
|------|-----------------|-------|
| Precio, cotización, vigencia de la cotización | Solo `assert_pre_reservation_quotable` y `expires_at` (005 limita su vigencia a la retención más restrictiva) | 005 |
| Reserva confirmada y bloqueo de inventario | No se bloquea inventario. Una pre-reserva nunca se convierte en reserva | 006 |
| Métricas de horas hábiles | 004 guarda las marcas de tiempo y expone las horas transcurridas. El cálculo en horas hábiles queda para analítica | 008 |
| Automatización con proveedores / channel managers | No se implementa. El punto de integración es la regla de `record_item_verification` (R-006) | Cap. 31 |
| Gestión de proveedores en el panel | No se implementa. Se usan los `providers` existentes | 002 (futuro) |
| Anonimización del cliente | La pre-reserva no guarda PII del viajero, así que `anonymize_customer` no cambia | 003 |

---

## Resumen de decisiones

| ID | Decisión | Impacto principal |
|----|----------|-------------------|
| R-001 | Capacidad `core/pre-reservations`, pantallas bajo `/sales/*`, cola solo para operador/admin | Navegación / módulos |
| R-002 | Conversión atómica por núcleo interno; `set_request_status` intacto | Frontera con 003 |
| R-003 | Estado global derivado por una única función SQL y persistido | Consistencia |
| R-004 | Barrido idempotente al leer, en lugar de `pg_cron` | Expiración |
| R-005 | Líneas inmutables, alternativas por autorreferencia, ajustes por RPC | Modelo / historial |
| R-006 | Instantánea del proveedor y enlaces de contacto del dispositivo | Integración humana |
| R-007 | Historial append-only separado de la auditoría sin PII | Trazabilidad / privacidad |
| R-008 | Elegibilidad en SQL y excepción de administrador invalidable | Frontera con 005 |
| R-009 | `require_tenant_member` / `require_availability_verifier` / `require_tenant_admin` | Seguridad |
| R-010 | RLS de solo lectura y vistas `security_invoker` | Seguridad |
| R-011 | Aviso global en el shell por Realtime, con sondeo de respaldo | FR-010 |
| R-012 | Referencia `PRE-#####` | UX |
| R-013 | Puntos de integración explícitos con 005, 006 y 008 | Alcance |
