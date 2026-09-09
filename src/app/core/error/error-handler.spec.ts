import { toAppError } from './error-handler';

describe('toAppError', () => {
  it('maps EMAIL_ALREADY_EXISTS from a contract code', () => {
    expect(toAppError({ code: 'EMAIL_ALREADY_EXISTS' }).code).toBe('EMAIL_ALREADY_EXISTS');
  });

  it('maps AGENCY_SLUG_EXISTS from a contract code', () => {
    expect(toAppError({ code: 'AGENCY_SLUG_EXISTS' }).code).toBe('AGENCY_SLUG_EXISTS');
  });

  it('maps AGENCY_SLUG_EXISTS from a unique-violation on slug', () => {
    expect(
      toAppError({
        code: '23505',
        message: 'duplicate key value violates unique constraint "organizations_slug_key"',
        details: 'Key (slug)=(agencia-nueva) already exists.',
      }).code,
    ).toBe('AGENCY_SLUG_EXISTS');
  });

  it('maps a unique-violation on email to EMAIL_ALREADY_EXISTS', () => {
    expect(
      toAppError({
        code: '23505',
        message: 'duplicate key value violates unique constraint "user_profiles_email_key"',
      }).code,
    ).toBe('EMAIL_ALREADY_EXISTS');
  });

  it('reads the contract code out of a PostgreSQL exception message', () => {
    expect(toAppError({ message: 'AGENCY_SLUG_EXISTS' }).code).toBe('AGENCY_SLUG_EXISTS');
  });

  it('maps PRODUCT_HAS_NO_VALID_PRICE from a contract code in the message', () => {
    expect(toAppError({ message: 'PRODUCT_HAS_NO_VALID_PRICE' }).code).toBe(
      'PRODUCT_HAS_NO_VALID_PRICE',
    );
  });

  it('maps SEASON_OVERLAP from a contract code in the message', () => {
    expect(toAppError({ message: 'SEASON_OVERLAP' }).code).toBe('SEASON_OVERLAP');
  });

  it('maps a GiST exclusion violation to SEASON_OVERLAP', () => {
    expect(toAppError({ code: '23P01' }).code).toBe('SEASON_OVERLAP');
  });

  it('maps INVALID_SEASON_RANGE and INVALID_PRICE_TARGET from contract codes', () => {
    expect(toAppError({ message: 'INVALID_SEASON_RANGE' }).code).toBe('INVALID_SEASON_RANGE');
    expect(toAppError({ message: 'INVALID_PRICE_TARGET' }).code).toBe('INVALID_PRICE_TARGET');
  });

  it('maps PACKAGE_NESTING_NOT_ALLOWED from a contract code in the message', () => {
    expect(toAppError({ message: 'PACKAGE_NESTING_NOT_ALLOWED' }).code).toBe(
      'PACKAGE_NESTING_NOT_ALLOWED',
    );
  });

  it('maps a unique-violation on category slug to VALIDATION_ERROR', () => {
    expect(
      toAppError({
        code: '23505',
        message:
          'duplicate key value violates unique constraint "categories_organization_id_slug_key"',
        details: 'Key (organization_id, slug)=(…, aventura) already exists.',
      }).code,
    ).toBe('VALIDATION_ERROR');
  });
});
