# API Contracts: 005-quotation-proposals

Contratos internos PostgREST. El cliente autenticado usa el JWT de la organización. El cliente de la propuesta solo envía el token. Ninguna RPC acepta `organization_id` desde el navegador, salvo la interna `assert_quotation_confirmable`, que no tiene `GRANT` a `anon` ni a `authenticated`.

Errores: `RAISE EXCEPTION '<CODE>' USING ERRCODE = 'raise_exception'`. Permisos: `INSUFFICIENT_PERMISSIONS` con `insufficient_privilege`. Una fila de otra organización responde `VALIDATION_ERROR` sin revelar si existe.

## 1. Lecturas

| Lectura | Quién | Uso |
|---------|-------|-----|
| `quotation_list` | authenticated, su org | Listado paginado `range` + `count: 'exact'`, orden `created_at desc` |
| `quotation_versions` + `quotation_lines` + `quotation_adjustments` | authenticated | Detalle. El servicio no recomputa totales |
| `quotation_responses` | authenticated | Historial de respuestas |
| `quotation_defaults` | authenticated | Plantilla, solo lectura en el panel |

Antes de listar o abrir un detalle, el servicio llama a `expire_due_quotations()`.

## 2. US1 — Borrador (`045_us1_quotation_draft.sql`)

`GRANT EXECUTE` a `authenticated`.

| RPC | Éxito | Errores |
|-----|-------|---------|
| `create_quotation_draft(p_pre_reservation_id uuid)` | `{ family_id, version_id, version_number, status: 'draft', currency, lines[], subtotal, tax_total, adjustment_total, total, pending_currencies }` | `PRE_RESERVATION_NOT_VERIFIED`, `PRE_RESERVATION_EXPIRED`, `PRE_RESERVATION_CLOSED`, `QUOTATION_ALREADY_OPEN`, `QUOTATION_ALREADY_ACCEPTED`, `TARIFF_NOT_FOUND`, `AMBIGUOUS_TARIFF` |
| `recalculate_quotation(p_version_id uuid)` | mismo desglose | `QUOTATION_FROZEN`, `TARIFF_NOT_FOUND`, `AMBIGUOUS_TARIFF`, `EXCHANGE_RATE_REQUIRED`, `VALIDATION_ERROR` |
| `set_quotation_line_tax(p_line_id uuid, p_tax_rate numeric)` | desglose | `TAX_RATE_OUT_OF_RANGE`, `QUOTATION_FROZEN` |
| `set_quotation_exchange_rate(p_version_id uuid, p_currency text, p_rate numeric)` | desglose | `EXCHANGE_RATE_INVALID`, `QUOTATION_FROZEN` |
| `set_quotation_texts(p_version_id uuid, p_inclusions text, p_exclusions text, p_notes text)` | `{ version_id }` | `VALIDATION_ERROR` si supera 4000/4000/2000, `QUOTATION_FROZEN` |
| `upsert_quotation_adjustment(p_version_id uuid, p_pre_reservation_item_id uuid, p_label text, p_direction quotation_adjustment_direction, p_kind quotation_adjustment_kind, p_value numeric)` | desglose. `p_pre_reservation_item_id` null = global | `ADJUSTMENT_REQUIRES_ADMIN`, `ADJUSTMENT_LABEL_REQUIRED`, `QUOTATION_FROZEN`, `VALIDATION_ERROR` |
| `delete_quotation_adjustment(p_adjustment_id uuid)` | desglose | `QUOTATION_FROZEN` |

`EXCHANGE_RATE_REQUIRED` cuando falta tasa para una moneda distinta. El borrador se guarda igual si el agente todavía no emite, pero `issue_quotation` no avanza hasta que la tasa exista. `create_quotation_draft` devuelve el desglose y, si falta tasa, incluye `pending_currencies: ['USD']` sin fallar. `issue_quotation` sí falla.

## 3. US2 — Emisión (`046_us2_quotation_issue.sql`)

