import { customerDisplayName } from './customer.model';

describe('customerDisplayName', () => {
  it('hides an anonymized profile', () => {
    expect(
      customerDisplayName({
        first_name: 'Cliente anonimizado',
        last_name: null,
        is_anonymized: true,
      }),
    ).toBe('Cliente anonimizado');
  });

  it('omits a missing surname', () => {
    expect(
      customerDisplayName({ first_name: 'Laura', last_name: null, is_anonymized: false }),
    ).toBe('Laura');
  });

  it('joins the name and collapses extra spaces', () => {
    expect(
      customerDisplayName({
        first_name: '  Laura',
        last_name: 'Gómez  ',
        is_anonymized: false,
      }),
    ).toBe('Laura Gómez');
  });
});
