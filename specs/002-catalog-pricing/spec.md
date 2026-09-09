# Feature Specification: 002-catalog-pricing

**Feature Branch**: `002-catalog-pricing`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Gestión de catálogo turístico (experiencias, alojamientos, paquetes, add-ons) y esquema de precios derivado de mainspec.md (Capítulos 4, 5, 6, 7, 8, 18)."

## Clarifications

### Session 2026-09-09

- Q: ¿A qué roles del sistema existente (Admin/Operador/Agente de 001) corresponden el "gestor de producto" y el "administrador comercial"? → A: Catálogo (productos, add-ons, paquetes, categorías) gestionable por Operador y Administrador; definición de esquemas de precios por Operador y Administrador; sobreescritura manual de precios restringida a Administrador; Agente solo lectura del catálogo.
- Q: ¿El precio de un Paquete Predefinido es explícito o calculado desde sus componentes? → A: Explícito — el paquete tiene su propio esquema de precios independiente de los precios de los componentes (la suma automática queda diferida).
- Q: ¿La moneda es única por organización o se define por esquema de precios? → A: Cada esquema de precios almacena su propia moneda, heredando por defecto la moneda configurada en la organización si no se especifica (multi-moneda futuro sin rediseño).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Gestión de Experiencias y Alojamientos (Priority: P1)

Como gestor de producto de la agencia, quiero dar de alta, editar y categorizar experiencias turísticas y alojamientos con sus descripciones, ubicaciones, duraciones y capacidades, para que formen la oferta comercial de la agencia.

**Why this priority**: Las experiencias y alojamientos son las dos unidades base del inventario turístico que comercializa la empresa.

**Independent Test**: Puede probarse creando una experiencia y un alojamiento con todos sus atributos requeridos, editando su información, activando/desactivando el ítem y listándolos en el catálogo interno.

**Acceptance Scenarios**:

1. **Given** un gestor de producto autenticado, **When** registra una nueva experiencia con nombre, descripción, duración, categoría, capacidad de participantes y estado activo, **Then** el sistema la guarda y la hace disponible en el catálogo comercial.
2. **Given** un gestor de producto, **When** registra un alojamiento especificando tipo, ubicación, capacidad máxima de huéspedes y reglas de estancia, **Then** el sistema lo guarda como ítem de catálogo independiente.
3. **Given** un producto existente, **When** se modifica su estado a "inactivo", **Then** el producto deja de estar disponible para nuevas cotizaciones y solicitudes públicas sin alterar cotizaciones o reservas pasadas.

---

### User Story 2 - Configuración de Add-ons y Personalización de Productos (Priority: P1)

Como gestor de producto, quiero definir servicios adicionales (add-ons o complementos) y asociar cuáles pueden agregarse opcionalmente a cada experiencia, alojamiento o paquete, para permitir que los clientes personalicen su viaje.

**Why this priority**: El modelo de negocio se basa en planes a la medida y servicios complementarios (transporte, alimentación, guías especializados, seguros).

**Independent Test**: Puede probarse creando add-ons independientes, vinculándolos como opciones seleccionables para una experiencia o alojamiento, y verificando que son consultables con sus reglas de aplicabilidad.

**Acceptance Scenarios**:

1. **Given** un add-on registrado (ej. "Almuerzo típico" o "Transporte privado"), **When** el gestor lo vincula a una experiencia como complemento elegible, **Then** el sistema permite que dicho complemento sea seleccionado al presupuestar la experiencia.
2. **Given** un add-on con restricción de capacidad o requerimiento obligatorio, **When** se evalúa la selección, **Then** el sistema valida las reglas de compatibilidad antes de agregarlo al plan.

---

### User Story 3 - Composición de Paquetes Predefinidos (Priority: P2)

Como gestor de producto, quiero combinar múltiples experiencias, alojamientos y add-ons en un "Paquete Predefinido" con un itinerario estructurado y un precio de paquete, para ofrecer soluciones completas y atractivas a los clientes.

**Why this priority**: Los paquetes representan productos de alto valor que simplifican la decisión de compra del cliente.

**Independent Test**: Puede probarse creando un paquete compuesto por una experiencia y dos noches de alojamiento, verificando que los ítems individuales quedan agrupados y su disponibilidad o precio responde a las reglas del paquete.

**Acceptance Scenarios**:

1. **Given** experiencias y alojamientos activos en el catálogo, **When** el gestor crea un paquete predefinido seleccionando dichos ítems y fijando días/noches de itinerario, **Then** el paquete queda disponible como producto único en el catálogo.
2. **Given** un paquete predefinido, **When** uno de sus ítems componentes es desactivado globalmente en el catálogo, **Then** el sistema advierte al gestor de producto sobre la inconsistencia del paquete.

---

### User Story 4 - Definición y Estructuración de Precios (Priority: P2)

Como administrador comercial, quiero definir precios base, precios por temporada, precios por persona o por unidad, y habilitar la capacidad de registrar sobreescrituras manuales autorizadas, para mantener márgenes comerciales claros y adaptados al mercado.

