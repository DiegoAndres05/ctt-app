# Revisión de alineación con el constitution

**Proyecto:** ctt-app (CTT Admin)
**Fecha:** 23 de octubre de 2026
**Alcance:** solo lectura. Este archivo es el único cambio de la rama. No se modificó código de la aplicación.
**Constitution evaluado:** `.specify/memory/constitution.md` (3.798 líneas, 16 capítulos). No tiene número de versión, fecha de ratificación ni registro de enmiendas dentro del propio documento.

## Veredicto general

El constitution existe y el producto implementado sigue una parte sustancial de su dirección técnica y de seguridad: Angular 22 con Signals y Signal Forms, Supabase/PostgreSQL, RLS por organización, RBAC de tres roles, auditoría inmutable y un monolito modular. Esa base es real y, en lo que se pudo ejecutar, compila y pasa las pruebas de frontend.

El proyecto **no está alineado** con el constitution como norma de gobierno. La jerarquía documental que el propio texto exige está incompleta y, además, el capítulo 3 y el capítulo 16 se contradicen. Las reglas de negocio viven dentro de PostgreSQL, en contra del mandato de independencia del dominio respecto de la base de datos. WordPress, exigido como CMS headless, no existe en el repositorio. Reservas confirmadas, analítica y el CMS editorial están especificados y no construidos, mientras el contrato de navegación y `AGENTS.md` ya los presentan como parte del sistema. Observabilidad, retención, clasificación de datos, ciclo de vida del tenant y CI no tienen implementación.

Ninguna feature puede declararse «Done» según las 16 puertas del capítulo 15.

### Conteo

Se evaluaron **148 requisitos** normativos (principios, reglas SHALL/SHOULD verificables y las 16 puertas del Definition of Done). Los párrafos puramente retóricos se absorbieron en el requisito del capítulo al que pertenecen.

| Veredicto | Cantidad |
| --- | ---: |
| Cumple | 51 |
| Parcial | 59 |
| No cumple | 28 |
| No verificable | 10 |
| **Total** | **148** |

## Qué se ejecutó y qué no

Entorno de esta revisión: Node `v22.23.4` (el `package.json` pide `>=20.19.0`). El npm del PATH es `10.9.9`; el repositorio declara `packageManager: npm@11.6.2` y `engines.npm >= 11`. `npm ci` instaló 515 paquetes igualmente.

| Comando | Resultado |
| --- | --- |
| `npm ci` | Correcto. `npm audit --omit=dev`: 2 altas (`@angular/router`, `zod` transitivo). Árbol completo: 16 avisos, 3 críticos, todos en la cadena de build (`piscina`, `vite`, `proxy-addr`). |
| `npm run build` | Correcto. Aviso de presupuesto: el chunk inicial pesa 521,66 kB y el warning de `angular.json` está en 500 kB. El tope de error (1 MB) no se supera. |
| `npm test -- --watch=false` | 16 archivos, 128 pruebas, todas correctas. |
| `npm run lint` | Sin hallazgos. |
| `npm run format:check` | Sin hallazgos. |
| `./supabase/tests/run-sql-tests.sh` | No ejecutado. Docker no está instalado en este entorno. El script exige un contenedor Postgres 17. |
| App en navegador contra Supabase | No ejecutado. `src/environments/environment.ts` trae placeholders (`SUPABASE_URL_PLACEHOLDER`). `environment.development.ts` apunta a `http://127.0.0.1:54321` con la anon key pública de la demo local de Supabase. No hay stack local levantado y no se usaron credenciales de producción. |

Las 33 suites SQL (RLS, auth, catálogo, clientes, pre-reservas, cotizaciones) están escritas y no quedaron demostradas en esta revisión. El veredicto de correctitud de esas reglas es de código, no de ejecución.

## 1. Inventario de funcionalidades reales

### 1.1 Forma del sistema

Un solo frontend Angular (`src/`) y un backend Supabase: 48 migraciones SQL (~14.200 líneas), 123 funciones (114 `SECURITY DEFINER`), 76 políticas RLS, 43 triggers y 2 Edge Functions. No hay microservicios, bus de eventos ni segundo deployable de negocio. El `Dockerfile` empaqueta solo el frontend sobre nginx.

Capacidades con código, pruebas y pantalla:

| Capacidad | Spec | Estado en el repo |
| --- | --- | --- |
| Identidad, tenant, RBAC, auditoría, alta de agencia | 001 | Implementada. Tareas 51/51. Evidencia en `specs/001-auth-tenant-access/validation-evidence.md`. |
| Catálogo y tarifas | 002 | Implementada. Tareas 46/46. |
| Solicitudes, WhatsApp, privacidad | 003 | Implementada. Tareas 59/59. |
| Pre-reservas y verificación de cupos | 004 | Implementada en código. Tareas 47/48. Falta T048 (prueba manual) y faltan `plan.md`, `data-model.md`, `contracts/` y `quickstart.md`, que el propio `tasks.md` declara prerrequisito. |
| Cotizaciones y enlace público | 005 | Implementada. Tareas 41/41. Mismos artefactos de diseño ausentes. |
| Fichas públicas y cutover | 009 | Implementada. Tareas 46/46. |
| Shell, navegación, redirects | 010 | Implementada. Tareas 37/37. El contrato de UI se adelantó a reservas que no existen. |
| Reservas confirmadas, depósito, órdenes de servicio | 006 | Solo `spec.md` y checklist. Sin plan, tareas, tablas, rutas ni `docs/modules/reservations.md`. |
| CMS editorial WordPress y portal público | 007 | Solo `spec.md` y checklist. |
| Analítica y embudo comercial | 008 | Solo `spec.md` y checklist. El visor de auditoría de 001 cubre una parte del user story 4. |

`README.md` (línea 3) describe el repositorio como la implementación de 001. El árbol contiene 001–005, 009 y 010.

### 1.2 Rutas

Definidas en `src/app/app.routes.ts`.

Públicas:

- `/login`, `/register`
- `/q/:token` — propuesta comercial sin sesión (`get_public_quotation`)

Autenticadas, dentro de `AdminShellComponent` (`authGuard` + `passwordChangeGuard`):

- `/change-password`
- `/dashboard`
- `/sales/requests`, `/new`, `/:id` — rol mínimo `agent`
- `/sales/pre-reservations`, `/new`, `/:id` — `agent`
- `/sales/quotations`, `/new`, `/:versionId` — `agent`
- `/sales/verification` — `operator`
- `/sales/customers`, `/:id` — `agent`
- `/settings/users`, `/new`, `/:id`; `/settings/roles`; `/settings/audit` — `admin`
- `/cms/experiences`, `/cms/accommodations`, `/cms/packages` — lectura `agent`, alta `operator`
- `/cms/settings` (categorías, categorías públicas, add-ons) — `operator`; `/cms/settings/cutover` — `admin`

Redirects de compatibilidad: `/users`, `/audit`, `/catalog/*` hacia las rutas nuevas (`app.routes.ts` líneas 405–421).

No existen `/sales/reservations`, `/sales/reservations/new` ni `/sales/reservations/:id`. El contrato `specs/010-admin-layout-navigation/contracts/ui-contracts.md` líneas 25–27 y 128–130 las declara, y la línea 114 marca «Comercial / Reservas» visible para los tres roles. El mismo contrato no menciona pre-reservas ni verificación, que sí están en `src/app/shared/layout/nav-items.ts` líneas 38–56.