| RPC | Quién | Éxito | Errores |
|-----|-------|-------|---------|
| `set_quotation_terms(p_version_id uuid, p_terms text, p_valid_until timestamptz)` | member | `{ version_id, valid_until, terms }` | `VALIDITY_EXCEEDS_HOLD`, `VALIDITY_EXCEEDS_30_DAYS`, `TERMS_REQUIRED`, `QUOTATION_FROZEN` |
| `issue_quotation(p_version_id uuid)` | member | `{ version_id, reference, version_number, status: 'issued', valid_until, public_token, total, currency }` | `EXCHANGE_RATE_REQUIRED`, `TERMS_REQUIRED`, `TARIFF_NOT_FOUND`, `PRE_RESERVATION_*`, `QUOTATION_FROZEN`, `VALIDITY_EXCEEDS_HOLD` |
| `expire_due_quotations()` | member | `{ expired_count }` | — |
| `upsert_quotation_defaults(p_terms text)` | admin | `{ organization_id }` | `TERMS_REQUIRED`, `INSUFFICIENT_PERMISSIONS` |

`public_token` solo viaja en esta respuesta. No se vuelve a leer de la base.

## 4. US3 — Entrega (`047_us3_quotation_delivery.sql`)

### `get_public_quotation(p_token text) → jsonb`

`GRANT EXECUTE` a `anon` y `authenticated`. `SECURITY DEFINER`.

Token vacío o desconocido, o versión vigente `voided`:

```json
{ "available": false }
```

Versión vigente `issued`, `accepted`, `rejected` o `expired`:

```json
{
  "available": true,
  "status": "issued",
  "reference": "COT-00001",
  "version_number": 1,
  "currency": "COP",
  "valid_until": "2026-10-11T15:00:00Z",
  "party_adults": 2,
  "party_children": 0,
  "inclusions": "",
  "exclusions": "",
  "terms": "",
  "subtotal": 1000,
  "tax_total": 0,
  "adjustment_total": 0,
  "total": 1000,
  "lines": [
    {
      "label": "City tour",
      "kind": "experience",
      "start_date": "2026-11-01",
      "end_date": null,
      "charge_basis": 2,
      "unit_price": 500,
      "tax_rate": 0,
      "line_total": 1000
    }
  ],
  "adjustments": [
    { "label": "Temporada", "direction": "surcharge", "kind": "percent", "value": 0 }
  ],
  "can_accept": true
}
```

`can_accept` es true solo si `status = issued` y `valid_until > now()`. No incluye `customer_id`, correo, teléfono, notas, proveedor, `pre_reservation_id` ni token.

### `quotation_whatsapp_text(p_version_id uuid) → text`

Authenticated. Ejemplo de forma (los importes salen de columnas congeladas):

```text
✨ Propuesta COT-00001
City tour · 1 nov 2026 · 2 viajeros
Total: COP 1.000
Vigente hasta: 11 oct 2026, 10:00
Detalle: https://<origen>/q/<token>
```

La función no tiene el token en claro. El servicio de Angular concatena el token que guardó en memoria al emitir, o el agente copia el enlace que la pantalla ya muestra. El RPC devuelve el cuerpo **sin** URL; la pantalla añade la línea `Detalle: ${origin}/q/${token}` con el token retenido en el estado de esa sesión. Si el agente recarga, la pantalla dice «El enlace se mostró al emitir. Anulá y emití una versión nueva si lo perdiste.» No se regenera el token en el MVP (el hash no es reversible).

Esa limitación se acepta: el token se muestra una vez en el detalle tras emitir y el agente puede copiarlo antes de salir. La pantalla lo guarda en `sessionStorage` bajo `quotation-token:<version_id>` para sobrevivir una recarga de la pestaña, no un cierre del navegador. No se escribe en la base.

## 5. US4 — Respuesta y versión (`048_us4_quotation_responses.sql`)

