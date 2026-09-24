# Feature Specification: Contenido público del catálogo

**Feature Branch**: `009-catalog-site-cms`

**Created**: 2026-09-22

**Status**: Draft

**Input**: User description: "Mejora del spec 002 para que lo creado en el catálogo se administre como contenido de la página pública https://www.cartagenatailoredtravel.com/, con carga de imágenes y la misma estructura de contenido que esa página ya usa (ejemplo: oferta pública con nombre, descripción, imagen, inclusiones, advertencias, categoría, ubicación y precio mostrado, en español e inglés)."

## Clarifications

### Session 2026-09-23

- Q: Cuando la página pase a mostrar el contenido del panel, ¿qué debe pasar con las ofertas y los alojamientos que ya se ven hoy? → A: Copiar al panel las ofertas y alojamientos que la página muestra hoy, y a partir del cambio la página muestra solo lo publicado en el panel.
- Q: Las ofertas que hoy muestra el catálogo de la página, ¿como qué producto del catálogo interno deben copiarse? → A: Cada oferta del catálogo público se copia como experiencia y cada alojamiento como alojamiento. Los yates que muestra la página de yates también se copian como experiencias.
- Q: Al copiar una oferta o un alojamiento, ¿el precio que el visitante ve hoy también queda como tarifa inicial del producto? → A: En ofertas y alojamientos, el precio visible queda como tarifa inicial y la ficha puede marcarse agotada. En yates, el precio es opcional y también pueden marcarse agotados. Cambiar después el precio de vitrina no cambia la tarifa.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Publicar una oferta con el contenido de la página (Priority: P1)

Como gestor de producto, quiero completar la ficha pública de una experiencia o un paquete predefinido con los mismos datos que hoy muestra el catálogo de la página, en español e inglés, para que la oferta aparezca en el sitio sin que alguien tenga que editar la página a mano.

**Why this priority**: El catálogo interno ya existe. El valor de esta mejora es que ese catálogo alimente la vitrina pública con la estructura que la página ya entiende.

**Independent Test**: Puede probarse tomando una experiencia o un paquete activo, completando su ficha pública obligatoria, publicándola y comprobando que un visitante ve en el catálogo público el nombre, la descripción, la imagen, la ubicación, la categoría, las inclusiones y el precio mostrado, en el idioma que elija.

**Acceptance Scenarios**:

1. **Given** una experiencia o un paquete predefinido activo sin ficha pública, **When** el gestor completa identificador público, nombres, descripciones, categoría, ubicación, imagen, inclusiones en español e inglés y precio mostrado, y la publica, **Then** la oferta aparece en el catálogo público con esos datos y deja de requerir un cambio manual en la página.
2. **Given** un visitante que consulta la página en inglés, **When** abre una oferta publicada, **Then** ve el nombre, la descripción y las inclusiones en inglés.
3. **Given** un visitante que consulta la página en español, **When** abre la misma oferta, **Then** ve el nombre, la descripción y las inclusiones en español.
4. **Given** una ficha pública incompleta, **When** el gestor intenta publicarla, **Then** el sistema la conserva como borrador y explica qué datos faltan.
5. **Given** una oferta publicada, **When** el gestor corrige un texto o el precio mostrado y guarda, **Then** la siguiente visita a la página muestra el contenido actualizado y las cotizaciones ya emitidas conservan el precio que tenían.

---

### User Story 2 - Cargar y reemplazar imágenes (Priority: P1)

Como gestor de producto, quiero subir la foto principal de una oferta y, en los alojamientos, fotos adicionales, para que la página muestre imágenes propias de la agencia y pueda cambiarlas cuando la oferta se actualice.

**Why this priority**: Sin imagen la página no puede presentar la oferta como lo hace hoy, y la carga manual fuera del panel es el vacío que esta mejora cierra.

**Independent Test**: Puede probarse subiendo una imagen válida a una ficha, comprobando que queda asociada como imagen principal, reemplazándola por otra y verificando que un archivo que no es imagen o que excede el tamaño permitido es rechazado sin perder el resto de la ficha.

