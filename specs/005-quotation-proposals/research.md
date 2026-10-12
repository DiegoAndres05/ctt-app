# Research: 005-quotation-proposals

Decisiones de Phase 0. La sesión de clarify del 2026-10-04 ya está en el spec. No se reabrió: no contradice a 004.

## R-001 — Una sola autoridad de cálculo

**Decision**: Cada cambio de borrador llama a `recalculate_quotation`. La UI pinta `subtotal`, `tax_total`, `adjustment_total`, `total` y el desglose por línea que devuelve el servidor. No existe una función TypeScript que multiplique precio por cantidad.

**Rationale**: FR-002 y SC-002 exigen una sola autoridad y cero discrepancias de redondeo.

**Alternatives considered**: Calcular en el cliente y confirmar en el servidor. Se rechaza porque dos redondeos pueden divergir.

## R-002 — Tarifa y cantidad

**Decision**: `resolve_quotation_tariff` lee `pricing_schemes` vigentes con la misma precedencia que `public.resolve_price` (temporada que cubre la fecha, si no la base; `valid_from` más reciente). La fecha de tarifa es `start_date` de la línea.

Tipo de cobro preferido:

| Línea | Preferido |
|-------|-----------|
| Experiencia | `per_person` |
| Alojamiento | `per_night` |
| Paquete | `per_group` (tarifa propia del paquete; no se suman componentes, regla de 002) |
| Complemento `per_person` | `per_person` |
| Complemento `per_unit` o `per_service` | `per_group` |

Si el preferido no existe y hay exactamente un tipo vigente, se usa ese y se guarda en la línea. Si no hay ninguno: `TARIFF_NOT_FOUND`. Si hay varios y ninguno es el preferido: `AMBIGUOUS_TARIFF`.

Base de cantidad:

- `per_person`: `adults + children`
- `per_night`: `quantity * (end_date - start_date)` en noches. Sin rango válido: `INVALID_DATE_RANGE`
- `per_group`: `quantity`, excepto complemento `per_service`, cuya base es 1

Solo entran líneas principales vigentes (`alternative_of_item_id IS NULL` y `withdrawn_at IS NULL`).

**Rationale**: Respeta el tipo de cobro del spec y la decisión de 002 de no sumar componentes del paquete.

**Alternatives considered**: Dejar que el agente elija el tipo de cobro. Se rechaza: la tarifa vigente ya define el tipo.

## R-003 — Redondeo, impuesto y moneda

**Decision**: Importes `numeric(14,2)`. `round(x, 2)` de PostgreSQL (half away from zero) en cada línea antes de sumar. El encabezado es la suma de líneas ya redondeadas, no un segundo redondeo del total crudo.

Orden fijo:

1. `line_base = round(unit_price * base, 2)`
2. Ajustes de línea, con signo (descuento negativo, suplemento positivo), sobre `line_base`
3. `line_net = line_base + ajustes de línea`
4. `line_tax = round(line_net * tax_rate / 100, 2)` con `tax_rate` entre 0 y 100, default 0
5. `line_total = line_net + line_tax`
6. Ajuste global sobre `sum(line_total)`
7. `total = sum(line_total) + ajuste global`

`total < 0` → `VALIDATION_ERROR`.

Moneda de la cotización: `organizations.settings ->> 'default_currency'`, o `COP` si falta. Si la tarifa está en otra moneda, el agente carga una tasa `> 0` (unidades de la moneda de la cotización por 1 unidad de la tarifa) antes de emitir. `unit_price = round(tariff_amount * tasa, 2)`. La tasa se congela al emitir en `exchange_rates`. Si todas las tarifas coinciden con la moneda de la cotización, la tasa es null.

`party_adults` = máximo de `adults` de las líneas cotizadas. `party_children` = máximo de `children`. 006 usará ese tamaño de grupo.

**Rationale**: Una moneda por cotización y tasa congelada están en el spec. El tamaño de grupo queda explícito para no reabrir el cálculo en 006.

**Alternatives considered**: Tabla de tasas diarias. Se rechaza: no hay fuente externa en este MVP y el agente ya conoce la tasa que va a honrar.

## R-004 — Elegibilidad y huella

**Decision**: Crear, recalcular, emitir, versionar y aceptar llaman a `public.assert_pre_reservation_quotable(org, pre_reservation_id)` dentro de la transacción. Esa función sigue siendo la de 004 (refresh + `verified` o excepción vigente, no cancelada).

