export type PreviewVariant = 'catalog' | 'lodging' | 'yacht';
export type PreviewLocale = 'es' | 'en';

export const PREVIEW_TITLE_LIMIT = 70;
export const PREVIEW_SUMMARY_LIMIT = 140;

/** Form signals mapped into the card. Empty copy is never borrowed from the other locale. */
export interface PreviewListingInput {
  variant: PreviewVariant;
  locale: PreviewLocale;
  titleEs: string;
  titleEn: string;
  descriptionEs: string;
  descriptionEn: string;
  categoryLabelEs: string;
  categoryLabelEn: string;
  location: string;
  imageUrl: string | null;
  displayPrice: number | null;
  currency: string | null;
  soldOut: boolean;
  lodgingType?: string | null;
  occupancy?: number | null;
  imageLoading?: boolean;
}

export interface PreviewListing {
  variant: PreviewVariant;
  locale: PreviewLocale;
  title: string;
  summary: string;
  categoryLabel: string;
  location: string;
  imageUrl: string | null;
  displayPrice: number | null;
  currency: string;
  soldOut: boolean;
  lodgingType: string | null;
  occupancy: number | null;
  missingLocale: boolean;
  showPrice: boolean;
  imageLoading: boolean;
}

export function truncatePreview(value: string, max: number): string {
  const chars = [...value];
  if (chars.length <= max) {
    return value;
  }
  return `${chars.slice(0, Math.max(0, max - 1)).join('')}…`;
}

export function toPreviewListing(input: PreviewListingInput): PreviewListing {
  const titleRaw = (input.locale === 'en' ? input.titleEn : input.titleEs).trim();
  const summaryRaw = (input.locale === 'en' ? input.descriptionEn : input.descriptionEs).trim();
  const categoryRaw = (
    input.locale === 'en' ? input.categoryLabelEn : input.categoryLabelEs
  ).trim();
  const language = input.locale === 'en' ? 'inglés' : 'español';
  const missingLocale = titleRaw.length === 0 || summaryRaw.length === 0;
  const price = input.displayPrice;
  const showPrice = !(input.variant === 'yacht' && (price === null || Number.isNaN(price)));

  return {
    variant: input.variant,
    locale: input.locale,
    title: titleRaw ? truncatePreview(titleRaw, PREVIEW_TITLE_LIMIT) : 'Sin título',
    summary: summaryRaw
      ? truncatePreview(summaryRaw, PREVIEW_SUMMARY_LIMIT)
      : `Falta la descripción en ${language}`,
    categoryLabel: categoryRaw,
    location: input.location.trim(),
    imageUrl: input.imageUrl,
    displayPrice: price,
    currency: input.currency?.trim().toUpperCase() || 'COP',
    soldOut: input.soldOut,
    lodgingType: input.variant === 'lodging' ? input.lodgingType?.trim() || null : null,
    occupancy: input.variant === 'lodging' ? (input.occupancy ?? null) : null,
    missingLocale,
    showPrice,
    imageLoading: input.imageLoading ?? false,
  };
}
