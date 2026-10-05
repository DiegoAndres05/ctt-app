import {
  YACHT_ICONS,
  type BilingualPair,
  type LodgingAmenity,
  type LodgingDetails,
  type LodgingType,
  type PublicListing,
  type PublicPlacement,
  type SavePublicListingPayload,
  type YachtIcon,
  type YachtLine,
} from '../../../../core/catalog/models/public-listing.model';
import type { ProductType } from '../../../../core/catalog/models/product.model';

/** Editable public-listing fields. Mirrors the 009 ficha without a new table. */
export interface PublicDraft {
  placement: PublicPlacement;
  publicSlug: string;
  nameEs: string;
  nameEn: string;
  descriptionEs: string;
  descriptionEn: string;
  featured: boolean;
  publicCategoryId: string;
  location: string;
  meetingPoint: string;
  schedule: string;
  duration: string;
  displayPrice: string;
  originalPrice: string;
  currency: string;
  rating: string;
  includesText: string;
  warningsText: string;
  lodgingType: LodgingType;
  locationEs: string;
  locationEn: string;
  neighborhoodEs: string;
  neighborhoodEn: string;
  bedrooms: number;
  bathrooms: number;
  maxGuests: number;
  mapUrl: string;
  tagsText: string;
  yachtLinesText: string;
}

export function defaultPlacement(type: ProductType): PublicPlacement {
  if (type === 'accommodation') {
    return 'lodging';
  }
  return 'catalog';
}

export function emptyPublicDraft(placement: PublicPlacement): PublicDraft {
  return {
    placement,
    publicSlug: '',
    nameEs: '',
    nameEn: '',
    descriptionEs: '',
    descriptionEn: '',
    featured: false,
    publicCategoryId: '',
    location: '',
    meetingPoint: '',
    schedule: '',
    duration: '',
    displayPrice: '',
    originalPrice: '',
    currency: 'COP',
    rating: '',
    includesText: '',
    warningsText: '',
    lodgingType: 'casa',
    locationEs: '',
    locationEn: '',
    neighborhoodEs: '',
    neighborhoodEn: '',
    bedrooms: 0,
    bathrooms: 0,
    maxGuests: 2,
    mapUrl: '',
    tagsText: '',
    yachtLinesText: '',
  };
}

export function draftFromListing(
  listing: PublicListing | null,
  productType: ProductType,
): { draft: PublicDraft; amenities: LodgingAmenity[] } {
  const placement = listing?.placement ?? defaultPlacement(productType);
  const lodging = listing?.lodging;
  return {
    amenities: (lodging?.amenities ?? []) as LodgingAmenity[],
    draft: {
      ...emptyPublicDraft(placement),
      placement,
      publicSlug: listing?.public_slug ?? '',
      nameEs: listing?.name_es ?? '',
      nameEn: listing?.name_en ?? '',
      descriptionEs: listing?.description_es ?? '',
      descriptionEn: listing?.description_en ?? '',
      featured: listing?.featured ?? false,
      publicCategoryId: listing?.public_category_id ?? '',
      location: listing?.location ?? '',
      meetingPoint: listing?.meeting_point ?? '',
      schedule: listing?.schedule ?? '',
      duration: listing?.duration ?? '',
      displayPrice: listing?.display_price == null ? '' : String(listing.display_price),
      originalPrice: listing?.original_price == null ? '' : String(listing.original_price),
      currency: listing?.currency ?? 'COP',
      rating: listing?.rating == null ? '' : String(listing.rating),
      includesText: formatBilingualLines(listing?.includes ?? []),
      warningsText: formatBilingualLines(listing?.warnings ?? []),
      lodgingType: lodging?.lodging_type ?? 'casa',
      locationEs: lodging?.location_es ?? '',
      locationEn: lodging?.location_en ?? '',
      neighborhoodEs: lodging?.neighborhood_es ?? '',
      neighborhoodEn: lodging?.neighborhood_en ?? '',
      bedrooms: lodging?.bedrooms ?? 0,
      bathrooms: lodging?.bathrooms ?? 0,
      maxGuests: listing?.max_guests ?? 2,
      mapUrl: lodging?.map_url ?? '',
      tagsText: (lodging?.tags ?? []).join(', '),
      yachtLinesText: formatYachtLines(listing?.yacht_lines ?? []),
    },
  };
}

