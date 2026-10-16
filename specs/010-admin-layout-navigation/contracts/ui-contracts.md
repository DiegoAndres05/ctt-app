# UI Contracts: Navegación lateral, listados y CMS guiado con vista previa

**Feature**: 010-admin-layout-navigation  
**Date**: 2026-09-30

No hay endpoints públicos nuevos. El contrato es de **rutas, query params y componentes**. Las RPC de 001/002/009 no cambian.

## Route map

All routes below sit under the authenticated shell (`canActivate: authGuard, passwordChangeGuard`) except where noted.

| Path | Min role | Screen | Opens with |
|------|----------|--------|------------|
| `/login`, `/register` | public | Auth, no sidebar | — |
| `/change-password` | session | Auth, no sidebar | — |
| `/dashboard` | any authenticated | Empty dashboard | — |
| `/sales/requests` | agent | Request inbox | `?q&page&status&channel&assignee` |
| `/sales/requests/new` | agent | Assisted intake | `?channel&customerId` |
| `/sales/requests/:id` | agent | Request detail | — |
| `/sales/customers` | agent | Customer directory | `?q&page` |
| `/sales/customers/:id` | agent | Customer profile | — |
| `/sales/quotations` | agent | Quotation list | — |
| `/sales/quotations/new` | agent | Quotation draft create | `?preReservationId` |
| `/sales/quotations/:versionId` | agent | Quotation detail / editor | — |
| `/sales/reservations` | agent | Reservation list | — |
| `/sales/reservations/new` | agent | Reservation confirm | `?quotationVersionId` |
| `/sales/reservations/:id` | agent | Reservation detail (lifecycle, voucher, service orders) | — |
| `/q/:token` | public (no session, outside the shell) | Client quotation view | — |
| `/settings/users` | admin | User list | `?q&page&role&status` |
| `/settings/users/new` | admin | User create | — |
| `/settings/users/:id` | admin | User detail | — |
| `/settings/roles` | admin | Role matrix | — |
| `/settings/audit` | admin | Audit log | existing filters |
| `/cms/experiences` | agent | Experience list (includes yachts) | `?q&page&status&publicStatus&placement&categoryId` |
| `/cms/experiences/new` | operator | Product editor (`type=experience`) | — |
| `/cms/experiences/:id` | agent | Product editor (readonly if agent) | — |
| `/cms/accommodations` | agent | Accommodation list | same minus `placement` |
| `/cms/accommodations/new` | operator | Product editor (`type=accommodation`) | — |
| `/cms/accommodations/:id` | agent | Product editor | — |
| `/cms/packages` | agent | Package list | list query |
| `/cms/packages/new` | operator | Package builder | — |
| `/cms/packages/:id` | agent | Package builder | — |
| `/cms/settings` | operator | Settings hub | — |
| `/cms/settings/categories` | operator | Ops categories | — |
| `/cms/settings/public-categories` | operator | Public categories | — |
| `/cms/settings/addons` | operator | Add-ons | — |
| `/cms/settings/cutover` | admin | Public cutover | — |

Default authenticated path: `/` → `/dashboard`.

Exception (005): `/q/:token` is public like `/login` — no `authGuard`, no sidebar, no
shell. Every other route above renders inside the authenticated shell.

### Compatibility redirects (FR-009)

| From | To |
|------|----|
| `/users` | `/settings/users` |
| `/users/:id` | `/settings/users/:id` |
| `/audit` | `/settings/audit` |
| `/catalog` | `/cms/experiences` |
| `/catalog/products` | `/cms/experiences` |
| `/catalog/products/new` | `/cms/experiences/new` |
| `/catalog/products/:id` | `/cms/experiences/:id` |
| `/catalog/packages` | `/cms/packages` |
| `/catalog/packages/:rest` | `/cms/packages/:rest` |
| `/catalog/addons` | `/cms/settings/addons` |
| `/catalog/addons/:rest` | `/cms/settings/addons/:rest` |
| `/catalog/public-categories` | `/cms/settings/public-categories` |
| `/catalog/public-cutover` | `/cms/settings/cutover` |

