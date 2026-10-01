# Feature Specification: Navegación lateral, listados y CMS guiado con vista previa

**Feature Branch**: `010-admin-layout-navigation`

**Created**: 2026-09-30

**Status**: Draft

**Input**: User description: "Organizar el panel por menús. Crear un menú lateral izquierdo con dos secciones: Configuración (submenús de usuarios, roles y permisos) y, debajo, CMS (experiencias, alojamientos y todo lo relacionado: categorías, adicionales). Ordenar visualmente los formularios de creación. Que la pantalla inicial de cada menú sea su listado (por ejemplo, usuarios con sus roles). Cuidar especialmente el CMS, porque ahí se crean los productos que se despliegan en la web, e incluir una card de mini vista previa que se vaya llenando a medida que se completa el formulario. Crear un dashboard inicial, vacío por ahora, como destino después del login. Continúa el camino de la spec 009."

## Clarifications

### Session 2026-09-30

- Q: ¿Cómo se crea un producto con su ficha pública si la ficha y las imágenes necesitan que el producto ya exista? → A: Una sola pantalla con todas las secciones; el primer «Guardar borrador» crea el producto y desde ese momento se habilitan imágenes y precio. La vista previa funciona desde el primer dato escrito.
- Q: ¿La edición de un producto usa la misma pantalla que la creación? → A: Sí. La misma pantalla por secciones sirve para crear y editar, e incluye tarifas, estado comercial, categorías, adicionales elegibles, galería y opiniones de huéspedes (alojamientos); reemplaza a la pantalla de detalle actual.
- Q: ¿Dónde se gestionan los yates dentro del menú? → A: Dentro de «Experiencias», con una columna y un filtro por ubicación pública (catálogo o yates); la vista previa usa la card de yate cuando la ubicación es yates.
- Q: ¿Cuántos registros muestra cada página de un listado y cómo responde la búsqueda? → A: 20 por página; la búsqueda filtra mientras se escribe, tras una pausa breve; la búsqueda, los filtros y la página se conservan al volver y al compartir el enlace.
- Q: Cuando un agente abre un registro del CMS, ¿qué ve? → A: El mismo formulario por secciones en solo lectura, con la vista previa, sin acciones de guardar, publicar ni cambiar estado.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Moverse por el panel con un menú lateral (Priority: P1)

Como colaborador autenticado, quiero un menú lateral fijo a la izquierda con las secciones del panel agrupadas, para llegar a cualquier pantalla sin volver a una página intermedia y saber siempre en qué parte del panel estoy.

**Why this priority**: Hoy el panel no tiene estructura de navegación: el dashboard hace de menú improvisado y cada pantalla queda aislada. Sin el menú, ninguna de las demás mejoras se puede encontrar.

**Independent Test**: Puede probarse iniciando sesión con cada rol y comprobando que el menú lateral aparece en todas las pantallas autenticadas, muestra solo las secciones permitidas para ese rol, resalta la sección actual y lleva a cada destino con un clic.

**Acceptance Scenarios**:

1. **Given** un colaborador que acaba de iniciar sesión, **When** se carga el panel, **Then** ve el menú lateral con «Dashboard» arriba, luego «Configuración» y debajo «CMS», y el contenido de la pantalla a la derecha.
2. **Given** un administrador, **When** abre «Configuración», **Then** ve los submenús «Usuarios», «Roles y permisos» y «Auditoría».
3. **Given** un colaborador en cualquier pantalla, **When** abre «CMS», **Then** ve los submenús «Experiencias», «Alojamientos», «Paquetes» y «Ajustes del catálogo» (categorías, categorías públicas, adicionales y publicación del sitio).
4. **Given** un colaborador dentro de una pantalla de experiencias, **When** mira el menú, **Then** la sección «CMS» está desplegada y «Experiencias» aparece resaltada como la ubicación actual.
5. **Given** un operador o un agente, **When** ve el menú, **Then** no aparece la sección «Configuración».
6. **Given** un agente, **When** ve el menú, **Then** dentro de «CMS» solo aparecen los listados de consulta y no aparecen los ajustes del catálogo.
7. **Given** un colaborador, **When** usa la parte superior del panel, **Then** ve su nombre, su rol y su organización, y puede cerrar sesión desde ahí.

---

