---

description: "Task list for Blog multiagencia en el CMS"
---

# Tasks: Blog multiagencia en el CMS

**Input**: Documentos de diseño en `/specs/013-editorial-content/`

**Prerequisites**:
- [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/) y [quickstart.md](./quickstart.md).
- Puerta de gobierno resuelta: [ADR-0004](../../docs/adr/0004-blog-authoring-in-panel.md) *Accepted* el 2026-11-17.

**Tests**: El plan los exige:
- Arnés SQL (`./supabase/tests/run-sql-tests.sh`) con suites `blog_*_test.sql`.
- Vitest (`npm test`) para el modelo de bloques, el servicio y los componentes.

En cada historia, los tests se escriben antes que la implementación.

**Organization**: Las tareas se agrupan por historia de usuario. Después de la fase 2, cada historia se puede implementar y validar por separado.

> **Reemplazo (2026-11-17)**: Este archivo sustituye a las tareas originales del 013 (lectura de WordPress desde un shell público Angular), que quedaron obsoletas al reformular el spec.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Se puede hacer en paralelo (archivos distintos y sin dependencia de tareas incompletas).
- **[Story]**: US1–US6, según `spec.md`.
- Las rutas son relativas a la raíz del repositorio.

## Design baseline

- **Migraciones**: nuevas desde `066`. No editar `001`–`065`.
- **RPC**: todas con `SECURITY DEFINER` y `SET search_path = ''`. El mensaje de la excepción es el código de error (ver `contracts/management.md`).
- **Agencia**: siempre sale del JWT en el panel. En la lectura pública, de `resolve_public_access_key` o `require_organization_identifier_access` (016).
- **Roles**:
  - Artículos: `require_catalog_manager_or_forbidden` (Operador o Administrador).
  - Fuente y manifiesto: `require_tenant_admin_or_forbidden`.
- **Acceso a tablas**: `anon` sin acceso. `authenticated` solo puede hacer `SELECT` con RLS (Operador o Administrador de la propia agencia), sin escrituras directas.
- **Cuerpo**: bloques JSON (`data-model.md`, «Documento de bloques»), nunca HTML.
- **Imágenes**: bucket `catalog-media` en `{org}/blog/{article}/{uuid}.{ext}`, con las políticas de 026.
- **Panel**: sin dependencias npm nuevas. Signal Forms (ADR-0001). Copy en español.
- **Auditoría**: la metadata lleva solo `articleId`, `slug` y `locales`. Nunca títulos ni cuerpos.

---

## Phase 1: Setup

**Purpose**: Archivos base y verificación de lo que se reutiliza.

- [x] T001 Crear los archivos de migración vacíos con su cabecera de propósito, en orden: `supabase/migrations/066_blog_enums.sql`, `067_blog_tables.sql`, `068_blog_content_validation.sql`, `069_blog_management_rpcs.sql`, `070_blog_public_read.sql` y `071_blog_source_cutover.sql`.
- [x] T002 [P] Crear las suites SQL vacías con la estructura `BEGIN … ROLLBACK` y los helpers `pg_temp.add_collaborator`/`act_as` (copiados de `supabase/tests/traveler_case_status_test.sql`) en:
  - `supabase/tests/blog_articles_test.sql`
  - `supabase/tests/blog_isolation_test.sql`
  - `supabase/tests/blog_public_read_test.sql`
  - `supabase/tests/blog_cutover_test.sql`
- [x] T003 [P] Crear las carpetas `src/app/core/blog/models/`, `src/app/core/blog/services/`, `src/app/features/blog/blog-list/`, `src/app/features/blog/blog-editor/` y `src/app/features/blog/blog-migration/`.
- [x] T004 [P] Revisar que siguen vigentes, con las firmas que cita `research.md`:
  - `require_catalog_manager_or_forbidden` y `require_tenant_admin_or_forbidden`;
  - `resolve_public_access_key` y `require_organization_identifier_access`;
  - `public_profiles.languages`;
  - las políticas de `catalog-media` en `supabase/migrations/026_catalog_media_bucket.sql`.

  Anotar en `specs/013-editorial-content/research.md` cualquier diferencia.

---

## Phase 2: Foundational

**Purpose**: Tipos, tablas, validación de bloques y piezas compartidas del panel. **Bloquea todas las historias.**

