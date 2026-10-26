# API & UI Contracts: 008-analytics-reporting

## 1. RPCs (`GRANT EXECUTE` a `authenticated`)

Todas: `require_tenant_member()`, rango de fechas (research R-002/R-008). `REVOKE` a `anon`.

### `analytics_funnel(p_from date, p_to date, p_channel text)`

JSON: `{ from, to, channel, scope, stages[] }` según data-model. Agente → `scope: self`.

### `analytics_ops_times(p_from date, p_to date, p_channel text)`

JSON OpsTimes. Operator/admin: org. Agente: propias (mismo criterio de R-003).

### `analytics_stale_queue()`

JSON `{ items: StaleItem[] }`. Operator/admin. Agente: solo ítems que creó. Vacío = `{ items: [] }`.

### `analytics_sales_summary(p_from date, p_to date)`

JSON `{ currencies: SalesSummary[] }`. Solo operator/admin. Agente: `INSUFFICIENT_PERMISSIONS`.

### `analytics_product_ranking(p_from date, p_to date, p_limit int)`

JSON `{ rows: ProductRankRow[] }`. `p_limit` default 20, max 100. Ranking por `revenue` desc luego `traveler_count`. Importe: operator/admin. Agente: puede recibir conteos sin `revenue` o el RPC rechaza importe — **decisión**: agente no llama esta RPC (`INSUFFICIENT_PERMISSIONS`); el menú Productos es `hideForAgent`.

## 2. Errores

| Código | Mensaje ES |
|--------|------------|
| `VALIDATION_ERROR` | (existente) rango inválido |
| `INSUFFICIENT_PERMISSIONS` | (existente) agente en finanzas / anon |
| `UNKNOWN_ERROR` | (existente) |

Sin códigos nuevos si los existentes cubren. Si hace falta: `DATE_RANGE_TOO_LONG` «El rango no puede superar 366 días.»

## 3. CSV

El cliente, con las filas ya recibidas, descarga `text/csv; charset=utf-8` (BOM). Columnas = claves del DTO. Nombre `embudo-YYYY-MM-DD.csv` etc. No hay RPC de archivo.

## 4. UI

| Path | Quién | Pantalla |
|------|--------|----------|
| `/reports/funnel` | agent+ | Embudo + filtro fechas/canal + export CSV (agente: su scope) |
| `/reports/ops` | operator+ | Tiempos + Atención requerida |
| `/reports/products` | operator+ | Ranking + resumen por moneda + CSV |
| `/dashboard` | operator+ | Resumen del mes + enlace a Reportes; agente: saludo actual |
| `/settings/audit` | admin | Visor existente + tipos 002–006 |

Textos:

| Situación | Texto |
|-----------|--------|
| Sin datos | `No hay movimientos en este período.` |
| Tasa nula | `—` |
| Export | `Descargar CSV` |

Menú: grupo **Reportes** (`minRole: operator`) con Embudo también visible para agent (`minRole: agent` en el hijo funnel). Productos y Tiempos `hideForAgent`.

## 5. Auditoría visor

Añadir al select (si el enum ya los tiene): al menos `reservation_cancelled`, `reservation_confirmed`, `quotation_issued`, `price_overridden`, `role_changed`. Filtros fecha/actor ya existen.
