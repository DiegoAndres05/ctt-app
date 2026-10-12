import type { ChargeType } from '../../catalog/models/pricing.model';
import type { PreReservationItemKind } from '../../pre-reservations/models/pre-reservation.model';

/**
 * Quotation domain types (feature 005).
 *
 * Row shapes mirror `public.quotation_list`, `public.quotation_versions`,
 * `public.quotation_lines` and `public.quotation_adjustments` column-for-column, and the
 * breakdown JSON the quotation RPCs return (specs/005-quotation-proposals/contracts).
 * The server owns every amount: this module only types what it receives (FR-002).
 */

/** Mirrors `public.quotation_status` (042_quotation_enums.sql). */
export type QuotationStatus =
  'draft' | 'issued' | 'accepted' | 'rejected' | 'expired' | 'voided' | 'superseded';

/** Mirrors `public.quotation_adjustment_direction`. */
export type QuotationAdjustmentDirection = 'discount' | 'surcharge';

/** Mirrors `public.quotation_adjustment_kind`. */
export type QuotationAdjustmentKind = 'percent' | 'amount';

/** Mirrors `public.quotation_response_kind`. */
export type QuotationResponseKind = 'accepted' | 'rejected' | 'changes_requested';

/** Mirrors `public.quotation_response_origin`. */
export type QuotationResponseOrigin = 'customer' | 'agent';

/** A row of the `public.quotation_list` view: no e-mail, phone or token (data-model §View). */
export interface QuotationListRow {
  version_id: string;
  family_id: string;
  organization_id: string;
  /** `COT-#####`; null until the first version of the family is issued. */
  reference: string | null;
  version_number: number;
  status: QuotationStatus;
  customer_id: string;
  customer_first_name: string;
  customer_last_name: string | null;
  customer_is_anonymized: boolean;
  pre_reservation_id: string;
  pre_reservation_reference: string;
  currency: string;
  total: number;
  valid_until: string | null;
  issued_at: string | null;
  created_at: string;
  created_by: string | null;
  agent_name: string | null;
}

