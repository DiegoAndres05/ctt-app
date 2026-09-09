# Research: 002-catalog-pricing

**Date**: 2026-09-09 | **Spec**: [spec.md](./spec.md)

---

## R-001: Modelado de Producto y sus subtipos (Experiencia / Alojamiento / Paquete)

**Decision**: Tabla base `products` con columna `type` (enum `product_type`) + tablas de subtipo 1:1 (`experiences`, `accommodations`) que comparten PK con `products`. Los Paquetes se modelan con `packages` (metadatos de itinerario) + `package_items` (componentes).

**Rationale**:
- Los tres subtipos comparten atributos comunes (organización, nombre, descripción, estado, categoría) → tabla base evita duplicación (Composition Over Duplication).
- Los atributos específicos (duración/dificultad vs. tipo de inmueble/ocupación) viven en su tabla de subtipo, manteniendo integridad sin columnas nulas dispersas.
- PK compartida (`experiences.id` = `products.id`) simplifica joins y garantiza 1:1.

**Alternatives considered**:
- Tabla única con todas las columnas nullable ("single table inheritance"): Descartado por columnas dispersas y validaciones condicionales complejas.
- Tablas totalmente independientes por tipo: Descartado por duplicar atributos comunes y romper el listado unificado del catálogo (SC-004).

---

## R-002: Mapeo de roles del negocio a los roles fijos de la feature 001

**Decision** (clarificado 2026-09-09): Reutilizar el enum `app_role` existente (`admin`, `operator`, `agent`).
- **Gestión de catálogo** (productos, add-ons, paquetes, categorías): `operator` y `admin`.
- **Definición de esquemas de precios** (base y temporada): `operator` y `admin`.
- **Sobreescritura manual de precio**: **solo `admin`** (registrada en auditoría).
- `agent`: solo lectura del catálogo.

**Rationale**:
- La Constitución fija los roles del MVP (Evolution Over Prediction); crear roles nuevos requeriría un cambio de nivel arquitectónico.
- El modelo jerárquico de 001 (admin hereda operator/agent) permite que `admin` también gestione catálogo y precios.
- Los operadores gestionan la oferta comercial (incluida la definición de tarifas), pero la sobreescritura manual —que altera el margen sobre una tarifa ya definida— queda reservada al `admin` y auditada (FR-009).

**Alternatives considered**:
- Introducir roles `product_manager` y `commercial_admin`: Descartado por violar el modelo de roles fijos del MVP; se difiere a fases SaaS avanzadas (PBAC).
- Restringir toda la definición de precios a `admin`: Descartado en la clarificación — el negocio requiere que el Operador también configure tarifas; solo la sobreescritura manual permanece exclusiva de `admin`.

---

## R-003: Estrategia de precios y versionado / congelamiento (FR-007, SC-002)

**Decision**: `pricing_schemes` versionados por `valid_from`/`valid_to` (append-only para cambios de tarifa base) + captura de precio congelado aguas abajo. El catálogo expone el esquema vigente; el congelamiento efectivo (snapshot) lo realiza el módulo de cotizaciones (feature 005) copiando el precio calculado al emitir. En 002 se garantiza que **actualizar un precio nunca muta registros históricos**: un cambio de tarifa crea una nueva versión y cierra la anterior con `valid_to`.

**Rationale**:
- SC-002 exige 100% de inmutabilidad de cotizaciones/reservas previas → los esquemas no se sobreescriben in-place.
- Separar "definición de precio" (002) de "congelamiento en cotización" (005) respeta las fronteras de capacidad de negocio (Bounded Contexts).
- El versionado por fechas permite reconstruir qué tarifa estaba vigente en cualquier momento (auditabilidad).

**Alternatives considered**:
- UPDATE in-place del monto: Descartado por romper la no-retroactividad.
- Snapshot inmediato en 002: Descartado porque el objeto que se congela es la cotización, que pertenece a la feature 005.

---

## R-004: Precios por temporada y validación anti-solapamiento (FR-006, Edge Case)

**Decision**: Cada `pricing_scheme` de tipo estacional define `season_start`/`season_end` (rango de fechas). Se usa una `EXCLUDE` constraint de PostgreSQL con `daterange` + `gist` para impedir solapamientos de temporada para el mismo producto y tipo de cobro. La selección de tarifa por fecha se resuelve con una función SQL determinista.

**Rationale**:
- Una `EXCLUDE USING gist (product_id WITH =, charge_type WITH =, daterange(season_start, season_end) WITH &&)` garantiza a nivel de BD que no existan rangos contradictorios (Explicitness, Correctness).
- Resolver la tarifa en SQL (no en el cliente) asegura cálculo consistente y testeable (SC-003).

**Alternatives considered**:
- Validación solo en la capa de aplicación: Descartado por riesgo de bypass e inconsistencia (Default Deny / Business Rules en el dominio).
- Precios estacionales como filas sin constraint: Descartado por permitir estados inválidos.

---

## R-005: Categorización / Taxonomías (FR-005)

