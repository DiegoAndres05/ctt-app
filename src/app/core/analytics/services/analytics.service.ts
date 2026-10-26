import { inject, Injectable } from '@angular/core';
import { SupabaseService } from '../../auth/services/supabase.service';
import { toAppError } from '../../error/error-handler';
import type {
  FunnelReport,
  OpsTimesReport,
  ProductRankRow,
  SalesSummary,
  StaleItem,
} from '../models/analytics.model';

@Injectable({ providedIn: 'root' })
export class AnalyticsService {
  private readonly supabase = inject(SupabaseService);

  async funnel(from: string, to: string, channel: string | null): Promise<FunnelReport> {
    const { data, error } = await this.supabase.client.rpc('analytics_funnel', {
      p_from: from,
      p_to: to,
      p_channel: channel,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as FunnelReport;
  }

  async opsTimes(from: string, to: string, channel: string | null): Promise<OpsTimesReport> {
    const { data, error } = await this.supabase.client.rpc('analytics_ops_times', {
      p_from: from,
      p_to: to,
      p_channel: channel,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as OpsTimesReport;
  }

  async staleQueue(): Promise<StaleItem[]> {
    const { data, error } = await this.supabase.client.rpc('analytics_stale_queue');
    if (error) {
      throw toAppError(error);
    }
    return ((data as { items?: StaleItem[] } | null)?.items ?? []) as StaleItem[];
  }

  async salesSummary(from: string, to: string): Promise<SalesSummary[]> {
    const { data, error } = await this.supabase.client.rpc('analytics_sales_summary', {
      p_from: from,
      p_to: to,
    });
    if (error) {
      throw toAppError(error);
    }
    return ((data as { currencies?: SalesSummary[] } | null)?.currencies ?? []) as SalesSummary[];
  }

  async productRanking(from: string, to: string, limit = 20): Promise<ProductRankRow[]> {
    const { data, error } = await this.supabase.client.rpc('analytics_product_ranking', {
      p_from: from,
      p_to: to,
      p_limit: limit,
    });
    if (error) {
      throw toAppError(error);
    }
    return ((data as { rows?: ProductRankRow[] } | null)?.rows ?? []) as ProductRankRow[];
  }

  downloadCsv(filename: string, rows: Record<string, unknown>[]): void {
    const keys = rows.length > 0 ? Object.keys(rows[0]!) : [];
    const lines = [
      keys.join(','),
      ...rows.map((row) => keys.map((key) => csvCell(row[key])).join(',')),
    ];
    const blob = new Blob(['\uFEFF' + lines.join('\n')], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  }
}

function csvCell(value: unknown): string {
  const text = value == null ? '' : String(value);
  if (/[",\n]/.test(text)) {
    return `"${text.replaceAll('"', '""')}"`;
  }
  return text;
}
