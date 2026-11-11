# Estabilización del entorno local — 2026-11-11

**Alcance**: corrección de los defectos D1 y D2 reportados en `docs/e2e-2026-11-09.md`, reparación de los dos fixtures SQL rotos y verificación por niveles (unitarias → SQL → integración RPC → E2E en navegador) según la Constitución §13 y el Quality Gate 12.

**Entorno**: rama `main` (sin commits), Supabase local (`127.0.0.1:54321`, CLI 2.117.0, sin `db reset`), `ng serve` en `http://localhost:4201` (arrancado con `preview_start ctt-app`), navegador integrado, cuenta seed `admin@demo-turismo.test`. Arnés SQL `./supabase/tests/run-sql-tests.sh` (PostgreSQL 17 desechable en Docker).

---

## A. Resumen ejecutivo

**Estado inicial (medido hoy, no tomado del informe del 09-11)**

- Unitarias: 138/138 (18 archivos).
- SQL: 41/43. El arnés oficial se detiene en el primer fallo (`set -e`), así que el conteo por suite se obtuvo con un runner auxiliar que monta el mismo entorno (harness + migraciones + seed) y ejecuta cada suite por separado. Fallaban `catalog_performance_probe_test.sql` y `pricing_rules_test.sql`.
- Migraciones locales aplicadas: 001–055.
- D1 y D2 seguían presentes en el código (`037` línea 71; `051` línea 138; `054` línea 312).

**Problemas confirmados**

| ID | Confirmación |
| --- | --- |
| D1 | Causa verificada en código: XOR con el operador `?`, que solo mira si la clave existe. La nueva suite SQL falla sin la migración 056 (`ERROR: VALIDATION_ERROR` con `{"product_id": "<uuid>", "addon_id": null}`). |
| D2 | Causa verificada: `encode(…, 'base64')` en `confirm_reservation` y `rotate_reservation_voucher`. La nueva suite falla sin 057: el token generado contenía `/`, `+` y `=`. |
| SQL | Problema del fixture, no de la lógica de precios: `valid_from` toma `now()` por defecto y `resolve_price` filtra `valid_from <= fecha`. Desde el 2026-10-15, las fechas consultadas son anteriores a la tarifa. Las suites originales (HEAD) fallan hoy con el mismo error. |

**Correcciones**: migraciones correctivas `056` (D1) y `057` (D2), el payload Angular omite la clave del identificador que no se usa, la pantalla de confirmación muestra el enlace completo del voucher (helper compartido `publicVoucherUrl`), los fixtures SQL usan una validez fija y explícita, y se agregaron 2 suites SQL y 5 casos de Vitest.

**Estado final**: unitarias 143/143; SQL 45/45 (43 anteriores + 2 nuevas); integración RPC 26/26; recorrido E2E completo en el navegador sin errores de consola. Migraciones 056 y 057 aplicadas en local con `supabase migration up --local`.

## B. Tabla de defectos

