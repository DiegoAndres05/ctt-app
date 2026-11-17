# Feature Specification: Traducción automática de artículos del blog

**Feature Branch**: `017-blog-translation`

**Created**: 2026-11-17

**Status**: Implemented (2026-11-17) · producción pendiente de alojar el traductor

**Input**: User description: "En el blog, si se escribe en español, que se traduzca automáticamente a inglés pero pudiendo corregirlo o editarlo, y viceversa. Con spec-kit, sin nada de IA, algo que sea gratis." Decisión previa del usuario: traductor de código abierto alojado por el propio proyecto (sin coste por uso y sin enviar el texto a terceros).

**Depende de**: `013-editorial-content` (artículos bilingües, revisión en curso, validación al publicar) y `016-multiagency-public-cms` (idiomas de la agencia).

## Clarifications

### Session 2026-11-17

- Q: ¿Qué traductor gratuito se usa? → A: Uno de código abierto alojado por el propio proyecto (sin coste por uso, sin IA generativa y sin enviar el texto a terceros). Se aceptó que todo traductor automático actual usa modelos neuronales; lo que se excluye es la IA generativa y los servicios de pago o de terceros.
- Q: ¿Dónde corre el traductor en producción? → A: Se decide después. En esta versión corre en local; en producción se activa al configurar la dirección del servidor. Mientras no esté configurado, el botón informa que la traducción no está disponible (US3).
- Q: (implementación) El traductor local tarda ~2 s por frase; un artículo de 1.500 palabras no cabe en una sola solicitud de 60 s. → A: El artículo se envía en partes con progreso y el límite pasa de solicitudes a caracteres por hora (FR-011–FR-013, SC-001).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Traducir un artículo al otro idioma y corregirlo (Priority: P1)

Como persona autorizada de una agencia, quiero que el artículo que escribí en español se traduzca al inglés (o al revés) con un botón, y que el resultado quede en el editor como texto normal que puedo corregir, para no tener que escribir cada artículo dos veces.

**Why this priority**: Es el objetivo de la funcionalidad. Por sí sola ya reduce a la mitad el trabajo de publicar en una agencia bilingüe.

**Independent Test**: En una agencia que ofrece español e inglés, se crea un artículo con título, resumen, contenido con títulos, lista, enlace en negrita e imagen con texto alternativo, todo solo en español. En la pestaña Inglés se pulsa «Traducir desde Español». Los campos en inglés se rellenan con la traducción, se mantienen los mismos bloques, el enlace apunta a la misma dirección y la imagen es la misma. Se corrige una frase a mano, se guarda y se publica.

**Acceptance Scenarios**:

1. **Given** un artículo con contenido en español y la pestaña Inglés vacía, **When** la persona pulsa «Traducir desde Español», **Then** título, resumen, contenido, textos alternativos (portada e imágenes) y, si existen, título y descripción SEO aparecen traducidos en la pestaña Inglés.
2. **Given** una traducción recién aplicada, **When** la persona revisa la pestaña, **Then** ve un aviso de que es una traducción automática que debe revisar, y todos los campos traducidos se pueden editar como cualquier otro texto.
3. **Given** un artículo escrito solo en inglés, **When** la persona pulsa «Traducir desde Inglés» en la pestaña Español, **Then** ocurre lo mismo en la dirección contraria.
4. **Given** un contenido con párrafos, títulos de nivel 2 y 3, listas, citas, negritas, cursivas, enlaces e imágenes, **When** se traduce, **Then** la traducción conserva el mismo número y tipo de bloques, el mismo orden, las mismas imágenes y las mismas direcciones de enlace. Solo cambia el texto visible.
5. **Given** una traducción aplicada pero sin guardar, **When** la persona sale del editor, **Then** recibe el mismo aviso de cambios sin guardar que con cualquier otra edición.
6. **Given** una traducción aplicada y guardada en un artículo publicado, **When** se consulta el sitio público, **Then** la versión pública no cambia hasta que la persona pulsa «Publicar cambios».

---

### User Story 2 - No perder lo que ya está escrito en el otro idioma (Priority: P2)

Como persona autorizada, quiero que traducir no borre sin avisar lo que ya escribí o corregí en el idioma de destino, para poder volver a traducir después de cambiar el original sin perder mis correcciones por accidente.

**Why this priority**: Sin esta protección, una segunda traducción destruye el trabajo de revisión. No es necesaria para la primera traducción, por eso va después de US1.

