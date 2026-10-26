# Feature Specification: Solicitud pública desde la ficha

**Feature Branch**: `012-public-trip-request`

**Created**: 2026-10-26

**Status**: Draft

**Input**: Iteración 2 de 5. El viajero envía una solicitud de la ficha que está viendo. La agencia la recibe en la misma bandeja que el resto de canales. Una solicitud no es una reserva (`.specify/mainspec.md`, capítulos 9 y 15, principio 1).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pedir información de la ficha elegida (Priority: P1)

Como viajero, quiero enviar mis datos, las fechas y el número de personas junto con la experiencia, el alojamiento o el yate que estoy viendo, para que la agencia me prepare una propuesta sin que yo cree una cuenta.

**Why this priority**: Es el canal web que el producto promete. El panel ya sabe recibir la solicitud; el viajero todavía no tiene el formulario en la ficha.

**Independent Test**: Desde una ficha publicada, el visitante completa el formulario, acepta el uso de sus datos y recibe una referencia. En la bandeja interna aparece la misma solicitud, ligada a esa ficha, en estado recibida.

**Acceptance Scenarios**:

1. **Given** una ficha publicada, **When** el visitante envía nombre, apellido, correo, teléfono, fechas, adultos y el consentimiento, **Then** ve una confirmación con la referencia de la solicitud y el texto deja claro que la agencia va a revisar la petición y que todavía no hay reserva.
2. **Given** el envío anterior, **When** un agente abre la bandeja, **Then** la solicitud está recibida, con la ficha preseleccionada, el canal web y los datos de contacto.
3. **Given** un visitante que no marca el consentimiento, **When** intenta enviar, **Then** el envío no se crea y se le explica que el consentimiento es necesario.
4. **Given** fechas en el pasado o una fecha de fin anterior al inicio, **When** intenta enviar, **Then** el envío no se crea y se indica qué corregir.

---

### User Story 2 - No duplicar ni confundir con una reserva (Priority: P1)

Como viajero que reintenta el envío, quiero que un doble clic no abra dos casos, y como agente quiero seguir viendo una sola solicitud.

**Why this priority**: El canal web ya rechaza duplicados. La pantalla tiene que respetar esa regla y no prometer una reserva.

**Independent Test**: Enviar dos veces el mismo formulario en la misma visita devuelve la misma referencia. El título de éxito no dice «reserva enviada» ni «reserva confirmada».

**Acceptance Scenarios**:

1. **Given** un envío ya aceptado en esa visita, **When** el visitante reintenta sin cambiar los datos, **Then** ve la misma referencia y la bandeja no gana una segunda solicitud.
2. **Given** la pantalla de éxito, **When** se lee el mensaje, **Then** habla de solicitud recibida y de que la agencia contactará al viajero. No habla de reserva confirmada, localizador de viaje ni pago.

---

### User Story 3 - Avisar cuando la ficha ya no se puede pedir (Priority: P2)

Como viajero, quiero enterarme si la ficha dejó de estar disponible mientras yo llenaba el formulario, para no creer que mi solicitud entró.

**Why this priority**: Entre abrir la ficha y enviar, un operador puede despublicar. El viajero necesita un fallo honesto.

**Independent Test**: Con el formulario abierto, se despublica la ficha y el envío muestra que esa oferta ya no admite solicitudes, sin crear un caso.

**Acceptance Scenarios**:

1. **Given** una ficha que deja de estar publicada antes del envío, **When** el visitante envía, **Then** no se crea la solicitud y el mensaje invita a volver al catálogo.
2. **Given** demasiados envíos seguidos con el mismo correo, teléfono o para la misma agencia, **When** el visitante insiste, **Then** ve que debe esperar y no se crea otra solicitud.

---

### Edge Cases

- El campo oculto anti-automatismos, si viene con texto, no crea solicitud y no explica la trampa.
- Correo o teléfono ilegibles se rechazan con un mensaje de corrección, sin crear un cliente a medias.
- Niños pueden ser cero. Adultos no pueden ser cero.
- Una ficha agotada no abre este formulario: el catálogo ya lo impide. Si alguien llega igual a la dirección, el envío responde que la oferta no admite solicitudes.
- La solicitud no calcula precio, no aparta cupo y no crea pre-reserva, cotización ni reserva.
- Si el contacto coincide con un cliente ya existente, la bandeja sigue las reglas actuales de vinculación y revisión. Esta pantalla no fusiona ni pisa nombres.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El formulario DEBE abrirse con la ficha pública ya elegida y esa ficha DEBE viajar con la solicitud.
- **FR-002**: El visitante DEBE informar nombre, apellido, correo, teléfono, fecha de inicio, fecha de fin, cantidad de adultos y consentimiento de uso de datos. Los niños y una nota son opcionales.
- **FR-003**: Sin consentimiento, con fechas inválidas o con contacto ilegible, el sistema NO DEBE crear la solicitud.
- **FR-004**: Un envío aceptado DEBE devolver una referencia visible y DEBE aparecer en la bandeja interna como solicitud web recibida.
- **FR-005**: Repetir el mismo envío en la misma visita, o el mismo contenido en una ventana corta, DEBE devolver la referencia ya creada.
- **FR-006**: La confirmación DEBE decir que la solicitud fue recibida y que no existe una reserva.
- **FR-007**: Si la ficha ya no admite solicitudes, el sistema NO DEBE crear el caso y DEBE decirlo.
- **FR-008**: El sistema DEBE limitar envíos repetidos por contacto y por agencia, con un mensaje de espera.
- **FR-009**: El formulario NO DEBE crear pre-reserva, cotización, reserva ni pago.

### Key Entities

- **Solicitud web**: Intención del viajero. Atributos: referencia, ficha, contacto, fechas, personas, nota, consentimiento, canal web.
- **Confirmación**: Lo que ve el viajero tras enviar: referencia y la frase de que la agencia revisará la petición.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un visitante completa el formulario de una ficha publicada en menos de 3 minutos.
- **SC-002**: El 100% de los envíos válidos de prueba aparecen en la bandeja con la ficha correcta y el canal web.
- **SC-003**: El 100% de los reintentos de la misma visita conservan una sola referencia.
- **SC-004**: En una revisión del texto de éxito, 10 de cada 10 personas entienden que aún no tienen una reserva.

## Assumptions

- La bandeja, la vinculación de clientes y las reglas de deduplicación y límite ya existen (003). Esta iteración no las cambia.
- El catálogo público de la iteración 1 ya puede abrir una ficha.
- No se pide cuenta ni contraseña al viajero.
- El texto de la pantalla está en el idioma activo del catálogo.