- [x] T005 Definir en `supabase/migrations/066_blog_enums.sql`:
  - los enums `public.blog_article_status` (`draft`, `published`, `retired`) y `public.blog_content_kind` (`published`, `working`);
  - los valores de auditoría `blog_article_published`, `blog_article_changes_published`, `blog_article_retired`, `blog_article_deleted`, `blog_source_changed` y `blog_cutover_manifest_changed`.

  Va en una migración aparte porque un valor de enum no se usa en la transacción que lo crea.
- [x] T006 Crear en `supabase/migrations/067_blog_tables.sql` las tablas `blog_articles`, `blog_article_contents`, `public_blog_source` y `public_blog_cutover_items`, con las columnas, CHECK, FKs compuestas e índices de `data-model.md`, incluido `(organization_id, status, first_published_at DESC)`.
- [x] T007 En `supabase/migrations/067_blog_tables.sql`, añadir:
  - RLS en las cuatro tablas;
  - `REVOKE ALL` a `anon`;
  - políticas `SELECT` para `authenticated` con `organization_id` del JWT y `app_role IN ('operator','admin')`;
  - ninguna política de escritura;
  - triggers que impiden cambiar `organization_id`, `migrated` y `created_at`, impiden cambiar `slug` si `first_published_at IS NOT NULL` y no permiten volver atrás `first_published_at` ni `cutover_completed_at` una vez asignados.
- [x] T008 En `supabase/migrations/068_blog_content_validation.sql`, implementar `public.blog_normalize_body(p_body jsonb, p_org uuid, p_article uuid, p_allow_external boolean) RETURNS jsonb`. Debe:
  - conservar solo `paragraph`, `heading` (2|3), `list`, `quote` e `image`, y descartar bloques desconocidos;
  - limpiar inline a `text`, `bold`, `italic` y `href`, y quitar los `href` que no sean `https:`, `http:` ni `mailto:`;
  - aplicar los límites de 500 bloques, 100 ítems por lista y 200 KB por idioma;
  - lanzar `INVALID_IMAGE_REF` si un `image.ref` está fuera de `{org}/blog/{article}/`, salvo una URL `https` con `p_allow_external`.

  Es interna: `REVOKE` a `anon` y `authenticated`.
- [x] T009 En `supabase/migrations/068_blog_content_validation.sql`, implementar:
  - `public.blog_required_locales(p_org uuid) RETURNS text[]`: `public_profiles.languages`, o `{es}` si no hay perfil;
  - `public.blog_publish_errors(p_article uuid) RETURNS jsonb`: una lista `[{field, locale}]` sobre el contenido `working` con las reglas de FR-004 (`data-model.md`, «Validación de publicación»).

  Ambas son internas.
- [x] T010 [P] Añadir los modelos de dominio en `src/app/core/blog/models/blog-article.model.ts`:
  - los tipos `BlogArticleStatus`, `BlogLocale`, `BlogArticleSummary`, `BlogArticleDetail`, `BlogContent`, `BlogLocaleContent`, `BlogSavePayload`, `BlogPublishError` y `BlogSource`;
  - las funciones `parseBlogArticleSummary`, `parseBlogArticleDetail` y `parseBlogSource`, que validan las respuestas de `contracts/management.md`.
- [x] T011 [P] Implementar el modelo de bloques en `src/app/core/blog/models/blog-blocks.ts`:
  - los tipos `BlogBlock` e `InlineRun`;
  - `parseInlineMarkup(text)`, que convierte `**negrita**`, `*cursiva*` y `[texto](url)` a `InlineRun[]` y deja como texto cualquier URL que no sea http(s) ni mailto;
  - `serializeInlineMarkup(runs)`;
  - `isBodyEmpty(blocks)`.
- [x] T012 [P] Escribir los tests del modelo de bloques en `src/app/core/blog/models/blog-blocks.spec.ts`:
  - ida y vuelta de marcas en línea;
  - un enlace `javascript:` queda como texto;
  - un `**` sin cerrar queda literal;
  - un cuerpo vacío o con solo espacios cuenta como vacío.
- [x] T013 Añadir los códigos de error del blog con mensajes en español en `src/app/core/error/error-handler.ts`: `ARTICLE_CONFLICT`, `SLUG_TAKEN`, `INVALID_SLUG`, `SLUG_LOCKED`, `INVALID_IMAGE_REF`, `PUBLISH_INCOMPLETE`, `INVALID_TRANSITION`, `NOT_DELETABLE`, `MIGRATION_CLOSED` y `BLOG_CUTOVER_INCOMPLETE`.
- [x] T014 Crear `src/app/core/blog/services/blog.service.ts` con:
  - el cliente Supabase con sesión;
  - un mapeo de errores de RPC que extrae `DETAIL` como JSON para `PUBLISH_INCOMPLETE` y `BLOG_CUTOVER_INCOMPLETE`;
  - `uploadImage(articleId, file)`, que sube a `catalog-media` en `{org}/blog/{articleId}/{uuid}.{ext}`, valida JPEG, PNG o WebP de 10 MB como máximo y devuelve la ruta.
