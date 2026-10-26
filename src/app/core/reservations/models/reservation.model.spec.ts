import {
  RESERVATION_STATUS_LABELS,
  canClientSumPayments,
  isReservationTerminal,
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
