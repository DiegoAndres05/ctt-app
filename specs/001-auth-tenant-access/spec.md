# Feature Specification: 001-auth-tenant-access

**Feature Branch**: `001-auth-tenant-access`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Autenticación, gestión de usuarios internos, roles/permisos, aislamiento multi-tenant y auditoría base derivado de mainspec.md (Capítulos 16, 17, 20, 23, 25)."

## Clarifications

### Session 2026-09-08

- Q: ¿Cómo se aprovisionará la organización inicial y el primer usuario Administrador para el MVP? → A: Formulario público de registro de agencias ("Registrar mi agencia") con creación automática de tenant y admin.
- Q: ¿Cómo deben recibir su acceso inicial los colaboradores (operadores y agentes) invitados por el Administrador? → A: Contraseña temporal asignada por el Administrador con cambio obligatorio en el primer inicio de sesión.
- Q: ¿Cómo debe ser la asignación de roles para los colaboradores internos? → A: Un único rol por usuario con jerarquía (el Administrador puede ejecutar acciones de Operador y Agente).
- Q: ¿Cuál debe ser la política de duración y expiración de sesión para los usuarios internos? → A: Sesión de jornada laboral estándar (8 horas de inactividad / 24 horas continuas).
- Q: ¿Qué alcance de eventos debe capturar la bitácora de auditoría base en este módulo? → A: Eventos de seguridad y control de acceso (login, logout, intentos fallidos, cambios de roles y creación/desactivación de usuarios).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Autenticación y Gestión de Sesiones Seguras (Priority: P1)

Como usuario interno de la agencia (administrador, operador o agente comercial), quiero iniciar sesión de forma segura en la plataforma para acceder a las herramientas de gestión de acuerdo con mis responsabilidades.

**Why this priority**: Es la puerta de entrada indispensable para cualquier operación del sistema. Sin autenticación confiable, ninguna otra funcionalidad de gestión puede ejecutarse.

**Independent Test**: Puede probarse de forma independiente verificando el inicio de sesión exitoso con credenciales válidas, rechazo ante credenciales inválidas, bloqueo por intentos fallidos y revocación de sesión al cerrar sesión.

**Acceptance Scenarios**:

1. **Given** un usuario interno registrado con credenciales válidas y cuenta activa, **When** ingresa su usuario y contraseña, **Then** el sistema inicia su sesión, establece su contexto de identidad y lo redirige a su panel correspondiente.
2. **Given** un usuario con credenciales incorrectas, **When** intenta iniciar sesión, **Then** el sistema rechaza el acceso con un mensaje genérico de error de autenticación sin revelar la existencia del correo/usuario.
3. **Given** un usuario con sesión activa, **When** solicita cerrar sesión o transcurre el período máximo de inactividad, **Then** la sesión se invalida y se restringe el acceso a cualquier recurso protegido.

---

### User Story 2 - Aislamiento Multi-Tenant (Priority: P1)

Como administrador de la plataforma o agencia, quiero garantizar que todos los datos y operaciones pertenezcan estrictamente a la organización del usuario autenticado, de modo que jamás exista fuga de información ni acceso cruzado entre distintas agencias.

**Why this priority**: La Constitución y los requisitos de negocio exigen diseño tenant-aware desde el día cero para habilitar la evolución SaaS sin rediseño estructural.

**Independent Test**: Puede probarse creando dos organizaciones con datos independientes y verificando que un usuario de la Organización A no puede listar, leer, modificar ni eliminar registros de la Organización B bajo ninguna circunstancia.

**Acceptance Scenarios**:

1. **Given** dos organizaciones distintas A y B en el sistema, **When** un usuario perteneciente a la organización A consulta el sistema, **Then** solo recibe información, configuraciones y registros pertenecientes a la organización A.
2. **Given** un intento deliberado de consultar un recurso de la organización B utilizando un identificador directo desde la sesión de la organización A, **Then** el sistema rechaza la operación informando que el recurso no existe o denegando el acceso.

---

### User Story 3 - Control de Acceso Basado en Roles (RBAC) (Priority: P2)

Como administrador de la agencia, quiero asignar roles predefinidos (Administrador, Operador, Agente) a los usuarios internos para que cada miembro del equipo tenga acceso exclusivo a las funciones y datos que le corresponden por su puesto.

**Why this priority**: Protege la integridad de precios, cotizaciones, confirmaciones y configuraciones según el principio de menor privilegio.

**Independent Test**: Puede probarse asignando diferentes roles a cuentas de prueba y verificando que solo los roles autorizados pueden ejecutar acciones restringidas (ej. cambio de precios por administradores, verificación por operadores, emisión por agentes).

**Acceptance Scenarios**:

1. **Given** un usuario con rol Agente Comercial, **When** intenta acceder a la configuración global de precios o gestión de usuarios, **Then** el sistema bloquea la acción indicando falta de privilegios.
2. **Given** un usuario con rol Operador, **When** accede al módulo de disponibilidad, **Then** puede verificar y actualizar estados de pre-reservas con proveedores, pero no reasignar roles de usuarios.
3. **Given** un Administrador, **When** crea un nuevo usuario interno o modifica su rol, **Then** el sistema actualiza inmediatamente los permisos efectivos del usuario.

---

### User Story 4 - Registro Inmutable de Auditoría Base (Priority: P2)

Como administrador o responsable de auditoría, quiero que las operaciones críticas del sistema queden registradas de forma inmutable y cronológica para poder saber con exactitud quién realizó cada cambio relevante y cuándo.

**Why this priority**: El negocio turístico y la Constitución exigen trazabilidad completa de acciones sensibles para resolución de disputas y control operacional.

