import { toSearchOrFilter } from './search-pattern';

describe('toSearchOrFilter', () => {
  it('returns null for an empty query', () => {
    expect(toSearchOrFilter('   ', ['reference'])).toBeNull();
  });

  it('strips characters that would inject another filter', () => {
    expect(toSearchOrFilter('a,b),or(id.eq.1', ['reference'])).toBe(
      'reference.ilike.*aborid.eq.1*',
    );
  });

  it('searches a phone column by digits only', () => {
    expect(toSearchOrFilter('300 123', ['customer_phone_e164'], ['customer_phone_e164'])).toBe(
      'customer_phone_e164.ilike.*300123*',
    );
  });

  it('omits the phone column when the term has no digits', () => {
    expect(toSearchOrFilter('Ana', ['customer_first_name'], ['customer_phone_e164'])).toBe(
      'customer_first_name.ilike.*Ana*',
    );
  });

  it('caps the term at 80 characters', () => {
    const term = 'a'.repeat(90);
    const filter = toSearchOrFilter(term, ['reference']);
    expect(filter).toBe(`reference.ilike.*${'a'.repeat(80)}*`);
  });
});