Forbidden deep links keep `roleGuard` behavior: no content, message «No tienes permisos…», stay in the shell.

## List query contract

Shared query string:

```
q?: string
page?: number          # default 1, size fixed at 20
```

Users add:

```
role?: admin|operator|agent
status?: active|inactive
```

CMS product lists add:

```
status?: draft|active|inactive
publicStatus?: none|draft|published|unpublished|sold_out
categoryId?: uuid
placement?: catalog|yacht   # experiences only
```

**Client behavior**:
- Debounce `q` ~300 ms.
- Changing any filter resets `page` to 1.
- The same query is written back so refresh and share reproduce the list.

## Navigation tree contract

Visible items by role (FR-004):

| Item | admin | operator | agent |
|------|-------|----------|-------|
| Dashboard | ✓ | ✓ | ✓ |
| Comercial / Solicitudes | ✓ | ✓ | ✓ |
| Comercial / Clientes | ✓ | ✓ | ✓ |
| Comercial / Cotizaciones | ✓ | ✓ | ✓ |
| Comercial / Reservas | ✓ | ✓ | ✓ |
| Configuración / Usuarios | ✓ | — | — |
| Configuración / Roles y permisos | ✓ | — | — |
| Configuración / Auditoría | ✓ | — | — |
| CMS / Experiencias | ✓ | ✓ | ✓ |
| CMS / Alojamientos | ✓ | ✓ | ✓ |
| CMS / Paquetes | ✓ | ✓ | ✓ |
| CMS / Ajustes del catálogo | ✓ | ✓ | — |
| Ajustes / Publicación del sitio | ✓ | — | — |

Active item: longest matching `path` prefix of the current URL. Parent group stays expanded.

Agregado por 003 (orden: Dashboard → Comercial → Configuración → CMS). Cotizaciones
agregada por 005 dentro de Comercial (`minRole: agent`, visible también para operator y
admin); `/q/:token` no aparece en el menú. Reservas agregada por 006 dentro de Comercial
(`minRole: agent`, visible también para operator y admin), con las rutas
`/sales/reservations`, `/sales/reservations/new` y `/sales/reservations/:id`.

## Preview card contract

Input: `PreviewListing` (see data-model). Output: a card with:

1. Cover (image or placeholder; loading state while upload in flight)
2. Title (truncated ~70) or «Sin título»
3. Short description (truncated ~140) or «Falta la descripción en {idioma}» when `missingLocale`
4. Public category + location
5. Display price + currency (hidden when yacht and empty)
6. Sold-out badge when `soldOut`

Locale toggle is a sibling control, not inside the card.

## Service extensions (internal)

These are TypeScript APIs, not new RPCs.

```ts
ProductService.listPage(input: {
  type: 'experience' | 'accommodation' | 'package';
  q?: string;
  status?: ProductStatus;
  publicStatus?: 'none' | PublicListingStatus | 'sold_out';
  placement?: 'catalog' | 'yacht';
  categoryId?: string;
  page: number; // 1-based, page size 20
}): Promise<{ rows: ProductListRow[]; total: number }>;

UserService.list(): Promise<UserProfile[]>; // unchanged
UserService.listWithLastAccess(): Promise<UserListRow[]>;
```

`listWithLastAccess` batches latest `login_success` from `audit.audit_events`. Filtering and pagination of users may be client-side if the tenant has few collaborators; if the list exceeds a few hundred, apply the same `range` pattern.

## Unchanged RPCs

`create_product`, `set_product_status`, `upsert_pricing_scheme`, `save_public_listing`, `publish_public_listing`, `unpublish_public_listing`, `attach_public_image`, `create_internal_user`, `toggle_user_status`, `change_user_role`, `get_public_site`, cutover RPCs — signatures and rules stay as in 001/002/009.
