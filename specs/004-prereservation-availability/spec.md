# Feature Specification: 004-prereservation-availability

**Feature Branch**: `004-prereservation-availability`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Pre-reservas y proceso operativo de verificación de disponibilidad humana derivado de mainspec.md (Capítulos 10, 11, 28)."

## Clarifications

### Session 2026-10-04

- Q: ¿Desde qué estados de una Solicitud se puede crear una Pre-Reserva, cuántas admite una misma Solicitud y qué le ocurre a la Solicitud al convertirla? → A: Desde "Recibida" o "En Gestión"; la primera Pre-Reserva pasa la Solicitud a "En Pre-Reserva" en la misma operación. Una Solicitud que ya está "En Pre-Reserva" admite Pre-Reservas adicionales (replanteos); una Solicitud "Descartada" o de un cliente anonimizado no admite ninguna.
- Q: ¿Cuál es el conjunto canónico de estados globales de una Pre-Reserva y cómo se calcula (el spec mezclaba "Verificada", "Incompleta / Requiere Ajuste" y "No Disponible")? → A: Seis estados: Pendiente de Verificación, Parcialmente Verificada, Totalmente Verificada, Requiere Ajuste, Expirada y Cancelada. Todos menos Cancelada se calculan automáticamente a partir de las líneas principales vigentes, y todas las líneas principales son críticas: con alguna línea en "No Disponible" o "Alternativa Sugerida" la Pre-Reserva queda en "Requiere Ajuste"; con todas "Disponible", en "Totalmente Verificada"; con algunas, en "Parcialmente Verificada"; con ninguna, en "Pendiente de Verificación". Cancelada es manual, exige motivo y es terminal. Al llegar a "Totalmente Verificada" se avisa al agente responsable dentro del panel (sin correo).
- Q: ¿Cómo se registran opciones alternativas (otras fechas u otro servicio) sin confundirlas con las principales, y cómo se resuelve una contingencia? → A: Como líneas alternativas vinculadas a una línea principal. Se verifican igual que las principales pero no cuentan para el estado global. El agente puede promover una alternativa a principal, lo que retira la principal original. Una contingencia se resuelve retirando líneas (con motivo), agregando líneas nuevas o promoviendo alternativas. Fechas, producto y pasajeros de una línea no se editan en el lugar.
- Q: ¿Cuándo expira una Pre-Reserva y qué pasa al expirar? → A: Al marcar una línea como "Disponible", el operador puede registrar la fecha y hora límite de retención que fija el proveedor. La vigencia de la Pre-Reserva es la retención más próxima entre sus líneas principales disponibles. Al vencer, la Pre-Reserva pasa a "Expirada" y esa línea vuelve a la cola para re-verificación. Registrar de nuevo la disponibilidad con una retención futura reactiva el cálculo. Sin retenciones registradas, la Pre-Reserva no vence.
- Q: ¿Qué roles crean Pre-Reservas, cuáles registran la verificación y quién puede autorizar cotizar sin verificación total? → A: Agente, Operador y Administrador crean, ajustan y cancelan Pre-Reservas. Solo Operador y Administrador acceden a la Cola de Verificación y registran resultados. Solo el Administrador autoriza la excepción "cotizar sin verificación total", con motivo obligatorio y registro en auditoría; la autorización se invalida si cambian las líneas principales. Generar la cotización pertenece a la feature 005: esta feature solo expone la regla de elegibilidad para cotizar.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Conversión de Solicitud a Pre-Reserva (Priority: P1)

Como agente comercial u operador, quiero convertir una solicitud de cliente en una Pre-Reserva con ítems concretos (experiencias, alojamientos, paquetes o complementos, con fechas y pasajeros específicos), para iniciar formalmente la verificación técnica y de cupos con los prestadores de servicio.

**Why this priority**: La Pre-Reserva es la entidad intermedia esencial que formaliza los servicios solicitados antes de generar una cotización de precio vinculante o una confirmación.

**Independent Test**: Puede probarse seleccionando una solicitud en estado "Recibida" o "En Gestión" y creando a partir de ella una Pre-Reserva con líneas de producto específicas, verificando que la Pre-Reserva nace en estado "Pendiente de Verificación" y que la solicitud pasa a "En Pre-Reserva".

**Acceptance Scenarios**:

