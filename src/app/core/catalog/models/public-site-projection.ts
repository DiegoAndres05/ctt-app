/**
 * Typed shape of the `get_public_site` projection (feature 009).
 *
 * The Cartagena Tailored Travel website is the consumer of this JSON; this app only reads it
 * for the cutover screen. Field names follow the camelCase JSON built by
 * `supabase/migrations/025_public_site_read.sql`. That function uses `jsonb_strip_nulls`, so
 * every optional field can be missing. `parsePublicSite` turns the raw RPC payload into
 * these types without trusting it: wrong types become empty values, entries without a slug
 * are dropped. The JSON returned by 009 is not changed.
 */

import type { PublicSource } from './public-listing.model';

/** Experience / tour (`offers`, placement `catalog`). */
export interface PublicOffer {
  id: string;
  name: string;
  nameEn: string;
  category: string | null;
  description: string;
  descriptionEn: string;
  image: string | null;
  includes: string[];
  includesEn: string[];
  warnings: string[];
  warningsEn: string[];
  /** Spanish-only free text in 009 (no English column). */
  meetingPoint: string | null;
  schedule: string | null;
  duration: string | null;
  location: string | null;
  maxGuests: number | null;
  featured: boolean;
  price: number | null;
  originalPrice: number | null;
  currency: string | null;
  soldOut: boolean;
  acceptsRequests: boolean;
}

/** Lodging (`lodgings`, placement `lodging`). */
export interface PublicLodging {
  id: string;
  name: string;
  nameEn: string;
  type: string | null;
  location: string;
  locationEn: string;
  neighborhood: string;
  neighborhoodEn: string;
  description: string;
  descriptionEn: string;
  pricePerNight: number | null;
  currency: string | null;
  maxGuests: number | null;
  bedrooms: number | null;
  bathrooms: number | null;
  image: string | null;
  gallery: string[];
  amenities: string[];
  mapUrl: string | null;
  featured: boolean;
  soldOut: boolean;
  acceptsRequests: boolean;
}

export interface PublicYachtLine {
  icon: string | null;
  text: string;
  textEn: string;
}

/** Yacht (`yachts`, placement `yacht`). */
export interface PublicYacht {
  id: string;
  name: string;
  nameEn: string;
  description: string;
  descriptionEn: string;
  image: string | null;
  capacity: PublicYachtLine[];
  features: PublicYachtLine[];
  price: number | null;
  currency: string | null;
  soldOut: boolean;
  acceptsRequests: boolean;
}

export interface PublicCatalog {
  /** `legacy` means the agency has not switched the showcase on: show «preparing» (FR-007). */
  source: PublicSource;
  offers: PublicOffer[];
  lodgings: PublicLodging[];
  yachts: PublicYacht[];
}

export const EMPTY_PUBLIC_CATALOG: PublicCatalog = {
  source: 'legacy',
  offers: [],
  lodgings: [],
  yachts: [],
};

type Raw = Record<string, unknown>;

function isRecord(value: unknown): value is Raw {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function str(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function optStr(value: unknown): string | null {
  return str(value) || null;
}

function num(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value))) {
    return Number(value);
  }
  return null;
}

function strList(value: unknown): string[] {
  return Array.isArray(value) ? value.map(str).filter((entry) => entry.length > 0) : [];
}

function records(value: unknown): Raw[] {
  return Array.isArray(value) ? value.filter(isRecord) : [];
}

/** Sold out is explicit; requests are accepted only when the RPC says so and it is not sold out. */
function requestFlags(row: Raw): { soldOut: boolean; acceptsRequests: boolean } {
  const soldOut = row['soldOut'] === true;
  return { soldOut, acceptsRequests: !soldOut && row['acceptsRequests'] === true };
}

function toOffer(row: Raw): PublicOffer {
  return {
    id: str(row['id']),
    name: str(row['name']),
    nameEn: str(row['nameEn']),
    category: optStr(row['category']),
    description: str(row['description']),
    descriptionEn: str(row['descriptionEn']),
    image: optStr(row['image']),
    includes: strList(row['includes']),
    includesEn: strList(row['includesEn']),
    warnings: strList(row['warnings']),
    warningsEn: strList(row['warningsEn']),
    meetingPoint: optStr(row['meetingPoint']),
    schedule: optStr(row['schedule']),
    duration: optStr(row['duration']),
    location: optStr(row['location']),
    maxGuests: num(row['maxGuests']),
    featured: row['featured'] === true,
    price: num(row['price']),
    originalPrice: num(row['originalPrice']),
    currency: optStr(row['currency']),
    ...requestFlags(row),
  };
}

function toLodging(row: Raw): PublicLodging {
  return {
    id: str(row['id']),
    name: str(row['name']),
    nameEn: str(row['nameEn']),
    type: optStr(row['type']),
    location: str(row['location']),
    locationEn: str(row['locationEn']),
    neighborhood: str(row['neighborhood']),
    neighborhoodEn: str(row['neighborhoodEn']),
    description: str(row['description']),
    descriptionEn: str(row['descriptionEn']),
    pricePerNight: num(row['pricePerNight']),
    currency: optStr(row['currency']),
    maxGuests: num(row['maxGuests']),
    bedrooms: num(row['bedrooms']),
    bathrooms: num(row['bathrooms']),
    image: optStr(row['image']),
    gallery: strList(row['gallery']),
    amenities: strList(row['amenities']),
    mapUrl: optStr(row['mapUrl']),
    featured: row['featured'] === true,
    ...requestFlags(row),
  };
}

function toYachtLines(value: unknown): PublicYachtLine[] {
  return records(value)
    .map((line) => ({
      icon: optStr(line['icon']),
      text: str(line['text']),
      textEn: str(line['textEn']),
    }))
    .filter((line) => line.text.length > 0 || line.textEn.length > 0);
}

function toYacht(row: Raw): PublicYacht {
  return {
    id: str(row['id']),
    name: str(row['name']),
    nameEn: str(row['nameEn']),
    description: str(row['description']),
    descriptionEn: str(row['descriptionEn']),
    image: optStr(row['image']),
    capacity: toYachtLines(row['capacity']),
    features: toYachtLines(row['features']),
    price: num(row['price']),
    currency: optStr(row['currency']),
    ...requestFlags(row),
  };
}

function withSlug<T extends { id: string }>(items: T[]): T[] {
  return items.filter((item) => item.id.length > 0);
}

/**
 * Normalizes the raw `get_public_site` payload.
 *
 * Anything other than `source: 'panel'` is the «preparing» state and carries no listings,
 * so a half-configured showcase never leaks partial cards (FR-007).
 */
export function parsePublicSite(raw: unknown): PublicCatalog {
  if (!isRecord(raw) || raw['source'] !== 'panel') {
    return EMPTY_PUBLIC_CATALOG;
  }
  return {
    source: 'panel',
    offers: withSlug(records(raw['offers']).map(toOffer)),
    lodgings: withSlug(records(raw['lodgings']).map(toLodging)),
    yachts: withSlug(records(raw['yachts']).map(toYacht)),
  };
}
