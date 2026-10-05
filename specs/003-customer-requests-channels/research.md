# Research: 003-customer-requests-channels

**Date**: 2026-10-04 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Decisiones técnicas para la captación multicanal y la gestión de clientes, revisadas contra el código actual (features 001, 002, 009 y 010 implementadas; última migración `027_public_catalog_seed.sql`). Sustituye el borrador del 2026-09-09.

**Correcciones respecto al borrador anterior**:
- Las migraciones `022`–`028` del borrador chocaban con las de 009; esta feature empieza en `028`.
- El borrador ponía `CHECK (travel_start_date >= CURRENT_DATE)` en la tabla. Un CHECK con `CURRENT_DATE` no es inmutable: invalida filas antiguas en restores y updates. La regla se valida solo al crear la solicitud (R-010).
- El borrador normalizaba el teléfono en la Edge Function (`libphonenumber-js`) y además en SQL: dos autoridades para la misma regla. Ahora hay una sola, en SQL (R-004).
- El borrador creaba una ruta pública Angular `/solicitar`. 009 estableció que el sitio público es una aplicación externa que consume `get_public_site`; el formulario vive allí (R-001).
- El borrador colgaba las pantallas de `/customers` y `/requests` con enlaces en el dashboard. 010 prohíbe duplicar el menú en el dashboard; las pantallas entran al shell por el grupo «Comercial» (R-008).

---

## R-001 — Canal web: RPC pública anónima consumida por el sitio externo

**Decision**: El sitio público externo (`https://www.cartagenatailoredtravel.com/`, consumidor de `get_public_site` según 009 R-004/R-005) llama por PostgREST con la anon key a `public.submit_public_request(p_organization_id uuid, p_payload jsonb)`, `SECURITY DEFINER`, con `GRANT EXECUTE ... TO anon`. Las tablas siguen sin ningún privilegio para `anon`. La RPC delega en el núcleo compartido `capture_request_core` (R-005/R-006) y devuelve `{ reference, deduplicated }` — nunca IDs internos de cliente.

**Rationale**: Es exactamente el contrato que el sitio ya usa para leer (`get_public_site(p_organization_id)`), así que el consumidor no necesita un segundo mecanismo. Toda la regla de negocio queda en SQL, testeable en el harness Docker sin Edge Runtime. 007 (CTA con producto preseleccionado) y 009 FR-029 (agotado no acepta solicitudes) se cumplen con el mismo `public_slug` que devuelve `get_public_site`.

**Alternatives considered**:
- *Edge Function `capture-request` con `service_role`* (borrador anterior): rechazada para el MVP. Agrega un salto de red y un despliegue sin aportar reglas: la validación sería la misma RPC. Queda como evolución si se agrega captcha (R-002); el payload no cambia.
- *Ruta pública en Angular*: rechazada. Contradice 009 ("no se reescribe esa página dentro de Angular") y duplicaría la UI del sitio.
- *Política RLS INSERT para `anon`*: rechazada. Expone tablas con PII y no permite matching ni dedup atómicos.

---

## R-002 — Controles anti-abuso del canal público sin captcha

**Decision**: `submit_public_request` aplica, en este orden: tamaño del payload (≤ 16 KB, ≤ 10 ítems, textos acotados), honeypot (`payload.website` debe venir vacío; si no, `VALIDATION_ERROR` sin persistir), consentimiento explícito (`privacy_consent = true`, si no `CONSENT_REQUIRED`), organización existente con `status = 'active'` (inexistente o no activa → `VALIDATION_ERROR`, sin revelar cuál de las dos), y *throttling* en base de datos: como máximo 5 solicitudes web por hora por email o teléfono normalizado y 200 por hora por organización (`RATE_LIMITED`). El *idempotency key* (R-006) no cuenta para el límite.

**Rationale**: Sin Edge Function no hay IP confiable ni captcha; el throttling por contacto y por organización cubre el abuso más probable (reenvíos y spam dirigido) y es determinista y testeable. Los límites son constantes en la función (convención sobre configuración); si un tenant los necesita distintos se moverán a `organizations.settings`.

**Alternatives considered**:
- *Throttling por IP leyendo `request.headers`*: rechazado. `x-forwarded-for` es falsificable desde el cliente si no pasa por un proxy de confianza, y guardar IPs agrega PII.
- *Captcha (Turnstile/hCaptcha) ya*: diferido. Exige secreto de servidor y por tanto una Edge Function delante; se documenta como riesgo y evolución.

