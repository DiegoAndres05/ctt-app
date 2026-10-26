import { inject, Injectable } from '@angular/core';
import { SupabaseService } from '../../auth/services/supabase.service';
import { toSearchOrFilter } from '../../customers/search-pattern';
import { toAppError } from '../../error/error-handler';
import { LIST_PAGE_SIZE } from '../../../shared/components/data-table/list-query';
import {
  reservationTokenStorageKey,
  type ConfirmReservationResult,
  type PublicVoucher,
  type ReservationDepositInput,
  type ReservationDetail,
  type ReservationItem,
  type ReservationListRow,
  type ReservationPassenger,
  type ReservationPassengerInput,
  type ReservationPayment,
  type ReservationStatus,
  type ReservationVersion,
} from '../models/reservation.model';

export interface ReservationPageQuery {
  q?: string;
  status?: ReservationStatus | '';
  page: number;
}

interface FamilyEmbed {
  reference: string;
  quotation_version_id: string;
  quotation_family_id: string;
}

interface VersionRow extends ReservationVersion {
  family: FamilyEmbed | FamilyEmbed[] | null;
}

const VERSION_SELECT = '*, family:reservation_families(reference, quotation_version_id, quotation_family_id)';

@Injectable({ providedIn: 'root' })
export class ReservationService {
  private readonly supabase = inject(SupabaseService);

  async listPage(input: ReservationPageQuery): Promise<{
    rows: ReservationListRow[];
    total: number;
  }> {
    const page = Math.max(1, Math.floor(input.page) || 1);
    const from = (page - 1) * LIST_PAGE_SIZE;
    const to = from + LIST_PAGE_SIZE - 1;

    let query = this.supabase.client
      .from('reservation_list')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (input.status) {
      query = query.eq('status', input.status);
    }

    const filter = toSearchOrFilter(input.q ?? '', [
      'reference',
      'quotation_reference',
      'customer_first_name',
      'customer_last_name',
    ]);
    if (filter) {
      query = query.or(filter);
    }

    const { data, error, count } = await query;
    if (error) {
      throw toAppError(error);
    }
    return { rows: (data ?? []) as ReservationListRow[], total: count ?? 0 };
  }

  async getById(versionId: string): Promise<ReservationDetail | null> {
    const { data, error } = await this.supabase.client
      .from('reservation_versions')
      .select(VERSION_SELECT)
      .eq('id', versionId)
      .maybeSingle();
    if (error) {
      throw toAppError(error);
    }
    if (!data) {
      return null;
    }

    const row = data as VersionRow;
    const family = Array.isArray(row.family) ? (row.family[0] ?? null) : row.family;
    if (!family) {
      return null;
    }

    const [passengers, items, payments, list] = await Promise.all([
      this.supabase.client
        .from('reservation_passengers')
        .select('*')
        .eq('version_id', versionId)
        .order('position'),
      this.supabase.client
        .from('reservation_items')
        .select('*')
        .eq('version_id', versionId)
        .order('position'),
      this.supabase.client
        .from('reservation_payments')
        .select('*')
        .eq('family_id', row.family_id)
        .order('created_at'),
      this.supabase.client
        .from('reservation_list')
        .select('paid_total, balance, quotation_reference')
        .eq('version_id', versionId)
        .maybeSingle(),
    ]);
    if (passengers.error) {
      throw toAppError(passengers.error);
    }
    if (items.error) {
      throw toAppError(items.error);
    }
    if (payments.error) {
      throw toAppError(payments.error);
    }
    if (list.error) {
      throw toAppError(list.error);
    }

    const { family: _embed, ...version } = row;
    return {
      ...(version as ReservationVersion),
      reference: family.reference,
      quotation_version_id: family.quotation_version_id,
      quotation_reference: list.data?.quotation_reference ?? null,
      paid_total: Number(list.data?.paid_total ?? 0),
      balance: Number(list.data?.balance ?? 0),
      passengers: (passengers.data ?? []) as ReservationPassenger[],
      items: (items.data ?? []) as ReservationItem[],
      payments: (payments.data ?? []) as ReservationPayment[],
    };
  }

  async confirm(
    quotationVersionId: string,
    deposit: ReservationDepositInput,
    passengers: ReservationPassengerInput[],
    assistancePhones: string,
  ): Promise<ConfirmReservationResult> {
    const { data, error } = await this.supabase.client.rpc('confirm_reservation', {
      p_quotation_version_id: quotationVersionId,
      p_deposit: deposit,
      p_passengers: passengers,
      p_assistance_phones: assistancePhones,
    });
    if (error) {
      throw toAppError(error);
    }
    const result = data as ConfirmReservationResult;
    if (result.family_id && result.voucher_token) {
      sessionStorage.setItem(
        reservationTokenStorageKey(result.family_id),
        result.voucher_token,
      );
    }
    return result;
  }

