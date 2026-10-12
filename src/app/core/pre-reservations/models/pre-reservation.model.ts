import type { RequestStatus } from '../../customers/models/request.model';
import type { AvailabilityStatus, ProviderContactMethod } from './verification.model';

/**
 * Pre-reservation domain types (feature 004).
 *
 * Row shapes mirror `public.pre_reservations`, `public.pre_reservation_items` and the
 * `public.pre_reservation_list` view column-for-column. The global status is derived and
 * persisted by `refresh_pre_reservation_status` (migration 037); this module only reads it.
 */

/** Mirrors `public.pre_reservation_status`. */
export type PreReservationStatus =
  | 'pending_verification'
  | 'partially_verified'
  | 'verified'
  | 'requires_adjustment'
  | 'expired'
  | 'cancelled';

/** Mirrors the `item_kind` CHECK on `public.pre_reservation_items`. */
export type PreReservationItemKind = 'experience' | 'accommodation' | 'package' | 'addon';

/** A row of the `public.pre_reservation_list` view. */
export interface PreReservationListRow {
  id: string;
  organization_id: string;
  reference: string;
  status: PreReservationStatus;
  request_id: string;
  request_reference: string;
  customer_id: string;
  customer_first_name: string;
  customer_last_name: string | null;
  customer_is_anonymized: boolean;
  responsible_agent_id: string;
  responsible_agent_name: string;
  assigned_operator_id: string | null;
  assigned_operator_name: string | null;
  created_at: string;
  verified_at: string | null;
  first_verified_at: string | null;
  expires_at: string | null;
  cancelled_at: string | null;
  has_quote_override: boolean;
  quote_eligible: boolean;
  first_service_date: string | null;
  primary_item_count: number;
  available_item_count: number;
}

/** A row of `public.pre_reservations`. */
export interface PreReservation {
  id: string;
  organization_id: string;
  reference: string;
  request_id: string;
  customer_id: string;
  responsible_agent_id: string;
  assigned_operator_id: string | null;
  status: PreReservationStatus;
  expires_at: string | null;
  verified_at: string | null;
  first_verified_at: string | null;
  cancelled_at: string | null;
  cancel_reason: string | null;
  cancelled_by: string | null;
  quote_override_at: string | null;
  quote_override_by: string | null;
  quote_override_reason: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

/** A row of `public.pre_reservation_items`, plus the verifier embed the detail screen reads. */
export interface PreReservationItem {
  id: string;
  organization_id: string;
  pre_reservation_id: string;
  position: number;
  alternative_of_item_id: string | null;
  item_kind: PreReservationItemKind;
  product_id: string | null;
  addon_id: string | null;
  source_request_item_id: string | null;
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
  verified_by: string | null;
  verified_at: string | null;
  provider_contact_person: string | null;
  contact_method: ProviderContactMethod | null;
  hold_expires_at: string | null;
  alternative_suggestion: string | null;
  operator_notes: string | null;
  withdrawn_at: string | null;
  withdrawn_reason: string | null;
  withdrawn_by: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  verifier: { full_name: string } | null;
}

/** Header row plus the embeds, lines (withdrawn included) and eligibility the detail reads. */
export interface PreReservationDetail extends PreReservation {
  request: { id: string; reference: string; status: RequestStatus } | null;
  customer: {
    id: string;
    first_name: string;
    last_name: string | null;
    is_anonymized: boolean;
  } | null;
  agent: { full_name: string } | null;
  operator: { full_name: string } | null;
  /** Admin who authorized the quotation exception (`quote_override_by` embed), for «Excepción autorizada por …». */
  override_by: { full_name: string } | null;
  items: PreReservationItem[];
  quote_eligible: boolean;
  has_quote_override: boolean;
}

/** A row of the `public.pre_reservation_verification_times` view (US4). */
export interface VerificationTimes {
  id: string;
  organization_id: string;
  reference: string;
  status: PreReservationStatus;
  created_at: string;
  first_started_at: string | null;
  first_verified_at: string | null;
  hours_to_first_start: number | null;
  hours_to_verified: number | null;
  item_count: number;
  verifier_count: number;
}

export const PRE_RESERVATION_STATUS_LABELS: Record<PreReservationStatus, string> = {
  pending_verification: 'Pendiente de verificación',
  partially_verified: 'Parcialmente verificada',
  verified: 'Totalmente verificada',
  requires_adjustment: 'Requiere ajuste',
  expired: 'Expirada',
  cancelled: 'Cancelada',
};

export const ITEM_KIND_LABELS: Record<PreReservationItemKind, string> = {
  experience: 'Experiencia',
  accommodation: 'Alojamiento',
  package: 'Paquete',
  addon: 'Complemento',
};

/** A cancelled pre-reservation is terminal: every screen stays read-only. */
export function isPreReservationClosed(status: PreReservationStatus): boolean {
  return status === 'cancelled';
}

/**
 * Why the pre-reservation is not quotable yet, for «No elegible para cotizar: <motivo>».
 *
 * Returns `null` when it is eligible: fully verified, or covered by an active admin
 * exception (`quote_eligible` from the view). The authority of the rule is
 * `assert_pre_reservation_quotable`; this only mirrors it for display (R-008).
 */
export function quoteEligibilityReason(detail: {
  status: PreReservationStatus;
  quote_eligible: boolean;
}): string | null {
  if (detail.quote_eligible) {
    return null;
  }
  switch (detail.status) {
    case 'pending_verification':
    case 'partially_verified':
      return 'aún no está totalmente verificada';
    case 'requires_adjustment':
      return 'tiene servicios por ajustar';
    case 'expired':
      return 'la disponibilidad confirmada venció';
    case 'cancelled':
      return 'está cancelada';
    case 'verified':
      // Unreachable: the view marks every verified pre-reservation eligible.
      return null;
  }
}