---

## R-003 — Ítems de interés: ficha pública en web, producto en captura asistida

**Decision**: `customer_request_items` guarda `product_id` (FK compuesta a `products`) o `free_text`, más `public_slug` como instantánea cuando el ítem llegó por la web. En `submit_public_request` cada ítem trae `public_slug`; se resuelve contra `public_listings` de la misma organización y debe estar `status = 'published'`, `sold_out = false` y su producto `active`. Si no, la solicitud completa se rechaza con `LISTING_NOT_AVAILABLE` (009 FR-029/SC-010). El visitante también puede enviar un interés libre (`interest_text`) sin producto; se guarda como un ítem con `free_text`. En `create_assisted_request` el agente elige `product_id` de productos `active` de su organización (puede elegir un agotado: el agente gestiona alternativas) o escribe texto libre.

**Rationale**: Reutiliza la identidad pública ya existente (no se inventa un catálogo paralelo) y mantiene la regla de agotado en el mismo lugar de verdad (`public_listings.sold_out`). El `public_slug` instantáneo conserva lo que el visitante vio aunque la ficha cambie después.

**Alternatives considered**:
- *Recibir `product_id` desde el sitio*: rechazado. `get_public_site` no expone IDs internos y no debe empezar a hacerlo.
- *Ítem obligatorio*: rechazado. Muchos leads describen un viaje a medida sin producto.

---

## R-004 — Normalización de teléfono a E.164 en SQL (autoridad única)

**Decision**: `public.normalize_phone_e164(p_raw text, p_default_country_code text)` (`IMMUTABLE`): elimina espacios, guiones, puntos y paréntesis; `+NNN…` o `00NNN…` se toman como internacionales; en otro caso se quita un `0` inicial (prefijo troncal) y se antepone el código de país por defecto de la organización, leído de `organizations.settings ->> 'default_phone_country_code'` con valor por defecto `'57'` (mismo patrón que `default_currency` en 017). El resultado debe cumplir `^\+[1-9][0-9]{7,14}$`; si no, `INVALID_PHONE`. Los números de WhatsApp (que Meta entrega como dígitos sin `+`) pasan por la misma función con prefijo `+`. El email se normaliza con `public.normalize_email(text)` (`lower(btrim())`, formato básico `^[^@\s]+@[^@\s]+\.[^@\s]+$`, si no `INVALID_EMAIL`).

**Rationale**: Una sola implementación para web, captura asistida y WhatsApp (Constitución: "every rule SHALL have a single authoritative implementation"). Sin dependencias nuevas. La agencia opera en Colombia con clientes internacionales que escriben con `+`; el caso nacional cubre los móviles colombianos de 10 dígitos.

**Alternatives considered**:
- *`libphonenumber-js` en Edge Function* (borrador): rechazado. Obligaría a pasar también la captura asistida por la Edge Function o a duplicar la regla en SQL.
- *Validación por plan de numeración de cada país*: rechazado para el MVP; la complejidad no se justifica. Riesgo aceptado: números nacionales de otros países sin `+` se interpretan con el código por defecto.

---

## R-005 — Matching de cliente sin sobrescribir ni fusionar

**Decision** (clarificación 2026-10-04): `match_or_create_customer(org, contact)` busca primero por `email` normalizado y luego por `phone_e164`, solo entre clientes no anonimizados de la organización.
- **Sin coincidencia**: crea el cliente.
- **Con coincidencia**: completa solo campos vacíos del perfil (`last_name`, `email`, `phone_e164`, `country_code`) si el valor no pertenece ya a otro cliente; nunca sobrescribe un valor existente.
- **Conflicto** (email apunta a A y teléfono a B, o nombre/email/teléfono enviados distintos de los del perfil): vincula a A (o al encontrado por teléfono si no hubo email), marca `customer_requests.contact_review_required = true` y guarda lo enviado en `customer_requests.submitted_contact` (jsonb).

Unicidad: `UNIQUE (organization_id, email)` y `UNIQUE (organization_id, phone_e164)` parciales (`WHERE ... IS NOT NULL`). Las columnas ya se guardan normalizadas, por eso no hace falta índice por expresión.

