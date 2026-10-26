# Feature Specification: Portal público del catálogo

**Feature Branch**: `011-public-catalog-browse`

**Created**: 2026-10-26

**Status**: Draft

**Input**: Iteración 1 de 5. El viajero descubre experiencias, alojamientos y yates publicados por la agencia, en español e inglés, sin cuenta. Cierra el tramo «Discover» de `.specify/mainspec.md` (capítulos 15 y 30) sobre las fichas que ya publica el panel (009).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Recorrer el catálogo publicado (Priority: P1)

Como viajero sin cuenta, quiero ver las experiencias, los alojamientos y los yates que la agencia tiene publicados, con foto, nombre, resumen y precio de vitrina, para elegir qué quiero conocer antes de hablar con la agencia.

**Why this priority**: Sin vitrina, el canal web del producto no existe. El panel ya puede publicar fichas; el viajero todavía no las ve dentro de la aplicación.

**Independent Test**: Con la vitrina de la agencia ya activada en el panel, un visitante sin sesión abre el catálogo y ve solo ofertas, alojamientos y yates publicados, cada uno con foto, nombre, resumen y precio mostrado.

**Acceptance Scenarios**:

1. **Given** un visitante sin sesión y la vitrina activada, **When** abre el catálogo, **Then** ve tres grupos: experiencias, alojamientos y yates, y cada tarjeta muestra foto principal, nombre, resumen y precio de vitrina en el idioma activo.
2. **Given** un producto en borrador, inactivo o despublicado, **When** el visitante recorre el catálogo o intenta abrir su dirección, **Then** ese producto no aparece y la dirección no revela que existió.
3. **Given** una ficha publicada marcada como agotada, **When** el visitante la ve, **Then** sigue visible, muestra que está agotada y no ofrece enviar una solicitud.
4. **Given** la vitrina todavía no está activada, **When** el visitante abre el catálogo, **Then** ve un aviso de que el catálogo se está preparando, sin error técnico y sin fichas a medias.

---

### User Story 2 - Leer la ficha en su idioma (Priority: P1)

Como viajero, quiero abrir una oferta y leerla en español o en inglés, con la misma información que la agencia publicó, para decidir si pido una propuesta.

**Why this priority**: La ficha es la unidad de descubrimiento. El idioma es parte de lo que la agencia ya carga en el panel.

**Independent Test**: Se abre una ficha publicada, se cambia el idioma y se comprueba que nombre, descripción e inclusiones cambian de idioma y que el precio de vitrina sigue siendo el publicado.

**Acceptance Scenarios**:

1. **Given** una ficha publicada, **When** el visitante la abre, **Then** ve galería, descripción, inclusiones, advertencias, ubicación o datos propios del tipo (alojamiento o yate) y el precio de vitrina.
2. **Given** la ficha en español, **When** el visitante elige inglés, **Then** nombre, descripción e inclusiones pasan a inglés sin mezclar ambos idiomas en el mismo bloque.
3. **Given** una dirección de ficha desconocida, **When** el visitante la abre, **Then** ve una página de «no encontrada» y un regreso al catálogo.

---

### User Story 3 - Llegar a pedir información (Priority: P2)

Como viajero que ya eligió una ficha, quiero un llamado claro para pedir información de ese viaje, para no tener que buscar otro canal ni creer que ya reservé.

**Why this priority**: El descubrimiento solo convierte si lleva a la solicitud. La solicitud en sí es la iteración 2; aquí el llamado debe existir y decir la verdad.

**Independent Test**: En una ficha publicada, el botón visible dice que se solicita información o una propuesta, y lleva al inicio de esa solicitud con la ficha ya elegida. No dice «reserva confirmada».

**Acceptance Scenarios**:

1. **Given** una ficha publicada, **When** el visitante pulsa el llamado, **Then** llega al inicio de la solicitud con esa ficha preseleccionada.
2. **Given** una ficha agotada, **When** el visitante ve la ficha, **Then** no hay botón de solicitud y el texto dice que esta oferta no admite pedidos ahora.

---

### Edge Cases

- Si no hay ninguna ficha publicada en un grupo, ese grupo muestra un vacío claro («aún no hay experiencias») y los otros grupos siguen visibles.
- El precio de vitrina es orientativo. La ficha no promete el precio final ni la disponibilidad.
- Una ficha publicada cuyo producto deje de estar activo desaparece del catálogo en la siguiente visita, igual que una despublicada.
- El visitante no ve datos de otros clientes, notas internas, tarifas de costo ni el nombre del prestador.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Un visitante sin cuenta DEBE poder abrir el catálogo público de la agencia.
- **FR-002**: El catálogo DEBE mostrar solo fichas publicadas de productos activos, separadas en experiencias, alojamientos y yates.
- **FR-003**: Cada tarjeta y cada ficha DEBEN mostrar la foto principal, el nombre, el resumen y el precio de vitrina publicados para el idioma activo.
- **FR-004**: El visitante DEBE poder alternar español e inglés. El contenido visible de un bloque DEBE corresponder a un solo idioma.
- **FR-005**: Borradores, fichas despublicadas y productos inactivos NO DEBEN aparecer ni ser recuperables por una dirección conocida.
- **FR-006**: Una ficha agotada DEBE seguir visible, DEBE indicarlo de forma explícita y NO DEBE ofrecer el envío de una solicitud.
- **FR-007**: Mientras la vitrina de la agencia no esté activada, el visitante DEBE ver un estado de preparación y ninguna ficha parcial.
- **FR-008**: Toda ficha que admite solicitudes DEBE ofrecer un llamado a pedir información, con un texto que no presente la acción como reserva confirmada.
- **FR-009**: El catálogo público NO DEBE mostrar costos de prestador, notas internas, datos de clientes ni el precio final de una cotización.

### Key Entities

- **Ficha pública**: Lo que el visitante puede ver de una experiencia, un alojamiento o un yate. Atributos visibles: identificador público, grupo, nombres, textos, galería, inclusiones, advertencias, precio de vitrina, idioma, marca de agotado.
- **Vitrina de la agencia**: El interruptor ya existente que decide si el catálogo público muestra lo publicado en el panel o el aviso de preparación.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un visitante sin cuenta encuentra una ficha publicada y abre su detalle en menos de 1 minuto desde la portada del catálogo.
- **SC-002**: En una revisión de 20 fichas mezclando publicadas, borradores, inactivas y agotadas, el 100% de las no publicables permanece invisible y el 100% de las agotadas se reconoce como agotada.
- **SC-003**: En una revisión bilingüe, el 100% de las fichas publicadas muestra nombre, descripción e inclusiones en el idioma elegido.
- **SC-004**: 10 de cada 10 revisores distinguen el precio de vitrina y el llamado a solicitar información de una reserva ya confirmada.

## Assumptions

- La agencia ya publica fichas desde el panel (009), con textos en español e inglés, foto, precio de vitrina y grupo (experiencia, alojamiento o yate).
- Esta iteración no crea ni edita fichas. Solo las muestra.
- El formulario de solicitud se especifica en `specs/012-public-trip-request/`. Aquí el llamado solo conduce a ese inicio.
- Hay una sola agencia servida por este sitio público.
- El sitio público no usa el menú interno de operadores.
