# Feature Specification: Base multiagencia del contenido público

**Feature Branch**: `016-multiagency-public-cms`

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Base multi-agencia del contenido público (CMS): categorías, tipos de alojamiento, amenidades, clave pública y perfil público configurables por agencia, con transición compatible para CTT."

## Clarifications

### Session 2026-11-13

- Q: ¿Durante cuánto tiempo debe seguir funcionando la clave pública anterior después de regenerar una nueva? → A: 7 días.

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.

  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.
  Think of each story as a standalone slice of functionality that can be:
  - Developed independently
  - Tested independently
  - Deployed independently
  - Demonstrated to users independently
-->

### User Story 1 - Configurar la clasificación pública (Priority: P1)

Como Administrador u Operador de una agencia, quiero administrar las categorías, tipos de alojamiento y amenidades de mi agencia, para que el catálogo público refleje su oferta sin depender de categorías fijas de otra agencia.

**Why this priority**: Es la base de la autonomía de cada agencia y elimina el acoplamiento del contenido público a CTT.

**Independent Test**: Puede probarse creando una categoría, un tipo y una amenidad bilingües en una agencia, asignándolos a fichas, desactivándolos y verificando que otra agencia no los vea ni pueda modificarlos.

**Acceptance Scenarios**:

1. **Given** una agencia nueva, **When** el Administrador abre la configuración pública, **Then** encuentra categorías, tipos y amenidades de ejemplo que puede renombrar, desactivar o reemplazar.
2. **Given** un gestor autorizado, **When** crea una categoría, tipo o amenidad con identificador estable y nombres en español e inglés, **Then** puede usarlo en nuevas fichas de su agencia.
3. **Given** un tipo o amenidad usado por una ficha publicada, **When** el gestor intenta borrarlo, **Then** el sistema solo permite desactivarlo y la ficha continúa mostrando el valor hasta ser editada.

---

### User Story 2 - Gestionar la clave pública (Priority: P1)

Como Administrador de una agencia, quiero obtener, regenerar y revocar la clave pública de mi agencia, para conectar una vitrina externa sin entregar acceso al panel ni a datos internos.

**Why this priority**: La clave es el límite de acceso entre el contenido publicado de una agencia y cualquier página o vitrina externa.

**Independent Test**: Puede probarse leyendo el catálogo con una clave vigente, intentando usarla después de revocarla o regenerarla, y confirmando que las respuestas inválidas son indistinguibles y no permiten operaciones internas.

**Acceptance Scenarios**:

1. **Given** una agencia con una clave vigente, **When** su vitrina consulta contenido publicado y envía una solicitud de viajero, **Then** solo recibe los datos públicos permitidos y la solicitud queda asociada a esa agencia.
2. **Given** una clave regenerada, **When** la agencia usa la clave anterior durante el periodo de transición informado, **Then** puede continuar funcionando hasta su vencimiento y después recibe una respuesta genérica de acceso no válido.
3. **Given** una clave revocada o inexistente, **When** una vitrina consulta, **Then** recibe la misma respuesta genérica sin revelar si la agencia existe.

---

### User Story 3 - Administrar el perfil público (Priority: P1)

Como Administrador u Operador, quiero completar el perfil público de mi agencia, para que la vitrina pueda presentarla con su identidad, canales de contacto, idiomas y moneda.

**Why this priority**: Sin perfil, una vitrina puede mostrar productos pero no la identidad ni los canales comerciales de la agencia.

**Independent Test**: Puede probarse guardando el perfil con datos válidos, leyéndolo desde una vitrina autorizada y verificando que no incluye usuarios, notas internas ni datos de clientes.

**Acceptance Scenarios**:

1. **Given** un gestor autorizado, **When** completa nombre comercial, logo, color, correo, teléfono, WhatsApp, redes, idiomas y moneda, **Then** el perfil queda guardado y la vitrina muestra esos datos.
2. **Given** un Agente, **When** intenta editar el perfil público, **Then** la operación es rechazada y el perfil no cambia.
3. **Given** un cambio de perfil, **When** un Administrador revisa el historial, **Then** puede identificar quién lo hizo y cuándo.

