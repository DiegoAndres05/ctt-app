# Research: Blog multiagencia en el CMS

**Feature**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md) · **Date**: 2026-11-17

Cada decisión resuelve una incógnita del contexto técnico. Se prioriza reutilizar lo que ya existe en 009 y 016: fichas públicas, bucket de medios, fuente pública, clave pública y auditoría.

---

## Decisión 1: Contenido enriquecido como documento de bloques, no HTML

- **Decision**: El cuerpo de cada idioma se guarda como un documento JSON de bloques con una lista cerrada de tipos:
  - `paragraph`, `heading` (niveles 2 y 3), `list` (con o sin orden), `quote` e `image`.
  - El texto en línea admite solo tres marcas: negrita, cursiva y enlace (`http`, `https` o `mailto`).
  - La base de datos valida la estructura en cada guardado. Un bloque o una marca desconocida se descarta; una URL de enlace no permitida invalida el enlace y deja el texto.
  - La lectura pública entrega los mismos bloques.
- **Rationale**:
  - FR-007 y SC-009 exigen que nunca lleguen scripts, formularios ni contenido embebido. Con bloques tipados no hay HTML que sanear: lo que no es un bloque conocido no existe.
  - El servidor puede validar la estructura sin depender de un sanitizador de HTML en PL/pgSQL.
  - FR-004 pide «texto alternativo en cada imagen del contenido». Con bloques, eso es un campo del bloque `image` que se puede comprobar al publicar.
  - El sitio consumidor decide cómo pintar cada bloque, coherente con FR-027 (rutas y diseño del lado del sitio).
- **Alternatives considered**:
  - *HTML saneado en el cliente*: rechazada porque el cliente no es frontera de seguridad. Además, PL/pgSQL no tiene un sanitizador fiable.
  - *Markdown completo*: admite HTML en línea por diseño, y validar texto alternativo e imágenes exige parsearlo en el servidor.
  - *Entregar también HTML pre-renderizado*: se pospone. Si los sitios lo piden, se añade como campo derivado sin cambiar el almacenamiento.

## Decisión 2: Editor por bloques propio, sin dependencias nuevas

- **Decision**: El editor del panel es un componente Angular con Signal Forms. El usuario añade, ordena y elimina bloques:
  - Cada `paragraph`, `heading` y `quote` es un área de texto.
  - Las marcas en línea se escriben con una sintaxis mínima (`**negrita**`, `*cursiva*`, `[texto](url)`) que el cliente convierte a marcas al guardar.
  - El bloque `image` sube el archivo y pide el texto alternativo o la marca de decorativa.
  - Pegar contenido en un área de texto inserta solo texto plano.
  - Una vista previa pinta los bloques con el mismo mapeo que documenta el contrato público.
- **Rationale**:
  - El proyecto no tiene ninguna librería de texto enriquecido. La Constitución pide simplicidad y consistencia, y añadir un editor (ProseMirror, Tiptap, Quill) traería `contentEditable` y la superficie de XSS que la Decisión 1 elimina.
  - El pegado como texto plano cumple SC-009 por construcción.
  - Las formas por bloque encajan con el estilo de formularios del catálogo (Signal Forms, ADR-0001).
- **Alternatives considered**:
  - *Tiptap o ProseMirror*: mejor experiencia WYSIWYG, pero requiere una dependencia nueva, ADR y mapear su esquema a los bloques. Puede reconsiderarse si SC-001 (≤ 20 min por idioma) no se cumple en la validación con usuarios.
  - *`contentEditable` propio*: se descarta por la complejidad del manejo de selección y del pegado.

## Decisión 3: Artículo con versión publicada y revisión en curso (D-2)

- **Decision**:
  - Una tabla `blog_articles` guarda la identidad: agencia, slug, estado, fechas, origen migrado y un contador de versión para la concurrencia.
  - Una tabla `blog_article_contents` guarda como máximo dos contenidos por artículo, `kind = 'published' | 'working'`, cada uno con los campos de los dos idiomas.
  - **Borrador**: solo existe el contenido `working`.
  - **Publicar**: valida el `working` y lo mueve a `published`.
  - **Editar un publicado o un retirado**: crea el `working` copiando el `published` si aún no existe.
  - **Publicar cambios**: valida el `working` y reemplaza el `published`.
  - **Descartar cambios**: borra el `working`.
- **Rationale**:
  - Modela D-2 tal cual: la lectura pública solo mira `published` (FR-013 y FR-022), y la marca «Cambios sin publicar» es simplemente que exista `working` (FR-001).
  - El slug vive en el artículo, así que es único por agencia en cualquier estado (FR-014) y queda fijo desde `first_published_at` (FR-016).
- **Alternatives considered**:
  - *Historial completo de versiones*: el spec no pide historial ni restauración, y la auditoría (FR-020) ya registra quién publicó y cuándo.
  - *Columnas `draft_*` duplicadas en la misma fila*: duplica cada campo bilingüe y complica la validación común.

## Decisión 4: Bilingüe por columnas, con exigencia según el perfil (D-1)