La pantalla de roles (`src/app/features/users/roles/roles-matrix.component.ts` líneas 16–44) describe dashboard, usuarios, catálogo y publicación. Omite solicitudes, pre-reservas, cotizaciones, clientes y verificación. El texto del agente («Consulta experiencias… No crea ni publica») no refleja que un agente crea solicitudes, pre-reservas y cotizaciones.

El dashboard (`src/app/features/dashboard/dashboard.component.ts` líneas 5–16) saluda al colaborador y declara que los indicadores llegarán después.

No hay formulario público de solicitud dentro de esta app. `submit_public_request` está pensada para un sitio externo (`supabase/migrations/031_us1_public_request_intake.sql` líneas 1–4). Ese sitio no está en el repositorio.

### 1.3 Roles y permisos

Enum `public.app_role`: `admin`, `operator`, `agent`, jerárquicos (`supabase/migrations/001_create_enums.sql` líneas 9–10). El rango se replica en `src/app/core/auth/models/user.model.ts` líneas 34–48. El guard de ruta solo decide qué se pinta (`src/app/core/auth/guards/role.guard.ts` líneas 6–12). La autorización de datos está en RLS y en funciones `require_tenant_admin`, `require_catalog_manager`, `require_tenant_member`, `require_availability_verifier`.

El claim de aplicación viaja en `app_role`, no en `role` (ADR-0002, `supabase/config.toml` líneas 72–75). El alta pública de colaboradores está apagada (`enable_signup = false`, `config.toml` línea 52). `register_agency` solo es ejecutable por `service_role` (`supabase/migrations/010_us5_register_agency.sql` líneas 132–134) y la Edge Function `register-agency` tiene `verify_jwt = false` porque el alta ocurre antes de la sesión (`config.toml` líneas 88–90).

### 1.4 Tablas

36 tablas de negocio y auditoría, más stubs locales de `storage.buckets` y `storage.objects` en `supabase/migrations/026_catalog_media_bucket.sql` líneas 11–23 para poder probar políticas de Storage fuera del stack Supabase.

- Identidad: `organizations`, `user_profiles`, `audit.audit_events`
- Catálogo: `providers`, `products`, `experiences`, `accommodations`, `categories`, `product_categories`, `pricing_schemes`, `add_ons`, `product_addons`, `packages`, `package_items`
- Sitio público: `public_sites`, `public_categories`, `public_listings`, `public_images`, `guest_reviews`, `public_cutover_items`
- Comercial: `customers`, `customer_requests`, `customer_request_items`, `organization_sequences`, `channel_connections`, `inbound_messages`, `request_notes`, `pre_reservations`, `pre_reservation_items`, `availability_verification_events`, `quotation_families`, `quotation_versions`, `quotation_lines`, `quotation_adjustments`, `quotation_responses`, `quotation_defaults`

RLS está habilitado en todas ellas. No hay `FORCE ROW LEVEL SECURITY` en ninguna migración: el owner de la tabla sigue pudiendo saltarse las políticas. Las funciones `SECURITY DEFINER` reautorizan dentro del cuerpo y hacen `REVOKE` a `PUBLIC` antes de un `GRANT` explícito.

No hay tablas de reserva confirmada, pago, voucher, orden de servicio, suscripción, feature flag ni clasificación de datos.

### 1.5 Flujos que el código sostiene

1. Alta de agencia (`register-agency` → `register_agency`) y login con bloqueo server-side (`password_verification_hook`, ADR-0003).
2. Cambio obligatorio de contraseña y relojes de sesión de 8 h de inactividad y 24 h absolutas. Esos dos relojes viven en el navegador (`src/app/core/auth/interceptors/session.interceptor.ts` líneas 12–35). El comentario de las líneas 32–35 dice que no son la frontera: la frontera es el JWT (`jwt_expiry = 3600` en `config.toml` línea 47) y RLS.
3. Administración de colaboradores: crear, cambiar rol, activar o desactivar. Solo admin.
4. Catálogo operativo: productos, experiencias, alojamientos, paquetes, add-ons, categorías, tarifas append-only y override de precio con motivo.
5. Ficha pública bilingüe, galería en Storage, reseñas, agotado y cutover del sitio (`get_public_site`, concedida a `anon` y `authenticated`, `supabase/migrations/025_public_site_read.sql` líneas 244–245).
6. Solicitud asistida (WhatsApp, teléfono, presencial) con casilla de aviso de privacidad (`request-intake.component.ts` líneas 181–185). Intake web anónimo por `submit_public_request`, que rechaza organizaciones que no están `active` (`031_us1_public_request_intake.sql` líneas 45–49).
7. Webhook de Meta: la Edge Function `whatsapp-inbound` verifica `X-Hub-Signature-256` y llama a `ingest_whatsapp_webhook`, concedida solo a `service_role` (`032_us2_whatsapp_intake.sql` líneas 451–452; `supabase/functions/whatsapp-inbound/index.ts` líneas 1–9).
8. Pre-reserva desde una solicitud, cola de verificación humana, alternativas, expiración y elegibilidad para cotizar.
9. Cotización con precio calculado en el servidor, emisión, enlace opaco, aceptación pública sin devolver correo, teléfono ni `customer_id` (`047_us3_quotation_delivery.sql` líneas 110–157).
10. Anonimización de cliente (`anonymize_customer`, `034_us4_customer_privacy.sql` línea 9).
11. Consulta de auditoría solo para admin de la misma organización (`005_create_rls_policies.sql` líneas 92–99). UPDATE, DELETE y TRUNCATE los rechaza `audit.reject_audit_mutation` (`007_create_triggers.sql` líneas 38–58).

### 1.6 Integraciones

- Supabase Auth, PostgREST, Storage y Realtime (pre-reservas escuchan `UPDATE` de `pre_reservations`).
- Meta WhatsApp Cloud API, detrás de la Edge Function. Sin `WHATSAPP_APP_SECRET` la función responde `CHANNEL_NOT_CONFIGURED` y no persiste nada.
- El sitio público consumidor de `get_public_site` y `submit_public_request` se menciona en los specs (cartagena tailored travel) y no está en este repo.
- WordPress: cero código, cero cliente HTTP, cero variable de entorno.

### 1.7 Pruebas presentes

- 16 specs Vitest, concentradas en modelos, guards, payloads y navegación. Una sola pantalla tiene spec de componente (`login.component.spec.ts`).
- 33 archivos `supabase/tests/*_test.sql`.
- El comentario de `supabase/tests/run-sql-tests.sh` líneas 29–32 anuncia cinco suites de reservas (`reservation_confirm_test.sql` y otras). Esos archivos no existen.
- No hay workflow de CI (no hay `.github/`), ni pruebas e2e, ni pruebas de carga ejecutables fuera del probe SQL de catálogo.

## 2. Artefactos de gobierno que el constitution nombra

El capítulo 3 (líneas 385–411) ordena: Constitution → PRD → Domain Model → Use Cases → Technical Architecture → Cross-Cutting Requirements → Development Standards → Implementation Plan → Source Code.

El capítulo 16 (líneas 3641–3651) ordena otra cosa: Constitution → ADRs → PRDs → Technical Specifications → Development Standards → Source Code → Operational Documentation.