### User Story 4 - Mantener la compatibilidad de CTT (Priority: P1)

Como responsable de CTT, quiero conservar sus categorías e identificadores actuales y usar temporalmente su identificador de organización, para migrar a la clave pública sin romper filtros, direcciones ni fichas existentes.

**Why this priority**: La transición debe proteger el contenido y las direcciones que CTT ya usa mientras la plataforma deja de depender de una configuración específica.

**Independent Test**: Puede probarse consultando una ficha CTT con cada identificador actual, usando el identificador de organización durante la transición y verificando que, al finalizarla, solo se acepta la clave pública.

**Acceptance Scenarios**:

1. **Given** CTT con sus ocho categorías actuales, **When** se habilita esta funcionalidad, **Then** conserva los mismos identificadores, filtros y direcciones públicas.
2. **Given** CTT durante la transición, **When** su página usa el identificador de organización, **Then** puede leer lo publicado y enviar solicitudes como antes.
3. **Given** el fin de la transición, **When** una consulta usa solo el identificador de organización, **Then** es rechazada sin afectar fichas ni imágenes publicadas.

### User Story 5 - Publicar directamente o migrar contenido (Priority: P2)

Como responsable de una agencia, quiero elegir si migro contenido desde un sitio existente o publico fichas nuevas directamente, para no imponer a las agencias nuevas un paso de copia que no necesitan.

**Why this priority**: El flujo de incorporación debe servir tanto a agencias con sitio propio como a agencias que comienzan a publicar en la plataforma.

**Independent Test**: Puede probarse marcando una agencia como migrada y verificando la regla de copia completa, y creando otra agencia sin fuente previa para publicar una ficha sin bloqueo de migración.

**Acceptance Scenarios**:

1. **Given** una agencia migrada desde un sitio propio, **When** falta copiar una ficha que su página ya muestra, **Then** no puede completar el cambio de fuente y la página actual sigue operativa.
2. **Given** una agencia nueva sin sitio previo, **When** publica una ficha válida, **Then** no se exige una copia previa de contenido externo.

---

[Add more user stories as needed, each with an assigned priority]

### Edge Cases

- Un identificador de categoría, tipo o amenidad duplicado dentro de una agencia se rechaza; el mismo identificador puede existir en otra agencia sin mezclar datos.
- No se permite guardar nombres bilingües vacíos, identificadores inválidos o valores que colisionen con otro elemento activo de la misma agencia.
- Desactivar una categoría asignada a una ficha publicada no cambia la ficha existente, pero impide asignarla a nuevas fichas y exige una categoría activa para futuras publicaciones o ediciones.
- Intentar borrar un elemento usado por una ficha publicada no lo elimina; si no está en uso, puede eliminarse según las reglas de gestión de la agencia.
- Regenerar una clave mantiene la anterior válida durante 7 días; después la invalida. Revocar la clave la invalida de inmediato.
- Una clave nunca permite consultar borradores, tarifas internas, usuarios, notas, clientes ni datos de otra agencia.
- Si una agencia no configura logo, redes o WhatsApp, la vitrina omite esos datos sin mostrar campos vacíos.
- El perfil debe rechazar una moneda o idioma no soportado por la configuración pública de la agencia.
- El identificador de organización solo funciona para CTT durante la transición; no se convierte en mecanismo público general para otras agencias.
- El cambio de fuente no altera identificadores públicos, imágenes ni fichas ya publicadas.

## Requirements *(mandatory)*

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right functional requirements.
-->

### Functional Requirements

