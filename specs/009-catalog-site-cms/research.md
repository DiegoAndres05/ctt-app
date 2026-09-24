# Research: 009-catalog-site-cms

**Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

---

## R-001: La ficha pública no se mezcla con el producto operativo

**Decision**: Nueva entidad `public_listings`, 1:1 con `products`. El producto de 002 conserva nombre operativo, estado y tarifas. La ficha guarda el contenido bilingüe, la ubicación pública (`catalog`, `lodging`, `yacht`), el precio de vitrina y la marca de agotado.

**Rationale**: El spec separa precio de vitrina y tarifa, y una experiencia puede publicarse como oferta o como yate. Meter esos campos en `products` acoplaría el catálogo interno a la página y obligaría a columnas nulas distintas por tipo.

**Alternatives considered**:
- Ampliar `products`, `experiences` y `accommodations`: Descartado. Mezcla idioma, galería y agotado con reglas operativas que ya están cerradas en 002.
- WordPress como CMS de estas fichas: Descartado. La Constitución reserva WordPress al contenido editorial. Precios, productos y publicación comercial siguen en PostgreSQL.

---

## R-002: Dónde aparece cada producto

**Decision**: Columna `placement` con valores `catalog`, `lodging` y `yacht`.
- `catalog` solo en experiencias y paquetes predefinidos.
- `lodging` solo en alojamientos.
- `yacht` solo en experiencias.
Un producto tiene como máximo una ficha.

**Rationale**: La página ya separa catálogo, hospedaje y yates. El tipo interno no alcanza: la copia declaró que los yates también son experiencias, pero no deben salir en el listado de ofertas.

**Alternatives considered**:
- Nuevo `product_type = yacht`: Descartado. Duplicaría experiencias y abriría un subtipo que el spec no pidió.
- Usar la categoría pública `premium` para los yates: Descartado. La categoría filtra el catálogo; no decide la sección.

---

## R-003: Categorías públicas distintas de las categorías operativas

**Decision**: Tabla `public_categories` con identificador estable (`islas`, `baru`, `tierra_bomba`, `compartidos`, `cultural`, `aventura`, `baile`, `premium`), nombre en español e inglés, y estado. La ficha de oferta apunta a una categoría pública. Las categorías de 002 no se reutilizan como filtro de la página.

**Rationale**: La página filtra por esos identificadores. Las categorías de 002 son una taxonomía interna con UUID y pueden no coincidir.

**Alternatives considered**:
- Forzar los slugs dentro de `categories`: Descartado. Cambiaría el significado de una taxonomía ya usada por el catálogo operativo.

---

## R-004: Lectura pública sin abrir el catálogo operativo

**Decision**: El rol `anon` no recibe acceso a `products` ni a `pricing_schemes`. Una función `get_public_site` (`SECURITY DEFINER`) devuelve solo fichas `published` cuyo producto está `active`, más la bandera de fuente `legacy` o `panel`. Las imágenes de una ficha publicada se leen por su URL pública.

**Rationale**: Hoy `anon` está revocado en el catálogo. La página necesita leer sin login, pero no debe ver borradores, tarifas históricas ni productos de trabajo interno.

**Alternatives considered**:
- Política `SELECT` de `anon` sobre `products`: Descartado. Filtrar solo en el cliente no cumple el aislamiento ni oculta borradores.
- Embeber otra vez el JSON en el admin: Descartado. No cumple el cambio de fuente.

---

## R-005: La página pública sigue siendo la aplicación que ya existe

**Decision**: Este repositorio entrega el panel, el almacenamiento y el contrato de lectura. La aplicación de `https://www.cartagenatailoredtravel.com/` es el consumidor: mientras `source = legacy` conserva su contenido actual; cuando `source = panel` renderiza solo la respuesta de `get_public_site`. No se reescribe esa página dentro de Angular.

**Rationale**: El spec exige que el visitante vea el panel después del cambio, y la Constitución mantiene un modular monolith para el panel. La página ya existe aparte y hoy trae las fichas en su propio paquete.

**Alternatives considered**:
- Reconstruir la página pública en Angular: Descartado. Duplicaría el sitio y contradice el alcance, que es administrar el contenido que esa página ya muestra.
- Copiar el JSON a mano en cada deploy: Descartado. Es el proceso que esta mejora reemplaza.

---

## R-006: Copia inicial y compuerta de cambio

**Decision**: Un manifiesto `public_cutover_items` lista las ofertas, alojamientos y yates vigentes de Cartagena Tailored Travel. Una semilla crea el producto, la ficha publicada y, en ofertas y alojamientos, la tarifa inicial. `complete_public_cutover` solo pasa `source` a `panel` si cada ítem del manifiesto tiene ficha `published` y producto `active`. Hasta entonces `source` permanece `legacy`.

