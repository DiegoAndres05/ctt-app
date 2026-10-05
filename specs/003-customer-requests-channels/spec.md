# Feature Specification: 003-customer-requests-channels

**Feature Branch**: `003-customer-requests-channels`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Captura multicanal de solicitudes (Web y WhatsApp) y gestión de clientes derivado de mainspec.md (Capítulos 9, 15, 19, 24, Principio 1)."

## Clarifications

### Session 2026-09-09

- Q: ¿Cuál es el conjunto canónico de estados de una Solicitud de Cliente (el spec mezclaba "En Análisis" y "En Gestión")? → A: Cuatro estados: Recibida (`received`) → En Gestión (`in_review`) → Descartada (`discarded`) / En Pre-Reserva (`pre_reservation`).
- Q: ¿Qué alcance tiene WhatsApp en el MVP? → A: Captura asistida y manual por el agente comercial; sin webhook automático ni integración con WhatsApp Business Cloud API (diferida). *(Reemplazada en la sesión 2026-10-04.)*
- Q: ¿Dónde vive el formulario web público de solicitud? → A: Ruta pública en la app Angular (sin sesión) que invoca la Edge Function; la incrustación en WordPress (feature 007) se difiere. *(Reemplazada en la sesión 2026-10-04.)*
- Q: ¿Cuál es la ventana para deduplicar solicitudes idénticas (doble submit)? → A: 2 minutos, reforzada por un `idempotency_key` opcional.
- Q: ¿Cómo se maneja la supresión/rectificación de datos personales (habeas data)? → A: Anonimización lógica que preserva el historial de solicitudes (integridad referencial); sin purga automática por retención en el MVP.

### Session 2026-10-04

- Q: ¿Dónde vive el formulario web de solicitud ahora que el sitio público de la agencia es una aplicación externa que consume la lectura pública del catálogo (feature 009) y no se reconstruye en el panel? → A: El sitio público externo aloja el formulario y envía las solicitudes a un punto de captura público de la plataforma, identificado por organización (mismo patrón que la lectura pública de 009); los productos de interés se identifican por el identificador público de su ficha. El panel no tiene ruta pública de solicitud.
- Q: ¿Qué alcance tiene WhatsApp en el MVP, dado que la integración real exige credenciales del proveedor? → A: Captura manual asistida en el panel más un adaptador de entrada de WhatsApp Business detrás de una frontera aislada, inactivo mientras no haya credenciales y con una ruta de simulación local; los mensajes entrantes de un número que ya tiene una solicitud abierta (Recibida o En Gestión) por WhatsApp se agregan a esa solicitud y, si no, crean una nueva. Sin envío de mensajes salientes.
- Q: ¿Qué hace el sistema cuando los datos de contacto recibidos coinciden con un cliente existente pero difieren de su perfil, o cuando el email y el teléfono apuntan a clientes distintos? → A: Vincula por email y, si no hay coincidencia, por teléfono; los canales de entrada solo completan campos vacíos del perfil, nunca sobrescriben datos existentes ni fusionan clientes; la solicitud conserva los datos enviados y queda marcada "Datos de contacto a revisar".
- Q: ¿Quién puede mover una solicitud a "En Pre-Reserva" mientras la feature 004 no exista? → A: Solo la conversión de la feature 004 (al crear la primera pre-reserva, desde Recibida o En Gestión); en esta feature el estado existe y se puede filtrar, pero no se asigna manualmente. "Descartada" es terminal y exige un motivo.
- Q: ¿Cómo y en cuánto tiempo se entera el equipo de una solicitud nueva (SC-004)? → A: La bandeja de Solicitudes abierta muestra la solicitud nueva sin recargar en 10 segundos o menos; sin correo ni notificaciones push en el MVP; se registra la hora de la primera gestión para medir el tiempo de respuesta.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Recepción de Solicitud de Cliente vía Web (Priority: P1)

Como potencial cliente que navega en la web de la agencia, quiero enviar un formulario de solicitud detallando lo que me interesa (experiencia, fechas estimadas, número de personas, notas especiales) para que la agencia elabore una propuesta personalizada.

**Why this priority**: Es el canal primario digital estructurado de captación de clientes.

**Independent Test**: Puede probarse enviando una solicitud a través del formulario web con datos válidos de contacto y viaje, verificando que se crea una Solicitud de Cliente en estado "Recibida" y se asocia o crea el perfil del cliente.

**Acceptance Scenarios**:

1. **Given** un visitante en el sitio web público de la agencia, **When** completa el formulario de solicitud con nombre, email, teléfono, productos de interés (preseleccionados desde la ficha pública o elegidos en el formulario), fechas tentativas y cantidad de viajeros, **Then** la plataforma registra la solicitud con identificador único y devuelve al sitio la confirmación que este muestra al cliente.
2. **Given** un formulario con campos de contacto obligatorios vacíos o mal formateados, **When** el visitante intenta enviarlo, **Then** el sistema señala los errores de validación sin crear registros incompletos.
3. **Given** una solicitud recibida exitosamente, **When** el sistema la procesa, **Then** queda explícitamente en estado "Solicitud Recibida" y NO compromete inventario ni asume reserva confirmada (Principio: Una solicitud no es una reserva).

