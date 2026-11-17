# Research: Traducción automática de artículos del blog (017)

## R1. Motor de traducción

- **Decision**: LibreTranslate (AGPL-3.0, motor Argos Translate / OpenNMT), imagen oficial `libretranslate/libretranslate:v1.6.4`, cargando solo los modelos `es` y `en` (`LT_LOAD_ONLY=es,en`).
- **Rationale**: es gratuito por uso, de código abierto y se aloja en la infraestructura propia, así que el texto no sale a terceros (FR-010). No es IA generativa: es traducción automática neuronal clásica, sin instrucciones ni generación libre. Expone una API HTTP simple (`POST /translate`) que acepta varios textos por petición y un modo `html` que conserva etiquetas.
- **Alternatives considered**:
  - DeepL API Free: mejor calidad, pero límite mensual de 500.000 caracteres, cuenta con clave y el texto sale a un tercero. Descartado por la decisión del usuario.
  - Google Translate / Azure: de pago a partir de cierto volumen y externos.
  - MyMemory: gratuito pero con límites diarios bajos y externo.
  - Modelos de IA generativa (Claude, GPT): excluidos expresamente por el usuario.
  - Bergamot / Firefox Translations en el navegador: sin servidor, pero exige descargar ~30 MB de modelos en cada navegador y no hay paquete mantenido para Angular. Queda como alternativa futura si alojar un servidor resulta un problema.

## R2. Dónde se llama al traductor

- **Decision**: una Edge Function de Supabase, `translate-blog`, hace de proxy autenticado. El navegador nunca llama a LibreTranslate.
- **Rationale**: el servidor de LibreTranslate no tiene autenticación por usuario. Exponerlo al navegador permitiría que cualquiera lo use sin límite. La función verifica el JWT (`verify_jwt = true`), comprueba el rol y el límite con una RPC usando la sesión del usuario, limita el tamaño y aplica el tiempo máximo. La URL y la clave opcional del traductor quedan como secretos (`LIBRETRANSLATE_URL`, `LIBRETRANSLATE_API_KEY`).
- **Alternatives considered**: llamar desde PostgreSQL con `pg_net` (asíncrono, no devuelve el resultado en la misma petición); llamar directamente desde el navegador (sin control de acceso ni límite).

## R3. Conservar el formato (FR-003)

- **Decision**: el cliente convierte cada texto en un segmento HTML mínimo con solo `<b>`, `<i>` y `<a id="N">`. La dirección real del enlace nunca se envía: se sustituye por un índice y se restaura al volver. Se traduce con `format: "html"`. Al volver, un analizador estricto que solo reconoce esas tres etiquetas reconstruye los fragmentos (`InlineRun[]`) y comprueba que la secuencia de marcas sea la misma que la original.
- **Fallback**: si un segmento vuelve con otra secuencia de marcas (el motor perdió o duplicó una etiqueta), se repite la traducción de ese segmento fragmento por fragmento como texto plano en una segunda petición. Así la estructura siempre se conserva, con algo menos de calidad en esos segmentos. Esa segunda petición también cuenta para el límite (FR-012).
- **Rationale**: traducir fragmento por fragmento desde el principio rompe el contexto de frases con negritas o enlaces («Visita **Cartagena** hoy»). El modo HTML conserva el contexto en la mayoría de los casos y el fallback garantiza SC-002.
- **Estructura**: los bloques, su tipo y nivel, el orden, las listas y las imágenes se copian del origen; solo se reemplaza el texto. Una lista se traduce ítem por ítem (un segmento por ítem). El slug no se envía (FR-007).

## R4. Límite de uso (FR-012)