1. **Given** una solicitud de cliente en estado "Recibida" o "En Gestión", **When** el agente hace clic en "Crear Pre-Reserva" y define los ítems de catálogo, fechas exactas y número de personas, **Then** el sistema genera la Pre-Reserva vinculada a la solicitud y al cliente con estado "Pendiente de Verificación", y la solicitud pasa a "En Pre-Reserva" en la misma operación.
2. **Given** una Pre-Reserva creada, **When** se consulta su estado, **Then** el sistema muestra con claridad que no constituye una reserva confirmada y que requiere verificación operativa.
3. **Given** una solicitud "Descartada" o de un cliente anonimizado, **When** el agente intenta crear una Pre-Reserva, **Then** el sistema lo rechaza con un mensaje claro.
4. **Given** una solicitud que ya está "En Pre-Reserva", **When** el agente crea otra Pre-Reserva a partir de ella, **Then** el sistema la crea y ambas aparecen vinculadas a la solicitud.

---

### User Story 2 - Cola Operativa de Verificación de Disponibilidad (Priority: P1)

Como operador de la agencia, quiero visualizar una lista/cola de tareas de verificación ordenadas por prioridad y fecha de viaje, para saber qué proveedores debo contactar (por llamada, WhatsApp o correo) y verificar si tienen cupos disponibles.

**Why this priority**: El negocio turístico de la agencia depende de proveedores externos (guías, dueños de fincas, lancheros) que no cuentan con APIs automatizadas y requieren validación humana (Human-in-the-loop).

**Independent Test**: Puede probarse accediendo a la cola de verificación con el rol Operador, viendo cada ítem pendiente agrupado por proveedor y marcando el avance de la gestión.

**Acceptance Scenarios**:

1. **Given** un operador autenticado, **When** accede a la bandeja de verificación, **Then** ve todas las líneas de pre-reserva que requieren acción (pendientes de verificación o con retención vencida) con la información de contacto del proveedor y las fechas requeridas.
2. **Given** un ítem en la cola, **When** el operador contacta al proveedor y este confirma cupo, **Then** el operador marca el ítem como "Disponible" registrando la fecha, hora, persona de contacto en el proveedor, medio de contacto, notas relevantes y, si aplica, la fecha/hora límite de retención.
3. **Given** un proveedor que informa no tener disponibilidad para la fecha solicitada, **When** el operador registra la no disponibilidad, **Then** el sistema actualiza el estado de la línea a "No Disponible" y permite registrar la sugerencia de fechas o alternativas ("Alternativa Sugerida").
4. **Given** un usuario con rol Agente, **When** intenta abrir la cola de verificación o registrar un resultado, **Then** el sistema no muestra la cola y rechaza el registro.

---

### User Story 3 - Consolidación del Estado de la Pre-Reserva (Priority: P2)

Como agente comercial, quiero saber cuándo todos los ítems de una pre-reserva han sido verificados satisfactoriamente, para proceder de inmediato a elaborar la cotización formal para el cliente.

**Why this priority**: Evita emitir cotizaciones o compromisos comerciales sobre servicios que no cuentan con disponibilidad real garantizada.

**Independent Test**: Puede probarse marcando como disponibles todas las líneas principales de una pre-reserva compuesta y comprobando que el estado global de la pre-reserva cambia automáticamente a "Totalmente Verificada".

**Acceptance Scenarios**:

1. **Given** una pre-reserva con 3 líneas principales (ej. 1 alojamiento y 2 actividades), **When** el operador marca como disponible la última línea pendiente, **Then** el sistema actualiza el estado global de la pre-reserva a "Totalmente Verificada" y avisa en el panel al agente responsable.
2. **Given** una pre-reserva donde al menos una línea principal resulta "No Disponible" o "Alternativa Sugerida", **When** el operador guarda el resultado, **Then** el sistema marca la pre-reserva como "Requiere Ajuste" y la declara no elegible para cotización hasta resolver la contingencia (retirar, reemplazar o promover una alternativa).
3. **Given** una pre-reserva "Totalmente Verificada" cuya retención más próxima vence, **When** se consulta la pre-reserva o la cola, **Then** la pre-reserva aparece como "Expirada" y la línea vencida vuelve a la cola para re-verificación.
4. **Given** una pre-reserva no verificada totalmente, **When** un Administrador autoriza la excepción para cotizar indicando un motivo, **Then** la pre-reserva queda elegible para cotización y la excepción queda registrada en la auditoría.

---

