# Data Model: Traducción automática de artículos del blog (017)

No se añaden columnas a los artículos: la traducción solo rellena el editor y se guarda con `save_blog_article` de 013.

## Tabla `blog_translation_usage` (migración 072)

| Columna | Tipo | Regla |
| --- | --- | --- |
| `organization_id` | `uuid` | FK `organizations(id)` `ON DELETE CASCADE` |
| `window_start` | `timestamptz` | Inicio de la hora (`date_trunc('hour', now())`) |
| `characters` | `integer` | `>= 0`, caracteres enviados en la ventana |

- PK `(organization_id, window_start)`.
- RLS activada, sin políticas para `authenticated` ni `anon`; solo la RPC escribe y lee. No guarda texto de artículos (FR-014).
- Filas de más de un día se borran al consumir.

## RPC `consume_blog_translation_quota(p_characters integer) → jsonb`

- `SECURITY DEFINER`, `SET search_path = ''`, `GRANT EXECUTE` a `authenticated`.
- Exige Operador o Administrador (`require_catalog_manager_or_forbidden`); Agente → `FORBIDDEN`.
- `p_characters` entre 1 y 5.000 (una parte); fuera de rango → `VALIDATION_ERROR`.
- Suma a la ventana actual de la agencia del JWT con `INSERT … ON CONFLICT DO UPDATE` (atómico ante peticiones simultáneas).
- Si la suma pasaría de 150.000 → `RAISE 'TRANSLATION_RATE_LIMITED'` con `DETAIL {"retry_at": "<window_start + 1 h>"}` y no suma.
- Devuelve `{"remaining": n, "reset_at": "<iso>"}`.

## Segmento de traducción (efímero, cliente)

| Campo | Descripción |
| --- | --- |
| `path` | Dónde va el resultado: `title`, `summary`, `coverAlt`, `seoTitle`, `seoDescription`, `block:<i>`, `block:<i>:item:<j>`, `block:<i>:alt` |
| `runs` | `InlineRun[]` de origen (texto plano = un fragmento sin marcas) |
| `html` | Texto enviado: escapado, con `<b>`, `<i>`, `<a id="N">` |
| `hrefs` | Direcciones originales por índice `N`; nunca se envían |

Reconstrucción válida ⇔ la secuencia de marcas (`b`, `i`, `a#N`) del resultado es igual a la del origen y no hay etiquetas desconocidas.
