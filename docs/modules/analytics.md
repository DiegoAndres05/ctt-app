# Analytics & Reporting (008-analytics-reporting)

Operational funnel, cycle times, product ranking and CSV export. Amounts and conversion
rates are computed in Postgres RPCs. The UI only paints JSON. The audit viewer in
Configuración is extended with operational event types (no second log, no `056` migration).

**Spec**: `specs/008-analytics-reporting/`
**Plan**: `specs/008-analytics-reporting/plan.md`

## What lives where

| Concern | Location |
| --- | --- |
| RPCs | `supabase/migrations/055_analytics_rpcs.sql` |
| SQL tests | `supabase/tests/analytics_*_test.sql` |
| Models / service | `src/app/core/analytics/` |
| Screens | `src/app/features/analytics/` |
| Dashboard widgets | `src/app/features/dashboard/dashboard.component.ts` |
| Audit filters | `src/app/features/audit/audit-log/` |

## RPCs

`analytics_funnel`, `analytics_ops_times`, `analytics_stale_queue` (authenticated member;
agent scoped to self). `analytics_sales_summary`, `analytics_product_ranking` (operator/admin).

## Routes

`/reports/funnel` (agent+), `/reports/ops` and `/reports/products` (operator+).

## Quickstart mapping

Pass of 2026-10-22.

| Check | Result |
| --- | --- |
| SQL `analytics_rls_test.sql`, `analytics_funnel_test.sql`, `analytics_ops_test.sql`, `analytics_sales_test.sql` | Passed |
| `055` applied locally (`supabase migration up --local`) | Applied |
| Dashboard widget `/dashboard` as operator | Embudo de este mes: 2 solicitudes, 2 pre-reservas, 0 verificadas / cotizaciones / reservas |
| `/reports/funnel` | Embudo comercial; mismos conteos; CSV habilitado |
| `/reports/ops` | Tiempos operativos; cola «Nada pendiente de atención» |
| `/reports/products` | Vacío (sin reservas confirmadas en seed); CSV deshabilitado |
| Rango > 366 días | `El rango no puede superar 366 días.` (`DATE_RANGE_TOO_LONG`) |

Seed still has no accepted quotation, so ranking/revenue stays empty until a 006 confirmation.
