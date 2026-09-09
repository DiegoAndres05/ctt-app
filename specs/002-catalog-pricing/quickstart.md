# Quickstart: 002-catalog-pricing

**Date**: 2026-09-09 | **Spec**: [spec.md](./spec.md) | **Data Model**: [data-model.md](./data-model.md) | **Contracts**: [contracts/api-contracts.md](./contracts/api-contracts.md)

Esta guía valida la capacidad **Catálogo & Precios** de extremo a extremo. Reutiliza la app Angular + Supabase y el aislamiento multi-tenant de la feature `001-auth-tenant-access`.

---

## Prerequisites

- Feature `001-auth-tenant-access` desplegada (organizaciones, `user_profiles`, claims JWT `organization_id`/`app_role`, esquema `audit`).
- Node.js 20+ y Angular CLI 22+.
- Docker (para los tests SQL en Postgres 17).
- Una organización con un usuario `admin` y un usuario `operator` activos (semilla de 001).

---

## Setup Commands

### 1. Base de Datos (Supabase)

```bash
# Aplicar migraciones incrementales de catálogo/precios (011+)
supabase db push --db-url "$DATABASE_URL"

# Ejecutar la suite SQL de esta feature en Postgres 17 dockerizado
./supabase/tests/run-sql-tests.sh
```

### 2. Frontend Angular

```bash
npm install
npm start   # http://localhost:4200
```

---

## Validation Scenarios

### Escenario 1: Alta de Experiencia y Alojamiento (US1)

**Goal**: Crear los dos ítems base del inventario y verlos en el catálogo.

Pasos: login como `operator` → `/catalog/products/new` → crear una Experiencia (nombre, duración, dificultad, capacidad) y un Alojamiento (tipo, ubicación, ocupación).

**Expected Outcome**:
- Ambos productos se crean en estado `draft`.
- Aparecen en el listado del catálogo interno filtrable por `type`.
- Ver contrato: `POST /rest/v1/rpc/create_product`.

---

### Escenario 2: Producto sin precio no se activa (Edge Case + R-008)

**Goal**: Verificar que un producto sin esquema de precio válido no puede activarse.

Pasos: intentar `set_product_status(product_id, 'active')` sobre un producto sin precio.

**Expected Outcome**:
- La operación falla con `PRODUCT_HAS_NO_VALID_PRICE` (409).
- Tras crear un `pricing_scheme` vigente, la activación tiene éxito.

**Verification SQL**:
```sql
-- Debe fallar
SELECT set_product_status('<product_id>', 'active');
-- => ERROR PRODUCT_HAS_NO_VALID_PRICE
```

---

### Escenario 3: Precios por temporada y anti-solapamiento (US4 + R-004)

**Goal**: Configurar tarifa base y de temporada; validar que no se permiten rangos solapados.

Pasos: como `admin`, crear un `pricing_scheme` base y uno de temporada (`season_start`/`season_end`); luego intentar otro que se solape.

**Expected Outcome**:
- La primera temporada se crea correctamente.
- El segundo esquema solapado falla con `SEASON_OVERLAP` (409).
- `resolve_price(product_id, on_date, charge_type)` devuelve la tarifa de temporada dentro del rango y la base fuera de él (SC-003).

**Verification SQL**:
```sql
SELECT * FROM resolve_price('<product_id>', '2026-12-20', 'per_person'); -- source = 'season'
SELECT * FROM resolve_price('<product_id>', '2026-06-20', 'per_person'); -- source = 'base'
```

---

### Escenario 4: No afectación retroactiva al cambiar el precio (SC-002 + R-003)

**Goal**: Verificar que actualizar un precio no muta versiones históricas.

Pasos: crear una tarifa, versionarla con `upsert_pricing_scheme` (nuevo monto).

**Expected Outcome**:
- La versión anterior conserva su `base_amount` y recibe `valid_to = now()`.
- La nueva versión queda vigente (`valid_to IS NULL`).
- Ninguna fila histórica cambia su `base_amount`.

---

### Escenario 5: Sobreescritura manual auditada (US4 escenario 2)

**Goal**: Registrar un ajuste manual de precio con trazabilidad.

Pasos: como `admin`, `apply_price_override(product_id, new_amount, reason)`.

**Expected Outcome**:
- Se genera un evento `audit.audit_events` con `event_type = 'price_overridden'`, actor, organización, `previous_amount`, `new_amount` y `reason`.
- Un `operator` o `agent` recibe `INSUFFICIENT_PERMISSIONS` al intentarlo.

---

### Escenario 6: Composición de Paquete e inconsistencia (US3)

**Goal**: Crear un paquete y detectar componentes inactivos.

Pasos: `create_package` con una experiencia + dos noches de alojamiento; luego desactivar un componente.

**Expected Outcome**:
- El paquete queda como producto único con su itinerario.
- No se permiten paquetes anidados (`PACKAGE_NESTING_NOT_ALLOWED`).
- Al desactivar un componente, `get_package_consistency` reporta la inconsistencia (advertencia, sin auto-desactivar).

---

### Escenario 7: Aislamiento multi-tenant del catálogo (SC-002 aislamiento)

**Goal**: Verificar que el catálogo de una organización no es visible para otra.

Pasos: con sesión de Organización A crear productos; con sesión de Organización B listar el catálogo.

**Expected Outcome**:
- B no ve productos, categorías, add-ons ni precios de A.
- El acceso por ID directo cross-tenant retorna vacío/404.
- Cubierto por `supabase/tests/catalog_rls_test.sql`.

---

### Escenario 8: Add-ons y reglas de aplicabilidad (US2)

**Goal**: Crear un add-on y vincularlo como opción de una experiencia.

Pasos: crear "Transporte privado" → vincular a una experiencia con `is_mandatory`/`max_quantity`.

**Expected Outcome**:
- El add-on queda consultable como complemento elegible del producto.
- Las reglas de compatibilidad quedan disponibles para el módulo de cotización (feature 005).