- **FR-001**: El sistema DEBE mantener categorías públicas separadas por agencia, con identificador estable, nombre en español, nombre en inglés y estado activo o inactivo.
- **FR-002**: Una agencia nueva DEBE iniciar con un conjunto general de categorías de ejemplo que el Administrador u Operador pueda renombrar, desactivar o reemplazar sin afectar a otras agencias.
- **FR-003**: Operador y Administrador DEBEN poder crear, editar, activar y desactivar categorías de su agencia; Agente NO DEBE poder modificarlas.
- **FR-004**: El sistema DEBE conservar para CTT sus ocho categorías actuales con los mismos identificadores y nombres funcionales que usan sus filtros y direcciones.
- **FR-005**: El sistema DEBE mantener tipos de alojamiento y amenidades separados por agencia, cada uno con identificador estable, nombres en español e inglés y estado activo o inactivo.
- **FR-006**: Toda agencia nueva DEBE iniciar con una lista general de tipos y amenidades configurables, que incluya como mínimo casa, apartamento, finca, habitación, hotel, wifi, piscina, aire acondicionado, cocina, parqueadero y vista al mar.
- **FR-007**: Operador y Administrador DEBEN poder crear, editar, activar y desactivar tipos y amenidades de su agencia; Agente NO DEBE poder modificarlos.
- **FR-008**: Un tipo o amenidad utilizado por una ficha publicada NO DEBE poder borrarse; DEBE poder desactivarse y la ficha DEBE conservar el valor visible hasta que sea editada.
- **FR-009**: El sistema DEBE rechazar identificadores duplicados dentro de una agencia y DEBE permitir el mismo identificador en agencias distintas sin compartir registros.
- **FR-010**: Cada agencia DEBE tener una clave pública independiente para leer su catálogo publicado y enviar solicitudes de viajeros asociadas a esa agencia.
- **FR-011**: La clave pública NO DEBE permitir acceso al panel, usuarios, datos internos, datos de clientes, borradores ni tarifas internas.
- **FR-012**: Solo el Administrador DEBE poder ver, generar, regenerar y revocar la clave pública; Operador y Agente NO DEBEN poder realizar esas acciones.
- **FR-013**: El sistema DEBE registrar quién creó, regeneró o revocó una clave pública y cuándo ocurrió cada acción.
- **FR-014**: Al regenerar una clave, el sistema DEBE informar que la anterior seguirá funcionando durante 7 días y debe dejar de funcionar al finalizar ese periodo.
- **FR-015**: Una clave revocada, inexistente o vencida DEBE producir la misma respuesta genérica, sin revelar si la agencia existe ni cuál fue la causa.
- **FR-016**: Durante el periodo de transición, el sitio de CTT DEBE poder usar su identificador de organización para consultar contenido publicado y enviar solicitudes.
- **FR-017**: El identificador de organización DEBE dejar de aceptarse para CTT al finalizar el periodo de transición; las consultas con clave pública DEBEN continuar funcionando.
- **FR-018**: El perfil público DEBE permitir nombre comercial, logo, color principal, correo, teléfono, WhatsApp, redes sociales, idiomas ofrecidos y moneda de exhibición.
- **FR-019**: El perfil DEBE permitir español, inglés o ambos como idiomas ofrecidos, y DEBE permitir seleccionar la moneda configurada para los precios públicos.
- **FR-020**: Operador y Administrador DEBEN poder crear y actualizar el perfil público de su agencia; Agente NO DEBE poder modificarlo.
- **FR-021**: El sistema DEBE registrar quién creó o modificó el perfil público y cuándo ocurrió cada cambio.
- **FR-022**: La lectura pública DEBE devolver el perfil público junto con el catálogo publicado de la agencia identificada por una clave válida.
- **FR-023**: La respuesta pública NO DEBE incluir usuarios, notas internas, costos, tarifas internas, datos de clientes, prestadores ni información de otra agencia.
- **FR-024**: Todo cambio de categorías, tipos, amenidades, clave y perfil DEBE respetar el aislamiento de agencia para lectura y modificación.
- **FR-025**: Las fichas publicadas, identificadores públicos e imágenes existentes DEBEN conservarse sin cambios por esta funcionalidad.
- **FR-026**: Una agencia con sitio propio DEBE poder marcarse como migrada y, antes de cambiar la fuente, DEBE contar con una ficha publicada por cada contenido que su sitio vigente muestra.
- **FR-027**: Si falta contenido por copiar en una agencia migrada, el cambio de fuente DEBE rechazarse y el sitio vigente DEBE continuar mostrando su contenido.
- **FR-028**: Una agencia nueva sin contenido externo previo DEBE poder publicar fichas directamente sin cumplir una regla de copia.
- **FR-029**: El sistema DEBE registrar los cambios de configuración pública con actor, agencia, acción y fecha, de forma consultable por Administradores autorizados.