| ID | Severidad | Causa raíz | Archivos | Corrección | Evidencia | Riesgo residual |
| --- | --- | --- | --- | --- | --- | --- |
| D1 | Alta (P0) | `resolve_pre_reservation_item` validaba «exactamente uno de `product_id`/`addon_id`» con `jsonb ? 'clave'` (existencia), y el panel enviaba la clave sin usar con valor `null` | `supabase/migrations/037_pre_reservation_core.sql:71` (origen); `pre-reservation-payload.ts` (`buildCreatePayload`, que también usa el detalle para `add_pre_reservation_item`) | `056`: XOR sobre valores efectivos (`NULLIF(btrim(v_item->>'x'),'')`). Un uuid mal formado ahora devuelve `VALIDATION_ERROR` en vez de un error de conversión. Cliente: omite la clave sin usar | `pre_reservation_item_identifiers_test.sql` (19 aserciones; falla sin 056). Vitest: 3 casos. Integración y E2E: `create_pre_reservation` y `add_pre_reservation_item` → 200 | Bajo. Ver D3 (patrón latente en `alternative_of`) |
| D2 | Media-alta (P0) | Token del voucher en base64 estándar (`+ / =`); un `/` parte la ruta `/r/:token` | `051_us1_confirm_reservation.sql:138`, `054_us4_provider_orders_voucher.sql:312`, `reservation-confirm.component.ts` (solo mostraba el token) | `057`: helper interno `new_voucher_token()` en base64url sin relleno, con los mismos 32 bytes aleatorios, usado en los dos puntos. UI: enlace completo `${origin}/r/<token>` con `encodeURIComponent` | `reservation_voucher_token_test.sql` (19 aserciones; falla sin 057). Vitest: 2 casos. E2E: enlace `/r/…` abierto sin sesión y con recarga directa | Tokens anteriores a 057 que contienen `/`: siguen siendo válidos (búsqueda por hash), pero **solo** con el enlace codificado. Un enlace crudo ya compartido sigue fallando; la solución es reemitir |
| S1 | Media (calidad de pruebas) | Fixtures sin `valid_from` (default `now()`) consultados con fechas fijas ya pasadas | `catalog_performance_probe_test.sql`, `pricing_rules_test.sql` | Validez explícita `valid_from = 2026-01-01T00:00Z`, `valid_to = NULL`. La aserción posterior al override consulta `2099-10-15`, porque el override crea la versión con `clock_timestamp()` por diseño (append-only). Se añadió una aserción histórica | Las dos suites pasan; las versiones de HEAD siguen fallando | Las fechas de temporada (2026-12…2027-03) ya no dependen de la fecha de ejecución |
| D3 | Baja (latente, sin corregir) | `create_pre_reservation_core` (`037:572`) cuenta líneas principales con `NOT (v_item ? 'alternative_of') OR … = ''`. Con `"alternative_of": null` la expresión da NULL y la línea no cuenta como principal | `037_pre_reservation_core.sql:572` | No corregido (fuera de alcance; el cliente solo envía `alternative_of` cuando hay valor). Documentado | Revisión de código | Bajo mientras el cliente mantenga ese contrato |
| O1 | Baja (UI, observación) | Tras «Confirmar aceptación» en `/q/<token>`, la página sigue en «Emitida» y muestra «Esta propuesta expiró…», aunque la vigencia es futura. Al recargar muestra «Aceptada» y el texto correcto | `src/app/features/public-quotation/` | No corregido (el informe del 09-11 ya registró una variante) | E2E de hoy (COT-00005) | Confunde al cliente final; sin impacto en los datos |
| O2 | Baja (observación) | `source_request_item_id` mal formado en `resolve_pre_reservation_item` sigue lanzando un error de conversión (22P02) en vez de `VALIDATION_ERROR` | `056` (heredado de 037) | No corregido: el panel envía ids reales | Revisión | Mínimo |

Patrón `?` revisado en todas las migraciones: los usos restantes (`end_date`, `source_request_item_id`, `hold_expires_at`, `alternative_of_item_id` en 040, y las líneas 604/629 de 037) combinan `?` con `->> <> ''`, que con `null` se evalúa como falso, así que son seguros. El único riesgo es D3.

## C. Cambios realizados

