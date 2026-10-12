# Feature Specification: 006-reservation-lifecycle

**Feature Branch**: `006-reservation-lifecycle`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Confirmación de reservas y gestión completa del ciclo de vida operativo derivado de mainspec.md (Capítulos 13, 14, 20, 29)."

## Clarifications

### Session 2026-10-09

- Q: ¿El código de la reserva debe ser una secuencia numérica o un código que no se pueda adivinar? → A: Código opaco `RSV-` más 6 caracteres, único por agencia y generado en el servidor. No es una secuencia correlativa.
- Q: ¿Qué pago hace falta para confirmar la reserva si no hay pasarela ni factura electrónica? → A: Un comprobante manual por al menos el anticipo (30 % del total congelado por defecto, configurable por agencia entre 0 % y 100 %). Un administrador puede eximir el anticipo con motivo. Si el archivo no se puede guardar, la confirmación sigue con la referencia y un aviso. Sin pasarela y sin factura electrónica.
- Q: ¿Un cambio de fechas crea otra reserva o actualiza la misma? → A: Actualiza la misma reserva y conserva el localizador. «Reprogramada» es un estado, no una reserva nueva. «Completada» y «Cancelada» son terminales. Cancelar un viaje ya iniciado exige un administrador y un informe de contingencia.
- Q: ¿Cómo recibe el proveedor la orden si no hay WhatsApp ni correo automático? → A: El operador arma una ficha por proveedor, sin precios de venta ni datos de otros prestadores, la copia o la imprime y marca «Transmitida». No hay envío automático.
- Q: ¿Cuántas reservas salen de una cotización aceptada y qué datos quedan congelados? → A: Como máximo una reserva no cancelada por cotización aceptada. Se copian las líneas, el total, la moneda y la cantidad de viajeros ya congelados. Hay que registrar exactamente esa cantidad de pasajeros. Confirmar no cambia el estado de la pre-reserva ni recalcula el precio.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Confirmación Formal de Reserva (Priority: P1)

Como agente comercial, operador o administrador, quiero convertir una cotización aceptada por el cliente en una "Reserva Confirmada" tras registrar el anticipo (o una exención de administrador), para formalizar el compromiso comercial sin abrir una pasarela de pago.

**Why this priority**: La reserva confirmada es la culminación del proceso de ventas y el inicio de la ejecución del servicio turístico.

**Independent Test**: Puede probarse eligiendo una cotización "Aceptada", cargando tantos pasajeros como viajeros congeló la cotización, registrando un abono manual de al menos el anticipo y obteniendo un localizador `RSV-` que no sigue una secuencia.

**Acceptance Scenarios**:

1. **Given** una cotización en estado "Aceptada", **When** el agente registra pasajeros por la cantidad congelada y un abono manual mayor o igual al anticipo (30 % por defecto), **Then** el sistema crea una sola Reserva Confirmada con localizador opaco `RSV-` más 6 caracteres, copia los servicios y el total sin recalcular, y no cambia el estado de la pre-reserva.
2. **Given** una cotización en estado "Expirada", "Rechazada" o todavía no aceptada, **When** se intenta confirmar, **Then** el sistema bloquea la acción y no crea reserva.
3. **Given** una reserva confirmada, **When** el agente abre el voucher, **Then** ve el itinerario, las políticas de la cotización y el teléfono de asistencia si la agencia lo configuró, listo para imprimir, sin precios internos de proveedores.
4. **Given** una cotización aceptada que ya tiene una reserva no cancelada, **When** se intenta confirmar otra vez, **Then** el sistema rechaza el duplicado. Si esa reserva fue cancelada, se puede confirmar una nueva con otro localizador.

---

### User Story 2 - Gestión del Ciclo de Vida de la Reserva (Priority: P1)

Como operador o administrador, quiero actualizar el estado de la misma reserva a medida que avanza el viaje (Confirmada → En ejecución → Completada) para saber en qué etapa está, sin crear otra reserva ni otro localizador.

**Why this priority**: Permite el seguimiento operativo en tiempo real de los viajeros y evita desatenciones en destino.

**Independent Test**: Puede probarse pasando una reserva de Confirmada a En ejecución y luego a Completada, comprobando que un agente no puede hacer esas transiciones, que Completada no vuelve atrás y que cada paso queda en el historial con fecha y usuario.

**Acceptance Scenarios**:

1. **Given** una reserva "Confirmada", **When** el operador la pasa a "En ejecución", **Then** el estado cambia en la misma reserva y un agente recibe un rechazo por permisos.
2. **Given** una reserva "En ejecución", **When** el operador la marca "Completada", **Then** queda terminal: no admite cancelación, reprogramación ni vuelta a un estado anterior.
3. **Given** una reserva "Completada" o "Cancelada", **When** alguien intenta otra transición, **Then** el sistema la rechaza.

---

### User Story 3 - Cancelaciones y Modificaciones con Trazabilidad (Priority: P2)

Como agente o administrador, quiero cancelar o cambiar fechas y pasajeros de la misma reserva, registrando el motivo y el porcentaje de reembolso informado, sin mover dinero en una pasarela y sin emitir otra reserva.