### User Story 2 - Llegar a un dashboard inicial después del login (Priority: P1)

Como colaborador, quiero que después de iniciar sesión me reciba un dashboard propio, aunque por ahora esté vacío, para tener un punto de partida estable al que luego se agregarán indicadores.

**Why this priority**: Es el destino del login y la raíz del menú. Sin él, el panel no tiene una pantalla inicial clara.

**Independent Test**: Puede probarse iniciando sesión y verificando que se llega al dashboard con el menú lateral, un saludo con el nombre del colaborador y un mensaje que indica que los indicadores estarán disponibles más adelante.

**Acceptance Scenarios**:

1. **Given** un colaborador con credenciales válidas y sin cambio de contraseña pendiente, **When** inicia sesión, **Then** llega al dashboard.
2. **Given** el dashboard, **When** se muestra, **Then** contiene un saludo con el nombre del colaborador y un estado vacío que explica que esta pantalla mostrará indicadores en una versión futura, sin enlaces de navegación duplicados del menú.
3. **Given** un colaborador en cualquier pantalla, **When** pulsa «Dashboard» en el menú, **Then** vuelve al dashboard.

---

### User Story 3 - Ver primero el listado al entrar a una sección (Priority: P1)

Como colaborador, quiero que al entrar a una opción del menú lo primero que vea sea el listado de esa sección, con la información clave y la opción de crear un registro nuevo, para encontrar rápido lo que busco antes de editar o crear.

**Why this priority**: El listado es la pantalla que más se usa. Hoy los listados existen, pero no siguen un formato común ni muestran lo necesario para decidir sin abrir cada registro.

**Independent Test**: Puede probarse entrando a «Usuarios», «Experiencias» y «Alojamientos» y comprobando que cada uno abre un listado con columnas relevantes, búsqueda, filtros, botón de creación (solo para quien puede crear) y un estado vacío comprensible.

**Acceptance Scenarios**:

1. **Given** un administrador, **When** entra a «Usuarios», **Then** ve el listado de colaboradores con nombre, correo, rol, estado de la cuenta (activo o inactivo, y si tiene cambio de contraseña pendiente) y último acceso, y el botón «Nuevo usuario».
2. **Given** el listado de usuarios, **When** el administrador escribe un nombre o correo o filtra por rol o estado, **Then** el listado muestra solo las coincidencias.
3. **Given** un colaborador, **When** entra a «Experiencias», **Then** ve las experiencias con foto principal en miniatura, nombre, categoría, estado del producto (borrador, activo, inactivo), estado de la ficha pública (sin ficha, borrador, publicada, agotada) y precio mostrado.
4. **Given** el listado de experiencias o alojamientos, **When** el colaborador busca por nombre o filtra por estado del producto, estado de la ficha pública o categoría, **Then** el listado muestra solo las coincidencias.
5. **Given** un listado sin registros, **When** se muestra, **Then** aparece un estado vacío que explica qué se guarda en esa sección y, si el colaborador puede crear, un botón para crear el primero.
6. **Given** un agente, **When** ve un listado del CMS, **Then** no aparece el botón de creación y puede abrir cada registro solo para consultarlo.
7. **Given** un listado con más de 20 registros, **When** se muestra, **Then** está paginado de a 20 y conserva la búsqueda y los filtros al cambiar de página, al volver desde un registro y al abrir el enlace compartido.
8. **Given** el listado de experiencias, **When** el colaborador filtra por ubicación pública «yates», **Then** ve solo las experiencias que se muestran en la página de yates.

---

### User Story 4 - Crear una experiencia o un alojamiento con una mini vista previa en vivo (Priority: P1)

Como gestor de producto, quiero que mientras completo el formulario de una experiencia o un alojamiento se vaya llenando una card de vista previa con los datos que escribo, para ver cómo quedará en la página pública antes de publicarla.

**Why this priority**: El CMS es la fuente de lo que el visitante ve en la web (spec 009). Un error en el título, la imagen o el precio llega directo al sitio, y la vista previa permite detectarlo mientras se escribe.

**Independent Test**: Puede probarse abriendo «Nueva experiencia», escribiendo un título, una descripción corta, eligiendo categoría y ubicación, subiendo una foto y un precio mostrado, y comprobando que la card se actualiza con cada cambio sin guardar, y que puede alternarse entre español e inglés.

