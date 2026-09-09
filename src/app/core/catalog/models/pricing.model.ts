/**
 * Pricing scheme domain types.
 *
 * Row shapes mirror `public.pricing_schemes` column-for-column. Versioning is append-only:
 * a tariff change closes the current row (`valid_to`) and inserts a new one.
 */

/** Mirrors the `public.charge_type` enum. */
export type ChargeType = 'per_person' | 'per_night' | 'per_group';

/** Whether `resolve_price` selected a seasonal scheme or the unseasoned base tariff. */
export type PriceSource = 'season' | 'base';

/** A row of `public.pricing_schemes`. Exactly one of `product_id` / `addon_id` is set. */
export interface PricingScheme {
  id: string;
  organization_id: string;
  product_id: string | null;
  addon_id: string | null;
  currency: string;
  base_amount: number;
  charge_type: ChargeType;
  season_start: string | null;
  season_end: string | null;
  valid_from: string;
  valid_to: string | null;
  created_at: string;
}

/** Result of `public.resolve_price(product_id, on_date, charge_type)`. */
export interface ResolvedPrice {
  currency: string;
  amount: number;
  source: PriceSource;
}
