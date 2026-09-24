# API Contracts: Contenido público del catálogo

**Module**: 009-catalog-site-cms | **Date**: 2026-09-23

Dos superficies:

1. **Panel** — RPC autenticadas. Reutilizan el JWT de 001 (`organization_id`, `app_role`) y `require_catalog_manager()` de 002.
2. **Página pública** — `get_public_site`, ejecutable por `anon` y por usuarios autenticados. No acepta `organization_id` elegido por el cliente de otra agencia: el sitio público de cada agencia llama con el identificador de su propia organización, y la función solo devuelve fichas de esa organización. Un usuario autenticado que llame la función sigue limitado a la organización de su JWT si no se trata de la lectura anónima del sitio.

La forma pública usa los nombres de campo que la página ya consume. El detalle de columnas está en [data-model.md](../data-model.md).

---

## POST /rest/v1/rpc/save_public_listing

**Authenticated**: Sí | **Role**: `operator`, `admin`

Crea o actualiza la ficha en `draft` o conserva `published` si ya lo estaba y el guardado sigue siendo válido para estar publicada. No cambia `pricing_schemes`.

### Request

```json
{
  "product_id": "uuid",
  "placement": "catalog | lodging | yacht",
  "public_slug": "islas-capri-premium",
  "name_es": "string",
  "name_en": "string",
  "description_es": "string",
  "description_en": "string",
  "public_category_id": "islas",
  "location": "Islas del Rosario",
  "meeting_point": "string | null",
  "schedule": "string | null",
  "duration": "string | null",
  "max_guests": 12,
  "featured": false,
  "rating": 4.9,
  "display_price": 500950,
  "original_price": 625950,
  "currency": "COP",
  "includes": [{ "es": "Transporte", "en": "Transport" }],
  "warnings": [{ "es": "string", "en": "string" }],
  "lodging": null,
  "yacht_lines": []
}
```

`lodging` es obligatorio cuando `placement = lodging` y trae `lodging_type`, `location_es`, `location_en`, `neighborhood_es`, `neighborhood_en`, `bedrooms`, `bathrooms`, `amenities`, `tags`, `map_url`.

`yacht_lines` es la lista `{ kind, position, icon, text_es, text_en }` cuando `placement = yacht`.

### Response 200

`{ "id": "uuid", "status": "draft | published | unpublished" }`

### Errors

| Código | Cuándo |
|--------|--------|
| `PUBLIC_SLUG_IMMUTABLE` | El slug cambia después de `first_published_at`. |
| `PUBLIC_SLUG_TAKEN` | Otro producto de la agencia ya usa el slug. |
| `PLACEMENT_PRODUCT_MISMATCH` | El tipo de producto no admite esa sección. |
| `ORIGINAL_PRICE_NOT_HIGHER` | El precio anterior no supera al actual. |
| `BILINGUAL_PAIR_INCOMPLETE` | Falta `es` o `en` en un par. |
| `FORBIDDEN` | Rol `agent` o producto de otra organización. |

---

## POST /rest/v1/rpc/publish_public_listing

**Authenticated**: Sí | **Role**: `operator`, `admin`

### Request

`{ "listing_id": "uuid" }`

### Response 200

`{ "status": "published", "first_published_at": "timestamptz" }`

### Errors

| Código | Cuándo |
|--------|--------|
| `PUBLIC_LISTING_INCOMPLETE` | Falta un campo obligatorio del placement, la portada o un par bilingüe. |
| `PRODUCT_NOT_ACTIVE` | El producto no está `active`. |
| `PRODUCT_HAS_NO_VALID_PRICE` | No hay tarifa vigente. Heredado de 002. El mensaje indica que la vitrina no sustituye a la tarifa. |

Registra `public_listing_published`.

---

## POST /rest/v1/rpc/unpublish_public_listing

**Authenticated**: Sí | **Role**: `operator`, `admin`

`{ "listing_id": "uuid" }` → `{ "status": "unpublished" }`

Registra `public_listing_unpublished`. No borra el producto ni la tarifa.

---

## POST /rest/v1/rpc/set_public_listing_sold_out

**Authenticated**: Sí | **Role**: `operator`, `admin`

`{ "listing_id": "uuid", "sold_out": true }`

Solo si `status = published`. Registra `public_listing_sold_out_changed` con el valor anterior y el nuevo. No modifica `pricing_schemes` ni `products.status`.

---

## POST /rest/v1/rpc/attach_public_image

**Authenticated**: Sí | **Role**: `operator`, `admin`

El archivo ya está en el bucket `catalog-media`, o se adjunta una referencia copiada.

```json
{
  "listing_id": "uuid",
  "role": "cover | gallery",
  "storage_path": "org/listing/image",
  "external_ref": null,
  "sort_order": 0
}
```

Exactamente uno de `storage_path` o `external_ref`. Reemplazar la portada conserva la fila anterior, registra `public_image_replaced` y actualiza `cover_image_ref`.

### Errors

