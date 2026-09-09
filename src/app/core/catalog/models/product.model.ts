/**
 * Catalog product domain types.
 *
 * Row shapes mirror `public.products` and the 1:1 subtype tables column-for-column, including
 * snake_case naming, so PostgREST payloads can be consumed without a translation layer.
 */

/** Mirrors the `public.product_type` enum. */
export type ProductType = 'experience' | 'accommodation' | 'package';

/** Mirrors the `public.product_status` enum. */
export type ProductStatus = 'draft' | 'active' | 'inactive';

/** Mirrors the `public.experience_difficulty` enum. */
export type ExperienceDifficulty = 'easy' | 'moderate' | 'hard';

/** A row of `public.products`. */
export interface Product {
  id: string;
  organization_id: string;
  provider_id: string | null;
  type: ProductType;
  name: string;
  description: string | null;
  status: ProductStatus;
  created_at: string;
  updated_at: string;
}

/** A row of `public.experiences` (PK shared with `products`). */
export interface Experience {
  id: string;
  organization_id: string;
  duration_minutes: number;
  difficulty: ExperienceDifficulty | null;
  meeting_point: string | null;
  min_capacity: number;
  max_capacity: number;
}

/** A row of `public.accommodations` (PK shared with `products`). */
export interface Accommodation {
  id: string;
  organization_id: string;
  property_type: string;
  location: string;
  check_in: string | null;
  check_out: string | null;
  max_occupancy: number;
  occupancy_rules: Record<string, unknown> | null;
}

/** A row of `public.packages` (PK shared with `products`). */
export interface Package {
  id: string;
  organization_id: string;
  total_days: number | null;
  total_nights: number | null;
}

/** A row of `public.package_items`. `organization_id` is denormalized for RLS. */
export interface PackageItem {
  id: string;
  package_id: string;
  component_product_id: string;
  organization_id: string;
  sort_order: number;
  day_number: number | null;
}

/** Inactive component reported by `get_package_consistency` (warning only). */
export interface PackageInactiveComponent {
  product_id: string;
  name: string;
  status: ProductStatus;
  type: ProductType;
}

/** One package entry from `get_package_consistency`. */
export interface PackageConsistency {
  package_id: string;
  package_name: string;
  package_status: ProductStatus;
  consistent: boolean;
  inactive_components: PackageInactiveComponent[];
}

/** A row of `public.providers`. */
export interface Provider {
  id: string;
  organization_id: string;
  name: string;
  contact_email: string | null;
  contact_phone: string | null;
  metadata: Record<string, unknown> | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}
