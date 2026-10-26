---
description: "Task list for 008-analytics-reporting implementation"
---

# Tasks: 008-analytics-reporting (Reportes)

**Input**: Design documents from `/specs/008-analytics-reporting/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts, quickstart. Features 001–006. Última migración `054`. Esta feature empieza en `055`. No editar `049`–`054`. UI no calcula tasas ni sumas. Sin warehouse ni Excel.

**Tests**: Suites SQL + Vitest de modelos. Quedan sin marcar hasta ejecutarlas.

**Organization**: US1–US4 de spec.md.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

- Backend: `supabase/migrations/` desde `055_`, `supabase/tests/`
- Frontend: `src/app/core/analytics/`, `src/app/features/analytics/`, dashboard, audit-log, `app.routes.ts`, `nav-items.ts`
- Docs: `docs/modules/analytics.md`

## Conventions every task must follow

- SQL: `SECURITY DEFINER`, `SET search_path = ''`, `RAISE EXCEPTION '<CODE>'`, `REVOKE ALL` PUBLIC, `GRANT EXECUTE` authenticated. Fechas `America/Bogota`.
- Suites: `BEGIN`/`ROLLBACK`, `pg_temp.act_as`, `tests.assert_*` (query text para `assert_true`; `assert_equals(actual, expected, desc)`).
- Angular: standalone, OnPush, signals, `toAppError`. `canClientComputeMetrics = false`.
- No service role en `src/`. No mutar 049–054.

---

## Phase 1: Setup

- [X] T001 Crear carpetas `.gitkeep`: `src/app/core/analytics/models/`, `src/app/core/analytics/services/`, `src/app/features/analytics/funnel/`, `src/app/features/analytics/ops/`, `src/app/features/analytics/sales/`

---

## Phase 2: Foundational

- [X] T002 Crear `src/app/core/analytics/models/analytics.model.ts` y `analytics.model.spec.ts`: etapas, DTOs, `canClientComputeMetrics = false`, `FUNNEL_STAGE_LABELS`
- [X] T003 [P] Registrar `DATE_RANGE_TOO_LONG` «El rango no puede superar 366 días.» en `auth.model.ts`, `error-handler.ts`, `error-handler.spec.ts`
- [X] T004 [P] Crear `supabase/tests/analytics_rls_test.sql`: `anon` sin EXECUTE de las RPCs 055; agente no ejecuta `analytics_sales_summary`

**Checkpoint**: Modelos y error listos. RPCs aún no existen (T004 falla hasta T005).

---

## Phase 3: US1 Embudo 🎯 MVP

**Independent Test**: quickstart §1 y `analytics_funnel_test.sql`

- [X] T005 [P] [US1] Crear `supabase/tests/analytics_funnel_test.sql`: periodo con 2 web + 1 whatsapp; etapas y tasas; canal whatsapp; ceros → conversión null
- [X] T006 [US1] Crear `supabase/migrations/055_analytics_rpcs.sql` con helper de rango y `analytics_funnel` según contracts §1 y research R-002/R-003
- [X] T007 [US1] Crear `src/app/core/analytics/services/analytics.service.ts`: `funnel(...)`, `downloadCsv(...)` (no suma)
- [X] T008 [US1] Crear `src/app/features/analytics/funnel/funnel-report.component.ts`: filtros fechas/canal, etapas, «—», vacío, CSV
- [X] T009 [US1] Rutas `/reports/funnel` (`roleGuard('agent')`), nav grupo Reportes + hijo Embudo; `nav-items.spec.ts`

**Checkpoint**: Embudo usable.

---

## Phase 4: US2 Tiempos

- [X] T010 [P] [US2] Crear `supabase/tests/analytics_ops_test.sql`: medias y cola >24 h
- [X] T011 [US2] Añadir `analytics_ops_times` y `analytics_stale_queue` en `055_analytics_rpcs.sql`
- [X] T012 [US2] Métodos en `analytics.service.ts` y `ops-report.component.ts`; ruta `/reports/ops` operator+; nav Tiempos `hideForAgent`

**Checkpoint**: Tiempos y Atención requerida.

---

## Phase 5: US3 Productos

- [X] T013 [P] [US3] Crear `supabase/tests/analytics_sales_test.sql`: brutos/cancelados/netos; ranking; agente `INSUFFICIENT_PERMISSIONS`
- [X] T014 [US3] Añadir `analytics_sales_summary` y `analytics_product_ranking` en `055`
- [X] T015 [US3] `sales-report.component.ts`, ruta `/reports/products` operator+, CSV, nav Productos

**Checkpoint**: Ranking e ingresos del servidor.

---

## Phase 6: US4 Auditoría

- [X] T016 [US4] Extender `audit-event.model.ts` y `audit-log.component.ts` con tipos 002–006 (al menos `price_overridden`, `quotation_issued`, `reservation_cancelled`, `reservation_confirmed`). Sin migración de tabla. `056` solo si hace falta un GRANT; si no, omitir archivo y documentar en el módulo

**Checkpoint**: Filtro de auditoría cubre operaciones.

---

## Phase 7: Polish

- [X] T017 [P] Widgets de embudo del mes en `dashboard.component.ts` para operator/admin
- [X] T018 [P] `docs/modules/analytics.md` + puntero en `AGENTS.md`; comentario de suites en `run-sql-tests.sh`
- [X] T019 Quickstart mapping en el módulo (SQL vs browser). Pasada 2026-10-22: SQL + browser operador (`/dashboard`, `/reports/funnel`, `/reports/ops`, `/reports/products`, rango > 366).

---

## Dependencies

US1 MVP. US2–US3 añaden RPCs al mismo `055` si se implementan juntas. US4 independiente del visor. Polish al final.

## MVP

T001–T009 (embudo).

## Notes

- Última migración prevista: `055` (y `056` solo si es estrictamente necesario).
- No marcar tareas hasta implementar.