- [x] T015 [P] Añadir los seis tipos de evento del blog en `src/app/core/audit/models/audit-event.model.ts`.

**Checkpoint**: Las migraciones 066–068 se aplican con `./supabase/tests/run-sql-tests.sh` sin errores, y `npm test` pasa con el modelo de bloques.

---

## Phase 3: User Story 1 - Escribir y guardar un borrador (Priority: P1) 🎯 MVP

**Goal**: Operador y Administrador crean, listan, abren, editan y eliminan borradores bilingües incompletos, con imágenes y textos alternativos, sin que aparezcan en ningún sitio.

**Independent Test**: Crear un borrador solo con el título en español, recargar, completar el cuerpo con una imagen y su texto alternativo, y guardar. Lo encuentra en «Borrador». Dos guardados con la misma `expectedRevision` producen `ARTICLE_CONFLICT`. (`quickstart.md`, escenarios 1, 10, 12 y 13)

### Tests for User Story 1

- [x] T016 [P] [US1] Escribir los tests SQL de borradores en `supabase/tests/blog_articles_test.sql`:
  - crear con solo el título;
  - slug propuesto desde el título sin tildes y con sufijo `-2` si ya existe;
  - `SLUG_TAKEN` e `INVALID_SLUG`;
  - límites de FR-006;
  - normalización que descarta un bloque `script` y un `href` `javascript:`;
  - `INVALID_IMAGE_REF` fuera del prefijo;
  - `ARTICLE_CONFLICT` con una revisión vieja;
  - eliminar un borrador nunca publicado;
  - `list_blog_articles` filtrado por estado.
- [x] T017 [P] [US1] Escribir los tests del servicio en `src/app/core/blog/services/blog.service.spec.ts`: mapeo de `ARTICLE_CONFLICT` y `SLUG_TAKEN`, ruta de subida con `organization_id` y `articleId`, y rechazo de un archivo no permitido antes de subir.

### Implementation for User Story 1

- [x] T018 [US1] Implementar en `supabase/migrations/069_blog_management_rpcs.sql`:
  - `save_blog_article(p_payload jsonb)`: crea o actualiza el contenido `working`, propone el slug, valida longitudes, normaliza los cuerpos con `blog_normalize_body`, comprueba `expectedRevision`, incrementa `revision` y devuelve `{id, revision, status, hasPendingChanges}`;
  - `delete_blog_article(p_id, p_expected_revision)`, solo para borradores sin `first_published_at` (FR-009).
- [x] T019 [US1] Implementar en `supabase/migrations/069_blog_management_rpcs.sql`:
  - `list_blog_articles(p_status text)`, con `hasPendingChanges`, `completeLocales` (calculado con `blog_publish_errors` por idioma) y el título según la regla del contrato;
  - `get_blog_article(p_id)`, que devuelve `NOT_FOUND` si el artículo no es de la agencia.
- [x] T020 [US1] Añadir a `src/app/core/blog/services/blog.service.ts` los métodos `listArticles(status?)`, `getArticle(id)`, `saveArticle(payload)` y `deleteArticle(id, revision)`, con signals de carga y error.
- [x] T021 [P] [US1] Construir el listado en `src/app/features/blog/blog-list/blog-list.component.ts` (y su `.html`):
  - tabla con título, estado, «Cambios sin publicar», idiomas completos y fechas;
  - filtro por estado y botón «Nuevo artículo»;
  - estado vacío.
- [x] T022 [US1] Construir el editor en `src/app/features/blog/blog-editor/blog-editor.component.ts` (y su `.html`):
  - pestañas ES/EN, con título, resumen, texto alternativo de la portada, título SEO y descripción SEO por idioma;
  - slug editable con sugerencia;
  - portada con subida;
  - lista de bloques: añadir, mover, eliminar, área de texto con marcas en línea y bloque de imagen con subida, texto alternativo y casilla «decorativa»;
  - pegado como texto plano;
  - guardar con `expectedRevision` y aviso de conflicto con «Recargar» o «Sobrescribir»;
  - eliminar un borrador.

  Usar Signal Forms.
