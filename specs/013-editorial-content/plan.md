# Implementation Plan: Blog multiagencia en el CMS

**Branch**: `013-editorial-content` | **Date**: 2026-11-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-editorial-content/spec.md`

## Summary

El panel tendrá una sección «Blog» en el CMS. Ahí Operador y Administrador redactan artículos bilingües (español e inglés, con un solo slug), los guardan incompletos, los publican, preparan cambios como una revisión en curso y los retiran. El sitio de cada agencia lee solo lo publicado mediante cuatro RPC públicas que resuelven la agencia con la clave de 016, o con el identificador de CTT durante su transición.

Las decisiones técnicas son:

- **Contenido**: se guarda como un documento de bloques validado en la base de datos, no como HTML. Así no puede llegar código ejecutable al sitio.
- **Publicado y en curso**: cada artículo tiene como máximo dos contenidos, `published` y `working`.
- **Imágenes**: van al bucket existente `catalog-media`.
- **Migración desde WordPress**: sigue el modelo `legacy` → `panel` de 009 y 016, con un manifiesto de slugs.

Detalle en [research.md](./research.md).

## Technical Context

**Language/Version**: TypeScript 6 / Angular 22; SQL PostgreSQL 17

**Primary Dependencies**: Supabase Auth, PostgreSQL RLS y RPC, Supabase Storage (bucket `catalog-media`), Angular Signals y Signal Forms. **No hay dependencias npm nuevas**: el editor por bloques es propio (research, Decisión 2).

**Storage**: PostgreSQL:
- Tablas nuevas `blog_articles`, `blog_article_contents`, `public_blog_source` y `public_blog_cutover_items`.
- Storage para las imágenes, bajo `{org}/blog/{article}/`.

**Testing**:
- Arnés SQL `./supabase/tests/run-sql-tests.sh`, con suites nuevas `blog_articles_test.sql`, `blog_isolation_test.sql`, `blog_public_read_test.sql` y `blog_cutover_test.sql`.
- Vitest (`npm test`) para el modelo de bloques, el parser de marcas en línea, el servicio y los componentes.
- `npm run lint` y `npm run build`.

**Target Platform**: Panel web Angular (`/cms/blog`, `/cms/settings/blog-migration`) y sitios externos de cada agencia, que consumen el contrato público.

**Project Type**: Aplicación web multiagencia con backend Supabase y contrato público de solo lectura.

**Performance Goals**:
- Lectura pública del listado (página de 12) y de un artículo en menos de 500 ms p95 con hasta 1.000 artículos por agencia. Es la misma meta que 016.
- Guardar o publicar en el panel en menos de 2 s p95.
- Visibilidad pública de 5 minutos o menos (FR-029), sin caché en el servidor.

**Constraints**:
- Aislamiento por `organization_id`. `anon` no tiene acceso a tablas.
- Sin service role en `src/`.
- `search_path = ''` en todas las RPC.
- El cuerpo es solo bloques permitidos, como máximo 200 KB por idioma.
- Las imágenes siguen las reglas de 026 (10 MB, JPEG, PNG o WebP).
- No se modifican las migraciones `001`–`065`. Las nuevas empiezan en `066`.
- La interfaz del panel está en español.

**Scale/Scope**:
- Decenas o cientos de artículos por agencia y, como máximo, 2.000 slugs en el manifiesto de migración.
- Tres pantallas: listado, editor y migración.
- La entrega no incluye un sitio público alojado ni una importación automática desde WordPress (queda como mejora opcional).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principio | Estado | Nota |
| --- | --- | --- |
| Business Value First | PASS | Cada agencia publica sin pedir cambios de código. |
| Simplicity Over Complexity | PASS | Sin librería de editor ni caché. Se reutilizan el bucket, la clave, la transición y la auditoría. |
| Consistency Over Innovation | PASS | Pares `*_es`/`*_en` y el flujo `legacy` → `panel` como en las fichas. RPC con los mismos códigos de error y el mismo `search_path`. |
| Security By Design | PASS | RLS más RPC. Agente sin acceso. No enumeración (`found: false` y `PUBLIC_ACCESS_UNAVAILABLE`). Bloques en lugar de HTML. La auditoría no guarda contenido. |
| Multi-Tenant Readiness / Tenant Isolation | PASS | Toda tabla nueva tiene `organization_id`. El slug es único por agencia. El acceso cruzado responde `NOT_FOUND`. |
| Documentation Before Implementation | PASS | spec, research, data-model, contratos y quickstart, antes de las tareas. |
| **Technology Direction → Content Management** («WordPress SHALL be used as a headless CMS» para «Blog articles») y mainspec 22.1 | **PASS (tras enmienda)** | Era un FAIL justificado. Se resolvió con [ADR-0004](../../docs/adr/0004-blog-authoring-in-panel.md) (*Accepted*, 2026-11-17) y su enmienda: el blog pertenece al CMS del panel por agencia y WordPress sigue para landing pages, marketing y SEO. |

**Resultado de la puerta**: PASS. La única violación (Content Management) quedó resuelta al aceptar ADR-0004 y aplicar la enmienda a la Constitución y al mainspec. La implementación puede empezar.

**Re-check post-diseño** (después de la fase 1, revisado tras la enmienda): PASS. Data-model y contratos no introducen violaciones y cumplen la sección *Content Management* enmendada: blog en el panel por agencia, migración con cambio de fuente explícito, sin datos de negocio en WordPress.

## Project Structure

### Documentation (this feature)

```text
specs/013-editorial-content/
├── spec.md
├── plan.md              # Este archivo
├── research.md          # Fase 0
├── data-model.md        # Fase 1
├── quickstart.md        # Fase 1
├── contracts/
│   ├── management.md    # RPC del panel
│   └── public-consumer.md  # Lectura pública para el sitio de la agencia
├── checklists/requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks). La versión actual está obsoleta y se regenerará.
```

### Source Code (repository root)

```text
docs/adr/
└── 0004-blog-authoring-in-panel.md        # Accepted: enmienda de Content Management

