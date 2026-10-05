import {
  PREVIEW_SUMMARY_LIMIT,
  PREVIEW_TITLE_LIMIT,
  toPreviewListing,
  truncatePreview,
  type PreviewListingInput,
} from './preview-listing.model';

function input(patch: Partial<PreviewListingInput> = {}): PreviewListingInput {
  return {
    variant: 'catalog',
    locale: 'es',
    titleEs: 'Paseo en lancha',
    titleEn: 'Boat ride',
    descriptionEs: 'Salida al amanecer por la bahía.',
    descriptionEn: 'Dawn departure across the bay.',
    categoryLabelEs: 'Mar',
    categoryLabelEn: 'Sea',
    location: 'Taganga',
    imageUrl: null,
    displayPrice: 120000,
    currency: 'cop',
    soldOut: false,
    ...patch,
  };
}

describe('toPreviewListing', () => {
  it('uses the active locale and does not borrow the other language', () => {
    const preview = toPreviewListing(input({ locale: 'en', titleEn: '', descriptionEn: '' }));
    expect(preview.title).toBe('Sin título');
    expect(preview.summary).toBe('Falta la descripción en inglés');
    expect(preview.missingLocale).toBe(true);
    expect(preview.summary).not.toContain('amanecer');
  });

  it('truncates long title and summary', () => {
    const title = 'A'.repeat(PREVIEW_TITLE_LIMIT + 10);
    const summary = 'B'.repeat(PREVIEW_SUMMARY_LIMIT + 10);
    const preview = toPreviewListing(input({ titleEs: title, descriptionEs: summary }));
    expect([...preview.title].length).toBe(PREVIEW_TITLE_LIMIT);
    expect(preview.title.endsWith('…')).toBe(true);
    expect([...preview.summary].length).toBe(PREVIEW_SUMMARY_LIMIT);
  });

  it('hides an empty yacht price and shows lodging extras', () => {
    const yacht = toPreviewListing(input({ variant: 'yacht', displayPrice: null }));
    expect(yacht.showPrice).toBe(false);

    const lodging = toPreviewListing(
      input({ variant: 'lodging', lodgingType: 'casa', occupancy: 6, displayPrice: null }),
    );
    expect(lodging.showPrice).toBe(true);
    expect(lodging.lodgingType).toBe('casa');
    expect(lodging.occupancy).toBe(6);
    expect(lodging.currency).toBe('COP');
  });

  it('truncatePreview leaves short copy intact', () => {
    expect(truncatePreview('Bahía', 70)).toBe('Bahía');
  });
});
