# Quickstart: 008-analytics-reporting

Prueba manual con migraciones `055`+, seed y `npm start`. SQL: `./supabase/tests/run-sql-tests.sh analytics_funnel_test.sql analytics_ops_test.sql analytics_sales_test.sql analytics_rls_test.sql`.

## Prerequisites

- Features 001–006 aplicadas (última de 006: `054_us4_provider_orders_voucher.sql`).
- Datos: al menos una solicitud; idealmente el flujo hasta reserva. Si el seed no tiene reserva, las suites SQL insertan un periodo sintético.
- `operador@demo-turismo.test` / `DemoPass123!` y `agente@demo-turismo.test` (cambio de clave).

## Scenarios

### 1. Embudo (US1)

1. Operator: Reportes → Embudo, mes actual, canal Todos.
2. Filtrar WhatsApp.

**Esperado**: cinco etapas, tasas o «—»; filtro WhatsApp cambia conteos. SQL: `analytics_funnel_test.sql` (ceros sin división).

### 2. Tiempos y estancados (US2)

1. Reportes → Tiempos.
2. Ver “Atención requerida” si hay solicitudes > 24 h.

**Esperado**: medias en horas o «—»; lista o vacío. SQL: `analytics_ops_test.sql`.

### 3. Productos y CSV (US3)

1. Reportes → Productos.
2. Descargar CSV.

**Esperado**: brutos / cancelados / netos del servidor; CSV abre en hoja de cálculo. Agente no ve el menú. SQL: `analytics_sales_test.sql`.

### 4. Auditoría (US4)

1. Configuración → Auditoría.
2. Filtrar cancelación de reserva o cambio de precio (si hay eventos).

**Esperado**: filas inmutables con actor y fecha. Tipos nuevos en el select.

### 5. RLS

SQL: `anon` sin EXECUTE; agente no llama `analytics_sales_summary`.

## Automated evidence

| Scenario | Suite |
|----------|--------|
| 1 | `analytics_funnel_test.sql` |
| 2 | `analytics_ops_test.sql` |
| 3 | `analytics_sales_test.sql` |
| 5 | `analytics_rls_test.sql` |