**Acceptance Scenarios**:

1. **Given** una ficha en edición, **When** el gestor sube una imagen válida, **Then** esa imagen queda como foto principal de la oferta y es la que ve el visitante al publicarse.
2. **Given** una oferta ya publicada, **When** el gestor reemplaza la foto principal, **Then** la siguiente visita muestra la imagen nueva y la ficha conserva el resto del contenido.
3. **Given** un archivo que no es una imagen o que supera el tamaño permitido, **When** el gestor intenta subirlo, **Then** el sistema rechaza el archivo, explica el motivo y no altera la imagen anterior.
4. **Given** un alojamiento con galería, **When** el gestor agrega, reordena o quita fotos adicionales, **Then** la página de hospedaje muestra la galería en ese orden, siempre con la foto principal presente.

---

### User Story 3 - Publicar alojamientos como en la página de hospedaje (Priority: P2)

Como gestor de producto, quiero publicar un alojamiento del catálogo con la ficha que ya usa la página de hospedaje, para que casas, apartamentos, fincas y habitaciones se administren desde el mismo panel y aparezcan en esa sección.

**Why this priority**: Los alojamientos ya se crean en el catálogo, pero la página de hospedaje usa una ficha distinta a la de las ofertas del catálogo público.

**Independent Test**: Puede probarse publicando un alojamiento activo con tipo, barrio, capacidad, habitaciones, baños, precio por noche, amenidades, foto principal y galería, y comprobando que aparece en hospedaje y no en el listado de ofertas del catálogo.

**Acceptance Scenarios**:

1. **Given** un alojamiento activo, **When** el gestor completa su ficha pública de hospedaje y la publica, **Then** el visitante lo encuentra en la sección de hospedaje con tipo, ubicación, barrio, descripción bilingüe, precio por noche, capacidad y fotos.
2. **Given** un alojamiento publicado, **When** el gestor marca opiniones de huéspedes, **Then** la página muestra autor, calificación, texto en el idioma del visitante y fecha, y el número de opiniones coincide con las registradas.
3. **Given** una experiencia o un paquete, **When** se publica, **Then** aparece en el catálogo de ofertas y no se presenta como alojamiento.

---

### User Story 4 - Organizar categorías y visibilidad pública (Priority: P2)

Como gestor de producto, quiero elegir la categoría pública de cada oferta, destacarla o retirarla de la página sin borrar el producto interno, para controlar qué ve el visitante y cómo filtra el catálogo.

**Why this priority**: La página ya filtra por categoría y marca ofertas destacadas. Esa visibilidad debe decidirse en el panel, no en la página.

**Independent Test**: Puede probarse asignando una categoría existente, destacando una oferta, despublicándola y desactivando el producto interno, y comprobando en cada caso qué sigue viendo el visitante.

**Acceptance Scenarios**:

1. **Given** las categorías públicas ya usadas por la página, **When** el gestor asigna una a una oferta y la publica, **Then** el visitante puede encontrarla al filtrar por esa categoría.
2. **Given** una oferta publicada, **When** el gestor la marca como destacada, **Then** la página puede presentarla como destacada; al quitar la marca, deja de estarlo y sigue publicada.
3. **Given** una oferta publicada, **When** el gestor la despublica, **Then** desaparece de la página y el producto sigue disponible para el trabajo interno de la agencia.
4. **Given** un producto desactivado en el catálogo, **When** un visitante consulta la página, **Then** su ficha pública no se muestra ni es accesible por su dirección pública.
5. **Given** un agente comercial, **When** consulta el catálogo, **Then** puede ver la ficha pública y no puede modificarla, subir imágenes ni publicarla.
6. **Given** un gestor, **When** crea una categoría pública nueva con nombre en español e inglés, **Then** puede asignarla a una oferta y el visitante puede filtrar por ella.
7. **Given** una ficha ya publicada, **When** un administrador consulta su historial de publicación, **Then** ve quién la publicó o despublicó, quién reemplazó la imagen principal y en qué momento ocurrió cada acción.
8. **Given** dos agencias distintas, **When** un gestor de una agencia busca una ficha de la otra, **Then** no puede verla ni modificarla.