| Código | Cuándo |
|--------|--------|
| `IMAGE_TOO_LARGE` | Más de 10 MB. |
| `IMAGE_TYPE_NOT_ALLOWED` | Distinto de JPEG, PNG o WebP. |
| `COVER_REQUIRED` | Se intenta quitar la única portada de una ficha publicada. |
| `GALLERY_ONLY_FOR_LODGING` | `role = gallery` fuera de `lodging`. |

---

## POST /rest/v1/rpc/reorder_public_gallery

**Authenticated**: Sí | **Role**: `operator`, `admin`

`{ "listing_id": "uuid", "image_ids": ["uuid"] }`

El orden del arreglo es el orden público. Solo galerías de alojamiento. La portada debe seguir incluida.

---

## POST /rest/v1/rpc/save_guest_review

**Authenticated**: Sí | **Role**: `operator`, `admin`

```json
{
  "listing_id": "uuid",
  "review_id": "uuid | null",
  "author": "string",
  "rating": 5,
  "text_es": "string",
  "text_en": "string",
  "reviewed_on": "2026-09-23"
}
```

Solo `lodging`. `review_id` nulo crea la opinión.

---

## POST /rest/v1/rpc/save_public_category

**Authenticated**: Sí | **Role**: `operator`, `admin`

```json
{
  "id": "nueva_categoria",
  "name_es": "string",
  "name_en": "string",
  "is_active": true
}
```

Las ocho categorías protegidas no se eliminan. Desactivar una categoría que todavía usa una ficha `published` responde `CATEGORY_IN_USE`.

---

## POST /rest/v1/rpc/complete_public_cutover

**Authenticated**: Sí | **Role**: `operator`, `admin`

Sin argumentos de organización: usa la del JWT.

### Response 200

`{ "source": "panel", "cutover_completed_at": "timestamptz" }`

### Errors

| Código | Cuándo |
|--------|--------|
| `CUTOVER_INCOMPLETE` | Devuelve la lista de `public_slug` del manifiesto sin ficha `published` de producto `active`. `source` sigue `legacy`. |
| `CUTOVER_ALREADY_COMPLETED` | La fuente ya es `panel`. |

Registra `public_cutover_completed`.

---

## POST /rest/v1/rpc/get_public_site

**Authenticated**: No. `anon` y `authenticated`.

```json
{ "organization_id": "uuid" }
```

### Response 200

```json
{
  "source": "legacy | panel",
  "offers": [],
  "lodgings": [],
  "yachts": []
}
```

Si `source = legacy`, los tres arreglos van vacíos. El consumidor debe seguir mostrando su contenido actual.

Si `source = panel`, cada arreglo trae solo fichas `published` de productos `active`. Un borrador, una ficha `unpublished` o un producto `inactive` no aparece.

### Offer

Misma forma que la página, más disponibilidad:

```json
{
  "id": "islas-capri-premium",
  "name": "string",
  "nameEn": "string",
  "category": "islas",
  "description": "string",
  "descriptionEn": "string",
  "image": "https://... o /images/...",
  "includes": ["string"],
  "includesEn": ["string"],
  "meetingPoint": "string",
  "schedule": "string",
  "duration": "string",
  "maxGuests": 12,
  "warnings": ["string"],
  "warningsEn": ["string"],
  "featured": true,
  "location": "string",
  "rating": 5,
  "price": 500950,
  "originalPrice": 625950,
  "currency": "COP",
  "soldOut": false,
  "acceptsRequests": true
}
```

Los opcionales se omiten cuando no tienen valor. `acceptsRequests` es `false` cuando `soldOut` es `true`.

### Lodging

`id`, `name`, `nameEn`, `type`, `location`, `locationEn`, `neighborhood`, `neighborhoodEn`, `description`, `descriptionEn`, `pricePerNight`, `currency`, `maxGuests`, `bedrooms`, `bathrooms`, `image`, `gallery`, `amenities`, `tags`, `rating`, `reviewCount`, `reviews`, `mapUrl`, `featured`, `soldOut`, `acceptsRequests`.

`reviews[]`: `author`, `rating`, `text`, `textEn`, `date`. `reviewCount` es `reviews.length`.

### Yacht

```json
{
  "id": "azimut-70",
  "name": "AZIMUT 70",
  "nameEn": "AZIMUT 70",
  "description": "string",
  "descriptionEn": "string",
  "image": "string",
  "capacity": [{ "icon": "people", "text": "string", "textEn": "string" }],
  "features": [{ "icon": "boat", "text": "string", "textEn": "string" }],
  "price": null,
  "currency": null,
  "soldOut": false,
  "acceptsRequests": true
}
```

`price` y `currency` se omiten cuando el yate no tiene precio de vitrina.

### Regla del consumidor

Con `source = panel` la página no mezcla esta respuesta con el listado anterior. Un yate no se pinta en ofertas ni en hospedaje. Una oferta no se pinta como alojamiento ni como yate.

---

## Storage: `catalog-media`

| Operación | Quién |
|-----------|--------|
| Insert / update en `{organization_id}/**` | `operator`, `admin` de esa organización |
| Lectura | Pública por URL, solo para mostrar la referencia guardada en una ficha |

Límite 10 MB. MIME permitidos: `image/jpeg`, `image/png`, `image/webp`.