### User Story 4 - Trazabilidad y Tiempos de Verificación (Priority: P3)

Como administrador de operaciones, quiero auditar cuánto tiempo tardan los operadores en verificar la disponibilidad con los proveedores y qué persona confirmó cada servicio, para identificar cuellos de botella y mejorar la calidad de respuesta.

**Why this priority**: Asegura que la agencia responda ágilmente al cliente antes de que busque otras alternativas.

**Independent Test**: Puede probarse registrando una verificación y revisando el historial de la línea para validar que se guarda la marca temporal, el operador actuante y el contacto del proveedor.

**Acceptance Scenarios**:

1. **Given** una verificación completada, **When** se consulta el historial de la pre-reserva, **Then** se detalla por línea: quién verificó, cuándo inició, cuándo concluyó, la persona de contacto del proveedor y las notas, y para la pre-reserva el tiempo total desde su creación hasta "Totalmente Verificada".

---

### Edge Cases

- ¿Qué sucede si un proveedor confirma disponibilidad pero impone una fecha límite para sostenerla (time-limit)? El operador registra la fecha/hora límite de retención en la línea. La vigencia de la Pre-Reserva es la retención más próxima entre sus líneas principales disponibles; al vencer, la Pre-Reserva pasa a "Expirada" y la línea vuelve a la cola. Una retención en el pasado se rechaza.
- ¿Qué ocurre si la solicitud del cliente contiene múltiples alternativas de fechas? Se registran como líneas alternativas vinculadas a una línea principal; se verifican igual, no afectan el estado global y el agente puede promover una alternativa a principal (la principal original queda retirada).
- ¿Puede un agente forzar una cotización si un ítem no ha sido verificado? No. Solo un Administrador puede autorizar la excepción, con motivo obligatorio y registro en la bitácora de auditoría como excepción operativa; agregar, retirar o promover líneas principales después invalida la autorización.
- ¿Qué ocurre si se retiran todas las líneas principales? El sistema lo impide: una Pre-Reserva vigente conserva al menos una línea principal.
- ¿Qué ocurre si se intenta modificar una Pre-Reserva Cancelada? Se rechaza; Cancelada es terminal. La solicitud origen conserva el estado "En Pre-Reserva".
- ¿Qué ocurre si el producto o complemento está inactivo en el catálogo, o si las fechas están en el pasado? Se rechaza la línea. Un alojamiento exige fecha de salida posterior a la de llegada.
- ¿Qué ocurre si el producto no tiene proveedor registrado? La línea se crea con el nombre y contacto del proveedor escritos por el agente u operador, o sin proveedor; aparece en la cola como "Sin proveedor".

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE permitir generar una o más Pre-Reservas a partir de una Solicitud de Cliente en estado "Recibida", "En Gestión" o "En Pre-Reserva". La primera conversión DEBE pasar la Solicitud a "En Pre-Reserva" en la misma operación. Una Solicitud "Descartada" o de un cliente anonimizado NO DEBE admitir conversión.
- **FR-002**: Toda Pre-Reserva DEBE componerse de una o más Líneas de Servicio principales (experiencias, noches de alojamiento, paquetes o complementos) con fechas, pasajeros y cantidades específicas, y PUEDE incluir líneas alternativas vinculadas a una principal.
- **FR-003**: Toda Pre-Reserva DEBE iniciar en estado "Pendiente de Verificación" con todas sus líneas en "Pendiente".
- **FR-004**: El sistema DEBE proporcionar una Bandeja/Cola de Verificación Operativa accesible solo para los roles Operador y Administrador. Por defecto, la cola ordena por fecha de servicio más próxima y DEBE poder filtrarse por proveedor y por estado de verificación.
- **FR-005**: El sistema DEBE permitir registrar para cada línea de servicio: estado de disponibilidad (Pendiente, Disponible, No Disponible, Alternativa Sugerida), persona de contacto en el proveedor, medio de contacto (llamada, WhatsApp, correo, otro), fecha/hora límite de retención, sugerencia de alternativa y observaciones. Solo Operador y Administrador pueden registrar resultados.
- **FR-006**: El sistema DEBE calcular y actualizar automáticamente el estado global de la Pre-Reserva a partir de sus líneas principales vigentes, con esta precedencia: "Expirada" (alguna línea disponible con retención vencida) > "Requiere Ajuste" (alguna No Disponible o Alternativa Sugerida) > "Totalmente Verificada" (todas Disponible) > "Parcialmente Verificada" (alguna Disponible) > "Pendiente de Verificación". "Cancelada" es manual, exige motivo y es terminal.
- **FR-007**: El sistema DEBE declarar no elegible para cotización vinculante toda Pre-Reserva que no esté en "Totalmente Verificada", salvo una excepción autorizada por un Administrador con motivo. La excepción se registra en auditoría y se invalida si cambian las líneas principales. La generación de la cotización pertenece a la feature 005, que DEBE consultar esta regla.
- **FR-008**: El sistema DEBE permitir ajustar una Pre-Reserva no cancelada: agregar líneas, retirar líneas con motivo y promover una línea alternativa a principal (lo que retira la principal original). Fechas, producto y pasajeros de una línea existente no se editan en el lugar.
- **FR-009**: El sistema DEBE conservar un historial inalterable de la verificación por línea: inicio de la gestión, cada resultado registrado, retiros y promociones, con el actor, la fecha y hora, la persona de contacto del proveedor y las notas.
- **FR-010**: El sistema DEBE avisar dentro del panel al agente responsable cuando una de sus Pre-Reservas llega a "Totalmente Verificada". En el MVP no hay correo ni notificaciones push.
- **FR-011**: Al crear una línea, el sistema DEBE tomar el nombre y el contacto del proveedor registrado del producto; si el producto no tiene proveedor, el usuario PUEDE escribirlos.
- **FR-012**: Toda Pre-Reserva DEBE tener una referencia legible única por organización y conservar su responsable comercial (agente) y, opcionalmente, un operador asignado a la verificación.