**Acceptance Scenarios**:

1. **Given** el formulario de nueva experiencia vacío, **When** se abre, **Then** a un lado aparece una card de vista previa con marcadores neutros en lugar del título, la imagen y el precio.
2. **Given** el formulario en edición, **When** el gestor escribe el título, **Then** la card muestra ese título de inmediato, sin necesidad de guardar.
3. **Given** el formulario en edición, **When** el gestor completa descripción corta, categoría pública, ubicación, foto principal o precio mostrado, **Then** cada dato aparece en la card en el lugar que ocupa en la página pública.
4. **Given** una ficha con textos en español e inglés, **When** el gestor cambia el idioma de la vista previa, **Then** la card muestra los textos del idioma elegido y marca los que faltan en ese idioma.
5. **Given** un alojamiento, **When** el gestor completa su formulario, **Then** la card de vista previa sigue el formato de la página de hospedaje (tipo de inmueble, capacidad, ubicación, foto principal y precio por noche mostrado).
6. **Given** una ficha marcada como agotada, **When** se ve la card, **Then** muestra la marca de agotado como la vería el visitante.
7. **Given** una pantalla angosta, **When** el gestor completa el formulario, **Then** la vista previa sigue disponible, plegada debajo del formulario o en un botón que la muestra.

---

### User Story 5 - Completar formularios del CMS ordenados por secciones (Priority: P2)

Como gestor de producto, quiero que los formularios de creación y edición estén ordenados en secciones claras, con los datos obligatorios señalados y los errores junto a cada campo, para crear un producto completo sin saltar entre pantallas ni adivinar qué falta para publicarlo.

**Why this priority**: Hoy el producto se crea en un formulario y la ficha pública se completa después en otra parte del detalle. Unificarlo en un recorrido ordenado reduce errores, pero depende de que el menú y los listados ya existan.

**Independent Test**: Puede probarse creando una experiencia de principio a fin desde «Nueva experiencia», guardando como borrador a mitad de camino, retomándola desde el listado y verificando que la sección de publicación indica exactamente qué falta para publicar.

**Acceptance Scenarios**:

1. **Given** el formulario de experiencia o alojamiento, **When** se abre, **Then** está dividido en secciones en este orden: información básica, detalles operativos, categorías y adicionales, contenido público (español e inglés), imágenes, precio y publicación; los alojamientos agregan opiniones de huéspedes.
2. **Given** un formulario nuevo que aún no se ha guardado, **When** el gestor mira las secciones de imágenes y precio, **Then** aparecen deshabilitadas con el mensaje «Guarda el borrador para continuar», y se habilitan tras el primer guardado sin salir de la pantalla.
3. **Given** un producto existente, **When** el gestor lo abre desde el listado, **Then** ve la misma pantalla por secciones con sus datos cargados, incluidas tarifas, estado comercial y ficha pública.
4. **Given** cualquier sección, **When** el gestor deja vacío un dato obligatorio o escribe un valor inválido, **Then** el error aparece junto al campo con un mensaje que explica cómo corregirlo, y la sección se marca como incompleta.
5. **Given** un formulario a medio completar, **When** el gestor guarda, **Then** el producto queda como borrador con todo lo escrito y puede retomarse desde el listado.
6. **Given** un formulario con cambios sin guardar, **When** el gestor intenta salir de la pantalla, **Then** el sistema le advierte que perderá los cambios y le permite quedarse.
7. **Given** la sección de publicación, **When** la ficha no cumple las condiciones para publicarse (producto activo, tarifa vigente, foto principal, textos obligatorios en ambos idiomas), **Then** el sistema lista las condiciones pendientes y no ofrece publicar hasta cumplirlas.
8. **Given** un agente que abre un producto, **When** se muestra la pantalla, **Then** ve las mismas secciones y la vista previa en solo lectura, sin acciones de guardar, publicar ni cambiar estado.
9. **Given** un formulario de categoría, categoría pública o adicional, **When** se abre, **Then** sigue la misma distribución por secciones, la misma señalización de obligatorios y la misma ubicación de las acciones de guardar y cancelar.

---

### User Story 6 - Consultar roles y permisos (Priority: P3)

