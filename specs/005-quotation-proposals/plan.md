# Implementation Plan: 005-quotation-proposals

**Branch**: `005-quotation-proposals` | **Date**: 2026-10-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-quotation-proposals/spec.md` (clarifications session 2026-10-04). Git checkout stays `004-prereservation-availability`; this workflow does not create a branch.

**Dependency**: Feature 004 owns migrations `035`–`041` and the internal function `public.assert_pre_reservation_quotable`. This feature starts at `042`. It does not renumber 004 and does not edit `supabase/migrations/035_pre_reservation_enums.sql` or the empty 004 folders already in the working tree.

## Summary

Nueva capacidad **Comercial — Cotizaciones**. Un agente crea un borrador a partir de una pre-reserva elegible (`assert_pre_reservation_quotable`). El servidor es la única autoridad del precio: resuelve la tarifa vigente de 002, aplica el tipo de cobro, impuestos por línea (0 % por defecto), ajustes comerciales y redondeo, y devuelve el desglose. Al emitir se asigna `COT-#####`, se congela el dinero, se fija la vigencia (48 h por defecto, tope 30 días y nunca después de la retención de 004) y se crea un token público opaco. El cliente ve `/q/:token` fuera del shell y puede aceptar con confirmación explícita; el agente registra Aceptada, Rechazada o Requiere modificaciones. Aceptar revalida la pre-reserva y la huella de líneas congelada en la emisión. Una versión nueva deja la anterior como «Superada por nueva versión». Esta feature no crea reservas, no cobra y no factura.

No hubo contradicción con 004 que obligara a reabrir la sesión 2026-10-04. `assert_pre_reservation_quotable` sigue siendo la elegibilidad vigente; la comparación de huella es la regla adicional de 005 para «las líneas cambiaron después de emitir» (research R-004).

## Technical Context

**Language/Version**: TypeScript 6.x (Angular 22, Standalone Components, Signals, Signal Forms); PL/pgSQL (PostgreSQL 17). Sin Edge Functions nuevas.

**Primary Dependencies**: Angular 22, `@angular/router`, `@angular/forms/signals`, `@supabase/supabase-js` (PostgREST). Sin dependencias npm nuevas. Reutiliza `data-table`, `unsavedChangesGuard`, `roleGuard`, `toAppError`.

**Storage**: PostgreSQL vía Supabase. Tablas `quotation_families`, `quotation_versions`, `quotation_lines`, `quotation_adjustments`, `quotation_responses` (append-only), `quotation_defaults`. Vista `security_invoker` `quotation_list`. Secuencia `organization_sequences` con scope `quotation`. Token público guardado solo como SHA-256 (`extensions.digest`). Migraciones `042`–`048`.

**Testing**: Suites SQL en `supabase/tests/*_test.sql` (harness Postgres 17, `./supabase/tests/run-sql-tests.sh`) para precio, RLS, emisión/vigencia, vista pública y versionado. Vitest para etiquetas de estado, reglas de botones y el contrato de que la UI no recompone totales. Validación manual según [quickstart.md](./quickstart.md).

**Target Platform**: Panel en `/sales/quotations`. Vista de cliente en `/q/:token`, pública, fuera de `AdminShellComponent`. Sin WhatsApp saliente: el agente copia un texto que arma el servidor.

**Project Type**: Módulo del modular monolith. Contratos: RPCs `SECURITY DEFINER` y una vista `security_invoker`. Punto de entrada desde 004: `assert_pre_reservation_quotable`. Punto de salida hacia 006: `assert_quotation_confirmable` (interna; no inserta reservas).

**Performance Goals**: Recalcular un borrador de hasta 30 líneas en la misma transacción. Listado de 20 filas con `range` + `count: 'exact'`. La vista pública responde con un solo RPC.

**Constraints**: RLS `SELECT`-only por `organization_id`. `anon` no lee tablas de cotización; solo ejecuta `get_public_quotation` y `accept_public_quotation`. Escrituras por RPC con `SET search_path = ''`. Auditoría sin PII ni motivos en `metadata`. La UI no suma importes. No pasarela de pago, no factura electrónica, no envío WhatsApp, no tabla `reservations`.