supabase/
├── migrations/
│   ├── 066_blog_enums.sql                 # blog_article_status, blog_content_kind y valores de auditoría
│   ├── 067_blog_tables.sql                # tablas, RLS, índices, triggers de inmutabilidad
│   ├── 068_blog_content_validation.sql    # normalización de bloques, blog_required_locales, blog_publish_errors
│   ├── 069_blog_management_rpcs.sql       # list/get/save/publish/changes/retire/republish/delete
│   ├── 070_blog_public_read.sql           # get_public_blog[_by_key], get_public_blog_article[_by_key]
│   └── 071_blog_source_cutover.sql        # fuente, manifiesto, complete_blog_cutover
└── tests/
    ├── blog_articles_test.sql
    ├── blog_isolation_test.sql
    ├── blog_public_read_test.sql
    └── blog_cutover_test.sql

src/app/
├── core/blog/
│   ├── models/blog-article.model.ts       # tipos y parse de las respuestas
│   ├── models/blog-blocks.ts              # tipos de bloque y parse/serialize de marcas en línea
│   └── services/blog.service.ts           # RPC del panel y subida de imágenes
├── features/blog/
│   ├── blog-list/                         # /cms/blog
│   ├── blog-editor/                       # /cms/blog/new y /cms/blog/:id (bloques, idiomas, vista previa)
│   └── blog-migration/                    # /cms/settings/blog-migration (Administrador)
├── core/audit/models/audit-event.model.ts # nuevos tipos de evento
├── features/audit/audit-log/              # etiquetas de los nuevos eventos
├── shared/layout/nav-items.ts             # entrada «Blog» bajo CMS
└── app.routes.ts                          # rutas con roleGuard('operator') y roleGuard('admin')

docs/modules/catalog-pricing.md            # sección «Blog (013)» y contrato público
```

**Structure Decision**: Se mantiene el monorepo actual (Angular más migraciones Supabase), como en 009 y 016.
- **Base de datos**: guarda las reglas de negocio. Validación de bloques y de publicación, transiciones, aislamiento y migración viven en migraciones y RPC de PostgreSQL.
- **Angular**: ofrece el editor y servicios tipados.
- **Contrato público**: se documenta para el sitio de cada agencia, que es quien pinta los bloques.
- **Módulo**: el blog es un dominio propio (`core/blog`, `features/blog`), separado de `catalog`. Su documentación vive junto al resto del contenido público en `catalog-pricing.md`.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| — | — | Sin violaciones vigentes. El conflicto con *Content Management* se resolvió con ADR-0004 y la enmienda constitucional del 2026-11-17; la justificación y las alternativas descartadas están en el ADR. |