| Artefacto exigido | Dónde está | Hueco |
| --- | --- | --- |
| Constitution | `.specify/memory/constitution.md` | Sin versión ni bitácora de enmiendas. ADR-0001 (líneas 12–16) afirma que el texto pasó de Reactive Forms a Signal Forms. |
| PRD | `.specify/mainspec.md` actúa como definición de producto | No está nombrado PRD ni enlazado desde el constitution. |
| Domain Model único | `data-model.md` por feature, y solo en 001, 002, 003, 009 y 010 | 004 y 005, ya implementadas, no lo tienen. |
| Use Cases | Historias dentro de cada `spec.md` | No hay documento de casos de uso. |
| Technical Architecture | `plan.md` de cinco features | No hay arquitectura de plataforma. 004 y 005 no tienen plan. |
| Cross-Cutting Requirements | No existe | Seguridad, privacidad y observabilidad solo están en el constitution. |
| Development Standards | No existe | El constitution (líneas 1463–1464) los declara fuera de su alcance. ADR-0001 líneas 60–64 pide actualizarlos. |
| ADR | `docs/adr/0001`, `0002`, `0003` | Los tres tienen identificador, estado, contexto, decisión, alternativas y consecuencias. No hay ADR para «el dominio vive en PLpgSQL», para el modelo multi-tenant ni para aplazar WordPress. |
| RFC | No hay carpeta ni plantilla | WhatsApp, el CMS comercial y el alta de agencias se implementaron sin RFC. |
| Implementation plans | 001, 002, 003, 009, 010 | 004–008 no. |
| Código | `src/`, `supabase/` | En varias zonas va por delante del contrato (pre-reservas) o por detrás (reservas). |

`AGENTS.md` líneas 19–24 remite a `docs/modules/reservations.md` y a `specs/008-analytics-reporting/plan.md`. Ninguno de los dos archivos existe. El commit `4617093`, titulado «docs(006): reservations module doc…», modifica `AGENTS.md`, un párrafo de `identity-access.md`, el contrato de UI y un comentario del runner SQL. No añade el módulo de reservas.

## 3. Contraste por requisito

La evidencia cita archivo y línea del código o del documento. «No verificable» significa que el requisito es una práctica de personas o de producción y este repositorio no deja evidencia para juzgarlo.

### Capítulo 1 — Propósito y dirección tecnológica

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R01 | Plataforma SaaS de operaciones turísticas: productos, cotizaciones, reservas y clientes | Parcial | Clientes, catálogo, pre-reservas y cotizaciones están en `app.routes.ts` 63–183. Reservas confirmadas: solo `specs/006-reservation-lifecycle/spec.md` línea 9 (estado Draft). |
| R02 | El desarrollo es specification-driven y la documentación es la fuente de verdad | Parcial | Specs 001–010 existen. 004 y 005 se implementaron sin los diseños que `specs/004-prereservation-availability/tasks.md` línea 8 exige. |
| R03 | El MVP debe poder volverse multi-tenant sin rediseño | Cumple | `organizations` y `organization_status` nacen en `001_create_enums.sql` 13 y `002_create_organizations.sql` 5–9. RLS filtra por `organization_id`. |
| R04 | Frontend: Angular, TypeScript, standalone, Signals, Signal Forms | Cumple | `package.json` 20–25 (`@angular/*` 22). `app.ts` 4–8 usa `imports` en el componente (standalone por defecto en Angular 19+). `form()` en los formularios, por ejemplo `login.component.ts` 113. ADR-0001. |
| R05 | Backend: Supabase, PostgreSQL, Auth, Storage, RLS | Cumple | `supabase/config.toml` 1–40. RLS en `002_create_organizations.sql` 31 y en el resto de tablas. Storage en `026_catalog_media_bucket.sql`. |
| R06 | WordPress como CMS headless | No cumple | El constitution lo exige en las líneas 46–47 y 3204–3205. Búsqueda de cliente, configuración o dependencia WordPress: no hay implementación. `specs/007-cms-public-discovery/spec.md` sigue en Draft. |
| R07 | Despliegue compatible con Docker, cloud-first y portable | Parcial | `Dockerfile` 1–14 y `docker-compose.yml` 1–10 contenedorizan el frontend. El backend depende de Auth Hooks y Edge Functions de Supabase (`config.toml` 72–94). |
| R08 | Todo artefacto del proyecto cumple este constitution | Parcial | El código de seguridad se acerca. Faltan los documentos de la jerarquía y hay contradicción interna (R25, R147). |

### Capítulo 2 — Filosofía de ingeniería

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R09 | Ante un trade-off, el valor de negocio va primero | No verificable | No hay actas de decisión que muestren el orden aplicado, fuera de los tres ADR. |
| R10 | La solución más simple que resuelve el problema actual | Parcial | El shape es un monolito. La superficie SQL (123 funciones, componentes como `quotation-editor.component.ts` y `product-editor.component.ts` de decenas de kB en el build) ya concentra mucha complejidad. |
| R11 | Convención sobre configuración | Cumple | Las tareas de 004 y 005 fijan el mismo molde SQL y Angular (`tasks.md` de 004, líneas 27–32). ESLint y Prettier pasan. |
| R12 | Evolucionar de forma incremental; no diseñar para un futuro hipotético | Cumple | No hay microservicios ni billing. La preparación multi-tenant está exigida por el propio capítulo 10, y el esquema la cumple con `organization_id` sin infraestructura extra. |
| R13 | Consistencia sobre adopción de tecnología de moda | Cumple | Un solo frontend y un solo backend. El cambio a Signal Forms quedó en ADR-0001 en lugar de convivir con Reactive Forms. |
| R14 | Decisiones visibles; nada de magia ni supuestos sin documentar | Parcial | Los headers SQL citan el spec. La matriz de roles (`roles-matrix.component.ts` 16–44) no dice lo que las rutas permiten. |
| R15 | La documentación precede a la implementación y se mantiene sincronizada | No cumple | 004 y 005 tienen código y tareas, y no tienen plan, modelo ni contrato. `AGENTS.md` 19–24 apunta a archivos que no existen. `ui-contracts.md` 25–27 describe rutas que `app.routes.ts` no tiene. |
| R16 | Reutilizar antes de duplicar; la lógica de negocio no se duplica | Parcial | El precio de la cotización se calcula en SQL y la UI declara que no suma importes (`specs/005-quotation-proposals/tasks.md` línea 31). Los helpers de test SQL se copian de suite en suite. |
| R17 | Seguridad desde el diseño, no como actividad posterior | Cumple | RLS se activa al crear cada tabla (ejemplo `004_create_audit_schema.sql` 48–50). Los grants nacen cerrados. |
| R18 | La IA acelera y no redefine la arquitectura | Parcial | Hay Spec Kit, specs y ADR. También hay implementación de 004/005 sin los diseños que el proceso exige, y un commit de «docs(006)» que no entrega el módulo. |