**Independent Test**: Se traduce un artículo al inglés, se corrige el título en inglés y se guarda. Se cambia un párrafo en español y se vuelve a pulsar «Traducir desde Español». El sistema pregunta si rellenar solo lo vacío o reemplazar todo. Con «Cancelar» nada cambia. Con «Reemplazar todo» el título corregido se sustituye.

**Acceptance Scenarios**:

1. **Given** una pestaña de destino con al menos un campo con texto, **When** la persona pulsa traducir, **Then** el sistema pide elegir entre «Rellenar solo campos vacíos», «Reemplazar todo» y «Cancelar» antes de cambiar nada.
2. **Given** la opción «Rellenar solo campos vacíos», **When** se aplica, **Then** solo se rellenan los campos de destino vacíos y el contenido de destino solo se rellena si está vacío; ningún texto existente cambia.
3. **Given** la opción «Cancelar», **When** se elige, **Then** la pestaña de destino queda exactamente igual.
4. **Given** una traducción aplicada que no gusta, **When** la persona pulsa «Deshacer traducción» antes de guardar, **Then** la pestaña de destino vuelve a lo que tenía justo antes de traducir.

---

### User Story 3 - Seguir trabajando si el traductor no responde (Priority: P3)

Como persona autorizada, quiero que, si la traducción falla o tarda demasiado, se me diga claramente y pueda seguir escribiendo a mano, para que un problema del traductor nunca me impida editar ni publicar.

**Why this priority**: Protege el flujo editorial existente. El traductor es una ayuda, no un requisito para publicar.

**Independent Test**: Con el traductor apagado, se pulsa traducir. Aparece un mensaje en español que explica que la traducción no está disponible, la pestaña de destino no cambia y se puede escribir, guardar y publicar a mano.

**Acceptance Scenarios**:

1. **Given** el traductor no disponible, **When** la persona pulsa traducir, **Then** ve un mensaje claro, la pestaña de destino no cambia y el resto del editor sigue funcionando.
2. **Given** un artículo en el que una parte se traduce y otra falla, **When** termina el intento, **Then** no se aplica nada (todo o nada) y se informa del fallo.
3. **Given** una agencia que alcanzó su límite de caracteres de la hora, **When** pulsa traducir, **Then** ve cuándo puede volver a intentarlo y la pestaña de destino no cambia.
4. **Given** una traducción en curso, **When** la persona espera, **Then** ve que se está traduciendo y cuántas partes van, y no puede lanzar otra traducción del mismo artículo a la vez.

### Edge Cases

- **Origen vacío**: si el idioma de origen no tiene ningún texto traducible, el botón está desactivado y explica por qué.
- **Agencia con un solo idioma**: si la agencia ofrece un único idioma, el botón no se muestra.
- **Texto traducido demasiado largo**: si una traducción supera el límite de un campo (por ejemplo, título de más de 120 caracteres), se aplica igualmente y el campo muestra el error de longitud de siempre para que la persona lo acorte. Nunca se recorta en silencio.
- **Slug**: nunca se traduce ni cambia; es uno por artículo (013 FR-014–FR-016).
- **Enlaces y correos**: la dirección de un enlace no se traduce; solo su texto visible.
- **Imágenes decorativas**: una imagen marcada como decorativa sigue decorativa y sin texto alternativo.
- **Nombres propios y marcas** (Cartagena, Islas del Rosario, nombre de la agencia): el traductor puede alterarlos; la persona los corrige en la revisión. No hay glosario en esta versión.
- **Artículos migrados**: se traducen igual que los demás; la traducción no cambia su slug ni su fecha original.
- **Edición simultánea**: guardar una traducción sigue la regla de conflicto de 013 FR-010.
- **Contenido no permitido**: la traducción pasa por la misma limpieza de contenido que cualquier guardado (013 FR-007).

## Requirements *(mandatory)*

### Functional Requirements

**Traducción**

- **FR-001**: Las personas con permiso para editar el blog (Administrador y Operador, 013 FR-018) DEBEN poder traducir un artículo de español a inglés y de inglés a español desde el editor. Agente NO DEBE poder hacerlo.
- **FR-002**: La traducción DEBE cubrir título, resumen, contenido, texto alternativo de la portada, texto alternativo de cada imagen no decorativa, título SEO y descripción SEO. Los campos vacíos en el origen DEBEN quedar sin cambios en el destino.
- **FR-003**: La traducción DEBE conservar la estructura del contenido: mismos bloques en el mismo orden y con el mismo tipo y nivel, mismas imágenes, mismas direcciones de enlace y mismos formatos (negrita, cursiva, enlace) sobre el texto equivalente. Solo DEBE cambiar el texto visible.
- **FR-004**: La traducción DEBE aplicarse solo en el editor, como una edición sin guardar. NO DEBE guardar, publicar ni modificar la versión publicada. Guardar y publicar siguen las reglas de 013 (borrador, revisión en curso, validación por idioma, conflicto).
- **FR-005**: El editor DEBE mostrar en la pestaña de destino un aviso de que el texto es una traducción automática que debe revisarse, hasta que la persona guarde o descarte.
- **FR-006**: Una traducción DEBE aplicarse completa o no aplicarse. Si falla cualquier parte, el destino NO DEBE cambiar.
- **FR-007**: El slug NO DEBE traducirse ni cambiar al traducir.