**Rationale**: Un visitante anónimo que escribe el email de otra persona no puede alterar su perfil (Trust Nothing). La marca de revisión deja la decisión a un humano. El historial queda siempre vinculado (SC-002).

**Alternatives considered**:
- *Actualizar el perfil con lo último recibido*: rechazado por seguridad e integridad.
- *Fusión automática A+B*: rechazada. No determinista y afecta historial; una fusión manual puede llegar en otra feature.
- *Match difuso por nombre*: rechazado.

---

## R-006 — Deduplicación e idempotencia

**Decision**: Dentro de `capture_request_core`:
1. Si llega `idempotency_key` (uuid) y existe una solicitud con `(organization_id, idempotency_key)`, se devuelve esa solicitud con `deduplicated = true`. `UNIQUE (organization_id, idempotency_key) WHERE idempotency_key IS NOT NULL` lo garantiza ante concurrencia (se captura `unique_violation` y se relee).
2. Si no, se calcula `dedup_fingerprint` = `md5` de canal + `customer_id` + fechas + pasajeros + ítems ordenados + texto de interés normalizado. Si existe una solicitud con la misma huella de la misma organización creada hace ≤ 2 minutos, se devuelve con `deduplicated = true`.

El sitio externo debe generar un `idempotency_key` por montaje de formulario (documentado en el contrato).

**Rationale**: Cubre doble clic, reintento de red y pestañas duplicadas (edge case del spec) de forma determinista. La huella permite aplicar la ventana sin comparar JSON en caliente.

**Alternatives considered**:
- *Solo deshabilitar el botón*: insuficiente.
- *UNIQUE duro por cliente+canal*: rechazado; impediría solicitudes legítimas posteriores.

---

## R-007 — WhatsApp: adaptador aislado + captura manual + simulación local

**Decision** (clarificación 2026-10-04):
- **Captura manual asistida**: pantalla `/sales/requests/new?channel=whatsapp` que llama a `create_assisted_request` (cualquier colaborador).
- **Adaptador**: Edge Function `supabase/functions/whatsapp-inbound/index.ts` (`verify_jwt = false`).
  - `GET`: handshake de verificación de Meta (`hub.mode=subscribe`, `hub.verify_token == WHATSAPP_VERIFY_TOKEN` → devuelve `hub.challenge`; si no, 403).
  - `POST`: si falta `WHATSAPP_APP_SECRET` → `503 { code: 'CHANNEL_NOT_CONFIGURED' }`. Verifica `X-Hub-Signature-256` (HMAC-SHA256 del cuerpo crudo, comparación en tiempo constante) → si falla `401`. Si es válida, llama con `service_role` a `public.ingest_whatsapp_webhook(p_payload jsonb)` y responde `200` con el resumen (Meta reintenta ante no-2xx; los reintentos son idempotentes).
  - No registra cuerpos ni teléfonos en logs.
- **Parseo en SQL**: `ingest_whatsapp_webhook` recorre `entry[].changes[].value`, resuelve el tenant por `metadata.phone_number_id` en `channel_connections` (`provider = 'meta_cloud'`, `status = 'active'`), y por cada `messages[]` de tipo `text` (otros tipos se guardan con cuerpo `[mensaje no soportado: <tipo>]`): inserta en `inbound_messages` con `UNIQUE (provider, provider_message_id)` (reintento → se omite), normaliza `from`, vincula o crea el cliente por teléfono (nombre = `contacts[].profile.name` o «Contacto WhatsApp»), y adjunta el mensaje a la solicitud abierta más reciente del cliente por canal `whatsapp` (`received`/`in_review`) o crea una nueva vía `capture_request_core` (`special_requirements` = primer mensaje). `phone_number_id` desconocido → se ignora y se cuenta en el resumen (`ignored`).
- **Simulación local sin credenciales**: `channel_connections` sembrada para la organización demo con `provider = 'meta_cloud'`, `external_account_id = 'local-dev-phone-number-id'`; `supabase/functions/whatsapp-inbound/fixtures/text-message.json`; `scripts/simulate-whatsapp-inbound.sh` firma el fixture con `WHATSAPP_APP_SECRET` local (de `supabase/functions/.env`, ignorado por git; plantilla `.env.example`) y lo envía a `http://127.0.0.1:54321/functions/v1/whatsapp-inbound`. Alternativa sin Edge Runtime: la suite `whatsapp_intake_test.sql` invoca `ingest_whatsapp_webhook` con el mismo fixture.
- **Fuera de alcance**: mensajes salientes, plantillas, medios, estados de entrega, pantalla de administración de conexiones (se gestionan por SQL/seed en el MVP).

