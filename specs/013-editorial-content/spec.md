# Feature Specification: Blog multiagencia en el CMS

**Feature Branch**: `013-editorial-content`

**Created**: 2026-10-26

**Updated**: 2026-11-17 (reformulado como módulo de blog multiagencia del panel; aclaraciones D-1 a D-3)

**Status**: Implemented (2026-11-17)

**Input**: User description: "Revisa y actualiza el spec existente `013-editorial-content` para definir un módulo de blog multiagencia en el CMS de `ctt-app`. Una persona autorizada de una agencia puede escribir, editar, publicar y retirar artículos desde el panel. Los artículos publicados aparecen en el sitio público conectado a esa agencia sin que su equipo tenga que modificar código para cada publicación."

> **Historial de alcance**
>
> - **2026-10-26**: La versión original pedía que el sitio público mostrara blog, guías, destinos y políticas leídos desde WordPress.
> - **2026-11-13**: Se marcó como *Superseded*. Ese contenido lo mostraba el sitio de Cartagena Tailored Travel, y esta app no leía WordPress.
> - **2026-11-17**: Se reabre con otro objetivo. El panel pasa a ser el lugar donde cada agencia **escribe y publica** sus artículos, y el sitio conectado a la agencia los **lee** con el modelo de integración de 016. Esta app sigue sin construir un sitio público propio.
>
> La trazabilidad con la versión anterior está en [Trazabilidad con la versión anterior de 013](#trazabilidad-con-la-versión-anterior-de-013).

> **Gobierno (resuelto 2026-11-17)**
>
> La autoría del blog en el panel contradecía la Constitución (*Content Management*: «WordPress SHALL be used… for Blog articles») y el mainspec 22.1. Por ser un cambio de **Nivel 3**, se resolvió con [ADR-0004](../../docs/adr/0004-blog-authoring-in-panel.md) (*Accepted*), que también hace de propuesta de RFC.
>
> Con ese ADR se enmendaron la Constitución y los apartados 22.1, 27.1 y 30.1 del mainspec: el blog se gestiona en el CMS del panel por agencia, y WordPress sigue para landing pages, marketing y páginas SEO. Guías, destinos y políticas quedan para un ADR posterior.

## Clarifications

### Session 2026-11-17

- Q: ¿Cómo se relaciona un artículo con los idiomas que la agencia ofrece en su perfil público? → A: Un solo artículo y un solo slug, con versión en español y en inglés, como las fichas del catálogo. Para publicar se exige cada idioma que la agencia ofrece.
- Q: Al editar un artículo publicado, ¿el cambio se ve en la web al guardar o espera a «Publicar cambios»? → A: La web mantiene la versión publicada. Las ediciones se guardan como una revisión en curso, que solo llega a la web al publicarla y se puede descartar.
- Q: Para una agencia que ya tiene su blog en WordPress, ¿qué pasa con esos artículos? → A: Se migra con cambio de fuente, como en 016 US5. Se copian los artículos conservando sus slugs y, hasta completar la copia, el sitio sigue leyendo WordPress. Al final, el panel es la única fuente del blog.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Escribir y guardar un borrador (Priority: P1)

Como persona autorizada de una agencia, quiero crear un artículo desde la sección «Blog» del panel y guardarlo aunque esté incompleto, para poder escribirlo en varias sesiones sin perder trabajo ni publicarlo antes de tiempo.

**Why this priority**: Sin borradores no hay flujo editorial. Es la base de todas las demás historias y ya entrega valor: la agencia tiene un solo lugar donde preparar su contenido.

**Independent Test**: Una persona autorizada crea un artículo solo con el título en español y guarda. Cierra sesión, vuelve a entrar y lo encuentra en el listado del Blog como borrador. Añade el resumen, el contenido, las imágenes y la versión en inglés, y guarda de nuevo. En ningún momento aparece en el sitio público.

**Acceptance Scenarios**:

1. **Given** una persona autorizada en la sección «Blog», **When** crea un artículo con el título en uno solo de los idiomas y guarda, **Then** el artículo queda guardado como borrador y aparece en el listado de su agencia con estado «Borrador».
2. **Given** un borrador incompleto guardado, **When** la persona vuelve más tarde al panel y lo abre, **Then** encuentra todo lo que guardó en cada idioma y puede seguir editándolo.
3. **Given** un borrador con contenido enriquecido (párrafos, títulos, listas, enlaces e imágenes), **When** la persona añade texto alternativo a cada imagen y guarda, **Then** el contenido y los textos alternativos se conservan tal como los dejó.
4. **Given** el listado del Blog, **When** la persona lo abre, **Then** ve solo los artículos de su agencia, con título, estado, idiomas completos y fecha de última modificación, y puede filtrar por estado.

---

### User Story 2 - Publicar un artículo y verlo en el sitio de la agencia (Priority: P1)

Como persona autorizada para publicar, quiero publicar un artículo completo y que aparezca en el sitio conectado a mi agencia, en su listado y en su propia dirección, sin pedir cambios de código al equipo técnico.

**Why this priority**: Es el objetivo central del módulo: que publicar no dependa de un desarrollador.

**Independent Test**: En una agencia que ofrece español e inglés, se publica un artículo completo en los dos idiomas. Antes de que venza el plazo de visibilidad, el sitio conectado lo muestra en el listado (ordenado por fecha de publicación) y en su página individual, en ambos idiomas, con título y descripción para buscadores. Otro artículo de la misma agencia que sigue en borrador no aparece en el listado ni se abre por dirección directa.

**Acceptance Scenarios**:

1. **Given** un borrador completo en todos los idiomas que ofrece la agencia, **When** una persona autorizada lo publica, **Then** el artículo pasa a «Publicado», recibe su fecha de publicación y aparece en el listado público y en su dirección dentro del plazo de visibilidad.
2. **Given** un borrador al que le falta algún campo obligatorio, el texto alternativo de alguna imagen o la versión en un idioma que la agencia ofrece, **When** se intenta publicar, **Then** la publicación se rechaza, se indica cada campo faltante por idioma y el artículo sigue en borrador sin cambios.
3. **Given** varios artículos publicados, **When** el sitio conectado pide el listado, **Then** los recibe del más reciente al más antiguo por fecha de publicación.
4. **Given** un artículo en borrador, **When** alguien pide su dirección pública directa, **Then** obtiene la misma respuesta que para un artículo inexistente.
5. **Given** un artículo publicado, **When** el sitio conectado lo pide, **Then** recibe, por cada idioma publicado, título, resumen, texto alternativo de la portada, contenido, título SEO y descripción SEO, además de la portada y la fecha de publicación, y nada interno de la agencia.

---

### User Story 3 - Aislamiento entre agencias y permisos de publicación (Priority: P1)

Como agencia, quiero que mis artículos solo los puedan ver, editar o publicar las personas autorizadas de mi agencia, y que mi sitio muestre solo mis artículos aunque otra agencia use el mismo slug.

**Why this priority**: Es un requisito de seguridad de una plataforma multiagencia. Una fuga entre agencias o una publicación no autorizada daña la reputación de la agencia afectada.

**Independent Test**: Dos agencias publican un artículo con el mismo slug y cada sitio muestra el suyo. Un Agente intenta publicar y es rechazado. Un usuario de la agencia B intenta abrir, editar, publicar o retirar un artículo de la agencia A y es rechazado sin que el artículo cambie.

**Acceptance Scenarios**:

1. **Given** la agencia A y la agencia B, cada una con un artículo publicado con slug `que-ver-en-cartagena`, **When** el sitio de A pide ese slug con su credencial, **Then** recibe el artículo de A. **When** el sitio de B pide el mismo slug, **Then** recibe el de B.
2. **Given** un usuario con rol Agente, **When** intenta crear, editar, publicar o retirar un artículo, **Then** la operación se rechaza y el artículo no cambia.
3. **Given** un Operador o Administrador de la agencia B, **When** intenta leer, editar, publicar o retirar un artículo de la agencia A, **Then** la operación se rechaza como si el artículo no existiera para él.
4. **Given** una credencial pública revocada, vencida o inexistente, **When** se pide el listado o un artículo, **Then** la respuesta es la misma respuesta genérica de acceso no válido que define 016.

---

### User Story 4 - Editar un artículo publicado sin romper su dirección (Priority: P2)

Como persona autorizada, quiero preparar cambios a un artículo ya publicado sin que el sitio muestre una edición a medias, y publicarlos cuando estén listos, para mantenerlo vigente sin que cambie su dirección ni se pierdan los enlaces que otros sitios ya tienen hacia él.

**Why this priority**: Los artículos envejecen (temporadas, normas locales, precios orientativos). Conservar la dirección protege el posicionamiento en buscadores y los enlaces compartidos. Separar la revisión de la versión publicada evita exponer trabajo incompleto.

**Independent Test**: Se edita el contenido de un artículo publicado y se guarda sin publicar. El sitio sigue mostrando la versión anterior. Se publican los cambios y, dentro del plazo de visibilidad, la misma dirección muestra la versión nueva. En otra prueba se descartan los cambios y el panel vuelve a la versión publicada. El slug no se puede cambiar.

**Acceptance Scenarios**:

1. **Given** un artículo publicado, **When** una persona autorizada lo edita y guarda, **Then** los cambios quedan como revisión en curso, el artículo muestra en el panel la marca «Cambios sin publicar» y el sitio sigue mostrando la versión publicada.
2. **Given** una revisión en curso incompleta, **When** se guarda, **Then** se acepta igual que un borrador. **When** se intenta «Publicar cambios», **Then** se valida igual que una publicación y, si falta algo, se rechaza sin tocar la versión publicada.
3. **Given** una revisión en curso completa, **When** una persona autorizada publica los cambios, **Then** la misma dirección muestra la versión nueva dentro del plazo de visibilidad, y el artículo conserva su fecha de publicación original y su posición en el orden.
4. **Given** una revisión en curso, **When** una persona autorizada descarta los cambios, **Then** la revisión se elimina y el panel vuelve a mostrar la versión publicada sin cambios.
5. **Given** un artículo que ya se publicó alguna vez, **When** alguien intenta cambiar su slug, **Then** el panel no lo permite y explica que el slug quedó fijo al publicarse.

---

### User Story 5 - Retirar un artículo (Priority: P2)

Como persona autorizada para publicar, quiero retirar un artículo publicado, para que deje de verse en el sitio cuando su contenido ya no sea correcto, sin perderlo del panel.

**Why this priority**: Es la forma de corregir un error o de quitar contenido caducado. Sin ella, la única salida sería pedir un cambio técnico.

**Independent Test**: Se retira un artículo publicado. Dentro del plazo de visibilidad, desaparece del listado y su dirección directa da la misma respuesta que un artículo inexistente. En el panel sigue disponible como «Retirado» y se puede volver a publicar con el mismo slug.

**Acceptance Scenarios**:

1. **Given** un artículo publicado, **When** una persona autorizada lo retira, **Then** queda en estado «Retirado», desaparece del listado público y su dirección deja de mostrar el contenido dentro del plazo de visibilidad.
2. **Given** un artículo retirado, **When** alguien pide su dirección pública, **Then** recibe la misma respuesta que para un artículo inexistente.
3. **Given** un artículo retirado, **When** una persona autorizada lo vuelve a publicar, **Then** reaparece en la misma dirección con su fecha de publicación original.
4. **Given** un artículo publicado con una revisión en curso, **When** se retira, **Then** la revisión se conserva en el panel y no llega a la web.

---

### User Story 6 - Migrar el blog existente desde WordPress (Priority: P2)

Como responsable de una agencia que ya publica su blog en WordPress (como CTT), quiero copiar mis artículos al panel conservando sus direcciones y pasar el sitio a la nueva fuente solo cuando la copia esté completa, para no perder posicionamiento ni dejar enlaces rotos durante el cambio.

**Why this priority**: Sin una migración segura, CTT no puede adoptar el módulo sin romper su blog actual. Las agencias nuevas no la necesitan, por eso no es P1.

**Independent Test**: Se marca una agencia como «blog migrado». Mientras falte copiar algún artículo que su sitio muestra, el cambio de fuente se rechaza y el sitio sigue leyendo WordPress. Al completar la copia con los mismos slugs, el cambio de fuente se acepta y cada dirección antigua muestra el artículo desde el panel. Otra agencia sin blog previo publica directamente sin pasar por este flujo.

**Acceptance Scenarios**:

1. **Given** una agencia marcada como «blog migrado» a la que le falta copiar un artículo que su sitio muestra hoy, **When** se intenta completar el cambio de fuente, **Then** se rechaza, se indica qué artículos faltan y el sitio sigue mostrando el blog actual.
2. **Given** la copia completa con los mismos slugs y fechas de publicación originales, **When** se completa el cambio de fuente, **Then** el sitio lee el blog solo desde el panel y cada dirección antigua sigue mostrando su artículo.
3. **Given** una agencia sin blog previo, **When** publica un artículo válido, **Then** no se le exige ninguna copia ni cambio de fuente.

---

### Edge Cases

- **Slug repetido en la misma agencia**: crear o renombrar un borrador con un slug que ya usa otro artículo de la agencia (en cualquier estado) se rechaza con un mensaje claro. El mismo slug en otra agencia no genera conflicto.
- **Slug inválido**: solo se aceptan minúsculas sin tilde, números y guiones simples, sin guion inicial ni final. El sistema puede proponer un slug a partir del título en español, que la persona puede cambiar mientras el artículo no se haya publicado nunca.
- **Slug heredado de WordPress que no cumple el formato**: en una migración se acepta tal cual para conservar la dirección existente. La excepción solo vale para artículos copiados durante la migración, no para artículos nuevos.
- **Agencia que cambia sus idiomas ofrecidos**: si deja de ofrecer un idioma, ese idioma deja de entregarse en la lectura pública. Si empieza a ofrecer uno nuevo, los artículos ya publicados siguen visibles en sus idiomas completos, y la próxima publicación de cambios de cada artículo exige el idioma nuevo.
- **Imagen sin texto alternativo**: se puede guardar en borrador o en revisión. Bloquea la publicación hasta completarlo en cada idioma ofrecido, salvo que la imagen se marque explícitamente como decorativa.
- **Imagen inválida o demasiado grande**: se rechaza al subirla y el resto del borrador o de la revisión se conserva.
- **Contenido con código o elementos activos**: el contenido enriquecido solo admite texto con formato, títulos, listas, citas, enlaces e imágenes. Cualquier script, formulario o contenido embebido se descarta y no llega nunca al sitio público.
- **Borrar**: un artículo que nunca se publicó se puede eliminar. Uno que se publicó alguna vez solo se puede retirar, para conservar su slug y su historial.
- **Edición simultánea**: si dos personas editan el mismo borrador o la misma revisión y una guarda después de que la otra ya guardó, el sistema avisa del conflicto y no sobrescribe en silencio.
- **Retiro inmediato tras publicar**: si se publica y se retira dentro del mismo plazo de visibilidad, al terminar ese plazo el artículo no está visible.
- **Precio escrito en el artículo**: un precio mencionado en el texto no cambia tarifas, precios de vitrina, solicitudes ni reservas (se conserva el FR-005 original).
- **Agencia sin artículos publicados**: el listado público llega vacío, sin error, y el sitio decide cómo presentarlo.
- **Agencia suspendida o inactiva**: su credencial pública deja de servir artículos, igual que deja de servir el catálogo según 016.
- **Fallo al leer el blog**: si la lectura de artículos falla, la lectura del catálogo y el envío de solicitudes de la misma agencia siguen funcionando (se conserva el espíritu de US3 original).

## Requirements *(mandatory)*

### Functional Requirements

**Gestión en el panel**

- **FR-001**: El panel DEBE ofrecer una sección «Blog» donde las personas autorizadas listen los artículos de su agencia con:
  - título;
  - estado (Borrador, Publicado o Retirado);
  - la marca «Cambios sin publicar» cuando haya una revisión en curso;
  - los idiomas completos;
  - la fecha de última modificación y, cuando exista, la de publicación.

  Las personas autorizadas DEBEN poder filtrar el listado por estado.
- **FR-002**: Las personas autorizadas DEBEN poder crear artículos en estado Borrador y guardarlos con solo el título en un idioma. El resto de los campos son opcionales mientras el artículo esté en borrador.
- **FR-003**: Cada artículo DEBE tener un único slug y una portada compartidos por todos sus idiomas. Por cada idioma (español e inglés) DEBE admitir:
  - título;
  - resumen;
  - texto alternativo de la portada;
  - contenido enriquecido: párrafos, títulos, listas, citas, enlaces e imágenes, cada imagen con texto alternativo o marcada como decorativa;
  - título SEO;
  - descripción SEO.
- **FR-004**: Al publicar o al publicar cambios, el sistema DEBE exigir:
  - un slug válido y una portada;
  - en **cada idioma que la agencia ofrece** en su perfil público (016 FR-019): título, resumen, texto alternativo de la portada, contenido no vacío y texto alternativo (o la marca de decorativa) en cada imagen.

  Si falta algo, DEBE rechazar la operación listando cada campo faltante por idioma, sin cambiar el estado del artículo ni su versión publicada.
- **FR-005**: El título SEO y la descripción SEO DEBEN ser opcionales. Si faltan en un idioma, la versión pública de ese idioma DEBE usar el título y el resumen del artículo.
- **FR-006**: Los límites de longitud DEBEN validarse al guardar, en cada idioma: título hasta 120 caracteres, resumen hasta 300, título SEO hasta 70 y descripción SEO hasta 160.
- **FR-007**: El contenido enriquecido NO DEBE poder contener scripts, formularios ni contenido embebido ejecutable. Lo que no esté permitido DEBE descartarse antes de guardarse y nunca DEBE llegar a la versión pública.
- **FR-008**: Las personas autorizadas DEBEN poder retirar un artículo publicado y volver a publicar uno retirado.
- **FR-009**: Un artículo que nunca se publicó DEBE poder eliminarse. Uno que se publicó alguna vez NO DEBE poder eliminarse, solo retirarse.
- **FR-010**: Si alguien intenta guardar un borrador o una revisión que otra persona modificó después de que él lo abrió, el sistema DEBE avisar del conflicto y NO DEBE sobrescribir esos cambios sin confirmación explícita.

**Revisiones de artículos publicados**

- **FR-011**: Editar un artículo publicado o retirado NO DEBE cambiar su versión publicada. Los cambios DEBEN guardarse como una única revisión en curso por artículo, que admite datos incompletos igual que un borrador.
- **FR-012**: Las personas autorizadas DEBEN poder «Publicar cambios», que reemplaza la versión publicada por la revisión tras validarla según FR-004. También DEBEN poder «Descartar cambios», que elimina la revisión sin tocar la versión publicada.
- **FR-013**: La revisión en curso NUNCA DEBE entregarse en la lectura pública.

**Slugs, fechas y direcciones**

- **FR-014**: El slug DEBE ser único dentro de cada agencia, entre artículos en cualquier estado. Agencias distintas DEBEN poder usar el mismo slug sin conflicto.
- **FR-015**: El slug DEBE contener solo minúsculas sin tilde, números y guiones simples, sin guion al inicio ni al final, con hasta 120 caracteres. La única excepción son los slugs copiados en una migración (FR-031).
- **FR-016**: El slug DEBE quedar fijo desde la primera publicación del artículo. Editar, publicar cambios, retirar o volver a publicar NO DEBE cambiarlo.
- **FR-017**: La fecha de publicación DEBE asignarse en la primera publicación y conservarse al publicar cambios, retirar y republicar. La fecha de última actualización pública DEBE cambiar cada vez que se publican cambios.

**Permisos y aislamiento**

- **FR-018**: Administrador y Operador DEBEN poder crear, editar, publicar, publicar cambios, descartar cambios, retirar y eliminar artículos de su agencia (con la regla de FR-009). Agente NO DEBE poder hacer ninguna de esas acciones ni ver la sección Blog. Esto sigue la regla de 016 para el contenido público (FR-003, FR-007 y FR-020 de 016).
- **FR-019**: Ningún usuario DEBE poder listar, abrir, editar, publicar, retirar ni eliminar artículos de otra agencia. El intento DEBE responder como si el artículo no existiera.
- **FR-020**: El sistema DEBE registrar quién publicó, publicó cambios, retiró o eliminó un artículo, en qué agencia y cuándo. El registro DEBE poder consultarlo un Administrador autorizado, sin incluir el contenido completo del artículo.

**Lectura pública**

- **FR-021**: El sitio conectado DEBE poder leer el blog de una agencia con el mismo modelo de integración que define 016: la clave pública de la agencia o, solo para CTT y durante su transición, su identificador de organización.
- **FR-022**: La lectura pública DEBE devolver solo la versión publicada de los artículos en estado Publicado de la agencia resuelta. Nunca DEBE devolver borradores, revisiones en curso, artículos retirados, artículos de otra agencia, usuarios, correos ni notas internas.
- **FR-023**: La lectura pública DEBE entregar solo los idiomas que la agencia ofrece en ese momento. El sitio consumidor elige qué idioma mostrar.
- **FR-024**: El listado público DEBE ordenar los artículos por fecha de publicación, del más reciente al más antiguo, y entregar por cada uno al menos slug, portada, fecha de publicación y, por idioma, título, resumen y texto alternativo de la portada. DEBE poder pedirse por páginas.
- **FR-025**: La lectura de un artículo por slug DEBE entregar la portada, la fecha de publicación, la fecha de última actualización pública y, por idioma, título, resumen, texto alternativo de la portada, contenido con sus textos alternativos, título SEO y descripción SEO.
- **FR-026**: Pedir un slug que no existe, que está en borrador, que fue retirado o que pertenece a otra agencia DEBE producir la misma respuesta de «no encontrado», sin revelar cuál de esos casos se dio.
- **FR-027**: La plataforma NO DEBE imponer el formato de la dirección pública. Entrega el slug, y cada sitio consumidor arma su propia ruta por idioma (por ejemplo `/blog/<slug>` y `/en/blog/<slug>`).
- **FR-028**: Una credencial inválida, revocada, vencida o de una agencia no activa DEBE recibir la respuesta genérica de acceso no válido de 016.

**Plazo de visibilidad**

- **FR-029**: Una publicación, una publicación de cambios o un retiro DEBE reflejarse en la lectura pública de la agencia en un plazo máximo de **5 minutos**. Es el mismo plazo que 014 fijó para las fichas del catálogo.

**Migración desde un blog existente**

- **FR-030**: Una agencia con un blog previo DEBE poder marcarse como «blog migrado». Mientras no complete el cambio de fuente, su sitio DEBE seguir leyendo el blog anterior, y los artículos que publique en el panel NO DEBEN reemplazarlo.
- **FR-031**: Los artículos copiados en una migración DEBEN conservar su slug original, aunque no cumpla FR-015, y su fecha de publicación original.
- **FR-032**: Completar el cambio de fuente DEBE requerir un artículo publicado en el panel por cada artículo que el sitio vigente muestra, con el mismo slug. Si falta alguno, el cambio DEBE rechazarse indicando cuáles faltan, y el sitio DEBE seguir mostrando el blog anterior.
- **FR-033**: Tras el cambio de fuente, el panel DEBE ser la única fuente del blog de esa agencia.
- **FR-034**: Una agencia sin blog previo DEBE poder publicar artículos directamente, sin cumplir ninguna regla de copia.
- **FR-035**: El sistema DEBE registrar quién marcó una agencia como «blog migrado» y quién completó el cambio de fuente, y cuándo.

**Separación de datos comerciales y disponibilidad**

- **FR-036**: El blog NO DEBE ser fuente de productos, tarifas, disponibilidad, clientes, solicitudes, cotizaciones ni reservas. Publicar o editar artículos NO DEBE modificar ninguno de esos datos (se conserva el FR-005 original).
- **FR-037**: Un fallo en la lectura del blog NO DEBE impedir la lectura del catálogo publicado ni el envío de solicitudes de la misma agencia (se conserva el FR-006 original).

### Key Entities

- **Artículo**: Pieza editorial de una agencia.
  - Datos comunes: agencia propietaria, slug, portada, estado (Borrador, Publicado o Retirado), fecha de primera publicación, fecha de última actualización pública, fechas de creación y modificación, autor de la última modificación, y si proviene de una migración.
  - Tiene una versión publicada (cuando se ha publicado) y, como máximo, una revisión en curso.
- **Versión de idioma del artículo**: Contenido de un artículo en español o en inglés: título, resumen, texto alternativo de la portada, contenido enriquecido, título SEO y descripción SEO. Existe tanto en la versión publicada como en la revisión en curso.
- **Revisión en curso**: Cambios guardados sobre un artículo publicado o retirado que aún no llegan a la web. Se publica o se descarta como un todo.
- **Imagen de artículo**: Imagen de la portada o del contenido. Pertenece a un artículo y a su agencia, y tiene texto alternativo por idioma o la marca de decorativa.
- **Fuente del blog de la agencia**: Indica si la agencia viene de un blog previo («blog migrado») y si ya completó el cambio de fuente. Es la misma idea que la configuración de fuente pública de 016, aplicada al blog.
- **Evento editorial**: Registro de auditoría de publicación, publicación de cambios, retiro, eliminación, marca de migración y cambio de fuente, con actor, agencia, artículo y momento.
- **Agencia, perfil público y clave pública** (de 016): Definen el límite de aislamiento, los idiomas ofrecidos y la credencial con la que el sitio conectado lee el blog.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Una persona autorizada redacta y publica un artículo nuevo de unas 800 palabras por idioma, con portada y dos imágenes, en menos de 20 minutos por idioma, sin ayuda técnica, en al menos 9 de 10 intentos.
- **SC-002**: En una prueba de 20 publicaciones, publicaciones de cambios y retiros, el 100% se refleja en el sitio conectado en 5 minutos o menos.
- **SC-003**: En una revisión de 30 artículos (borradores, publicados y retirados de 3 agencias), el 100% de los borradores y retirados queda oculto en el listado y responde «no encontrado» por dirección directa, y el 100% de los publicados aparece solo en el sitio de su agencia.
- **SC-004**: En una prueba con 10 agencias que publican un artículo con el mismo slug, cada sitio muestra el artículo de su propia agencia en el 100% de los casos.
- **SC-005**: En una prueba de 20 operaciones de permisos, el 100% de las acciones de Agente y de usuarios de otra agencia se rechaza sin cambiar el artículo, y el 100% de las acciones permitidas de Operador y Administrador se completa.
- **SC-006**: En una revisión de 20 artículos publicados con una revisión en curso, el 100% sigue mostrando en la web su versión publicada hasta que se publican los cambios. Después de publicarlos, el 100% conserva su dirección y su fecha de publicación.
- **SC-007**: En 20 intentos de publicar artículos o cambios incompletos, incluidos los que no tienen un idioma ofrecido por la agencia, el 100% se rechaza con la lista de campos faltantes por idioma y ninguno llega a la web.
- **SC-008**: En una auditoría de 30 publicaciones, publicaciones de cambios y retiros, el 100% queda asociado a la agencia, el actor y el momento correctos.
- **SC-009**: En una revisión de 20 artículos con contenido pegado desde otras fuentes, ninguno muestra en el sitio público scripts, formularios ni contenido embebido ejecutable.
- **SC-010**: En una migración de prueba, el cambio de fuente se rechaza en el 100% de los intentos con al menos un artículo faltante. Tras completarlo, el 100% de las direcciones de artículos del blog anterior muestra el artículo correspondiente con su fecha original.

## Assumptions

- Esta app no construye un sitio público. El sitio de cada agencia (para CTT, https://www.cartagenatailoredtravel.com/) se encarga de presentar el listado y la página del artículo, sus rutas por idioma y su diseño. Esta especificación cubre la autoría en el panel y la lectura pública de lo publicado.
- La regla de permisos sigue el precedente de 009 y 016: Operador y Administrador gestionan y publican el contenido público, y Agente no lo modifica. Esta iteración no separa «redactar» de «publicar» entre Operador y Administrador. Si más adelante se quiere un flujo de revisión por terceros, será una ampliación.
- El plazo de 5 minutos se toma de 014 para que catálogo y blog tengan una sola expectativa de frescura. Si el sitio consumidor guarda su propia copia, debe respetar ese plazo (igual que en 014).
- Los idiomas posibles son español e inglés, los mismos que admite el perfil público de 016. Añadir otros idiomas queda fuera de esta iteración.
- Los límites de tamaño y formato de las imágenes son los mismos que ya rigen para las imágenes de las fichas públicas.
- La copia de los artículos durante una migración la puede hacer la agencia a mano o con ayuda de una importación. El mecanismo se define en `/speckit-plan`; esta especificación fija solo qué condiciones debe cumplir la copia.
- Los autores no se muestran en la versión pública. Si en el futuro se quiere una firma, será un campo editorial explícito, no el usuario interno.
- No hay programación de publicaciones a futuro, categorías ni etiquetas de blog, comentarios, ni búsqueda dentro del blog en esta iteración.
- No se pide cuenta al visitante para leer.

## Decisiones

Las tres decisiones que la versión del 2026-11-17 dejó abiertas se resolvieron en la sesión de aclaraciones del mismo día:

- **D-1 Idiomas**: un artículo bilingüe con un solo slug. Para publicar se exige cada idioma que ofrece la agencia (FR-003, FR-004, FR-023).
- **D-2 Cambios en artículos publicados**: revisión en curso separada de la versión publicada, con «Publicar cambios» y «Descartar cambios» (US4, FR-011 a FR-013).
- **D-3 Convivencia con WordPress**: migración con cambio de fuente, tras la cual el panel es la única fuente del blog (US6, FR-030 a FR-035).

El conflicto con la Constitución se resolvió con [ADR-0004](../../docs/adr/0004-blog-authoring-in-panel.md) (*Accepted*, 2026-11-17) y su enmienda. Landing pages, contenido de marketing y páginas SEO siguen en WordPress.

## Trazabilidad con la versión anterior de 013

| Elemento original (2026-10-26) | Estado en esta versión |
| --- | --- |
| US1 Publicar una página editorial | **Vigente y ampliada** en US1, US2, US4 y US5, ahora con autoría en el panel. |
| US2 Cuatro tipos (blog, guías, destinos, políticas) | **Reducida a artículos.** Guías, destinos y políticas quedan **fuera de esta iteración**. ADR-0004 los deja en WordPress hasta que un ADR posterior decida si serán otros tipos de este módulo. |
| US3 El sitio comercial sigue si el gestor falla | **Vigente** como FR-037 y caso límite «Fallo al leer el blog». |
| FR-001 / FR-002 Mostrar cuatro tipos en secciones propias | **Sustituidos** por FR-021 a FR-027 (solo artículos). Las secciones las arma el sitio consumidor. |
| FR-003 No publicado no es recuperable por dirección | **Vigente** como FR-022 y FR-026, ampliado a revisiones en curso, artículos retirados y artículos de otra agencia. |
| FR-004 Título, texto, imagen, fecha | **Vigente y ampliado** en FR-003 y FR-025 (bilingüe, texto alternativo y SEO). |
| FR-005 El gestor no es fuente de datos comerciales | **Vigente** como FR-036. |
| FR-006 / FR-007 Fallo del gestor no tumba catálogo ni solicitudes | **FR-006 vigente** como FR-037. **FR-007** (aviso en el sitio) pasa al sitio consumidor. |
| FR-008 Ocultar dejando de publicar | **Vigente** como FR-008 (retirar). |
| Supuesto «El gestor editorial es WordPress» | **Reemplazado para el blog** por D-3: tras la migración, el panel es la única fuente. Aprobado con ADR-0004 y la enmienda constitucional. |
| `tasks.md` (lectura de WordPress desde un shell Angular público) | **Obsoleto.** Se regenerará con `/speckit-tasks` después de `/speckit-plan`. |

## Dependencies

- **016 Base multiagencia del contenido público**: clave pública, transición del identificador de CTT, respuesta genérica de acceso no válido, idiomas ofrecidos del perfil público, roles de gestión del contenido público, modelo de cambio de fuente y auditoría.
- **014 Frescura pública**: plazo de 5 minutos como expectativa común de visibilidad.
- **001 Identidad y acceso**: roles Administrador, Operador y Agente, y aislamiento por agencia.
- **Gobierno**: ADR-0004 (*Accepted*) y enmienda de la Constitución (*Content Management*) y del mainspec (22.1, 27.1, 30.1), ya aplicadas.