---

### User Story 2 - Captura y Registro de Solicitudes vía WhatsApp (Priority: P1)

Como agente comercial de la agencia, quiero registrar o canalizar solicitudes que se originan a través de conversaciones de WhatsApp hacia la plataforma, para que no se pierda ninguna oportunidad en chats aislados y la información quede centralizada y estructurada.

**Why this priority**: La gran mayoría de los clientes de turismo en la región inician contacto por WhatsApp; perder esa trazabilidad es la principal fuente actual de fallos operacionales.

**Independent Test**: Puede probarse simulando la recepción o captura manual asistida de una conversación de WhatsApp hacia una solicitud estructurada en el sistema, vinculando el número de teléfono con el cliente.

**Acceptance Scenarios**:

1. **Given** un cliente que escribe por WhatsApp manifestando interés en un plan, **When** el agente captura la solicitud mediante registro rápido asistido/manual, o el adaptador de entrada de WhatsApp recibe el mensaje, **Then** el sistema crea la Solicitud asociada al canal "WhatsApp" y al número de teléfono correspondiente.
2. **Given** un cliente recurrente que contacta por un nuevo viaje por WhatsApp, **When** entra su solicitud, **Then** el sistema identifica el número de teléfono y asocia la nueva solicitud a su perfil histórico de cliente existente.
3. **Given** un número de WhatsApp que ya tiene una solicitud abierta (Recibida o En Gestión) por ese canal, **When** llega un mensaje nuevo de ese número, **Then** el mensaje se agrega a la conversación de esa solicitud y no se crea una solicitud nueva.
4. **Given** un entorno sin credenciales del proveedor de WhatsApp, **When** se ejecuta la simulación local de un mensaje entrante, **Then** el resultado es el mismo que con un mensaje real (cliente vinculado, solicitud creada o actualizada).

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
2. **Given** un cliente que ejerce su derecho de rectificación o supresión de datos no sujetos a retención legal contable, **When** el administrador procesa la solicitud, **Then** el sistema anonimiza lógicamente la PII (valores tombstone) preservando el historial de solicitudes y su integridad referencial, y registra el evento en auditoría.

---

### Edge Cases

- ¿Qué ocurre si un cliente envía múltiples solicitudes idénticas en un lapso corto de tiempo (ej. doble clic en el formulario web)? El sistema debe detectar solicitudes duplicadas dentro de una ventana de 2 minutos (reforzada por un `idempotency_key` opcional) y responder de forma idempotente para evitar duplicación de trabajo a los agentes.
- ¿Cómo se manejan números de teléfono internacionales con diferentes formatos de código de país? El sistema debe normalizar el número telefónico a formato estándar internacional (ej. E.164).
- ¿Qué ocurre si una solicitud se recibe para una fecha pasada? El formulario debe impedir seleccionar fechas pasadas como fecha de inicio del viaje.
- ¿Qué ocurre si el visitante pide un producto cuya ficha pública está agotada o ya no está publicada? La solicitud se rechaza indicando que el producto no está disponible, tal como exige la feature 009 para fichas agotadas.
- ¿Qué ocurre si el email del formulario coincide con un cliente y el teléfono con otro, o si los datos enviados difieren del perfil existente? La solicitud se vincula al cliente encontrado por email (o por teléfono si no hay email coincidente), el perfil no se sobrescribe ni se fusiona, se guardan los datos enviados en la solicitud y esta queda marcada "Datos de contacto a revisar".
- ¿Qué ocurre si el proveedor de WhatsApp reenvía el mismo mensaje (reintento)? El mensaje se procesa una sola vez; los reintentos no crean solicitudes ni mensajes duplicados.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE proveer un punto de captura público, identificado por organización, que el sitio web público externo de la agencia invoca para registrar solicitudes, capturando datos del cliente (nombre, email, teléfono), fechas estimadas, número de pasajeros (adultos/niños) y productos de interés identificados por su ficha pública. El punto de captura DEBE rechazar productos cuya ficha no esté publicada o esté agotada.
- **FR-002**: El sistema DEBE registrar el canal de procedencia de cada solicitud (Web, WhatsApp, Presencial, Telefónico). La captura por WhatsApp DEBE ser posible de forma manual asistida por el agente y mediante el adaptador de entrada de WhatsApp (FR-009).
- **FR-003**: El sistema DEBE crear o vincular automáticamente el perfil del Cliente al recibir una solicitud, buscando primero por correo electrónico normalizado y luego por número telefónico normalizado. Los canales de entrada solo DEBEN completar campos vacíos del perfil; NO DEBEN sobrescribir datos existentes ni fusionar clientes. Si los datos enviados difieren del perfil o el email y el teléfono corresponden a clientes distintos, la solicitud DEBE conservar los datos enviados y quedar marcada "Datos de contacto a revisar".
- **FR-004**: El sistema DEBE mantener el estado inicial de toda solicitud como "Recibida", sin realizar bloqueos de inventario ni emitir confirmaciones de reserva.
- **FR-005**: El sistema DEBE permitir a los agentes comerciales asignar solicitudes a miembros del equipo, cambiar estados según la máquina de estados canónica y agregar notas internas. Transiciones manuales permitidas: Recibida → En Gestión, Recibida → Descartada, En Gestión → Descartada; descartar exige un motivo y "Descartada" es terminal. La transición a "En Pre-Reserva" (desde Recibida o En Gestión) solo la realiza la conversión de la feature 004 y NO se ofrece manualmente.
- **FR-006**: El sistema DEBE proteger los datos personales del cliente aplicando el principio de necesidad de conocer y evitando exposición pública en endpoints no autenticados.
- **FR-008**: El sistema DEBE soportar la rectificación y la supresión de datos personales mediante anonimización lógica (sustitución de PII por valores tombstone) que preserva el historial de solicitudes y su integridad referencial; sin purga automática por retención en el MVP.
- **FR-007**: El sistema DEBE almacenar el historial cronológico de todas las solicitudes enviadas por un mismo cliente.
- **FR-009**: El adaptador de entrada de WhatsApp DEBE estar aislado detrás de una frontera explícita, permanecer inactivo mientras no existan credenciales del proveedor, procesar cada mensaje una sola vez aunque el proveedor lo reenvíe, agregar los mensajes de un número con solicitud abierta (Recibida o En Gestión) por WhatsApp a esa solicitud y crear una solicitud nueva en los demás casos. DEBE existir una ruta de simulación local que produzca el mismo resultado sin credenciales. El envío de mensajes salientes queda fuera de alcance.
- **FR-010**: La bandeja de Solicitudes abierta por un colaborador DEBE mostrar las solicitudes nuevas de su organización sin recargar la página, y el sistema DEBE registrar la hora de la primera gestión de cada solicitud (paso de Recibida a otro estado).

