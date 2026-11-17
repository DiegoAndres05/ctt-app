# Contract: Edge Function `translate-blog`

`POST /functions/v1/translate-blog` · `verify_jwt = true` · invocada con `supabase.functions.invoke`.

## Request

```json
{ "source": "es", "target": "en", "segments": ["Qué ver en <b>Cartagena</b>", "…"] }
```

- `source`, `target`: `"es"` o `"en"`, distintos.
- `segments`: una **parte** de 1–40 textos no vacíos y 5.000 caracteres en total como máximo. HTML mínimo (`<b>`, `<i>`, `<a id="N">`) o texto plano escapado. El panel envía un artículo largo como varias partes seguidas.

## Flujo

1. Valida el cuerpo → `400 VALIDATION_ERROR` o `413 TRANSLATION_TOO_LARGE`.
2. `rpc('consume_blog_translation_quota', { p_characters })` con la sesión del usuario (caracteres de la parte) → `403 FORBIDDEN`, `429 TRANSLATION_RATE_LIMITED` (`retryAt`), `401 SESSION_EXPIRED`.
3. Sin `LIBRETRANSLATE_URL` → `503 TRANSLATION_UNAVAILABLE`.
4. `POST {LIBRETRANSLATE_URL}/translate` con `{ q: segments, source, target, format: "html", api_key? }`, tiempo máximo 55 s.
5. Respuesta distinta de 200, JSON inválido, o `translatedText` que no es un arreglo de la misma longitud → `503 TRANSLATION_UNAVAILABLE`.

No registra el texto en logs (FR-014): solo código, número de segmentos y duración.

## Response 200

```json
{ "segments": ["What to see in <b>Cartagena</b>", "…"] }
```

## Errores

```json
{ "code": "TRANSLATION_RATE_LIMITED", "retryAt": "2026-11-17T15:00:00Z" }
```

| HTTP | `code` | Mensaje en el panel |
| --- | --- | --- |
| 400 | `VALIDATION_ERROR` | Datos inválidos |
| 401 | `SESSION_EXPIRED` | Sesión expirada |
| 403 | `FORBIDDEN` | Sin permiso |
| 413 | `TRANSLATION_TOO_LARGE` | Un bloque es demasiado largo para traducirlo (más de 5.000 caracteres) |
| 429 | `TRANSLATION_RATE_LIMITED` | Límite de 150.000 caracteres de la hora; reintentar a las HH:MM |
| 503 | `TRANSLATION_UNAVAILABLE` | La traducción automática no está disponible; puedes seguir escribiendo a mano |
