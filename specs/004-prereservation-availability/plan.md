# Implementation Plan: 004-prereservation-availability

**Branch**: `004-prereservation-availability` | **Date**: 2026-10-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-prereservation-availability/spec.md` (clarifications session 2026-10-04 encoded in the spec)

## Summary

Nueva capacidad de negocio **Comercial — Pre-Reservas y Verificación de Disponibilidad**. Una solicitud en estado `received`, `in_review` o `pre_reservation` se convierte en una **Pre-Reserva** (`PRE-#####`) con líneas de servicio concretas (experiencias, alojamientos, paquetes, complementos; fechas y pasajeros). La primera conversión pasa la solicitud a `pre_reservation` en la misma transacción (frontera pactada con 003). Un operador/admin verifica cada línea con el proveedor por canales humanos (llamada, WhatsApp, correo — el panel solo ofrece enlaces `tel:`/`wa.me`/`mailto:`) desde una **Cola de Verificación** restringida por rol. El estado global se **deriva automáticamente** de las líneas principales vigentes (`refresh_pre_reservation_status`, única autoridad), con expiración por retención del proveedor mediante barrido idempotente al leer (sin `pg_cron`). La elegibilidad para cotizar vive en `assert_pre_reservation_quotable` (punto de integración para 005), con excepción de Administrador auditada e invalidable. Historial append-only por línea separado de la auditoría sin PII, y aviso en el shell por Realtime cuando la pre-reserva queda `verified`.

## Technical Context

**Language/Version**: TypeScript 6.x (Angular 22, Standalone Components, Signals, Signal Forms); PL/pgSQL (PostgreSQL 17). Sin Edge Functions nuevas.

**Primary Dependencies**: Angular 22, `@angular/router`, `@angular/forms/signals`, `@supabase/supabase-js` (PostgREST + Realtime). Sin dependencias npm nuevas. Reutiliza `data-table`, `list-query`, `unsavedChangesGuard`, `roleGuard`, `toAppError` (010/003).

**Storage**: PostgreSQL vía Supabase. Tablas nuevas en `public`: `pre_reservations`, `pre_reservation_items`, `availability_verification_events` (append-only); vistas `security_invoker` `pre_reservation_list`, `availability_verification_queue`, `availability_verification_history`, `pre_reservation_verification_times`. Cambio de soporte: `providers` gana `UNIQUE (id, organization_id)`; `pre_reservations` entra en `supabase_realtime` si la publicación existe. Reutiliza `customer_requests` (003, estado `pre_reservation` ya reservado), `customers`, `organization_sequences`, `products`/`add_ons`/`providers` (002), `user_profiles`, `audit.audit_events` (001). Migraciones `035_…` a `041_…`.

**Testing**: Suites SQL en `supabase/tests/*_test.sql` (harness Postgres 17 en Docker, `run-sql-tests.sh`) para enums/RLS, conversión y ciclo de la solicitud, cola y resultados de verificación, consolidación/ajustes/expiración/excepción, historial y tiempos. Vitest (`ng test`) para lógica TS: árbol de navegación, `list-query` (providerId/group), estados/acciones de pre-reserva, construcción del payload de líneas, enlaces de contacto del proveedor. Validación manual del panel y de Realtime según [quickstart.md](./quickstart.md).

**Target Platform**: Panel interno en navegador de escritorio (shell de 010), rutas bajo `/sales/*`. Supabase (PostgREST, Realtime). La verificación con proveedores es humana: sin integraciones salientes.

**Project Type**: Módulo de negocio del modular monolith (Angular + Supabase). Contratos internos: RPCs `SECURITY DEFINER` + vistas `security_invoker`; punto de integración `assert_pre_reservation_quotable` para la feature 005.

**Performance Goals**: Cola y listados de 20 filas con paginación en servidor (`range` + `count: 'exact'`); recálculo de estado O(líneas) en la misma transacción; aviso de «Totalmente verificada» ≤ 10 s vía Realtime (sondeo de 30 s como respaldo); operador abre la cola, filtra por proveedor y registra un resultado en ≤ 3 clics (SC-004).