### Key Entities *(include if feature involves data)*

- **Agencia**: Unidad propietaria de categorías, tipos, amenidades, perfil, clave y fichas públicas; define el límite de aislamiento.
- **Categoría pública**: Clasificación bilingüe configurable por agencia para filtrar fichas publicadas.
- **Tipo de alojamiento**: Valor bilingüe configurable por agencia para describir alojamientos.
- **Amenidad**: Característica bilingüe configurable por agencia que puede asociarse a alojamientos.
- **Clave pública**: Credencial limitada que identifica una agencia para lectura pública y envío de solicitudes; tiene estado, creación, expiración opcional y revocación.
- **Perfil público de agencia**: Información comercial y de identidad que una vitrina puede mostrar junto con el catálogo.
- **Configuración de fuente pública**: Estado que indica si una agencia migra contenido existente y qué condiciones debe cumplir antes de cambiar de fuente.
- **Registro de auditoría pública**: Evidencia del actor, agencia, acción y momento de cambios sobre clave y perfil, y de la gestión de taxonomías.

## Success Criteria *(mandatory)*

<!--
  ACTION REQUIRED: Define measurable success criteria.
  These must be technology-agnostic and measurable.
-->

### Measurable Outcomes

- **SC-001**: En una prueba con 10 agencias, cada agencia puede crear y usar una categoría, tipo y amenidad propios sin que aparezcan registros de otra agencia en el 100% de los casos.
- **SC-002**: En una prueba de 20 operaciones de permisos, el 100% de las acciones de Agente sobre categorías, tipos, amenidades, perfil y clave son rechazadas, mientras que las acciones permitidas de Operador y Administrador se completan correctamente.
- **SC-003**: En una prueba con 30 claves válidas, vencidas, revocadas e inexistentes, el 100% de las claves inválidas recibe una respuesta genérica y ninguna obtiene datos privados o de otra agencia.
- **SC-004**: Un Administrador puede generar o regenerar una clave y encontrar su periodo de transición en menos de 2 minutos, sin asistencia externa, en al menos 9 de 10 intentos.
- **SC-005**: En una comparación de CTT antes y después de activar la funcionalidad, el 100% de sus categorías, identificadores públicos, imágenes y fichas publicadas permanece igual.
- **SC-006**: Una agencia migrada bloquea el cambio de fuente en el 100% de las pruebas con contenido faltante; una agencia nueva publica directamente en el 100% de las pruebas válidas.
- **SC-007**: En una revisión de 20 perfiles públicos, el 100% muestra únicamente los campos configurados por la agencia y ningún usuario, cliente, nota interna o tarifa de costo.
- **SC-008**: En una prueba de auditoría con 30 cambios de clave y perfil, el 100% queda asociado a la agencia, actor y momento correctos.

## Assumptions

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right assumptions based on reasonable defaults
  chosen when the feature description did not specify certain details.
-->

- La agencia y el usuario deben estar autenticados para gestionar configuración; la vitrina y el envío de solicitudes usan únicamente la clave pública.
- El catálogo publicado existente, sus identificadores y sus imágenes ya son válidos y no se migran ni renombran como parte de esta especificación.
- El conjunto inicial de ejemplo es editable y sirve como punto de partida; no se impone como vocabulario común entre agencias.
- La moneda pública se selecciona de las monedas que la plataforma ya soporta; esta funcionalidad no define nuevas monedas ni conversión de precios.
- El periodo de transición de una clave regenerada es fijo, explícito y visible para el Administrador: 7 días.
- El identificador de organización durante la transición es una excepción exclusiva de CTT y no se ofrece como mecanismo de acceso público para nuevas agencias.
- La auditoría puede consultarse por Administradores autorizados y no expone secretos de las claves.
- El sitio público alojado por la plataforma, el estado del caso para viajeros y las notificaciones internas permanecen fuera de alcance.