### Capítulo 3 — Gobernanza

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R19 | Las especificaciones definen el sistema; el código las implementa | Parcial | 001, 002, 003, 009 y 010 tienen cadena spec → plan → código. 004 y 005 invierten el orden respecto de sus diseños ausentes. |
| R20 | Toda decisión arquitectónica significativa tiene ADR con el formato exigido | No cumple | Tres ADR en `docs/adr/`. No hay ADR del lugar del dominio, del multi-tenant ni de aplazar WordPress. El capítulo 3 líneas 516–537 lo exige para patrones nuevos, infraestructura, seguridad y cambios que cruzan módulos. |
| R21 | Cada cambio significativo responde por qué, quién, qué spec y qué código | Parcial | Los headers de migración citan el spec. El constitution no tiene versión. El commit `4617093` no corresponde con los archivos que su mensaje anuncia. |
| R22 | Existen los documentos de la jerarquía, cada uno con un solo dueño | No cumple | No hay Development Standards, Cross-Cutting Requirements, Domain Model único ni Use Cases. Lista en la sección 2 de este informe. |
| R23 | Un RFC aceptado precede a capacidades nuevas, pagos, idiomas, despliegues o reestructuración del dominio | No cumple | No hay RFC. El producto ya tiene WhatsApp, fichas bilingües (`validate_bilingual_pairs` en `024_public_listing_rpcs.sql`) y alta de agencia. |
| R24 | Nivel 1 sin doc nueva; nivel 2 actualiza specs antes de codear; nivel 3 exige ADR | Parcial | Signal Forms tiene ADR (nivel 3). 006–008 están en spec sin código, que es el orden correcto. 004 y 005 tienen código de nivel 2 sin el plan. |
| R25 | Una sola jerarquía resuelve los conflictos | No cumple | Capítulo 3 líneas 385–411 y capítulo 16 líneas 3641–3651 ordenan los artefactos de forma distinta. Los ADR están debajo del plan en un capítulo y encima del PRD en el otro. |
| R26 | Está prohibido introducir arquitectura en silencio | Parcial | Los tres ADR existentes son explícitos. El dominio en PLpgSQL y el «CMS» comercial en PostgreSQL se acumularon en migraciones sin ADR. |

### Capítulo 4 — Atributos de calidad

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R27 | Resultados deterministas, reglas validadas, operaciones inválidas rechazadas, integridad | Parcial | Triggers de identidad y estados (`029_customers_requests.sql`, `036_pre_reservations.sql`, `043_quotations.sql`) y `RAISE EXCEPTION` con código. Las 33 suites SQL no se ejecutaron aquí. |
| R28 | Autenticar, autorizar, proteger datos sensibles, aislar tenants y registrar eventos críticos | Cumple | Guards, RLS, `audit.log_event` y tipos de evento extendidos hasta `quotation_expired` (`042_quotation_enums.sql` 67–73). |
| R29 | Diseño modular, poco acoplamiento, alta cohesión, lógica de negocio aislada | Parcial | `src/app/core/<capacidad>` y `src/app/features/<capacidad>` separan pantallas. La lógica no está aislada de PostgreSQL (R39, R125). |
| R30 | Implementaciones directas, sin abstracciones prematuras ni configuración de más | Parcial | No hay un framework de dominio encima de SQL, y eso mantiene el sistema más simple. La convención está documentada en tareas, no en Development Standards. |
| R31 | Fallos con degradación, transacción, sin fallos silenciosos y con error comprensible | Parcial | `toAppError` y códigos de excepción. Los barridos de expiración tragan el error con `console.warn` (`pre-reservation.service.ts` 143, `quotation.service.ts` 106). |
| R32 | Mismos patrones, mismos nombres, misma UI, mismos flujos | Parcial | Patrones de lista, formulario y error se repiten. El menú llama «CMS» al catálogo comercial (`nav-items.ts` 95–98) y el constitution reserva CMS a WordPress (líneas 3203–3214). |
| R33 | Crecer por módulos, seguir siendo multi-tenant y evitar cuellos arquitectónicos | Cumple | Cada feature añade migraciones y una carpeta. No aparece un segundo servicio. |
| R34 | Menos viajes de red, menos queries repetidas, caché cuando aporte, medir antes de optimizar | Parcial | Paginación `range` documentada en las tareas de 004. `config.toml` línea 13 limita `max_rows` a 1000. Hay probes SQL de catálogo. No hay métricas de producción. |
| R35 | Componer, respetar bordes de módulo y crecer sin reescribir | Parcial | Las features se componen sobre RPCs. Un cambio de regla obliga a tocar funciones SQL grandes, no un módulo con interfaz estrecha. |
| R36 | Menos esfuerzo, feedback claro, flujos operativos | Parcial | UI en español, guard de cambios sin guardar, alertas. El dashboard no opera (`dashboard.component.ts` 14–16) y la matriz de roles informa mal. |

### Capítulo 5 — Principios de arquitectura

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R37 | El MVP es un monolito modular. Los microservicios quedan prohibidos sin justificación medida | Cumple | Un `ng build` y un proyecto Supabase. Las Edge Functions son adaptadores (alta y webhook), que el capítulo 14 línea 3180 permite «cuando se justifiquen». |
| R38 | El sistema se organiza por capacidad de negocio, y cada una posee reglas, datos, servicios, UI y validación | Cumple | Carpetas `core/auth`, `core/catalog`, `core/customers`, `core/pre-reservations`, `core/quotations` y features homólogas. |
| R39 | Separar presentación, aplicación, dominio e infraestructura. El dominio no depende de la infraestructura | No cumple | No hay capa de dominio ni de aplicación. Las invariantes están en funciones PLpgSQL. El constitution lo prohíbe en las líneas 990–1003 y 3248–3257. |
| R40 | Un lenguaje ubicuo, igual en specs, base, API, código y UI | Parcial | `customer`, `pre_reservation`, `quotation` se sostienen. «CMS» en la UI nombra otra cosa que «Content Management» en el constitution. Código y tablas en inglés, pantallas en español: el concepto coincide, la palabra visible no. |
| R41 | Composición en lugar de herencia; evitar jerarquías profundas | Cumple | No hay jerarquías de clases de dominio. Los componentes componen servicios. |
| R42 | Dependencias entre módulos visibles, intencionales y sin ciclos | No verificable | A simple vista `features` importa `core` y no al revés. No se corrió un análisis de ciclos. |
| R43 | Los servicios de negocio permanecen sin estado; el estado vive en la base o en la sesión | Cumple | Las RPC no guardan estado de proceso. La sesión está en Supabase Auth más `SessionActivityStore`. |
| R44 | El contrato se define antes de implementar y un cambio que rompe el contrato actualiza la spec | Parcial | Contratos en 001, 002, 003, 009 y 010. 004 y 005 no tienen contrato en el árbol. |
| R45 | El diseño de datos, la autorización, las reglas y la auditoría contemplan al tenant | Cumple | `organization_id` en las tablas de negocio y en `audit.audit_events` (`004_create_audit_schema.sql` 13). El reporting de negocio, también exigido en la línea 1093, no existe (R99). |
| R46 | Las reglas de negocio sobreviven a un cambio de hosting o de proveedor | No cumple | Auth Hooks `pg-functions://`, policies de `storage.objects` y `auth.jwt()` acoplan el comportamiento a Supabase. |
| R47 | Preferir servicios gestionados y mantenerlos reemplazables detrás de un borde | Parcial | Supabase es el servicio gestionado elegido. El borde de reemplazo no existe: el cliente `@supabase/supabase-js` se usa desde `src/app/core/**`. |
| R48 | La arquitectura evoluciona con cambios pequeños y reversibles | Cumple | 48 migraciones incrementales, numeradas, sin un rewrite visible. |

