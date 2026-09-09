import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { SupabaseService } from '../../auth/services/supabase.service';
import type { ChargeType, PricingScheme, ResolvedPrice } from '../models/pricing.model';

export interface UpsertPricingSchemeInput {
  productId?: string | null;
  addonId?: string | null;
  currency?: string | null;
  baseAmount: number;
  chargeType: ChargeType;
  seasonStart?: string | null;
  seasonEnd?: string | null;
}

export interface UpsertedPricingScheme {
  id: string;
  valid_from: string;
}

export interface ApplyPriceOverrideInput {
  productId: string;
  newAmount: number;
  reason: string;
  chargeType?: ChargeType | null;
}

export interface PriceOverrideResult {
  pricing_scheme_id: string;
  previous_amount: number;
  new_amount: number;
}

/**
 * Tenant-scoped tariff schemes. Listing goes through PostgREST (RLS). Definition, versioning
 * and admin overrides go through SECURITY DEFINER RPCs that re-check `app_role` and
 * `organization_id`. Amounts are never updated in place: a change closes `valid_to` and
 * inserts a new row.
 */
@Injectable({ providedIn: 'root' })
export class PricingService {
  private readonly supabase = inject(SupabaseService);

  async listForProduct(productId: string): Promise<PricingScheme[]> {
    const { data, error } = await this.supabase.client
      .from('pricing_schemes')
      .select('*')
      .eq('product_id', productId)
      .order('valid_from', { ascending: false })
      .returns<PricingScheme[]>();

    if (error) {
      throw toAppError(error);
    }

    return (data ?? []).map(coerceScheme);
  }

  async listCurrentForProduct(productId: string): Promise<PricingScheme[]> {
    const { data, error } = await this.supabase.client
      .from('pricing_schemes')
      .select('*')
      .eq('product_id', productId)
      .is('valid_to', null)
      .order('valid_from', { ascending: false })
      .returns<PricingScheme[]>();

    if (error) {
      throw toAppError(error);
    }

    return (data ?? []).map(coerceScheme);
  }

  async upsert(input: UpsertPricingSchemeInput): Promise<UpsertedPricingScheme> {
    const { data, error } = await this.supabase.client.rpc('upsert_pricing_scheme', {
      p_product_id: input.productId || null,
      p_addon_id: input.addonId || null,
      p_currency: input.currency?.trim().toUpperCase() || null,
      p_base_amount: input.baseAmount,
      p_charge_type: input.chargeType,
      p_season_start: input.seasonStart || null,
      p_season_end: input.seasonEnd || null,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as UpsertedPricingScheme;
  }

  async applyOverride(input: ApplyPriceOverrideInput): Promise<PriceOverrideResult> {
    const { data, error } = await this.supabase.client.rpc('apply_price_override', {
      p_product_id: input.productId,
      p_new_amount: input.newAmount,
      p_reason: input.reason.trim(),
      p_charge_type: input.chargeType || null,
    });

    if (error) {
      throw toAppError(error);
    }

    const row = data as {
      pricing_scheme_id: string;
      previous_amount: number | string;
      new_amount: number | string;
    };

    return {
      pricing_scheme_id: row.pricing_scheme_id,
      previous_amount: Number(row.previous_amount),
      new_amount: Number(row.new_amount),
    };
  }

  async resolvePrice(
    productId: string,
    onDate: string,
    chargeType: ChargeType,
  ): Promise<ResolvedPrice | null> {
    const { data, error } = await this.supabase.client.rpc('resolve_price', {
      p_product_id: productId,
      p_on_date: onDate,
      p_charge_type: chargeType,
    });

    if (error) {
      throw toAppError(error);
    }

    const rows = (Array.isArray(data) ? data : data ? [data] : []) as {
      currency: string;
      amount: number | string;
      source: ResolvedPrice['source'];
    }[];
    const row = rows[0];
    if (!row) {
      return null;
    }

    return {
      currency: row.currency,
      amount: Number(row.amount),
      source: row.source,
    };
  }
}

function coerceScheme(row: PricingScheme): PricingScheme {
  return {
    ...row,
    base_amount: Number(row.base_amount),
    currency: row.currency?.trim() ?? row.currency,
  };
}
