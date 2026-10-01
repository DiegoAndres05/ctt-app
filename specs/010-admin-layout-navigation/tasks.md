# Tasks: Navegación lateral, listados y CMS guiado con vista previa

**Input**: Design documents from `/specs/010-admin-layout-navigation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ui-contracts.md, quickstart.md

**Tests**: Unit tests only where the plan calls them out (nav tree, preview model, list query). No new SQL tests.

**Organization**: Tasks are grouped by user story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story label (US1–US6)
- Paths are repository-relative

## Path Conventions

Angular modular monolith: `src/app/shared`, `src/app/features`, `src/app/core`, `src/app/app.routes.ts`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Folders and docs so the new layout has a home

- [x] T001 Create `src/app/shared/layout/` and `src/app/shared/components/data-table/` directories per `specs/010-admin-layout-navigation/plan.md`
- [x] T002 [P] Point module docs at this feature: update the Spec Kit pointer already in `AGENTS.md` is done; add a short «Admin layout» note to `docs/modules/identity-access.md` and `docs/modules/catalog-pricing.md` describing the new routes

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shell route, nav tree, redirects. Blocks every story.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 Write the static nav tree and role visibility helpers in `src/app/shared/layout/nav-items.ts` per `specs/010-admin-layout-navigation/contracts/ui-contracts.md`
- [x] T004 [P] Add Vitest coverage for `visibleNavItems(role)` and active-item matching in `src/app/shared/layout/nav-items.spec.ts`
- [x] T005 Implement `SidebarNavComponent` in `src/app/shared/layout/sidebar-nav.component.ts` (expand/collapse groups, active highlight, drawer under 960px, desktop icon collapse persisted as `ctt.sidebar.collapsed`)
- [x] T006 Implement `AdminShellComponent` in `src/app/shared/layout/admin-shell.component.ts` with sidebar, top bar (name, role, organization, sign out) and `<router-outlet>`
- [x] T007 Restructure `src/app/app.routes.ts`: wrap authenticated children (except `change-password`) in `AdminShellComponent`; add `/settings/*` and `/cms/*` destinations using existing feature components as placeholders; add compatibility `redirectTo` from `/users`, `/audit`, `/catalog/**` as in `contracts/ui-contracts.md`; keep `roleGuard` on every protected path
- [x] T008 Move the denied-permission alert from `src/app/features/dashboard/dashboard.component.ts` into the shell (or a shared outlet) so deep-link denials still show inside the layout

**Checkpoint**: Login as admin/operator/agent shows the correct menu; old URLs redirect; login/register/change-password have no sidebar

---

## Phase 3: User Story 1 - Moverse por el panel con un menú lateral (Priority: P1) 🎯 MVP

**Goal**: Collaborators navigate the panel from a left sidebar that respects role and highlights the current section

**Independent Test**: Sign in with each role, confirm the menu matches FR-004, current item is highlighted, and a forbidden URL is denied

- [x] T009 [US1] Wire `SidebarNavComponent` to `AuthService` role and `Router` URL so groups stay expanded on the active child in `src/app/shared/layout/sidebar-nav.component.ts`
- [x] T010 [US1] Remove per-page «Panel» back-links from `src/app/features/users/user-list/user-list.component.ts`, `src/app/features/audit/audit-log/audit-log.component.ts`, and `src/app/features/catalog/catalog-shell/catalog-shell.component.ts` so navigation lives only in the sidebar
- [x] T011 [US1] Add a CMS settings hub at `src/app/features/catalog/catalog-settings/catalog-settings.component.ts` listing categorías, categorías públicas, adicionales and (admin) publicación del sitio

**Checkpoint**: US1 is demoable without new list columns or the product editor

---

## Phase 4: User Story 2 - Dashboard inicial vacío (Priority: P1)

**Goal**: Login lands on a greeting dashboard that does not duplicate the menu

**Independent Test**: Sign in → `/dashboard` with name + empty-state copy, no Catálogo/Usuarios/Auditoría links

- [x] T012 [US2] Rewrite `src/app/features/dashboard/dashboard.component.ts` to a greeting + future-indicators empty state; drop local nav and sign-out (those belong to the shell)

**Checkpoint**: US1 + US2 work together; dashboard is the post-login home

---

## Phase 5: User Story 3 - Listados como pantalla inicial (Priority: P1)

**Goal**: Each submenu opens a shared-format list (20/page, URL state, role-aware create)

**Independent Test**: Users, Experiencias and Alojamientos open lists with the columns in FR-014/FR-015; query string survives back/share; agent has no create button

- [x] T013 [P] [US3] Build shared list chrome (title, create slot, search, filters, table, pagination, empty / no-results) in `src/app/shared/components/data-table/data-table.component.ts`
- [x] T014 [P] [US3] Add list-query helpers (parse/write query params, debounce 300 ms, reset page on filter change) in `src/app/shared/components/data-table/list-query.ts` and a spec in `src/app/shared/components/data-table/list-query.spec.ts`
- [x] T015 [US3] Extend `src/app/core/catalog/services/product.service.ts` with `listPage` returning `ProductListRow[]` + `total` (join public listing for thumb, public status, display price, placement) per `data-model.md`
- [x] T016 [US3] Add `listWithLastAccess` in `src/app/features/users/services/user.service.ts` batching latest `login_success` from `audit.audit_events`
- [x] T017 [US3] Rebuild `src/app/features/users/user-list/user-list.component.ts` on the shared table: name, email, role, status + pending password change, last access; filters `q`, `role`, `status`; 20/page; create button admin-only
- [x] T018 [US3] Split `src/app/features/catalog/products/product-list/product-list.component.ts` into experience and accommodation modes (route data `type`) with columns thumb, name, category, product status, public status, display price; experiences add placement column/filter
- [x] T019 [P] [US3] Align `src/app/features/catalog/packages/package-list/package-list.component.ts` and `src/app/features/catalog/addons/addon-list/addon-list.component.ts` with the same list chrome and query persistence
- [x] T020 [US3] Hide create buttons for agents on CMS lists using `hasRoleAtLeast(..., 'operator')` in the product/package/addon list components

**Checkpoint**: Every submenu’s first screen is its list; `/settings/users?role=operator` filters correctly

---

## Phase 6: User Story 4 - Mini vista previa en vivo (Priority: P1)

**Goal**: Experience/accommodation (and package) forms show a card that fills as the user types

**Independent Test**: Type a title on Nueva experiencia — the card updates without save; EN toggle flags missing copy; yacht placement uses the yacht card

- [x] T021 [P] [US4] Add `PreviewListing` mapper and locale/truncation helpers in `src/app/shared/components/listing-preview/preview-listing.model.ts` plus `preview-listing.spec.ts`
- [x] T022 [US4] Implement `ListingPreviewCardComponent` in `src/app/shared/components/listing-preview/listing-preview-card.component.ts` (catalog | lodging | yacht, placeholders, sold-out, image loading)
- [x] T023 [US4] Mount the card beside the product form (and package builder) once the editor exists; until T026, mount it on the current create/detail templates in `src/app/features/catalog/products/` so US4 can be shown independently

**Checkpoint**: Preview works on create even if the sectioned editor is not finished

---

## Phase 7: User Story 5 - Formularios del CMS por secciones (Priority: P2)

**Goal**: One editor for create and edit, sections in spec order, draft-first images/price, publish gates, unsaved-changes warning, agent read-only

**Independent Test**: Create an experience end-to-end, save mid-way, resume from the list, see publish blockers; agent opens the same screen read-only

- [x] T024 [US5] Add `unsavedChangesGuard` in `src/app/shared/components/unsaved-changes.guard.ts` and attach it to product/package/addon/category form routes in `src/app/app.routes.ts`
- [x] T025 [US5] Create `src/app/features/catalog/products/product-editor/product-editor.component.ts` that replaces `product-create` and `product-detail`: sections básica → operativa → categorías/adicionales → contenido público → imágenes → precio → publicación (+ opiniones on lodging)
- [x] T026 [US5] First save calls `create_product`, then enables images/price in place (navigate to `:id` without losing field values); subsequent saves update product + `save_public_listing`
- [x] T027 [US5] Port pricing editor, status, category assignment, add-on links, gallery, guest reviews and 009 publish/unpublish/sold-out actions from `src/app/features/catalog/products/product-detail/product-detail.component.ts` into the editor sections without dropping behavior
- [x] T028 [US5] Publicación section lists pending 009 gates and hides Publish until they pass; bind live `PreviewListing` (T021–T022) to form signals with ES/EN toggle
- [x] T029 [US5] Agent path: same sections + preview, controls read-only, no save/publish/status actions (`hasRoleAtLeast` / `roleGuard`)
- [x] T030 [US5] Apply the same section chrome (required markers, field errors, save/cancel placement) to `src/app/features/catalog/packages/package-builder/package-builder.component.ts`, `src/app/features/catalog/addons/addon-form/addon-form.component.ts`, and `src/app/features/catalog/public-categories/public-categories.component.ts`
- [x] T031 [US5] Delete or re-export obsolete create/detail entry points so routes only load `ProductEditorComponent`; keep redirects from `/catalog/products/:id`

**Checkpoint**: Create and edit are the same screen; 009 publish rules still hold

---

## Phase 8: User Story 6 - Roles y permisos de consulta (Priority: P3)

**Goal**: Admin sees the three roles, active counts, and a capability matrix

**Independent Test**: Open Roles y permisos; click Operador and land on `/settings/users?role=operator`

- [x] T032 [US6] Add `src/app/features/users/roles/roles-matrix.component.ts` with static matrix from `data-model.md`, active counts from `UserService.list`, and navigation to the user list with `?role=`
- [x] T033 [US6] Register `/settings/roles` in `src/app/app.routes.ts` behind `roleGuard('admin')`

**Checkpoint**: All six stories are independently testable

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Visual consistency, docs, validation

- [x] T034 [P] Shared form/list spacing and typography in `src/app/shared/layout/admin-shell.component.ts` (and a small `src/styles.scss` if needed) so lists and editors look like one product
- [x] T035 [P] Update `docs/modules/identity-access.md` and `docs/modules/catalog-pricing.md` with the final route table
- [x] T036 Remove leftover catalog-shell-only navigation if `src/app/features/catalog/catalog-shell/catalog-shell.component.ts` is unused after redirects
- [x] T037 Run `npm test`, `npm run lint`, and the manual checks in `specs/010-admin-layout-navigation/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational
- **US2 (Phase 4)**: Depends on Foundational; uses the shell from US1
- **US3 (Phase 5)**: Depends on Foundational; lists sit inside the shell
- **US4 (Phase 6)**: Preview card can be built in parallel with US3; mount on editor in US5
- **US5 (Phase 7)**: Depends on US3 lists (entry points) and US4 card
- **US6 (Phase 8)**: Depends on US3 user-list query params
- **Polish (Phase 9)**: After the stories to ship

### User Story Dependencies

- **US1**: After Phase 2
- **US2**: After Phase 2 (shell already in place)
- **US3**: After Phase 2
- **US4**: After Phase 2; independently demoable on current create form
- **US5**: After US3 + US4
- **US6**: After US3

### Parallel Opportunities

- T002, T004 in parallel with neighboring setup/foundation tasks
- T013 and T014 in parallel
- T019 in parallel with T017/T018 after T013
- T021 in parallel with list work
- T032 after T017 (`?role=` must exist)

---

## Parallel Example: User Story 3

```bash
Task: "Shared data-table chrome in src/app/shared/components/data-table/data-table.component.ts"
Task: "List-query helpers in src/app/shared/components/data-table/list-query.ts"
```

Then sequentially: `listPage` / `listWithLastAccess` → user list → product lists → package/addon alignment.

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Phase 1 + 2
2. US1 sidebar
3. US2 empty dashboard
4. Validate login → menu → dashboard

### Incremental Delivery

1. MVP (shell + dashboard)
2. US3 lists
3. US4 preview on create
4. US5 unified editor
5. US6 roles matrix
6. Polish + quickstart

### Suggested MVP scope

Ship Phase 1–4 (shell, menu, dashboard). Lists and CMS editor are the next increment; do not stop there for this request — implement all phases.

---

## Notes

- Do not add business tables or change 009 RPCs
- Do not commit unless the user asks
- Mark each task `[x]` in this file when done
- Spanish UI copy