### Capítulo 6 — Modelado de dominio

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R49 | DDD pragmático: entidades, value objects, agregados, servicios y eventos con responsabilidades distintas | Parcial | Hay tablas con identidad y funciones de caso de uso. No hay value objects ni agregados como tipos. Los modelos TypeScript son filas (`user.model.ts` 14–28). |
| R50 | El mismo concepto no tiene dos nombres, y dos conceptos no comparten nombre | Parcial | Pre-reserva y cotización están separados. «CMS» y «reserva» se usan en documentos para cosas que el código no tiene o nombra distinto (R32, R40). |
| R51 | La identidad de una entidad es inmutable | Cumple | UUID como clave. Triggers `prevent_*_identity_change` en solicitudes, pre-reservas y cotizaciones (por ejemplo `029_customers_requests.sql` 240). El tipo de producto tampoco cambia (`014_create_products.sql` 75). |
| R52 | Cada agregado protege sus invariantes y no persiste estados inválidos | Parcial | CHECK, triggers y RPC rechazan transiciones. Eso está en la base, no en un agregado con interfaz pública. |
| R53 | Las entidades cambian por transiciones explícitas que validan y rechazan | Cumple | `set_request_status`, `refresh_pre_reservation_status`, `set_product_status`, `issue_quotation`, `void_quotation`. |
| R54 | Cada regla de negocio tiene una sola implementación autoritativa | Cumple | Tarifas en `resolve_price` / `resolve_quotation_tariff`. La UI de cotización pinta los totales del RPC. |
| R55 | Los hechos de negocio se modelan como eventos, no como comandos | Parcial | `audit.audit_event_type` nombra hechos (`quotation_issued`, `customer_anonymized`). Es un log de auditoría, no un modelo de domain events consumible por otros módulos. |
| R56 | El sistema se divide en capacidades con vocabulario, reglas y datos propios | Cumple | Módulos de la sección 1. Los contextos cruzan por identificadores (`pre_reservation_id`, `quotation_version_id`), no por objetos compartidos. |
| R57 | El identificador no codifica significado de negocio | Cumple | La identidad es UUID. El localizador humano sale de `organization_sequences` (`029_customers_requests.sql` 224), columna distinta. |
| R58 | Los cambios de negocio relevantes se pueden auditar en lenguaje de negocio | Cumple | Tipos de evento de catálogo, solicitudes, pre-reservas y cotizaciones. La pantalla está en `/settings/audit`. |
| R59 | Ningún concepto nuevo entra al código antes de aparecer en PRD, modelo y casos de uso | No cumple | Pre-reservas y cotizaciones están en código sin `data-model.md`. El constitution lo exige en las líneas 1404–1414. |
| R60 | Los conceptos obsoletos se retiran en lugar de abandonarse | No verificable | No hay un registro de conceptos retirados. Los redirects `/catalog/*` conservan rutas viejas a propósito (`app.routes.ts` 408–421). |

### Capítulo 7 — Estándares de ingeniería

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R61 | El código se lee solo: nombres, estructura, responsabilidades pequeñas; el comentario explica por qué | Cumple | Headers de migración y comentarios de guards explican la razón (ejemplo `session.interceptor.ts` 6–35, `004_create_audit_schema.sql` 1–8). Lint y Prettier pasan. |
| R62 | Cada componente tiene una responsabilidad | Parcial | Servicios por capacidad. `product-editor` y `quotation-editor` concentran ficha, precio, publicación y textos en un solo componente (chunks de 56 kB y 31 kB en el build). |
| R63 | Módulos independientes que hablan por interfaces, y se reutiliza antes de crear | Cumple | `data-table`, `alert`, `spinner`, `toAppError` y `unsavedChangesGuard` se comparten. La comunicación entre capacidades pasa por RPC. |
| R64 | Toda operación valida, falla de forma predecible, informa y conserva la consistencia | Cumple | Validación de payload en `submit_public_request` (tamaño, forma, consentimiento) y en `validateIntakeDraft` (`intake-payload.ts` 65–70). Las funciones corren en una transacción de PostgreSQL. |
| R65 | La deuda técnica intencional está documentada, con riesgo y plan de salida | No cumple | No hay registro de deuda. El dashboard «para más adelante» solo vive en un comentario de componente (`dashboard.component.ts` 5–6). El constitution líneas 1579–1590 prohíbe la deuda sin documento. |
| R66 | Cada dependencia se justifica por necesidad, madurez y seguridad | Parcial | `package.json` es corto y no añade librerías de UI. `npm audit` marca 2 altas en producción y 3 críticas en la cadena de build. No hay un registro de aceptación de esas alertas. |
| R67 | Todo cambio significativo pasa por revisión técnica | No verificable | No hay `CODEOWNERS`, plantilla de PR ni checks obligatorios en el repo. |
| R68 | El refactor conserva el comportamiento observable | No verificable | No hay un historial de refactors aislados que se pueda juzgar. |
| R69 | Los problemas repetidos mejoran el proceso, no solo el caso | No verificable | No hay retrospectivas ni actualización de estándares a partir de incidentes. |
| R70 | El código generado por IA se revisa con los mismos criterios | No verificable | No hay marca de autoría ni evidencia de revisión independiente. |

### Capítulo 8 — Seguridad

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R71 | Mínimo privilegio: el permiso se concede, no se hereda por accidente | Cumple | `REVOKE ALL` y `GRANT EXECUTE` por función. Ejemplo `issue_quotation` solo a `authenticated` (`046_us2_quotation_issue.sql` 408–409). `ingest_whatsapp_webhook` solo a `service_role`. |
| R72 | Denegación por defecto | Cumple | RLS al crear la tabla y revocación a `PUBLIC`/`anon` en catálogo (`013_create_providers.sql` 24–26). Sin política no hay acceso para el rol del navegador. |
| R73 | Defensa en profundidad: auth, autorización, RLS, validación y auditoría, de modo que un fallo no baste | Cumple | Guard + RLS + chequeo dentro de la RPC. El propio guard lo dice (`role.guard.ts` 9–11). |
| R74 | La configuración por defecto es la segura | Cumple | Signup apagado, contraseña con clases de caracteres (`config.toml` 52–56), anon key de producción en placeholder (`environment.ts` 10–13). La service role no aparece en `src/`. |
| R75 | Toda entrada externa se trata como no confiable | Cumple | HMAC del webhook (`whatsapp-inbound/index.ts` 46–58). `submit_public_request` valida tamaño y forma. `get_public_quotation` no revela si el token vacío corresponde a algo (`047` líneas 87–89 y 156–157). |
| R76 | La identidad se autentica aparte de la autorización, con un proveedor de identidad | Cumple | Supabase Auth para la credencial; `app_role` y `organization_id` para la autorización (ADR-0002). |
| R77 | La autorización se evalúa en UI, API y base, y no basta la validación del cliente | Cumple | `roleGuard` y, de forma independiente, RLS y `require_*`. |
| R78 | El aislamiento entre organizaciones es comprobable en base, storage, autorización y auditoría | Parcial | Políticas `tenant_isolation_select` y tests `rls_isolation_test.sql`, `catalog_rls_test.sql`, `pre_reservation_rls_test.sql`, `quotation_rls_test.sql`. Esas suites no se ejecutaron en esta revisión. No hay `FORCE ROW LEVEL SECURITY`. |
| R79 | La sesión se identifica, expira, se puede revocar y se audita | Parcial | JWT de 1 h, rotación de refresh (`config.toml` 46–49), `record_session_end`, bloqueo por intentos. Los límites de 8 h y 24 h son solo del navegador (`session.interceptor.ts` 32–35). |
| R80 | Secretos fuera del código; datos sensibles protegidos en almacenamiento y tránsito | Cumple | Placeholders de producción. La anon key de desarrollo es la clave pública de la demo local, comentada como tal (`environment.development.ts` 1–9). `redact()` quita credenciales de los logs de error (`error-handler.ts` 216–246). |
| R81 | Los eventos de seguridad quedan en un registro que no se puede alterar | Cumple | `audit.reject_audit_mutation` (`007_create_triggers.sql` 38–58) y ausencia de políticas UPDATE/DELETE (`005_create_rls_policies.sql` 109–110). `system_insert` con `WITH CHECK (true)` está limitado a `service_role` (líneas 104–107). |
| R82 | Preparación para detectar, investigar, contener y recuperar un incidente | No cumple | No hay runbook, alertas ni responsable de un aviso. El capítulo 8 líneas 1922–1934 lo pide. |

