import {
  RESERVATION_STATUS_LABELS,
  canClientSumPayments,
  isReservationTerminal,
  publicVoucherUrl,
  reservationTokenStorageKey,
  type ReservationStatus,
} from './reservation.model';

const ALL_STATUSES: readonly ReservationStatus[] = [
  'confirmed',
  'in_progress',
  'completed',
  'cancelled',
  'superseded',
];

describe('RESERVATION_STATUS_LABELS', () => {
  it('uses the Spanish labels from the contract', () => {
    expect(RESERVATION_STATUS_LABELS).toEqual({
      confirmed: 'Confirmada',
      in_progress: 'En ejecución',
      completed: 'Completada',
      cancelled: 'Cancelada',
      superseded: 'Superada',
    });
  });

  it('labels every status', () => {
    for (const status of ALL_STATUSES) {
      expect(RESERVATION_STATUS_LABELS[status]).toBeTruthy();
    }
  });
});

describe('isReservationTerminal', () => {
  it('treats completed and cancelled as terminal', () => {
    expect(isReservationTerminal('completed')).toBe(true);
    expect(isReservationTerminal('cancelled')).toBe(true);
    expect(isReservationTerminal('confirmed')).toBe(false);
    expect(isReservationTerminal('in_progress')).toBe(false);
    expect(isReservationTerminal('superseded')).toBe(false);
  });
});

describe('canClientSumPayments', () => {
  it('is always false', () => {
    expect(canClientSumPayments).toBe(false);
  });
});

describe('reservationTokenStorageKey', () => {
  it('scopes the sessionStorage key to the family', () => {
    expect(reservationTokenStorageKey('abc')).toBe('reservation-token:abc');
  });
});

describe('publicVoucherUrl', () => {
  const origin = 'http://localhost:4201';

  it('keeps a base64url token as-is in a single /r/ segment', () => {
    const token = 'hkNqKEZfk5tZW4yX9YGCY0TmS_n5ZW_sDq-e09699Oo';
    expect(publicVoucherUrl(origin, token)).toBe(`${origin}/r/${token}`);
  });

  it('percent-encodes a legacy standard-base64 token so "/" does not split the route', () => {
    const legacy = 'hkNq/KEZ+fk5=';
    const url = publicVoucherUrl(origin, legacy);
    expect(url).toBe(`${origin}/r/hkNq%2FKEZ%2Bfk5%3D`);
    const segment = url.slice(`${origin}/r/`.length);
    expect(segment).not.toContain('/');
    expect(decodeURIComponent(segment)).toBe(legacy);
  });
});
