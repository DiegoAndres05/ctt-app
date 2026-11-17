# Catalog & Pricing (002-catalog-pricing + 009-catalog-site-cms)

Module that owns the internal tourism catalog (experiences, accommodations, predefined
packages, add-ons) and versioned tariff schemes. Feature **009** adds the **public listing**
layer the agency website consumes (`get_public_site`), without opening `products` or
`pricing_schemes` to `anon`. Tenant isolation, JWT claims, and the audit trail are inherited
from Identity & Access.

**Spec (ops catalog)**: `specs/002-catalog-pricing/`
**Spec (public site CMS)**: `specs/009-catalog-site-cms/`
**Plan**: `specs/009-catalog-site-cms/plan.md` (current) · `specs/002-catalog-pricing/plan.md`

## What lives where

| Concern | Location |
| --- | --- |
| Schema, RLS, RPCs, triggers | `supabase/migrations/011_…` … `021_…` (ops) · `022_…` … `027_…` (public listings) |
| SQL verification | `supabase/tests/` (incl. `public_*_test.sql`) |
| Domain models | `src/app/core/catalog/models/` (`public-listing.model.ts` for 009) |
| Product / category / add-on / pricing / public listing services | `src/app/core/catalog/services/` |
| Catalog UI (Operator/Admin via `roleGuard`) | `src/app/features/catalog/` |
| Shared banners and spinners | `src/app/shared/components/` |

## Entities

| Entity | Table | Notes |
| --- | --- | --- |
| Product | `products` | Base row: `experience` \| `accommodation` \| `package`. Logical status `draft` / `active` / `inactive`. Never physically deleted. |
| Experience | `experiences` | 1:1 subtype (duration, difficulty, capacity). PK = `products.id`. |
| Accommodation | `accommodations` | 1:1 subtype (property type, location, occupancy). |
| Package | `packages` + `package_items` | Explicit package price (not the sum of components). Nested packages are rejected. |
| Category | `categories` + `product_categories` | Organization taxonomy, optional `parent_id`, N:M tagging. |
| Add-on | `add_ons` + `product_addons` | Independent complement; eligibility rules `is_mandatory` / `max_quantity`. |
| Pricing scheme | `pricing_schemes` | XOR `product_id` / `addon_id`. Currency per scheme (defaults from organization). Append-only versions via `valid_from` / `valid_to`. |
| Provider | `providers` | Supplier metadata only; availability is out of scope. |
| Public listing | `public_listings` | 1:1 with `products`. Placement `catalog` / `lodging` / `yacht`. Showcase price ≠ tariff. |
| Public category | `public_categories` | Site filters (not ops `categories`). Eight protected seeds. |
| Public image | `public_images` | Cover / gallery; Storage path XOR external ref. Bucket `catalog-media`. |
| Guest review | `guest_reviews` | Lodging only. |
| Public site | `public_sites` | `source` `legacy` → `panel` via cutover. |
| Cutover item | `public_cutover_items` | Manifesto of slugs that must be published before cutover. |

## Public listings (009)

- One public ficha per product. Editing `display_price` **never** calls `upsert_pricing_scheme`.
- `public_slug` and `placement` are immutable after `first_published_at`.
- Images: JPEG/PNG/WebP ≤ 10 MB in `catalog-media`, or an `external_ref` copied from the legacy site.
- Yates = `experience` + `placement = yacht` (no new `product_type`).
- Angular: the product editor sections include the public ficha; `/cms/settings/public-categories`; `/cms/settings/cutover` (admin).
- Agents: read-only in the UI (`hasRoleAtLeast(…, 'operator')` gates writes). RLS still rejects agent writes.

### Public RPCs