- **Decision**: `blog_article_contents` tiene columnas `*_es` y `*_en` para título, resumen, texto alternativo de la portada, cuerpo, título SEO y descripción SEO. La portada es una sola por contenido.
  - Al publicar, `public.blog_required_locales(org)` toma los idiomas de `public_profiles.languages` (016) y exige los campos de cada uno.
  - Si la agencia no tiene perfil, se exige español.
  - La lectura pública entrega solo los idiomas ofrecidos en ese momento (FR-023).
- **Rationale**:
  - Es el mismo patrón de pares `name_es`/`name_en` que usan las fichas (`public_listings`), con un solo slug, como decidió D-1.
  - Leer los idiomas del perfil en el momento de publicar cubre el caso límite «la agencia cambia sus idiomas».
- **Alternatives considered**:
  - *Una fila por idioma*: más normalizado, pero D-1 eligió un artículo con un slug y las fichas ya usan columnas pareadas. Consistencia sobre innovación.

## Decisión 5: Concurrencia optimista con `revision`

- **Decision**: `blog_articles.revision` es un entero que cada guardado incrementa. Cada RPC de escritura recibe `p_expected_revision`. Si no coincide, devuelve `ARTICLE_CONFLICT` sin escribir. El panel muestra el aviso y deja elegir entre recargar o forzar, y forzar reenvía con la revisión actual.
- **Rationale**: Cumple FR-010 sin bloqueos pesimistas ni sesiones de edición. Es el patrón más simple que no sobrescribe en silencio.
- **Alternatives considered**: *Bloqueo de edición por usuario*: requiere expiración y liberación del bloqueo, y no aporta nada para un equipo pequeño.

## Decisión 6: Imágenes en el bucket existente `catalog-media`

- **Decision**: Portada e imágenes del cuerpo se suben a `catalog-media` bajo `{organization_id}/blog/{article_id}/{uuid}.{ext}`.
  - Se reutilizan las políticas de 026: escritura solo para `operator` y `admin` en el prefijo de su agencia. Límites: 10 MB, JPEG, PNG o WebP.
  - Un guardado rechaza referencias fuera del prefijo de la agencia y del artículo.
  - Solo los artículos migrados aceptan, además, URLs `https` externas (las imágenes ya alojadas en WordPress), igual que `external_ref` en `public_images`.
- **Rationale**:
  - El spec fija «los mismos límites de imagen que las fichas».
  - El bucket ya es de lectura pública y está aislado por prefijo de agencia para escribir.
  - Los nombres son UUID imposibles de adivinar. Una imagen de borrador no queda listada en ninguna lectura pública, aunque su URL no tenga control de acceso, igual que las imágenes de fichas en borrador hoy.
- **Alternatives considered**:
  - *Bucket privado con URLs firmadas*: las URLs firmadas caducan, lo que obliga a los sitios a refrescarlas y rompe la caché de 5 minutos. No hay un requisito de confidencialidad para las imágenes de borrador.
  - *Bucket `blog-media` separado*: duplica las políticas sin ganar aislamiento.

## Decisión 7: Lectura pública con RPC propias, separadas del catálogo

- **Decision**: Hay cuatro RPC públicas `SECURITY DEFINER` con `search_path = ''`:
  - `get_public_blog_by_key(p_key, p_page, p_page_size)` y `get_public_blog_article_by_key(p_key, p_slug)`.
  - `get_public_blog(p_organization_id, …)` y `get_public_blog_article(p_organization_id, p_slug)`, para la transición de CTT, resuelta con `require_organization_identifier_access`.
  - Con sesión, se usa la organización del JWT (vista previa), igual que `get_public_site`.
  - El artículo inexistente, en borrador, retirado o de otra agencia devuelve `{"found": false}`.
  - Una clave inválida devuelve `PUBLIC_ACCESS_UNAVAILABLE` (016).
- **Rationale**:
  - FR-037: un fallo del blog no debe tumbar el catálogo, así que el blog no viaja dentro de `get_public_site`.
  - Reutilizar `resolve_public_access_key` y `require_organization_identifier_access` hace que las reglas de clave y transición sean idénticas a las de 016 (FR-021 y FR-028).
  - La paginación (FR-024) tiene `p_page_size` por defecto de 12 y máximo de 50.
- **Alternatives considered**:
  - *Añadir `blog` a `get_public_site`*: acopla los fallos y agranda una respuesta que el sitio pide en cada página.
  - *Vistas públicas con RLS para `anon`*: la regla del repositorio es que `anon` no tiene acceso a tablas.

## Decisión 8: Frescura de 5 minutos sin caché del lado del servidor

- **Decision**:
  - La proyección del blog se calcula en cada llamada, como `get_public_site` (014).
  - El contrato exige al sitio consumidor que, si guarda copia, la invalide en 300 segundos o menos.
  - Cada respuesta incluye `public_updated_at` del artículo, y `generated_at` en el listado, para que el sitio pueda revalidar.