- [x] T023 [P] [US1] Añadir la vista previa de bloques con el mapeo de `contracts/public-consumer.md` en `src/app/features/blog/blog-editor/blog-preview.component.ts`. Todo el texto se escapa y no se usa `innerHTML` con contenido del usuario.
- [x] T024 [US1] Registrar las rutas en `src/app/app.routes.ts`: `cms/blog`, `cms/blog/new` y `cms/blog/:id`, con `roleGuard('operator')`. Añadir la entrada «Blog» bajo CMS en `src/app/shared/layout/nav-items.ts`, visible solo para Operador y Administrador.
- [x] T025 [P] [US1] Escribir los tests de componente en `src/app/features/blog/blog-editor/blog-editor.component.spec.ts`:
  - guardar un borrador con solo el título;
  - el conflicto muestra el aviso;
  - pegar HTML inserta texto plano;
  - la vista previa no interpreta HTML.

**Checkpoint**: US1 funciona sola: los borradores se guardan, listan y editan, y nada es público todavía.

---

## Phase 4: User Story 2 - Publicar y ver el artículo en el sitio (Priority: P1)

**Goal**: Publicar un borrador completo en los idiomas que ofrece la agencia y leerlo desde el sitio por listado paginado y por slug, con SEO, ocultando todo lo que no está publicado.

**Independent Test**: Publicar un artículo completo y leerlo con `get_public_blog_by_key` y `get_public_blog_article_by_key`. Intentar publicar uno incompleto devuelve `PUBLISH_INCOMPLETE` con los campos por idioma. Un borrador y un slug inventado devuelven el mismo `{"found": false}`. (`quickstart.md`, escenarios 2, 3, 4, 14 y 18)

### Tests for User Story 2

- [x] T026 [P] [US2] Añadir a `supabase/tests/blog_articles_test.sql` los tests de publicación:
  - `PUBLISH_INCOMPLETE` con el `DETAIL` esperado (portada, `alt` de imagen e idioma `en` faltante en una agencia que ofrece `es,en`);
  - una agencia con solo `es` publica sin `en`;
  - la publicación asigna `first_published_at` y `public_updated_at`;
  - se emite el evento `blog_article_published` sin título en la metadata.
- [x] T027 [P] [US2] Escribir en `supabase/tests/blog_public_read_test.sql` los tests de lectura pública:
  - orden por `publishedAt` descendente y paginación (`p_page_size` de 1 a 50, y 12 por defecto);
  - solo los idiomas ofrecidos;
  - `seoTitle` y `seoDescription` toman el título y el resumen si faltan;
  - borrador, slug inventado y slug de otra agencia devuelven exactamente `{"found": false}`;
  - clave revocada o inexistente: `PUBLIC_ACCESS_UNAVAILABLE`;
  - identificador de organización fuera de la transición: `PUBLIC_ACCESS_UNAVAILABLE`;
  - una sesión autenticada usa la agencia del JWT;
  - `GRANT` a `anon` y `authenticated`, y las funciones internas sin `EXECUTE`;
  - la respuesta no contiene `revision`, autores ni contenido `working`.

### Implementation for User Story 2

- [x] T028 [US2] Implementar `publish_blog_article(p_id, p_expected_revision)` en `supabase/migrations/069_blog_management_rpcs.sql`:
  - valida con `blog_publish_errors` y, si hay errores, lanza `PUBLISH_INCOMPLETE` con `DETAIL` en JSON;
  - mueve `working` a `published`;
  - asigna las fechas y `status = published`;
  - emite la auditoría.
- [x] T029 [US2] Implementar en `supabase/migrations/070_blog_public_read.sql`:
  - los internos `public.build_public_blog_list(p_org, p_page, p_page_size)` y `public.build_public_blog_article(p_org, p_slug)`, según `contracts/public-consumer.md`, con `source` (`panel`/`legacy` desde `public_blog_source`), `languages`, `total`, `generatedAt`, idiomas filtrados y fallback SEO;
  - las cuatro entradas públicas: `get_public_blog_by_key`, `get_public_blog_article_by_key`, `get_public_blog` y `get_public_blog_article`, estas dos para la transición de CTT o el JWT, con la misma resolución de agencia que `get_public_site`;
  - `GRANT` a `anon` y `authenticated`, y `REVOKE` de los internos.