Además, al emitir se guarda `pre_reservation_fingerprint`: arreglo JSON ordenado por `id` de las líneas principales vigentes con `product_id`, `addon_id`, `start_date`, `end_date`, `adults`, `children`, `quantity`. Al aceptar se recomputa la huella. Si difiere, la versión pasa a `expired` y la RPC levanta `QUOTATION_STALE`.

No es una contradicción con 004. `assert_pre_reservation_quotable` responde si **hoy** se puede cotizar. La huella responde si la propuesta emitida sigue describiendo los mismos servicios. Una pre-reserva puede volver a `verified` con otras líneas; esa cotización no se acepta.

**Rationale**: El spec exige rechazar la aceptación cuando las líneas principales cambiaron después de emitir.

**Alternatives considered**: Confiar solo en el estado `verified`. Se rechaza porque una re-verificación posterior dejaría aceptable una propuesta de otro itinerario.

## R-005 — Ajustes y tope del 15 %

**Decision**: Ajuste por línea (clave `pre_reservation_item_id`) o global (`pre_reservation_item_id` null). Dirección `discount` o `surcharge`. Tipo `percent` o `amount`. Valor `> 0`. Etiqueta obligatoria de 1 a 80 caracteres, guardada en la fila y **no** en la auditoría.

Tope del agente: la suma de los valores absolutos de los ajustes ya convertidos a dinero no puede superar `round(sum(line_base) * 0.15, 2)`. Por encima, `ADJUSTMENT_REQUIRES_ADMIN` salvo `require_tenant_admin()`. Si `sum(line_base) = 0`, cualquier ajuste distinto de cero exige administrador.

Cualquier ajuste sobre una versión cuyo origen ya fue emitido (versión > 1, o la familia ya tuvo una versión emitida) exige administrador, aunque esté bajo el 15 %. Un agente sí puede crear la versión nueva y emitirla sin ajustes, con tarifas recalculadas.

Los ajustes solo se escriben en `draft`. Emitida, se rechaza con `QUOTATION_FROZEN`.

**Rationale**: Traduce el tope acumulado y la regla de «ajuste sobre lo ya emitido» a una comprobación testeable.

**Alternatives considered**: Porcentajes compuestos sucesivos. Se rechaza porque el orden de captura cambiaría el tope.

## R-006 — Vigencia

**Decision**: Al emitir, `valid_until` por defecto es `issued_at + interval '48 hours'`. El agente puede fijarlo antes de emitir, entre `issued_at + 1 hour` y `issued_at + 30 days`. Si la pre-reserva tiene `expires_at`, el tope es el mínimo entre ese instante y los 30 días. Si el tope de retención es anterior al mínimo de 1 hora, `VALIDITY_EXCEEDS_HOLD` y no se emite. El default efectivo es `min(48 horas, tope)`.

`expire_due_quotations()` barre solo el tenant del llamador: versiones `issued` con `valid_until <= now()` pasan a `expired`. Lo invocan el listado, la lectura, la aceptación y la vista pública. No hay `pg_cron`.

**Rationale**: Mismo patrón de barrido que 004 (research R-004 de esa feature) y los topes del spec.

**Alternatives considered**: Job programado. El proyecto no usa `pg_cron`.

## R-007 — Versiones y respuestas

**Decision**: `quotation_families` agrupa la referencia y el token. `quotation_versions` es cada versión. La referencia `COT-#####` se asigna al emitir la v1 con `next_organization_sequence(org, 'quotation')` y `lpad` a 5 dígitos. Las versiones siguientes reutilizan la referencia.

`changes_requested` no es un estado. Inserta una fila en `quotation_responses` y la versión sigue `issued`. La UI ofrece «Crear nueva versión».

`create_quotation_version` exige origen `issued`, `rejected` o `expired`, marca ese origen `superseded` y abre un `draft` que **recalcula** tarifas (no copia importes congelados). `accepted` y `voided` rechazan con `QUOTATION_TERMINAL`.

Aceptada y anulada son terminales. Rechazada y expirada admiten versión nueva. Superada queda en solo lectura y no se acepta.

Una pre-reserva no puede tener dos familias con versión `draft`, `issued` o `accepted`. Tras anular o cerrar, se puede abrir otra familia.

**Rationale**: El spec distingue estado de cotización y respuesta «Requiere modificaciones», y exige historial inmutable.

**Alternatives considered**: Editar la emitida. Lo prohíbe FR-008 y FR-011.

## R-008 — Token público