| RPC | Who | Behavior |
| --- | --- | --- |
| `save_public_listing` | Operator / Admin | Upsert draft/published ficha. Slug/placement rules, bilingual pairs, showcase price. |
| `publish_public_listing` | Operator / Admin | Requires complete ficha, cover, `active` product, valid tariff. |
| `unpublish_public_listing` | Operator / Admin | Hides from public projection; keeps product/tariff. |
| `set_public_listing_sold_out` | Operator / Admin | Only while published. Does not change product status or tariff. |
| `attach_public_image` | Operator / Admin | Cover or gallery; replaces cover with audit. |
| `reorder_public_gallery` | Operator / Admin | Lodging gallery order. |
| `save_guest_review` | Operator / Admin | Lodging reviews. |
| `save_public_category` | Operator / Admin | Upsert; `CATEGORY_IN_USE` if deactivating a category still on published listings. |
| `complete_public_cutover` | **Admin only** | Switches `public_sites.source` to `panel` when manifesto is complete. |
| `get_public_site(organization_id)` | `anon` / authenticated | Empty arrays while `legacy`; Offer/Lodging/Yacht projection when `panel`. Authenticated callers are limited to their JWT org. |

## RPCs

| RPC | Who | Behavior |
| --- | --- | --- |
| `create_product` | Operator / Admin | Atomic product + subtype in `draft`. |
| `set_product_status` | Operator / Admin | Activate only with a current tariff (`PRODUCT_HAS_NO_VALID_PRICE`). Emits `product_activated` / `product_deactivated`. |
| `create_package` | Operator / Admin | Draft package + itinerary. `PACKAGE_NESTING_NOT_ALLOWED`; cross-org components are `VALIDATION_ERROR`. |
| `get_package_consistency` | Authenticated (RLS) | Warns when components are `inactive`. Never auto-deactivates the package. |
| `upsert_pricing_scheme` | Operator / Admin | Append-only versioning. `SEASON_OVERLAP`, `INVALID_SEASON_RANGE`, `INVALID_PRICE_TARGET`. |
| `apply_price_override` | **Admin only** | Versions the current tariff and writes `audit.audit_events` (`price_overridden`). |
| `resolve_price(product_id, on_date, charge_type)` | Authenticated (RLS) | Deterministic: seasonal match wins over base among versions covering the date (SC-003). |

Mutating RPCs are `SECURITY DEFINER` and call `require_catalog_manager()` or `require_tenant_admin()`. Those helpers read `organization_id` / `app_role` from `auth.jwt()` **and** the live `user_profiles` row. Clients never pass role or tenant as an authorization argument.

## RBAC

| Action | Agent | Operator | Admin |
| --- | --- | --- | --- |
| Read catalog (tables + `resolve_price`) | Yes (own org) | Yes | Yes |
| Manage products, packages, add-ons, categories | No | Yes | Yes |
| Define / version tariffs (`upsert_pricing_scheme`) | No | Yes | Yes |
| Manual price override (`apply_price_override`) | No | No | Yes |
| Read public listings / categories / cutover status | Yes (own org) | Yes | Yes |
| Save / publish / images / sold out / public categories | No | Yes | Yes |
| Complete public cutover (`complete_public_cutover`) | No | No | Yes |

Angular `roleGuard('operator')` only hides routes. PostgreSQL RLS is the authorization boundary.

## Pricing and versioning

- A product cannot become `active` without a current `pricing_schemes` row (`valid_to IS NULL`).
- Changing a tariff never `UPDATE`s `base_amount`. The current row is closed (`valid_to = now()`) and a new row is inserted (`enforce_pricing_scheme_append_only`).
- Overlapping current seasons for the same target and `charge_type` are rejected (`EXCLUDE USING gist`).
- Package price is explicit on the package product, independent of component tariffs.
- Historical versions keep their amounts so later catalog changes cannot rewrite issued quotes (SC-002; quotes themselves are feature 005).

## Security invariants (do not regress)

- Every catalog table has RLS enabled. `anon` is revoked. Unmatched operations are Default Deny.
- SELECT/INSERT/UPDATE policies compare `organization_id` to `auth.jwt() ->> 'organization_id'` and writes require `app_role IN ('operator','admin')`.
- Subtype and join tables denormalize `organization_id` so RLS does not depend on a join, and composite FKs pin both sides to one tenant.
- `apply_price_override` uses `require_tenant_admin()` (JWT + live admin profile).
- Direct PostgREST inserts of `organization_id` from the Angular session are still checked by RLS `WITH CHECK`; a mismatched tenant is rejected.

## Local commands

```bash
npm install
npm start                          # Angular on http://127.0.0.1:4200
./supabase/tests/run-sql-tests.sh  # PostgreSQL 17 harness (Docker)
ng build
```

