# Feature Specification: 004-prereservation-availability

**Feature Branch**: `004-prereservation-availability`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Pre-reservas y proceso operativo de verificación de disponibilidad humana derivado de mainspec.md (Capítulos 10, 11, 28)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Conversión de Solicitud a Pre-Reserva (Priority: P1)

Como agente comercial u operador, quiero convertir una solicitud de cliente en una Pre-Reserva con ítems concretos (experiencias, alojamientos, fechas y pasajeros específicos), para iniciar formalmente la verificación técnica y de cupos con los prestadores de servicio.

**Why this priority**: La Pre-Reserva es la entidad intermedia esencial que formaliza los servicios solicitados antes de generar una cotización de precio vinculante o una confirmación.

**Independent Test**: Puede probarse seleccionando una solicitud en estado "Recibida" y creando a partir de ella una Pre-Reserva con líneas de producto específicas, verificando que la Pre-Reserva nace en estado "Pendiente de Verificación".

**Acceptance Scenarios**:

1. **Given** una solicitud de cliente activa, **When** el agente hace clic en "Crear Pre-Reserva" y define los ítems de catálogo, fechas exactas y número de personas, **Then** el sistema genera la Pre-Reserva vinculada a la solicitud con estado "Pendiente de Verificación".
2. **Given** una Pre-Reserva creada, **When** se consulta su estado, **Then** el sistema muestra con claridad que no constituye una reserva confirmada y que requiere verificación operativa.

---

### User Story 2 - Cola Operativa de Verificación de Disponibilidad (Priority: P1)

Como operador de la agencia, quiero visualizar una lista/cola de tareas de verificación ordenadas por prioridad y fecha de viaje, para saber qué proveedores debo contactar (por llamada, WhatsApp o correo) y verificar si tienen cupos disponibles.

**Why this priority**: El negocio turístico de la agencia depende de proveedores externos (guías, dueños de fincas, lancheros) que no cuentan con APIs automatizadas y requieren validación humana (Human-in-the-loop).

**Independent Test**: Puede probarse accediendo a la cola de verificación con el rol Operador, viendo cada ítem pendiente agrupado por proveedor y marcando el avance de la gestión.

**Acceptance Scenarios**:

1. **Given** un operador autenticado, **When** accede a la bandeja de verificación, **Then** ve todos los ítems de pre-reserva en estado "Pendiente de Verificación" con la información de contacto del proveedor y las fechas requeridas.
2. **Given** un ítem en la cola, **When** el operador contacta al proveedor y este confirma cupo, **Then** el operador marca el ítem como "Verificado / Disponible" registrando la fecha, hora, persona de contacto en el proveedor y notas relevantes.
3. **Given** un proveedor que informa no tener disponibilidad para la fecha solicitada, **When** el operador registra la no disponibilidad, **Then** el sistema actualiza el estado a "No Disponible" y permite sugerir fechas o alternativas.

---

### User Story 3 - Consolidación del Estado de la Pre-Reserva (Priority: P2)

Como agente comercial, quiero saber cuándo todos los ítems de una pre-reserva han sido verificados satisfactoriamente, para proceder de inmediato a elaborar la cotización formal para el cliente.

**Why this priority**: Evita emitir cotizaciones o compromisos comerciales sobre servicios que no cuentan con disponibilidad real garantizada.

**Independent Test**: Puede probarse marcando como verificados todos los ítems de una pre-reserva compuesta y comprobando que el estado global de la pre-reserva cambia automáticamente a "Totalmente Verificada".

**Acceptance Scenarios**:

1. **Given** una pre-reserva con 3 ítems (ej. 1 alojamiento y 2 actividades), **When** el operador marca como disponible el último ítem pendiente, **Then** el sistema actualiza el estado global de la pre-reserva a "Verificada" y notifica al agente responsable.
2. **Given** una pre-reserva donde al menos un ítem crítico resulta "No Disponible", **When** el operador guarda el resultado, **Then** el sistema marca la pre-reserva como "Incompleta / Requiere Ajuste" e impide avanzar a cotización final sin resolver la contingencia.

---

### User Story 4 - Trazabilidad y Tiempos de Verificación (Priority: P3)