**Rationale**: Frontera explícita (Third-Party Integrations, Portability): solo la Edge Function conoce la firma de Meta y solo `ingest_whatsapp_webhook` conoce la forma del JSON; el dominio recibe contacto + texto. Sin secretos todo se prueba localmente con el mismo código.

**Alternatives considered**:
- *Solo manual* (clarificación 2026-09-09): sustituida; el usuario pidió diseñar la integración detrás de una frontera.
- *Parsear el webhook en TypeScript*: rechazado. No hay runner Deno en el repo y quedaría sin pruebas automáticas; en SQL lo cubre el harness.
- *BSP intermedio (Twilio, 360dialog)*: diferido; el adaptador es el punto de reemplazo.

---

## R-008 — Ubicación en el panel: grupo «Comercial» bajo `/sales/*`

**Decision**: Nuevo grupo de menú `{ id: 'sales', label: 'Comercial', path: null, minRole: 'agent' }` con hijos «Solicitudes» (`/sales/requests`) y «Clientes» (`/sales/customers`), ambos `minRole: 'agent'`, insertado en `NAV_TREE` justo después de «Dashboard». Rutas hijas del shell autenticado con `canActivate: [roleGuard('agent')]`; alta asistida y ficha de cliente con `canDeactivate: [unsavedChangesGuard]`. `/sales` redirige a `/sales/requests`. Listados con `DataTableComponent`, 20 filas, estado en query string; `ListQuery` se amplía con `channel` y `assignee`. Detalles y alta con secciones `.section` (`<h2>` por sección, `.incomplete` para faltantes), igual que 010 FR-018/FR-023.

**Rationale**: `/settings/*` es administración y `/cms/*` es catálogo/contenido; la gestión comercial es una tercera capacidad y la primera tarea diaria de los agentes, por eso va primero tras el dashboard. `/sales` es corto, en inglés como `/settings` y `/cms`, y admite crecer con `/sales/pre-reservations` (004) y `/sales/quotations` (005). Todos los roles internos comparten la bandeja (supuesto del spec); la anonimización se oculta a no-admins con `hasRoleAtLeast(role, 'admin')` y además la bloquea `require_tenant_admin()`.

**Impact on 010**: cambia el orden de FR-002 de 010 (Dashboard → Comercial → Configuración → CMS) y la tabla de visibilidad de su `ui-contracts.md`; se actualizan `nav-items.spec.ts` y la documentación (tarea final).

**Alternatives considered**:
- *Agregar «Solicitudes» y «Clientes» dentro de CMS*: rechazado; mezcla contenido público con datos personales.
- *Grupo «Comercial» al final del menú*: viable sin enmendar 010, pero esconde la tarea diaria detrás de configuración y catálogo.
- *Rutas en español (`/comercial`)*: rechazado por consistencia con `/settings` y `/cms`.

---

## R-009 — Escrituras solo por RPC; lectura por RLS y vistas `security_invoker`

**Decision**: Todas las tablas nuevas: `ENABLE ROW LEVEL SECURITY`, `REVOKE ALL ... FROM anon`, `REVOKE INSERT, UPDATE, DELETE ... FROM authenticated`, y una única política `tenant_isolation_select` (`organization_id = (auth.jwt() ->> 'organization_id')::uuid`). Las escrituras pasan por RPCs `SECURITY DEFINER` con `SET search_path = ''` que llaman a un helper nuevo `public.require_tenant_member()` (JWT + perfil vivo activo de cualquier rol, mismo patrón que `require_catalog_manager()`), o a `require_tenant_admin()` para anonimizar. Los listados leen vistas `customer_request_list` y `customer_list` creadas con `WITH (security_invoker = true)` para que apliquen el RLS de las tablas base. Se agrega `UNIQUE (id, organization_id)` a `user_profiles` para que `assigned_to` y `author_id` usen FKs compuestas que fijan el tenant.

