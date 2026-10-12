# Implementation Plan: 006-reservation-lifecycle

**Branch**: `006-reservation-lifecycle` | **Date**: 2026-10-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-reservation-lifecycle/spec.md` (clarifications session 2026-10-09). Git checkout stays `004-prereservation-availability`; this workflow does not create a branch.

**Dependency**: Feature 005 ends at `048_us4_quotation_responses.sql` and exposes `assert_quotation_confirmable`. This feature starts at `049`. It does not renumber 004 or 005.

## Summary

Nueva capacidad **Comercial — Reservas**. Un miembro confirma una cotización aceptada: copia líneas, total, moneda y tamaño de grupo sin recalcular, exige esa cantidad de pasajeros y un anticipo manual (30 % por defecto, eximible por un administrador). El localizador es `RSV-` más 6 caracteres opacos. La misma reserva recorre Confirmada, En ejecución, Completada, Cancelada y Reprogramada. Completada y Cancelada son terminales. Las órdenes de servicio se copian o imprimen y se marcan transmitidas; no hay WhatsApp ni correo saliente. No hay pasarela ni factura electrónica. La pre-reserva no cambia de estado.

## Technical Context

**Language/Version**: TypeScript 6.x (Angular 22, Standalone Components, Signals, Signal Forms); PL/pgSQL (PostgreSQL 17). Sin Edge Functions nuevas.

**Primary Dependencies**: Angular 22, `@angular/forms/signals`, `@supabase/supabase-js`. Sin dependencias npm nuevas. Reutiliza `data-table`, `unsavedChangesGuard`, `roleGuard`, `toAppError`.

**Storage**: PostgreSQL. Tablas `reservations`, `reservation_passengers`, `reservation_items`, `reservation_payments`, `service_orders`, `reservation_events` (append-only), `reservation_settings`. Vista `reservation_list`. Bucket privado `reservation-receipts` (el comprobante es opcional si la subida falla). Migraciones `049`–`055`.

**Testing**: Suites SQL de confirmación, RLS, ciclo de vida, cambios y órdenes. Vitest para etiquetas, transiciones permitidas y el localizador que no se arma en el cliente. Validación manual en [quickstart.md](./quickstart.md).

**Target Platform**: Panel en `/sales/reservations`. El voucher se imprime dentro del detalle autenticado: lleva nombres de pasajeros y no se publica con un token anónimo.

**Project Type**: Módulo del modular monolith. Entrada: `assert_quotation_confirmable` (005). No escribe pre-reservas ni cotizaciones.

**Performance Goals**: Confirmar (copia de hasta 30 líneas) en una transacción. Listado de 20 filas paginado. El voucher sale del detalle ya cargado, sin otra consulta de precio.

**Constraints**: RLS `SELECT`-only por `organization_id`. `anon` sin privilegios. Escrituras por RPC `SECURITY DEFINER` y `search_path` vacío. Auditoría sin nombres, documentos, motivos ni informes. Un localizador no se reutiliza. Como máximo una reserva no cancelada por versión de cotización.

**Scale/Scope**: Cientos de reservas al año por tenant piloto. 3 pantallas, 7 migraciones, 5 suites SQL.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Justification |
|-----------|--------|---------------|
| **Business Value First** | ✅ PASS | Cierra la venta: la cotización aceptada pasa a ser un viaje con localizador, pasajeros y anticipo manual. |
| **Security By Design / Default Deny** | ✅ PASS | `anon` no lee reservas ni pasajeros. El voucher no es público. El bucket de comprobantes es privado. |
| **Trust Nothing** | ✅ PASS | Estado, cantidad de pasajeros, anticipo y localizador se validan en SQL. |
| **Simplicity Over Complexity** | ✅ PASS | Sin pasarela, sin factura, sin mensajería. Un localizador opaco con reintento, no un servicio aparte. |
| **Composition Over Duplication** | ✅ PASS | La elegibilidad de la cotización sigue en `assert_quotation_confirmable`. El precio no se vuelve a calcular. |
| **Modular Monolith** | ✅ PASS | `core/reservations` y pantallas en `features/sales/reservations`. |
| **Multi-Tenant Readiness** | ✅ PASS | `organization_id`, FKs compuestas, localizador único por agencia, bucket con prefijo de organización. |
| **Domain-Centric / Ubiquitous Language** | ✅ PASS | Reserva, localizador, anticipo, reprogramada, orden de servicio. |
| **Explicit State Transitions** | ✅ PASS | Una función por transición. Completada y Cancelada no salen. |
| **Privacy & Data Governance** | ✅ PASS | Documentos solo en `reservation_passengers`. Auditoría sin PII. La orden de un proveedor no muestra otro. |
| **Evolution Over Prediction** | ✅ PASS | La pasarela y la factura quedan fuera. El pago manual ya deja monto, método y referencia. |
| **Documentation Before Implementation** | ✅ PASS | Spec clarificado el 2026-10-09, research, data-model, contracts, quickstart y tasks. |

**Post Phase 1 Re-check**: ✅ All gates pass. Confirmar no actualiza `pre_reservations` ni `quotation_versions`. El comprobante ausente no bloquea la reserva.

## Project Structure

### Documentation (this feature)

```text
specs/006-reservation-lifecycle/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── api-contracts.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
supabase/migrations/
├── 049_reservation_enums.sql
├── 050_reservations.sql
├── 051_reservation_core.sql
├── 052_us1_reservation_confirm.sql
├── 053_us2_reservation_lifecycle.sql
├── 054_us3_reservation_changes.sql
└── 055_us4_service_orders.sql

supabase/tests/
├── reservation_confirm_test.sql
├── reservation_rls_test.sql
├── reservation_lifecycle_test.sql
├── reservation_changes_test.sql
└── service_orders_test.sql

src/app/core/reservations/
├── models/reservation.model.ts
└── services/reservation.service.ts

src/app/features/sales/reservations/
├── reservation-list/
├── reservation-confirm/
└── reservation-detail/
```

**Structure Decision**: Pantallas bajo Comercial. El voucher es una sección imprimible del detalle, no una ruta anónima. El backend sigue en `049` después de `048`.

## Complexity Tracking

> No hay violaciones de gates. El bucket privado reutiliza el patrón de `026_catalog_media_bucket.sql` (stub de `storage` si el harness no lo trae) y no abre los comprobantes al público.
