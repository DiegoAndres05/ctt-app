# Quickstart: Navegación lateral, listados y CMS guiado con vista previa

**Feature**: 010-admin-layout-navigation  
**Date**: 2026-09-30

Guía de validación manual. No sustituye a `tasks.md`.

## Prerequisites

```bash
npm install
npx supabase start          # local stack; reuse the seeded agency from 001/009
npm start                   # http://127.0.0.1:4200
```

Need three collaborators in the same org: **admin**, **operator**, **agent**. Use the users already created in 001 or provision them from `/settings/users` once the admin shell works.

## 1. Shell and menu (US1)

1. Open `/login` — no sidebar.
2. Sign in as admin — land on `/dashboard` with left sidebar: Dashboard, Configuración, CMS.
3. Expand Configuración: Usuarios, Roles y permisos, Auditoría.
4. Expand CMS: Experiencias, Alojamientos, Paquetes, Ajustes del catálogo.
5. Open Experiencias — CMS stays open and Experiencias is highlighted.
6. Sign in as operator — Configuración is absent; CMS is complete except Publicación del sitio.
7. Sign in as agent — Configuración and Ajustes del catálogo are absent; CMS lists are visible.
8. As agent, type `/settings/users` — denied message, no user list.
9. Narrow the viewport — sidebar becomes a drawer; desktop collapse remembers the next reload.

## 2. Dashboard (US2)

1. After login (no pending password change) the URL is `/dashboard`.
2. Greeting uses the collaborator name; body explains that indicators come later.
3. No duplicate nav links to Catálogo / Usuarios / Auditoría.
4. Sidebar «Dashboard» returns here from any screen.

## 3. Lists (US3)

1. Admin → Usuarios: columns name, email, role, status (incl. pending password change), last access. «Nuevo usuario» visible.
2. Type a name — after a short pause the table filters. `?q=` is in the URL.
3. Open a user and go back — query string is intact.
4. CMS → Experiencias: thumbnail, name, category, product status, public status, display price. Filter placement = Yates.
5. Agent on Experiencias: no create button; row opens read-only.
6. Empty filters that match nothing: «sin resultados» + clear filters. Brand-new empty section: empty-state copy + create (if allowed).

## 4. Live preview (US4)

1. Operator → Experiencias → Nueva experiencia.
2. Preview card shows placeholders.
3. Type a title — card title updates without save.
4. Fill short description, public category, location, cover, display price — each appears on the card.
5. Toggle EN — missing English copy is flagged, Spanish is not substituted.
6. Set placement to yates — card switches to yacht layout; price may be empty.
7. Open an accommodation — card shows lodging type and occupancy.

## 5. Sectioned editor (US5)

1. Sections appear in order: básica, operativa, categorías/adicionales, contenido público, imágenes, precio, publicación (+ opiniones on lodging).
2. Images and price stay disabled with «Guarda el borrador para continuar» until the first save.
3. First save creates a draft, enables those sections, stays on the same screen.
4. Incomplete required fields show errors on the field and mark the section.
5. Publicación lists pending 009 gates and does not offer Publish until they pass.
6. Navigate away with dirty fields — confirm dialog; Cancel stays.
7. Agent opening `:id` sees the same sections and preview, no save/publish/status actions.

## 6. Roles (US6)

1. Admin → Roles y permisos: three roles, active counts, capability matrix.
2. Click Operador → `/settings/users?role=operator`.

## Compatibility

- `/users`, `/audit`, `/catalog/products` still resolve to the new screens.

## Out of this check

- Changing `get_public_site` or running 009 SQL tests.
- Filling the dashboard with analytics (008).
