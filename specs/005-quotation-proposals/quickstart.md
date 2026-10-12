# Quickstart: 005-quotation-proposals

Guía de validación. No implementa el módulo. Requiere las migraciones de 004 (`035`–`041`) aplicadas, porque el borrador llama a `assert_pre_reservation_quotable`.

## Prerequisites

- `supabase start` y migraciones al día, incluida `048_us4_quotation_responses.sql`
- Un colaborador agente y uno administrador de la misma organización
- Una pre-reserva `verified` con al menos una línea principal, tarifa vigente y, si aplica, `expires_at` futuro
- `npm start` para el panel

## Scenario 1 — Borrador calculado por el servidor (US1)

1. Entrar como agente a **Comercial → Cotizaciones → Nueva cotización** y elegir la pre-reserva verificada.
2. Confirmar que cada línea muestra tipo de cobro, cantidad, precio unitario, impuesto 0 % y total, y que el encabezado coincide con la suma anunciada por el servidor.
3. Subir el impuesto de una línea a 19. El total cambia sin recargar fórmulas en el cliente.
4. Agregar un descuento del 10 % con etiqueta «Cortesía». Se ve en el desglose.
5. Intentar un descuento que deje el impacto por encima del 15 % del subtotal de tarifas. El sistema responde que requiere un administrador. Con el usuario administrador, el mismo ajuste se guarda.

**Esperado**: códigos `ADJUSTMENT_REQUIRES_ADMIN` para el agente y desglose nuevo para el administrador. Ningún total se calcula en TypeScript.

## Scenario 2 — Vigencia y emisión (US2)

1. En el borrador, dejar la vigencia por defecto y pulsar **Emitir cotización**.
2. Anotar referencia `COT-#####`, vigencia a 48 horas y el enlace `/q/…` mostrado una sola vez.
3. Intentar cambiar el precio de la línea. Debe rechazarse (`QUOTATION_FROZEN`).
4. Repetir con una vigencia posterior a `expires_at` de la pre-reserva. Debe rechazarse indicando el tope.
5. Avanzar el reloj de la base (o fijar `valid_until` en el pasado dentro de un test SQL) y volver a abrir el listado. La cotización figura **Expirada**.

**Esperado**: términos no vacíos, `valid_until` dentro de los topes, importes idénticos después de cambiar una tarifa del catálogo.

## Scenario 3 — Enlace público y WhatsApp (US3)

1. Abrir `/q/<token>` en una ventana sin sesión, ancho de móvil.
2. Ver itinerario, inclusiones, exclusiones, desglose, condiciones y **Aceptar propuesta**. No debe verse correo, teléfono ni notas internas.
3. Pulsar **Copiar para WhatsApp** en el panel y comprobar que el texto lleva la referencia, el total y el enlace.
4. **Imprimir** abre el diálogo del navegador.
5. Anular como administrador. Volver a abrir el enlace: «Esta propuesta ya no está disponible.» sin importes.

## Scenario 4 — Respuesta y versión (US4)

1. Emitir otra cotización. En el enlace, **Aceptar propuesta** y luego **Confirmar aceptación**.
2. El panel muestra **Aceptada**, origen Cliente, y el texto de que la reserva se confirma en el módulo de reservas. No aparece un alta de reserva.
3. En otra cotización emitida, registrar **Requiere modificaciones** y **Crear nueva versión**. La v1 queda **Superada por nueva versión** y el mismo token muestra la v2 cuando se emita.
4. Cambiar una línea principal de la pre-reserva después de emitir y intentar aceptar. La cotización pasa a **Expirada** (`QUOTATION_STALE`).
5. Intentar versionar una cotización **Aceptada**. Se rechaza.

## SQL

Las suites cubren lo mismo sin UI:

- `quotation_pricing_test.sql` — tipos de cobro, redondeo, tope, moneda
- `quotation_rls_test.sql` — aislamiento, `anon` sin `SELECT`, grants
- `quotation_issue_test.sql` — vigencia, congelado, barrido
- `quotation_public_test.sql` — token, anulación, confirmación
- `quotation_version_test.sql` — versión, huella, `assert_quotation_confirmable`

Comandos de verificación (no forman parte de esta guía de diseño; los ejecuta quien implemente):

- `npm test -- --watch=false`
- `npm run lint`
- `npm run build`
- `./supabase/tests/run-sql-tests.sh`
