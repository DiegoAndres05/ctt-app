# Implementation Plan: Base multiagencia del contenido público

**Branch**: `016-multiagency-public-cms` | **Date**: 2026-11-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/016-multiagency-public-cms/spec.md`

## Summary

Extender la configuración pública existente para que cada agencia tenga sus propias
categorías, tipos de alojamiento, amenidades, perfil y credencial pública, conservando
la compatibilidad de CTT durante la transición. La solución reutiliza el aislamiento
por `organization_id`, las políticas RLS, las RPC protegidas y la proyección pública
existente; añade configuración pública y validaciones sin modificar los identificadores,
imágenes ni fichas ya publicadas.

## Technical Context

**Language/Version**: TypeScript 6 / Angular 22; SQL PostgreSQL 17

**Primary Dependencies**: Supabase Auth, PostgreSQL RLS, Supabase Storage, Angular Signals/Signal Forms

**Storage**: PostgreSQL/Supabase; Storage para el logo y referencias de imágenes existentes

**Testing**: arnés SQL `./supabase/tests/run-sql-tests.sh`; Vitest mediante `npm test`; lint y build Angular

**Target Platform**: panel web Angular y vitrinas externas que consumen la interfaz pública

**Project Type**: aplicación web multi-tenant con backend Supabase y contrato público de lectura/intake

**Performance Goals**: consultas públicas de catálogo y perfil en menos de 500 ms p95 bajo carga normal; operaciones de panel en menos de 2 s p95

**Constraints**: aislamiento estricto por agencia; respuestas indistinguibles para claves inválidas; la clave se almacena solo de forma no reversible; la clave anterior expira a los 7 días; no exponer datos internos; conservar compatibilidad de CTT

**Scale/Scope**: múltiples agencias, cada una con taxonomías, un perfil público y una o más claves históricas; la primera entrega cubre panel y contrato externo, no una vitrina alojada

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

* **Business Value**: PASS — permite operar el catálogo público por agencia y reduce dependencia de CTT.
* **Security by Design**: PASS — RLS, autorización por rol, credenciales limitadas, auditoría y no enumeración son requisitos del diseño.
* **Multi-tenant Readiness**: PASS — toda entidad nueva tiene `organization_id` y las operaciones cruzadas se rechazan.
* **Explicitness and Data Integrity**: PASS — estados, expiración, unicidad y reglas de publicación quedan modelados y probados.
* **Reuse Over Duplication**: PASS — se extienden `public_sites`, `public_categories`, `public_listings` y sus servicios en lugar de crear una segunda vitrina.
* **Testing and Traceability**: PASS — se añaden pruebas SQL de RLS/credenciales/rotación y pruebas unitarias de modelos/servicios.

## Project Structure

### Documentation (this feature)

```text
specs/016-multiagency-public-cms/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
supabase/
├── migrations/
├── functions/
└── tests/
    ├── public_cms_config_test.sql
    ├── public_key_security_test.sql
    └── public_source_transition_test.sql

src/app/
├── core/catalog/models/
├── core/catalog/services/
├── features/catalog/
│   ├── public-categories/
│   ├── public-taxonomies/
│   ├── public-profile/
│   └── public-key/
└── shared/

specs/016-multiagency-public-cms/
├── contracts/
├── data-model.md
├── quickstart.md
└── research.md
```

**Structure Decision**: Se mantiene el monorepo actual. Las reglas de negocio y el
aislamiento viven en migraciones/RPCs PostgreSQL; Angular ofrece las pantallas de
configuración y servicios tipados. Las interfaces externas se documentan como
contratos JSON independientes de la implementación.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | No se identifican violaciones de la constitución. |