Como administrador, quiero ver en un solo lugar qué puede hacer cada rol y cuántos colaboradores tienen cada uno, para asignar roles con criterio sin depender de la documentación.

**Why this priority**: Los roles ya existen y se asignan desde el detalle del usuario. La pantalla aporta claridad, pero el panel funciona sin ella.

**Independent Test**: Puede probarse entrando a «Configuración > Roles y permisos» como administrador y verificando que aparecen los tres roles con su descripción, su cantidad de colaboradores y una matriz de lo que cada uno puede hacer por sección.

**Acceptance Scenarios**:

1. **Given** un administrador, **When** entra a «Roles y permisos», **Then** ve los roles administrador, operador y agente, cada uno con una descripción breve y el número de colaboradores activos que lo tienen.
2. **Given** la pantalla de roles, **When** el administrador la consulta, **Then** ve una matriz que indica, por sección del panel, si cada rol puede consultar, crear y editar, o administrar.
3. **Given** un rol en la pantalla, **When** el administrador lo selecciona, **Then** llega al listado de usuarios filtrado por ese rol.

---

### Edge Cases

- Un colaborador escribe directamente la dirección de una sección que su rol no permite: el sistema no muestra el contenido, lo lleva a una pantalla permitida y explica que no tiene permiso.
- Al colaborador le cambian el rol mientras tiene la sesión abierta: el menú refleja el rol nuevo a más tardar en la siguiente renovación de sesión y las acciones ya no permitidas son rechazadas.
- Un colaborador con cambio de contraseña obligatorio pendiente: ve solo la pantalla de cambio de contraseña, sin menú navegable, hasta completarlo.
- Las pantallas de inicio de sesión y registro no muestran el menú lateral.
- Direcciones guardadas o compartidas de pantallas existentes (catálogo, usuarios, auditoría) siguen llevando a la pantalla equivalente en la nueva organización.
- El título o la descripción son muy largos: la card de vista previa los recorta como lo haría la página pública y el formulario indica el largo recomendado.
- La foto principal todavía no se ha subido, se está subiendo o fue rechazada: la card muestra un marcador, un indicador de carga o mantiene la imagen anterior, respectivamente.
- Falta el texto en inglés: la vista previa en inglés lo marca como pendiente en lugar de mostrar el texto en español.
- Se pierde la conexión al guardar un formulario: lo escrito no se descarta y el sistema explica que no se pudo guardar.
- Pantallas angostas: el menú lateral se pliega y se abre con un botón; en pantallas de escritorio puede contraerse a solo íconos.
- Una búsqueda o un filtro no devuelve resultados: el listado lo dice y ofrece limpiar los filtros.

## Requirements *(mandatory)*

### Functional Requirements

**Estructura y navegación**

- **FR-001**: Toda pantalla autenticada MUST mostrarse dentro de una estructura común con un menú lateral a la izquierda, una barra superior y el área de contenido.
- **FR-002**: El menú lateral MUST mostrar, en este orden: «Dashboard»; «Configuración» con los submenús «Usuarios», «Roles y permisos» y «Auditoría»; y «CMS» con los submenús «Experiencias», «Alojamientos», «Paquetes» y «Ajustes del catálogo».
- **FR-003**: «Ajustes del catálogo» MUST agrupar categorías, categorías públicas, adicionales y publicación del sitio, cada uno con su propio listado.
- **FR-004**: El menú MUST mostrar solo las secciones y submenús que el rol del colaborador puede usar: el administrador ve todo; el operador ve «Dashboard» y «CMS» completo; el agente ve «Dashboard» y los listados de «Experiencias», «Alojamientos» y «Paquetes» en modo consulta. «Publicación del sitio» MUST verse solo para administradores.
- **FR-005**: El menú MUST resaltar la sección y el submenú en que se encuentra el colaborador y mantener desplegado el grupo que los contiene.
- **FR-006**: La barra superior MUST mostrar el nombre, el rol y la organización del colaborador y la acción de cerrar sesión.
- **FR-007**: El menú MUST plegarse en pantallas angostas y abrirse con un botón, y MUST poder contraerse a íconos en escritorio, recordando esa preferencia en el mismo dispositivo.
- **FR-008**: El acceso directo por dirección a una sección no permitida MUST rechazarse con un mensaje de falta de permiso; ocultar una opción del menú no sustituye la verificación de permisos.
- **FR-009**: Las direcciones de pantallas existentes MUST seguir llevando a la pantalla equivalente en la nueva organización.
- **FR-010**: Las pantallas de inicio de sesión, registro y cambio de contraseña obligatorio MUST mostrarse sin el menú navegable.

