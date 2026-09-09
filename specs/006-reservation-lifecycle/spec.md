# Feature Specification: 006-reservation-lifecycle

**Feature Branch**: `006-reservation-lifecycle`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Confirmación de reservas y gestión completa del ciclo de vida operativo derivado de mainspec.md (Capítulos 13, 14, 20, 29)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Confirmación Formal de Reserva (Priority: P1)

Como agente comercial o administrador, quiero convertir una cotización aceptada por el cliente en una "Reserva Confirmada" tras comprobar el pago del anticipo o depósito requerido, para formalizar el compromiso comercial y asegurar el viaje.

**Why this priority**: La reserva confirmada es la culminación del proceso de ventas y el inicio de la ejecución del servicio turístico.

**Independent Test**: Puede probarse seleccionando una cotización en estado "Aceptada", registrando la información del pago/abono recibido y generando la Reserva Confirmada con su código localizador único.

**Acceptance Scenarios**:

1. **Given** una cotización en estado "Aceptada" vigente, **When** el agente registra la confirmación comercial y el comprobante del depósito, **Then** el sistema crea la Reserva Confirmada con un localizador alfanumérico único (ej. RSV-7890) y asocia todos los servicios comprometidos.
2. **Given** una cotización en estado "Expirada" o "Rechazada", **When** se intenta forzar la confirmación, **Then** el sistema bloquea la acción exigiendo actualización de la cotización.
3. **Given** una reserva confirmada, **When** se genera el registro, **Then** se emite un voucher/comprobante de reserva con el resumen completo del itinerario para el cliente.

---

### User Story 2 - Gestión del Ciclo de Vida de la Reserva (Priority: P1)

Como operador o coordinador de viajes, quiero actualizar el estado de la reserva a medida que avanza el viaje (Confirmada → En Ejecución → Completada) para mantener la trazabilidad de la operación y saber en qué etapa se encuentra cada pasajero.

**Why this priority**: Permite el seguimiento operativo en tiempo real de los viajeros y evita desatenciones en destino.

**Independent Test**: Puede probarse transitando una reserva desde Confirmada hasta Completada, verificando que cada transición de estado es válida según las reglas de negocio y registra fecha/hora y usuario.

**Acceptance Scenarios**:

1. **Given** una reserva en estado "Confirmada", **When** llega la fecha de inicio del servicio y el cliente inicia el viaje, **Then** el operador transiciona el estado a "En Ejecución / En Curso".
2. **Given** una reserva "En Ejecución", **When** concluyen satisfactoriamente todos los servicios del itinerario, **Then** se actualiza el estado a "Completada".
3. **Given** cualquier intento de transicionar una reserva completada a un estado anterior no válido, **When** se evalúa la regla, **Then** el sistema rechaza la transición protegiendo la integridad del ciclo de vida.

---

### User Story 3 - Cancelaciones y Modificaciones con Trazabilidad (Priority: P2)

Como administrador o agente, quiero registrar cancelaciones de reservas o modificaciones de fechas/pasajeros, aplicando las penalidades o políticas correspondientes y dejando constancia inmutable del motivo, para gestionar imprevistos con claridad financiera.

**Why this priority**: Las cancelaciones y modificaciones son habituales en el turismo por factores climáticos, personales o logísticos.

**Independent Test**: Puede probarse cancelando una reserva confirmada con un motivo explícito, comprobando que cambia a estado "Cancelada", se liberan los compromisos operativos y queda registrado en la bitácora de auditoría.

**Acceptance Scenarios**:

1. **Given** una reserva activa (Confirmada), **When** el cliente solicita la cancelación justificada, **Then** el agente procesa la cancelación indicando motivo, porcentaje de reembolso aplicable y fecha de solicitud.
2. **Given** una solicitud de modificación de fechas para una reserva confirmada, **When** el operador verifica que los proveedores aceptan el cambio, **Then** el sistema registra la modificación generando una nueva versión de la reserva con su historial de cambios auditado.

---

### User Story 4 - Asignación de Responsables y Notificación a Proveedores (Priority: P2)

Como operador, quiero emitir las órdenes de servicio o notificaciones de confirmación definitiva a los proveedores de cada experiencia y alojamiento para que tengan listo el cupo y los servicios en destino.