**Rationale**: Cada escritura necesita normalización, auditoría o validación de transición; con RPCs no hay camino directo que la salte. Las vistas resuelven el join cliente/responsable y la búsqueda en una sola consulta paginada.

**Alternatives considered**:
- *Políticas INSERT/UPDATE por rol* (patrón de catálogo): rechazado aquí; la actualización directa de `status` o `email` saltaría la máquina de estados y la normalización.

---

## R-010 — Máquina de estados, frontera con 004 y marcas de tiempo para 008

**Decision** (clarificación 2026-10-04): `set_request_status(p_request_id, p_status, p_reason)` acepta solo `received → in_review`, `received → discarded`, `in_review → discarded`. `discarded` exige `p_reason` (1–500 caracteres, `DISCARD_REASON_REQUIRED`) y es terminal. `p_status = 'pre_reservation'` → `PRE_RESERVATION_REQUIRES_CONVERSION`. Cualquier otra → `INVALID_STATUS_TRANSITION`. Marcas: `first_handled_at` (primera salida de `received`), `closed_at` (`discarded` o `pre_reservation`), `assigned_at` (última asignación). La fecha de inicio de viaje no puede ser pasada solo al crear (`TRAVEL_DATE_IN_PAST`), y `travel_end_date >= travel_start_date` sí es CHECK de tabla.

**Contrato para 004** (documentado, no implementado): su RPC de conversión, en la misma transacción que crea la primera pre-reserva, hará `UPDATE customer_requests SET status = 'pre_reservation', closed_at = now(), first_handled_at = coalesce(first_handled_at, now())` desde `received` o `in_review`, y emitirá `request_status_changed`. Pre-reservas posteriores de la misma solicitud no cambian el estado. En `pre_reservation` la solicitud queda de solo lectura en 003 salvo notas.

**Rationale**: Estados explícitos (Constitución); evita un estado "En Pre-Reserva" huérfano sin pre-reserva real. Las marcas cubren los tiempos de 008 sin depender del log de auditoría.

**Alternatives considered**:
- *Permitir `pre_reservation` manual*: rechazado (clarificación).
- *Tabla de historial de estados*: diferida; la auditoría ya registra cada cambio con `from`/`to`.

---

## R-011 — Aviso de solicitudes nuevas (SC-004)

**Decision**: La migración `029` agrega `public.customer_requests` a la publicación `supabase_realtime` dentro de un bloque `DO` que solo actúa si la publicación existe (el harness Docker no la tiene). `RequestRealtimeService` abre un canal `postgres_changes` `INSERT` con filtro `organization_id=eq.<org>` mientras `RequestListComponent` está montado; cada evento solo dispara un `refresh()` de la página actual (el contenido del evento no se usa en la UI) y un aviso «Llegó una solicitud nueva». Si el canal pasa a `CHANNEL_ERROR` o `TIMED_OUT`, el componente vuelve a una consulta cada 10 s mientras siga abierto.

**Rationale**: Capacidad gestionada ya incluida en Supabase. Realtime aplica el RLS de SELECT al suscriptor. El respaldo por consulta garantiza el objetivo de 10 s aunque Realtime no esté disponible (por ejemplo, en local sin el servicio).

**Alternatives considered**:
- *Solo consulta periódica*: aceptable, pero carga innecesaria cuando Realtime funciona.
- *Correo/push*: fuera de alcance (clarificación).

---

## R-012 — Privacidad: consentimiento, anonimización y auditoría sin PII

**Decision**:
- **Consentimiento**: el canal web exige `privacy_consent = true` y guarda `customer_requests.privacy_consent_at = now()` (Ley 1581 de 2012, Constitución §9 "Consent and Transparency"). En captura asistida, el agente marca que informó el tratamiento de datos (`privacy_notice_given`), que se guarda igual.
- **Anonimización** `anonymize_customer(p_customer_id, p_reason)` (`require_tenant_admin()`): en `customers` pone `first_name = 'Cliente anonimizado'` y `NULL` en `last_name`, `email`, `phone_e164`, `document_type`, `document_number`, `country_code`; `is_anonymized = true`, `anonymized_at`. En sus solicitudes: `submitted_contact = NULL`, `special_requirements` → `'[anonimizado]'` si no era nulo, y `free_text` de sus ítems → `'[anonimizado]'`. En `inbound_messages`: `body = '[anonimizado]'`, `from_phone_e164 = NULL`, `profile_name = NULL`. Se conservan canal, fechas, pasajeros, ítems de catálogo, estados y notas internas del equipo. Es irreversible. Evento `customer_anonymized` con metadata `{ reason_provided: true, requests_scrubbed: n }`.
- **Auditoría sin PII**: `request_received` (`{ channel, deduplicated }`), `request_assigned` (`{ from, to }` IDs de colaboradores), `request_status_changed` (`{ from, to }`), `customer_updated` (`{ fields: [...] }` solo nombres de campos), `customer_anonymized`.
- Clientes anonimizados no participan del matching (sus claves son NULL); un contacto nuevo con el mismo email crea un cliente nuevo.