- [x] T030 [US2] Añadir a `src/app/core/blog/services/blog.service.ts` el método `publishArticle(id, revision)`, que devuelve `BlogPublishError[]` cuando hay `PUBLISH_INCOMPLETE`.
- [x] T031 [US2] En `src/app/features/blog/blog-editor/blog-editor.component.ts`, añadir:
  - el botón «Publicar», solo en borradores;
  - la lista de campos faltantes agrupada por idioma, que lleva a la pestaña y al campo correspondiente;
  - un indicador de idiomas exigidos, según `requiredLocales`.
- [x] T032 [P] [US2] Añadir a `src/app/features/blog/blog-editor/blog-editor.component.spec.ts` los tests de publicación: los errores por idioma se muestran y enfocan, y una publicación correcta pasa el estado a «Publicado».

**Checkpoint**: US1 y US2 juntas forman el MVP: redactar, publicar y leer desde el sitio.

---

## Phase 5: User Story 3 - Aislamiento entre agencias y permisos (Priority: P1)

**Goal**: Mismo slug en varias agencias sin cruce de datos. Agente sin acceso. Cualquier intento entre agencias responde como si el artículo no existiera.

**Independent Test**: Las agencias A y B publican `que-ver-en-cartagena` y cada clave devuelve el suyo. Un Agente recibe `FORBIDDEN` en todas las RPC. El Operador de B recibe `NOT_FOUND` con un id de A. (`quickstart.md`, escenarios 5 y 6)

### Tests for User Story 3

- [x] T033 [P] [US3] Escribir en `supabase/tests/blog_isolation_test.sql`:
  - mismo slug en dos agencias;
  - `SELECT` directo a las cuatro tablas como `anon` (denegado) y como Agente (cero filas);
  - Operador de B sobre artículos de A: `NOT_FOUND` en `get`, `save`, `publish`, `retire`, `republish`, `discard`, `publish_changes` y `delete`;
  - Agente: `FORBIDDEN` en todas;
  - Operador: `FORBIDDEN` en las RPC de fuente y manifiesto;
  - escritura directa (`INSERT`/`UPDATE`) como `authenticated` rechazada;
  - una referencia de imagen de otra agencia: `INVALID_IMAGE_REF`.
- [x] T034 [P] [US3] Añadir a `src/app/shared/layout/nav-items.spec.ts` el test de que la entrada «Blog» no aparece para el rol Agente y sí para Operador y Administrador.

### Implementation for User Story 3

- [x] T035 [US3] Revisar `supabase/migrations/069_blog_management_rpcs.sql` para que cada RPC de artículo resuelva la agencia solo desde el JWT y busque por `(id, organization_id)`, devolviendo `NOT_FOUND`. Corregir lo que T033 detecte.
- [x] T036 [US3] Confirmar que el bloque de imagen y la subida de `blog.service.ts` solo generan rutas con el `organization_id` de la sesión, y que `blog_normalize_body` rechaza cualquier otro prefijo. Ajustar `src/app/core/blog/services/blog.service.ts` si hace falta.

**Checkpoint**: SC-004 y SC-005 verificados por la suite de aislamiento.

---

## Phase 6: User Story 4 - Editar un artículo publicado sin romper su dirección (Priority: P2)

**Goal**: Las ediciones de un publicado quedan como revisión en curso, que se publica o se descarta, sin cambiar la URL ni la fecha de publicación.

**Independent Test**: Editar un publicado y guardar: la web sigue mostrando la versión anterior y el panel marca «Cambios sin publicar». Publicar los cambios: la misma URL muestra la versión nueva con la misma `publishedAt`. Descartar en otra edición devuelve la versión publicada. Cambiar el slug devuelve `SLUG_LOCKED`. (`quickstart.md`, escenarios 7, 8 y 9)

### Tests for User Story 4

- [x] T037 [P] [US4] Añadir a `supabase/tests/blog_articles_test.sql`:
  - guardar sobre un publicado crea `working` copiando `published` y la lectura pública no cambia;
  - una revisión incompleta se guarda, pero `publish_blog_article_changes` devuelve `PUBLISH_INCOMPLETE` sin tocar `published`;
  - publicar cambios actualiza `public_updated_at` y conserva `first_published_at`;
  - descartar borra `working`;
  - `SLUG_LOCKED`;
  - se emite `blog_article_changes_published`.

### Implementation for User Story 4

- [x] T038 [US4] En `supabase/migrations/069_blog_management_rpcs.sql`:
  - extender `save_blog_article` para crear `working` desde `published` en artículos publicados o retirados y para rechazar un cambio de slug con `SLUG_LOCKED`;
  - implementar `publish_blog_article_changes` y `discard_blog_article_changes`, con `INVALID_TRANSITION` si no hay `working`.
