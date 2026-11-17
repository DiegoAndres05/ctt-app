# Public consumer contract: blog

Este contrato lo usa el sitio conectado a una agencia, con la clave `anon` de Supabase. La agencia se resuelve igual que en 016 (`specs/016-multiagency-public-cms/contracts/public-consumer.md`):

- `*_by_key(p_key, …)`: la clave pública de la agencia. Es el mecanismo general.
- `(p_organization_id, …)`: solo para CTT, mientras dure su transición de identificador. Con una sesión de panel se usa la organización del JWT y el argumento se ignora (vista previa).

Una clave inválida, revocada, vencida, inexistente o de una agencia no activa produce siempre el mismo error:

```text
PUBLIC_ACCESS_UNAVAILABLE
```

## List articles

```ts
await supabase.rpc('get_public_blog_by_key', {
  p_key: publicKey,
  p_page: 1, // >= 1
  p_page_size: 12, // 1..50, por defecto 12
});
// Transición CTT: get_public_blog({ p_organization_id, p_page, p_page_size })
```

```json
{
  "source": "panel",
  "languages": ["es", "en"],
  "page": 1,
  "pageSize": 12,
  "total": 37,
  "generatedAt": "2026-11-17T16:00:00Z",
  "articles": [
    {
      "slug": "que-ver-en-cartagena",
      "cover": "<org>/blog/<id>/<uuid>.webp",
      "publishedAt": "2026-11-17T15:00:00Z",
      "updatedAt": "2026-11-17T15:40:00Z",
      "es": { "title": "…", "summary": "…", "coverAlt": "…" },
      "en": { "title": "…", "summary": "…", "coverAlt": "…" }
    }
  ]
}
```

- **Orden**: `publishedAt` descendente y, en caso de empate, `slug` (FR-024).
- **Idiomas**: solo vienen las claves de los idiomas de `languages`, es decir, los que la agencia ofrece ahora (FR-023).
- **`source: "legacy"`**: la agencia está migrando su blog y no completó el cambio de fuente. `articles` llega vacío y `total` vale 0. El sitio debe seguir leyendo su blog anterior (FR-030).
- **Sin artículos**: `source: "panel"` con `articles: []`. Una agencia sin artículos no es un error.

## Read one article

```ts
await supabase.rpc('get_public_blog_article_by_key', { p_key: publicKey, p_slug: 'que-ver-en-cartagena' });
// Transición CTT: get_public_blog_article({ p_organization_id, p_slug })
```

```json
{
  "found": true,
  "slug": "que-ver-en-cartagena",
  "cover": "<org>/blog/<id>/<uuid>.webp",
  "publishedAt": "2026-11-17T15:00:00Z",
  "updatedAt": "2026-11-17T15:40:00Z",
  "es": {
    "title": "Qué ver en Cartagena",
    "summary": "…",
    "coverAlt": "…",
    "seoTitle": "Qué ver en Cartagena",
    "seoDescription": "…",
    "body": [
      { "type": "heading", "level": 2, "text": [{ "text": "La ciudad amurallada" }] },
      {
        "type": "paragraph",
        "text": [
          { "text": "Empieza por la " },
          { "text": "Torre del Reloj", "bold": true },
          { "text": "." }
        ]
      },
      { "type": "image", "src": "<org>/blog/<id>/<uuid>.webp", "alt": "Torre del Reloj al atardecer", "decorative": false },
      { "type": "list", "ordered": false, "items": [[{ "text": "Getsemaní" }], [{ "text": "San Diego" }]] },
      { "type": "quote", "text": [{ "text": "…" }] }
    ]
  },
  "en": {}
}
```

- **SEO**: `seoTitle` y `seoDescription` siempre vienen rellenos. Si la agencia no los escribió, se usan el título y el resumen (FR-005).
- **No encontrado**: un slug inexistente, en borrador, retirado o de otra agencia, o una agencia en `legacy`, devuelve exactamente `{"found": false}` (FR-026).
- **Lo que nunca viene**: autores, usuarios, revisiones en curso, estado, `revision`, notas ni datos de otra agencia (FR-022).

## Referencias de imagen

`cover` e `image.src` siguen la misma convención que las imágenes de `get_public_site`:

- **Ruta de Storage** (no empieza por `https://`): el sitio arma la URL como `<SUPABASE_URL>/storage/v1/object/public/catalog-media/<ruta>`.
- **URL `https://`**: solo la usan los artículos migrados (imágenes que siguen alojadas en el blog anterior). El sitio la usa tal cual.

## Rendering rules for consumers

| Bloque | Mapeo sugerido |
| --- | --- |
| `paragraph` | `<p>` |
| `heading` | `<h2>` o `<h3>` según `level`. El `<h1>` es el título del artículo. |
| `list` | `<ul>` u `<ol>` con un `<li>` por ítem |
| `quote` | `<blockquote>` |
| `image` | `<img src alt>`. Si `decorative` es verdadero, `alt=""`. |
| inline | `bold` → `<strong>`, `italic` → `<em>`, `href` → `<a href rel="noopener">` |

- Todo texto llega como texto plano y el sitio debe escaparlo. No hay HTML en la respuesta.
- Un bloque de tipo desconocido debe ignorarse, para que el sitio siga funcionando si en el futuro se añaden tipos.

## Routes, caching and freshness

- **Rutas**: la plataforma no fija la URL. El sitio arma, por ejemplo, `/blog/<slug>` y `/en/blog/<slug>` (FR-027).
- **Caché**: si el sitio guarda copia de una respuesta, debe descartarla en **300 segundos o menos**. Así, una publicación, un cambio publicado o un retiro se ve en 5 minutos como máximo (FR-029). `updatedAt` y `generatedAt` sirven para revalidar.
- **Independencia del catálogo**: el blog se lee con llamadas separadas de `get_public_site`. Si estas fallan, el sitio debe seguir mostrando el catálogo y aceptando solicitudes (FR-037).
