# Feature Specification: 003-customer-requests-channels

**Feature Branch**: `003-customer-requests-channels`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Captura multicanal de solicitudes (Web y WhatsApp) y gestión de clientes derivado de mainspec.md (Capítulos 9, 15, 19, 24, Principio 1)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Recepción de Solicitud de Cliente vía Web (Priority: P1)

Como potencial cliente que navega en la web de la agencia, quiero enviar un formulario de solicitud detallando lo que me interesa (experiencia, fechas estimadas, número de personas, notas especiales) para que la agencia elabore una propuesta personalizada.

**Why this priority**: Es el canal primario digital estructurado de captación de clientes.

**Independent Test**: Puede probarse enviando una solicitud a través del formulario web con datos válidos de contacto y viaje, verificando que se crea una Solicitud de Cliente en estado "Recibida" y se asocia o crea el perfil del cliente.

**Acceptance Scenarios**:

1. **Given** un visitante en la web, **When** completa el formulario de solicitud con nombre, email, teléfono, productos de interés, fechas tentativas y cantidad de viajeros, **Then** el sistema registra la solicitud con identificador único y confirmación visual al cliente.
2. **Given** un formulario con campos de contacto obligatorios vacíos o mal formateados, **When** el visitante intenta enviarlo, **Then** el sistema señala los errores de validación sin crear registros incompletos.
3. **Given** una solicitud recibida exitosamente, **When** el sistema la procesa, **Then** queda explícitamente en estado "Solicitud Recibida" y NO compromete inventario ni asume reserva confirmada (Principio: Una solicitud no es una reserva).

---

### User Story 2 - Captura y Registro de Solicitudes vía WhatsApp (Priority: P1)

Como agente comercial de la agencia, quiero registrar o canalizar solicitudes que se originan a través de conversaciones de WhatsApp hacia la plataforma, para que no se pierda ninguna oportunidad en chats aislados y la información quede centralizada y estructurada.

**Why this priority**: La gran mayoría de los clientes de turismo en la región inician contacto por WhatsApp; perder esa trazabilidad es la principal fuente actual de fallos operacionales.

**Independent Test**: Puede probarse simulando la recepción o captura manual asistida de una conversación de WhatsApp hacia una solicitud estructurada en el sistema, vinculando el número de teléfono con el cliente.

**Acceptance Scenarios**:

1. **Given** un cliente que escribe por WhatsApp manifestando interés en un plan, **When** se captura la solicitud (mediante webhook de mensajería o registro rápido asistido por el agente), **Then** el sistema crea la Solicitud asociada al canal "WhatsApp" y al número de teléfono correspondiente.
2. **Given** un cliente recurrente que contacta por un nuevo viaje por WhatsApp, **When** entra su solicitud, **Then** el sistema identifica el número de teléfono y asocia la nueva solicitud a su perfil histórico de cliente existente.

---

### User Story 3 - Gestión Centralizada de Perfiles de Clientes (Priority: P2)

Como agente comercial, quiero consultar la ficha del cliente con su información de contacto, historial de solicitudes, cotizaciones previas y notas de preferencias, para brindarle una atención personalizada y rápida.

**Why this priority**: Permite construir relaciones duraderas y entender el contexto del viajero al armar una cotización.

**Independent Test**: Puede probarse consultando el perfil de un cliente y verificando que muestra su información de contacto limpia, sus solicitudes históricas ordenadas cronológicamente y la posibilidad de registrar notas internas.

**Acceptance Scenarios**:

1. **Given** un agente comercial con sesión activa, **When** busca un cliente por nombre, email o teléfono, **Then** el sistema despliega el perfil consolidado con su historial de interacciones.
2. **Given** un cliente que solicita actualizar sus datos de contacto, **When** el agente guarda las modificaciones, **Then** el perfil se actualiza y los registros históricos mantienen referencia clara al cliente.

---

### User Story 4 - Protección de Datos Personales y Privacidad (Priority: P2)

Como oficial de cumplimiento o cliente, quiero que los datos personales recopilados (teléfono, email, documentos de identidad) se almacenen con seguridad y se restrinjan solo a los usuarios internos autorizados, para cumplir con las normativas de protección de datos (habeas data).