**Why this priority**: Las cancelaciones y modificaciones son habituales en el turismo por factores climáticos, personales o logísticos.

**Independent Test**: Puede probarse cancelando una reserva confirmada con motivo y porcentaje de reembolso, comprobando que el localizador se conserva, que los servicios quedan cancelados y que el historial no se puede editar.

**Acceptance Scenarios**:

1. **Given** una reserva "Confirmada", **When** el agente cancela con motivo y un porcentaje de reembolso entre 0 y 100, **Then** la reserva pasa a "Cancelada", el reembolso queda calculado sobre el total congelado y no se ejecuta un pago saliente.
2. **Given** una reserva "Confirmada", **When** el operador cambia las fechas porque el proveedor aceptó, **Then** la misma reserva pasa a "Reprogramada" con el mismo localizador. Al registrar que el proveedor confirmó el nuevo fecha, el operador la devuelve a "Confirmada".
3. **Given** una reserva "En ejecución", **When** alguien que no es administrador intenta cancelarla, **Then** el sistema lo rechaza. Un administrador solo puede cancelarla con un informe de contingencia.

---

### User Story 4 - Asignación de Responsables y Notificación a Proveedores (Priority: P2)

Como operador o administrador, quiero preparar la orden de servicio de cada proveedor para copiarla o imprimirla y dejar constancia de que ya la transmití por fuera del sistema.

**Why this priority**: Asegura que el prestador local reciba los nombres de los pasajeros, requerimientos alimenticios y horarios antes de la llegada del cliente.

**Independent Test**: Puede probarse generando la ficha de un proveedor, comprobando que no muestra precios de venta ni pasajeros de otro prestador, y marcándola como transmitida sin que salga un mensaje automático.

**Acceptance Scenarios**:

1. **Given** una reserva confirmada con 2 proveedores distintos, **When** el operador abre la orden de cada uno, **Then** ve solo los servicios, fechas, pasajeros y requisitos de ese proveedor, sin precios de venta ni datos del otro prestador, y puede marcarla «Transmitida».
2. **Given** que no hay integración de correo ni de WhatsApp, **When** el operador marca la orden transmitida, **Then** el sistema solo registra quién y cuándo la marcó. No envía ningún mensaje.

---

### Edge Cases

- ¿Qué ocurre si un proveedor cancela un servicio después de confirmada la reserva? El operador marca ese servicio como «Proveedor incumplido» sin cancelar la reserva. Puede agregar un servicio de reemplazo; el precio de venta congelado no cambia solo por el reemplazo. Un cambio de precio exige un administrador y queda en el historial.
- ¿Qué ocurre si se cancela una reserva que ya está «En ejecución»? Solo un administrador, con un informe de contingencia de entre 1 y 2000 caracteres. Una reserva «Completada» no se cancela.
- ¿Cómo se garantiza que no haya localizadores duplicados? El servidor genera `RSV-` más 6 caracteres de un alfabeto sin letras ambiguas y reintenta si choca con el único de la agencia. No es una secuencia 00001, 00002.
- ¿Qué ocurre si el abono es menor que el anticipo? La confirmación se rechaza. Un administrador puede eximir el anticipo con un motivo. La auditoría registra que hubo exención, no el texto del motivo.
- ¿Qué ocurre si el archivo del comprobante no se puede almacenar? La confirmación no se bloquea: queda la referencia del pago y la pantalla avisa que el archivo no se guardó.
- ¿Qué ocurre si faltan pasajeros o sobran? No se confirma hasta que la cantidad de pasajeros sea exactamente la de adultos más niños congelada en la cotización. El número de habitaciones no sustituye a esa cuenta.
- ¿Qué ocurre con el documento de identidad en la auditoría? El documento vive solo en la ficha del pasajero. El registro de auditoría no incluye el número de documento, el nombre ni el texto del informe de contingencia.
- ¿Qué ocurre con la pre-reserva y la cotización al confirmar? La cotización sigue «Aceptada». La pre-reserva conserva el estado que le corresponde a la feature 004.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE confirmar una Reserva solo a partir de una Cotización «Aceptada», llamando a la regla de la feature 005, copiando líneas, total, moneda y cantidad de viajeros sin recalcular. Como máximo DEBE existir una reserva no cancelada por esa cotización. Confirmar NO DEBE cambiar el estado de la pre-reserva ni crear otra cotización.
- **FR-002**: Toda Reserva DEBE recibir un localizador único por agencia, opaco, con forma `RSV-` y 6 caracteres, generado en el servidor. El localizador no cambia si la reserva se reprograma o se cancela.
- **FR-003**: El sistema DEBE gestionar los estados Confirmada, En ejecución, Completada, Cancelada y Reprogramada sobre la misma reserva. Completada y Cancelada son terminales. Solo operador o administrador pueden pasar a En ejecución o Completada. Reprogramada vuelve a Confirmada cuando el operador registra que el proveedor aceptó las nuevas fechas. Un agente puede cancelar una Confirmada o una Reprogramada. Solo un administrador puede cancelar una En ejecución, y solo con informe de contingencia.
- **FR-004**: El sistema DEBE exigir, antes de confirmar, tantos pasajeros como adultos más niños congeló la cotización. Cada pasajero tiene nombre y apellido. Documento, fecha de nacimiento y requisitos especiales son opcionales. Esos datos no salen en la orden de otro proveedor ni en el registro de auditoría.
- **FR-005**: El sistema DEBE registrar el anticipo de forma manual (método, monto, fecha y referencia). El monto DEBE cubrir al menos el porcentaje de anticipo de la agencia (30 % por defecto, entre 0 % y 100 % del total congelado), salvo exención de administrador con motivo. El archivo del comprobante se guarda si el almacenamiento responde; si no, la confirmación continúa y la pantalla lo indica. El sistema NO DEBE cobrar por pasarela ni emitir factura electrónica.
- **FR-006**: El sistema DEBE mostrar un voucher imprimible con el localizador, el itinerario, las políticas copiadas de la cotización y el teléfono de asistencia de la agencia cuando exista. El voucher NO DEBE incluir precios de costo ni datos de pago.
- **FR-007**: El sistema DEBE dejar un historial que no se pueda editar ni borrar, con actor y fecha, para transiciones, cancelaciones, cambios de fecha, sustitución de proveedor y órdenes marcadas transmitidas. El registro de auditoría NO DEBE incluir nombres, documentos, motivos ni el informe de contingencia.
- **FR-008**: El sistema DEBE armar una orden de servicio por proveedor, sin precios de venta y sin servicios de otros proveedores, para copiar o imprimir, y permitir al operador marcarla «Transmitida». NO DEBE enviar WhatsApp ni correo.

