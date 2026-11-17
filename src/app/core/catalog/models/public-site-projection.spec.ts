import { parsePublicSite } from './public-site-projection';

const offer = {
  id: 'islas-capri-premium',
  name: 'Islas del Rosario',
  nameEn: 'Rosario Islands',
  description: 'Día completo en las islas.',
  descriptionEn: 'Full day at the islands.',
  image: 'org/cover.jpg',
  includes: ['Almuerzo', 'Transporte'],
  includesEn: ['Lunch', 'Transport'],
  warnings: [],
  warningsEn: [],
  price: 250000,
  currency: 'cop',
  soldOut: false,
  acceptsRequests: true,
};

describe('parsePublicSite', () => {
  it('treats legacy as the preparing state with no listings', () => {
    const catalog = parsePublicSite({
      source: 'legacy',
      offers: [offer],
      lodgings: [],
      yachts: [],
    });
    expect(catalog.source).toBe('legacy');
    expect(catalog.offers).toEqual([]);
  });

  it('treats a missing or malformed payload as preparing', () => {
    expect(parsePublicSite(null).source).toBe('legacy');
    expect(parsePublicSite([]).source).toBe('legacy');
    expect(parsePublicSite({ source: 'other' }).source).toBe('legacy');
  });

  it('maps a panel payload with one offer', () => {
    const catalog = parsePublicSite({ source: 'panel', offers: [offer], lodgings: [], yachts: [] });
    expect(catalog.source).toBe('panel');
    expect(catalog.offers).toHaveLength(1);
    const [mapped] = catalog.offers;
    expect(mapped.id).toBe('islas-capri-premium');
    expect(mapped.nameEn).toBe('Rosario Islands');
    expect(mapped.includesEn).toEqual(['Lunch', 'Transport']);
    expect(mapped.price).toBe(250000);
    expect(mapped.acceptsRequests).toBe(true);
    expect(mapped.meetingPoint).toBeNull();
  });

  it('keeps a sold-out listing visible and never lets it accept requests', () => {
    const catalog = parsePublicSite({
      source: 'panel',
      offers: [],
      lodgings: [],
      yachts: [{ id: 'azimut-70', name: 'Azimut', soldOut: true, acceptsRequests: true }],
    });
    expect(catalog.yachts).toHaveLength(1);
    expect(catalog.yachts[0].soldOut).toBe(true);
    expect(catalog.yachts[0].acceptsRequests).toBe(false);
  });

  it('has no draft: only what the RPC projects is listed', () => {
    const catalog = parsePublicSite({ source: 'panel', offers: [offer], lodgings: [], yachts: [] });
    expect(catalog.offers.map((item) => item.id)).toEqual(['islas-capri-premium']);
    expect(catalog.lodgings).toEqual([]);
  });

  it('drops entries without a slug and coerces bad field types', () => {
    const catalog = parsePublicSite({
      source: 'panel',
      offers: [{ name: 'Sin slug' }, 'texto', { ...offer, price: 'abc', includes: 'no' }],
      lodgings: [
        {
          id: 'villa-caribe',
          name: 'Villa',
          pricePerNight: '480000',
          gallery: ['a.jpg', 3, ''],
          amenities: ['wifi'],
        },
      ],
      yachts: [],
    });
    expect(catalog.offers).toHaveLength(1);
    expect(catalog.offers[0].price).toBeNull();
    expect(catalog.offers[0].includes).toEqual([]);
    expect(catalog.lodgings[0].pricePerNight).toBe(480000);
    expect(catalog.lodgings[0].gallery).toEqual(['a.jpg']);
  });
});
