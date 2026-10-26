# Quickstart: 006-reservation-lifecycle

Prueba manual cuando existan migraciones `049`+, seed y `npm start`. SQL: `./supabase/tests/run-sql-tests.sh`. Vitest: `npm test`.

## Prerequisites

- Features 001–005 aplicadas (última migración de 005: `048_us4_quotation_responses.sql`).
- Una cotización **aceptada** en el tenant demo (flujo 005: pre-reserva cotizable → emitir → aceptar).
- `supabase start` y panel en el puerto del proyecto.

## Scenarios

### 1. Confirmar desde cotización aceptada (US1)

1. Abrir una cotización `accepted`.
2. «Confirmar reserva».
3. Cargar pasajeros en número igual a adultos+niños, depósito > 0, método y referencia.
4. Enviar.

**Esperado**: `RSV-#####`, voucher token una vez, ítems copiados, estado `confirmed`. En SQL, `quotation_version_id` único. Rechazar una cotización `issued`/`expired` muestra «Solo se confirma una cotización aceptada.»

### 2. Ciclo de vida (US2)

1. Operador: Confirmada → En ejecución → Completada.
2. Intentar Completada → Confirmada.

**Esperado**: las dos primeras transiciones auditadas; la tercera `INVALID_TRANSITION`.

### 3. Cancelar (US3)

1. Agente cancela una `confirmed` con motivo.
2. Intentar cancelar `in_progress` como agente.
3. Admin cancela `in_progress` con informe.

**Esperado**: (1) `cancelled`; (2) «Hace falta un administrador…»; (3) ok.

### 4. Nueva versión de fechas (US3)

1. En `confirmed`, cambiar fechas/pax vía «Nueva versión».
2. Listar historial.

**Esperado**: v2 actual, v1 `superseded`, pagos de familia intactos, auditoría `reservation_version_created`.

### 5. Órdenes a proveedor (US4)

1. Reserva con ≥ 2 proveedores.
2. Copiar orden del ítem A; marcar enviada.
3. Verificar que el texto de A no incluye el prestador B ni importes de venta.

### 6. Voucher público

1. Abrir `/r/<token>` justo después de confirmar.
2. Void admin y recargar.

**Esperado**: (1) localizador e itinerario sin documentos ni totales internos; (2) «Este voucher ya no está disponible.»

### 7. Comprobante de pago

1. Subir archivo al bucket en el prefijo de org.
2. Registrar abono extra.
3. Comprobar `balance` pintado por el servidor, no calculado en el cliente.

## Automated evidence (when implemented)

| Scenario | Suite prevista |
|----------|----------------|
| 1 | `reservation_confirm_test.sql` |
| 2 | `reservation_lifecycle_test.sql` |
| 3–4 | `reservation_changes_test.sql` |
| 5 | `service_orders_test.sql` |
| 6 | `reservation_public_voucher_test.sql` |
| RLS / anon | `reservation_rls_test.sql` |
