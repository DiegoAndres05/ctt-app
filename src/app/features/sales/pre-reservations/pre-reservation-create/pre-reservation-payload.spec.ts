import type { RequestItem } from '../../../../core/customers/models/request.model';
import type { BookableOption } from '../../../../core/pre-reservations/services/pre-reservation.service';
import {
  buildCreatePayload,
  draftsFromRequest,
  emptyItemDraft,
  validateItemDrafts,
  type PreReservationItemDraft,
} from './pre-reservation-payload';

const TODAY = '2026-10-04';

function mainItem(overrides: Partial<PreReservationItemDraft> = {}): PreReservationItemDraft {
  return {
    ...emptyItemDraft('product'),
    productId: 'prod-1',
    itemKind: 'accommodation',
    startDate: '2026-12-01',
    endDate: '2026-12-05',
    adults: 2,
    children: 1,
    quantity: 1,
    sourceRequestItemId: 'ri-1',
    ...overrides,
  };
}

describe('validateItemDrafts', () => {
  it('accepts a main line plus an alternative pointing at it', () => {
    const alternative = mainItem({
      productId: 'prod-2',
      itemKind: 'experience',
      endDate: '',
      alternativeOf: 0,
    });
    expect(validateItemDrafts([mainItem(), alternative], TODAY)).toEqual([]);
  });

  it('requires a product when the selector is Producto', () => {
    const issues = validateItemDrafts([mainItem({ productId: null })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.bookable')).toBe(true);
  });

  it('requires an add-on when the selector is Complemento', () => {
    const issues = validateItemDrafts([emptyItemDraft('addon')], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.bookable')).toBe(true);
  });

  it('requires a start date', () => {
    const issues = validateItemDrafts([mainItem({ startDate: '' })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.startDate')).toBe(true);
  });

  it('rejects a start date before today', () => {
    const issues = validateItemDrafts([mainItem({ startDate: '2026-10-03' })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.startDate')).toBe(true);
  });

  it('requires the exit date on accommodations', () => {
    const issues = validateItemDrafts([mainItem({ endDate: '' })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.endDate')).toBe(true);
  });

  it('rejects an exit date on or before the arrival date', () => {
    const issues = validateItemDrafts([mainItem({ endDate: '2026-12-01' })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.endDate')).toBe(true);
  });

  it('rejects adults outside 1–99', () => {
    const issues = validateItemDrafts([mainItem({ adults: 0 })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.adults')).toBe(true);
  });

  it('rejects children outside 0–99', () => {
    const issues = validateItemDrafts([mainItem({ children: 100 })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.children')).toBe(true);
  });

  it('rejects quantity outside 1–99', () => {
    const issues = validateItemDrafts([mainItem({ quantity: 0 })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.quantity')).toBe(true);
  });

  it('rejects an alternative pointing at a later row', () => {
    const issues = validateItemDrafts([mainItem({ alternativeOf: 1 })], TODAY);
    expect(issues.some((issue) => issue.field === 'item-0.alternativeOf')).toBe(true);
  });

  it('rejects an alternative pointing at another alternative', () => {
    const alternative = mainItem({ productId: 'prod-2', itemKind: 'experience', endDate: '' });
    const issues = validateItemDrafts(
      [mainItem(), { ...alternative, alternativeOf: 0 }, { ...alternative, alternativeOf: 1 }],
      TODAY,
    );
    expect(issues.some((issue) => issue.field === 'item-2.alternativeOf')).toBe(true);
  });

  it('requires at least one main line', () => {
    expect(validateItemDrafts([], TODAY)).toEqual([
      { field: 'items', message: 'La pre-reserva necesita al menos un servicio principal.' },
    ]);
  });
});

describe('buildCreatePayload', () => {
  it('trims text and turns blanks into null', () => {
    const payload = buildCreatePayload(
      [
        mainItem({
          startDate: '  2026-12-01  ',
          endDate: '   ',
          providerName: '  ',
          providerPhone: '+57 300 111 2233',
          sourceRequestItemId: '  ri-1  ',
        }),
      ],
      null,
    );

    expect(payload.items[0].start_date).toBe('2026-12-01');
    expect(payload.items[0].end_date).toBeNull();
    expect(payload.items[0].source_request_item_id).toBe('ri-1');
    expect(payload.items[0].provider_name).toBeNull();
    expect(payload.items[0].provider_phone).toBe('+57 300 111 2233');
    expect(payload.assigned_operator_id).toBeNull();
  });

  it('sends alternative_of only on alternative lines', () => {
    const alternative = mainItem({ productId: 'prod-2', itemKind: 'experience', endDate: '' });
    const payload = buildCreatePayload([mainItem(), { ...alternative, alternativeOf: 0 }], null);
    expect(payload.items[0]).not.toHaveProperty('alternative_of');
    expect(payload.items[1].alternative_of).toBe(0);
  });

  it('omits the manual provider when the product already carries one', () => {
    const payload = buildCreatePayload(
      [
        mainItem({
          productHasProvider: true,
          providerName: 'Lanchas Barú',
          providerPhone: '+57 300 111 2233',
          providerEmail: 'hola@baru.test',
        }),
      ],
      null,
    );
    expect(payload.items[0].provider_name).toBeNull();
    expect(payload.items[0].provider_phone).toBeNull();
    expect(payload.items[0].provider_email).toBeNull();
  });

  it('keeps the manual provider when the product has none', () => {
    const payload = buildCreatePayload(
      [
        mainItem({
          productHasProvider: false,
          providerName: '  Transportes Isla  ',
          providerPhone: '',
          providerEmail: 'isla@test.co',
        }),
      ],
      null,
    );
    expect(payload.items[0].provider_name).toBe('Transportes Isla');
    expect(payload.items[0].provider_phone).toBeNull();
    expect(payload.items[0].provider_email).toBe('isla@test.co');
  });

  it('passes the assigned operator through', () => {
    expect(buildCreatePayload([mainItem()], 'op-1').assigned_operator_id).toBe('op-1');
    expect(buildCreatePayload([mainItem()], null).assigned_operator_id).toBeNull();
  });
});

describe('draftsFromRequest', () => {
  const bookables: BookableOption[] = [
    {
      id: 'prod-1',
      name: 'Cabaña Barú',
      kind: 'accommodation',
      provider_id: 'prov-1',
      provider: {
        id: 'prov-1',
        name: 'Lanchas Barú',
        contact_phone: '+57 300 111 2233',
        contact_email: 'hola@baru.test',
        is_active: true,
      },
    },
    {
      id: 'prod-off',
      name: 'Tour archivado',
      kind: 'experience',
      provider_id: null,
      provider: null,
    },
    { id: 'addon-1', name: 'Transporte', kind: 'addon', provider_id: null, provider: null },
  ];

  function interest(overrides: Partial<RequestItem> = {}): RequestItem {
    return {
      id: 'ri-1',
      product_id: 'prod-1',
      public_slug: null,
      free_text: null,
      quantity: 3,
      position: 0,
      product: { id: 'prod-1', name: 'Cabaña Barú', product_type: 'accommodation' },
      ...overrides,
    };
  }

  it('prefills dates, passengers and the provider snapshot from the request', () => {
    const drafts = draftsFromRequest(
      {
        travel_start_date: '2026-12-01',
        travel_end_date: '2026-12-08',
        adults: 2,
        children: 1,
        items: [interest()],
      },
      bookables,
    );

    expect(drafts).toHaveLength(1);
    expect(drafts[0]).toMatchObject({
      kind: 'product',
      productId: 'prod-1',
      itemKind: 'accommodation',
      startDate: '2026-12-01',
      endDate: '2026-12-08',
      adults: 2,
      children: 1,
      quantity: 3,
      productHasProvider: true,
      providerName: 'Lanchas Barú',
      sourceRequestItemId: 'ri-1',
      alternativeOf: null,
    });
  });

  it('skips interests without a product and products missing from the catalog', () => {
    const drafts = draftsFromRequest(
      {
        travel_start_date: null,
        travel_end_date: null,
        adults: 1,
        children: 0,
        items: [
          interest({ id: 'ri-free', product_id: null, free_text: 'Texto libre', product: null }),
          interest({ id: 'ri-gone', product_id: 'prod-gone' }),
        ],
      },
      bookables,
    );
    expect(drafts).toEqual([]);
  });

  it('leaves the manual provider empty when the product provider is inactive', () => {
    const inactive: BookableOption[] = [
      {
        id: 'prod-1',
        name: 'Cabaña Barú',
        kind: 'accommodation',
        provider_id: 'prov-1',
        provider: {
          id: 'prov-1',
          name: 'Lanchas Barú',
          contact_phone: null,
          contact_email: null,
          is_active: false,
        },
      },
    ];
    const drafts = draftsFromRequest(
      {
        travel_start_date: '2026-12-01',
        travel_end_date: null,
        adults: 1,
        children: 0,
        items: [interest()],
      },
      inactive,
    );
    expect(drafts[0].productHasProvider).toBe(false);
    expect(drafts[0].providerName).toBe('');
    expect(drafts[0].endDate).toBe('');
  });
});