### Capítulo 9 — Privacidad y gobierno del dato

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R83 | Recoger solo lo necesario y evitar copias de datos personales | Parcial | El cliente vive en `customers`. El webhook guarda el mensaje en `inbound_messages`. No hay una política escrita de minimización. |
| R84 | Cada entidad de negocio tiene un dueño responsable de exactitud, ciclo de vida y acceso | No cumple | No hay registro de ownership. El constitution líneas 2030–2043 lo exige. |
| R85 | Clasificar al menos: público, interno, confidencial, personal sensible y crítico de seguridad | No cumple | No hay taxonomía ni columna de clasificación. El constitution líneas 2047–2059 lo exige. |
| R86 | Los datos de negocio se validan; lo inválido se rechaza | Cumple | Fechas, consentimiento, estados y solapes de tarifa se rechazan en RPC y constraints. |
| R87 | Cada concepto tiene una fuente autoritativa | Cumple | PostgreSQL es el almacén. El precio público de vitrina y la tarifa operativa están separados a propósito en el plan de 009, con la tarifa como autoridad comercial. |
| R88 | Ciclo de vida con archivo o borrado, y retención definida por negocio y norma | No cumple | Hay alta, edición y `anonymize_customer`. No hay plazos de retención ni job de depuración. El enum de organización no tiene operación de baja. |
| R89 | El consentimiento es explícito, informado, verificable y revocable; el personal tiene borrado seguro | Parcial | Web: `privacy_consent` obligatorio en el contrato de 003. Panel: el agente marca «Informé al cliente…» (`request-intake.component.ts` 181–185), que no es la firma del titular. La revocación visible es anonimizar. |
| R90 | La auditoría de datos dice quién, qué, cuándo, valor anterior, valor nuevo y motivo | Parcial | `audit_events` guarda actor, tipo, instante y `metadata`. El override de precio documenta anterior/nuevo/motivo (`020_us4_pricing_rpcs.sql` 391). No es así en cada columna de cliente. |
| R91 | Compartir datos solo con autorización explícita y sin cruzar tenants | Cumple | RLS por organización. La lectura pública de una cotización va por token y omite el contacto (`047` líneas 156–157). |
| R92 | El dato de negocio se puede exportar en un formato abierto | Parcial | Está en PostgreSQL, así que un operador con acceso a la base puede sacarlo. No hay exportación en el producto. El spec 008 la pide y no está construido. |

### Capítulo 10 — Preparación multi-tenant

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R93 | Toda operación corre en el contexto de un solo tenant; nadie asume una sola organización | Cumple | `require_tenant_member` y el JWT `organization_id`. `get_public_site` ignora el id recibido cuando hay sesión y usa el del token (`025_public_site_read.sql` 20–32). |
| R94 | La identidad del tenant es única, estable e independiente del nombre comercial | Cumple | `organizations.id` UUID. El nombre es un atributo (`002_create_organizations.sql`). |
| R95 | Consultas, storage y auditoría no cruzan el tenant | Cumple | Políticas de tabla y de `storage.objects` (`026_catalog_media_bucket.sql` 68–96). `audit_events.organization_id` es `NOT NULL`. |
| R96 | El permiso se evalúa con usuario y tenant a la vez | Cumple | Las políticas combinan `app_role` y `organization_id` (`005_create_rls_policies.sql` 70–74). |
| R97 | La configuración del tenant extiende el comportamiento y no fork ea el producto | Parcial | Existen `quotation_defaults`, `public_sites` y código de país telefónico. No hay branding, notificaciones ni localización como configuración. El código es uno solo: no hay un fork por cliente. |
| R98 | Ciclo de vida: aprovisionar, activar, configurar, operar, suspender, reactivar y dar de baja | Parcial | `register_agency` crea la organización `active`. El enum tiene `suspended` e `inactive` (`001_create_enums.sql` 13) y el intake público lo respeta (`031` líneas 45–49). No hay RPC de suspensión, reactivación ni baja. |
| R99 | Métricas operativas por tenant sin romper el aislamiento | No cumple | No hay métricas. El dashboard lo dice (`dashboard.component.ts` 14–16). |
| R100 | La ausencia de planes, cupos, flags y facturación no cierra la puerta a tenerlos | Cumple | `organization_id` en cada fila permite colgar esos conceptos después. No hay un supuesto de una sola organización embebido en las reglas. |

### Capítulo 11 — Rendimiento y escalabilidad

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R101 | Optimizar con medición: cuello de botella, impacto y trade-off | Parcial | Hay `catalog_performance_probe_test.sql` y `performance_probe_test.sql`. No hay medición de producción ni decisión de optimización documentada. |
| R102 | Primero la implementación simple y correcta | Cumple | No aparece caché, réplicas ni sharding. El presupuesto de bundle avisa y el build no introduce una optimización opaca para callarlo. |
| R103 | Leer solo lo necesario y mantener la transacción | Cumple | Listados con `range` y `count`. `max_rows = 1000` (`config.toml` 13). Índices de auditoría en `004_create_audit_schema.sql` 36–46. |
| R104 | La caché no es fuente de verdad y su ausencia no rompe la corrección | Cumple | No hay capa de caché de negocio. La lectura pasa por PostgreSQL. |
| R105 | Cada feature relevante declara su impacto en tiempo, base, memoria y almacenamiento | No cumple | El único presupuesto medible es el de bundles en `angular.json` 39–50, y el build ya lo supera en warning (521,66 kB frente a 500 kB). No hay presupuestos de latencia ni de crecimiento. |
| R106 | Tiempos de respuesta, errores, throughput y capacidad son observables | No cumple | No hay exportador de métricas ni tablero. |

### Capítulo 12 — Observabilidad

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R107 | De una operación crítica se puede decir qué pasó, cuándo, por qué, quién, qué tenant y con qué resultado | Parcial | La auditoría cubre quién, qué, cuándo y tenant para los eventos modelados. No cubre el «por qué» operativo ni la salud del proceso. |
| R108 | Los logs explican y no guardan datos sensibles | Cumple | La Edge Function registra códigos y contadores, no el cuerpo ni el teléfono (`whatsapp-inbound/index.ts` 8–9 y 92–100). `redact()` en el cliente. |
| R109 | Los logs no sustituyen a la auditoría de negocio | Cumple | El registro de negocio es `audit.audit_events`, con privilegios distintos (`004_create_audit_schema.sql` 52–59). |
| R110 | Métricas de disponibilidad, latencia, errores, capacidad y actividad de negocio | No cumple | No hay instrumentación. Spec 008 en Draft. |
| R111 | Las operaciones que cruzan bordes se pueden trazar | No cumple | No hay identificador de traza entre el navegador, la Edge Function y la RPC. |
| R112 | Salud (sano, degradado, caído), alertas con dueño y visión de capacidad | No cumple | No hay endpoint de salud de negocio, ni alertas, ni series de usuarios, organizaciones o reservas. nginx solo sirve el estático (`nginx.conf` 1–8). |
| R113 | Los incidentes dejan causa, factores y mejora | No cumple | No hay registro de incidentes. |

