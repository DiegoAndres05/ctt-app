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
});
