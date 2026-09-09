/**
 * Add-on / complement domain types.
 *
 * Row shapes mirror `public.add_ons` and `public.product_addons` column-for-column. Tables
 * arrive with US2; the types exist so catalog services can be typed against the data model.
 */

/** Mirrors the `public.addon_unit` enum. */
export type AddonUnit = 'per_person' | 'per_unit' | 'per_service';

/** A row of `public.add_ons`. */
export interface Addon {
  id: string;
  organization_id: string;
  name: string;
  description: string | null;
  unit: AddonUnit;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

/** A row of `public.product_addons` (eligibility + applicability rules). */
export interface ProductAddon {
  id: string;
  product_id: string;
  addon_id: string;
  organization_id: string;
  is_mandatory: boolean;
  max_quantity: number | null;
}

/** Eligibility row with the linked add-on payload from PostgREST embeds. */
export interface ProductAddonWithAddon extends ProductAddon {
  add_ons: Addon | null;
}