- [x] T039 [US4] Añadir a `src/app/core/blog/services/blog.service.ts` los métodos `publishChanges(id, revision)` y `discardChanges(id, revision)`.
- [x] T040 [US4] En `src/app/features/blog/blog-editor/blog-editor.component.ts`, para artículos publicados o retirados:
  - banner «Cambios sin publicar»;
  - botones «Publicar cambios» y «Descartar cambios» (este con confirmación);
  - slug de solo lectura con la explicación de por qué;
  - vista previa que permite alternar entre la versión publicada y la revisión.
- [x] T041 [P] [US4] Añadir a `src/app/features/blog/blog-editor/blog-editor.component.spec.ts`: el slug está bloqueado en un publicado, el banner aparece cuando hay `working` y descartar pide confirmación.

**Checkpoint**: SC-006 verificado.

---

## Phase 7: User Story 5 - Retirar un artículo (Priority: P2)

**Goal**: Retirar oculta el artículo en el sitio sin perderlo del panel. Republicar lo restaura en la misma URL y con la misma fecha.

**Independent Test**: Retirar: el artículo desaparece del listado y su slug devuelve `{"found": false}`. Republicar: vuelve con la misma `publishedAt`. Eliminar un retirado: `NOT_DELETABLE`. (`quickstart.md`, escenarios 11 y 12)

### Tests for User Story 5

- [x] T042 [P] [US5] Añadir a `supabase/tests/blog_articles_test.sql`:
  - retirar y republicar conservan el slug y `first_published_at`;
  - un retirado con `working` conserva la revisión;
  - `NOT_DELETABLE` para retirados y publicados;
  - `INVALID_TRANSITION` al retirar un borrador;
  - se emite `blog_article_retired`.
- [x] T043 [P] [US5] Añadir a `supabase/tests/blog_public_read_test.sql` que un retirado no aparece en el listado ni por slug, y reaparece al republicar.

### Implementation for User Story 5

- [x] T044 [US5] Implementar `retire_blog_article` y `republish_blog_article`, con auditoría, en `supabase/migrations/069_blog_management_rpcs.sql`.
- [x] T045 [US5] Añadir a `src/app/core/blog/services/blog.service.ts` los métodos `retire(id, revision)` y `republish(id, revision)`.
- [x] T046 [US5] Añadir los botones «Retirar» (con confirmación) y «Volver a publicar» en `src/app/features/blog/blog-editor/blog-editor.component.ts`. Ocultar «Eliminar» si el artículo se publicó alguna vez.

**Checkpoint**: Todo el ciclo de vida editorial (US1–US5) está completo.

---

## Phase 8: User Story 6 - Migrar el blog existente desde WordPress (Priority: P2)

**Goal**: Una agencia con blog previo copia sus artículos conservando slug y fecha, y completa el cambio de fuente solo cuando el manifiesto está completo. Hasta entonces, el sitio sigue leyendo WordPress.

**Independent Test**: Marcar la agencia como «blog migrado» y cargar un manifiesto de 3 slugs. Con 2 copiados, `complete_blog_cutover` devuelve `BLOG_CUTOVER_INCOMPLETE` y la lectura pública responde `source: "legacy"`. Al copiar el tercero (con un slug heredado fuera de formato y su fecha original), el cambio se completa y la lectura responde `source: "panel"`. Una agencia sin fila de fuente publica directamente. (`quickstart.md`, escenarios 15, 16 y 17)

### Tests for User Story 6

- [x] T047 [P] [US6] Escribir en `supabase/tests/blog_cutover_test.sql`:
  - marcar y desmarcar la migración;
  - reemplazar el manifiesto (como máximo 2.000 slugs);
  - `MIGRATION_CLOSED` al crear un artículo migrado sin migración abierta o después del cambio;
  - un artículo migrado acepta un slug heredado, `originalPublishedAt` y una imagen `https` externa;
  - un artículo no migrado rechaza la URL externa;
  - `BLOG_CUTOVER_INCOMPLETE` con la lista de faltantes en `DETAIL`;
  - completar el cambio asigna `cutover_completed_at` y la lectura pública pasa de `legacy` a `panel`;
  - `INVALID_TRANSITION` al desmarcar después del cambio;
  - una agencia sin fila de fuente publica en `panel`;
  - eventos `blog_source_changed` y `blog_cutover_manifest_changed`.

### Implementation for User Story 6

