# Research: 008-analytics-reporting

**Feature**: 008-analytics-reporting

## R-001: Dónde se calculan las métricas

**Decision**: RPCs `SECURITY DEFINER` (`analytics_funnel`, `analytics_ops_times`, `analytics_stale_queue`, `analytics_product_ranking`, `analytics_sales_summary`) con `SET search_path = ''`. El cliente pinta el JSON y **no** calcula tasas ni sumas (`canClientComputeMetrics = false`).

**Rationale**: Misma frontera que cotizaciones/reservas (FR-002 de 005, SC-002 de 008). Evita división por cero y desajustes de moneda en el browser.

**Alternatives considered**: Agregar en Angular (rechazado: SC-002/SC-003). Warehouse (fuera de Assumptions).

## R-002: Grano del embudo y conversión

**Decision**: Para un intervalo `[from, to]` en `America/Bogota` (fechas inclusivas) y canal opcional (`web` | `whatsapp` | `phone` | todos):

| Etapa | Conteo |
|-------|--------|
| Solicitudes | `customer_requests` con `created_at` en el rango; canal = `channel` |
| Pre-reservas | `pre_reservations` con `created_at` en el rango |
| Verificadas | pre-reservas cuyo `status` es `verified` (o equivalente “totalmente verificada” de 004) con `updated_at` o marca de cierre en el rango |
| Cotizaciones emitidas | `quotation_versions` con `issued_at` en el rango (no borradores) |
| Reservas confirmadas | `reservation_families` con `created_at` en el rango |

`conversion_from_previous` = etapa_n / etapa_{n-1} si el denominador > 0, si no `null`. `conversion_from_top` = etapa / solicitudes si solicitudes > 0, si no `null`. La UI muestra «—» cuando es `null`.

Canal en etapas posteriores: join a la solicitud origen (pre-reserva → request → channel). Sin request (no debería ocurrir) la fila no entra al filtro de canal.

**Rationale**: Fechas de creación/emisión, no “siguen vivas hoy”. Evita doble conteo de versiones superseded.

**Alternatives considered**: Contar solo el estado actual (subestima el funnel histórico).

## R-003: Alcance por rol

**Decision**:

- `admin` y `operator`: org completa.
- `agent`: mismas RPCs, filtro interno `created_by = auth.uid()` (solicitud capturada, cotización emitida, reserva confirmada por ese agente). Sin CSV financiero (`analytics_sales_summary` y ranking por importe → `INSUFFICIENT_PERMISSIONS` o `FORBIDDEN`).
- `anon`: sin `EXECUTE`.

**Rationale**: Edge case del spec (menor privilegio). FR-007.

**Alternatives considered**: Ocultar el menú al agente (sigue pudiendo llamar RPC). El RPC es la autoridad.

## R-004: Tiempos y estancados (US2)

**Decision**: Medias en **horas** con `numeric`, sobre pares de timestamps existentes:

- Respuesta a solicitud: `first_handled_at - created_at` (003) si `first_handled_at` no es null.
- Verificación: `verified_at` más tardío de ítems − `created_at` de la pre-reserva, solo ítems no withdrawn.
- Cotización: `issued_at - created_at` de la versión emitida.

Estancados (Atención requerida): solicitudes `received` o `in_review` con `created_at < now() - 24h`; pre-reservas no `verified` y no `cancelled` con `created_at < now() - 24h`. Límite 50 filas, las más antiguas primero.

**Rationale**: No inventar columnas nuevas; 003/004 ya guardan marcas.

## R-005: Ingresos y ranking (US3)

**Decision**: Moneda = moneda de la versión de reserva vigente (no `superseded`). En el periodo (familia `created_at`):

- **Brutos**: `sum(total)` de versiones actuales con status `confirmed` | `in_progress` | `completed` | `cancelled`.
- **Cancelados**: `sum(total)` de versiones actuales `cancelled`.
- **Netos**: brutos − cancelados.
- **Recaudado / saldo**: `paid_total` y `balance` de `reservation_list` (ya calculados en 006); el cliente no los re-suma.

Ranking: agrupar `reservation_items` de versiones no `superseded` no `cancelled` por `product_id` (add-ons aparte, etiqueta del snapshot `item_label`). Viajeros = `adults + children` sumados. Importe = `sum(line_total)` del snapshot (servidor). Top 20.

Export CSV: misma RPC de ranking/resumen, `Accept` implícito; el cliente arma CSV con BOM UTF-8. Sin Excel. Tope 10 000 filas (`VALIDATION_ERROR` si el rango es absurdo; rango máximo 366 días).

**Rationale**: SC-002 alineado a reservas 006. Excel implicaría dependencia.

## R-006: Auditoría (US4)

**Decision**: Reusar `/settings/audit`. Ampliar el union TypeScript y el `<select>` con eventos ya existentes en el enum (`price_overridden`, `reservation_cancelled`, `quotation_issued`, etc.). No hay tabla nueva. IP y metadata ya están en `audit.audit_events`. No reconstruir before/after si el evento no lo guardó (001/006 no duplican PII).

**Rationale**: Composition Over Duplication. El visor de 001 ya pagina y filtra.

## R-007: Caché y dashboard

**Decision**: Sin caché de aplicación. Índices ya existentes por org + `created_at`. Dashboard (operator+) llama `analytics_funnel` para “este mes” y enlaza a Reportes. Agente no ve widgets globales.

**Rationale**: SC-001 con volumen MVP. Invalidación de caché sería complejidad prematura.

## R-008: Fuera de alcance

Warehouse, Excel, gráficos de terceros de pago, datos de WordPress, recálculo de tarifas, abrir `anon`, mutar 049–054, cron de alertas (la cola se consulta al abrir Tiempos).