**Why this priority**: El cobro adecuado y la rentabilidad de la agencia dependen de reglas de tarificación claras y predecibles.

**Independent Test**: Puede probarse configurando precios para temporada alta/baja y tarifas por adulto/niño, verificando que el cálculo del precio base corresponde exactamente a las reglas parametrizadas.

**Acceptance Scenarios**:

1. **Given** una experiencia o alojamiento, **When** el administrador configura una tarifa base y una tarifa de temporada con rango de fechas, **Then** el sistema aplica automáticamente la tarifa correspondiente a la fecha consultada.
2. **Given** una cotización en proceso, **When** un usuario autorizado aplica un ajuste o sobreescritura manual de precio, **Then** el sistema registra el motivo, el valor anterior, el nuevo valor y el usuario responsable en auditoría.

---

### Edge Cases

- ¿Qué sucede con las cotizaciones en curso si se actualiza el precio base en el catálogo? Las cotizaciones existentes mantienen el precio congelado que tenían al momento de emitirse hasta su fecha de vencimiento; no se alteran retroactivamente.
- ¿Cómo se maneja un producto sin precio configurado? No puede activarse comercialmente ni incluirse en cotizaciones hasta que tenga al menos un esquema de precio válido.
- ¿Se permite solapamiento de rangos de fechas para temporadas con tarifas contradictorias? El sistema debe validar que los rangos temporales para una misma tarifa no se solapen.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE permitir el registro, actualización, consulta y desactivación lógica de Experiencias turísticas (nombre, descripción, duración, dificultad, capacidad, categoría).
- **FR-002**: El sistema DEBE permitir el registro, actualización, consulta y desactivación lógica de Alojamientos (nombre, tipo, ubicación, capacidad, amenidades).
- **FR-003**: El sistema DEBE soportar la creación de Paquetes Predefinidos compuestos por combinaciones de experiencias, alojamientos y complementos con itinerario. El precio del paquete DEBE definirse de forma explícita como un esquema de precios propio del paquete, independiente de los precios de sus componentes.
- **FR-004**: El sistema DEBE permitir registrar Complementos / Add-ons independientes y asociarlos a productos base.
- **FR-005**: El sistema DEBE categorizar los productos mediante taxonomías organizacionales (ej. aventura, ecológico, cultural, lujo).
- **FR-006**: El sistema DEBE permitir la configuración de esquemas de precios (precio por persona, precio por grupo/unidad, y precios diferenciados por temporadas con fechas inicio/fin) a usuarios con rol Operador o Administrador.
- **FR-007**: El sistema DEBE soportar el versionado o congelamiento de precios para evitar afectaciones retroactivas a cotizaciones y reservas existentes.
- **FR-008**: El sistema DEBE restringir la creación/gestión del catálogo (experiencias, alojamientos, paquetes, add-ons, categorías) a los roles Operador y Administrador; el rol Agente DEBE tener acceso de solo lectura al catálogo.
- **FR-009**: El sistema DEBE restringir la sobreescritura manual de precios exclusivamente al rol Administrador, registrando en auditoría el actor, motivo, valor anterior y valor nuevo.

### Key Entities

- **Producto**: Entidad base abstracta del catálogo. Atributos: ID, OrganizaciónID, Nombre, Descripción, Estado (Borrador, Activo, Inactivo), Tipo (Experiencia, Alojamiento, Paquete).
- **Experiencia**: Subtipo de producto. Atributos: Duración (horas/días), Dificultad, Punto de encuentro, Capacidad mínima/máxima.
- **Alojamiento**: Subtipo de producto. Atributos: Tipo de inmueble (hotel, cabaña, glamping), Ubicación, Horarios check-in/out, Reglas de ocupación.
- **Paquete**: Subtipo de producto. Lista de componentes (ítems de catálogo) con orden temporal/itinerario.
- **Add-on / Complemento**: Servicio adicional opcional. Atributos: Nombre, Descripción, Unidad de medida, Reglas de aplicabilidad.
- **Esquema de Precios**: Estructura de tarifas asociadas a un producto o add-on. Atributos: Moneda (propia de cada esquema; hereda por defecto la moneda de la organización), Monto base, Tipo de cobro (por persona, por noche, por grupo), Temporada asociada (rango de fechas).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un gestor puede registrar un producto completo (con precios y add-ons) en menos de 5 minutos a través del panel de gestión.
- **SC-002**: El 100% de los cambios en precios base mantienen inalteradas las cotizaciones y reservas emitidas previamente.
- **SC-003**: Cero errores de cálculo en el desglose de precios base y suplementos de temporada en pruebas automatizadas.
- **SC-004**: Las consultas del catálogo interno devuelven resultados en menos de 1 segundo para catálogos de hasta 5,000 ítems.

## Assumptions

- No se requiere un motor de tarificación dinámico en tiempo real basado en algoritmos de demanda (queda explícitamente diferido en mainspec Cap. 31).
- La moneda principal es configurable por organización (ej. COP, USD).
- Los proveedores de las experiencias y alojamientos se registran como metadatos de contacto/operación para facilitar la posterior verificación de disponibilidad.
