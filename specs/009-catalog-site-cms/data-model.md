# Data Model: Contenido público del catálogo

**Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

Extiende el catálogo de 002. No cambia el significado de `products`, `pricing_schemes` ni `categories`.

## Enums

### `public_placement`

`catalog` | `lodging` | `yacht`

### `public_listing_status`

`draft` | `published` | `unpublished`

### `public_source`

`legacy` | `panel`

### `public_image_role`

`cover` | `gallery`

### `lodging_type`

`casa` | `apartamento` | `finca` | `habitacion`

### `yacht_icon`

`people` | `bed` | `shower` | `droplet` | `armchair` | `boat` | `kitchen` | `star` | `snow` | `users` | `sun` | `music` | `map`

### `lodging_amenity`

`wifi` | `pool` | `ac` | `kitchen` | `parking` | `terrace` | `washer` | `tv` | `bbq`

### Audit events (extensión de `audit.audit_event_type`)

`public_listing_published` | `public_listing_unpublished` | `public_image_replaced` | `public_listing_sold_out_changed` | `public_cutover_completed`

## 1. Public category

Filtro del catálogo público. No reemplaza `categories` de 002.

| Campo | Regla |
|-------|--------|
| `id` | Texto estable. Único por organización. Minúsculas, números y `_`. |
| `organization_id` | Dueña. |
| `name_es`, `name_en` | Obligatorios y no vacíos. |
| `is_active` | Una categoría inactiva no se asigna a fichas nuevas. |
| `protected` | Las ocho iniciales quedan `protected = true` y no se eliminan. |

Iniciales: `islas`, `baru`, `tierra_bomba`, `compartidos`, `cultural`, `aventura`, `baile`, `premium`.

## 2. Public site

Una fila por organización.

| Campo | Regla |
|-------|--------|
| `organization_id` | PK. |
| `source` | `legacy` al crear. Solo `complete_public_cutover` la pasa a `panel`. |
| `cutover_completed_at` | Nulo hasta el cambio. |
| `cutover_completed_by` | Usuario que completó el cambio. |

## 3. Public listing

Ficha 1:1 con un producto.

| Campo | Regla |
|-------|--------|
| `id` | UUID. |
| `organization_id` | Igual a la del producto. |
| `product_id` | Único. FK compuesta a `products (id, organization_id)`. |
| `placement` | Ver compatibilidad abajo. Inmutable después de la primera publicación. |
| `public_slug` | Único por organización. `^[a-z0-9]+(-[a-z0-9]+)*$`. Inmutable después de la primera publicación. |
| `status` | `draft`, `published`, `unpublished`. |
| `sold_out` | Solo tiene efecto público si `status = published`. Default `false`. |
| `name_es`, `name_en` | Obligatorios para publicar. |
| `description_es`, `description_en` | Obligatorios para publicar. |
| `cover_image_ref` | Referencia que la página puede mostrar. Obligatoria para publicar. |
| `public_category_id` | Obligatoria si `placement = catalog`. Nula en `yacht`. |
| `location` | Obligatoria en `catalog`. |
| `meeting_point`, `schedule`, `duration` | Opcionales. Solo `catalog`. |
| `max_guests` | Opcional en `catalog`. Obligatorio y positivo en `lodging`. |
| `featured` | Default `false`. |
| `rating` | Nulo o entre 0 y 5. |
| `display_price` | Obligatorio para publicar `catalog` y `lodging`. Opcional en `yacht`. Si se informa, `> 0`. |
| `original_price` | Opcional. Si se informa, debe ser mayor que `display_price`. |
| `currency` | Obligatoria cuando hay `display_price`. ISO 4217. |
| `includes` | Lista de `{es, en}`. Obligatoria y no vacía para publicar `catalog`. |
| `warnings` | Lista de `{es, en}`. Vacía o ambos idiomas en cada ítem. |
| `lodging` | Objeto obligatorio si `placement = lodging`. Ver sección 4. |
| `yacht_lines` | Lista obligatoria si `placement = yacht`. Ver sección 5. |
| `first_published_at` | Se fija en la primera publicación y no cambia. |
| `published_at`, `updated_at` | Última publicación y última edición. |

**Compatibilidad**:

| `placement` | `products.type` |
|-------------|-----------------|
| `catalog` | `experience` o `package` |
| `lodging` | `accommodation` |
| `yacht` | `experience` |

**Publicar** exige, además de los campos de la ficha, que el producto esté `active`. Si el producto pasa a `inactive`, la lectura pública lo oculta aunque la ficha siga `published`. Al reactivarlo no se republica sola: la ficha debe pasar de nuevo por publicar si estaba `unpublished`. Si estaba `published` y el producto vuelve a `active`, vuelve a verse; el spec pide que desactivar oculte y que reactivar no publique automáticamente una ficha que se despublicó. Una ficha que sigue `published` reaparece al reactivar. Una ficha puesta en `unpublished` por la desactivación no vuelve sola.

**Decisión de desactivación**: al pasar el producto a `inactive`, la ficha `published` pasa a `unpublished` y se registra el actor del cambio de estado del producto. Así reactivar no la muestra hasta una publicación nueva (FR-019).

