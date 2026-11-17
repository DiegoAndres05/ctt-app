# Tasks: Traducción automática de artículos del blog (017)

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/translate-blog.md](contracts/translate-blog.md)

**Regla**: no commitear salvo que se pida.

## Phase 1: Setup

- [x] T001 Crear `docker/libretranslate/compose.yml` (LibreTranslate `v1.6.4`, `LT_LOAD_ONLY=es,en`, puerto 5050, volumen de modelos)
- [x] T002 [P] Crear `supabase/functions/.env.example` con `LIBRETRANSLATE_URL` y `LIBRETRANSLATE_API_KEY`; comprobar que `supabase/functions/.env` está ignorado por git

## Phase 2: Foundational

- [x] T003 Migración `supabase/migrations/072_blog_translation_quota.sql`: tabla `blog_translation_usage` con RLS sin políticas y RPC `consume_blog_translation_quota()` (rol, ventana horaria, 30 por hora, `TRANSLATION_RATE_LIMITED` con `retry_at`, limpieza > 1 día)
- [x] T004 Test `supabase/tests/blog_translation_quota_test.sql`: operador y admin consumen; agente `FORBIDDEN`; solicitud 31 rechazada con `retry_at`; contadores separados por agencia; sin acceso directo a la tabla para `authenticated`/`anon`; `search_path` fijo
- [x] T005 [P] Códigos `TRANSLATION_UNAVAILABLE`, `TRANSLATION_RATE_LIMITED`, `TRANSLATION_TOO_LARGE` en `src/app/core/auth/models/auth.model.ts` y mensajes en `src/app/core/error/error-handler.ts`

## Phase 3: User Story 1 — Traducir y corregir (P1) 🎯 MVP

- [x] T006 [US1] Edge Function `supabase/functions/translate-blog/index.ts` según el contrato (validación, RPC con la sesión del usuario, tiempo máximo 55 s, sin registrar texto) y `verify_jwt = true` en `supabase/config.toml`
- [x] T007 [US1] Módulo `src/app/features/blog/blog-editor/blog-translation.ts`: segmentos desde un `LocaleDraft`, HTML mínimo con enlaces por índice, analizador estricto, reconstrucción, fallback por fragmentos, aplicar al destino
- [x] T008 [P] [US1] `blog-translation.spec.ts`: escape, estructura conservada, enlaces restaurados, etiquetas desconocidas rechazadas, fallback, imágenes decorativas, campos vacíos
- [x] T009 [US1] `BlogService.translate()` con `functions.invoke`, tiempo máximo 60 s y decodificación de errores (`retryAt`); tests en `blog.service.spec.ts`
- [x] T010 [US1] Editor: botón «Traducir desde …» en la pestaña de destino, estado «Traduciendo…», aplicar en un solo `update`, aviso de traducción automática; oculto si la agencia ofrece un solo idioma; desactivado si el origen está vacío

## Phase 4: User Story 2 — Proteger lo escrito (P2)

- [x] T011 [US2] Diálogo nativo con «Rellenar solo campos vacíos», «Reemplazar todo» y «Cancelar» cuando el destino tiene texto
- [x] T012 [US2] «Deshacer traducción» con copia del destino; se limpia al guardar, descartar o recargar
- [x] T013 [P] [US2] Tests del editor: diálogo, modo rellenar, cancelar, deshacer

## Phase 5: User Story 3 — Fallos (P3)

- [x] T014 [US3] Mensajes de error en el editor (no disponible, límite con hora, demasiado largo); destino sin cambios; tests del editor

## Phase 6: Polish

- [x] T015 [P] Sección «Traducción del blog (017)» en `docs/modules/catalog-pricing.md` y puntero en `AGENTS.md`
- [x] T016 Verificación: suites SQL, Vitest, lint, build y escenarios del quickstart con LibreTranslate local
- [x] T017 Marcar el spec como implementado y completar el checklist de ADR-0005

## Notas de implementación

- **Partes y límite por caracteres**: el traductor local tarda ~2 s por frase, así que un artículo largo no cabe en una solicitud de 60 s. El panel envía partes de hasta 40 textos y 5.000 caracteres con progreso, y la RPC limita 150.000 caracteres por agencia y hora en lugar de 30 solicitudes. Spec, contrato, data-model y research (R9) actualizados.
- **Ubicación del módulo**: `blog-translation.ts` vive en `features/blog/blog-editor/` porque trabaja sobre el estado del editor (`LocaleDraft`).
- **Diálogo**: panel en línea con `role="alertdialog"` en vez de `<dialog>` nativo, por compatibilidad con el entorno de pruebas.
- **Calidad observada**: «Fiestas Noviembrinas» → «Festivals»; los nombres propios necesitan revisión, como prevé el spec.
- **Verificación**: 55 suites SQL, 221 pruebas Vitest, lint y build (el aviso de presupuesto del bundle inicial ya existía). En el navegador, contra Supabase y LibreTranslate locales: traducir ES→EN, diálogo con «Cancelar» y «Deshacer». Por `curl`: 200 con formato y enlaces conservados, 401 sin sesión, 400 con cuerpo inválido y 503 con el traductor apagado.

## Dependencies

T003 → T004, T006. T007 → T009 → T010 → T011–T014. T005 antes de T009.