---

### User Story 5 - Conservar el catálogo vigente al cambiar la fuente (Priority: P1)

Como gestor de producto, quiero que las ofertas, los alojamientos y los yates que la página ya muestra pasen al panel antes de que la página deje su contenido actual, para que el visitante no pierda el catálogo el día del cambio.

**Why this priority**: La página ya vende con ese catálogo. Cambiar la fuente sin copiarlo deja la vitrina vacía.

**Independent Test**: Puede probarse comparando las ofertas, alojamientos y yates visibles antes del cambio con los publicados en el panel, confirmando que cada oferta y alojamiento conserva su dirección pública, y que después del cambio la página ya no muestra contenido que no esté publicado en el panel.

**Acceptance Scenarios**:

1. **Given** las ofertas y alojamientos que la página muestra hoy, **When** se prepara el cambio de fuente, **Then** cada oferta queda como experiencia y cada alojamiento como alojamiento, con ficha publicada, identificador público actual, textos, imagen y precios, y cada alojamiento conserva además su galería y sus opiniones.
2. **Given** los yates que la página de yates muestra hoy, **When** se prepara el cambio de fuente, **Then** cada yate queda como experiencia con ficha de yate publicada, nombre, descripción, imagen, capacidades y características en español e inglés.
3. **Given** una dirección pública que ya existe, **When** el visitante la abre después del cambio, **Then** llega a la misma oferta o alojamiento.
4. **Given** el cambio de fuente ya realizado, **When** un visitante abre el catálogo, el hospedaje o los yates, **Then** solo ve fichas publicadas en el panel.
5. **Given** una oferta, un alojamiento o un yate vigente que todavía no está publicado en el panel, **When** se intenta hacer el cambio de fuente, **Then** el cambio no se realiza y se indica qué fichas faltan.
6. **Given** una oferta o un alojamiento copiado desde la página, **When** queda publicado, **Then** su tarifa inicial tiene el mismo monto y la misma moneda que el precio que el visitante ve hoy, y el precio anterior tachado no se usa como tarifa.
7. **Given** una ficha publicada, **When** el gestor la marca como agotada, **Then** el visitante sigue viéndola con la etiqueta de agotado y no puede iniciar una solicitud nueva para ese producto. Al quitar la etiqueta, vuelve a poder solicitarla.

---

### Edge Cases