**Punto de extensión 006**: cuando existan reservas, `anonymize_customer` deberá rechazar clientes con obligaciones contables vigentes; se documenta, no se implementa.

**Alternatives considered**:
- *Borrado físico*: rechazado (clarificación 2026-09-09).
- *Anonimizar también las notas internas*: rechazado; son del equipo y la regla es no escribir PII en ellas (indicado en la UI). Riesgo documentado.

---

## R-013 — Referencia legible por organización

**Decision**: Tabla `organization_sequences (organization_id, scope, last_value)` y función `next_organization_sequence(p_org, p_scope)` (`UPDATE ... RETURNING` con bloqueo de fila; inserta la fila si falta). `customer_requests.reference = 'SOL-' || lpad(n, 5, '0')`, `UNIQUE (organization_id, reference)`. La web recibe y muestra esa referencia.

**Rationale**: US1 pide un identificador único para la confirmación; un UUID no es comunicable por teléfono. La misma tabla servirá a 005 (`ReferenciaConsecutiva` de cotizaciones) y 006 (localizador) con otros `scope`.

**Alternatives considered**:
- *Secuencia global*: rechazada; filtra el volumen entre tenants.
- *Sin referencia*: rechazada.

---

## R-014 — Puntos de extensión para 004–008 (sin implementarlos)

| Feature | Qué consume de 003 | Lo que 003 deja listo |
|---------|-------------------|------------------------|
| 004 Pre-reserva | Solicitud origen, cliente, ítems | `UNIQUE (id, organization_id)` en `customer_requests` para FK compuesta; estado `pre_reservation` y contrato de transición (R-010); ítems con `product_id`. |
| 005 Cotización | Cliente | `UNIQUE (id, organization_id)` en `customers`; `organization_sequences`. |
| 006 Reserva | Cliente titular | Bloqueo futuro en `anonymize_customer` (R-012). |
| 007 Sitio público | CTA a formulario | `submit_public_request` por `public_slug`. |
| 008 Analítica | Embudo y tiempos por canal | `channel`, `created_at`, `first_handled_at`, `assigned_at`, `closed_at`, índices por `(organization_id, channel)`. |

---

## Resumen de decisiones

| ID | Decisión | Impacto principal |
|----|----------|-------------------|
| R-001 | Web por RPC anónima `submit_public_request` desde el sitio externo | Integración / seguridad |
| R-002 | Honeypot, límites, consentimiento y throttling por contacto/org | Abuso |
| R-003 | Ítems por `public_slug` (web) o `product_id` (asistido); agotado rechaza | Consistencia con 009 |
| R-004 | E.164 en SQL con código de país de la organización | Calidad de dato |
| R-005 | Match email → teléfono; completar sin sobrescribir; marca de revisión | Integridad / seguridad |
| R-006 | `idempotency_key` + huella con ventana de 2 min | Doble envío |
| R-007 | WhatsApp: Edge Function con firma → parseo SQL; manual + simulación | Frontera de integración |
| R-008 | Grupo «Comercial» `/sales/*` tras Dashboard | Navegación |
| R-009 | RLS solo lectura; escrituras por RPC; vistas `security_invoker` | Seguridad |
| R-010 | Transiciones manuales acotadas; `pre_reservation` solo por 004 | Ciclo de vida |
| R-011 | Realtime + respaldo por consulta cada 10 s | SC-004 |
| R-012 | Consentimiento, anonimización con limpieza de texto libre, auditoría sin PII | Privacidad |
| R-013 | Referencia `SOL-00001` por organización | UX / 005–006 |
| R-014 | Puntos de extensión documentados | Evolución |