## Admin layout (010)

The CMS lives under `/cms`. Old `/catalog/**` paths redirect.

| Path | Min role | Screen |
| --- | --- | --- |
| `/cms/experiences` | agent | Experience list, including yachts (`placement`) |
| `/cms/experiences/new` and `/:id` | operator to create; agent reads `/:id` | Sectioned editor + live preview |
| `/cms/accommodations` | agent | Accommodation list |
| `/cms/accommodations/new` and `/:id` | operator to create; agent reads `/:id` | Same editor, lodging sections |
| `/cms/packages` | agent | Package list |
| `/cms/packages/new` and `/:id` | operator to create; agent reads `/:id` | Package builder + preview |
| `/cms/settings` | operator | Categories, public categories, add-ons |
| `/cms/settings/cutover` | admin | Publicación del sitio |

Lists show 20 rows and keep filters in the query string. Agents do not see create, save, or
publish actions. `/catalog/products/:id` still opens the experience editor, which redirects
when the product is an accommodation or a package.

## Contenido público multiagencia (016)

Each agency owns its public configuration; nothing is shared between agencies and nothing is
fixed to CTT any more. Screens live under **CMS › Ajustes del catálogo › Sitio público**.

| What | Table / RPCs | Who manages it |
| --- | --- | --- |
| Public categories | `public_categories`; `save_public_category`, `delete_public_category` | Operator, Admin |
| Lodging types and amenities | `public_taxonomy_values` (kind `lodging_type` / `amenity`); `list_/save_/delete_public_taxonomy_value` | Operator, Admin |
| Public profile (name, logo, color, contact, networks, languages, currency) | `public_profiles`; `get_public_profile`, `save_public_profile` | Operator, Admin |
| Public access key | `public_access_keys`; `generate_/revoke_/list_public_access_keys` | Admin only |
| Source policy (migration vs direct publication, CTT transition) | `public_source_config`; `set_public_source_migration`, `end_organization_identifier_transition`, `complete_public_cutover` | Admin only |

Rules worth knowing:

- **New agency defaults** (trigger on `organizations`): seven editable example categories
  (`tours`, `playa`, `aventura`, `cultural`, `gastronomia`, `naturaleza`, `premium`), five lodging
  types (incl. `hotel`), ten amenities (incl. `sea_view`), a profile from the agency name and
  `settings.default_currency`, and `migration_required = false`.
- **Used values**: a category, type or amenity used by a listing can be deactivated but not
  deleted (`CATEGORY_IN_USE`, `TAXONOMY_VALUE_IN_USE`). A listing keeps a deactivated value it
  already had; a deactivated value cannot be newly assigned (`TAXONOMY_VALUE_INACTIVE`), and a code
  from another agency is rejected (`TAXONOMY_VALUE_INVALID`) by the `public_listings` trigger.
  The public projection still labels inactive values that a published listing shows.
- **Protected categories**: only an agency migrating CTT's site has them (the eight CTT
  identifiers). They can be renamed or deactivated, never deleted (`CATEGORY_PROTECTED`).
- **Keys**: `pk_` + 48 hex chars, shown once. Only the SHA-256 fingerprint and an 11-char prefix
  are stored. Regenerating leaves the previous key valid for exactly **7 days**; revoking is
  immediate, also during that grace period. Audit records actor and key id, never the key.
- **Direct publication vs migration**: a migration-free agency's published listings are public at
  once (`build_public_catalog` reports `source: panel`). A migrating agency shows the «preparing»
  state until `complete_public_cutover` passes the manifest gate (`public_cutover_items`).

## Sitio público externo (vitrinas)

