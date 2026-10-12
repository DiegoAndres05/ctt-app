# Quickstart: 006-reservation-lifecycle

Requiere 005 aplicado hasta `048`, porque confirmar llama a `assert_quotation_confirmable`.

## Prerequisites

- Migraciones hasta `055_us4_service_orders.sql`
- Una cotización `accepted` con `party_adults + party_children` conocido y total congelado
- Usuarios agente, operador y administrador
- `npm start`

## Scenario 1 — Confirmar (US1)

1. Como agente, en la cotización aceptada pulsar **Confirmar reserva**.
2. Cargar exactamente los pasajeros pedidos. Intentar confirmar con uno menos: «Faltan pasajeros…».
3. Registrar un abono menor al 30 %. Debe rechazarse.
4. Completar el abono (transferencia, fecha, referencia). Confirmar. Anotar el localizador `RSV-` de 6 caracteres.
5. Comprobar que la cotización sigue Aceptada y que la pre-reserva no cambió de estado.
6. Repetir la confirmación: «Esta cotización ya tiene una reserva activa.»
7. Quitar el archivo a mitad de la subida (o bloquear el bucket) y confirmar solo con referencia. Debe aparecer «No se pudo guardar el archivo. La referencia queda registrada.» y la reserva existe.

## Scenario 2 — Ciclo (US2)

1. Como agente, **Pasar a en ejecución**. Debe rechazarse.
2. Como operador, pasar a **En ejecución** y luego **Marcar completada**.
3. Intentar cancelar la completada. Debe rechazarse: «Esta reserva está cerrada.»

## Scenario 3 — Cancelar y reprogramar (US3)

1. En otra reserva confirmada, cancelar con motivo y 50 % de reembolso. El localizador se conserva y el estado es **Cancelada**.
2. Confirmar de nuevo esa misma cotización. Debe permitir un localizador distinto.
3. En una reserva en ejecución, cancelar como operador: rechazo. Como administrador, sin informe: rechazo. Con informe: **Cancelada**.
4. Reprogramar fechas como operador. Estado **Reprogramada**, mismo localizador. **El proveedor aceptó las nuevas fechas** vuelve a **Confirmada**.
5. Marcar un servicio **Proveedor incumplido** y agregar reemplazo. El total no cambia. Como administrador, ajustar el total con motivo y ver el historial.

## Scenario 4 — Orden y voucher (US4)

1. Con dos proveedores, abrir cada **Orden de servicio**. No debe verse el precio ni el otro proveedor.
2. **Copiar orden** e **Imprimir**. No sale ningún mensaje automático.
3. **Marcar como transmitida**.
4. **Voucher de reserva** muestra localizador, itinerario, políticas y, si no hay teléfono, «La agencia indicará el teléfono de asistencia.» No muestra el abono.

## SQL

- `reservation_confirm_test.sql`
- `reservation_rls_test.sql`
- `reservation_lifecycle_test.sql`
- `reservation_changes_test.sql`
- `service_orders_test.sql`

Quien implemente ejecuta, sin que este diseño los marque hechos:

- `npm test -- --watch=false`
- `npm run lint`
- `npm run build`
- `./supabase/tests/run-sql-tests.sh`
