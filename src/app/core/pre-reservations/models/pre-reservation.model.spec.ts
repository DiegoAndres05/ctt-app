import {
  ITEM_KIND_LABELS,
  PRE_RESERVATION_STATUS_LABELS,
  isPreReservationClosed,
  quoteEligibilityReason,
  type PreReservationStatus,
} from './pre-reservation.model';
import {
  AVAILABILITY_EVENT_KIND_LABELS,
  AVAILABILITY_STATUS_LABELS,
  CONTACT_METHOD_LABELS,
  type AvailabilityEventKind,
  type AvailabilityStatus,
  type ProviderContactMethod,
} from './verification.model';

const ALL_PRE_RESERVATION_STATUSES: readonly PreReservationStatus[] = [
  'pending_verification',
  'partially_verified',
  'verified',
  'requires_adjustment',
  'expired',
  'cancelled',
];

const ALL_AVAILABILITY_STATUSES: readonly AvailabilityStatus[] = [
  'pending',
  'available',
  'unavailable',
  'alternative_suggested',
];

const ALL_CONTACT_METHODS: readonly ProviderContactMethod[] = [
  'phone',
  'whatsapp',
  'email',
  'other',
];

const ALL_EVENT_KINDS: readonly AvailabilityEventKind[] = [
  'item_added',
  'verification_started',
  'outcome_recorded',
  'item_withdrawn',
  'alternative_promoted',
  'pre_reservation_cancelled',
  'quote_override_authorized',
];

describe('isPreReservationClosed', () => {
  it('is true only for cancelled', () => {
    for (const status of ALL_PRE_RESERVATION_STATUSES) {
      expect(isPreReservationClosed(status)).toBe(status === 'cancelled');
    }
  });
});

describe('quoteEligibilityReason', () => {
  it('returns null for a verified pre-reservation', () => {
    expect(quoteEligibilityReason({ status: 'verified', quote_eligible: true })).toBeNull();
  });

  it('returns null whenever an admin exception keeps it eligible', () => {
    expect(
      quoteEligibilityReason({ status: 'pending_verification', quote_eligible: true }),
    ).toBeNull();
    expect(
      quoteEligibilityReason({ status: 'partially_verified', quote_eligible: true }),
    ).toBeNull();
    expect(
      quoteEligibilityReason({ status: 'requires_adjustment', quote_eligible: true }),
    ).toBeNull();
    expect(quoteEligibilityReason({ status: 'expired', quote_eligible: true })).toBeNull();
  });

  it('explains a pending or partially verified pre-reservation', () => {
    const reason = 'aún no está totalmente verificada';
    expect(quoteEligibilityReason({ status: 'pending_verification', quote_eligible: false })).toBe(
      reason,
    );
    expect(quoteEligibilityReason({ status: 'partially_verified', quote_eligible: false })).toBe(
      reason,
    );
  });

  it('explains each remaining ineligible state', () => {
    expect(quoteEligibilityReason({ status: 'requires_adjustment', quote_eligible: false })).toBe(
      'tiene servicios por ajustar',
    );
    expect(quoteEligibilityReason({ status: 'expired', quote_eligible: false })).toBe(
      'la disponibilidad confirmada venció',
    );
    expect(quoteEligibilityReason({ status: 'cancelled', quote_eligible: false })).toBe(
      'está cancelada',
    );
  });
});

describe('labels', () => {
  it('labels every pre-reservation and availability status', () => {
    for (const status of ALL_PRE_RESERVATION_STATUSES) {
      expect(PRE_RESERVATION_STATUS_LABELS[status]).toBeTruthy();
    }
    for (const status of ALL_AVAILABILITY_STATUSES) {
      expect(AVAILABILITY_STATUS_LABELS[status]).toBeTruthy();
    }
  });

  it('labels every contact method and event kind', () => {
    for (const method of ALL_CONTACT_METHODS) {
      expect(CONTACT_METHOD_LABELS[method]).toBeTruthy();
    }
    for (const kind of ALL_EVENT_KINDS) {
      expect(AVAILABILITY_EVENT_KIND_LABELS[kind]).toBeTruthy();
    }
  });

  it('labels every item kind', () => {
    for (const kind of ['experience', 'accommodation', 'package', 'addon'] as const) {
      expect(ITEM_KIND_LABELS[kind]).toBeTruthy();
    }
  });
});