- [x] T048 [US6] Implementar `get_blog_source`, `set_blog_migration_required`, `replace_blog_cutover_manifest` y `complete_blog_cutover`, solo para Administrador, con auditoría y `DETAIL` en JSON, en `supabase/migrations/071_blog_source_cutover.sql`.
- [x] T049 [US6] En `supabase/migrations/071_blog_source_cutover.sql`, redefinir con `CREATE OR REPLACE` `save_blog_article`, para aceptar `migrated` y `originalPublishedAt` solo al crear con la migración abierta (`MIGRATION_CLOSED` en otro caso), eximir del formato de slug a los migrados y pasar `p_allow_external = migrated` a `blog_normalize_body`. Redefinir también `publish_blog_article`, para usar `originalPublishedAt` como `first_published_at` de un migrado.
- [x] T050 [US6] Añadir a `src/app/core/blog/services/blog.service.ts` los métodos `getSource()`, `setMigrationRequired(flag)`, `replaceManifest(slugs)` y `completeCutover()`, que devuelven la lista de faltantes cuando hay `BLOG_CUTOVER_INCOMPLETE`.
- [x] T051 [US6] Construir la pantalla de migración en `src/app/features/blog/blog-migration/blog-migration.component.ts` (y su `.html`):
  - interruptor «Blog migrado»;
  - área de texto del manifiesto, un slug por línea, con conteo;
  - tabla con slug, artículo y estado (publicado, falta);
  - botón «Completar cambio de fuente» con confirmación y la lista de faltantes;
  - estado final de solo lectura.
- [x] T052 [US6] Registrar `cms/settings/blog-migration` con `roleGuard('admin')` en `src/app/app.routes.ts` y enlazarla desde `src/app/features/catalog/catalog-settings/catalog-settings.component.ts`. En `blog-editor.component.ts`, mostrar la casilla «Artículo migrado» y la fecha original solo al crear y con la migración abierta.
- [x] T053 [P] [US6] Escribir los tests de componente en `src/app/features/blog/blog-migration/blog-migration.component.spec.ts`: la lista de faltantes se muestra tras `BLOG_CUTOVER_INCOMPLETE` y el estado completado queda de solo lectura.

**Checkpoint**: SC-010 verificado. CTT puede migrar sin romper direcciones.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [x] T054 [P] Añadir las etiquetas en español de los seis eventos del blog y su inclusión en el filtro, en `src/app/features/audit/audit-log/audit-log.component.ts`.
- [x] T055 [P] Documentar el módulo en `docs/modules/catalog-pricing.md`, en una sección «Blog (013)»:
  - entidades, RPC, roles y estados;
  - enlace a `specs/013-editorial-content/contracts/public-consumer.md`;
  - regla de caché de 300 s como máximo;
  - migración `legacy` → `panel`;
  - invariantes de seguridad.
- [x] T056 [P] Añadir las suites `blog_*_test.sql` a la lista del comentario de cabecera de `supabase/tests/run-sql-tests.sh`.
- [x] T057 Añadir a `supabase/tests/blog_public_read_test.sql` una prueba de rendimiento: sembrar 1.000 artículos publicados en una agencia y verificar con `EXPLAIN` que el listado usa el índice `(organization_id, status, first_published_at DESC)`.
- [x] T058 Revisión de seguridad:
  - `rg -n "service_role|SERVICE_ROLE" src/app/core/blog src/app/features/blog` debe salir vacío;
  - toda función de `066`–`071` tiene `search_path = ''`;
  - ninguna llamada a `audit.log_event` del blog incluye títulos, cuerpos ni textos alternativos;
  - ningún `innerHTML` o `bypassSecurityTrust*` en `src/app/features/blog`.