**Why this priority**: El manejo de datos de viajeros exige rigurosidad legal y confidencialidad estricta.

**Independent Test**: Puede probarse verificando que los datos sensibles no son expuestos públicamente y que solo los usuarios autorizados de la agencia pueden ver la información de contacto completa.

**Acceptance Scenarios**:

1. **Given** un usuario no autenticado o una consulta pública a la API, **When** se intenta acceder a datos de clientes o solicitudes, **Then** el sistema deniega el acceso categóricamente.
2. **Given** un cliente que ejerce su derecho de rectificación o supresión de datos no sujetos a retención legal contable, **When** el administrador procesa la solicitud, **Then** el sistema aplica las políticas de anonimización o actualización correspondientes.

---

### Edge Cases

- ¿Qué ocurre si un cliente envía múltiples solicitudes idénticas en un lapso corto de tiempo (ej. doble clic en el formulario web)? El sistema debe detectar solicitudes duplicadas en un intervalo breve para evitar duplicación de trabajo a los agentes.
- ¿Cómo se manejan números de teléfono internacionales con diferentes formatos de código de país? El sistema debe normalizar el número telefónico a formato estándar internacional (ej. E.164).
- ¿Qué ocurre si una solicitud se recibe para una fecha pasada? El formulario debe impedir seleccionar fechas pasadas como fecha de inicio del viaje.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE proveer un mecanismo público para la recepción de solicitudes desde la web, capturando datos del cliente (nombre, email, teléfono), fechas estimadas, número de pasajeros (adultos/niños) y productos de interés.
- **FR-002**: El sistema DEBE registrar el canal de procedencia de cada solicitud (Web, WhatsApp, Presencial, Telefónico).
- **FR-003**: El sistema DEBE crear o vincular automáticamente el perfil del Cliente al recibir una solicitud, utilizando el correo electrónico o número telefónico normalizado como identificador de coincidencia.
- **FR-004**: El sistema DEBE mantener el estado inicial de toda solicitud como "Recibida", sin realizar bloqueos de inventario ni emitir confirmaciones de reserva.
- **FR-005**: El sistema DEBE permitir a los agentes comerciales asignar solicitudes a miembros del equipo, cambiar estados (Recibida, En Análisis, Descartada, Convertida en Pre-Reserva) y agregar notas internas.
- **FR-006**: El sistema DEBE proteger los datos personales del cliente aplicando el principio de necesidad de conocer y evitando exposición pública en endpoints no autenticados.
- **FR-007**: El sistema DEBE almacenar el historial cronológico de todas las solicitudes enviadas por un mismo cliente.

### Key Entities

- **Cliente**: Persona que solicita o adquiere servicios turísticos. Atributos: ID, OrganizaciónID, Nombre, Apellido, Email, Teléfono (formato normalizado), Tipo de documento, Número de documento, País de origen, Fecha de creación.
- **Solicitud de Cliente**: Intención comercial no vinculante. Atributos: ID, OrganizaciónID, ClienteID, Canal (Web, WhatsApp, etc.), Fecha de solicitud, Fechas tentativas de viaje, Pasajeros (adultos, niños), Ítems de interés, Requerimientos especiales, Estado (Recibida, En Gestión, Descartada, En Pre-Reserva).
- **Nota de Seguimiento**: Comentario interno del agente sobre la solicitud o cliente. Atributos: ID, SolicitudID / ClienteID, UsuarioAutorID, Fecha, Contenido.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: El formulario web procesa y confirma la recepción de una solicitud en menos de 2 segundos.
- **SC-002**: 100% de las solicitudes capturadas quedan vinculadas a un cliente con canal de origen explícito.
- **SC-003**: 0 reservas confirmadas directamente desde una solicitud sin haber pasado por el proceso de verificación y cotización previa.
- **SC-004**: Reducción del tiempo de respuesta inicial al cliente por parte de los agentes al tener solicitudes centralizadas y notificadas en tiempo real.

## Assumptions

- En la fase inicial del MVP, la integración con WhatsApp opera mediante captura asistida por el agente comercial y/o webhooks estándar para recepción de leads.
- Las solicitudes no representan contratos comerciales vinculantes.