## 4. Lodging details

Incrustados en la ficha `lodging`, no en una segunda ficha.

| Campo | Regla |
|-------|--------|
| `lodging_type` | `casa`, `apartamento`, `finca` o `habitacion`. |
| `location_es`, `location_en` | Obligatorios para publicar. |
| `neighborhood_es`, `neighborhood_en` | Obligatorios para publicar. |
| `bedrooms`, `bathrooms` | Enteros `>= 0`. |
| `amenities` | Subconjunto del enum. Sin duplicados. |
| `tags` | Lista de textos. |
| `map_url` | Opcional. Si se informa, es una URL `https`. |
| `gallery` | Ver imágenes. La portada forma parte de la galería. |

## 5. Yacht lines

Lista ordenada en la ficha `yacht`.

| Campo | Regla |
|-------|--------|
| `kind` | `capacity` o `feature`. |
| `position` | Orden dentro de su `kind`. |
| `icon` | Opcional. Uno de `yacht_icon`. |
| `text_es`, `text_en` | Ambos obligatorios. |

Para publicar: al menos una línea `capacity` y una `feature`.

## 6. Public image

| Campo | Regla |
|-------|--------|
| `id` | UUID. |
| `listing_id`, `organization_id` | FK a la ficha. |
| `role` | `cover` o `gallery`. Una sola `cover` por ficha. |
| `sort_order` | Orden de galería. La portada también tiene orden. |
| `storage_path` | Nulo si la imagen es una referencia copiada. |
| `external_ref` | Ruta o URL ya publicada. Exactamente uno de `storage_path` o `external_ref`. |
| `replaced_at` | Se informa cuando deja de ser la imagen vigente. Las filas reemplazadas se conservan para auditoría, no salen en la lectura pública. |

Quitar la única portada de una ficha `published` se rechaza.

## 7. Guest review

Solo fichas `lodging`.

| Campo | Regla |
|-------|--------|
| `author` | No vacío. |
| `rating` | Entero de 1 a 5. |
| `text_es`, `text_en` | Ambos obligatorios. |
| `reviewed_on` | Fecha. |

`review_count` de la lectura pública es la cantidad de filas, no un número editable.

## 8. Cutover item

Manifiesto de lo que la página muestra el día de la planificación. Una fila por identificador público requerido.

| Campo | Regla |
|-------|--------|
| `organization_id` | Agencia dueña de la página. |
| `public_slug` | Identificador que debe existir publicado. |
| `placement` | Sección de origen. |
| `listing_id` | Se llena cuando la semilla o el gestor crea la ficha. |

`complete_public_cutover` exige una ficha `published` y un producto `active` para cada fila.

### Manifiesto inicial

Ofertas (`catalog`), copiadas como `experience`:

`islas-capri-premium`, `islas-capri-classic`, `islas-borabora-vip`, `islas-borabora-club`, `baru-aura`, `baru-puerto-medallo`, `baru-nena-beach`, `baru-cabana-geronimo`, `tierra-fenix-pasadia`, `tierra-fenix-cena`, `tierra-makani`, `tierra-isla-real`, `tour-5-clasicos`, `tour-cholon-party`, `tour-4-destinos`, `tour-aviario-playa`, `tour-5-clasicos-openbar`, `cultural-chiva`, `cultural-van`, `cultural-pintura`, `cultural-rones`, `cultural-cocina`, `aventura-atv-adrenalina`, `aventura-atv-full`, `aventura-acuaticos`, `baile-latinos-azotea`, `premium-volcan`, `premium-sibarita`, `premium-botes`.

Alojamientos (`lodging`):

`villa-caribe`, `apartamento-centro-historico`, `casa-del-mar`, `loft-cartagena`, `finca-la-paz`, `suite-real`.

Yates (`yacht`), identificadores nuevos porque la página no les da una dirección propia:

`azimut-70`, `leopard-51`, `firpol-42`, `bravo-380`.

## Relaciones

```text
organizations 1──1 public_sites
organizations 1──* public_categories
organizations 1──* public_cutover_items
products      1──1 public_listings
public_listings *──1 public_categories   (solo placement catalog)
public_listings 1──* public_images
public_listings 1──* guest_reviews       (solo lodging)
public_listings *──1 public_cutover_items
```

## Transiciones

```text
draft ──publicar──► published ──despublicar──► unpublished
unpublished ──publicar──► published
published ──producto inactive──► unpublished
sold_out false ◄──► true        (solo mientras published; no cambia status)
source legacy ──complete_public_cutover──► panel
```

No hay vuelta de `panel` a `legacy`.

## Validación que no vive en la ficha

- La tarifa inicial de una oferta copiada usa `display_price`, `currency` y `per_person`.
- La tarifa inicial de un alojamiento copiado usa `display_price`, `currency` y `per_night`.
- Editar `display_price` no inserta ni cierra filas de `pricing_schemes`.
- Un yate copiado no recibe `display_price`. Publicarlo exige una tarifa vigente creada con el flujo de 002.
- `agent` lee. `operator` y `admin` escriben. `anon` solo recibe la proyección publicada de `get_public_site`.