**Independent Test**: Puede probarse ejecutando acciones críticas (cambio de rol, inicio/cierre de sesión, intentos fallidos) y verificando que se genera un registro de auditoría con actor, fecha, hora, tipo de evento y resultado, el cual no puede ser alterado ni eliminado.

**Acceptance Scenarios**:

1. **Given** cualquier usuario interno que ejecuta una acción sensible (ej. cambio de rol, autenticación), **When** la acción se completa o es rechazada, **Then** el sistema genera un registro de auditoría con identificador del usuario, organización, marca temporal y detalle de la operación.
2. **Given** un registro de auditoría generado, **When** un usuario intenta modificarlo o borrarlo, **Then** el sistema impide la mutación garantizando la inmutabilidad del historial.

---

### User Story 5 - Registro y Onboarding de Nueva Agencia (Priority: P2)

Como representante de una agencia de turismo, quiero registrar mi agencia en la plataforma a través de un formulario público indicando el nombre comercial de la agencia y mis datos de acceso, para crear mi organización y comenzar a operar de forma inmediata como Administrador.

**Why this priority**: Habilita el crecimiento de la plataforma en autoservicio desde el inicio.

**Independent Test**: Puede probarse completando el formulario de registro con datos de una nueva agencia y verificando que se crea la organización (Tenant) y el usuario Administrador con sesión activa.

**Acceptance Scenarios**:

1. **Given** un usuario que completa el formulario público de registro con nombre de agencia, nombre completo, email y contraseña válidos, **When** envía el formulario, **Then** el sistema crea la nueva Organización/Tenant, crea el usuario con rol Administrador y le permite acceder inmediatamente a su panel.
2. **Given** un intento de registro con un correo electrónico corporativo ya registrado en el sistema, **When** se envía el formulario, **Then** el sistema impide la duplicidad e informa que el correo ya se encuentra en uso.

---

### Edge Cases

- ¿Qué ocurre si un usuario es desactivado mientras mantiene una sesión activa? El sistema debe invalidar de inmediato su token/sesión en su siguiente interacción y expulsarlo al login.
- ¿Cómo se manejan múltiples intentos fallidos consecutivos de inicio de sesión? El sistema debe aplicar un bloqueo temporal de intentos para mitigar ataques de fuerza bruta.
- ¿Qué ocurre si una solicitud carece de identificación de organización/tenant? La solicitud debe ser rechazada de inmediato como no autorizada.
- ¿Qué ocurre si un colaborador ingresa con su contraseña temporal y no la cambia? El sistema debe bloquear cualquier navegación a funciones del sistema y exigir el cambio obligatorio de contraseña en la primera pantalla.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE autenticar a usuarios internos mediante credenciales seguras y mantener sesiones con expiración tras 8 horas continuas de inactividad o un máximo absoluto de 24 horas de sesión.
- **FR-002**: El sistema DEBE soportar un modelo de rol único jerárquico por usuario: Administrador (acceso total a la organización con facultades heredadas de Operador y Agente), Operador (gestión de disponibilidad, pre-reservas y operaciones) y Agente Comercial (gestión de solicitudes, cotizaciones y clientes).
- **FR-003**: El sistema DEBE asociar cada usuario interno y cada entidad de negocio a una única Organización/Tenant activa.
- **FR-004**: El sistema DEBE denegar por defecto cualquier intento de acceso o mutación de datos fuera del tenant del usuario autenticado.
- **FR-005**: El sistema DEBE registrar en una bitácora inmutable de auditoría base los eventos de seguridad y control de acceso: inicios y cierres de sesión, intentos fallidos de autenticación, cambios de roles y creación/activación/desactivación de usuarios internos.
- **FR-006**: El sistema DEBE permitir a los Administradores crear colaboradores asignando una contraseña temporal inicial, forzando un flag de cambio obligatorio en el primer inicio de sesión.
- **FR-007**: El sistema DEBE manejar contraseñas mediante funciones criptográficas robustas y no almacenar contraseñas en texto plano bajo ninguna circunstancia.
- **FR-008**: El sistema DEBE proveer un formulario público de registro ("Registrar mi agencia") que cree de manera atómica la nueva Organización/Tenant y su usuario Administrador inicial.

### Key Entities

- **Organización / Tenant**: Representa a la entidad comercial (agencia de turismo). Posee identificador único, nombre comercial, estado y configuraciones operativas base.
- **Usuario Interno**: Colaborador de la agencia. Posee identificador, correo electrónico corporativo, nombre completo, estado (activo/inactivo), referencia a su organización y rol asignado (único y jerárquico).
- **Rol y Permiso**: Definición de perfiles de acceso jerárquicos (Admin > Operador / Agente). El rol agrupa un conjunto de capacidades operativas específicas.
- **Evento de Auditoría**: Registro inmutable de actividad relevante. Contiene marca de tiempo, identificador de organización, identificador de actor, tipo de evento, recurso afectado y resultado.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: El 100% de las rutas y operaciones de gestión exigen autenticación y autorización previa.
- **SC-002**: 0% de fuga de datos entre organizaciones en pruebas automatizadas de aislamiento multi-tenant.
- **SC-003**: El tiempo de autenticación y verificación de sesión no supera los 2 segundos en condiciones normales.
- **SC-004**: Los eventos de auditoría de seguridad se generan y persisten en menos de 500 ms tras completarse la acción monitoreada.

## Assumptions

- El MVP inicial opera para una agencia piloto principal, pero la arquitectura y modelos de datos implementan separación estricta por organización desde el inicio.
- Los usuarios internos acceden a través de un navegador web estándar con conectividad HTTPS segura.
- Los roles iniciales son fijos (Admin, Operador, Agente); la creación de roles dinámicos personalizados queda diferida para fases SaaS avanzadas.