**Decision**: Al emitir la v1 se genera un token de 32 bytes (`extensions.gen_random_bytes`), codificado en base64url. Se persiste solo `encode(extensions.digest(token, 'sha256'), 'hex')`. El token en claro se devuelve una vez en la respuesta de `issue_quotation`. La ruta es `/q/:token`.

`get_public_quotation` busca por hash. Si no existe o la versión vigente está `voided`, responde `{ available: false }` sin itinerario ni importes. El mismo texto de UI cubre token inválido y propuesta anulada. `issued`, `accepted`, `rejected` y `expired` muestran la versión vigente (la de mayor `version_number` que no esté `superseded` ni `draft`). Nunca muestran correo, teléfono, documentos, notas de agente, proveedor ni otras cotizaciones.

`accept_public_quotation` exige `p_confirmed = true`. Sin eso, `CONFIRMATION_REQUIRED` y no cambia estado.

**Rationale**: FR-007 y el edge case de anulación. El hash evita filtrar el secreto si la tabla se lee con un rol interno.

**Alternatives considered**: JWT firmado. Se rechaza: hay que guardar revocación igual, y el token aleatorio es más simple.

## R-009 — Entrega

**Decision**: `quotation_whatsapp_text(version_id)` arma en SQL el resumen y el total congelado, sin URL: el token en claro no se guarda. La pantalla añade `Detalle: <origen>/q/<token>` con el token retenido al emitir (`sessionStorage`, clave `quotation-token:<version_id>`). No hay llamada a la API de WhatsApp. «Imprimir» usa `window.print()` y CSS. No se agrega librería de PDF.

Inclusiones: si el producto tiene ficha pública publicada (009), se copian las inclusiones en español al crear el borrador. Exclusiones las escribe el agente. Ambos textos se editan en borrador y se congelan al emitir. Si no hay ficha, el agente los redacta. WordPress no interviene.

**Rationale**: El spec pide formato WhatsApp, enlace e imprimible. El envío saliente queda fuera de alcance.

**Alternatives considered**: Edge Function que envía el mensaje. El usuario dejó el WhatsApp saliente fuera o detrás de un stub que se degrada. Copiar el texto se degrada sin configuración y cumple el escenario.

## R-010 — Frontera con 006, pagos y factura

**Decision**: No se crean tablas ni RPCs de reserva, pago o factura. Al aceptar, la UI dice «La reserva se confirma en el módulo de reservas.» y no llama a ninguna RPC de confirmación.

`assert_quotation_confirmable(p_org, p_version_id)` es interna (`REVOKE` a `anon` y `authenticated`). Exige `status = accepted` y devuelve la instantánea congelada (referencia, cliente, pre-reserva, moneda, total, tamaño de grupo, líneas). 006 la llamará dentro de su confirmación. No comprueba reservas: esa tabla aún no existe.

**Rationale**: El usuario prohibió que 005 cree reservas. El pago en línea y la factura electrónica están fuera del MVP en el spec.

**Alternatives considered**: Dejar un botón «Confirmar reserva» deshabilitado que igual inserte una fila. Se rechaza.

## R-011 — Auditoría

**Decision**: Eventos nuevos en `audit.audit_event_type`: `quotation_created`, `quotation_issued`, `quotation_adjustment_applied`, `quotation_response_recorded`, `quotation_superseded`, `quotation_voided`, `quotation_expired`.

`metadata` solo lleva ids, números de versión, códigos (`origin`, `response`, `direction`, `kind`) y banderas. Nunca etiqueta, términos, notas, motivo de anulación, nombres, correo, teléfono ni el token. El motivo de anulación vive en `void_reason`. El origen de la respuesta vive en `quotation_responses` y, como código, en metadata.

**Rationale**: Misma regla que 003 y 004.

**Alternatives considered**: Guardar el diff de precios en metadata. Los importes no son PII, pero el desglose completo duplica la fila de negocio. Se audita el hecho, no la cotización entera.

## R-012 — Estados canónicos

**Decision**: Enum `quotation_status`: `draft`, `issued`, `accepted`, `rejected`, `expired`, `voided`, `superseded`.

Etiquetas: Borrador, Emitida, Aceptada, Rechazada, Expirada, Anulada, Superada por nueva versión.

El spec dice «Emitida/Enviada». En este MVP emitir no envía un mensaje; el agente entrega el enlace. La etiqueta es «Emitida».

**Rationale**: Un nombre por estado. «Enviada» sugeriría un envío que esta feature no hace.

**Alternatives considered**: Estado `sent` aparte de `issued`. Se rechaza hasta que exista un canal saliente real.