| Archivo | Motivo |
| --- | --- |
| `supabase/migrations/056_fix_pre_reservation_item_identifiers.sql` (nuevo) | Redefine solo `resolve_pre_reservation_item`: XOR sobre valores efectivos y error controlado si el uuid no es válido. Conserva firma, `STABLE`, `SECURITY DEFINER`, `search_path = ''`, comentario y `REVOKE` (interna). El resto del cuerpo es idéntico a 037 (verificado con `diff`). |
| `supabase/migrations/057_fix_voucher_token_base64url.sql` (nuevo) | `new_voucher_token()` interna (32 bytes, base64url, sin `=`; misma receta que 046). Copia literal de `confirm_reservation` (051) y `rotate_reservation_voucher` (054), cambiando únicamente la línea del token. Mismos grants y comentario. 046 (cotización) no se tocó. |
| `src/app/features/sales/pre-reservations/pre-reservation-create/pre-reservation-payload.ts` | `buildCreatePayload` solo emite `product_id` **o** `addon_id`. Cubre la creación y la adición de servicio (el detalle reutiliza el builder). |
| `src/app/core/pre-reservations/services/pre-reservation.service.ts` | `PreReservationItemInput.product_id/addon_id` pasan a opcionales (`?: string`) según el contrato real; `PreReservationAddItemInput` lo hereda. |
| `src/app/core/reservations/models/reservation.model.ts` | Nuevo `publicVoucherUrl(origin, token)` con `encodeURIComponent`. |
| `src/app/features/sales/reservations/reservation-confirm/reservation-confirm.component.ts` | La confirmación muestra el enlace completo (`<pre><a …>`) en lugar del token suelto. Mismo layout, sin rediseño. |
| `src/app/features/sales/reservations/reservation-detail/reservation-detail.component.ts` | `publicLink` usa el helper compartido (mismo comportamiento que antes). |
| `…/pre-reservation-payload.spec.ts`, `…/reservation.model.spec.ts` | 5 casos de Vitest nuevos (3 del builder, 2 del enlace). |
| `supabase/tests/pre_reservation_item_identifiers_test.sql` (nuevo) | Regresión D1 (matriz completa más RPC públicas con el payload del panel). |
| `supabase/tests/reservation_voucher_token_test.sql` (nuevo) | Regresión D2 (formato ×500, hash, anon, redacción, inválidos, reemisión, revocación, compatibilidad con tokens anteriores, 046 intacta). |
| `supabase/tests/catalog_performance_probe_test.sql`, `supabase/tests/pricing_rules_test.sql` | Fixtures con validez explícita y determinista. Sin cambios en la lógica de precios. |
| `docs/modules/pre-reservations.md`, `docs/modules/reservations.md` | Gate 13: referencias a 056/057, formato del token y nuevas suites. |

Prettier: `--write` en los 7 TS tocados (`--check` limpio). `reservation.model.ts`, `reservation-confirm.component.ts` y `reservation-detail.component.ts` ya estaban sin formatear en HEAD, así que el diff incluye reformateo de líneas ajenas (≈ 12, 24 y 52 líneas).

## D. Resultados de pruebas

| Suite | Antes | Después | Estado |
| --- | --- | --- | --- |
| Unitarias (`npm test -- --watch=false`) | 138/138 (18 archivos) | 143/143 (18 archivos) | ✅ sin regresiones (+5) |
| SQL, conteo por suite | 41/43 | 45/45 (43 anteriores + 2 nuevas) | ✅ |
| SQL, arnés oficial completo | Abortaba en `catalog_performance_probe_test.sql` (8.ª suite) | `==> all suites passed`, 45 suites, exit 0 | ✅ |
| Regresión antes/después del fix | — | Sin 056/057: las 2 nuevas suites FALLAN. Con ellas: PASAN (19 + 19 aserciones) | ✅ |
| Integración RPC (Supabase local, HTTP) | D1 400 / D2 token no apto para URL | 26/26 comprobaciones | ✅ |
| E2E navegador | 2 defectos (pasos 4, 5 y 11) | Recorrido completo OK | ✅ |
| Prettier (TS tocados) | 3 archivos ya sin formatear | `--check` limpio | ✅ |

**Integración (script HTTP contra `127.0.0.1:54321`)**: login seed → alta de complemento por la misma vía que el panel (el seed no tiene ninguno) → `create_assisted_request` (SOL-00005) → `set_request_status in_review` → `create_pre_reservation` (PRE-00004, 200) → `add_pre_reservation_item` con `product_id: null` (200) → ambos identificadores y uuid inválido → 400 `VALIDATION_ERROR` → `record_item_verification` ×2 → borrador → términos → `issue_quotation` (COT-00004, token base64url) → `accept_public_quotation` (anon) → `confirm_reservation` (RSV-00004, token de 43 caracteres `[A-Za-z0-9_-]`) → `get_public_voucher` con anon key: disponible, solo claves documentadas, sin datos de proveedor ni documentos → tokens inválido, inexistente y en blanco → `{available:false}` → `rotate_reservation_voucher` (token nuevo base64url; el anterior queda revocado; el nuevo resuelve). Los tokens se registraron enmascarados.