**Constraints**: RLS `SELECT`-only por `organization_id` y Default Deny; `anon` sin privilegios; escrituras solo por RPC `SECURITY DEFINER` con `SET search_path = ''`. Solo operator/admin registran resultados (`require_availability_verifier()`); solo admin autoriza la excepción (`require_tenant_admin()`). PII del viajero nunca en la cola (solo nombre/apellido), nunca PII en metadata de auditoría. Una pre-reserva jamás bloquea inventario ni calcula precios. Líneas inmutables en fechas/producto/pasajeros (se retiran y se agregan).

**Scale/Scope**: Un tenant piloto con diseño multi-tenant; cientos de pre-reservas/año; < 20 colaboradores. 4 pantallas nuevas + cambios en el detalle de solicitud y en el shell, 7 migraciones, 5 suites SQL.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Justification |
|-----------|--------|---------------|
| **Business Value First** | ✅ PASS | Cierra el hueco operativo principal del embudo (verificar cupos con proveedores sin API) y habilita cotizar con disponibilidad real (005). |
| **Security By Design / Default Deny** | ✅ PASS | RLS SELECT-only por tenant; INSERT/UPDATE/DELETE revocados a `authenticated`; `anon` sin privilegios; la cola y los resultados exigen rol operator/admin en la RPC (no solo en la ruta). |
| **Trust Nothing** | ✅ PASS | Toda línea se valida en SQL (producto activo, fechas, rangos, `source_request_item_id` de la solicitud origen); filas ajenas devuelven `VALIDATION_ERROR` sin revelar existencia. |
| **Simplicity Over Complexity** | ✅ PASS | Expiración por barrido idempotente al leer en lugar de `pg_cron`; una tabla con autorreferencia para alternativas; contacto con proveedores por enlaces del dispositivo, sin integraciones. |
| **Composition Over Duplication** | ✅ PASS | `require_availability_verifier()` delega en `require_catalog_manager()`; referencias con `organization_sequences`; append-only con `reject_request_note_mutation()`; conversión reutiliza el CHECK y la auditoría de 003 sin reabrir `set_request_status`. |
| **Modular Monolith / Bounded Contexts** | ✅ PASS | Capacidad nueva `core/pre-reservations` + `features/sales`; consume Customers (003) y Catalog (002) por FKs compuestas de solo lectura. |
| **Multi-Tenant Readiness** | ✅ PASS | `organization_id` en todas las tablas, FKs compuestas `(id, organization_id)`, secuencias por tenant, barrido limitado al tenant del llamador. |
| **Domain-Centric / Ubiquitous Language** | ✅ PASS | Pre-Reserva, Línea principal/alternativa, Cola de Verificación, Retención; estados canónicos del spec con etiquetas en español. |
| **Explicit State Transitions** | ✅ PASS | Estado global derivado por una única función con precedencia documentada; `cancelled` manual, con motivo y terminal; historial append-only de cada acción. |
| **Privacy & Data Governance** | ✅ PASS | La pre-reserva no guarda PII del viajero (la cola oculta correo/teléfono); auditoría de seguridad sin PII; datos de contacto del **proveedor** solo en el historial operativo. |
| **Evolution Over Prediction** | ✅ PASS | No se crea adaptador de channel managers ni gestión de proveedores; puntos de integración explícitos para 005 (`assert_pre_reservation_quotable`), 006 y 008 (R-013). |
| **Documentation Before Implementation** | ✅ PASS | Spec clarificado (sesión 2026-10-04), research R-001..R-013, data-model, contracts, quickstart y tasks antes de implementar. |

**Post Phase 1 Re-check**: ✅ All gates pass. El diseño no abre tablas a `anon`, mantiene una sola autoridad para el estado global, no duplica la regla de elegibilidad en la UI (la vista `pre_reservation_list.quote_eligible` usa la misma expresión SQL que `assert_pre_reservation_quotable`) y deja la frontera con 003 (conversión) y 005 (cotización) como contratos internos testeados.

## Project Structure

### Documentation (this feature)

