/**
 * Category / taxonomy domain types.
 *
 * Row shapes mirror `public.categories` and `public.product_categories` column-for-column.
 */

/** A row of `public.categories`. Organization-scoped, optionally hierarchical via `parent_id`. */
export interface Category {
  id: string;
  organization_id: string;
  parent_id: string | null;
  name: string;
  slug: string;
  created_at: string;
  updated_at: string;
}

/** A row of `public.product_categories` (N:M). */
export interface ProductCategory {
  product_id: string;
  category_id: string;
  organization_id: string;
}
