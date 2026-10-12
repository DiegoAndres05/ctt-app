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

  it('maps customer and request contract codes carried in the message', () => {
    expect(toAppError({ message: 'CUSTOMER_CONTACT_TAKEN' }).code).toBe('CUSTOMER_CONTACT_TAKEN');
    expect(toAppError({ message: 'CONTACT_REQUIRED' }).code).toBe('CONTACT_REQUIRED');
    expect(toAppError({ message: 'PRE_RESERVATION_REQUIRES_CONVERSION' }).code).toBe(
      'PRE_RESERVATION_REQUIRES_CONVERSION',
    );
    expect(toAppError({ message: 'LISTING_NOT_AVAILABLE' }).code).toBe('LISTING_NOT_AVAILABLE');
  });

  it('maps pre-reservation contract codes carried in the message to code and message', () => {
    const requiresItems = toAppError({ message: 'PRE_RESERVATION_REQUIRES_ITEMS' });
    expect(requiresItems.code).toBe('PRE_RESERVATION_REQUIRES_ITEMS');
    expect(requiresItems.message).toBe(
      'La pre-reserva debe conservar al menos un servicio principal.',
    );

    const holdInPast = toAppError({ message: 'HOLD_EXPIRY_IN_PAST' });
    expect(holdInPast.code).toBe('HOLD_EXPIRY_IN_PAST');
    expect(holdInPast.message).toBe('La fecha límite de retención debe ser futura.');

    const overrideNotRequired = toAppError({ message: 'OVERRIDE_NOT_REQUIRED' });
    expect(overrideNotRequired.code).toBe('OVERRIDE_NOT_REQUIRED');
    expect(overrideNotRequired.message).toBe(
      'La pre-reserva ya está totalmente verificada; no necesita excepción.',
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

  // Quotations (feature 005): contracts §2–§5 raise the contract code as the message.
  const QUOTATION_MESSAGES: readonly (readonly [string, string])[] = [
    ['TARIFF_NOT_FOUND', 'No hay tarifa vigente para este servicio.'],
    ['AMBIGUOUS_TARIFF', 'Hay más de una tarifa vigente y ninguna coincide con el tipo de cobro.'],
    ['EXCHANGE_RATE_REQUIRED', 'Falta la tasa de cambio para emitir.'],
    ['EXCHANGE_RATE_INVALID', 'La tasa de cambio debe ser mayor que cero.'],
    ['TAX_RATE_OUT_OF_RANGE', 'El impuesto debe estar entre 0 % y 100 %.'],
    ['ADJUSTMENT_REQUIRES_ADMIN', 'Este ajuste supera el 15 % y requiere un administrador.'],
    ['ADJUSTMENT_LABEL_REQUIRED', 'El ajuste necesita una etiqueta.'],
    ['QUOTATION_FROZEN', 'La cotización emitida no se edita. Cree una versión nueva.'],
    ['QUOTATION_ALREADY_OPEN', 'Ya hay una cotización abierta para esta pre-reserva.'],
    ['QUOTATION_ALREADY_ACCEPTED', 'Esta pre-reserva ya tiene una cotización aceptada.'],
    ['VALIDITY_EXCEEDS_HOLD', 'La vigencia no puede pasar de la retención de la pre-reserva.'],
    ['VALIDITY_EXCEEDS_30_DAYS', 'La vigencia no puede pasar de 30 días.'],
    ['TERMS_REQUIRED', 'Faltan las condiciones de la propuesta.'],
    [
      'QUOTATION_STALE',
      'La pre-reserva cambió después de emitir. Hay que crear una versión nueva.',
    ],
    ['QUOTATION_NOT_OPEN', 'Esta propuesta ya no admite esa respuesta.'],
    ['QUOTATION_TERMINAL', 'Esta cotización está cerrada.'],
    ['QUOTATION_NOT_ACCEPTED', 'Solo una cotización aceptada puede confirmarse como reserva.'],
    ['QUOTATION_ACCEPTED', 'Una cotización aceptada no se anula.'],
    ['VOID_REASON_REQUIRED', 'Indique el motivo de la anulación.'],
    ['CONFIRMATION_REQUIRED', 'Confirme la aceptación para continuar.'],
  ];

  it('maps every quotation contract code carried in the message to its exact message', () => {
    for (const [code, message] of QUOTATION_MESSAGES) {
      const fromMessage = toAppError({ message: code });
      expect(fromMessage.code).toBe(code);
      expect(fromMessage.message).toBe(message);

      const fromCode = toAppError({ code });
      expect(fromCode.code).toBe(code);
      expect(fromCode.message).toBe(message);
    }
  });

  it('reuses the existing pre-reservation message for PRE_RESERVATION_NOT_VERIFIED', () => {
    const error = toAppError({ message: 'PRE_RESERVATION_NOT_VERIFIED' });
    expect(error.code).toBe('PRE_RESERVATION_NOT_VERIFIED');
    expect(error.message).toBe('La pre-reserva aún no está totalmente verificada.');
  });
});