- **Decision**: tabla `blog_translation_usage (organization_id, window_start, characters)` con ventanas de una hora, y RPC `consume_blog_translation_quota(p_characters)` (150.000 caracteres por hora; cada parte entre 1 y 5.000) (`SECURITY DEFINER`, `search_path = ''`, `require_catalog_manager_or_forbidden`). Si se supera el límite lanza `TRANSLATION_RATE_LIMITED` con `DETAIL {"retry_at": …}`.
- **Rationale**: mismo patrón que los límites de 015 (contadores por organización en PostgreSQL), sin infraestructura nueva. La RPC también hace la comprobación de rol (FR-001), de modo que la Edge Function no repite la lógica.
- **Limpieza**: la RPC borra las ventanas de la agencia con más de un día de antigüedad cuando consume; no hace falta tarea programada.

## R5. Tamaño y tiempo (FR-011, FR-013)

- **Decision**: el panel divide los textos en **partes** de hasta 40 textos y 5.000 caracteres (`splitIntoParts`) y las envía en orden mostrando el avance; un texto nunca se parte. La función rechaza con `TRANSLATION_TOO_LARGE` una parte mayor. Cada parte tiene un tiempo máximo de 55 s en la función y 60 s en el cliente. Cualquier fallo, tiempo agotado, respuesta mal formada o número de textos distinto devuelve `TRANSLATION_UNAVAILABLE`.

## R6. Aplicar sin perder trabajo (FR-004, FR-006, FR-008, FR-009)

- **Decision**: la traducción se aplica sobre la señal `draft` del editor en un solo `update`, solo si todos los segmentos se reconstruyeron. Antes se guarda una copia del idioma de destino para «Deshacer traducción», que se limpia al guardar, descartar o recargar. El aviso de «traducción automática» depende de esa copia. El guardia de cambios sin guardar existente cubre FR-004.
- **Modos**: «Rellenar solo campos vacíos» rellena cada campo vacío y el contenido solo si el contenido de destino está vacío (misma regla que `isBodyEmpty`); «Reemplazar todo» reemplaza cada campo que tenga texto en el origen.
- **Diálogo**: un panel en línea con `role="alertdialog"` y tres botones, porque `window.confirm` solo tiene dos (y `<dialog>.showModal` no está en el entorno de pruebas).

## R7. Entorno local y producción

- **Decision**: `docker/libretranslate/compose.yml` con el servicio en el puerto 5050 y un volumen para los modelos. Las Edge Functions locales leen `supabase/functions/.env` (`LIBRETRANSLATE_URL=http://host.docker.internal:5050`). En producción el usuario decidirá el alojamiento; mientras `LIBRETRANSLATE_URL` no exista, la función responde `TRANSLATION_UNAVAILABLE` (FR-016).
- **Recursos**: ~2 GB de RAM y ~1 GB de disco para los dos pares de idiomas.

## R8. Gobernanza

- **Decision**: añadir un servicio de infraestructura nuevo es nivel 3 (*Change Approval Levels*). Se redacta [ADR-0005](../../docs/adr/0005-self-hosted-machine-translation.md) y una enmienda a *Technology Direction → Infrastructure* para incluir «Self-hosted open-source machine translation (LibreTranslate) for editorial drafts». Las Edge Functions ya están permitidas «when justified».

## R9. Rendimiento medido (2026-11-17, Docker local en Intel Mac, 12 CPU)

| Prueba | Tiempo |
| --- | --- |
| 1 frase corta, en caliente | ~4 s de punta a punta (≈2 s en el traductor) |
| 10 frases de ~27 palabras, una solicitud | ~22–30 s |
| 4 solicitudes de 10 frases en paralelo | ~117 s (el traductor las serializa) |
| ~1.500 palabras en una sola solicitud | > 55 s → `TRANSLATION_UNAVAILABLE` |

- La velocidad depende de la CPU (usa ~5 núcleos por traducción) y no mejora juntando textos ni en paralelo. Por eso se envían partes en serie con progreso, y el límite se mide en caracteres.
- Con este equipo, un artículo de 1.500 palabras tarda unos 2–3 minutos. En el servidor de producción habrá que medirlo de nuevo; una CPU moderna dedicada debería ser varias veces más rápida.
