# Catalog & Pricing (002-catalog-pricing)

Module that owns the internal tourism catalog (experiences, accommodations, predefined
packages, add-ons) and versioned tariff schemes. Tenant isolation, JWT claims, and the
audit trail are inherited from Identity & Access.

**Spec**: `specs/002-catalog-pricing/`
**Plan**: `specs/002-catalog-pricing/plan.md`

## What lives where

| Concern | Location |
| --- | --- |
| Schema, RLS, RPCs, triggers | `supabase/migrations/011_create_catalog_enums.sql` … `021_us3_packages.sql` |
| SQL verification (RLS, prices, freeze, packages, perf, security) | `supabase/tests/` |
| Domain models | `src/app/core/catalog/models/` |
| Product / category / add-on / pricing services | `src/app/core/catalog/services/` |
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

Catalog routes (Operator/Admin): `/catalog`, `/catalog/products`, `/catalog/packages`, `/catalog/addons`. Pricing is edited on the product detail screen.

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