### Capítulo 13 — Verificación

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R114 | Cada implementación se traza a un requisito | Parcial | Las migraciones citan el spec. 004 y 005 no tienen contrato que trazar. T048 de 004 sigue abierta (`tasks.md` línea 167) y apunta a un `quickstart.md` que no está. |
| R115 | Pruebas automatizadas según el riesgo, no según una cuota | Parcial | El riesgo de RLS y de reglas tiene suites SQL. El riesgo de UI tiene 128 pruebas de unidad y casi ninguna de pantalla. Esta revisión ejecutó solo las de unidad. |
| R116 | Verificación manual y aceptación de negocio con evidencia | No cumple | No hay actas de aceptación. T048 pide esa pasada manual y sigue sin marcar. |
| R117 | Un defecto resuelto reduce la probabilidad de que vuelva | Parcial | ADR-0003 nace de huecos reales y añade comportamiento en base más tests. No hay una regla de «todo bug lleva prueba» escrita en el repo. |
| R118 | La evidencia de cumplimiento existe: reviews, tests, auditoría, aceptación | Parcial | `specs/001-auth-tenant-access/validation-evidence.md` existe. El resto de features no tiene un documento equivalente. |
| R119 | La verificación forma parte del flujo normal, incluido el despliegue | No cumple | No hay CI. Lint, tests y la suite SQL dependen de que alguien los lance. |
| R120 | La IA no se acepta como verificación; hace falta validación independiente | No verificable | No hay registro de quién validó cada feature. |

### Capítulo 14 — Restricciones técnicas

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R121 | Angular es el único frontend salvo ADR en contra | Cumple | Una aplicación. No hay segundo framework en `package.json`. |
| R122 | PostgreSQL es el almacén autoritativo, con integridad y relaciones explícitas | Cumple | Claves foráneas y constraints en las migraciones. No hay otra base. |
| R123 | WordPress se limita a contenido editorial; el dato de negocio no vive ahí | Parcial | El dato de negocio está en PostgreSQL, así que la prohibición se cumple. La obligación de usar WordPress para el editorial no se cumple (R06). |
| R124 | Monolito modular obligatorio en el MVP | Cumple | Igual que R37. |
| R125 | Las reglas de negocio no dependen de UI, proveedor, base de datos ni integración | No cumple | La implementación autoritativa es PLpgSQL con `auth.jwt()` y `SECURITY DEFINER`. El constitution líneas 3248–3257 lo declara obligatorio. |
| R126 | No se añaden dependencias solo por comodidad | Cumple | El árbol directo es Angular, `supabase-js`, RxJS y herramientas de lint/test. |
| R127 | Los servicios externos siguen siendo reemplazables | No cumple | Sustituir Supabase Auth, RLS y Storage implicaría reescribir la frontera de seguridad. No hay puerto de infraestructura. |
| R128 | La lógica y las specs pueden migrar de proveedor | Parcial | El SQL estándar de tablas podría moverse. Hooks, JWT de Supabase y Storage no. |

### Capítulo 15 — Definition of Done

Una feature solo está terminada cuando todas las puertas aplicables pasan (constitution líneas 3570–3572). El juicio de abajo es del producto tal como está en `main`, no de un commit aislado.

| ID | Puerta | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R129 | 1. Alineación de negocio | Parcial | El flujo llega hasta la cotización aceptada. El mainspec (`.specify/mainspec.md` líneas 15–16 y 60–66) incluye la reserva confirmada, que no existe. |
| R130 | 2. Cumplimiento de especificación | Parcial | 001, 002, 003, 009 y 010 siguen sus specs. El contrato de 010 ya no coincide con las rutas. 004 y 005 no tienen spec técnica completa en el árbol. |
| R131 | 3. Integridad de dominio | Parcial | Estados e invariantes de lo construido se sostienen en SQL. No hay modelo de dominio único. |
| R132 | 4. Cumplimiento arquitectónico | Parcial | Monolito modular y stack aprobado, con el dominio acoplado a la base (R39, R125). |
| R133 | 5. Calidad de ingeniería | Parcial | Lint, formato y pruebas de unidad pasan. Editores grandes y deuda sin registro. |
| R134 | 6. Seguridad | Parcial | Controles fuertes de auth, RLS y auditoría. Sesión larga solo en cliente (R79) y sin CI de seguridad. |
| R135 | 7. Privacidad | Parcial | Consentimiento y anonimización parciales. Sin clasificación ni retención (R85, R88). |
| R136 | 8. Preparación multi-tenant | Parcial | Aislamiento real. Ciclo de vida del tenant incompleto (R98). |
| R137 | 9. Rendimiento | Parcial | Sin optimización prematura. El bundle supera el warning y no hay medición de producción. |
| R138 | 10. Observabilidad | No cumple | R110–R113. |
| R139 | 11. Verificación | Parcial | Suites escritas; SQL y aceptación sin evidencia de esta revisión, y sin CI. |
| R140 | 12. Pruebas | Parcial | 128/128 en frontend. Suite SQL no corrida. Casi sin pruebas de pantalla. |
| R141 | 13. Documentación sincronizada | No cumple | README, AGENTS, contrato de navegación y comentario del runner SQL no describen el código (sección 2). |
| R142 | 14. Preparación operativa | Parcial | `Dockerfile`, `README` y hooks documentados. El despliegue real de los hooks queda como paso manual del README (líneas 57–64). No hay runbook. |
| R143 | 15. Revisión y aprobación con evidencia | No verificable | No hay aprovisionamiento de reviews en el repo. |
| R144 | 16. Mantenibilidad a largo plazo | Parcial | La estructura por capacidad ayuda. La ausencia de estándares, de CI y de un dominio separable la empeora. |

### Capítulo 16 — Gobierno del constitution