**Protección del texto existente**

- **FR-008**: Si el destino tiene texto en algún campo, el sistema DEBE pedir elegir entre «Rellenar solo campos vacíos», «Reemplazar todo» y «Cancelar» antes de aplicar nada.
- **FR-009**: Hasta guardar, la persona DEBE poder deshacer la última traducción y recuperar el destino tal como estaba justo antes.

**Servicio y límites**

- **FR-010**: El servicio de traducción DEBE ser gratuito por uso, de código abierto y operado por el propio proyecto. NO DEBE usar modelos de IA generativa ni enviar el texto de los artículos a servicios de terceros.
- **FR-011**: Un artículo largo DEBE enviarse al traductor en partes, mostrando el avance («Traduciendo… 2/5»). Si alguna parte no responde, falla o tarda más de 60 segundos, el editor DEBE mostrar un mensaje claro en español, no aplicar nada y seguir funcionando para escribir, guardar y publicar a mano.
- **FR-012**: El sistema DEBE limitar el uso a 150.000 caracteres enviados al traductor por agencia y hora (unos quince artículos largos), e indicar cuándo se puede volver a intentar.
- **FR-016**: Si el traductor no está configurado en un entorno, el botón DEBE mostrarse e informar al pulsarlo que la traducción no está disponible, como en FR-011.
- **FR-013**: Cada parte enviada al traductor DEBE tener como máximo 40 textos y 5.000 caracteres. Un solo bloque de texto de más de 5.000 caracteres DEBE rechazarse con un mensaje que pida dividirlo.
- **FR-014**: El texto traducido NO DEBE conservarse fuera del artículo ni registrarse en logs del servicio más allá de lo necesario para responder.
- **FR-015**: Solo DEBE poder traducirse el contenido de un artículo de la propia agencia (013 FR-019).

### Key Entities

- **Petición de traducción**: idioma de origen, idioma de destino y el texto de los campos del artículo. Es efímera: no se guarda.
- **Uso de traducción por agencia**: caracteres enviados por agencia y hora, para aplicar el límite de FR-012. No guarda el texto.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Una persona obtiene la versión traducida y lista para revisar de un artículo corto (título, resumen y unas 150 palabras) en menos de 30 segundos, y durante la traducción de un artículo largo ve avanzar las partes sin esperas de más de 60 segundos sin progreso. El tiempo total depende de la CPU del servidor del traductor (ver research R9).
- **SC-002**: En el 100 % de las traducciones de prueba, el contenido traducido tiene el mismo número, tipo y orden de bloques, las mismas imágenes y las mismas direcciones de enlace que el original.
- **SC-003**: Publicar un artículo en los dos idiomas a partir de uno solo ya escrito toma menos de la mitad del tiempo que escribir el segundo idioma a mano.
- **SC-004**: En el 100 % de las pruebas con el traductor apagado o fallando, el destino no cambia y el artículo se puede guardar y publicar a mano.
- **SC-005**: En el 100 % de las pruebas, ninguna traducción cambia la versión publicada ni el slug.
- **SC-006**: El coste por traducción es cero; el único coste es el del servidor donde corre el traductor.

## Assumptions

- Idiomas: solo español e inglés, los mismos de 013. Añadir idiomas queda fuera de esta versión.
- La calidad del traductor de código abierto es menor que la de servicios comerciales; la revisión humana es obligatoria por diseño (FR-004, FR-005) y la validación de 013 sigue exigiendo cada idioma completo antes de publicar.
- El traductor corre en la infraestructura del proyecto (local en desarrollo y un servidor propio en producción). Introducir este servicio es un cambio de nivel 3 de la constitución: requiere un ADR durante el plan.
- No hay glosario ni memoria de traducción en esta versión; los nombres propios se corrigen a mano.
- No se traducen catálogo, perfil público ni otras pantallas; solo artículos del blog.
- Traducir no genera evento de auditoría propio: el guardado y la publicación ya se auditan en 013.