Los identificadores públicos de ofertas y alojamientos son los que la página ya usa. Los yates no tienen dirección propia hoy; su identificador estable queda `azimut-70`, `leopard-51`, `firpol-42` y `bravo-380`.

**Rationale**: El spec bloquea el cambio si falta una ficha. El manifiesto hace esa condición comprobable. Inventar el precio de un yate queda prohibido; el yate se publica solo cuando ya tiene tarifa, como cualquier producto de 002.

**Alternatives considered**:
- Scraping de la página en cada arranque: Descartado. La copia es un hecho de negocio de una fecha, no una dependencia de disponibilidad del sitio.
- Cambio automático al publicar la primera ficha: Descartado. Viola la compuerta de FR-024.

---

## R-007: La tarifa inicial se crea una vez, con el precio actual

**Decision**: La semilla de una oferta llama a `upsert_pricing_scheme` con el precio actual, su moneda y `charge_type = per_person`. La de un alojamiento usa el precio por noche, su moneda y `charge_type = per_night`. El precio anterior tachado no entra en la tarifa. Queda copiado en `original_price`. Después, editar el precio de vitrina solo actualiza la ficha.

**Rationale**: 002 ya exige una tarifa vigente para activar, y la activación es condición para publicar. Reutilizar `upsert_pricing_scheme` conserva el versionado y el congelamiento. El spec dice que un cambio posterior de vitrina no reescribe la tarifa.

**Alternatives considered**:
- Publicar sin tarifa: Descartado. Rompe la regla de activación de 002.
- Usar el precio tachado como tarifa: Descartado. El visitante ve el precio actual como precio a pagar.

---

## R-008: Imágenes en Storage, con la referencia que la página ya entiende

**Decision**: Bucket público `catalog-media`, límite 10 MB, MIME `image/jpeg`, `image/png` y `image/webp`. La ruta es `{organization_id}/{listing_id}/{image_id}`. Escritura solo para `operator` y `admin` de esa organización. La ficha guarda la referencia en `image`. Una copia puede conservar una ruta ya publicada (`/images/...`) hasta que el gestor la reemplace. La página recibe esa referencia tal cual.

**Rationale**: La página ya muestra imágenes por URL o ruta, sin sesión. El spec pide carga, reemplazo y rechazo de archivos inválidos, y permite no volver a subir la imagen copiada.

**Alternatives considered**:
- URLs firmadas: Descartado. La página pública no puede renovar firmas en cada visita.
- Guardar el binario en PostgreSQL: Descartado. El proyecto ya usa Storage para imágenes públicas.

---

## R-009: Textos bilingües en pares, no en dos listas sueltas

**Decision**: Inclusiones, advertencias, capacidades y características se guardan como listas de pares `{es, en}` más el símbolo opcional en yates. Al entregar el contrato se proyectan a `includes` / `includesEn` (y equivalentes). Publicar exige la misma cantidad y el mismo orden porque cada par viaja junto.

**Rationale**: Dos arreglos independientes pueden desalinearse. El par hace imposible publicar una inclusión en español sin su inglés.

**Alternatives considered**:
- Dos columnas `text[]`: Descartado. La igualdad de longitud quedaría solo en la aplicación.

---

## R-010: Agotado no es un estado del producto

**Decision**: Booleano `sold_out` en la ficha publicada. El producto sigue `active` y la ficha sigue `published`. El contrato público incluye `soldOut: true` y `acceptsRequests: false`. Despublicar o desactivar sigue ocultando la ficha, como en 002 y en FR-019.

**Rationale**: El spec pide que la ficha agotada siga visible y no acepte solicitudes nuevas, sin confundirla con inactiva o despublicada.

**Alternatives considered**:
- Nuevo `product_status = sold_out`: Descartado. Desactivar ya oculta la ficha y bloquearía cotizaciones internas que el spec no pidió cerrar.

---

## R-011: Auditoría de publicación e imagen

**Decision**: Nuevos valores de `audit.audit_event_type`: `public_listing_published`, `public_listing_unpublished`, `public_image_replaced`, `public_listing_sold_out_changed`, `public_cutover_completed`. Cada uno registra actor y momento. El reemplazo de imagen guarda la referencia anterior y la nueva.

**Rationale**: FR-021 pide saber quién publicó, despublicó o reemplazó la imagen. Se reutiliza `audit.audit_events` en lugar de un log paralelo.

**Alternatives considered**:
- Tabla de historial propia: Descartado. Duplicaría la auditoría que 001 y 002 ya usan.
