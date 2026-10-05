import {
  buildAssistedRequestPayload,
  emptyIntakeDraft,
  validateIntakeDraft,
  type IntakeDraft,
} from './intake-payload';

const TODAY = '2026-10-04';

function validDraft(): IntakeDraft {
  return {
    ...emptyIntakeDraft('whatsapp'),
    firstName: 'Ana',
    phone: '300 123 4567',
    travelStart: '2026-12-01',
    adults: 2,
    children: 0,
    items: [{ productId: null, freeText: 'Cena romántica', quantity: 1 }],
    privacyNoticeGiven: true,
  };
}

describe('validateIntakeDraft', () => {
  it('accepts a complete new-customer draft', () => {
    expect(validateIntakeDraft(validDraft(), TODAY)).toEqual([]);
  });

  it('requires a name when no customer is selected', () => {
    const draft = validDraft();
    draft.firstName = '  ';
    expect(validateIntakeDraft(draft, TODAY).some((issue) => issue.field === 'firstName')).toBe(
      true,
    );
  });

  it('requires email or phone when no customer is selected', () => {
    const draft = validDraft();
    draft.phone = '';
    draft.email = '';
    expect(validateIntakeDraft(draft, TODAY).some((issue) => issue.field === 'email')).toBe(true);
  });

  it('skips contact rules when a customer is selected', () => {
    const draft = validDraft();
    draft.customerId = 'cust-1';
    draft.firstName = '';
    draft.phone = '';
    expect(validateIntakeDraft(draft, TODAY)).toEqual([]);
  });

  it('requires the privacy notice', () => {
    const draft = validDraft();
    draft.privacyNoticeGiven = false;
    expect(
      validateIntakeDraft(draft, TODAY).some((issue) => issue.field === 'privacyNoticeGiven'),
    ).toBe(true);
  });

  it('rejects a start date before today', () => {
    const draft = validDraft();
    draft.travelStart = '2026-10-03';
    expect(validateIntakeDraft(draft, TODAY).some((issue) => issue.field === 'travelStart')).toBe(
      true,
    );
  });

  it('rejects an end date before the start', () => {
    const draft = validDraft();
    draft.travelEnd = '2026-11-01';
    expect(validateIntakeDraft(draft, TODAY).some((issue) => issue.field === 'travelEnd')).toBe(
      true,
    );
  });

  it('rejects adults outside 1–99', () => {
    const draft = validDraft();
    draft.adults = 0;
    expect(validateIntakeDraft(draft, TODAY).some((issue) => issue.field === 'adults')).toBe(true);
  });

  it('requires an item or a customer note', () => {
    const draft = validDraft();
    draft.items = [{ productId: null, freeText: '', quantity: 1 }];
    draft.specialRequirements = '';
    expect(validateIntakeDraft(draft, TODAY).some((issue) => issue.field === 'items')).toBe(true);
  });

  it('rejects an item row with neither product nor text', () => {
    const draft = validDraft();
    draft.items = [
      { productId: 'prod-1', freeText: '', quantity: 1 },
      { productId: null, freeText: '  ', quantity: 1 },
    ];
    expect(validateIntakeDraft(draft, TODAY).some((issue) => issue.field === 'item-1')).toBe(true);
  });
});

describe('buildAssistedRequestPayload', () => {
  it('keeps the phone as typed and trims text', () => {
    const draft = validDraft();
    draft.lastName = '  ';
    draft.specialRequirements = '  Sin gluten  ';
    const payload = buildAssistedRequestPayload(draft, 'idem-1');
    expect(payload.contact?.phone).toBe('300 123 4567');
    expect(payload.contact?.last_name).toBeNull();
    expect(payload.special_requirements).toBe('Sin gluten');
    expect(payload.idempotency_key).toBe('idem-1');
    expect(payload.privacy_notice_given).toBe(true);
    expect(payload.items).toEqual([{ free_text: 'Cena romántica', quantity: 1 }]);
  });

  it('omits contact when a customer id is set and drops empty item rows', () => {
    const draft = validDraft();
    draft.customerId = 'cust-1';
    draft.items = [
      { productId: 'prod-1', freeText: '', quantity: 2 },
      { productId: null, freeText: '   ', quantity: 1 },
    ];
    const payload = buildAssistedRequestPayload(draft, 'idem-2');
    expect(payload.customer_id).toBe('cust-1');
    expect(payload.contact).toBeUndefined();
    expect(payload.items).toEqual([{ product_id: 'prod-1', quantity: 2 }]);
  });

  it('turns blank dates into null', () => {
    const draft = validDraft();
    draft.travelStart = '';
    draft.travelEnd = '  ';
    const payload = buildAssistedRequestPayload(draft, 'idem-3');
    expect(payload.travel_start_date).toBeNull();
    expect(payload.travel_end_date).toBeNull();
  });
});