- ¿Qué ocurre si las inclusiones en español y en inglés no tienen la misma cantidad de elementos? La publicación se rechaza y se indica que ambas listas deben corresponderse ítem por ítem. La misma regla aplica a las advertencias cuando se informan.
- ¿Qué ocurre si el precio anterior es menor o igual que el precio mostrado? La publicación se rechaza. El precio anterior solo existe para mostrar un ahorro y debe ser mayor que el precio actual.
- ¿Qué ocurre si el identificador público ya lo usa otra oferta o alojamiento de la misma agencia? El sistema rechaza el duplicado. El identificador queda fijo después de la primera publicación para no romper la dirección que ya conocen los visitantes.
- ¿Qué ocurre si se intenta publicar sin imagen principal? La ficha permanece en borrador.
- ¿Qué ocurre si se elimina la única imagen de una oferta ya publicada? El sistema no permite dejarla publicada sin foto principal.
- ¿Qué ocurre si una categoría pública en uso se desactiva? Las ofertas que la usan no pueden seguir publicadas con esa categoría hasta que se les asigne otra categoría activa. Las categorías iniciales de la página no se eliminan.
- ¿Qué ocurre con una ficha pública si el producto pasa a inactivo? Deja de verse en la página. Al reactivarlo, no vuelve a publicarse sola: el gestor debe publicarla de nuevo.
- ¿Qué ocurre si dos gestores editan la misma ficha? Prevalece el último guardado completo y el editor ve el contenido vigente al reabrir la ficha.
- ¿Qué ocurre con el precio operativo del catálogo? La copia inicial usa el precio que el visitante ve hoy como tarifa inicial. Un cambio posterior del precio mostrado no reescribe las tarifas ni las cotizaciones ya emitidas.
- ¿Qué ocurre si una ficha se marca agotada? Sigue publicada y visible, con la etiqueta de agotado. No desaparece de la página y no altera la tarifa. El visitante no puede iniciar una solicitud nueva hasta que se quite la etiqueta.
- ¿Qué precio se copia como tarifa si la página muestra un precio actual y uno anterior? Se usa el precio actual. El precio anterior solo se conserva como precio tachado.
- ¿Qué ocurre si se intenta cambiar la fuente de la página mientras falta una oferta, un alojamiento o un yate vigente? El cambio no se realiza. La página sigue mostrando su contenido actual hasta que todas esas fichas estén publicadas en el panel.
- ¿Qué ocurre si un yate se publica con la ficha de oferta del catálogo? No se permite. El yate usa su propia ficha y aparece solo en la sección de yates.
- ¿Qué ocurre con las direcciones que los visitantes ya usan? El identificador público copiado es el que la página ya usa, así que la dirección se conserva.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE permitir que Operador y Administrador completen, guarden como borrador, publiquen y despubliquen la ficha pública de una experiencia o un paquete predefinido. El rol Agente DEBE poder consultarla y NO DEBE poder modificarla.
- **FR-002**: La ficha pública de una experiencia o un paquete DEBE conservar la estructura de contenido que el catálogo de la página ya muestra. Para publicarse DEBE incluir: identificador público, nombre en español, nombre en inglés, categoría pública, descripción en español, descripción en inglés, imagen principal, inclusiones en español, inclusiones en inglés y ubicación.
- **FR-003**: La ficha pública de una experiencia o un paquete DEBE permitir, sin exigirlos para guardar un borrador, punto de encuentro, horario, duración, máximo de huéspedes, advertencias en español, advertencias en inglés, marca de destacada, calificación, precio mostrado, precio anterior y moneda.
- **FR-004**: El sistema DEBE exigir precio mostrado y moneda para publicar una oferta del catálogo. Si se informa precio anterior, DEBE ser mayor que el precio mostrado. La calificación, cuando se informa, DEBE estar entre 0 y 5. La ficha de yate NO DEBE exigir precio mostrado, precio anterior ni categoría.
- **FR-005**: Las listas de inclusiones en español e inglés DEBEN tener la misma cantidad de elementos y el mismo orden. La misma regla aplica a las advertencias cuando alguna de las dos listas tiene contenido.
- **FR-006**: El sistema DEBE permitir subir, reemplazar y quitar la imagen principal de una ficha. DEBE aceptar imágenes habituales de página web y DEBE rechazar archivos que no sean imagen o que superen el tamaño máximo permitido, sin perder el resto de la ficha.
- **FR-007**: Una oferta, un alojamiento o un yate publicado DEBE tener siempre una imagen principal. El contenido publicado DEBE guardar la referencia de esa imagen para que la página la muestre.
- **FR-008**: El sistema DEBE mostrar en el catálogo público solo fichas de oferta de experiencias y paquetes predefinidos en estado publicado cuyo producto interno esté activo. Un borrador, una ficha despublicada o un producto inactivo NO DEBE verse ni abrirse por su dirección pública.
- **FR-009**: El identificador público DEBE ser único dentro de la agencia, apto para formar la dirección de la oferta en la página, y DEBE permanecer fijo después de la primera publicación.
- **FR-010**: El sistema DEBE ofrecer las categorías públicas con las que la página ya filtra el catálogo: islas, Barú, Tierra Bomba, compartidos, cultural, aventura, baile y premium. Operador y Administrador DEBEN poder asignar una categoría activa a cada oferta. Esas categorías iniciales NO DEBEN eliminarse.
- **FR-011**: Operador y Administrador DEBEN poder crear categorías públicas adicionales con identificador estable, nombre en español y nombre en inglés, y desactivar una categoría que ya no se use. Una categoría desactivada NO DEBE asignarse a fichas nuevas.
- **FR-012**: El sistema DEBE permitir marcar y desmarcar una oferta publicada como destacada sin despublicarla.
- **FR-013**: Después de la copia inicial, cambiar el precio mostrado en la ficha pública NO DEBE modificar las tarifas operativas del catálogo ni las cotizaciones ya emitidas.
- **FR-014**: El sistema DEBE permitir la ficha pública de un alojamiento con la estructura que la página de hospedaje ya muestra. Para publicarse DEBE incluir: identificador público, nombre en español, nombre en inglés, tipo, ubicación en español e inglés, barrio en español e inglés, descripción en español e inglés, precio por noche, moneda, máximo de huéspedes, habitaciones, baños, imagen principal y al menos la foto principal dentro de la galería.
- **FR-015**: El tipo de alojamiento público DEBE ser uno de: casa, apartamento, finca o habitación. Las amenidades seleccionables DEBEN ser las que la página de hospedaje ya reconoce: wifi, piscina, aire acondicionado, cocina, parqueadero, terraza, lavadora, televisión y asador.
- **FR-016**: La ficha de alojamiento DEBE permitir etiquetas, calificación, enlace de mapa, marca de destacado y opiniones de huéspedes. Cada opinión DEBE tener autor, calificación, texto en español, texto en inglés y fecha. Si hay opiniones, la cantidad mostrada DEBE coincidir con las opiniones registradas.
- **FR-017**: Un alojamiento publicado DEBE aparecer en la sección de hospedaje y NO DEBE aparecer en el listado de ofertas del catálogo. Una experiencia o un paquete publicado como oferta NO DEBE aparecer como alojamiento ni como yate. Una experiencia publicada como yate DEBE aparecer solo en la sección de yates.
- **FR-018**: La galería de un alojamiento DEBE permitir agregar, reordenar y quitar imágenes adicionales. La foto principal DEBE seguir siendo una de las imágenes de la ficha.
- **FR-019**: Al desactivar un producto en el catálogo, su ficha pública DEBE dejar de mostrarse. Al reactivarlo, la ficha NO DEBE volver a publicarse automáticamente.
- **FR-020**: Cada ficha pública y cada imagen DEBEN pertenecer a una sola agencia. Un usuario NO DEBE ver ni modificar el contenido público de otra agencia.
- **FR-021**: El sistema DEBE registrar quién publicó, despublicó o reemplazó la imagen principal de una ficha, y cuándo lo hizo.
- **FR-022**: Antes de que la página deje de usar su contenido actual, el sistema DEBE tener publicada una ficha por cada oferta, cada alojamiento y cada yate que la página muestra en ese momento. Cada oferta copiada DEBE quedar como experiencia y cada alojamiento como alojamiento. La copia de una oferta o alojamiento DEBE conservar el identificador público, los textos en español e inglés, la imagen que ya ve el visitante y los precios mostrados. La oferta conserva su categoría. El alojamiento conserva además su galería y sus opiniones. Cada yate copiado DEBE quedar como experiencia y conservar nombre, descripción, imagen, capacidades y características en español e inglés.
- **FR-023**: Después del cambio de fuente, la página DEBE mostrar únicamente fichas publicadas en el panel en el catálogo, el hospedaje y los yates. NO DEBE seguir mostrando el listado anterior.
- **FR-024**: El cambio de fuente NO DEBE realizarse si falta alguna oferta, alojamiento o yate vigente por publicar. Hasta entonces, la página DEBE seguir mostrando su contenido actual.
- **FR-025**: El identificador público de cada ficha copiada DEBE ser el que la página ya usa, para que la dirección pública se conserve. El gestor puede reemplazar después la imagen copiada mediante una carga nueva.
- **FR-026**: La ficha pública de un yate DEBE incluir identificador público, nombre en español, nombre en inglés, descripción en español, descripción en inglés, imagen principal, al menos una capacidad y al menos una característica. Cada capacidad y cada característica DEBE tener texto en español e inglés, en el mismo orden. El símbolo de cada línea, cuando se informa, DEBE ser uno de los que la página de yates ya usa: personas, cama, ducha, gota, sillón, barco, cocina, estrella, aire acondicionado, grupo, sol, música o mapa.
- **FR-027**: Un yate publicado NO DEBE aparecer en el listado de ofertas ni en hospedaje. El texto de presentación y los destinos isleños de la página de yates quedan fuera de esta copia.
- **FR-028**: Al copiar una oferta o un alojamiento, el sistema DEBE crear la tarifa inicial con el monto y la moneda del precio que el visitante ve hoy. Si también se muestra un precio anterior, ese valor NO DEBE usarse como tarifa. En un alojamiento, esa tarifa inicial es por noche.
- **FR-029**: Operador y Administrador DEBEN poder marcar y desmarcar como agotada una ficha publicada de oferta, alojamiento o yate. Una ficha agotada DEBE seguir visible con una etiqueta de agotado. El visitante NO DEBE poder iniciar una solicitud nueva de ese producto mientras esté agotado.
- **FR-030**: La ficha de yate PUEDE incluir un precio mostrado y una moneda. Si no se informan, la página de yates NO DEBE mostrar un precio. La copia de un yate que hoy no muestra precio NO DEBE inventarlo. Para publicar el yate, el producto DEBE poder activarse con las reglas de tarifas del catálogo.