### Key Entities

- **Cliente**: Persona que solicita o adquiere servicios turísticos. Atributos: ID, OrganizaciónID, Nombre, Apellido, Email, Teléfono (formato normalizado), Tipo de documento, Número de documento, País de origen, Fecha de creación.
- **Solicitud de Cliente**: Intención comercial no vinculante. Atributos: ID, OrganizaciónID, Referencia legible única por organización, ClienteID, Canal (Web, WhatsApp, Presencial, Telefónico), Fecha de solicitud, Fechas tentativas de viaje, Pasajeros (adultos, niños), Ítems de interés (producto del catálogo vía su ficha pública, o texto libre), Requerimientos especiales, Datos de contacto enviados, Marca "Datos de contacto a revisar", Responsable asignado, Hora de primera gestión, Motivo de descarte, Estado (Recibida, En Gestión, Descartada, En Pre-Reserva). Estados canónicos: `received`, `in_review`, `discarded`, `pre_reservation`.
- **Nota de Seguimiento**: Comentario interno del agente sobre la solicitud o cliente. Atributos: ID, SolicitudID / ClienteID, UsuarioAutorID, Fecha, Contenido.
- **Mensaje Entrante**: Mensaje recibido por un canal de mensajería (WhatsApp) asociado a un cliente y a una solicitud. Atributos: ID, OrganizaciónID, Canal, Identificador del mensaje en el proveedor (único), Teléfono de origen, Nombre de perfil, Contenido, Fecha de recepción, ClienteID, SolicitudID.
- **Conexión de Canal**: Vínculo entre una organización y una cuenta de mensajería del proveedor (p. ej. el número de WhatsApp Business de la agencia), usado para saber a qué organización pertenece un mensaje entrante. Atributos: ID, OrganizaciónID, Canal, Proveedor, Identificador de la cuenta en el proveedor, Estado (activa/inactiva). Las credenciales no se guardan aquí.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: El formulario web procesa y confirma la recepción de una solicitud en menos de 2 segundos.
- **SC-002**: 100% de las solicitudes capturadas quedan vinculadas a un cliente con canal de origen explícito.
- **SC-003**: 0 reservas confirmadas directamente desde una solicitud sin haber pasado por el proceso de verificación y cotización previa.
- **SC-004**: El 100% de las solicitudes nuevas aparecen en la bandeja abierta de los colaboradores de la organización en 10 segundos o menos, sin recargar la página; el tiempo hasta la primera gestión queda registrado para el 100% de las solicitudes gestionadas.

## Assumptions

- La captura por WhatsApp funciona en el MVP de forma manual asistida por el agente y mediante un adaptador de entrada inactivo sin credenciales del proveedor; con credenciales reales se activa sin cambiar las reglas de negocio. Plantillas y mensajes salientes quedan diferidos.
- El formulario web vive en el sitio web público externo de la agencia (el mismo consumidor de la lectura pública de la feature 009), que invoca el punto de captura público de la plataforma; el panel no aloja un formulario público.
- Todos los colaboradores internos de la organización (Agente, Operador, Administrador) comparten la bandeja de solicitudes y la consulta de clientes; la anonimización es exclusiva del Administrador.
- Las solicitudes no representan contratos comerciales vinculantes.
