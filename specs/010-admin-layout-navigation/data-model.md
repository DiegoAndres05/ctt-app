# Data Model: Navegación lateral, listados y CMS guiado con vista previa

**Feature**: 010-admin-layout-navigation  
**Date**: 2026-09-30

Esta feature no crea tablas. Modela **vistas de presentación** sobre las entidades de 001, 002 y 009.

## Existing entities (unchanged)

| Entity | Source | Used for |
|--------|--------|----------|
| Collaborator (`user_profiles`) | 001 | Listado de usuarios, matriz de roles, barra superior |
| Role (`app_role`) | 001 | Visibilidad del menú, filtros, matriz |
| Audit event | 001 | Último acceso (`login_success`), pantalla Auditoría |
| Product / Experience / Accommodation / Package | 002 | Listados CMS, editor |
| Category / Add-on / Pricing scheme | 002 | Filtros, secciones del editor, ajustes |
| Public listing / Public image / Public category | 009 | Columnas del listado, preview, publicación |

## Presentation entities

### NavItem

Árbol estático. No se persiste.

| Field | Type | Notes |
|-------|------|-------|
| id | string | `dashboard`, `settings`, `cms`, `users`, `roles`, `audit`, `experiences`, `accommodations`, `packages`, `cms-settings`, `categories`, `public-categories`, `addons`, `cutover` |
| label | string | Texto del menú en español |
| path | string \| null | Ruta; `null` si solo agrupa |
| minRole | `admin` \| `operator` \| `agent` | Rol mínimo para ver el ítem |
| adminOnly | boolean | p.ej. cutover |
| children | NavItem[] | Submenús |
| hideForAgent | boolean | Ajustes del catálogo |

**Validation**: un ítem visible implica que su `path` (si existe) también está protegido con `roleGuard` equivalente o más estricto.

### ListQuery

Estado de un listado. Vive en query params.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| q | string | `''` | Nombre o correo; `ilike` |
| page | int ≥ 1 | `1` | 20 filas por página |
| role | `app_role` \| `''` | `''` | Solo usuarios |
| status | string \| `''` | `''` | Usuario: `active`/`inactive`. Producto: `draft`/`active`/`inactive` |
| publicStatus | `none` \| `draft` \| `published` \| `unpublished` \| `sold_out` \| `''` | `''` | Productos |
| placement | `catalog` \| `yacht` \| `''` | `''` | Solo experiencias |
| categoryId | uuid \| `''` | `''` | Categoría operativa |

**Rules**:
- Página fuera de rango → última página o vacío con «sin resultados».
- Al cambiar `q` o un filtro, `page` vuelve a 1.
- El enlace compartido reproduce el mismo `ListQuery`.

### UserListRow

| Field | Source |
|-------|--------|
| id, full_name, email, role, status, must_change_password | `user_profiles` |
| last_access_at | max(`audit.audit_events.created_at`) where `event_type = login_success` and `actor_id = id` |

### ProductListRow

| Field | Source |
|-------|--------|
| id, name, type, status | `products` |
| category_ids / category names | `product_categories` + `categories` |
| cover_thumb | `public_listings.cover_image_ref` o imagen `cover` |
| public_status | `none` si no hay ficha; si `sold_out` y published → `sold_out`; si no, `public_listings.status` |
| display_price, currency | `public_listings` |
| placement | `public_listings.placement` (`catalog`/`yacht` para experiencias; `lodging` para alojamientos) |

### PreviewListing

Modelo de la card. No se guarda.

| Field | Notes |
|-------|-------|
| variant | `catalog` \| `lodging` \| `yacht` |
| locale | `es` \| `en` |
| title | `name_es` / `name_en` |
| summary | primeros ~140 caracteres de la descripción del locale |
| categoryLabel | nombre de la categoría pública en el locale |
| location | ubicación / barrio según variante |
| imageUrl | URL de portada o `null` → marcador |
| displayPrice | número o `null`; en yate es opcional |
| currency | ISO, default de la org |
| soldOut | boolean |
| lodgingType / occupancy | solo `lodging` |
| missingLocale | `true` si el locale activo no tiene título o descripción |

**State**: se recalcula en el cliente a partir de los signals del formulario. Vacío → marcador, nunca el texto del otro idioma.

### ProductEditorDraft

Ciclo de vida en UI (el dominio no cambia):

```
empty form
    │ first save → create_product (draft)
    ▼
draft product (+ optional public listing draft)
    │ save listing / images / price
    │ set_product_status(active) when tariff exists
    │ publish_public_listing when 009 gates pass
    ▼
active + published
```

**Gates to publish** (inherited from 009, listed in the Publicación section):
- Producto `active`
- Tarifa vigente
- Foto principal
- Nombre y descripción en ES y EN
- Categoría pública y ubicación según placement
- Precio de vitrina (excepto yate)

### RoleMatrixRow

Estático.

| Section | admin | operator | agent |
|---------|-------|----------|-------|
| Dashboard | view | view | view |
| Usuarios / Roles / Auditoría | administer | — | — |
| Experiencias / Alojamientos / Paquetes | administer | edit | view |
| Ajustes del catálogo (categorías, adicionales, categorías públicas) | administer | edit | — |
| Publicación del sitio (cutover) | administer | — | — |

## Relationships

```
NavItem (static)
    └── filtered by Collaborator.role

ListQuery (URL)
    └── UserListRow[] | ProductListRow[]

ProductEditorDraft
    ├── Product + Experience | Accommodation | Package
    ├── PublicListing?
    └── PreviewListing (derived, not stored)

RoleMatrixRow (static)
    └── count of Collaborators per role (active)
```

## Validation rules (UI)

- Búsqueda: trim; no consultar hasta 300 ms sin teclear, o al cambiar un filtro.
- Página: 20 exactamente, salvo la última.
- Formulario: errores junto al campo; sección incompleta si algún obligatorio de esa sección falla.
- Salir con cambios: guard `CanDeactivate` que pregunta; Cancelar se queda.
- Agente: mismos campos, `readonly` / controles deshabilitados, sin botones de mutación.
