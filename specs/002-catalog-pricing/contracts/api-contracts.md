# API Contracts: Catalog & Pricing

**Module**: 002-catalog-pricing | **Date**: 2026-09-09

Se expone principalmente vía **Supabase PostgREST** (tablas con RLS) y **RPCs** para operaciones con reglas de negocio (activación, versionado de precios, sobreescrituras). Todas las llamadas requieren JWT autenticado con claims `organization_id` y `app_role` (feature 001). RLS filtra por organización automáticamente.

---

## GET /rest/v1/products (Listar catálogo interno)

**Authenticated**: Sí | **Role**: cualquier rol de la organización (`agent`/`operator`/`admin`)

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `type` | `string` | No | `experience` \| `accommodation` \| `package` |
| `status` | `string` | No | `draft` \| `active` \| `inactive` |
| `category_id` | `uuid` | No | Filtrar por categoría |
| `limit` / `offset` | `integer` | No | Paginación (default 50, max 200) |

### Response 200 OK

```json
{
  "data": [
    {
      "id": "uuid",
      "type": "experience",
      "name": "string",
      "status": "active",
      "provider_id": "uuid | null",
      "categories": ["uuid"],
      "created_at": "timestamptz"
    }
  ],
  "count": "integer"
}
```

> Nota: la respuesta debe cumplir SC-004 (< 1s para hasta 5,000 ítems por organización).

---

## POST /rest/v1/rpc/create_product (Crear Experiencia o Alojamiento)

**Authenticated**: Sí | **Role**: `operator` | `admin`

**Purpose**: Crea el registro base `products` + su subtipo (`experiences` o `accommodations`) atómicamente en estado `draft`.

### Request Body

```json
{
  "type": "experience | accommodation",
  "name": "string (required, max 255)",
  "description": "string",
  "provider_id": "uuid | null",
  "category_ids": ["uuid"],
  "experience": {
    "duration_minutes": 120,
    "difficulty": "easy | moderate | hard",
    "meeting_point": "string",
    "min_capacity": 1,
    "max_capacity": 10
  },
  "accommodation": {
    "property_type": "cabana",
    "location": "string",
    "check_in": "14:00",
    "check_out": "11:00",
    "max_occupancy": 4,
    "occupancy_rules": {}
  }
}
```

### Response 201 Created

```json
{ "data": { "id": "uuid", "status": "draft" } }
```

### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Campos inválidos (ej. `max_capacity < min_capacity`) |
| 403 | `INSUFFICIENT_PERMISSIONS` | Rol sin permiso de gestión |

---

## POST /rest/v1/rpc/set_product_status (Activar/Desactivar producto)

**Authenticated**: Sí | **Role**: `operator` | `admin`

**Purpose**: Cambia el estado de un producto con validación de reglas.

### Request Body

```json
{ "product_id": "uuid", "status": "active | inactive" }
```

### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 409 | `PRODUCT_HAS_NO_VALID_PRICE` | No puede activarse sin un esquema de precio vigente (R-008) |
| 403 | `INSUFFICIENT_PERMISSIONS` | Rol sin permiso |

---

## POST /rest/v1/rpc/upsert_pricing_scheme (Definir / versionar precio)

**Authenticated**: Sí | **Role**: `operator` | `admin`

**Purpose**: Crea o versiona un esquema de precios (base o de temporada) para un producto o add-on. Un cambio de monto cierra la versión vigente (`valid_to = now()`) e inserta una nueva (append-only, no-retroactivo).

### Request Body

```json
{
  "product_id": "uuid | null",
  "addon_id": "uuid | null",
  "currency": "COP",
  "base_amount": 150000.00,
  "charge_type": "per_person | per_night | per_group",
  "season_start": "2026-12-01 | null",
  "season_end": "2027-01-15 | null"
}
```

### Response 201 Created

```json
{ "data": { "id": "uuid", "valid_from": "timestamptz" } }
```

### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | `INVALID_PRICE_TARGET` | No se cumple XOR product_id/addon_id |
| 409 | `SEASON_OVERLAP` | El rango de temporada se solapa con otro vigente (R-004) |
| 400 | `INVALID_SEASON_RANGE` | `season_start > season_end` |
| 403 | `INSUFFICIENT_PERMISSIONS` | No es admin |

---

## POST /rest/v1/rpc/apply_price_override (Sobreescritura manual de precio)

**Authenticated**: Sí | **Role**: `admin`

**Purpose**: Registra un ajuste manual autorizado; persiste el motivo, valor anterior y nuevo en auditoría (US4 escenario 2).

### Request Body

```json
{
  "product_id": "uuid",
  "new_amount": 175000.00,
  "reason": "string (required)"
}
```

### Response 200 OK

```json
{
  "data": {
    "pricing_scheme_id": "uuid",
    "previous_amount": 150000.00,
    "new_amount": 175000.00
  }
}
```

> Genera un evento `audit.audit_events` con `event_type = 'price_overridden'` (actor, org, previous/new, reason).

---

## GET /rest/v1/rpc/resolve_price (Calcular precio vigente por fecha)

**Authenticated**: Sí | **Role**: cualquier rol de la organización

**Purpose**: Devuelve la tarifa vigente para un producto en una fecha (aplica temporada o base). Determinista (SC-003).

### Request Body / Params

```json
{ "product_id": "uuid", "on_date": "2026-12-20", "charge_type": "per_person" }
```

### Response 200 OK

```json
{ "data": { "currency": "COP", "amount": 180000.00, "source": "season | base" } }
```

---

## Package endpoints

- **POST /rest/v1/rpc/create_package** — crea `products(type=package)` + `packages` + `package_items` (roles `operator`/`admin`). Rechaza componentes de tipo `package` (`PACKAGE_NESTING_NOT_ALLOWED`) y componentes de otra organización.
- **GET /rest/v1/rpc/get_package_consistency** — devuelve advertencias si algún componente está `inactive` (US3 escenario 2).

---

## Add-on endpoints (PostgREST + RLS)

- **POST /rest/v1/add_ons** — crear complemento (`operator`/`admin`).
- **POST /rest/v1/product_addons** — vincular add-on a un producto con reglas (`is_mandatory`, `max_quantity`).
- **GET /rest/v1/product_addons?product_id=eq.<id>** — listar complementos elegibles de un producto.

---

## Contratos transversales

- **Aislamiento**: toda respuesta está pre-filtrada por RLS según `organization_id`; el acceso cross-tenant devuelve vacío/404.
- **Auditoría**: `apply_price_override` y cambios de estado sensibles generan eventos en `audit.audit_events`.
- **No-retroactividad**: `upsert_pricing_scheme`/`apply_price_override` nunca mutan versiones históricas (append-only).
