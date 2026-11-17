import {
  isIdentifierAccessOpen,
  isValidTaxonomyCode,
  suggestTaxonomyCode,
  validatePublicProfile,
  type SavePublicProfilePayload,
} from './public-agency-config.model';

const validProfile: SavePublicProfilePayload = {
  commercial_name: 'Agencia Uno',
  logo_ref: null,
  primary_color: '#0f766e',
  contact_email: 'hola@agencia.test',
  contact_phone: '+57 (300) 000-0000',
  whatsapp: null,
  social_links: { instagram: 'https://instagram.com/agencia' },
  languages: ['es', 'en'],
  currency: 'COP',
};

describe('isValidTaxonomyCode', () => {
  it('accepts stable lowercase codes with single underscores', () => {
    expect(isValidTaxonomyCode('sea_view')).toBe(true);
    expect(isValidTaxonomyCode('tierra_bomba')).toBe(true);
    expect(isValidTaxonomyCode('ac')).toBe(true);
  });

  it('rejects spaces, capitals, accents, edge or double underscores and long codes', () => {
    for (const code of [
      '',
      'Vista Mar',
      'Wifi',
      'baño',
      '_x',
      'x_',
      'a__b',
      'a-b',
      'x'.repeat(41),
    ]) {
      expect(isValidTaxonomyCode(code)).toBe(false);
    }
  });
});

describe('suggestTaxonomyCode', () => {
  it('derives a valid code from a bilingual label', () => {
    expect(suggestTaxonomyCode('Vista al mar')).toBe('vista_al_mar');
    expect(suggestTaxonomyCode('  Gastronomía & Vinos ')).toBe('gastronomia_vinos');
    expect(isValidTaxonomyCode(suggestTaxonomyCode('Habitación privada'))).toBe(true);
  });

  it('never ends on an underscore after truncation', () => {
    const code = suggestTaxonomyCode(`${'a'.repeat(39)} b`);
    expect(code.endsWith('_')).toBe(false);
    expect(code.length).toBeLessThanOrEqual(40);
  });
});

describe('isIdentifierAccessOpen', () => {
  const now = new Date('2026-11-13T12:00:00Z');

  it('is open only for a migrating agency before its cutoff', () => {
    const config = {
      organization_id: 'org',
      migration_required: true,
      organization_identifier_until: '2027-02-11T12:00:00Z',
    };
    expect(isIdentifierAccessOpen(config, now)).toBe(true);
    expect(
      isIdentifierAccessOpen(
        { ...config, organization_identifier_until: '2026-11-13T11:59:59Z' },
        now,
      ),
    ).toBe(false);
  });

  it('is closed for a migration-free agency or without configuration', () => {
    expect(
      isIdentifierAccessOpen(
        {
          organization_id: 'org',
          migration_required: false,
          organization_identifier_until: '2099-01-01T00:00:00Z',
        },
        now,
      ),
    ).toBe(false);
    expect(isIdentifierAccessOpen(null, now)).toBe(false);
  });
});

describe('validatePublicProfile', () => {
  it('accepts a complete, valid profile', () => {
    expect(validatePublicProfile(validProfile, ['COP', 'USD', 'EUR'])).toEqual({});
  });

  it('names every invalid field', () => {
    const errors = validatePublicProfile(
      {
        ...validProfile,
        commercial_name: '   ',
        primary_color: 'verde',
        contact_email: 'sin-arroba',
        contact_phone: 'llamar',
        whatsapp: 'x',
        social_links: { facebook: 'http://facebook.com/x' },
        languages: [],
        currency: 'JPY',
      },
      ['COP', 'USD', 'EUR'],
    );
    expect(Object.keys(errors).sort()).toEqual(
      [
        'commercial_name',
        'contact_email',
        'contact_phone',
        'currency',
        'languages',
        'primary_color',
        'social_links',
        'whatsapp',
      ].sort(),
    );
  });

  it('treats empty optional fields as absent, not invalid', () => {
    expect(
      validatePublicProfile(
        {
          ...validProfile,
          primary_color: null,
          contact_email: null,
          contact_phone: null,
          social_links: { instagram: '' },
        },
        ['COP'],
      ),
    ).toEqual({});
  });
});
