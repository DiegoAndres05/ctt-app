# Management contract (panel)

Estas son las RPC que llama el panel con la sesión del usuario. Todas son `SECURITY DEFINER` con `search_path = ''` y toman la agencia del JWT, nunca de un argumento.

Errores: el mensaje de la excepción es el código de la API.

| Código | Cuándo |
| --- | --- |
| `FORBIDDEN` | Rol sin permiso: Agente en artículos; Operador en fuente o manifiesto. |
| `NOT_FOUND` | El artículo no existe o es de otra agencia (FR-019). |
| `ARTICLE_CONFLICT` | `p_expected_revision` no coincide con la revisión actual (FR-010). |
| `SLUG_TAKEN` | El slug ya existe en la agencia (FR-014). |
| `INVALID_SLUG` | El formato no es válido y el artículo no está migrado (FR-015). |
| `SLUG_LOCKED` | Se intentó cambiar el slug después de la primera publicación (FR-016). |
| `INVALID_IMAGE_REF` | Una referencia de imagen está fuera del prefijo del artículo, o es una URL externa en un artículo no migrado. |
| `VALIDATION_ERROR` | Una longitud o un formato del payload no es válido (FR-006). |
| `PUBLISH_INCOMPLETE` | Faltan campos para publicar. `DETAIL` lleva el JSON `[{field, locale}]` (FR-004). |
| `INVALID_TRANSITION` | La acción no aplica al estado actual. |
| `NOT_DELETABLE` | Se intentó eliminar un artículo que ya se publicó alguna vez (FR-009). |
| `MIGRATION_CLOSED` | Se intentó crear un artículo migrado o editar el manifiesto sin una migración abierta. |
| `BLOG_CUTOVER_INCOMPLETE` | Faltan artículos del manifiesto. `DETAIL` lleva el JSON `["slug", …]` (FR-032). |

## Articles (Operador, Administrador)

### `list_blog_articles(p_status text DEFAULT NULL) → jsonb`

```json
[
  {
    "id": "uuid",
    "slug": "que-ver-en-cartagena",
    "status": "published",
    "hasPendingChanges": true,
    "completeLocales": ["es", "en"],
    "title": "Qué ver en Cartagena",
    "firstPublishedAt": "2026-11-17T15:00:00Z",
    "updatedAt": "2026-11-17T16:00:00Z",
    "migrated": false,
    "revision": 7
  }
]
```

`title` toma el título en español del contenido `working` si existe y, si no, del `published`; si falta el español, usa el inglés. `completeLocales` lista los idiomas exigidos que pasarían la validación de publicación.

### `get_blog_article(p_id uuid) → jsonb`

Devuelve la identidad del artículo, más `working` (o `null`), `published` (o `null`) y `requiredLocales`. Cada contenido trae `coverRef` y, por idioma (`es` y `en`), `title`, `summary`, `coverAlt`, `body`, `seoTitle` y `seoDescription`.

### `save_blog_article(p_payload jsonb) → jsonb`

Crea el artículo (sin `id`) o guarda su contenido `working` (con `id` y `expectedRevision`).

```json
{
  "id": null,
  "expectedRevision": null,
  "slug": "que-ver-en-cartagena",
  "migrated": false,
  "originalPublishedAt": null,
  "coverRef": "<org>/blog/<article>/<uuid>.webp",
  "es": {
    "title": "…",
    "summary": "…",
    "coverAlt": "…",
    "body": [],
    "seoTitle": null,
    "seoDescription": null
  },
  "en": {}
}
```

- **Al crear**: basta un título en un idioma (FR-002). Si falta `slug`, se propone a partir del título en español sin tildes y se le añade un sufijo `-2`, `-3`… si ya existe.
- **`migrated` y `originalPublishedAt`**: solo se aceptan al crear y mientras la migración de la agencia esté abierta; si no, devuelve `MIGRATION_CLOSED`.
- **Cuerpos**: se normalizan según el documento de bloques (data-model) antes de guardarse.
- **Respuesta**: `{ "id", "revision", "status", "hasPendingChanges" }`.

### Transiciones

Todas reciben `(p_id uuid, p_expected_revision integer)` y devuelven `{ "id", "revision", "status", "hasPendingChanges", "firstPublishedAt", "publicUpdatedAt" }`.

| RPC | Efecto | Errores típicos |
| --- | --- | --- |
| `publish_blog_article` | `draft` → `published` | `PUBLISH_INCOMPLETE`, `INVALID_TRANSITION` |
| `publish_blog_article_changes` | Reemplaza `published` por `working` | `PUBLISH_INCOMPLETE`, `INVALID_TRANSITION` (sin `working`) |
| `discard_blog_article_changes` | Borra `working` | `INVALID_TRANSITION` |
| `retire_blog_article` | `published` → `retired` | `INVALID_TRANSITION` |
| `republish_blog_article` | `retired` → `published` | `INVALID_TRANSITION` |
| `delete_blog_article` | Elimina un borrador que nunca se publicó | `NOT_DELETABLE` |

### Imágenes

Se suben directamente a Storage, al bucket `catalog-media`, en la ruta `{organization_id}/blog/{article_id}/{uuid}.{jpg|png|webp}`, con un máximo de 10 MB. Las políticas de 026 autorizan la escritura. El artículo debe existir antes de subir imágenes: el panel guarda primero el borrador.

## Blog source (Administrador)

| RPC | Entrada | Efecto |
| --- | --- | --- |
| `get_blog_source()` | — | `{ "migrationRequired", "cutoverCompletedAt", "manifest": [{ "slug", "articleId", "published" }], "missing": ["slug"] }` |
| `set_blog_migration_required(p_required boolean)` | | Marca o desmarca «blog migrado». No se puede después del cambio de fuente (`INVALID_TRANSITION`). Audita `blog_source_changed`. |
| `replace_blog_cutover_manifest(p_slugs text[])` | De 0 a 2.000 slugs | Reemplaza el manifiesto. Requiere migración abierta. Audita `blog_cutover_manifest_changed` con el conteo. |
| `complete_blog_cutover()` | — | Si a algún slug del manifiesto le falta un artículo `published`, devuelve `BLOG_CUTOVER_INCOMPLETE`. Si no, asigna `cutover_completed_at` y audita `blog_source_changed`. |

## Audit metadata

```json
{ "articleId": "uuid", "slug": "que-ver-en-cartagena", "locales": ["es", "en"] }
```

Nunca lleva títulos, cuerpos ni textos alternativos.
