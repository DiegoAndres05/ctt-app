# Feature Specification: 007-cms-public-discovery

**Feature Branch**: `007-cms-public-discovery`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Integración con CMS Headless (WordPress) y portal público de descubrimiento y catálogo derivado de mainspec.md (Capítulos 22, 26, 27)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Navegación Pública del Catálogo Turístico (Priority: P1)

Como viajero interesado, quiero explorar las experiencias, alojamientos y paquetes turísticos de la agencia en una interfaz web rápida, atractiva y categorizada, para descubrir las opciones que se ajustan a mis vacaciones y solicitar una propuesta.

**Why this priority**: Es la vitrina digital de la agencia que convierte visitantes en leads calificados.

**Independent Test**: Puede probarse navegando el portal público, filtrando por categoría de experiencia o destino, viendo la ficha detallada de un producto con sus fotos e información descriptiva y haciendo clic en el botón de solicitar cotización.

**Acceptance Scenarios**:

1. **Given** un usuario visitante no autenticado en la web pública, **When** accede a la sección de experiencias, **Then** visualiza las tarjetas de productos activos con foto principal, título, resumen, duración, precio referencial "desde" y botón de ver más.
2. **Given** un visitante en la ficha de una experiencia o paquete, **When** hace clic en "Solicitar Cotización / Personalizar este viaje", **Then** el sistema abre el formulario de solicitud con el producto de interés preseleccionado.
3. **Given** un producto marcado como "inactivo" o en borrador en el panel administrativo, **When** se consulta el portal público, **Then** dicho producto no aparece listado ni es accesible vía URL pública.

---

### User Story 2 - Publicación de Artículos y Páginas Informativas vía CMS Headless (Priority: P2)

Como equipo de marketing de la agencia, quiero redactar y publicar artículos de blog, guías de viaje, páginas de destino (landing pages) y políticas de servicio a través de un CMS (WordPress) sin tocar la base de datos transaccional, para que el contenido se renderice en la web pública de la agencia con optimización SEO.

**Why this priority**: La Constitución y el mainspec estipulan claramente que el contenido editorial debe desacoplarse estrictamente de la lógica transaccional y gestionarse en WordPress.

**Independent Test**: Puede probarse publicando un artículo en el CMS headless y verificando que el frontend público lo consume y renderiza con su título, contenido enriquecido, imágenes y meta-etiquetas SEO.

**Acceptance Scenarios**:

1. **Given** un nuevo artículo o guía de viaje publicado en WordPress, **When** un usuario visita la sección de blog o noticias en la web pública, **Then** el artículo se despliega con su tipografía corporativa, imágenes y diseño optimizado.
2. **Given** un artículo en estado borrador en el CMS, **When** se consulta la web pública, **Then** el contenido permanece oculto al público.

---

### User Story 3 - Estrategia de Caching para Alto Rendimiento (Priority: P2)

Como visitante de la web pública, quiero que las páginas de productos, artículos de blog y listados carguen instantáneamente, incluso ante picos de tráfico de campañas publicitarias.

**Why this priority**: La velocidad de carga en el frontend público es determinante para la experiencia de usuario, las tasas de conversión y el posicionamiento SEO (mainspec Cap. 26).

**Independent Test**: Puede probarse midiendo los tiempos de respuesta sucesivos para la misma página de catálogo o blog, verificando que las lecturas repetidas son servidas desde caché en milisegundos.

**Acceptance Scenarios**:

1. **Given** una solicitud a una página de catálogo público, **When** se solicita por primera vez, **Then** los datos se recuperan, se almacenan en caché y se devuelven al cliente.
2. **Given** consultas subsiguientes a la misma página dentro del tiempo de vida de la caché (TTL), **When** se solicitan, **Then** se sirven directamente desde la memoria caché con latencia mínima.
3. **Given** un cambio en el catálogo (ej. producto desactivado o editado), **When** el administrador guarda los cambios, **Then** el sistema invalida la caché de dicho ítem para reflejar la información actualizada.

---

### Edge Cases

- ¿Qué ocurre si el CMS (WordPress) no está disponible temporalmente? La web pública debe seguir funcionando sirviendo el contenido previamente cacheado o mostrando una degradación elegante sin afectar el motor de solicitudes o reservas.
- ¿Pueden publicarse precios o datos transaccionales desde el CMS? No, los precios y disponibilidades provienen exclusivamente del motor transaccional de la plataforma, nunca del CMS.
- ¿Cómo se manejan imágenes de gran tamaño subidas por marketing? El sistema debe optimizar la carga de recursos multimedia mediante formatos modernos y lazy loading.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE exponer un portal público de descubrimiento accesible para visitantes sin necesidad de registro ni autenticación.
- **FR-002**: El catálogo público DEBE mostrar únicamente productos (experiencias, alojamientos, paquetes) en estado Activo y con visibilidad pública autorizada.
- **FR-003**: Toda ficha de producto en el portal público DEBE incluir un llamado a la acción (CTA) directo que enlace al formulario de Solicitud de Cliente con el ítem preseleccionado.
- **FR-004**: El sistema DEBE integrar de forma desacoplada el contenido editorial (artículos, guías, landings, FAQs) originado en WordPress vía su API REST o GraphQL.
- **FR-005**: El sistema DEBE prohibir estrictamente que los datos transaccionales de reservas, clientes, cotizaciones o inventario residan o se administren dentro de WordPress (Principio de Fuente de Verdad).
- **FR-006**: El sistema DEBE implementar mecanismos de almacenamiento en caché para respuestas públicas de contenido y catálogo con tiempos de expiración configurables (TTL).
- **FR-007**: El sistema DEBE permitir la invalidación controlada de la caché ante actualizaciones de catálogo o publicaciones editoriales prioritarias.

### Key Entities

- **Publicación Editorial**: Contenido informativo originado en el CMS headless. Atributos: ID, Slug, Título, Contenido, ImagenDestacada, CategoríaEditorial, FechaPublicación, MetadatosSEO.
- **Ficha Pública de Producto**: Proyección pública de lectura optimizada del producto de catálogo. Atributos: ProductoID, Slug, Título, DescripciónCorta, DescripciónDetallada, GaleríaImágenes, AtributosDestacados, TarifaReferencialDesde, EnlaceSolicitud.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Tiempo de carga inicial de la página principal y fichas de producto menor a 1.5 segundos en conexiones de banda ancha estándar.
- **SC-002**: 90%+ de las solicitudes públicas de lectura atendidas desde caché durante períodos de alto tráfico.
- **SC-003**: 100% de aislamiento entre el CMS de marketing y la base de datos transaccional de operaciones turísticas (0 acoplamiento de negocio).
- **SC-004**: Disponibilidad del flujo de solicitudes web garantizada incluso si el servicio CMS experimenta interrupciones.

## Assumptions

- WordPress se utiliza exclusivamente como CMS Headless para artículos y contenido estático de marketing.
- El diseño y componentes visuales del portal público se construyen dentro de la aplicación frontend aprobada (Angular).
