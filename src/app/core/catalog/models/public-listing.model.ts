/**
 * Public catalog listing types (feature 009).
 *
 * Row shapes mirror `public_listings`, `public_categories`, `public_images`,
 * `guest_reviews`, `public_sites`, and `public_cutover_items` column-for-column
 * (snake_case). Payload helpers for RPCs use the same keys the SQL reads.
 */

/** Mirrors `public.public_placement`. */
export type PublicPlacement = 'catalog' | 'lodging' | 'yacht';

/** Mirrors `public.public_listing_status`. */
export type PublicListingStatus = 'draft' | 'published' | 'unpublished';

/** Mirrors `public.public_source`. */
export type PublicSource = 'legacy' | 'panel';

/** Mirrors `public.public_image_role`. */
export type PublicImageRole = 'cover' | 'gallery';

/** Mirrors `public.lodging_type`. */
export type LodgingType = 'casa' | 'apartamento' | 'finca' | 'habitacion';

/** Mirrors `public.yacht_icon`. */
export type YachtIcon =
  | 'people'
  | 'bed'
  | 'shower'
  | 'droplet'
  | 'armchair'
  | 'boat'
  | 'kitchen'
  | 'star'
  | 'snow'
  | 'users'
  | 'sun'
  | 'music'
  | 'map';

/** Mirrors `public.lodging_amenity`. */
export type LodgingAmenity =
  'wifi' | 'pool' | 'ac' | 'kitchen' | 'parking' | 'terrace' | 'washer' | 'tv' | 'bbq';

/** Bilingual pair stored in JSONB arrays (`includes`, `warnings`). */
export interface BilingualPair {
  es: string;
  en: string;
}

/** Yacht capacity/feature line stored in `yacht_lines` JSONB. */
export interface YachtLine {
  kind: 'capacity' | 'feature';
  position: number;
  icon?: YachtIcon | null;
  text_es: string;
  text_en: string;
}

/** Lodging details embedded in `public_listings.lodging`. */
export interface LodgingDetails {
  lodging_type: LodgingType;
  location_es: string;
  location_en: string;
  neighborhood_es: string;
  neighborhood_en: string;
  bedrooms: number;
  bathrooms: number;
  amenities: LodgingAmenity[];
  tags: string[];
  map_url?: string | null;
}

/** A row of `public.public_listings`. */
export interface PublicListing {
  id: string;
  organization_id: string;
  product_id: string;
  placement: PublicPlacement;
  public_slug: string;
  status: PublicListingStatus;
  sold_out: boolean;
  name_es: string | null;
  name_en: string | null;
  description_es: string | null;
  description_en: string | null;
  cover_image_ref: string | null;
  public_category_id: string | null;
  location: string | null;
  meeting_point: string | null;
  schedule: string | null;
  duration: string | null;
  max_guests: number | null;
  featured: boolean;
  rating: number | null;
  display_price: number | null;
  original_price: number | null;
  currency: string | null;
  includes: BilingualPair[];
  warnings: BilingualPair[];
  lodging: LodgingDetails | null;
  yacht_lines: YachtLine[];
  first_published_at: string | null;
  published_at: string | null;
  created_at: string;
  updated_at: string;
}

/** A row of `public.public_categories`. */
export interface PublicCategory {
  id: string;
  organization_id: string;
  name_es: string;
  name_en: string;
  is_active: boolean;
  protected: boolean;
  created_at: string;
  updated_at: string;
}

/** A row of `public.public_images` (active or replaced). */
export interface PublicImage {
  id: string;
  organization_id: string;
  listing_id: string;
  role: PublicImageRole;
  sort_order: number;
  storage_path: string | null;
  external_ref: string | null;
  replaced_at: string | null;
  created_at: string;
}

/** A row of `public.guest_reviews`. */
export interface GuestReview {
  id: string;
  organization_id: string;
  listing_id: string;
  author: string;
  rating: number;
  text_es: string;
  text_en: string;
  reviewed_on: string;
  created_at: string;
}

/** A row of `public.public_sites`. */
export interface PublicSite {
  organization_id: string;
  source: PublicSource;
  cutover_completed_at: string | null;
  cutover_completed_by: string | null;
  created_at: string;
  updated_at: string;
}

/** A row of `public.public_cutover_items`. */
export interface PublicCutoverItem {
  organization_id: string;
  public_slug: string;
  placement: PublicPlacement;
  listing_id: string | null;
  created_at: string;
}

/** Payload keys for `save_public_listing(p_payload jsonb)`. */
export interface SavePublicListingPayload {
  product_id: string;
  placement: PublicPlacement;
  public_slug: string;
  name_es?: string | null;
  name_en?: string | null;
  description_es?: string | null;
  description_en?: string | null;
  public_category_id?: string | null;
  location?: string | null;
  meeting_point?: string | null;
  schedule?: string | null;
  duration?: string | null;
  max_guests?: number | null;
  featured?: boolean;
  rating?: number | null;
  display_price?: number | null;
  original_price?: number | null;
  currency?: string | null;
  includes?: BilingualPair[];
  warnings?: BilingualPair[];
  lodging?: LodgingDetails | null;
  yacht_lines?: YachtLine[];
}

export interface SavedPublicListing {
  id: string;
  status: PublicListingStatus;
}

export interface PublishPublicListingResult {
  status: 'published';
  first_published_at: string;
}

export interface UnpublishPublicListingResult {
  status: 'unpublished';
}

export interface AttachPublicImageResult {
  id: string;
  role: PublicImageRole;
  ref: string;
}

export interface SaveGuestReviewPayload {
  listing_id: string;
  review_id?: string | null;
  author: string;
  text_es: string;
  text_en: string;
  rating: number;
  reviewed_on: string;
}

export interface SavePublicCategoryPayload {
  id: string;
  name_es: string;
  name_en: string;
  is_active?: boolean;
}

export interface CutoverStatus {
  site: PublicSite | null;
  items: PublicCutoverItem[];
  missing_slugs: string[];
}

/** Projection returned by `get_public_site` (consumer-facing camelCase). */
export interface PublicSiteProjection {
  source: PublicSource;
  offers: unknown[];
  lodgings: unknown[];
  yachts: unknown[];
}

export const LODGING_AMENITIES: readonly LodgingAmenity[] = [
  'wifi',
  'pool',
  'ac',
  'kitchen',
  'parking',
  'terrace',
  'washer',
  'tv',
  'bbq',
] as const;

export const YACHT_ICONS: readonly YachtIcon[] = [
  'people',
  'bed',
  'shower',
  'droplet',
  'armchair',
  'boat',
  'kitchen',
  'star',
  'snow',
  'users',
  'sun',
  'music',
  'map',
] as const;

export const LODGING_TYPES: readonly LodgingType[] = [
  'casa',
  'apartamento',
  'finca',
  'habitacion',
] as const;
