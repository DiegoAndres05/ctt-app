import type { PreReservationItemKind, PreReservationStatus } from './pre-reservation.model';

/**
 * Availability verification domain types (feature 004, US2/US4).
 *
 * Row shapes mirror the `public.availability_verification_queue` and
 * `public.availability_verification_history` views column-for-column. The history is
 * append-only in the database; this module only reads it.
 */

/** Mirrors `public.availability_status`. */
export type AvailabilityStatus = 'pending' | 'available' | 'unavailable' | 'alternative_suggested';

/** Outcomes `record_item_verification` accepts; `pending` is not recordable. */
export type RecordableAvailabilityStatus = Exclude<AvailabilityStatus, 'pending'>;

/** Mirrors `public.provider_contact_method`. */
export type ProviderContactMethod = 'phone' | 'whatsapp' | 'email' | 'other';

/** Mirrors `public.availability_event_kind`. */
export type AvailabilityEventKind =
  | 'item_added'
  | 'verification_started'
  | 'outcome_recorded'
  | 'item_withdrawn'
  | 'alternative_promoted'
  | 'pre_reservation_cancelled'
  | 'quote_override_authorized';

/** A row of the `public.availability_verification_queue` view (one per active line). */
export interface VerificationQueueRow {
  item_id: string;
  organization_id: string;
  pre_reservation_id: string;
  reference: string;
  pre_reservation_status: PreReservationStatus;
  is_alternative: boolean;
  alternative_of_item_id: string | null;
  item_kind: PreReservationItemKind;
  item_label: string;
  start_date: string;
  end_date: string | null;
  adults: number;
  children: number;
  quantity: number;
  provider_id: string | null;
  provider_name: string | null;
  provider_phone: string | null;
  provider_email: string | null;
  verification_status: AvailabilityStatus;
  verification_started_at: string | null;
  verified_at: string | null;
  verified_by_name: string | null;
  provider_contact_person: string | null;
  hold_expires_at: string | null;
  hold_expired: boolean;
  needs_action: boolean;
  assigned_operator_id: string | null;
  assigned_operator_name: string | null;
  customer_first_name: string;
  customer_last_name: string | null;
  customer_is_anonymized: boolean;
  item_created_at: string;
}

/** A row of the `public.availability_verification_history` view (US4). */
export interface VerificationEvent {
  id: number;
  organization_id: string;
  pre_reservation_id: string;
  reference: string;
  item_id: string | null;
  item_label: string | null;
  event_kind: AvailabilityEventKind;
  from_status: AvailabilityStatus | null;
  to_status: AvailabilityStatus | null;
  provider_contact_person: string | null;
  contact_method: ProviderContactMethod | null;
  hold_expires_at: string | null;
  notes: string | null;
  metadata: Record<string, unknown>;
  actor_id: string;
  actor_name: string | null;
  created_at: string;
}

/** Payload of `record_item_verification` (contracts §3.3). */
export interface VerificationOutcomePayload {
  status: RecordableAvailabilityStatus;
  contact_person: string;
  contact_method: ProviderContactMethod;
  /** ISO timestamp; only honored with `available`, and must be in the future. */
  hold_expires_at: string | null;
  /** Required with `alternative_suggested`. */
  alternative_suggestion: string | null;
  notes: string | null;
}

/** Body returned by `record_item_verification`. */
export interface RecordOutcomeResult {
  item_id: string;
  verification_status: AvailabilityStatus;
  pre_reservation_status: PreReservationStatus;
  expires_at: string | null;
}

export const AVAILABILITY_STATUS_LABELS: Record<AvailabilityStatus, string> = {
  pending: 'Pendiente',
  available: 'Disponible',
  unavailable: 'No disponible',
  alternative_suggested: 'Alternativa sugerida',
};

export const CONTACT_METHOD_LABELS: Record<ProviderContactMethod, string> = {
  phone: 'Llamada',
  whatsapp: 'WhatsApp',
  email: 'Correo',
  other: 'Otro',
};

export const AVAILABILITY_EVENT_KIND_LABELS: Record<AvailabilityEventKind, string> = {
  item_added: 'Servicio agregado',
  verification_started: 'Gestión iniciada',
  outcome_recorded: 'Resultado registrado',
  item_withdrawn: 'Servicio retirado',
  alternative_promoted: 'Alternativa promovida',
  pre_reservation_cancelled: 'Pre-reserva cancelada',
  quote_override_authorized: 'Excepción para cotizar autorizada',
};
