---

description: "Task list for Base multiagencia del contenido público"
---

# Tasks: Base multiagencia del contenido público

**Input**: Design documents from `/specs/016-multiagency-public-cms/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently after the foundational phase.

## Phase 1: Setup

- [x] T001 Create the feature migration sequence and focused SQL test file names in `supabase/migrations/` and `supabase/tests/` according to `specs/016-multiagency-public-cms/plan.md`
- [x] T002 [P] Add the feature model/service/component path map and verify referenced paths in `specs/016-multiagency-public-cms/quickstart.md`
- [x] T003 [P] Inventory existing public listing, category, cutover and audit RPCs in `supabase/migrations/023_public_listings.sql`, `supabase/migrations/024_public_listing_rpcs.sql`, `supabase/migrations/025_public_site_read.sql` and `src/app/core/catalog/services/public-listing.service.ts`

---

## Phase 2: Foundational

**Purpose**: Add shared tenant-safe primitives required by every user story.

- [x] T004 Add agency-scoped taxonomy, profile, access-key and source-policy tables with constraints and indexes in `supabase/migrations/058_public_agency_configuration.sql`
- [x] T005 Add RLS policies and authenticated role guards for all new tables in `supabase/migrations/058_public_agency_configuration.sql`
- [x] T006 Add idempotent seed/backfill logic for generic agency defaults and CTT's existing eight public category identifiers in `supabase/migrations/059_public_agency_configuration_seed.sql`
- [x] T007 Add shared audit event types and immutable actor/agency metadata for public configuration changes in `supabase/migrations/060_public_agency_configuration_audit.sql`
- [x] T008 [P] Define TypeScript models, literal unions and payload types for agency taxonomies, public profile, access keys and source policy in `src/app/core/catalog/models/public-agency-config.model.ts`
- [x] T009 [P] Add shared public configuration error-code mapping and user-facing messages in `src/app/core/error/error-handler.ts`
- [x] T010 Add tenant-scoped service helpers for loading agency configuration and handling RPC errors in `src/app/core/catalog/services/public-agency-config.service.ts`
- [x] T011 Add the foundational multi-agency isolation regression suite covering authenticated tenant reads and cross-tenant writes in `supabase/tests/public_cms_tenant_isolation_test.sql`

---

## Phase 3: User Story 1 - Configurar la clasificación pública (Priority: P1) 🎯 MVP

**Goal**: Each agency can independently manage bilingual public categories, lodging types and amenities, while used values remain visible and deletions are prevented.

**Independent Test**: Create the same code in two agencies, verify each agency sees only its own value, exercise Operator/Admin writes, reject Agent writes, and deactivate a value used by a published listing without removing its display snapshot.

- [x] T012 [P] [US1] Add SQL tests for agency-local uniqueness, default values, role permissions, deactivation and used-value deletion protection in `supabase/tests/public_cms_config_test.sql`
- [x] T013 [P] [US1] Add model validation tests for bilingual labels, stable codes and active-state behavior in `src/app/core/catalog/models/public-agency-config.spec.ts`
- [x] T014 [US1] Add taxonomy CRUD, activation/deactivation and used-value checks as `SECURITY DEFINER` RPCs in `supabase/migrations/061_public_agency_taxonomy_rpcs.sql`
- [x] T015 [US1] Extend the listing data model and publish validation to resolve agency taxonomy values while preserving display snapshots in `supabase/migrations/061_public_agency_taxonomy_rpcs.sql`
- [x] T016 [US1] Implement category, lodging-type and amenity list/create/update/deactivate methods in `src/app/core/catalog/services/public-agency-config.service.ts`
- [x] T017 [US1] Build the categories management screen with bilingual create/edit, active-state controls and protected-value feedback in `src/app/features/catalog/public-categories/public-categories.component.ts`
- [x] T018 [US1] Build the lodging types and amenities management screen with separate lists, bilingual forms and deactivation feedback in `src/app/features/catalog/public-taxonomies/public-taxonomies.component.ts`
- [x] T019 [US1] Add role-aware navigation and route protection for public taxonomy configuration in `src/app/app.routes.ts` and `src/app/shared/layout/nav-items.ts`
- [x] T020 [US1] Add focused frontend tests for taxonomy loading, validation, Agent denial and used-value deactivation in `src/app/features/catalog/public-taxonomies/public-taxonomies.component.spec.ts`

---

## Phase 4: User Story 2 - Gestionar la clave pública (Priority: P1)

**Goal**: Administrators can generate, rotate and revoke a public credential with a seven-day rotation grace period and generic invalid-key responses.

**Independent Test**: Generate a key, consume the public projection, regenerate it, verify old-key validity during seven days and expiration afterward, revoke a key immediately, and compare invalid-key responses.

- [x] T021 [P] [US2] Add SQL tests for key hashing, Administrator-only visibility, Operator/Agent denial, seven-day grace expiration, immediate revocation and generic invalid-key responses in `supabase/tests/public_key_security_test.sql`
- [x] T022 [P] [US2] Add contract tests for valid and invalid public-key response shapes in `supabase/tests/public_key_contract_test.sql`
- [x] T023 [US2] Implement secure key generation, fingerprint storage, current-key lookup, seven-day rotation grace and revocation RPCs in `supabase/migrations/062_public_access_key_rpcs.sql`
- [x] T024 [US2] Implement generic public-key authorization and projection scoping for public catalog/profile reads in `supabase/migrations/063_public_key_public_read.sql`
- [x] T025 [US2] Add public-key audit events without secret material in `supabase/migrations/062_public_access_key_rpcs.sql`
- [x] T026 [US2] Add key generation, regeneration, revocation and metadata methods to `src/app/core/catalog/services/public-agency-config.service.ts`
- [x] T027 [US2] Build the Administrator-only public-key screen with one-time secret display, expiration warning and revocation confirmation in `src/app/features/catalog/public-key/public-key.component.ts`
- [x] T028 [US2] Add route and role guards for the public-key screen in `src/app/app.routes.ts`
- [x] T029 [US2] Add frontend tests for one-time key display, seven-day expiration messaging and forbidden roles in `src/app/features/catalog/public-key/public-key.component.spec.ts`

---

## Phase 5: User Story 3 - Administrar el perfil público (Priority: P1)

**Goal**: Operators and Administrators can manage the agency profile consumed by a public showcase, without exposing internal data.

**Independent Test**: Save all supported profile fields, read the public projection, omit optional fields, reject unsupported language/currency values and verify Agent denial plus audit evidence.

- [x] T030 [P] [US3] Add SQL tests for profile validation, tenant isolation, role permissions, optional fields and audit records in `supabase/tests/public_profile_test.sql`
- [x] T031 [P] [US3] Add public projection contract tests proving only configured public profile fields are returned in `supabase/tests/public_profile_contract_test.sql`
- [x] T032 [US3] Implement profile save/read RPCs with language, currency, URL, color and optional-field validation in `supabase/migrations/064_public_profile_rpcs.sql`
- [x] T033 [US3] Extend the public site projection to return the agency profile and published catalog without internal fields in `supabase/migrations/065_public_profile_projection.sql`
- [x] T034 [US3] Add logo upload/reference validation using the existing catalog media conventions in `supabase/migrations/065_public_profile_projection.sql` and `src/app/core/catalog/services/public-agency-config.service.ts`
- [x] T035 [US3] Build the public profile editor for identity, contact channels, social links, languages and currency in `src/app/features/catalog/public-profile/public-profile.component.ts`
- [x] T036 [US3] Add profile form models, validation messages and dirty-state protection in `src/app/features/catalog/public-profile/public-profile.component.ts`
- [x] T037 [US3] Add role-aware route/navigation entries and frontend profile tests in `src/app/app.routes.ts`, `src/app/shared/layout/nav-items.ts` and `src/app/features/catalog/public-profile/public-profile.component.spec.ts`

---

## Phase 6: User Story 4 - Mantener la compatibilidad de CTT (Priority: P1)

**Goal**: Preserve CTT category IDs, listing slugs and images while allowing its organization identifier only during the configured transition.

**Independent Test**: Read all eight CTT category identifiers and existing listing references, consume with the organization identifier during transition, end the transition, and verify key-based access remains valid.

- [x] T038 [P] [US4] Add SQL regression tests for CTT category identifiers, listing slugs, image references and organization-identifier transition behavior in `supabase/tests/public_source_transition_test.sql`
- [x] T039 [P] [US4] Extend existing cutover tests to cover migration-free agencies and CTT-only identifier compatibility in `supabase/tests/public_cutover_test.sql`
- [x] T040 [US4] Add source-policy state, CTT transition cutoff and migration-required behavior to the public-site model in `supabase/migrations/066_public_source_policy.sql`
- [x] T041 [US4] Update public read and request-intake authorization to accept the CTT organization identifier only before its cutoff and never for other agencies in `supabase/migrations/067_public_source_compatibility.sql`
- [x] T042 [US4] Update cutover completion RPCs to bypass the manifest gate for migration-free agencies and retain the existing gate for migrated agencies in `supabase/migrations/067_public_source_compatibility.sql`
- [x] T043 [US4] Add source-policy and transition status methods to `src/app/core/catalog/services/public-agency-config.service.ts`
- [x] T044 [US4] Extend the public cutover screen to show migration mode, transition status and blocked missing items without changing existing listing controls in `src/app/features/catalog/public-cutover/public-cutover.component.ts`
- [x] T045 [US4] Add frontend tests for migration-required versus migration-free source behavior in `src/app/features/catalog/public-cutover/public-cutover.component.spec.ts`

---

## Phase 7: User Story 5 - Publicar directamente o migrar contenido (Priority: P2)

**Goal**: Agencies with an existing site must complete the manifest before cutover; new agencies can publish directly.

**Independent Test**: Block a migrated agency with one missing manifest item, complete it and cut over, then publish directly for a migration-free agency.

- [x] T046 [P] [US5] Add SQL tests for missing-manifest blocking, successful migrated cutover, direct publication and preservation of public identifiers in `supabase/tests/public_source_migration_test.sql`
- [x] T047 [P] [US5] Add contract tests for source status, missing items and cutover outcomes in `supabase/tests/public_source_contract_test.sql`
- [x] T048 [US5] Implement source-mode configuration and administrator-only transition operations in `supabase/migrations/068_public_source_management_rpcs.sql`
- [x] T049 [US5] Add missing-item and cutover result types to `src/app/core/catalog/models/public-agency-config.model.ts`
- [x] T050 [US5] Add source-mode configuration and cutover methods to `src/app/core/catalog/services/public-agency-config.service.ts`
- [x] T051 [US5] Add migration-mode controls and actionable missing-item status to `src/app/features/catalog/public-cutover/public-cutover.component.ts`
- [x] T052 [US5] Add frontend tests for direct publication and migration blocking states in `src/app/features/catalog/public-cutover/public-cutover.component.spec.ts`

---

## Phase 8: Polish & Cross-Cutting Concerns

- [x] T053 [P] Update public catalog and identity-access module documentation with agency-scoped configuration, key rotation and privacy boundaries in `docs/modules/catalog-pricing.md` and `docs/modules/identity-access.md`
- [x] T054 [P] Add the public consumer and management contracts to the maintained documentation index in `specs/016-multiagency-public-cms/contracts/`
- [x] T055 Run all focused SQL suites from `specs/016-multiagency-public-cms/quickstart.md` and record failures without weakening assertions in `supabase/tests/run-sql-tests.sh`
- [x] T056 Run the required npm quality commands and fix only feature regressions in `specs/016-multiagency-public-cms/quickstart.md`
- [x] T057 Run the complete quickstart validation against two agencies plus the seeded CTT agency and verify the success criteria in `specs/016-multiagency-public-cms/quickstart.md`
- [x] T058 Review all public projection fields and audit payloads for secret, customer, internal-note, provider and cost leakage in `supabase/migrations/063_public_key_public_read.sql`, `supabase/migrations/065_public_profile_projection.sql` and `supabase/migrations/062_public_access_key_rpcs.sql`

---

## Notas de implementación (2026-11-13)

Implementado. Diferencias con las rutas previstas arriba:

- **Migraciones consolidadas** en seis archivos en lugar de once (058–068):
  `058_public_agency_config_enums.sql` (tipos de auditoría; van solos porque un valor de enum
  nuevo no se puede usar en la misma transacción), `059_public_agency_configuration.sql` (tablas,
  RLS, valores iniciales, backfill y marca de agencia migrada; T004–T007),
  `060_public_agency_taxonomy_rpcs.sql` (T014–T015), `061_public_access_keys.sql` (claves,
  proyección por clave, intake por clave y transición de CTT; T023–T025, T040–T041),
  `062_public_profile.sql` (T032–T034, T024) y `063_public_source_policy.sql` (T042, T048).
- **Pruebas SQL**: el aislamiento (T011) vive en `public_cms_config_test.sql`; los contratos de
  clave (T022), perfil (T031) y fuente (T047) están dentro de `public_key_security_test.sql`,
  `public_profile_test.sql` y `public_source_transition_test.sql`. `public_cutover_test.sql` y las
  otras cinco suites que usan el identificador de organización ahora marcan su agencia de prueba
  como migrada (`mark_public_site_as_migrated`).
- **Navegación (T019, T037)**: las pantallas nuevas cuelgan de «Ajustes del catálogo» (sección
  «Sitio público»), que ya está en el menú; el ítem activo sigue siendo `cms-settings`.
- **Transición de CTT**: 90 días desde la migración 059; un administrador puede cerrarla antes.
- **Editor de producto**: tipos y amenidades salen de la configuración de la agencia;
  `LODGING_TYPES` y `LODGING_AMENITIES` fijos se eliminaron.
- **Verificación (T055–T057)**: 49 suites SQL, `npm test` (174), lint y build en verde. SC-001 se
  probó con dos agencias, no diez; SC-004 (tiempo de uso) no se midió.

## Dependencies & Execution Order

- Setup (Phase 1) has no prerequisites.
- Foundational (Phase 2) depends on Setup and blocks all user stories.
- User Stories 1–4 depend on Foundational and can proceed in parallel after it.
- User Story 5 depends on User Story 4's source-policy compatibility primitives.
- Polish (Phase 8) depends on all selected stories.

### User story dependencies

- **US1**: Foundational only.
- **US2**: Foundational only; its public-key projection is consumed by US3 and US4.
- **US3**: Foundational plus US2's public projection authorization.
- **US4**: Foundational plus US2's public-key authorization.
- **US5**: US4; it completes the migration/direct-publication workflow.

### Parallel opportunities

- T002–T003 can run in parallel after T001.
- T008–T009 can run in parallel with T004–T007.
- T012–T013 can run in parallel.
- After Phase 2, US1 and US2 can start in parallel; US3 and US4 can begin once the shared projection/key contracts they consume are available.
- Within each story, SQL tests and model tests marked `[P]` can be authored in parallel before implementation.
- T053–T054 can run in parallel with the final validation tasks.

## Implementation strategy

1. Complete Setup and Foundational phases without changing current CTT behavior.
2. Deliver US1 as the MVP for agency-owned public classification.
3. Deliver US2 and US3 to establish the credential and safe agency profile boundary.
4. Deliver US4 to preserve CTT compatibility and then US5 for onboarding modes.
5. Run the full quickstart and quality gates before release.

## Format validation

All implementation tasks use `- [ ]`, sequential `T###` identifiers, `[P]` only
for independent work, `[US#]` on story tasks, and an explicit repository file path.

