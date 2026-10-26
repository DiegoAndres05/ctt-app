# Feature Specification: Etapa del caso para el viajero

**Feature Branch**: `015-traveler-case-status`

**Created**: 2026-10-26

**Status**: Draft

**Input**: Iteración 5 de 5. Quien ya tiene una referencia puede ver en qué etapa va su caso, demostrando que es el contacto, sin cuenta y sin ver el expediente interno. Una solicitud no se presenta como reserva (`.specify/mainspec.md`, principios 1 y 5, criterio de éxito 5–9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Consultar la etapa con la referencia (Priority: P1)

Como viajero que recibió una referencia de solicitud, quiero consultar en qué punto va mi caso indicando esa referencia y el mismo correo o teléfono que dejé, para no reconstruir la historia por mensajes sueltos.

**Why this priority**: El producto existe para que la operación deje de vivir en chats. El viajero también necesita una respuesta fiel al estado real.

**Independent Test**: Con una solicitud web ya creada, el viajero escribe la referencia y el correo de esa solicitud y ve la etapa «Solicitud recibida» o «En revisión», más el nombre público de la ficha y las fechas. No ve notas internas.

**Acceptance Scenarios**:

1. **Given** una solicitud recibida, **When** el viajero indica la referencia y el correo o el teléfono de ese caso, **Then** ve la etapa en lenguaje claro, la referencia, las fechas pedidas y el nombre público de lo que pidió.
2. **Given** la misma solicitud ya pasada a revisión, **When** consulta de nuevo, **Then** la etapa dice que la agencia la está revisando.
3. **Given** una referencia descartada, **When** consulta con el contacto correcto, **Then** ve que la solicitud no continuó, sin el motivo interno.

---

### User Story 2 - Nombrar la etapa real, no una reserva imaginaria (Priority: P1)

Como viajero, quiero que la pantalla distinga solicitud, verificación, propuesta, reserva y viaje terminado o cancelado, para no creer que ya tengo un cupo cuando solo pedí información.

**Why this priority**: Es el cierre del principio «una solicitud no es una reserva» en la cara pública.

**Independent Test**: Cinco casos de prueba, uno en cada etapa gruesa, muestran cinco nombres distintos. El de solo solicitud no usa la palabra reserva como si ya existiera.

**Acceptance Scenarios**:

1. **Given** solo una solicitud, **When** el viajero consulta, **Then** el título de la etapa no afirma que exista una reserva.
2. **Given** una pre-reserva en verificación, **When** consulta, **Then** ve que la agencia está comprobando disponibilidad y que aún no está confirmado.
3. **Given** una cotización enviada, **When** consulta, **Then** ve que hay una propuesta y la instrucción de abrir el enlace que la agencia le envió. No ve el precio en esta pantalla.
4. **Given** una reserva confirmada, en curso, completada o cancelada, **When** consulta, **Then** ve esa etapa y la instrucción de abrir el comprobante que recibió. No ve documentos de identidad ni datos del prestador.

---

### User Story 3 - No enseñar el caso a quien no es el contacto (Priority: P1)

Como agencia, quiero que alguien que solo adivina una referencia, o que usa otro correo, reciba la misma respuesta que si el caso no existiera.

**Why this priority**: La referencia viaja por WhatsApp. No puede ser una llave suficiente para leer el caso de otra persona.

**Independent Test**: Referencia válida con correo distinto, referencia inventada y demasiados intentos producen el mismo mensaje neutro, sin indicar cuál de las dos falló ni revelar el teléfono guardado.

**Acceptance Scenarios**:

1. **Given** una referencia real y un correo que no es el del caso, **When** alguien consulta, **Then** ve que no hay un caso con esos datos. La pantalla no dice si la referencia existe.
2. **Given** una referencia que no existe, **When** alguien consulta, **Then** ve el mismo mensaje que en el escenario anterior.
3. **Given** muchos intentos seguidos, **When** la persona insiste, **Then** ve que debe esperar. No obtiene datos del caso.

---

### Edge Cases

- La consulta no crea una cuenta ni inicia sesión en el panel.
- No muestra el motivo de descarte, notas, costos, margen, otros pasajeros, documentos ni el enlace secreto de la cotización o del comprobante. Esos enlaces siguen siendo los que la agencia ya envió.
- Si hay varias piezas (solicitud, pre-reserva, cotización y reserva) del mismo caso, se muestra la etapa más avanzada, no un historial interno.
- Un cliente anonimizado ya no se puede consultar con el correo o el teléfono antiguos: la respuesta es la misma que «no encontrado».
- La pantalla no permite aceptar la cotización, pagar ni cancelar. Solo informa la etapa.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Un viajero sin cuenta DEBE poder consultar una referencia aportando el correo o el teléfono registrados en ese caso.
- **FR-002**: Si los datos coinciden, el sistema DEBE mostrar una sola etapa en lenguaje de viajero: solicitud recibida, en revisión, solicitud cerrada, comprobando disponibilidad, propuesta lista, reserva confirmada, viaje en curso, viaje completado o reserva cancelada.
- **FR-003**: La etapa mostrada DEBE ser la más avanzada del caso. Una solicitud sin pre-reserva NO DEBE presentarse como reserva.
- **FR-004**: La respuesta DEBE poder incluir la referencia, las fechas y el nombre público de lo solicitado. NO DEBE incluir precio, notas internas, motivo de descarte, datos de prestador, documentos, otros pasajeros ni los enlaces secretos de la propuesta o del comprobante.
- **FR-005**: Referencia desconocida y contacto que no coincide DEBEN producir el mismo mensaje, sin indicar cuál falló.
- **FR-006**: Intentos repetidos DEBEN bloquearse con un mensaje de espera, sin devolver datos del caso.
- **FR-007**: Un cliente anonimizado NO DEBE poder consultarse con el contacto que ya fue retirado.
- **FR-008**: Esta consulta NO DEBE crear ni modificar solicitudes, pre-reservas, cotizaciones, reservas ni pagos.

### Key Entities

- **Consulta del viajero**: Referencia más correo o teléfono. No es una sesión de operador.
- **Etapa visible**: El nombre público del punto más avanzado del caso, más fechas y nombre de la oferta. No es el expediente.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un viajero con la referencia y el correo correctos entiende la etapa en menos de 1 minuto, sin llamar a la agencia.
- **SC-002**: En una batería con un caso por cada etapa de FR-002, el 100% muestra el nombre de etapa que corresponde y ninguno de solo solicitud usa «reserva confirmada».
- **SC-003**: En 20 consultas con contacto incorrecto o referencia inventada, el 100% recibe el mismo mensaje y cero filtran precio, notas o enlaces.
- **SC-004**: Después de esas consultas, el 100% de los expedientes de prueba permanece sin cambios de estado.

## Assumptions

- Las referencias de solicitud, y los expedientes de pre-reserva, cotización y reserva, ya existen (003–006).
- El correo y el teléfono de comparación son los que quedaron guardados en el caso, no un dato nuevo que el viajero elija al consultar.
- Quien tiene el enlace secreto de la propuesta o del comprobante sigue abriendo esas páginas como hoy. Esta pantalla no las sustituye.
- Hay una sola agencia en el sitio público.
- El texto está en el idioma activo del sitio.