**Dashboard**

- **FR-011**: Después de un inicio de sesión exitoso sin cambio de contraseña pendiente, el sistema MUST llevar al colaborador al dashboard.
- **FR-012**: El dashboard MUST mostrar un saludo con el nombre del colaborador y un estado vacío que indique que los indicadores llegarán más adelante; MUST NOT duplicar los enlaces del menú.

**Listados**

- **FR-013**: Cada submenú MUST abrir primero el listado de su sección.
- **FR-014**: El listado de usuarios MUST mostrar nombre, correo, rol, estado de la cuenta (activo o inactivo, con indicación de cambio de contraseña pendiente) y último acceso, y permitir buscar por nombre o correo y filtrar por rol y estado.
- **FR-015**: Los listados de experiencias, alojamientos y paquetes MUST mostrar foto principal en miniatura, nombre, categoría, estado del producto, estado de la ficha pública y precio mostrado, y permitir buscar por nombre y filtrar por estado del producto, estado de la ficha pública y categoría.
- **FR-016**: Todos los listados MUST compartir el mismo formato: título de la sección, botón de creación arriba a la derecha (solo para quien puede crear), barra de búsqueda y filtros, tabla paginada, estado vacío y estado sin resultados.
- **FR-017**: Los listados MUST mostrar 20 registros por página, filtrar mientras se escribe tras una pausa breve, y conservar la búsqueda, los filtros y la página al volver desde un registro y al compartir el enlace.
- **FR-017a**: El listado de experiencias MUST incluir los yates, con una columna y un filtro por ubicación pública (catálogo o yates).

**Formularios del CMS**

- **FR-018**: Los formularios de experiencia y alojamiento MUST organizarse en secciones, en este orden: información básica, detalles operativos, categorías y adicionales, contenido público (español e inglés), imágenes, precio (tarifas) y publicación (estado comercial y ficha pública); los alojamientos MUST agregar una sección de opiniones de huéspedes.
- **FR-018a**: La misma pantalla por secciones MUST servir para crear y para editar, y MUST reemplazar a la pantalla de detalle de producto actual sin perder ninguna de sus funciones.
- **FR-019**: Los formularios MUST señalar los datos obligatorios, mostrar los errores junto al campo correspondiente e indicar qué secciones están incompletas.
- **FR-020**: El gestor MUST poder crear el producto y completar su ficha pública en un mismo recorrido, guardando como borrador en cualquier momento y retomándolo desde el listado. El primer guardado crea el producto en borrador; hasta entonces, las secciones de imágenes y precio MUST mostrarse deshabilitadas con el mensaje «Guarda el borrador para continuar», y MUST habilitarse tras ese guardado sin salir de la pantalla.
- **FR-021**: La sección de publicación MUST listar las condiciones pendientes para publicar, de acuerdo con las reglas de publicación vigentes (spec 009), y MUST NOT ofrecer publicar mientras alguna esté pendiente.
- **FR-022**: El sistema MUST advertir antes de abandonar un formulario con cambios sin guardar.
- **FR-023**: Los formularios de paquetes, categorías, categorías públicas y adicionales MUST seguir la misma distribución, señalización de obligatorios y ubicación de acciones que los de experiencia y alojamiento.
- **FR-024**: Para el agente, los formularios del CMS MUST mostrarse en solo lectura con la vista previa visible y sin acciones de guardar, publicar ni cambiar estado.

**Vista previa**

- **FR-025**: Los formularios de experiencia, alojamiento y paquete MUST mostrar una card de vista previa junto al formulario que refleje los datos escritos sin necesidad de guardar.
- **FR-026**: La card MUST mostrar, en la disposición que usa la página pública: foto principal, título, descripción corta, categoría pública, ubicación, precio mostrado y la marca de agotado cuando aplique. Para alojamientos MUST mostrar además tipo de inmueble y capacidad, siguiendo la card de la página de hospedaje; para experiencias con ubicación pública «yates» MUST seguir la card de la página de yates, donde el precio es opcional.
- **FR-027**: La card MUST mostrar marcadores neutros para los datos aún vacíos y MUST marcar los textos que faltan en el idioma seleccionado en lugar de sustituirlos por los del otro idioma.
- **FR-028**: El gestor MUST poder alternar la vista previa entre español e inglés.
- **FR-029**: La card MUST recortar los textos largos igual que la página pública.

