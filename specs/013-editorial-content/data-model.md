# Data Model: Blog multiagencia en el CMS

**Feature**: [spec.md](./spec.md) · **Research**: [research.md](./research.md)

Todas las entidades nuevas tienen `organization_id` como frontera de agencia. Ninguna es accesible por `anon`. `authenticated` solo puede leer filas de su agencia con rol `operator` o `admin`, y escribe únicamente mediante RPC.

## New entities

### `public.blog_articles`

Identidad, estado y fechas del artículo. Una fila por artículo.

| Campo | Tipo | Reglas |
| --- | --- | --- |
| `id` | uuid PK | |
| `organization_id` | uuid NOT NULL → `organizations` | Frontera de agencia. `UNIQUE (id, organization_id)` para FKs compuestas. |
| `slug` | text NOT NULL | `UNIQUE (organization_id, slug)` (FR-014). Formato `^[a-z0-9]+(-[a-z0-9]+)*$`, de 1 a 120 caracteres (FR-015), salvo `migrated = true` (FR-031). Inmutable si `first_published_at IS NOT NULL` (FR-016). |
| `status` | `public.blog_article_status` | `draft` \| `published` \| `retired`. |
| `migrated` | boolean NOT NULL DEFAULT false | Solo puede ser verdadero si se creó mientras la migración del blog de la agencia estaba abierta. Inmutable. |
| `original_published_at` | timestamptz | Solo artículos migrados: fecha del blog anterior, que se copia a `first_published_at` al publicar (FR-031). |
| `first_published_at` | timestamptz | Se asigna en la primera publicación (`coalesce(original_published_at, now())`). Inmutable una vez asignado (FR-017). |
| `public_updated_at` | timestamptz | Cambia en cada publicación y publicación de cambios (FR-017). |
| `revision` | integer NOT NULL DEFAULT 1 | Concurrencia optimista: se incrementa en cada escritura (FR-010). |
| `created_by`, `updated_by` | uuid → `user_profiles (id, organization_id)` | |
| `created_at`, `updated_at` | timestamptz | |

**Invariantes:**
- `status = 'draft'` ⇒ `first_published_at IS NULL`.
- `status IN ('published', 'retired')` ⇒ `first_published_at IS NOT NULL` y existe un contenido `published`.

**Índices:** `(organization_id, status, first_published_at DESC)` para el listado público.

### `public.blog_article_contents`

Contenido bilingüe. Como máximo dos filas por artículo: `published` y `working` (research, Decisión 3).

| Campo | Tipo | Reglas |
| --- | --- | --- |
| `article_id`, `organization_id` | FK compuesta → `blog_articles` ON DELETE CASCADE | |
| `kind` | `public.blog_content_kind` | `published` \| `working`. PK `(article_id, kind)`. |
| `cover_ref` | text | Ruta en `catalog-media` bajo `{organization_id}/blog/{article_id}/`, o URL `https` solo si el artículo está migrado. |
| `title_es`, `title_en` | text | Hasta 120 caracteres, sin espacios al inicio ni al final (FR-006). |
| `summary_es`, `summary_en` | text | Hasta 300 caracteres. |
| `cover_alt_es`, `cover_alt_en` | text | Hasta 250 caracteres. |
| `body_es`, `body_en` | jsonb NOT NULL DEFAULT `'[]'` | Documento de bloques validado (ver «Documento de bloques»). Hasta 200 KB por idioma. |
| `seo_title_es`, `seo_title_en` | text | Hasta 70 caracteres, opcional (FR-005). |
| `seo_description_es`, `seo_description_en` | text | Hasta 160 caracteres, opcional. |
| `updated_by` | uuid | |
| `updated_at` | timestamptz | |

Un contenido `working` puede estar incompleto (FR-002 y FR-011). Un contenido `published` siempre cumple la validación de publicación del momento en que se publicó.

### `public.public_blog_source`

Política de fuente del blog por agencia (research, Decisión 9). Si no hay fila, la agencia no requiere migración.

| Campo | Tipo | Reglas |
| --- | --- | --- |
| `organization_id` | uuid PK → `organizations` | |
| `migration_required` | boolean NOT NULL DEFAULT false | Marca «blog migrado» (FR-030). |
| `cutover_completed_at` | timestamptz | No es nulo después del cambio de fuente (FR-033). Una vez asignado no vuelve atrás. |
| `marked_by`, `marked_at` | uuid, timestamptz | Quién marcó la migración (FR-035). |
| `completed_by` | uuid | Quién completó el cambio de fuente. |
| `created_at`, `updated_at` | timestamptz | |

### `public.public_blog_cutover_items`

Manifiesto de los artículos que muestra el blog anterior.