- [x] T059 Ejecutar la validación completa de `specs/013-editorial-content/quickstart.md`: `./supabase/tests/run-sql-tests.sh` (todas las suites), `npm test -- --watch=false`, `npm run lint` y `npm run build`. Recorrer manualmente los escenarios 1–20 en el panel local.
- [x] T060 Marcar como completo el último ítem del checklist de aprobación de `docs/adr/0004-blog-authoring-in-panel.md` (implementación iniciada y entregada) y actualizar `Status: Draft` a `Implemented` en `specs/013-editorial-content/spec.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (fase 1)**: no depende de nada.
- **Foundational (fase 2)**: depende de la fase 1 y **bloquea todas las historias**.
- **US1 (fase 3)**: depende solo de la fase 2.
- **US2 (fase 4)**: depende de la fase 2. Usa `save_blog_article` de US1 para preparar sus datos de prueba, así que conviene hacerla después de T018.
- **US3 (fase 5)**: depende de las RPC de US1 y US2 que verifica (T018, T019, T028 y T029).
- **US4 (fase 6)**: depende de US2, porque necesita artículos publicados.
- **US5 (fase 7)**: depende de US2. Es independiente de US4.
- **US6 (fase 8)**: depende de US2 (lectura pública y publicación). Es independiente de US4 y US5.
- **Polish (fase 9)**: depende de todas las historias que se entreguen.

### Within Each User Story

- Los tests se escriben antes que la implementación y deben fallar primero.
- Migración SQL → servicio → componente → tests de componente.
- `069_blog_management_rpcs.sql` lo tocan US1, US2, US3, US4 y US5, así que esas tareas van en secuencia. US6 redefine las funciones en `071` en lugar de editar `069`.

### Parallel Opportunities

- **Fase 1**: T002, T003 y T004 en paralelo.
- **Fase 2**: T010, T011, T012 y T015 en paralelo con T005–T009 (archivos distintos).
- **Con la fase 4 completa**: US4, US5 y US6 pueden avanzar en paralelo en lo que respecta a tests y frontend. Las tareas SQL de US4 y US5 comparten `069`; las de US6 van en `071`.
- **Tests [P] de cada historia**: en paralelo entre sí.

---

## Parallel Example: User Story 1

```text
# Tests primero, en paralelo:
T016 Tests SQL de borradores en supabase/tests/blog_articles_test.sql
T017 Tests del servicio en src/app/core/blog/services/blog.service.spec.ts

# Después de T018–T020, la interfaz en paralelo:
T021 Listado en src/app/features/blog/blog-list/blog-list.component.ts
T023 Vista previa en src/app/features/blog/blog-editor/blog-preview.component.ts
```

## Parallel Example: después de US2

```text
T037 [US4] tests de revisión     (blog_articles_test.sql)
T047 [US6] tests de migración    (blog_cutover_test.sql)
T043 [US5] tests de lectura      (blog_public_read_test.sql)
```

---

## Implementation Strategy

### MVP (US1 + US2)

1. Fase 1 (Setup) y fase 2 (Foundational).
2. US1: borradores en el panel.
3. US2: publicar y leer desde el sitio.
4. **Validar**: escenarios 1–4, 10, 12–14 y 18 del quickstart. Con esto, una agencia nueva ya publica su blog.

### Entrega incremental

1. **MVP**: US1 y US2.
2. **US3**: aislamiento verificado. Es obligatorio antes de abrir el blog a una segunda agencia.
3. **US4 y US5**: ciclo editorial completo (revisiones, retiro).
4. **US6**: habilita la migración de CTT desde WordPress.
5. **Polish**: auditoría visible, documentación y validación completa.

### Notas de implementación (2026-11-17)

- **T018/T049**: las opciones de artículo migrado de `save_blog_article` y `publish_blog_article` (slug heredado, `originalPublishedAt`, imágenes `https`) se implementaron directamente en `069`, controladas por `blog_migration_open()`. `071` solo contiene las RPC de fuente y manifiesto, y no redefine funciones. Se añadió la columna `original_published_at` (ver `data-model.md`).
- **T022**: el editor usa signals y controles nativos en lugar de `form()` de Signal Forms. La lista de bloques es dinámica y los formularios reactivos siguen sin usarse (ADR-0001).
- **T024**: una sola ruta `cms/blog/:id`. `new` es un valor de `:id` que el componente trata como creación (`?migrated=1&slug=…` lo abre desde la pantalla de migración).
- **T033**: la suite de aislamiento llama a las RPC como superusuario con claims de JWT. Las funciones autorizan por claims y perfil, no por rol SQL. Grants y RLS se prueban con `SET ROLE`.
- **T057**: la prueba de rendimiento vive en `blog_public_read_test.sql` (1.000 artículos, el plan usa `blog_articles_public_list_idx`).
- **T059**: arnés SQL completo (54 suites), Vitest (28 archivos, 204 tests), lint y build en verde. Recorrido manual en el panel local: crear borrador, guardar, publicar incompleto (lista por idioma), vista previa que escapa HTML y listado. El resto de escenarios del quickstart (publicar completo, revisiones, retiro, migración, lectura por clave) están cubiertos por las suites SQL, no por un recorrido manual.

### Notas

- No hacer commit salvo que se pida.
- Marcar `[x]` en este archivo al completar cada tarea.
- La importación automática desde la API REST de WordPress queda fuera (research, Decisión 9). Si se necesita, se añade como tarea opcional de US6.