  async recordPayment(familyId: string, payment: ReservationDepositInput): Promise<void> {
    const { error } = await this.supabase.client.rpc('record_reservation_payment', {
      p_family_id: familyId,
      p_payment: payment,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async uploadReceipt(organizationId: string, familyId: string, file: File): Promise<string> {
    const safeName = file.name.replace(/[^\w.\-]+/g, '_');
    const path = `${organizationId}/${familyId}/${Date.now()}-${safeName}`;
    const { error } = await this.supabase.client.storage
      .from('reservation-receipts')
      .upload(path, file, { upsert: false });
    if (error) {
      throw toAppError(error);
    }
    return path;
  }

  async transition(versionId: string, to: ReservationStatus): Promise<void> {
    const { error } = await this.supabase.client.rpc('transition_reservation_status', {
      p_version_id: versionId,
      p_to: to,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async cancel(versionId: string, reason: string, contingencyReport: string | null): Promise<void> {
    const { error } = await this.supabase.client.rpc('cancel_reservation', {
      p_version_id: versionId,
      p_reason: reason,
      p_contingency_report: contingencyReport,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async createVersion(
    versionId: string,
    items: ReservationItem[],
    passengers: ReservationPassengerInput[],
  ): Promise<{ version_id: string; family_id: string }> {
    const { data, error } = await this.supabase.client.rpc('create_reservation_version', {
      p_version_id: versionId,
      p_items: items.map((item) => ({
        quotation_line_ref: item.quotation_line_ref,
        pre_reservation_item_id: item.pre_reservation_item_id,
        item_kind: item.item_kind,
        item_label: item.item_label,
        product_id: item.product_id,
        addon_id: item.addon_id,
        start_date: item.start_date,
        end_date: item.end_date,
        adults: item.adults,
        children: item.children,
        quantity: item.quantity,
        line_total: item.line_total,
        provider_id: item.provider_id,
      })),
      p_passengers: passengers,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as { version_id: string; family_id: string };
  }

  async providerOrderText(itemId: string): Promise<Record<string, unknown>> {
    const { data, error } = await this.supabase.client.rpc('reservation_provider_order_text', {
      p_item_id: itemId,
    });
    if (error) {
      throw toAppError(error);
    }
    return (data ?? {}) as Record<string, unknown>;
  }

  async markOrderSent(itemId: string, channel: 'whatsapp_copy' | 'email_copy' | 'print'): Promise<void> {
    const { error } = await this.supabase.client.rpc('mark_provider_order_sent', {
      p_item_id: itemId,
      p_channel: channel,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async reassignProvider(itemId: string, providerId: string, reason: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('reassign_reservation_item_provider', {
      p_item_id: itemId,
      p_provider_id: providerId,
      p_reason: reason,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async whatsappText(versionId: string): Promise<string> {
    const { data, error } = await this.supabase.client.rpc('reservation_whatsapp_text', {
      p_version_id: versionId,
    });
    if (error) {
      throw toAppError(error);
    }
    return typeof data === 'string' ? data : '';
  }

  async getPublicVoucher(token: string): Promise<PublicVoucher> {
    const { data, error } = await this.supabase.client.rpc('get_public_voucher', {
      p_token: token,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as PublicVoucher;
  }

  async voidVoucher(familyId: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('void_reservation_voucher', {
      p_family_id: familyId,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async rotateVoucher(familyId: string): Promise<string> {
    const { data, error } = await this.supabase.client.rpc('rotate_reservation_voucher', {
      p_family_id: familyId,
    });
    if (error) {
      throw toAppError(error);
    }
    const token = (data as { voucher_token?: string } | null)?.voucher_token ?? '';
    if (token) {
      sessionStorage.setItem(reservationTokenStorageKey(familyId), token);
    }
    return token;
  }

  async listProviders(): Promise<{ id: string; name: string }[]> {
    const { data, error } = await this.supabase.client
      .from('providers')
      .select('id, name')
      .order('name');
    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as { id: string; name: string }[];
  }

  readStoredToken(familyId: string): string | null {
    return sessionStorage.getItem(reservationTokenStorageKey(familyId));
  }
}