| Campo | Tipo | Reglas |
| --- | --- | --- |
| `organization_id` | uuid → `organizations` | |
| `slug` | text | PK `(organization_id, slug)`. Formato libre de hasta 200 caracteres (son slugs heredados). |
| `created_at` | timestamptz | |

Solo se puede editar mientras `migration_required AND cutover_completed_at IS NULL`.

### Enums

- `public.blog_article_status`: `draft`, `published`, `retired`.
- `public.blog_content_kind`: `published`, `working`.
- Nuevos valores de `audit.audit_event_type`, en una migración propia: `blog_article_published`, `blog_article_changes_published`, `blog_article_retired`, `blog_article_deleted`, `blog_source_changed`, `blog_cutover_manifest_changed`.

## Documento de bloques

Cada `body_*` es un arreglo JSON de bloques. Un bloque con un tipo desconocido o mal formado se descarta al guardar (FR-007).

| `type` | Campos | Reglas |
| --- | --- | --- |
| `paragraph` | `text`: inline[] | |
| `heading` | `level`: 2 \| 3, `text`: inline[] | |
| `list` | `ordered`: boolean, `items`: inline[][] | De 1 a 100 ítems. |
| `quote` | `text`: inline[] | |
| `image` | `ref`: text, `alt`: text \| null, `decorative`: boolean | `ref` con las mismas reglas que `cover_ref`. Al publicar se exige `alt` no vacío o `decorative = true` (FR-004). |

**Inline:** `{ "text": string, "bold"?: true, "italic"?: true, "href"?: string }`.
- `href` solo acepta `https:`, `http:` o `mailto:`, hasta 2.000 caracteres. Un `href` no permitido se elimina y se conserva el texto.
- Hay como máximo 500 bloques por idioma.

Un cuerpo se considera **no vacío** si tiene al menos un bloque `paragraph`, `heading`, `list` o `quote` con texto distinto de espacios.

## Validación de publicación (FR-004)

`public.blog_publish_errors(article_id)` evalúa el contenido `working` y devuelve una lista `{field, locale}` vacía si el contenido es publicable. Comprueba:

1. El slug es válido (o el artículo está migrado) y `cover_ref` existe.
2. Para cada idioma de `public.blog_required_locales(org)`: título, resumen, texto alternativo de la portada y cuerpo no vacíos, y `alt` o `decorative` en cada bloque `image`.

`blog_required_locales(org)` es `public_profiles.languages` de la agencia, o `{es}` si la agencia no tiene perfil.

## State transitions

```text
                 publish (valid)
   ┌───────┐ ─────────────────────▶ ┌───────────┐  retire   ┌─────────┐
   │ draft │                        │ published │ ────────▶ │ retired │
   └───────┘ ◀── delete (only if    └───────────┘ ◀──────── └─────────┘
       │          never published)      ▲    │     republish      │
       ▼                                │    │ edit → working     │ edit → working
    deleted                             │    ▼                    ▼
                          publish_changes (valid) · discard_changes
```

| Acción | Desde | Efecto |
| --- | --- | --- |
| `save` | cualquiera | Escribe `working`; si no existe en `published` o `retired`, primero lo crea copiando `published`. `revision + 1`. |
| `publish` | `draft` | Valida `working` → pasa a `published`; asigna `first_published_at` (si no existe) y `public_updated_at`; `status = published`. |
| `publish_changes` | `published`, `retired` con `working` | Valida → reemplaza `published`; `public_updated_at = now()`. El estado no cambia: un retirado sigue retirado. |
| `discard_changes` | `published`, `retired` con `working` | Borra `working`. |
| `retire` | `published` | `status = retired`. `working` se conserva. |
| `republish` | `retired` | `status = published` con el `published` existente. `first_published_at` no cambia. |
| `delete` | `draft` con `first_published_at IS NULL` | Borra el artículo y sus contenidos (FR-009). |

Toda acción recibe `p_expected_revision`. Si no coincide, devuelve `ARTICLE_CONFLICT` (FR-010).

### Fuente del blog

```text
no row / migration_required = false  ──────────────▶  source "panel"
migration_required = true, cutover pending  ───────▶  source "legacy" (sin artículos)
   └─ complete_blog_cutover() si todo slug del manifiesto
      tiene un artículo published  ────────────────▶  cutover_completed_at = now() → "panel"
```

## Relationships and invariants

- `blog_articles 1 ── 0..2 blog_article_contents` (`published` y `working`).
- `organizations 1 ── 0..1 public_blog_source`, `1 ── * public_blog_cutover_items`, `1 ── * blog_articles`.
- Los idiomas exigidos vienen de `public_profiles` (016). La lectura pública filtra por los idiomas ofrecidos en ese momento (FR-023).
- La lectura pública solo une `blog_articles.status = 'published'` con su contenido `published` (FR-013 y FR-022).
- Ninguna escritura del blog toca productos, tarifas, solicitudes, cotizaciones ni reservas (FR-036).