export function buildSavePayload(
  productId: string,
  draft: PublicDraft,
  amenities: readonly LodgingAmenity[],
  fallbackSlug: string,
): SavePublicListingPayload {
  const placement = draft.placement;
  const displayPrice = optionalNumber(draft.displayPrice);
  const originalPrice = optionalNumber(draft.originalPrice);
  const rating = optionalNumber(draft.rating);
  const slug = (draft.publicSlug.trim() || fallbackSlug).toLowerCase();

  return {
    product_id: productId,
    placement,
    public_slug: slug,
    name_es: draft.nameEs.trim() || null,
    name_en: draft.nameEn.trim() || null,
    description_es: draft.descriptionEs.trim() || null,
    description_en: draft.descriptionEn.trim() || null,
    featured: draft.featured,
    rating,
    display_price: displayPrice,
    original_price: originalPrice,
    currency: draft.currency.trim().toUpperCase() || null,
    warnings: parseBilingualLines(draft.warningsText),
    includes: placement === 'catalog' ? parseBilingualLines(draft.includesText) : [],
    public_category_id: placement === 'catalog' ? draft.publicCategoryId || null : null,
    location: placement === 'catalog' ? draft.location.trim() || null : null,
    meeting_point: placement === 'catalog' ? draft.meetingPoint.trim() || null : null,
    schedule: placement === 'catalog' ? draft.schedule.trim() || null : null,
    duration: placement === 'catalog' ? draft.duration.trim() || null : null,
    max_guests:
      placement === 'lodging' ? draft.maxGuests : optionalNumber(String(draft.maxGuests || '')),
    lodging: placement === 'lodging' ? buildLodgingDetails(draft, amenities) : null,
    yacht_lines: placement === 'yacht' ? parseYachtLines(draft.yachtLinesText) : [],
  };
}

export function placementOptions(type: ProductType): PublicPlacement[] {
  if (type === 'accommodation') {
    return ['lodging'];
  }
  if (type === 'package') {
    return ['catalog'];
  }
  if (type === 'experience') {
    return ['catalog', 'yacht'];
  }
  return ['catalog'];
}

export function placementLabel(placement: PublicPlacement): string {
  switch (placement) {
    case 'catalog':
      return 'Catálogo (ofertas)';
    case 'lodging':
      return 'Alojamiento';
    case 'yacht':
      return 'Yates';
  }
}

function buildLodgingDetails(
  draft: PublicDraft,
  amenities: readonly LodgingAmenity[],
): LodgingDetails {
  return {
    lodging_type: draft.lodgingType,
    location_es: draft.locationEs.trim(),
    location_en: draft.locationEn.trim(),
    neighborhood_es: draft.neighborhoodEs.trim(),
    neighborhood_en: draft.neighborhoodEn.trim(),
    bedrooms: draft.bedrooms,
    bathrooms: draft.bathrooms,
    amenities: [...amenities],
    tags: draft.tagsText
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean),
    map_url: draft.mapUrl.trim() || null,
  };
}

export function parseBilingualLines(text: string): BilingualPair[] {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [es, en] = line.split('|||').map((part) => part.trim());
      return { es: es ?? '', en: en ?? '' };
    });
}

export function formatBilingualLines(pairs: BilingualPair[]): string {
  return pairs.map((pair) => `${pair.es} ||| ${pair.en}`).join('\n');
}

export function parseYachtLines(text: string): YachtLine[] {
  const capacity: YachtLine[] = [];
  const feature: YachtLine[] = [];

  for (const raw of text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)) {
    const [meta, texts] = splitOnce(raw, '|||');
    const [kindRaw, iconRaw, esPart] = (meta ?? '').split('|').map((part) => part.trim());
    const kind = kindRaw === 'feature' ? 'feature' : 'capacity';
    const icon = (iconRaw || null) as YachtIcon | null;
    const line: YachtLine = {
      kind,
      position: 0,
      icon: icon && (YACHT_ICONS as readonly string[]).includes(icon) ? icon : null,
      text_es: (esPart ?? '').trim(),
      text_en: (texts ?? '').trim(),
    };
    if (kind === 'feature') {
      feature.push(line);
    } else {
      capacity.push(line);
    }
  }

  return [
    ...capacity.map((line, index) => ({ ...line, position: index })),
    ...feature.map((line, index) => ({ ...line, position: index })),
  ];
}

export function formatYachtLines(lines: YachtLine[]): string {
  return [...lines]
    .sort((a, b) => {
      if (a.kind === b.kind) {
        return a.position - b.position;
      }
      return a.kind === 'capacity' ? -1 : 1;
    })
    .map((line) => `${line.kind}|${line.icon ?? ''}|${line.text_es}|||${line.text_en}`)
    .join('\n');
}

function splitOnce(value: string, separator: string): [string, string] {
  const index = value.indexOf(separator);
  if (index < 0) {
    return [value, ''];
  }
  return [value.slice(0, index), value.slice(index + separator.length)];
}

export function optionalNumber(value: string | number | null | undefined): number | null {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

export function toTimeInput(value: string | null | undefined): string {
  if (!value) {
    return '';
  }
  return value.length >= 5 ? value.slice(0, 5) : value;
}