### Key Entities

- **Ficha pública de oferta**: Contenido con el que la página presenta una experiencia o un paquete predefinido. Campos: identificador público, nombre y nombre en inglés, categoría, descripción y descripción en inglés, imagen, inclusiones e inclusiones en inglés, ubicación, y de forma opcional punto de encuentro, horario, duración, máximo de huéspedes, advertencias y advertencias en inglés, destacada, calificación, precio mostrado, precio anterior, moneda y marca de agotado. Se relaciona con un único producto interno de tipo experiencia o paquete.
- **Ficha pública de alojamiento**: Contenido con el que la página de hospedaje presenta un alojamiento. Campos: identificador público, nombre y nombre en inglés, tipo, ubicación y ubicación en inglés, barrio y barrio en inglés, descripción y descripción en inglés, precio por noche, moneda, máximo de huéspedes, habitaciones, baños, imagen, galería, amenidades, etiquetas, calificación, cantidad de opiniones, opiniones, enlace de mapa, destacada y marca de agotado. Se relaciona con un único alojamiento interno.
- **Ficha pública de yate**: Contenido con el que la página de yates presenta una embarcación. Campos: identificador público, nombre y nombre en inglés, descripción y descripción en inglés, imagen, capacidades, características, precio mostrado opcional, moneda opcional y marca de agotado. Cada capacidad o característica tiene texto en español, texto en inglés y un símbolo opcional. Se relaciona con una única experiencia interna y no usa la ficha de oferta del catálogo.
- **Disponibilidad pública**: Marca de una ficha publicada. Puede estar disponible o agotada. Agotada no equivale a despublicada ni a producto inactivo: la ficha sigue visible y deja de aceptar solicitudes nuevas.
- **Categoría pública**: Agrupación con la que el visitante filtra el catálogo. Campos: identificador estable, nombre en español, nombre en inglés y estado activa o inactiva.
- **Imagen de contenido**: Archivo de imagen cargado por el gestor y asociado a una ficha como foto principal o como elemento de galería. Campos: referencia pública, orden y ficha a la que pertenece.
- **Opinión de huésped**: Comentario mostrado en un alojamiento. Campos: autor, calificación, texto, texto en inglés y fecha.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un gestor publica una oferta completa, con textos en español e inglés, imagen y precio mostrado, en menos de 8 minutos.
- **SC-002**: El 100% de las ofertas y alojamientos visibles en la página pública muestran exactamente el contenido publicado, incluida la imagen vigente.
- **SC-003**: El 100% de los intentos de publicar sin imagen, sin los textos obligatorios en ambos idiomas o con listas bilingües de distinta longitud son rechazados con un mensaje que indica qué corregir.
- **SC-004**: En una revisión de las ofertas publicadas, el 100% de las visitas en inglés muestran nombre, descripción e inclusiones en inglés, y el 100% de las visitas en español muestran esos mismos elementos en español.
- **SC-005**: El 100% de las fichas despublicadas o de productos desactivados dejan de estar disponibles para el visitante en la siguiente consulta de la página, sin cambiar cotizaciones ya emitidas.
- **SC-006**: Un gestor reemplaza la imagen principal de una oferta publicada y el visitante ve la imagen nueva en la siguiente consulta, sin perder el resto de la ficha.
- **SC-007**: El 100% de las ofertas y alojamientos visibles en la página el día del cambio siguen visibles después, en la misma dirección pública. El 100% de los yates visibles ese día siguen visibles en la sección de yates.
- **SC-008**: Después del cambio, el 100% de lo que el visitante ve en el catálogo, en hospedaje y en el listado de yates corresponde a una ficha publicada en el panel.
- **SC-009**: El 100% de las ofertas y alojamientos copiados quedan con una tarifa inicial igual al precio actual que el visitante veía, no al precio anterior.
- **SC-010**: El 100% de las fichas marcadas como agotadas siguen visibles con esa etiqueta y el 100% de los intentos de iniciar una solicitud nueva de ese producto son rechazados mientras la etiqueta siga puesta.