- **Rationale**:
  - Sin caché propia, la visibilidad es inmediata en el servidor y FR-029 depende solo del consumidor, igual que en 014.
  - Se evita invalidar caché al publicar, retirar o publicar cambios.
- **Alternatives considered**: *Tabla materializada o caché en el borde*: no hace falta con el volumen esperado (decenas o cientos de artículos por agencia) y añade estados de invalidación.

## Decisión 9: Migración desde WordPress con manifiesto y cambio de fuente (D-3)

- **Decision**:
  - **Fuente**: `public_blog_source` (una fila por agencia) guarda `migration_required`, `cutover_completed_at` y los actores.
  - **Manifiesto**: `public_blog_cutover_items` (agencia, slug) lista los artículos que el sitio actual muestra, igual que `public_cutover_items` de 009.
  - **Gestión**: el Administrador marca la agencia como «blog migrado», carga el manifiesto (texto con un slug por línea) y completa el cambio de fuente.
  - **Copia**: la hace Operador o Administrador desde el panel, creando un artículo con la opción «Artículo migrado». Esa opción solo aparece mientras la migración está abierta y permite un slug heredado fuera de formato (FR-031) y la fecha de publicación original.
  - **Cambio de fuente**: `complete_blog_cutover()` exige que cada slug del manifiesto tenga un artículo publicado. Si falta alguno, devuelve `BLOG_CUTOVER_INCOMPLETE` con la lista de los que faltan.
  - **Lectura pública**: mientras `migration_required` sea verdadero y no se haya completado el cambio, la lectura pública devuelve `source: "legacy"` y ningún artículo, para que el sitio siga leyendo WordPress (FR-030). Después devuelve `source: "panel"`.
- **Rationale**:
  - Es el mismo modelo que 016 US5 y 009 (`legacy` → `panel`), así que el sitio de CTT ya sabe interpretarlo.
  - Se reutiliza la regla «solo el Administrador decide la fuente» de 016.
- **Alternatives considered**:
  - *Reutilizar `public_source_config` del catálogo*: el blog y el catálogo migran en momentos distintos, y mezclarlos bloquearía uno por el otro.
  - *Importación automática desde la API REST de WordPress*: queda como mejora opcional (un script de operador que llama al mismo RPC de importación). No es requisito, porque el spec deja el mecanismo abierto y la copia manual cumple las condiciones.

## Decisión 10: Permisos y RLS

- **Decision**:
  - `blog_articles`, `blog_article_contents`, `public_blog_source` y `public_blog_cutover_items` tienen RLS.
  - `SELECT` solo para `operator` y `admin` de la propia agencia (FR-018 dice que Agente no ve la sección). Sin `INSERT`, `UPDATE` ni `DELETE` directos: toda escritura va por RPC.
  - `anon` no tiene acceso a las tablas.
  - Las RPC de artículos usan `require_catalog_manager_or_forbidden` (Operador o Administrador, el mismo control que las fichas); las de fuente y manifiesto, `require_tenant_admin_or_forbidden`.
  - Un artículo de otra agencia responde `NOT_FOUND` (FR-019).
  - En el panel, `roleGuard('operator')` en `/cms/blog` y `roleGuard('admin')` en `/cms/settings/blog-migration`.
- **Rationale**: Es la misma frontera que el resto del CMS (009 y 016): RLS más RPC, con el guardia de Angular solo para la experiencia de uso.
- **Alternatives considered**: ninguna; se sigue el patrón vigente.

## Decisión 11: Auditoría

- **Decision**: Hay seis nuevos valores de `audit.audit_event_type`, en una migración propia:
  - `blog_article_published`, `blog_article_changes_published`, `blog_article_retired` y `blog_article_deleted`;
  - `blog_source_changed`, para marcar la migración y completar el cambio de fuente;
  - `blog_cutover_manifest_changed`.

  La metadata lleva solo el id del artículo, el slug y los idiomas publicados, nunca el contenido (FR-020). Guardar un borrador no se audita, para no llenar el registro.
- **Rationale**: Mismo patrón que 016 (eventos en migración separada porque un valor de enum no se usa en la misma transacción que lo crea).

## Decisión 12: Gobierno, el conflicto con la Constitución

> **Estado**: resuelto el 2026-11-17. ADR-0004 fue aceptado y la enmienda se aplicó a la Constitución y al mainspec.

- **Decision**: Hay que redactar `docs/adr/0004-blog-authoring-in-panel.md` (Nivel 3) y la enmienda de *Technology Direction → Content Management* y de mainspec 22.1. Es la primera tarea de `tasks.md` y bloquea las tareas de migración SQL e interfaz.
  - El ADR debe registrar que WordPress deja de ser la fuente del blog tras el cambio de fuente.
  - También debe registrar que landing pages, contenido de marketing y SEO quedan como hoy, salvo otra decisión posterior.
- **Rationale**: La Constitución prevalece (*Conflict Resolution*) y un cambio de tecnología responsable es Nivel 3 (*Change Approval Levels*).
- **Alternatives considered**: *Implementar y documentar después*: lo prohíbe la Constitución («Implementation shall not begin before the RFC has been accepted»).
