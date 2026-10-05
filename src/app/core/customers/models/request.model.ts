import type { Customer } from './customer.model';

/** Mirrors `public.request_channel`. */
export type RequestChannel = 'web' | 'whatsapp' | 'phone' | 'in_person';

/** Mirrors `public.request_status`. */
export type RequestStatus = 'received' | 'in_review' | 'discarded' | 'pre_reservation';

/** Statuses a collaborator may set. `pre_reservation` belongs to feature 004. */
export type ManualRequestStatus = 'in_review' | 'discarded';

export interface SubmittedContact {
  first_name?: string;
  last_name?: string | null;
  email?: string | null;
  phone_e164?: string | null;
  country_code?: string | null;
}

/** A row of `public.customer_request_list`. */
export interface RequestListRow {
  id: string;
  organization_id: string;
  reference: string;
  channel: RequestChannel;
  status: RequestStatus;
  created_at: string;
  travel_start_date: string | null;
  travel_end_date: string | null;
  adults: number;
  children: number;
  contact_review_required: boolean;
  assigned_to: string | null;
  assignee_name: string | null;
  customer_id: string;
  customer_first_name: string;
  customer_last_name: string | null;
  customer_email: string | null;
  customer_phone_e164: string | null;
  customer_is_anonymized: boolean;
  item_count: number;
}

export interface RequestItem {
  id: string;
  product_id: string | null;
  public_slug: string | null;
  free_text: string | null;
  quantity: number;
  position: number;
  product: { id: string; name: string; product_type: string } | null;
}

/** Request row plus the embeds the detail screen reads. */
export interface RequestDetail {
  id: string;
  organization_id: string;
  reference: string;
  customer_id: string;
  channel: RequestChannel;
  status: RequestStatus;
  assigned_to: string | null;
  assigned_at: string | null;
  travel_start_date: string | null;
  travel_end_date: string | null;
  adults: number;
  children: number;
  special_requirements: string | null;
  locale: string | null;
  source_page: string | null;
  submitted_contact: SubmittedContact | null;
  contact_review_required: boolean;
  privacy_consent_at: string | null;
  discard_reason: string | null;
  first_handled_at: string | null;
  closed_at: string | null;
  created_at: string;
  customer: Customer;
  items: RequestItem[];
  assignee: { id: string; full_name: string } | null;
}

export interface InboundMessage {
  id: string;
  profile_name: string | null;
  message_type: string;
  body: string;
  provider_timestamp: string;
}

export interface RequestNote {
  id: string;
  request_id: string | null;
  customer_id: string | null;
  author_id: string;
  content: string;
  created_at: string;
  author: { full_name: string } | null;
}

/** Body returned by `capture_request_core` and `create_assisted_request`. */
export interface CaptureResult {
  request_id: string;
  reference: string;
  customer_id: string;
  customer_created: boolean;
  deduplicated: boolean;
  contact_review_required: boolean;
}

export const REQUEST_CHANNEL_LABELS: Record<RequestChannel, string> = {
  web: 'Web',
  whatsapp: 'WhatsApp',
  phone: 'Teléfono',
  in_person: 'Presencial',
};

export const REQUEST_STATUS_LABELS: Record<RequestStatus, string> = {
  received: 'Recibida',
  in_review: 'En gestión',
  discarded: 'Descartada',
  pre_reservation: 'En pre-reserva',
};

export const ASSISTED_CHANNELS = ['whatsapp', 'phone', 'in_person'] as const;

export type AssistedChannel = (typeof ASSISTED_CHANNELS)[number];

export function isRequestClosed(status: RequestStatus): boolean {
  return status === 'discarded' || status === 'pre_reservation';
}

/**
 * Buttons the detail screen may show.
 * Affordance only: `set_request_status` is the authority and rejects `pre_reservation`.
 */
export function availableStatusActions(status: RequestStatus): ManualRequestStatus[] {
  if (status === 'received') {
    return ['in_review', 'discarded'];
  }
  if (status === 'in_review') {
    return ['discarded'];
  }
  return [];
}