### Key Entities

- **Reserva**: Contrato de viaje sobre una cotización aceptada. Atributos: ID, OrganizaciónID, Localizador (`RSV-` + 6), CotizaciónOrigenID, ClienteTitularID, PreReservaID, FechaConfirmación, FechaInicioViaje, FechaFinViaje, Estado (Confirmada, En ejecución, Completada, Cancelada, Reprogramada), ImporteTotal congelado, Moneda, AnticipoExigido, SaldoRegistrado, SaldoPendiente, AgenteResponsableID. El localizador no cambia.
- **Pasajero**: Persona que viaja bajo una reserva. Atributos: ID, ReservaID, Nombre, Apellido, TipoDocumento (opcional), Documento (opcional), FechaNacimiento (opcional), RequerimientosEspeciales (opcional). La cantidad de filas debe coincidir con los viajeros de la cotización.
- **Ítem de Reserva**: Servicio copiado de una línea de cotización. Atributos: ID, ReservaID, LíneaCotizaciónID, ProductoID o ComplementoID, ProveedorID, FechaInicio, FechaFin, Cantidad, EstadoOperativo (Confirmado, En servicio, Completado, Incidencia, Proveedor incumplido, Cancelado), ÍtemReemplazadoID (opcional).
- **Registro de Pago**: Abono manual. Atributos: ID, ReservaID, Monto, Moneda, FechaPago, Método (transferencia, efectivo, tarjeta presente, otro), Referencia, RutaArchivo (opcional), Exención (sí/no), RegistradoPor.
- **Orden de servicio**: Ficha por proveedor. Atributos: ID, ReservaID, ProveedorID, Texto, TransmitidaEn, TransmitidaPor. No contiene precios de venta.
- **Evento de reserva**: Hecho que no se edita ni se borra. Atributos: ID, ReservaID, Tipo, EstadoAnterior, EstadoNuevo, ActorID, Fecha. El motivo y el informe viven en la reserva, no en el registro de auditoría.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100 % de las reservas confirmadas tienen un localizador `RSV-` único en su agencia y una cotización de origen en estado Aceptada.
- **SC-002**: El voucher imprimible queda disponible en la misma confirmación, sin una segunda petición de precio.
- **SC-003**: 100 % de transiciones, cancelaciones, reprogramaciones y sustituciones de proveedor quedan en el historial append-only con actor y fecha. La auditoría de seguridad no contiene nombres, documentos ni motivos.
- **SC-004**: 0 reservas confirmadas cuya cantidad de pasajeros difiera de adultos más niños congelados en la cotización.

## Assumptions

- El registro de pagos es manual. No hay pasarela (Stripe, Wompi u otra) ni factura electrónica en esta feature. Si el almacenamiento del comprobante no responde, la referencia alcanza para confirmar y la pantalla lo dice.
- No se bloquea inventario. Cancelar un servicio no devuelve un cupo numérico: deja el ítem cancelado o marcado como proveedor incumplido.
- El anticipo por defecto es el 30 % del total congelado. La agencia puede fijar otro porcentaje entre 0 y 100.
- El teléfono de asistencia del voucher sale de la configuración de la agencia. Si no está, el voucher indica que la agencia lo informará.
- La cotización aceptada la produce la feature 005. Esta feature no la crea ni la modifica, salvo leerla para copiar el congelado.
- El WhatsApp y el correo salientes no se envían. La orden de servicio se copia o se imprime.
