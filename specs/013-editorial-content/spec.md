# Feature Specification: Contenido editorial del sitio público

**Feature Branch**: `013-editorial-content`

**Created**: 2026-10-26

**Status**: Draft

**Input**: Iteración 3 de 5. Marketing publica blog, guías, páginas de destino y políticas en el gestor editorial, y el sitio público las muestra. Los datos comerciales siguen fuera de ese gestor (`.specify/mainspec.md`, capítulo 22).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Publicar una página editorial (Priority: P1)

Como responsable de marketing, quiero redactar y publicar un artículo, una guía, una página de destino o una política en el gestor editorial, para que el viajero la lea en el sitio sin que nadie toque reservas, precios o clientes.

**Why this priority**: El producto separa el contenido de marketing de la operación. Hoy esa vitrina editorial no está en el sitio de la aplicación.

**Independent Test**: Se publica un artículo en el gestor y, sin cambios en el panel comercial, el viajero lo abre en el sitio con título, texto, imagen y la fecha de publicación.

**Acceptance Scenarios**:

1. **Given** un artículo publicado en el gestor, **When** un visitante abre el blog, **Then** ve el título, el resumen, la imagen y puede leer el texto completo.
2. **Given** el mismo artículo en borrador, **When** el visitante abre el blog o la dirección del artículo, **Then** no lo ve.
3. **Given** una política publicada, **When** el visitante abre las políticas, **Then** lee el texto vigente, no un borrador anterior.

---

### User Story 2 - Cuatro tipos de contenido, un solo lugar (Priority: P1)

Como visitante, quiero encontrar el blog, las guías, los destinos y las políticas en secciones distintas, para no mezclar una inspiración de viaje con una condición de servicio.

**Why this priority**: El capítulo 22 nombra esos cuatro usos. Juntarlos en una sola lista los vuelve inútiles.

**Independent Test**: Existen cuatro entradas publicadas, una de cada tipo. Cada sección lista solo la suya.

**Acceptance Scenarios**:

1. **Given** contenido publicado de los cuatro tipos, **When** el visitante abre cada sección, **Then** ve solo ese tipo.
2. **Given** una página de destino publicada, **When** el visitante la abre, **Then** puede seguir hacia el catálogo, pero la página en sí no muestra cupos, precios finales ni datos de clientes.

---

### User Story 3 - El sitio comercial sigue si el gestor falla (Priority: P2)

Como visitante que quiere ver una experiencia o enviar una solicitud, quiero poder hacerlo aunque el gestor editorial no responda.

**Why this priority**: Una caída del blog no puede tumbar el canal de solicitudes.

**Independent Test**: Con el gestor editorial inalcanzable, el catálogo y el formulario de solicitud siguen abriendo. La sección editorial explica que el contenido no está disponible en este momento, sin una página en blanco de toda la aplicación.

**Acceptance Scenarios**:

1. **Given** el gestor editorial no responde, **When** el visitante abre una experiencia publicada, **Then** la ficha y el llamado a solicitar información siguen disponibles.
2. **Given** el mismo fallo, **When** abre el blog, **Then** ve un aviso de contenido no disponible y un camino de vuelta al catálogo.

---

### Edge Cases

- Un artículo programado o privado en el gestor no aparece.
- Quitar la publicación oculta la página en la siguiente visita; no deja una copia editable dentro del panel comercial.
- El gestor no es el lugar para crear productos, tarifas, solicitudes, cotizaciones ni reservas. Si alguien escribe un precio en un artículo, ese texto no actualiza la tarifa ni el precio de vitrina.
- La imagen destacada que falta no impide leer el texto.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sitio público DEBE mostrar artículos, guías, páginas de destino y políticas publicadas en el gestor editorial.
- **FR-002**: Cada tipo DEBE tener su propia sección.
- **FR-003**: Un contenido no publicado NO DEBE ser visible ni recuperable por su dirección pública.
- **FR-004**: La página editorial DEBE mostrar título, texto, imagen destacada cuando exista, y fecha de publicación.
- **FR-005**: El gestor editorial NO DEBE ser fuente de productos, tarifas, disponibilidad, clientes, solicitudes, cotizaciones ni reservas.
- **FR-006**: Un fallo del gestor editorial NO DEBE impedir ver el catálogo publicado ni enviar una solicitud.
- **FR-007**: Ante ese fallo, la sección editorial DEBE mostrar un aviso comprensible y un regreso al catálogo.
- **FR-008**: Marketing DEBE poder ocultar un contenido dejándolo de publicar, sin un trámite en el panel de operaciones.

### Key Entities

- **Publicación editorial**: Pieza de marketing. Atributos: tipo (artículo, guía, destino o política), título, resumen, texto, imagen, fecha, dirección pública, estado publicado o no.
- **Sección editorial**: Lista pública de un solo tipo.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Marketing publica un artículo y un visitante lo lee en el sitio en menos de 5 minutos, sin pedir un cambio al equipo de operaciones.
- **SC-002**: En una revisión de 12 piezas (publicadas y borradores de los cuatro tipos), el 100% de los borradores permanece oculto y cada sección lista solo su tipo.
- **SC-003**: Con el gestor editorial detenido, un visitante aún completa la apertura de una ficha y el envío de una solicitud de prueba.
- **SC-004**: Ninguna prueba de esta iteración modifica una tarifa, una solicitud o una reserva al publicar o editar contenido.

## Assumptions

- El gestor editorial es WordPress, como fija el capítulo 22 de `.specify/mainspec.md`. El panel de operaciones no lo reemplaza.
- El catálogo (011) y la solicitud (012) ya están disponibles para el visitante.
- Los textos editoriales se redactan en el idioma en que marketing los publique. Esta iteración no traduce sola.
- No se pide cuenta al visitante para leer.