**E2E (navegador integrado, datos nuevos)**: login → «Nueva solicitud» SOL-00006 (Azimut 70) → «Pasar a En gestión» → «Crear pre-reserva» desde la solicitud: PRE-00005 (`create_pre_reservation` 200) → «Agregar servicio» Complemento «Traslado QA estabilización» (`add_pre_reservation_item` 200) → «Registrar resultado» Disponible en las 2 líneas → «Totalmente verificada / Lista para cotizar» → borrador COT-00005 (4 550 000 COP), nota interna, condiciones → «Emitir cotización» → `/q/<token>` → «Aceptar propuesta» / «Confirmar aceptación» → `/sales/reservations/new` → RSV-00005; la pantalla muestra `http://localhost:4201/r/<token>` (43 caracteres base64url; texto = href) → «Cerrar sesión» (sin claves `sb-*` en localStorage) → carga directa del enlace: «Voucher RSV-00005», pasajeros, itinerario, asistencia y políticas → recarga: idéntico, sin errores de consola y sin filtrar nombre ni contacto del proveedor, nota interna, documentos, referencia de transferencia ni importes.

Compatibilidad de tokens anteriores (E2E, sobre el registro de prueba RSV-00004): se fijó su hash al de un token con formato antiguo `E2E+legacy/tok=`. `/r/E2E%2Blegacy%2Ftok%3D` → «Voucher RSV-00004» ✅. `/r/E2E+legacy/tok=` sin codificar → redirige a login/dashboard ❌ (comportamiento esperado y documentado como riesgo residual).

## E. Riesgos pendientes

1. **Enlaces crudos antiguos**: los vouchers emitidos antes de 057 cuyo token contiene `/` funcionan solo con el enlace codificado (el detalle siempre lo generó así). Si alguien compartió el token crudo armando la URL a mano, hay que reemitir (admin, «Reemitir voucher»). No se invalidó ningún token.
2. **D3** (latente) y **O1/O2**: documentados, sin corregir por alcance.
3. **No verificado en navegador**: la reemisión y la anulación desde la UI del detalle (solo se probaron por RPC y SQL); la visualización del enlace tras reemitir usa el mismo helper (cubierto por Vitest). Reproducción manual: detalle de la reserva como admin → «Reemitir voucher» → abrir el enlace en una ventana privada.
4. Para cambiar los valores de los selects (medio de contacto) en el E2E se dispararon eventos `input`/`change` por JS, porque el panel del navegador no abre los desplegables nativos. Los demás campos se escribieron con eventos de teclado reales.
5. `pricing_rules_test.sql` ya no crea la tarifa base y la de temporada con `upsert_pricing_scheme`: no es posible fijar `valid_from` por RPC. La RPC sigue cubierta en la misma suite (temporada adyacente, `SEASON_OVERLAP`, `INVALID_SEASON_RANGE`, RBAC) y en otras suites.
6. Las pruebas validan **solo el entorno local**; no se tocó ni se validó ningún entorno remoto o de producción. Para desplegar, hay que aplicar 056 y 057 en orden.

## F. Veredicto Quality Gate 12 — Testing (entorno local)

**APROBADO CON OBSERVACIONES**

- *Pruebas proporcionales al riesgo*: los dos defectos P0 tienen regresión SQL que falla antes y pasa después, Vitest del cliente, integración RPC y E2E.
- *Verificación automatizada de lo crítico*: la creación y adición de líneas de pre-reserva y el token público quedan cubiertos por suites del arnés (incluida la redacción del voucher y la revocación).
- *Las pruebas existentes siguen pasando*: 138 → 143 unitarias, 41/43 → 45/45 SQL.
- *Sin regresiones*: suites completas en verde; las firmas, grants y contratos RPC se conservan.
- Observaciones: riesgo residual de tokens antiguos crudos (E.1), D3/O1/O2 abiertos, reemisión desde la UI no probada en navegador (E.3).

## Datos de prueba creados en la base local

- Complemento «Traslado QA estabilización» (+ tarifa base 50 000 COP, `per_group`).
- Integración: cliente «Integracion QA <hhmmss>», SOL-00005, PRE-00004, COT-00004 (aceptada), RSV-00004 (voucher reemitido; después, su hash se fijó manualmente al token de prueba `E2E+legacy/tok=` para la prueba de compatibilidad).
- E2E: clienta «Marta E2E Estabilizacion», SOL-00006, PRE-00005 (verificada), COT-00005 (aceptada, con nota interna), RSV-00005 (confirmada, depósito 1 000 000 COP, 2 pasajeros).
- Migraciones 056 y 057 registradas en `supabase_migrations` local.