Como administrador de operaciones, quiero auditar cuánto tiempo tardan los operadores en verificar la disponibilidad con los proveedores y qué persona confirmó cada servicio, para identificar cuellos de botella y mejorar la calidad de respuesta.

**Why this priority**: Asegura que la agencia responda ágilmente al cliente antes de que busque otras alternativas.

**Independent Test**: Puede probarse registrando una verificación y revisando el historial de auditoría del ítem para validar que se guarda la marca temporal, el operador actuante y el contacto del proveedor.

**Acceptance Scenarios**:

1. **Given** una verificación completada, **When** se consulta el historial de la pre-reserva, **Then** se detalla: quién verificó, cuándo inició, cuándo concluyó y las notas del proveedor.

---

### Edge Cases

- ¿Qué sucede si un proveedor confirma disponibilidad pero impone una fecha límite para sostenerla (time-limit)? El sistema debe permitir registrar una fecha/hora límite de expiración de la disponibilidad verificada.
- ¿Qué ocurre si la solicitud del cliente contiene múltiples alternativas de fechas? La pre-reserva debe permitir verificar opciones alternativas sin confundir las opciones primarias.
- ¿Puede un agente forzar una cotización si un ítem no ha sido verificado? Solo si cuenta con permisos especiales de administrador y queda registrado en la bitácora de auditoría como excepción operativa.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE permitir generar una o más Pre-Reservas a partir de una Solicitud de Cliente existente.
- **FR-002**: Toda Pre-Reserva DEBE componerse de una o más Líneas de Servicio (experiencias, noches de alojamiento, paquetes o complementos) con fechas y cantidades específicas.
- **FR-003**: Toda Pre-Reserva DEBE iniciar en estado "Pendiente de Verificación".
- **FR-004**: El sistema DEBE proporcionar una Bandeja/Cola de Verificación Operativa accesible para roles autorizados (Operador, Admin).
- **FR-005**: El sistema DEBE permitir registrar para cada línea de servicio: estado de disponibilidad (Pendiente, Disponible, No Disponible, Alternativa Sugerida), contacto del proveedor, fecha/hora límite de reserva y observaciones.
- **FR-006**: El sistema DEBE calcular y actualizar el estado global de la Pre-Reserva: "Pendiente", "Parcialmente Verificada", "Totalmente Verificada", "No Disponible" o "Expirada".
- **FR-007**: El sistema DEBE advertir y bloquear la generación automática de cotizaciones vinculantes si la Pre-Reserva no está en estado "Totalmente Verificada" (salvo sobreescritura manual por Administrador).

### Key Entities

- **Pre-Reserva**: Agrupación operativa de servicios a verificar para un cliente. Atributos: ID, OrganizaciónID, SolicitudID, ClienteID, AgenteResponsableID, OperadorAsignadoID, Estado (Pendiente, Verificada, No Disponible, Cancelada), FechaCreación, FechaLímiteVigencia.
- **Ítem de Pre-Reserva**: Línea individual de servicio a verificar con un proveedor. Atributos: ID, PreReservaID, ProductoID / AddOnID, FechaInicio, FechaFin, CantidadPersonas, ProveedorNombre, ProveedorContacto, EstadoVerificación (Pendiente, Disponible, NoDisponible), VerificadoPorUsuarioID, FechaHoraVerificación, NotasOperador.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% de los ítems cotizados tienen registro explícito de verificación previa y persona responsable.
- **SC-002**: Reducción del tiempo promedio de verificación operativa de cupos a menos de 4 horas hábiles por solicitud.
- **SC-003**: 0 reservas fallidas por sobreventa de cupos derivadas de omisión en el flujo de verificación.
- **SC-004**: La cola operativa permite al operador filtrar y gestionar ítems de disponibilidad en menos de 3 clics.

## Assumptions

- En esta versión, la verificación con el proveedor se realiza de forma manual/asistida por el operador (llamada, WhatsApp externo o correo), registrando el resultado en el sistema (automatizaciones completas con channel managers quedan diferidas según Cap. 31).
- Los proveedores externos no tienen cuentas directas de usuario en este MVP.
