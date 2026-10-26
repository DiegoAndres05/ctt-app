# Data Model: 008-analytics-reporting

**Feature**: 008-analytics-reporting

No hay entidades persistidas nuevas. Los “Key Entities” del spec son **DTOs** que devuelven las RPCs.

## DTO: ConversionMetric (embudo)

| Campo | Tipo | Notas |
|-------|------|--------|
| `stage` | text | `requests`, `pre_reservations`, `verified`, `quotations_issued`, `reservations_confirmed` |
| `label` | text | Español para la UI |
| `count` | int | ≥ 0 |
| `conversion_from_previous` | numeric \| null | 0–1; null si denominador 0 |
| `conversion_from_top` | numeric \| null | vs solicitudes |

Cabecera: `{ from, to, channel, scope: 'org' \| 'self', stages: ConversionMetric[] }`.

## DTO: OpsTimes

| Campo | Tipo |
|-------|------|
| `avg_request_response_hours` | numeric \| null |
| `avg_verification_hours` | numeric \| null |
| `avg_quotation_issue_hours` | numeric \| null |
| `sample_request`, `sample_verification`, `sample_quotation` | int |

## DTO: StaleItem

| Campo | Tipo |
|-------|------|
| `kind` | `request` \| `pre_reservation` |
| `id` | uuid |
| `reference` | text |
| `age_hours` | numeric |
| `status` | text |

## DTO: SalesSummary

| Campo | Tipo |
|-------|------|
| `currency` | char(3) |
| `gross` | numeric(14,2) |
| `cancelled` | numeric(14,2) |
| `net` | numeric(14,2) |
| `paid_total` | numeric(14,2) |
| `balance` | numeric(14,2) |

Una fila por moneda presente.

## DTO: ProductRankRow

| Campo | Tipo |
|-------|------|
| `product_id` | uuid \| null |
| `item_label` | text |
| `item_kind` | text |
| `traveler_count` | int |
| `reservation_count` | int |
| `revenue` | numeric(14,2) |
| `currency` | char(3) |

## Validación de filtros (todas las RPCs)

- `p_from`, `p_to`: `date`, `from ≤ to`, `to - from ≤ 366`.
- `p_channel`: null = todos; si no, valor de `request_channel`.
- `VALIDATION_ERROR` si el rango es inválido.

## Índices

No se añaden tablas. Si una consulta de rango no usa índice existente, migración 055 puede crear `CREATE INDEX IF NOT EXISTS` en `(organization_id, created_at)` solo donde falte (verificar 029/036/043/050 antes).

## Auditoría

Sin modelo nuevo. El visor lee `audit.audit_events` (001). 008 solo completa el catálogo de `event_type` en el cliente.
