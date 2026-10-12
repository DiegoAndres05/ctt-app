import * as quotationModel from './quotation.model';
import {
  QUOTATION_ADJUSTMENT_DIRECTION_LABELS,
  QUOTATION_ADJUSTMENT_KIND_LABELS,
  QUOTATION_RESPONSE_KIND_LABELS,
  QUOTATION_RESPONSE_ORIGIN_LABELS,
  QUOTATION_STATUS_LABELS,
  canClientComputeTotals,
  isQuotationFrozen,
  isQuotationOpen,
  isQuotationTerminal,
  type QuotationAdjustmentDirection,
  type QuotationAdjustmentKind,
  type QuotationResponseKind,
  type QuotationResponseOrigin,
  type QuotationStatus,
} from './quotation.model';

const ALL_STATUSES: readonly QuotationStatus[] = [
  'draft',
  'issued',
  'accepted',
  'rejected',
  'expired',
  'voided',
  'superseded',
];

const ALL_DIRECTIONS: readonly QuotationAdjustmentDirection[] = ['discount', 'surcharge'];

const ALL_KINDS: readonly QuotationAdjustmentKind[] = ['percent', 'amount'];

const ALL_RESPONSE_KINDS: readonly QuotationResponseKind[] = [
  'accepted',
  'rejected',
  'changes_requested',
];

const ALL_ORIGINS: readonly QuotationResponseOrigin[] = ['customer', 'agent'];

describe('QUOTATION_STATUS_LABELS', () => {
  it('asserts the seven Spanish status labels', () => {
    expect(QUOTATION_STATUS_LABELS).toEqual({
      draft: 'Borrador',
      issued: 'Emitida',
      accepted: 'Aceptada',
      rejected: 'Rechazada',
      expired: 'Expirada',
      voided: 'Anulada',
      superseded: 'Superada por nueva versión',
    });
  });

  it('labels every status', () => {
    for (const status of ALL_STATUSES) {
      expect(QUOTATION_STATUS_LABELS[status]).toBeTruthy();
    }
  });
});

describe('adjustment and response labels', () => {
  it('labels every adjustment direction and kind', () => {
    for (const direction of ALL_DIRECTIONS) {
      expect(QUOTATION_ADJUSTMENT_DIRECTION_LABELS[direction]).toBeTruthy();
    }
    expect(QUOTATION_ADJUSTMENT_DIRECTION_LABELS).toEqual({
      discount: 'Descuento',
      surcharge: 'Suplemento',
    });

    for (const kind of ALL_KINDS) {
      expect(QUOTATION_ADJUSTMENT_KIND_LABELS[kind]).toBeTruthy();
    }
    expect(QUOTATION_ADJUSTMENT_KIND_LABELS).toEqual({
      percent: 'Porcentaje',
      amount: 'Monto fijo',
    });
  });

  it('labels every response kind and origin', () => {
    for (const kind of ALL_RESPONSE_KINDS) {
      expect(QUOTATION_RESPONSE_KIND_LABELS[kind]).toBeTruthy();
    }
    expect(QUOTATION_RESPONSE_KIND_LABELS.changes_requested).toBe('Requiere modificaciones');

    for (const origin of ALL_ORIGINS) {
      expect(QUOTATION_RESPONSE_ORIGIN_LABELS[origin]).toBeTruthy();
    }
    expect(QUOTATION_RESPONSE_ORIGIN_LABELS).toEqual({
      customer: 'Cliente',
      agent: 'Agente',
    });
  });
});

describe('isQuotationTerminal', () => {
  it('is true only for accepted and voided', () => {
    for (const status of ALL_STATUSES) {
      expect(isQuotationTerminal(status)).toBe(status === 'accepted' || status === 'voided');
    }
  });
});

describe('isQuotationFrozen', () => {
  it('is true for every status except draft', () => {
    for (const status of ALL_STATUSES) {
      expect(isQuotationFrozen(status)).toBe(status !== 'draft');
    }
  });
});

describe('isQuotationOpen', () => {
  it('is true only for issued', () => {
    for (const status of ALL_STATUSES) {
      expect(isQuotationOpen(status)).toBe(status === 'issued');
    }
  });
});

describe('canClientComputeTotals', () => {
  it('is false: the client never totals the breakdown', () => {
    expect(canClientComputeTotals).toBe(false);
  });

  it('exports no function that sums or totals amounts', () => {
    const functionNames = Object.entries(quotationModel)
      .filter(([, value]) => typeof value === 'function')
      .map(([name]) => name);
    expect(functionNames.some((name) => /^(sum|total|compute)/i.test(name))).toBe(false);
  });
});
