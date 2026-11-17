# Quickstart: Traducción automática de artículos del blog (017)

## Preparación local

```bash
docker compose -f docker/libretranslate/compose.yml up -d
```

La primera vez descarga los modelos es↔en (~1 GB). Listo cuando `curl -s localhost:5050/languages` devuelve `es` y `en`.

`supabase/functions/.env` (no versionado):

```
LIBRETRANSLATE_URL=http://host.docker.internal:5050
```

```bash
npx supabase db reset            # aplica 072
npx supabase functions serve translate-blog --env-file supabase/functions/.env
npm start
```

## Escenarios

1. **Traducción ES→EN (US1)**: artículo con título, resumen, título 2, lista, `**negrita**`, `[enlace](https://example.com)` e imagen con alt, solo en español. Pestaña Inglés → «Traducir desde Español». Todos los campos en inglés se rellenan, mismos bloques, el enlace apunta a `https://example.com`, la imagen es la misma, aparece el aviso de traducción automática.
2. **EN→ES (US1)**: lo mismo en la dirección contraria.
3. **Cambios sin guardar (US1)**: tras traducir, salir del editor pide confirmación.
4. **Versión publicada intacta (US1)**: en un artículo publicado, traducir y guardar no cambia la lectura pública hasta «Publicar cambios».
5. **Destino con texto (US2)**: aparece el diálogo con tres opciones. «Cancelar» no cambia nada; «Rellenar solo campos vacíos» respeta lo escrito; «Reemplazar todo» lo sustituye.
6. **Deshacer (US2)**: «Deshacer traducción» devuelve el destino a su estado previo.
7. **Traductor apagado (US3)**: `docker compose -f docker/libretranslate/compose.yml stop`; traducir muestra «no disponible», nada cambia y se puede guardar y publicar a mano.
8. **Límite (US3)**: `supabase/tests/blog_translation_quota_test.sql` cubre la solicitud 31 → `TRANSLATION_RATE_LIMITED` con `retry_at`.
9. **Agente**: no ve el Blog; la RPC responde `FORBIDDEN` (test SQL).
10. **Formato (SC-002)**: `blog-translation.spec.ts` cubre reconstrucción, enlaces y fallback por fragmentos.

## Pruebas automáticas

```bash
./supabase/tests/run-sql-tests.sh supabase/tests/blog_translation_quota_test.sql
npx ng test --watch=false
npm run lint
```