**Why this priority**: Asegura que el prestador local reciba los nombres de los pasajeros, requerimientos alimenticios y horarios antes de la llegada del cliente.

**Independent Test**: Puede probarse generando la lista de pasajeros y detalles de servicio por proveedor dentro de la reserva confirmada y marcando la confirmación transmitida al proveedor.

**Acceptance Scenarios**:

1. **Given** una reserva confirmada con 2 proveedores distintos, **When** el operador emite las órdenes de servicio, **Then** cada proveedor recibe su ficha individual sin exponer datos de otros prestadores ni precios de venta finales al público.

---

### Edge Cases

- ¿Qué ocurre si un proveedor cancela intempestivamente un servicio después de confirmada la reserva? El sistema debe permitir marcar el ítem individual en contingencia ("Proveedor Incumplido"), alertar al equipo de operaciones y permitir reasignar un proveedor alternativo sin cancelar la reserva completa.
- ¿Qué ocurre si se cancela una reserva que ya está "En Ejecución"? Requiere autorización especial de nivel Administrador y registro obligatorio de informe de contingencia.
- ¿Cómo se garantiza que no haya localizadores duplicados? El código de reserva debe ser un identificador único garantizado por secuencia segura en el sistema.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE permitir confirmar una Reserva a partir de una Cotización en estado "Aceptada".
- **FR-002**: Toda Reserva confirmada DEBE tener asignado un código localizador único alfanumérico no predecible (ej. RSV-XXXX).
- **FR-003**: El sistema DEBE gestionar los estados del ciclo de vida de la reserva: Confirmada, En Ejecución, Completada, Cancelada, Reprogramada.
- **FR-004**: El sistema DEBE asociar a la reserva el detalle de todos los pasajeros (nombres, documentos, edades, restricciones médicas/alimentarias).
- **FR-005**: El sistema DEBE registrar la información de pago del anticipo/saldo (método de pago, monto, fecha, referencia de transacción y archivo de comprobante).
- **FR-006**: El sistema DEBE generar el Voucher de Reserva para el cliente con itinerario detallado, teléfonos de asistencia y políticas de viaje.
- **FR-007**: El sistema DEBE registrar en la bitácora de auditoría inmutable toda transición de estado, cancelación, cambio de fecha o sustitución de proveedor.
- **FR-008**: El sistema DEBE permitir registrar los datos de confirmación final con cada prestador/proveedor asignado.

### Key Entities

- **Reserva**: Contrato de viaje confirmado. Atributos: ID, OrganizaciónID, LocalizadorÚnico, CotizaciónOrigenID, ClienteTitularID, FechaConfirmación, FechaInicioViaje, FechaFinViaje, Estado (Confirmada, EnEjecución, Completada, Cancelada, Modificada), ImporteTotal, SaldoPagado, SaldoPendiente, AgenteResponsableID.
- **Pasajero**: Persona que viaja bajo una reserva. Atributos: ID, ReservaID, Nombre, Apellido, TipoDocumento, Documento, FechaNacimiento, RequerimientosEspeciales.
- **Ítem de Reserva**: Servicio contratado en firme. Atributos: ID, ReservaID, ProductoID, ProveedorID, FechaInicio, FechaFin, EstadoOperativo (ConfirmadoProveedor, EnServicio, Completado, Incidencia).
- **Registro de Pago**: Comprobante del abono financiero. Atributos: ID, ReservaID, Monto, Moneda, FechaPago, MétodoPago, ReferenciaTransacción, VerificadoPorUsuarioID.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% de las reservas confirmadas cuentan con código localizador único y vinculación a su cotización de origen.
- **SC-002**: Generación del voucher de reserva para el cliente en menos de 3 segundos tras la confirmación.
- **SC-003**: Trazabilidad completa (100%) de quién, cuándo y por qué se modificó o canceló una reserva mediante auditoría.
- **SC-004**: 0 discrepancias entre el número de pasajeros registrados en la reserva y los asientos/habitaciones confirmados con proveedores.

## Assumptions

- En este MVP, el registro de pagos es conciliado manualmente por el operador o agente mediante comprobante bancario (la integración con pasarelas automáticas tipo Stripe o Wompi queda como evolución planificada).
- Las contingencias operativas se gestionan mediante reasignación manual asistida por el software.