### Key Entities

- **Pre-Reserva**: Agrupación operativa de servicios a verificar para un cliente. Atributos: ID, OrganizaciónID, Referencia, SolicitudID, ClienteID, AgenteResponsableID, OperadorAsignadoID, Estado (Pendiente de Verificación, Parcialmente Verificada, Totalmente Verificada, Requiere Ajuste, Expirada, Cancelada), FechaCreación, FechaVerificaciónTotal, FechaLímiteVigencia (derivada de la retención más próxima), MotivoCancelación, ExcepciónCotización (autor, fecha, motivo).
- **Línea de Pre-Reserva**: Línea individual de servicio a verificar con un proveedor. Atributos: ID, PreReservaID, ProductoID o ComplementoID, LíneaPrincipalID (solo alternativas), FechaInicio, FechaFin, Adultos, Niños, Cantidad, ProveedorNombre, ProveedorContacto, EstadoVerificación (Pendiente, Disponible, No Disponible, Alternativa Sugerida), InicioGestión, VerificadoPorUsuarioID, FechaHoraVerificación, PersonaContactoProveedor, MedioContacto, RetenciónHasta, SugerenciaAlternativa, NotasOperador, Retirada (fecha y motivo).
- **Evento de Verificación**: Registro inalterable de cada acción sobre una línea (inicio, resultado, retiro, promoción) con actor, fecha y hora, estado anterior y nuevo, contacto del proveedor y notas.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% de las Pre-Reservas elegibles para cotización tienen todas sus líneas principales con verificación registrada y operador responsable, o una excepción de Administrador registrada en auditoría.
- **SC-002**: Reducción del tiempo promedio de verificación operativa de cupos a menos de 4 horas hábiles por solicitud, medido desde la creación de la Pre-Reserva hasta "Totalmente Verificada" con las marcas temporales registradas.
- **SC-003**: 0 reservas fallidas por sobreventa de cupos derivadas de omisión en el flujo de verificación.
- **SC-004**: Desde el menú, el operador abre la cola, filtra por proveedor y abre el registro de un resultado en 3 clics o menos.

## Assumptions

- En esta versión, la verificación con el proveedor se realiza de forma manual/asistida por el operador (llamada, WhatsApp externo o correo), registrando el resultado en el sistema (automatizaciones completas con channel managers quedan diferidas según Cap. 31). El panel solo ofrece accesos directos para llamar, escribir por WhatsApp o enviar correo usando las aplicaciones del dispositivo; no envía mensajes.
- Los proveedores externos no tienen cuentas directas de usuario en este MVP.
- Las Pre-Reservas no bloquean inventario ni calculan precios; el precio y la cotización pertenecen a la feature 005 y la reserva confirmada a la feature 006.
- Un paquete se verifica como una única línea, no componente por componente.
