/**
 * Reservation domain types (feature 006).
 *
 * Row shapes mirror `public.reservation_list`, `reservation_versions`, passengers, items
 * and payments. The UI paints `paid_total` and `balance` from the server and never sums
 * them (`canClientSumPayments`).
 */

export type ReservationStatus =
  'confirmed' | 'in_progress' | 'completed' | 'cancelled' | 'superseded';

export type ReservationItemOpsStatus =
  'pending_provider' | 'confirmed_with_provider' | 'in_service' | 'completed' | 'provider_failed';

export type PaymentMethod = 'bank_transfer' | 'cash' | 'card_manual' | 'other';

export type IdDocumentType = 'cc' | 'ce' | 'passport' | 'ti' | 'other';

export type ProviderNotifyChannel = 'whatsapp_copy' | 'email_copy' | 'print';

export interface ReservationListRow {
  version_id: string;
  family_id: string;
  organization_id: string;
  reference: string;
  version_number: number;
  status: ReservationStatus;
  customer_id: string;
  customer_first_name: string;
  customer_last_name: string | null;
  customer_is_anonymized: boolean;
  quotation_version_id: string;
  quotation_reference: string | null;
  currency: string;
  total: number;
  paid_total: number;
  balance: number;
  travel_start_date: string;
  travel_end_date: string | null;
  created_at: string;
  created_by: string | null;
}

export interface ReservationVersion {
  id: string;
  organization_id: string;
  family_id: string;
  version_number: number;
  status: ReservationStatus;
  currency: string;
  total: number;
  travel_start_date: string;
  travel_end_date: string | null;
  party_adults: number;
  party_children: number;
  terms: string;
  assistance_phones: string;
  contingency_report: string | null;
  cancelled_at: string | null;
  cancel_reason: string | null;
  cancelled_by: string | null;
  status_changed_at: string | null;
  status_changed_by: string | null;
  created_by: string | null;
  created_at: string;
}

export interface ReservationPassenger {
  id: string;
  organization_id: string;
  version_id: string;
  position: number;
  first_name: string;
  last_name: string;
  document_type: IdDocumentType;
  document_number: string;
  date_of_birth: string | null;
  special_requirements: string | null;
  created_at: string;
}

export interface ReservationItem {
  id: string;
  organization_id: string;
  version_id: string;
  quotation_line_ref: string | null;
  pre_reservation_item_id: string | null;
  position: number;
  item_kind: string;
  item_label: string;
  product_id: string | null;
  addon_id: string | null;
  start_date: string;
  end_date: string | null;
  adults: number;
  children: number;
  quantity: number;
  line_total: number;
  provider_id: string | null;
  ops_status: ReservationItemOpsStatus;
  provider_notified_at: string | null;
  provider_notify_channel: ProviderNotifyChannel | null;
  reassign_reason: string | null;
  created_at: string;
}

export interface ReservationPayment {
  id: string;
  organization_id: string;
  family_id: string;
  amount: number;
  currency: string;
  paid_on: string;
  method: PaymentMethod;
  transfer_reference: string;
  receipt_path: string | null;
  recorded_by: string | null;
  created_at: string;
}

export interface ReservationFamily {
  id: string;
  organization_id: string;
  quotation_version_id: string;
  quotation_family_id: string;
  customer_id: string;
  reference: string;
}

export interface ReservationDetail extends ReservationVersion {
  reference: string;
  quotation_version_id: string;
  quotation_reference: string | null;
  paid_total: number;
  balance: number;
  passengers: ReservationPassenger[];
  items: ReservationItem[];
  payments: ReservationPayment[];
}

export interface ConfirmReservationResult {
  family_id: string;
  version_id: string;
  reference: string;
  voucher_token: string;
  total: number;
  currency: string;
}

export interface ReservationDepositInput {
  amount: number;
  currency: string;
  paid_on: string;
  method: PaymentMethod;
  transfer_reference: string;
  receipt_path?: string | null;
}

export interface ReservationPassengerInput {
  first_name: string;
  last_name: string;
  document_type: IdDocumentType;
  document_number: string;
  date_of_birth?: string | null;
  special_requirements?: string | null;
}

export interface PublicVoucherUnavailable {
  available: false;
}

export interface PublicVoucherAvailable {
  available: true;
  reference: string;
  status: ReservationStatus;
  travel_start_date: string;
  travel_end_date: string | null;
  terms: string;
  assistance_phones: string;
  passengers: { first_name: string; last_name: string }[];
  items: {
    title: string;
    start_date: string;
    end_date: string | null;
    quantity: number;
  }[];
}

export type PublicVoucher = PublicVoucherUnavailable | PublicVoucherAvailable;

export const RESERVATION_STATUS_LABELS: Record<ReservationStatus, string> = {
  confirmed: 'Confirmada',
  in_progress: 'En ejecución',
  completed: 'Completada',
  cancelled: 'Cancelada',
  superseded: 'Superada',
};

export const RESERVATION_OPS_STATUS_LABELS: Record<ReservationItemOpsStatus, string> = {
  pending_provider: 'Pendiente con proveedor',
  confirmed_with_provider: 'Confirmada con proveedor',
  in_service: 'En servicio',
  completed: 'Completada',
  provider_failed: 'Fallida con proveedor',
};

export const PAYMENT_METHOD_LABELS: Record<PaymentMethod, string> = {
  bank_transfer: 'Transferencia',
  cash: 'Efectivo',
  card_manual: 'Tarjeta (manual)',
  other: 'Otro',
};

export const ID_DOCUMENT_TYPE_LABELS: Record<IdDocumentType, string> = {
  cc: 'Cédula',
  ce: 'Cédula de extranjería',
  passport: 'Pasaporte',
  ti: 'Tarjeta de identidad',
  other: 'Otro',
};

/** Disabled by contract: the UI never sums payments or totals. */
export const canClientSumPayments = false;

export function isReservationTerminal(status: ReservationStatus): boolean {
  return status === 'completed' || status === 'cancelled';
}

export function reservationTokenStorageKey(familyId: string): string {
  return `reservation-token:${familyId}`;
}

/**
 * Public voucher link (`/r/<token>`). Tokens issued since migration 057 are base64url and need
 * no escaping; tokens issued before it are standard base64 and may contain `/`, `+` or `=`, so
 * the token is always percent-encoded to keep it in a single route segment.
 */
export function publicVoucherUrl(origin: string, token: string): string {
  return `${origin}/r/${encodeURIComponent(token)}`;
}
