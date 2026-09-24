# Quickstart: Contenido público del catálogo

**Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

Guía de validación. Los contratos están en [contracts/api-contracts.md](./contracts/api-contracts.md) y las reglas de datos en [data-model.md](./data-model.md).

## Prerequisites

- Panel local de 001 y 002 en marcha (`npm start`, Supabase local).
- Una organización con un usuario `operator` y otro `agent`.
- Migraciones de esta feature aplicadas, incluida la semilla del manifiesto y de las ocho categorías públicas.
- Bucket `catalog-media` creado con el límite de 10 MB.

```bash
npm install
npm start
./supabase/tests/run-sql-tests.sh
```

## 1. Publicar una oferta

1. Como operador, abre una experiencia `active` que ya tenga tarifa.
2. Completa la ficha de catálogo en español e inglés, con imagen, inclusiones y precio de vitrina.
3. Publica.

**Esperado**: `publish_public_listing` responde `published`. `get_public_site` no incluye la oferta mientras `source` sea `legacy`.

## 2. Rechazos de publicación

Intenta publicar sin portada, sin inglés, con inclusiones de distinta cantidad por idioma, o con precio anterior menor o igual al actual.

**Esperado**: la ficha sigue en borrador y el error indica el campo (`PUBLIC_LISTING_INCOMPLETE`, `BILINGUAL_PAIR_INCOMPLETE` o `ORIGINAL_PRICE_NOT_HIGHER`).

## 3. Imagen

Sube un JPEG menor de 10 MB y márcalo como portada. Reemplázalo. Intenta un PDF y un archivo de más de 10 MB.

**Esperado**: la portada vigente cambia y queda `public_image_replaced`. Los archivos inválidos responden `IMAGE_TYPE_NOT_ALLOWED` o `IMAGE_TOO_LARGE` y la portada anterior sigue igual.

## 4. Precio de vitrina y tarifa

En una oferta copiada, compara la tarifa vigente con el precio actual de la página, no con el tachado. Edita solo el precio de vitrina y vuelve a leer la tarifa.

**Esperado**: la tarifa inicial coincide con el precio actual (`per_person` en ofertas, `per_night` en alojamientos). Después de editar la vitrina, `pricing_schemes` no gana una versión nueva.

## 5. Agotado

Marca la ficha publicada como agotada.

**Esperado**: sigue en la proyección cuando `source = panel`, con `soldOut: true` y `acceptsRequests: false`. El producto sigue `active`. Quitar la marca devuelve `acceptsRequests: true`.

## 6. Roles y agencias

Como agente, intenta publicar o subir una imagen. Con el JWT de otra organización, lee la ficha.

**Esperado**: `FORBIDDEN` para el agente. La otra organización no ve la ficha.

## 7. Alojamiento y yate

Publica un alojamiento `active` con galería, amenidades y dos opiniones. Publica una experiencia como yate, con capacidad, característica e imagen, sin precio de vitrina, después de cargarle una tarifa por el flujo de 002.

**Esperado**: el alojamiento sale en `lodgings` y no en `offers`. `reviewCount` es 2. El yate sale solo en `yachts`. Intentar publicar el yate sin tarifa responde `PRODUCT_HAS_NO_VALID_PRICE`.

## 8. Desactivar el producto

Desactiva el producto de una ficha publicada y reactívalo sin volver a publicar.

**Esperado**: la ficha pasa a `unpublished` y desaparece de la proyección. Al reactivar no vuelve a la proyección hasta un `publish_public_listing` nuevo.

## 9. Compuerta de cambio

Llama `complete_public_cutover` antes de que todo el manifiesto esté publicado.

**Esperado**: `CUTOVER_INCOMPLETE` lista los slugs faltantes y `source` sigue `legacy`. Los arreglos de `get_public_site` van vacíos.

Cuando cada ítem del manifiesto esté publicado, un admin completa el cambio.

**Esperado**: `source = panel`. Una segunda llamada responde `CUTOVER_ALREADY_COMPLETED`. La proyección trae solo fichas publicadas de productos activos, con los slugs de ofertas y alojamientos que la página ya usaba.

## 10. Consumidor de la página

Esta comprobación ocurre en la aplicación de `https://www.cartagenatailoredtravel.com/`, fuera de este repositorio.

**Contrato de lectura** (PostgREST):

```http
POST {SUPABASE_URL}/rest/v1/rpc/get_public_site
Content-Type: application/json
apikey: {ANON_KEY}
Authorization: Bearer {ANON_KEY}

{ "p_organization_id": "<uuid de la organización CTT>" }
```

El `organization_id` de Cartagena Tailored Travel es el de la fila sembrada en `public_sites` / manifiesto (`027_public_catalog_seed.sql`). Con sesión autenticada, la RPC ignora un `p_organization_id` ajeno y usa el JWT.

- Con `source = legacy`, el visitante sigue viendo el contenido actual de la página; la RPC responde arreglos vacíos.
- Con `source = panel`, catálogo, hospedaje y yates muestran solo `get_public_site`. Una dirección ya publicada (`/catalogo/{slug}`) abre la misma oferta.
- Un yate no aparece en el catálogo de ofertas. El texto de presentación y los destinos isleños de esa página no dependen de esta ficha.

## SQL

Agregar a `supabase/tests/` y ejecutarlos con `./supabase/tests/run-sql-tests.sh`:

| Archivo | Cubre |
|---------|--------|
| `public_listing_rules_test.sql` | Pares bilingües, precio anterior, slug inmutable, placement contra tipo de producto. |
| `public_listing_rls_test.sql` | `anon` no lee borradores ni tarifas. Otra organización no lee la ficha. `agent` no publica. |
| `public_cutover_test.sql` | Compuerta incompleta, cambio exitoso, tarifa inicial distinta del precio de vitrina posterior. |
| `public_sold_out_test.sql` | Agotado visible, sin solicitudes, sin cambio de tarifa ni de estado del producto. |