## Assumptions

- Esta mejora extiende el catálogo del spec 002. Experiencias, alojamientos y paquetes predefinidos siguen creándose y tarifándose como hasta ahora. Esta especificación añade la ficha que ve el visitante en la página pública.
- Las experiencias y los paquetes predefinidos que se ofrecen en el catálogo se publican con la estructura de oferta del catálogo público. Los alojamientos se publican con la estructura de la sección de hospedaje. Los yates se publican con la estructura de la sección de yates y, por dentro, son experiencias. Los complementos del catálogo no tienen ficha propia en la página; si deben mencionarse, el gestor los escribe dentro de las inclusiones.
- El texto de presentación y los destinos isleños de la página de yates, igual que las notas, guías y páginas informativas, quedan fuera de esta mejora. Ese contenido editorial sigue perteneciendo a la gestión de contenido prevista en el spec 007.
- El precio mostrado es el precio de vitrina. Solo la copia inicial de una oferta o un alojamiento lo usa como tarifa. Después, cambiar el precio de vitrina no sustituye el esquema de tarifas ni altera cotizaciones o reservas ya emitidas.
- La página sigue presentando cada idioma por sí misma. El panel solo garantiza que el contenido publicado esté completo en español e inglés.
- El tamaño máximo de cada imagen es 10 MB. Los formatos aceptados son los de uso habitual en la página: JPEG, PNG y WebP.
- Las categorías iniciales conservan los identificadores que la página ya usa: islas, baru, tierra_bomba, compartidos, cultural, aventura, baile y premium.
- Cada agencia administra solo su contenido público. La página actual de Cartagena Tailored Travel consume el contenido publicado de su agencia.
- El cambio de fuente ocurre una sola vez: primero se copian y publican las ofertas, alojamientos y yates vigentes; después la página deja su listado anterior y muestra solo el panel.
- La página de yates hoy no muestra un precio. La copia no inventa ese precio. El gestor puede agregarlo después, junto con una etiqueta de agotado. Para publicar el yate, el producto debe poder activarse con las reglas de tarifas que el catálogo ya exige.
- Las fichas copiadas quedan disponibles. La etiqueta de agotado solo aparece cuando el gestor la marca. Agotado no despublica la ficha ni desactiva el producto.
- La imagen copiada puede ser la que la página ya muestra. No hace falta volver a cargarla para completar la copia. Una carga posterior la reemplaza.
- Guardar un borrador no exige la ficha completa. Publicar sí exige los campos obligatorios de esta especificación.
- Reordenar la galería de un alojamiento define el orden en que el visitante ve las fotos.
