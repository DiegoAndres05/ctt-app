# Implementation Plan: Traducción automática de artículos del blog

**Branch**: `017-blog-translation` | **Date**: 2026-11-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/017-blog-translation/spec.md`

## Summary

Botón «Traducir desde Español/Inglés» en cada pestaña de idioma del editor del blog (013). El panel convierte los campos y bloques del idioma de origen en segmentos HTML mínimos, los envía a una Edge Function autenticada (`translate-blog`) que aplica el rol y el límite por agencia con una RPC y reenvía a un LibreTranslate alojado por el proyecto. El panel reconstruye los bloques con la misma estructura, los aplica como edición sin guardar (con diálogo de sobrescritura y «Deshacer») y la persona revisa, guarda y publica con el flujo de 013.

## Technical Context

**Language/Version**: TypeScript 5.x (Angular 22), Deno (Supabase Edge Runtime), SQL (PostgreSQL 17)

**Primary Dependencies**: `@supabase/supabase-js@2`, LibreTranslate `v1.6.4` (Docker, modelos es↔en)

**Storage**: tabla `blog_translation_usage` (contador por agencia y hora); sin cambios en artículos

**Testing**: Vitest (modelo de segmentos, servicio, editor), arnés SQL (`run-sql-tests.sh`), comprobación manual con LibreTranslate local

**Target Platform**: panel web; servicio de traducción en un contenedor Docker

**Project Type**: web application (Angular + Supabase)

**Performance Goals**: artículo corto en < 30 s; progreso visible por partes en artículos largos (SC-001, research R9)

**Constraints**: gratis por uso, sin IA generativa, sin terceros (FR-010); 150.000 caracteres/agencia/hora; partes de ≤ 40 textos y 5.000 caracteres, enviadas en serie; tiempo máximo 60 s por parte

**Scale/Scope**: 1 migración, 1 Edge Function, 1 módulo de modelo, cambios en el editor y en el servicio del blog

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principio | Estado | Nota |
| --- | --- | --- |
| Business Value First | PASS | Evita escribir cada artículo dos veces en agencias bilingües. |
| Simplicity Over Complexity | PASS | Una función proxy, una tabla de contador y un módulo puro. Sin cola, caché ni glosario. |
| Consistency Over Innovation | PASS | Mismo patrón de RPC (`SECURITY DEFINER`, `search_path = ''`, códigos de error), límites como 015 y Edge Function como `register-agency`. |
| Security By Design | PASS | JWT verificado, rol en la RPC, límite por agencia, servidor de traducción no expuesto al navegador, direcciones de enlace nunca enviadas, nada se guarda ni se registra (FR-014). El resultado pasa por la normalización de 013 al guardar. |
| Multi-Tenant Readiness | PASS | El contador tiene `organization_id` del JWT; ningún dato cruza agencias. |
| Documentation Before Implementation | PASS | spec, research, data-model, contrato y quickstart antes de las tareas. |
| **Technology Direction → Infrastructure** (servicio nuevo) | **PASS (tras enmienda)** | Añadir LibreTranslate es nivel 3. Se resolvió con [ADR-0005](../../docs/adr/0005-self-hosted-machine-translation.md) (*Accepted*, 2026-11-17) y su enmienda a *Infrastructure*. |

**Resultado de la puerta**: PASS. La incorporación del servicio quedó aprobada con ADR-0005 y la enmienda constitucional.

**Re-check post-diseño**: igual. Data-model y contrato no introducen violaciones adicionales.

## Project Structure

### Documentation (this feature)

```text
specs/017-blog-translation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/translate-blog.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
docker/libretranslate/compose.yml                     # servicio local (puerto 5050)
supabase/
├── migrations/072_blog_translation_quota.sql         # tabla + consume_blog_translation_quota()
├── functions/translate-blog/index.ts                 # proxy autenticado
├── functions/.env.example                            # LIBRETRANSLATE_URL
└── tests/blog_translation_quota_test.sql
src/app/
├── features/blog/blog-editor/blog-translation.ts (+ .spec.ts) # segmentos, HTML mínimo, reconstrucción, aplicar
├── core/blog/services/blog.service.ts (+ spec)       # translate()
├── core/auth/models/auth.model.ts                    # códigos TRANSLATION_*
├── core/error/error-handler.ts                       # mensajes en español
└── features/blog/blog-editor/                        # botón, diálogo, aviso, deshacer
docs/modules/catalog-pricing.md                       # sección «Traducción del blog (017)»
docs/adr/0005-self-hosted-machine-translation.md
```

**Structure Decision**: misma estructura web que 013. La lógica de segmentos vive en el cliente como módulo puro (probado con Vitest), porque el repositorio no tiene Deno para probar código de Edge Functions; la función se mantiene mínima.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| Servicio de infraestructura nuevo (LibreTranslate) | Traducción gratuita, sin IA generativa y sin terceros (FR-010) | Servicios externos gratuitos (DeepL Free, MyMemory) envían el texto a terceros y tienen límites; traducir en el navegador exige descargar modelos en cada equipo. Detalle en ADR-0005. |