| RPC | Quién | Éxito | Errores |
|-----|-------|-------|---------|
| `record_quotation_response(p_version_id uuid, p_kind quotation_response_kind)` | member | `{ version_id, status, response }` | `QUOTATION_NOT_OPEN`, `QUOTATION_STALE`, `PRE_RESERVATION_*`, `QUOTATION_TERMINAL` |
| `accept_public_quotation(p_token text, p_confirmed boolean)` | anon, authenticated | `{ available: true, status: 'accepted' }` | `CONFIRMATION_REQUIRED`, `QUOTATION_NOT_OPEN`, `QUOTATION_STALE`, `PRE_RESERVATION_*` |
| `create_quotation_version(p_version_id uuid)` | member | borrador vN+1 | `QUOTATION_TERMINAL`, `PRE_RESERVATION_*`, `TARIFF_NOT_FOUND` |
| `void_quotation(p_version_id uuid, p_reason text)` | admin | `{ version_id, status: 'voided' }` | `VOID_REASON_REQUIRED`, `QUOTATION_ACCEPTED`, `INSUFFICIENT_PERMISSIONS` |
| `assert_quotation_confirmable(p_org uuid, p_version_id uuid)` | interna | instantánea congelada | `QUOTATION_NOT_ACCEPTED`, `VALIDATION_ERROR` |

`record_quotation_response('accepted')` y `accept_public_quotation` hacen, en orden: `expire_due_quotations`, rechazar si ya no está `issued`, `assert_pre_reservation_quotable`, comparar huella. Si la huella falla, la versión queda `expired` y se audita `quotation_expired` con `{ reason_code: 'stale' }`.

`changes_requested` inserta respuesta, audita `{ response: 'changes_requested', origin: 'agent' }` y deja `status = issued`.

## 6. Rutas y menú

| Ruta | Guard | Pantalla |
|------|-------|----------|
| `/sales/quotations` | `roleGuard('agent')` dentro del shell | Listado |
| `/sales/quotations/new` | `roleGuard('agent')`, `unsavedChangesGuard` | Alta; query `preReservationId` llama a `create_quotation_draft` |
| `/sales/quotations/:versionId` | `roleGuard('agent')`, `unsavedChangesGuard` si `draft` | Detalle / editor |
| `/q/:token` | ninguna; fuera del shell | Vista pública |

Menú Comercial, hijo nuevo en `src/app/shared/layout/nav-items.ts`:

```ts
{ id: 'sales-quotations', label: 'Cotizaciones', path: '/sales/quotations', minRole: 'agent' }
```

No se quitan Solicitudes, Clientes ni los ítems que agregue 004.

En el detalle de pre-reserva de 004 (`pre-reservation-detail.component.ts`), si `quote_eligible`, botón «Crear cotización» hacia `/sales/quotations` con query `preReservationId`. Si el archivo de 004 aún no existe al implementar, esta tarea espera a que exista; no se crea el módulo de pre-reservas aquí.

## 7. Copy de la UI (español)

| Situación | Texto |
|-----------|-------|
| Listado vacío | Todavía no hay cotizaciones. |
| Título listado | Cotizaciones |
| Crear | Nueva cotización |
| Emitir | Emitir cotización |
| Recalcular | Recalcular |
| Impuesto | Impuesto (%) |
| Ajuste sobre el tope | Este ajuste supera el 15 % y requiere un administrador. |
| Vigencia inválida | La vigencia no puede pasar de la retención ni de 30 días. |
| Emitida | Cotización COT-00001 emitida. El enlace público se muestra una sola vez. |
| Copiar WhatsApp | Copiar para WhatsApp |
| Imprimir | Imprimir |
| Aceptar (público) | Aceptar propuesta |
| Confirmar (público) | Confirmar aceptación |
| Tras aceptar | Propuesta aceptada. La reserva se confirma en el módulo de reservas. |
| No disponible | Esta propuesta ya no está disponible. |
| Expirada | Esta propuesta expiró. Hay que emitir una versión nueva. |
| Requiere modificaciones | Registrar «Requiere modificaciones» |
| Nueva versión | Crear nueva versión |
| Anular | Anular cotización |
| Motivo anulación | Motivo de la anulación |
| Superada | Superada por nueva versión |
| Plantilla | Plantilla de condiciones |
| Token perdido | El enlace se mostró al emitir. Si se perdió, anule y emita una versión nueva. |

## 8. Auditoría

`audit.log_event` con `resource_type = 'quotation_version'` y `resource_id` de la versión. Metadata permitida: `family_id`, `version_number`, `pre_reservation_id`, `response`, `origin`, `direction`, `kind`, `reason_code`. Prohibido: `label`, `terms`, `notes`, `void_reason`, `public_token`, nombres, correo, teléfono.
