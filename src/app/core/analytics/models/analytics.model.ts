export type FunnelStageId =
  | 'requests'
  | 'pre_reservations'
  | 'verified'
  | 'quotations_issued'
  | 'reservations_confirmed';

export interface FunnelStage {
  stage: FunnelStageId;
  label: string;
  count: number;
  conversion_from_previous: number | null;
  conversion_from_top: number | null;
}

export interface FunnelReport {
  from: string;
  to: string;
  channel: string | null;
  scope: 'org' | 'self';
  stages: FunnelStage[];
}

export interface OpsTimesReport {
  avg_request_response_hours: number | null;
  avg_verification_hours: number | null;
  avg_quotation_issue_hours: number | null;
  sample_request: number;
  sample_verification: number;
  sample_quotation: number;
}

export interface StaleItem {
  kind: 'request' | 'pre_reservation';
  id: string;
  reference: string;
  age_hours: number;
  status: string;
}

export interface SalesSummary {
  currency: string;
  gross: number;
  cancelled: number;
  net: number;
  paid_total: number;
  balance: number;
}

export interface ProductRankRow {
  product_id: string | null;
  item_label: string;
  item_kind: string;
  traveler_count: number;
  reservation_count: number;
  revenue: number;
  currency: string;
}

export const FUNNEL_STAGE_LABELS: Record<FunnelStageId, string> = {
  requests: 'Solicitudes',
  pre_reservations: 'Pre-reservas',
  verified: 'Verificadas',
  quotations_issued: 'Cotizaciones emitidas',
  reservations_confirmed: 'Reservas confirmadas',
};

/** Disabled by contract: rates and money come from the RPC. */
export const canClientComputeMetrics = false;

export function formatRate(value: number | null): string {
  if (value == null) {
    return '—';
  }
  return `${(value * 100).toFixed(1)} %`;
}