Traveler-facing websites are separate apps (CTT's is **https://www.cartagenatailoredtravel.com/**).
This repository owns the admin panel and the Supabase contract they consume
(`specs/016-multiagency-public-cms/contracts/public-consumer.md`):

| Step | Showcase calls (anon key, **no user session**) | Notes |
| --- | --- | --- |
| Read profile + catalog | `get_public_site_by_key(p_key)` → `{ profile, catalog }` | `catalog` = `source`, `offers`, `lodgings`, `yachts`, `categories`, `lodgingTypes`, `amenities` |
| Send a traveler request | `submit_public_request_by_key(p_key, payload)` | Same payload and errors as 003; lands in `/sales/requests` (channel `web`) |
| CTT only, during its transition | `get_public_site(organization_id)`, `submit_public_request(organization_id, payload)` | Accepted until `public_source_config.organization_identifier_until` (90 days from migration 059, or earlier if an admin closes it). Never available to other agencies. |

- Every invalid, unknown, expired or revoked key — and the organization identifier outside the
  transition — gets the same error, `PUBLIC_ACCESS_UNAVAILABLE` (SQLSTATE `42501`), so a caller
  cannot tell whether an agency exists.
- The projection contains only published listings of active products plus the configured
  profile fields; empty profile fields are omitted. No ids, users, customers, notes, providers,
  costs or tariffs.
- A signed-in panel user calling `get_public_site` always gets their own agency (preview).
- `parsePublicSite` (`core/catalog/models/public-site-projection.ts`) is the typed reading of
  the catalog part used by this app. Sold out never accepts requests.
- Known gaps in the projection: offers and yachts expose only a cover (no gallery); offer
  `location`, `meetingPoint`, `schedule` and `duration` exist only in Spanish.

## Blog (013)

Each agency writes, publishes, edits and retires its blog articles in the panel (`/cms/blog`). The site connected to the agency reads only what is published. Decision record: [ADR-0004](../adr/0004-blog-authoring-in-panel.md). Spec: `specs/013-editorial-content/`.

| Entity | Table | Notes |
| --- | --- | --- |
| Article | `blog_articles` | Slug unique per agency, fixed from the first publication. `status` draft / published / retired. `revision` for optimistic concurrency. |
| Content | `blog_article_contents` | At most two rows per article: `published` (what the site reads) and `working` (draft or pending revision, never public). Bilingual `*_es` / `*_en`. |
| Blog source | `public_blog_source`, `public_blog_cutover_items` | Migration from a previous blog (WordPress): manifest of slugs and source switch. |

**Body.** The body is a JSON block document (`paragraph`, `heading` 2|3, `list`, `quote`, `image`) with inline `bold`, `italic` and `href` (http, https, mailto). `blog_normalize_body` drops anything else on save, so no HTML or script reaches a site. Images live in `catalog-media` under `{org}/blog/{article}/`. Only migrated articles may reference `https` images on the old blog.

**Publishing.** Publishing (and publishing changes) requires the slug, the cover and, for every language the agency offers in its public profile, the title, summary, cover alt text, a non-empty body and an alt text (or the decorative mark) on each image. The error is `PUBLISH_INCOMPLETE`, with `[{field, locale}]` in `DETAIL`.

| RPC | Who | Behavior |
| --- | --- | --- |
| `list_blog_articles`, `get_blog_article` | Operator / Admin | Panel reads. Another agency's id is `NOT_FOUND`. |
| `save_blog_article` | Operator / Admin | Creates a draft (a title is enough) or writes the working content. Requires `expectedRevision` (`ARTICLE_CONFLICT`). |
| `publish_blog_article`, `publish_blog_article_changes`, `discard_blog_article_changes` | Operator / Admin | Draft → published; pending revision → published; drop the revision. |
| `retire_blog_article`, `republish_blog_article`, `delete_blog_article` | Operator / Admin | Retire and republish keep the slug and date. Only a never-published draft can be deleted. |
| `get_blog_source`, `set_blog_migration_required`, `replace_blog_cutover_manifest`, `complete_blog_cutover` | Admin | Migration. The cutover fails with `BLOG_CUTOVER_INCOMPLETE` while a manifest slug has no published article. |
| `get_public_blog_by_key`, `get_public_blog_article_by_key` | `anon` | Public read for the agency of the key. |
| `get_public_blog`, `get_public_blog_article` | `anon` (CTT transition), authenticated (own agency preview) | Same answer as the `_by_key` variants. |

**Public read contract.** See `specs/013-editorial-content/contracts/public-consumer.md`.
- The list is paginated (12 by default, at most 50) and sorted by first publication date, newest first.
- Only the languages the agency offers now are returned. SEO fields fall back to the title and summary.
- A draft, retired, unknown or other-agency slug returns `{"found": false}`.
- While a migration is open the read answers `source: "legacy"` with no articles, so the site keeps its old blog.
- There is no server cache. A site that caches must drop its copy within 300 s, so that changes show in 5 minutes or less.
- The blog is read separately from `get_public_site`, so a blog failure does not affect the catalog.

**Security invariants.**
- RLS limits `SELECT` to Operator and Admin of the same agency; Agent sees nothing.
- No API role can write the tables directly. `anon` has no table access.
- Audit events (`blog_article_*`, `blog_source_changed`, `blog_cutover_manifest_changed`) carry only article id, slug and locales, never titles or bodies.

SQL suites: `blog_articles_test.sql`, `blog_isolation_test.sql`, `blog_public_read_test.sql`, `blog_cutover_test.sql`.

## Traducción del blog (017)

Spec: `specs/017-blog-translation/` · ADR: `docs/adr/0005-self-hosted-machine-translation.md`.

- **Qué hace**: en el editor del blog, la pestaña de un idioma tiene «Traducir desde Español/Inglés». Rellena título, resumen, contenido, textos alternativos y SEO como edición **sin guardar**, con aviso y «Deshacer traducción». Si el destino ya tiene texto pregunta: rellenar vacíos, reemplazar todo o cancelar. Nunca guarda, publica ni toca el slug.
- **Motor**: LibreTranslate propio (sin IA generativa, sin terceros, sin coste por uso). Local: `docker compose -f docker/libretranslate/compose.yml up -d` (puerto 5050, modelos es↔en).
- **Camino**: panel → Edge Function `translate-blog` (`verify_jwt = true`) → RPC `consume_blog_translation_quota(p_characters)` (Operador/Administrador; 150.000 caracteres por agencia y hora; migración 072) → `LIBRETRANSLATE_URL`. El navegador nunca llama al traductor.
- **Formato**: cada texto viaja como HTML mínimo (`<b>`, `<i>`, `<a id="N">`); las URLs de los enlaces no se envían. Si vuelven las marcas cambiadas, ese texto se retraduce fragmento por fragmento (`blog-translation.ts`).
- **Partes**: hasta 40 textos y 5.000 caracteres por solicitud, en serie, con progreso. En un Mac Intel con Docker el traductor tarda ~2 s por frase (research R9).
- **Configuración**: `supabase/functions/.env` (copiar de `.env.example`) para `supabase functions serve`. En producción, sin `LIBRETRANSLATE_URL` la función responde `TRANSLATION_UNAVAILABLE` y el panel sigue funcionando a mano. El alojamiento de producción está pendiente.
- **Privacidad**: la tabla de uso solo guarda caracteres por hora; la función registra código, número de textos y duración, nunca el texto.
- **Pruebas**: `supabase/tests/blog_translation_quota_test.sql`, `blog-translation.spec.ts`, `blog.service.spec.ts`, `blog-editor.component.spec.ts`.

## Quickstart mapping (T043)

See `specs/002-catalog-pricing/quickstart.md`. Automated coverage:

| Scenario | Evidence |
| --- | --- |
| 1. Alta experiencia / alojamiento | `create_product` in `catalog_rls_test.sql` / `package_composition_test.sql`. UI create flow needs a browser. |
| 2. Activar sin precio | `catalog_rls_test.sql` (`PRODUCT_HAS_NO_VALID_PRICE`). |
| 3. Temporada + anti-solapamiento | `pricing_rules_test.sql` (`resolve_price`, `SEASON_OVERLAP`). |
| 4. No-retroactividad | `price_freeze_test.sql`. |
| 5. Override auditado | `pricing_rules_test.sql` (`price_overridden`; operator/agent denied). |
| 6. Paquete + inconsistencia | `package_composition_test.sql`. |
| 7. Aislamiento multi-tenant | `catalog_rls_test.sql`, `catalog_security_review_test.sql`. |
| 8. Add-ons + reglas | `catalog_security_review_test.sql` (link + isolation). UI form needs a browser. |

SC-001 (register a full product in under 5 minutes) is a UX timing criterion and is **not** claimed from SQL. SC-004 list latency is probed in `catalog_performance_probe_test.sql` against a local Postgres 17 container, not a deployed Supabase project.