| ID | Requisito | Veredicto | Evidencia |
| --- | --- | --- | --- |
| R145 | Este documento es la autoridad de ingeniería y está presente | Cumple | `.specify/memory/constitution.md` es el único constitution del repo. |
| R146 | Una enmienda incluye motivo, límite actual, cambio, beneficios, riesgos y capítulos afectados | Parcial | ADR-0001 documenta el paso a Signal Forms con ese contenido. El constitution no registra la enmienda ni una versión (líneas 3706–3717 piden el proceso; el archivo empieza directo en «# 1. Purpose»). |
| R147 | La jerarquía del capítulo 16 es coherente con el resto del constitution | No cumple | Contradice el capítulo 3. Detalle en R25. |
| R148 | Revisión periódica del constitution, priorizando la estabilidad | No verificable | No hay fecha de última revisión. |

## 4. Lo que el código hace y el constitution no contempla, o contradice

El constitution no es un catálogo de pantallas. Estas son las diferencias de fondo:

1. **El dominio está implementado como API de PostgreSQL.** Contradice las líneas 990–1003 y 3248–3257. A la vez cumple «una sola implementación de cada regla» (líneas 1320–1332). Las dos normas no se pueden satisfacer juntas con la arquitectura actual; hace falta un ADR que elija y, si la elección es la base de datos, una enmienda del constitution.
2. **El menú «CMS» administra catálogo comercial y fichas públicas**, incluidas reseñas y yates como colocación de experiencia (`ui-contracts.md` línea 34 y 96). El constitution asigna el CMS a WordPress y deja el dato de negocio fuera de WordPress. El dato está en el sitio correcto; el nombre y la ausencia de WordPress no.
3. **El contrato de navegación y `AGENTS.md` describen reservas confirmadas** que el código no tiene, y omiten pre-reservas y verificación, que el código sí tiene.
4. **El enlace público de cotización y el webhook de WhatsApp** son integraciones reales, alineadas con el mainspec, y no aparecen como tecnologías en el capítulo 14. No lo contradicen: el capítulo 14 permite servicios externos si siguen siendo reemplazables. El webhook está bien encapsulado en una Edge Function. El sitio público consumidor no está en el repo.
5. **Límites de sesión de 8 h y 24 h solo en el cliente**, mientras el capítulo 8 exige que la regla de negocio no dependa de la validación del navegador. El código lo admite en `session.interceptor.ts` 32–35.
6. **`WITH CHECK (true)` en la inserción de auditoría** (`005_create_rls_policies.sql` 104–107) es deliberado para `service_role`. No abre la tabla al navegador, que no tiene `INSERT`. Queda anotado para que no se lea como una política abierta.

## 5. Requisitos del constitution sin implementación

- WordPress headless: artículos, landings, SEO (capítulo 14 líneas 3203–3214; spec 007).
- Reserva confirmada, depósito, voucher, ciclo operativo y orden de servicio (misión del capítulo 1; spec 006; mainspec).
- Embudo, tiempos operativos y exportación comercial (spec 008). El visor de auditoría de 001 cubre solo una parte.
- Suspender, reactivar y dar de baja un tenant (capítulo 10 líneas 2372–2386).
- Clasificación de datos y plazos de retención (capítulo 9).
- Dueño explícito de cada entidad.
- Development Standards, Cross-Cutting Requirements, Domain Model único, RFC y ADR de las decisiones ya tomadas.
- Métricas, trazas, salud, alertas y capacidad (capítulos 11 y 12).
- CI y evidencia de aceptación más allá de la feature 001.
- Exportación de producto (SHOULD de portabilidad; requisito del spec 008).
- Presupuestos de rendimiento por feature.

Planes, cupos, facturación y white-label están nombrados como futuro (capítulo 10 líneas 2419–2431). Su ausencia es compatible con el constitution. La arquitectura actual no les cierra el paso.

## 6. Correcciones para alinear el proyecto, por prioridad

### Alta

1. **Resolver la contradicción de gobierno.** Unificar la jerarquía de los capítulos 3 y 16, numerar el constitution y registrar la enmienda de Signal Forms dentro del documento. Mientras las dos jerarquías convivan, un conflicto de artefactos no tiene ganador.
2. **Decidir dónde vive el dominio y dejarlo escrito.** O se extrae la regla de negocio de PLpgSQL hacia un módulo que la base solo persiste, o se enmienda el constitution para aceptar PostgreSQL como implementación autoritativa, con ADR de consecuencias (acoplamiento a Supabase, portabilidad, pruebas). Hoy el código y los capítulos 5 y 14 dicen cosas opuestas.
3. **Cerrar WordPress con una decisión, no con un silencio.** Integrar el CMS editorial del spec 007, o enmendar el capítulo 14 y renombrar el menú «CMS» del panel para que deje de chocar con el lenguaje ubicuo. El dato comercial debe seguir en PostgreSQL.
4. **Reconstruir los diseños de 004 y 005** (`plan.md`, `data-model.md`, `contracts/`, `quickstart.md`) a partir del código y de los specs, y corregir el contrato de 010: quitar `/sales/reservations` hasta que exista, y añadir pre-reservas y verificación. Corregir `AGENTS.md` y el `README`, que hoy describen un sistema distinto del que está en el árbol.
5. **Completar el ciclo de vida del tenant y la retención de datos personales.** El enum `suspended` ya condiciona el intake público y no hay forma de operar la transición. Definir clasificación mínima y plazos, aunque la primera versión sea un documento de Cross-Cutting Requirements más una RPC de suspensión.
6. **Hacer que la expiración de sesión y la observabilidad mínima no dependan del navegador.** Persistir el tope de 24 h donde el refresh token se emite, y añadir un punto de salud más el registro de errores de los barridos que hoy solo hacen `console.warn`.
7. **CI con `lint`, `test` y `run-sql-tests.sh`.** Sin eso, las 33 suites de seguridad son una intención. En esta revisión no pudieron correr porque no hay Docker.

### Media

8. Ajustar la matriz de roles al mapa real (`nav-items.ts` y `app.routes.ts`) para que un administrador no crea que el agente solo consulta el catálogo.
9. Tratar specs 006 y 008 como trabajo futuro explícito en el mainspec y en `AGENTS.md`, o construirlos. El commit `4617093` no debe seguir presentándolos como entregados.
10. Bajar el chunk inicial por debajo de 500 kB o subir el presupuesto con una nota de por qué.
11. Revisar las alertas `npm audit` (router y `zod` en producción; `piscina`/`vite` en build) y dejar constancia de cuáles aplican a este SPA sin SSR.
12. Valorar `FORCE ROW LEVEL SECURITY` en tablas de negocio para que el owner no sea un atajo silencioso.
13. Diferenciar el consentimiento del titular del acuse del agente, y documentar quién llama a `submit_public_request` desde el sitio público.
14. Escribir el Development Standards que el capítulo 7 da por existente (carpetas, SQL, Signal Forms, flujo de git) y mover allí las convenciones que hoy están copiadas en cada `tasks.md`.

### Baja

15. Añadir versión y fecha al constitution, y una plantilla de RFC vacía para el próximo cambio de nivel 3.
16. Presupuestos de latencia por capacidad, cuando exista un entorno donde medir.
17. Trazas entre Edge Function y RPC el día que haya más de un borde.
18. Exportación CSV del spec 008, junto con el embudo, no antes: el constitution pide no construir reporting por si acaso, y a la vez el mainspec lo incluye. La decisión de alcance debe quedar en el PRD.
19. Marcar T048 de 004 como bloqueada hasta que exista `quickstart.md`, para que la lista de tareas deje de apuntar a un archivo ausente.

## 7. Lectura final

La base de seguridad y de multi-tenant es el pedazo más fiel al constitution: identidad, RLS, mínimo privilegio, auditoría inmutable y un solo producto para muchas organizaciones. El desalineamiento está en el gobierno y en dos principios de arquitectura que el código contradice todos los días: documentación como fuente de verdad, y dominio independiente de la base de datos. Esas dos, más la ausencia de WordPress, de observabilidad y del tramo de reservas que el propio producto dice ser, explican la mayoría de los 28 «No cumple».

Hasta que esas decisiones se enmienden o se implementen, el Definition of Done del capítulo 15 no se puede usar como declaración de terminado.