**Decision**: Tabla `categories` (organization-scoped, jerárquica opcional vía `parent_id` nullable) + tabla de unión `product_categories` (N:M). Categorías semilla sugeridas (aventura, ecológico, cultural, lujo) creadas por organización.

**Rationale**:
- N:M permite que un producto pertenezca a varias taxonomías (ej. "aventura" + "ecológico").
- `parent_id` opcional habilita jerarquía futura sin forzarla en el MVP (Evolution Over Prediction).

**Alternatives considered**:
- Enum fijo de categorías: Descartado porque las taxonomías son organizacionales/configurables.
- Campo de texto libre: Descartado por inconsistencia y dificultad de filtrado.

---

## R-006: Add-ons / Complementos y reglas de aplicabilidad (FR-004)

**Decision**: Tabla `add_ons` independiente (organization-scoped) + tabla de unión `product_addons` que define elegibilidad por producto y reglas (`is_mandatory`, `max_quantity`). Add-ons con su propio `pricing_scheme`.

**Rationale**:
- Un add-on ("Transporte privado") puede aplicar a varios productos → entidad independiente reutilizable.
- Las reglas de compatibilidad (obligatorio, capacidad) se validan al presupuestar (frontera con feature 005), pero se definen aquí.

**Alternatives considered**:
- Add-ons embebidos por producto: Descartado por duplicación y falta de reutilización.

---

## R-007: Desactivación lógica y consistencia de paquetes (FR-001, US1/US3 edge cases)

**Decision**: Estado `product_status` (`draft`, `active`, `inactive`); nunca se borra físicamente. Desactivar un producto no altera cotizaciones/reservas pasadas (RESTRICT en el catálogo, no cascada). Si un componente de un paquete se desactiva, un trigger/consulta marca el paquete como inconsistente y se advierte al gestor (no se auto-desactiva).

**Rationale**:
- Preserva integridad histórica (SC-002) y trazabilidad.
- La advertencia (no bloqueo) respeta la decisión de negocio del spec (US3 escenario 2).

**Alternatives considered**:
- Borrado físico: Descartado por pérdida de historia y ruptura de FKs.
- Auto-desactivar el paquete: Descartado; el spec pide advertir, no desactivar automáticamente.

---

## R-008: Producto sin precio no comercializable (Edge Case)

**Decision**: Un producto solo puede transicionar a `active` si tiene al menos un `pricing_scheme` válido. Se valida con un trigger `BEFORE UPDATE`/`BEFORE INSERT` sobre `products` (o función de activación dedicada).

**Rationale**:
- El Edge Case exige que sin esquema de precio válido el producto no se active ni entre en cotizaciones.
- Enforcement a nivel de BD evita estados inválidos (Correctness, Default Deny).

**Alternatives considered**:
- Validar solo en UI: Descartado por bypass vía API/PostgREST.

---

## R-009: Moneda configurable por organización (Assumption)

**Decision**: Moneda por defecto en `organizations.settings` (jsonb, ej. `{"default_currency": "COP"}`); cada `pricing_scheme` almacena su `currency` (hereda el default de la organización si no se especifica). Sin conversión de divisas en el MVP.

**Rationale**:
- El spec asume moneda principal configurable por organización (COP, USD).
- Guardar la moneda en cada esquema permite futuros productos multi-moneda sin rediseño.

**Alternatives considered**:
- Moneda global del sistema: Descartado por ser multi-tenant.
- Motor de conversión de divisas: Fuera de alcance (diferido).

---

## R-010: Metadatos de proveedor (Assumption)

**Decision**: Tabla `providers` (organization-scoped) con datos de contacto/operación; `products.provider_id` como FK nullable. Sin lógica de disponibilidad en 002 (pertenece a la feature 004).

**Rationale**:
- El spec asume que los proveedores se registran como metadatos para facilitar la posterior verificación de disponibilidad (feature 004 pre-reserva).
- Una tabla ligera evita jsonb disperso y prepara la integración con 004 sin sobre-ingeniería.

**Alternatives considered**:
- `provider` como jsonb en `products`: Descartado por dificultar el join con disponibilidad futura.
- Modelar disponibilidad ahora: Descartado; fuera de alcance de esta capacidad.

---

## R-011: Frontend — reutilización de patrones de la feature 001

**Decision**: Standalone Components + Signals + Signal Forms; servicios `core/catalog/*` inyectan el `SupabaseService` y `AuthService` existentes; guards `authGuard`/`roleGuard` reutilizados para proteger rutas de gestión (operator/admin). Componentes compartidos `alert`/`spinner` reutilizados.

**Rationale**:
- Consistencia (Convention Over Configuration) y no duplicación (Composition Over Duplication).
- El `roleGuard('operator')` protege el catálogo y la definición de precios; la sobreescritura manual de precio se restringe con `roleGuard('admin')`.

**Alternatives considered**:
- Nueva capa de estado (NgRx): Descartado por simplicidad; Signals bastan.