**Roles y permisos**

- **FR-030**: La pantalla «Roles y permisos» MUST mostrar los roles existentes (administrador, operador, agente) con una descripción, el número de colaboradores activos con cada rol y una matriz de lo que cada rol puede hacer por sección.
- **FR-031**: Seleccionar un rol MUST llevar al listado de usuarios filtrado por ese rol.
- **FR-032**: La pantalla de roles MUST ser de solo consulta; crear roles nuevos o cambiar los permisos de un rol queda fuera de alcance.

### Key Entities

Esta mejora no introduce conceptos de negocio nuevos; reorganiza cómo se presentan los existentes.

- **Sección del panel**: Agrupación de navegación (Dashboard, Configuración, CMS) con sus submenús y el rol mínimo para verla. Es una regla de presentación, no un dato del negocio.
- **Colaborador, Rol**: Ya definidos en Identity & Access (spec 001). Se muestran en el listado de usuarios y en la pantalla de roles.
- **Producto (experiencia, alojamiento, paquete), Categoría, Adicional**: Ya definidos en el catálogo (spec 002).
- **Ficha pública, Imagen pública, Categoría pública**: Ya definidas en la spec 009. La card de vista previa representa una ficha pública sin guardar.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Desde cualquier pantalla autenticada, un colaborador llega a cualquier otra sección permitida en 2 clics o menos.
- **SC-002**: El 100% de las pantallas autenticadas, salvo el cambio de contraseña obligatorio, muestra el menú lateral con la ubicación actual resaltada.
- **SC-003**: Ningún rol ve en el menú una sección que no puede usar, y el 100% de los accesos directos a secciones no permitidas son rechazados.
- **SC-004**: Un gestor de producto crea una experiencia completa con ficha pública lista para publicar en menos de 10 minutos, sin salir del formulario.
- **SC-005**: Cada cambio en el formulario se refleja en la card de vista previa de forma inmediata para el usuario (sin pausa perceptible ni acción de guardar).
- **SC-006**: En una revisión con gestores, al menos 9 de cada 10 confirman que la vista previa coincide con lo que después ven en la página pública (mismos datos, mismo orden, mismos recortes).
- **SC-007**: Un administrador encuentra un colaborador por nombre o correo en menos de 15 segundos.
- **SC-008**: Ningún gestor pierde lo escrito en un formulario por salir de la pantalla sin la advertencia correspondiente.

## Assumptions

- Esta mejora continúa la spec 009: las reglas de ficha pública, imágenes, publicación, categorías públicas y paso del sitio al panel no cambian; solo cambia cómo se presentan y en qué orden se completan.
- Los roles siguen siendo los tres existentes (administrador, operador, agente) con su jerarquía actual. «Roles y permisos» es una pantalla de consulta; la asignación de rol sigue haciéndose desde el detalle del usuario.
- «Auditoría» se ubica dentro de «Configuración» porque hoy solo la usa el administrador y no tiene otro lugar natural en el menú.
- El usuario pidió tres submenús en el CMS (experiencias, alojamientos y lo relacionado). Los paquetes se muestran como submenú propio porque también son productos publicables en la página; categorías, categorías públicas, adicionales y publicación del sitio se agrupan en «Ajustes del catálogo».
- La card de vista previa es una aproximación fiel de la card pública (datos, orden y recortes), no una réplica exacta píxel a píxel del sitio.
- Los yates se crean como experiencias con ubicación de yates (spec 009) y se gestionan desde «Experiencias»; su vista previa usa la card de la página de yates.
- El dashboard queda vacío en esta versión; los indicadores serán una mejora posterior (spec 008).
- Las pantallas existentes de catálogo, usuarios y auditoría se reubican dentro de la nueva estructura sin perder funcionalidad.
- El panel se usa principalmente en escritorio; en pantallas angostas debe ser usable, pero no se optimiza para uso intensivo en móvil.
- La interfaz sigue en español.