/** A row of `public.quotation_versions` (data-model §2). */
export interface QuotationVersion {
  id: string;
  organization_id: string;
  family_id: string;
  version_number: number;
  status: QuotationStatus;
  currency: string;
  subtotal: number;
  tax_total: number;
  adjustment_total: number;
  total: number;
  /** `{ "USD": 4100.00 }`, frozen on issue. */
  exchange_rates: Record<string, number>;
  party_adults: number;
  party_children: number;
  inclusions: string;
  exclusions: string;
  terms: string;
  commercial_notes: string | null;
  valid_until: string | null;
  issued_at: string | null;
  issued_by: string | null;
  accepted_at: string | null;
  rejected_at: string | null;
  expired_at: string | null;
  voided_at: string | null;
  voided_by: string | null;
  void_reason: string | null;
  superseded_at: string | null;
  pre_reservation_fingerprint: Record<string, unknown> | null;
  response_origin: QuotationResponseOrigin | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

/** A row of `public.quotation_lines`: one line of the server-side breakdown (data-model §3). */
export interface QuotationLine {
  id: string;
  organization_id: string;
  version_id: string;
  pre_reservation_item_id: string;
  position: number;
  item_kind: PreReservationItemKind;
  /** Snapshot of the product or add-on name at creation time. */
  item_label: string;
  product_id: string | null;
  addon_id: string | null;
  start_date: string;
  end_date: string | null;
  adults: number;
  children: number;
  quantity: number;
  charge_type: ChargeType;
  charge_basis: number;
  tariff_currency: string;
  tariff_amount: number;
  /** Null when the tariff currency matches the quotation currency. */
  exchange_rate: number | null;
  /** Already expressed in the quotation currency. */
  unit_price: number;
  tax_rate: number;
  line_base: number;
  line_adjustment: number;
  line_tax: number;
  line_total: number;
  created_at: string;
}

/** A row of `public.quotation_adjustments` (data-model §4). */
export interface QuotationAdjustment {
  id: string;
  organization_id: string;
  version_id: string;
  /** Null = adjustment over the whole version. */
  pre_reservation_item_id: string | null;
  label: string;
  direction: QuotationAdjustmentDirection;
  kind: QuotationAdjustmentKind;
  /** > 0; when `percent`, at most 100. */
  value: number;
  created_by: string | null;
  created_at: string;
}

/** A row of `public.quotation_responses` (append-only, data-model §5). */
export interface QuotationResponse {
  id: number;
  organization_id: string;
  version_id: string;
  kind: QuotationResponseKind;
  origin: QuotationResponseOrigin;
  /** Null when the origin is the customer (public link). */
  created_by: string | null;
  created_at: string;
}

/** Payload of `upsert_quotation_adjustment` (contracts §2). */
export interface QuotationAdjustmentInput {
  /** Null = global adjustment over the whole version. */
  pre_reservation_item_id: string | null;
  label: string;
  direction: QuotationAdjustmentDirection;
  kind: QuotationAdjustmentKind;
  value: number;
}

/** Payload of `set_quotation_texts` (contracts §2). */
export interface QuotationTextsInput {
  inclusions: string;
  exclusions: string;
  /** Stored as `commercial_notes`, panel-only. */
  notes: string;
}

/**
 * Server-side price breakdown of one version (contracts §2).
 *
 * The UI only paints these fields: FR-002 forbids the client from summing or
 * recomputing anything (`canClientComputeTotals` below).
 */
export interface QuotationBreakdown {
  version_id: string;
  version_number: number;
  status: QuotationStatus;
  currency: string;
  subtotal: number;
  tax_total: number;
  adjustment_total: number;
  total: number;
  lines: QuotationLine[];
  /** Currencies still missing an exchange rate; empty when the version can be issued. */
  pending_currencies?: string[];
}

/** Body returned by `create_quotation_draft` (contracts §2). */
export interface CreateQuotationDraftResult extends QuotationBreakdown {
  family_id: string;
  pending_currencies: string[];
}

/** Version + family reference + lines + adjustments: everything the detail screen reads. */
export interface QuotationDetail extends QuotationVersion {
  /** `COT-#####` from the family; null until the first version is issued. */
  reference: string | null;
  lines: QuotationLine[];
  adjustments: QuotationAdjustment[];
}

/** One line of the public proposal (contracts §4): label and amounts only, no ids. */
export interface PublicQuotationLine {
  label: string;
  kind: PreReservationItemKind;
  start_date: string;
  end_date: string | null;
  charge_basis: number;
  unit_price: number;
  tax_rate: number;
  line_total: number;
}

/** One adjustment of the public proposal (contracts §4). */
export interface PublicQuotationAdjustment {
  label: string;
  direction: QuotationAdjustmentDirection;
  kind: QuotationAdjustmentKind;
  value: number;
}

/** Body of `get_public_quotation` for an unknown token or a voided link (contracts §4). */
export interface PublicQuotationUnavailable {
  available: false;
}

/** Body of `get_public_quotation` for the family's current version (contracts §4). */
export interface PublicQuotationAvailable {
  available: true;
  status: QuotationStatus;
  reference: string | null;
  version_number: number;
  currency: string;
  valid_until: string | null;
  party_adults: number;
  party_children: number;
  inclusions: string;
  exclusions: string;
  terms: string;
  subtotal: number;
  tax_total: number;
  adjustment_total: number;
  total: number;
  lines: PublicQuotationLine[];
  adjustments: PublicQuotationAdjustment[];
  can_accept: boolean;
}

/**
 * Discriminated body of `get_public_quotation` (contracts §4): the server decides what the
 * client sees. It never carries `customer_id`, e-mail, phone, notes, the pre-reservation
 * or the token, and the public screen must not add any of those (FR-007).
 */
export type PublicQuotation = PublicQuotationUnavailable | PublicQuotationAvailable;

export const QUOTATION_STATUS_LABELS: Record<QuotationStatus, string> = {
  draft: 'Borrador',
  issued: 'Emitida',
  accepted: 'Aceptada',
  rejected: 'Rechazada',
  expired: 'Expirada',
  voided: 'Anulada',
  superseded: 'Superada por nueva versión',
};

export const QUOTATION_ADJUSTMENT_DIRECTION_LABELS: Record<QuotationAdjustmentDirection, string> = {
  discount: 'Descuento',
  surcharge: 'Suplemento',
};

export const QUOTATION_ADJUSTMENT_KIND_LABELS: Record<QuotationAdjustmentKind, string> = {
  percent: 'Porcentaje',
  amount: 'Monto fijo',
};

export const QUOTATION_RESPONSE_KIND_LABELS: Record<QuotationResponseKind, string> = {
  accepted: 'Aceptada',
  rejected: 'Rechazada',
  changes_requested: 'Requiere modificaciones',
};

export const QUOTATION_RESPONSE_ORIGIN_LABELS: Record<QuotationResponseOrigin, string> = {
  customer: 'Cliente',
  agent: 'Agente',
};

/**
 * Disabled by contract (FR-002): every amount comes from the server breakdown.
 * There is deliberately no sum function in this module.
 */
export const canClientComputeTotals = false;

/** «Aceptada» y «Anulada» son terminales (FR-005): they admit no further transition. */
export function isQuotationTerminal(status: QuotationStatus): boolean {
  return status === 'accepted' || status === 'voided';
}

/**
 * The `QUOTATION_FROZEN` rule (FR-008): outside `draft` the amounts, commercial texts,
 * exchange rates and validity are immutable — any change means a new version.
 */
export function isQuotationFrozen(status: QuotationStatus): boolean {
  return status !== 'draft';
}

/** Only an `issued` version admits a response; anything else raises `QUOTATION_NOT_OPEN`. */
export function isQuotationOpen(status: QuotationStatus): boolean {
  return status === 'issued';
}