```text
specs/004-prereservation-availability/
├── plan.md              # Este archivo
├── research.md          # Phase 0 — decisiones R-001..R-013
├── data-model.md        # Phase 1 — entidades, constraints, RLS, funciones
├── quickstart.md        # Phase 1 — guía de validación
├── contracts/
│   └── api-contracts.md # Phase 1 — RPCs, lecturas PostgREST, Realtime, rutas y menú
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
supabase/
├── migrations/
│   ├── 035_pre_reservation_enums.sql          # enums + valores de audit.audit_event_type
│   ├── 036_pre_reservations.sql               # tablas, vistas lista/cola, RLS, Realtime, UNIQUE en providers
│   ├── 037_pre_reservation_core.sql           # require_availability_verifier, resolve/insert/log/refresh, create_pre_reservation_core
│   ├── 038_us1_pre_reservation_conversion.sql # create_pre_reservation, cancel_pre_reservation
│   ├── 039_us2_availability_verification.sql  # assign_operator, start/record_item_verification
│   ├── 040_us3_pre_reservation_consolidation.sql # add/withdraw/promote, expire_due, authorize_quotation_override, assert_pre_reservation_quotable
│   └── 041_us4_verification_traceability.sql  # vistas availability_verification_history, pre_reservation_verification_times
├── tests/
│   ├── pre_reservation_core_test.sql          # núcleo: referencias, conversión, estado derivado, validaciones de línea
│   ├── pre_reservation_rls_test.sql           # aislamiento, Default Deny, grants de RPC
│   ├── availability_verification_test.sql     # US2: cola, inicio, resultados, roles
│   ├── pre_reservation_consolidation_test.sql # US3: ajustes, alternativas, expiración, excepción
│   └── verification_traceability_test.sql     # US4: historial append-only, tiempos
└── seed.sql                                   # + pre-reservas demo en varios estados con líneas y eventos

src/app/
├── app.routes.ts                              # /sales/pre-reservations(+ /new, /:id), /sales/verification
├── core/
│   ├── auth/models/auth.model.ts              # + códigos de error 004
│   ├── error/error-handler.ts                 # + mensajes en español
│   └── pre-reservations/
│       ├── models/
│       │   ├── pre-reservation.model.ts       # estados/etiquetas/acciones (+ .spec.ts)
│       │   └── verification.model.ts
│       ├── provider-contact-links.ts (+ .spec.ts) # tel:, wa.me, mailto:
│       └── services/
│           ├── pre-reservation.service.ts
│           ├── availability-verification.service.ts
│           └── pre-reservation-realtime.service.ts
├── features/sales/
│   ├── requests/request-detail/               # botón «Crear pre-reserva» + sección «Pre-reservas»
│   ├── pre-reservations/
│   │   ├── pre-reservation-list/
│   │   ├── pre-reservation-create/            # líneas precargadas desde la solicitud
│   │   └── pre-reservation-detail/            # resumen, servicios, cotización, historial, tiempos
│   └── verification/
│       ├── verification-queue/                # cola con filtros y agrupación por proveedor
│       └── verification-outcome-form/         # formulario de resultado en la fila
└── shared/
    ├── layout/
    │   ├── nav-items.ts (+ .spec.ts)          # «Comercial»: + Pre-reservas, Verificación
    │   └── verified-notice/                   # aviso global «Totalmente verificada» en el shell
    └── components/data-table/list-query.ts (+ .spec.ts)  # + providerId, group

docs/modules/pre-reservations.md               # nuevo; enlazado desde AGENTS.md
```

**Structure Decision**: Se extiende la app Angular + Supabase existente. La capacidad vive en `src/app/core/pre-reservations/` (modelos, servicios, lógica pura testeable) y `src/app/features/sales/` (pantallas dentro de `AdminShellComponent`, junto a Solicitudes y Clientes de 003). El backend continúa la numeración desde `035`, una migración por historia de usuario tras las fundacionales, igual que 002/003/009. No hay ruta pública ni Edge Function: la verificación es humana y el único contrato externo es el punto de integración interno para 005.

## Complexity Tracking

> No hay violaciones de gates. La expiración sin planificador (barrido al leer) es la opción más simple que cumple FR-006 sin infraestructura nueva; queda documentada en research R-004.