**Scale/Scope**: Un tenant piloto, diseño multi-tenant. Cientos de cotizaciones al año. 3 pantallas de panel + 1 página pública, 7 migraciones, 5 suites SQL.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Justification |
|-----------|--------|---------------|
| **Business Value First** | ✅ PASS | Convierte una pre-reserva verificada en una propuesta con precio, vigencia y respuesta del cliente, sin adelantar la reserva (006). |
| **Security By Design / Default Deny** | ✅ PASS | Tablas opacas para `anon`. El token es aleatorio y solo se persiste su hash. Anular deja de devolver datos. |
| **Trust Nothing** | ✅ PASS | Elegibilidad, tarifa, tope del 15 %, vigencia y aceptación se deciden en SQL. La confirmación pública exige `p_confirmed = true`. |
| **Simplicity Over Complexity** | ✅ PASS | Sin PDF de terceros, sin pasarela, sin cron: expiración por barrido al leer, impresión con el navegador, WhatsApp por texto copiable. |
| **Composition Over Duplication** | ✅ PASS | Reutiliza `assert_pre_reservation_quotable`, `resolve_price` (misma regla de tarifa vigente), `next_organization_sequence` y `audit.log_event`. |
| **Modular Monolith** | ✅ PASS | Capacidad `core/quotations` + pantallas en `features/sales/quotations`. La página pública es una ruta suelta, no una segunda aplicación. |
| **Multi-Tenant Readiness** | ✅ PASS | `organization_id` en todas las tablas, FKs compuestas, secuencia y barrido del tenant del llamador. El token no acepta un `organization_id` del cliente. |
| **Domain-Centric / Ubiquitous Language** | ✅ PASS | Cotización, versión, ajuste, vigencia, superada. Estados canónicos del spec con etiquetas en español. |
| **Explicit State Transitions** | ✅ PASS | Borrador → Emitida → Aceptada / Rechazada / Expirada / Anulada / Superada. Aceptada y Anulada son terminales. |
| **Privacy & Data Governance** | ✅ PASS | La vista pública no lleva correo, teléfono, documentos, notas internas ni datos de otros clientes. Metadata de auditoría sin textos libres. |
| **WordPress solo editorial** | ✅ PASS | La cotización no se publica ni se edita en WordPress. |
| **Evolution Over Prediction** | ✅ PASS | 006 confirmará la reserva llamando a `assert_quotation_confirmable`. El pago y la factura quedan fuera. |
| **Documentation Before Implementation** | ✅ PASS | Spec ya clarificado (2026-10-04), research, data-model, contracts, quickstart y tasks antes de implementar. |

**Post Phase 1 Re-check**: ✅ All gates pass. El diseño no abre las tablas a `anon`, no calcula totales en el cliente, no inserta en `reservations` y deja la frontera con 004 y 006 como funciones internas testeadas.

## Project Structure

### Documentation (this feature)

```text
specs/005-quotation-proposals/
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
supabase/
├── migrations/
│   ├── 042_quotation_enums.sql
│   ├── 043_quotations.sql
│   ├── 044_quotation_pricing.sql
│   ├── 045_us1_quotation_draft.sql
│   ├── 046_us2_quotation_issue.sql
│   ├── 047_us3_quotation_delivery.sql
│   └── 048_us4_quotation_responses.sql
├── tests/
│   ├── quotation_pricing_test.sql
│   ├── quotation_rls_test.sql
│   ├── quotation_issue_test.sql
│   ├── quotation_public_test.sql
│   └── quotation_version_test.sql
└── seed.sql

src/app/
├── app.routes.ts
├── core/
│   ├── auth/models/auth.model.ts
│   ├── error/error-handler.ts
│   └── quotations/
│       ├── models/quotation.model.ts (+ .spec.ts)
│       └── services/quotation.service.ts
└── features/
    ├── public-quotation/public-quotation.component.ts
    └── sales/quotations/
        ├── quotation-list/
        ├── quotation-detail/
        └── quotation-editor/
```

**Structure Decision**: Se extiende el panel Angular + Supabase. El agente trabaja en `/sales/quotations`. El cliente abre `/q/:token` sin sesión y sin shell. El backend continúa en `042` después de `041`. No hay segunda app ni Edge Function.

## Complexity Tracking

> No hay violaciones de gates. La página pública fuera del shell es el mismo patrón que `/login`: el cliente no es un colaborador y no debe entrar a Comercial.
