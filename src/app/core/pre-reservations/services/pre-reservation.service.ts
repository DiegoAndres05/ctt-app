import { inject, Injectable } from '@angular/core';
import { SupabaseService } from '../../auth/services/supabase.service';
import { redact, toAppError } from '../../error/error-handler';
import { toSearchOrFilter } from '../../customers/search-pattern';
import { LIST_PAGE_SIZE } from '../../../shared/components/data-table/list-query';
import type { RequestStatus } from '../../customers/models/request.model';
import type { AssigneeOption } from '../../customers/services/request.service';
import type {
  PreReservation,
  PreReservationDetail,
  PreReservationItem,
  PreReservationItemKind,
  PreReservationListRow,
  PreReservationStatus,
  VerificationTimes,
} from '../models/pre-reservation.model';
import type { VerificationEvent } from '../models/verification.model';

export interface PreReservationPageQuery {
  q?: string;
  status?: PreReservationStatus | '';
  /** Collaborator id; `me` is resolved by the caller. */
  responsibleId?: string;
  page: number;
}

/** A line payload accepted by `create_pre_reservation` (contracts §1). */
export interface PreReservationItemInput {
  /** XOR with `addon_id`. */
  product_id: string | null;
  /** XOR with `product_id`. */
  addon_id: string | null;
  start_date: string;
  end_date: string | null;
  adults: number;
  children: number;
  quantity: number;
  source_request_item_id: string | null;
  provider_name: string | null;
  provider_phone: string | null;
  provider_email: string | null;
  /** 0-based index of a main row of the same payload; only on create. */
  alternative_of?: number;
}

/** Body of `create_pre_reservation` (contracts §2.1). */
export interface CreatePreReservationPayload {
  items: PreReservationItemInput[];
  assigned_operator_id: string | null;
}

/**
 * A line payload accepted by `add_pre_reservation_item` (contracts §1): like
 * `PreReservationItemInput`, but the alternative points at an existing item id.
 */
export type PreReservationAddItemInput = Omit<PreReservationItemInput, 'alternative_of'> & {
  alternative_of_item_id?: string | null;
};

/** Body returned by `create_pre_reservation`. */
export interface CreatePreReservationResult {
  pre_reservation_id: string;
  reference: string;
  status: 'pending_verification';
  request_status: RequestStatus;
}

export interface BookableProvider {
  id: string;
  name: string;
  contact_phone: string | null;
  contact_email: string | null;
  is_active: boolean;
}

/** An active product or add-on the line form can pick. */
export interface BookableOption {
  id: string;
  name: string;
  /** Products carry their subtype; add-ons are always `addon`. */
  kind: PreReservationItemKind;
  provider_id: string | null;
  provider: BookableProvider | null;
}

interface ProductCatalogRow {
  id: string;
  name: string;
  type: 'experience' | 'accommodation' | 'package';
  provider_id: string | null;
  provider: BookableProvider | BookableProvider[] | null;
}

interface RequestEmbed {
  id: string;
  reference: string;
  status: RequestStatus;
}

interface CustomerEmbed {
  id: string;
  first_name: string;
  last_name: string | null;
  is_anonymized: boolean;
}

interface ProfileEmbed {
  full_name: string;
}

interface PreReservationDetailRow extends PreReservation {
  request: RequestEmbed | RequestEmbed[] | null;
  customer: CustomerEmbed | CustomerEmbed[] | null;
  agent: ProfileEmbed | ProfileEmbed[] | null;
  operator: ProfileEmbed | ProfileEmbed[] | null;
  override_by: ProfileEmbed | ProfileEmbed[] | null;
}

const DETAIL_SELECT =
  '*, request:customer_requests!pre_reservations_request_fkey(id, reference, status), customer:customers!pre_reservations_customer_fkey(id, first_name, last_name, is_anonymized), agent:user_profiles!pre_reservations_responsible_agent_fkey(id, full_name), operator:user_profiles!pre_reservations_assigned_operator_fkey(id, full_name), override_by:user_profiles!pre_reservations_quote_override_by_fkey(full_name)';

const ITEMS_SELECT = '*, verifier:user_profiles!pre_reservation_items_verified_by_fkey(full_name)';

/**
 * Reads pre-reservations and applies the lifecycle RPCs.
 * Direct table writes are revoked; mutations go through SECURITY DEFINER functions,
 * including the admin quotation exception (`authorize_quotation_override`) the «Cotización»
 * screen calls.
 */
@Injectable({ providedIn: 'root' })
export class PreReservationService {
  private readonly supabase = inject(SupabaseService);

  /**
   * Expires pre-reservations whose provider hold ran out (R-004).
   *
   * The sweep is an optimization — the queue view already flags `hold_expired` per line —
   * so a failure is logged and swallowed: the read that triggered it must still succeed.
   */
  async sweepExpired(): Promise<number> {
    const { data, error } = await this.supabase.client.rpc('expire_due_pre_reservations');
    if (error) {
      console.warn('[cttadmin] could not sweep expired pre-reservations', redact(error));
      return 0;
    }
    return typeof data === 'number' ? data : 0;
  }

  /**
   * Converts a request into a pre-reservation with the given lines (contracts §2.1).
   * The request moves to `pre_reservation` when it was `received` or `in_review`.
   */
  async create(
    requestId: string,
    payload: CreatePreReservationPayload,
  ): Promise<CreatePreReservationResult> {
    const { data, error } = await this.supabase.client.rpc('create_pre_reservation', {
      p_request_id: requestId,
      p_payload: payload,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as CreatePreReservationResult;
  }

  /** Cancels a pre-reservation with a mandatory reason (contracts §2.2). */
  async cancel(id: string, reason: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('cancel_pre_reservation', {
      p_pre_reservation_id: id,
      p_reason: reason,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  /** Adds one line to an open pre-reservation (RPC `add_pre_reservation_item`, contracts §4). */
  async addItem(id: string, item: PreReservationAddItemInput): Promise<void> {
    const { error } = await this.supabase.client.rpc('add_pre_reservation_item', {
      p_pre_reservation_id: id,
      p_item: item,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  /**
   * Withdraws a line — and its live alternatives — with a mandatory reason
   * (RPC `withdraw_pre_reservation_item`, contracts §4).
   */
  async withdrawItem(itemId: string, reason: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('withdraw_pre_reservation_item', {
      p_item_id: itemId,
      p_reason: reason,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  /**
   * Promotes an alternative to main, withdrawing the line it replaced
   * (RPC `promote_alternative_item`, contracts §4).
   */
  async promoteItem(itemId: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('promote_alternative_item', {
      p_item_id: itemId,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  /** Assigns or clears the verification operator (RPC `assign_pre_reservation_operator`, contracts §3.1). */
  async assignOperator(id: string, operatorId: string | null): Promise<void> {
    const { error } = await this.supabase.client.rpc('assign_pre_reservation_operator', {
      p_pre_reservation_id: id,
      p_operator_id: operatorId,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  /**
   * Authorizes the admin quotation exception with a mandatory reason
   * (RPC `authorize_quotation_override`, contracts §4; admin-only server-side).
   */
  async authorizeOverride(id: string, reason: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('authorize_quotation_override', {
      p_pre_reservation_id: id,
      p_reason: reason,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async listPage(input: PreReservationPageQuery): Promise<{
    rows: PreReservationListRow[];
    total: number;
  }> {
    await this.sweepExpired();

    const page = Math.max(1, Math.floor(input.page) || 1);
    const from = (page - 1) * LIST_PAGE_SIZE;
    const to = from + LIST_PAGE_SIZE - 1;

    let query = this.supabase.client
      .from('pre_reservation_list')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (input.status) {
      query = query.eq('status', input.status);
    }
    if (input.responsibleId) {
      query = query.eq('responsible_agent_id', input.responsibleId);
    }

    const filter = toSearchOrFilter(input.q ?? '', [
      'reference',
      'request_reference',
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
    return { rows: (data ?? []) as PreReservationListRow[], total: count ?? 0 };
  }

  async listForRequest(requestId: string): Promise<PreReservationListRow[]> {
    const { data, error } = await this.supabase.client
      .from('pre_reservation_list')
      .select('*')
      .eq('request_id', requestId)
      .order('created_at', { ascending: true });

    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as PreReservationListRow[];
  }

  /** Header + relations + every line (withdrawn included) + quote eligibility. */
  async getById(id: string): Promise<PreReservationDetail | null> {
    await this.sweepExpired();

    const { data, error } = await this.supabase.client
      .from('pre_reservations')
      .select(DETAIL_SELECT)
      .eq('id', id)
      .maybeSingle();
    if (error) {
      throw toAppError(error);
    }
    if (!data) {
      return null;
    }

    const [itemsResult, eligibilityResult] = await Promise.all([
      this.supabase.client
        .from('pre_reservation_items')
        .select(ITEMS_SELECT)
        .eq('pre_reservation_id', id)
        .order('position'),
      this.supabase.client
        .from('pre_reservation_list')
        .select('quote_eligible, has_quote_override')
        .eq('id', id)
        .maybeSingle(),
    ]);
    if (itemsResult.error) {
      throw toAppError(itemsResult.error);
    }
    if (eligibilityResult.error) {
      throw toAppError(eligibilityResult.error);
    }

    return mapDetail(
      data as PreReservationDetailRow,
      (itemsResult.data ?? []) as PreReservationItem[],
      eligibilityResult.data,
    );
  }

  /** Event trail of a pre-reservation, newest first (view `availability_verification_history`). */
  async listHistory(id: string): Promise<VerificationEvent[]> {
    const { data, error } = await this.supabase.client
      .from('availability_verification_history')
      .select('*')
      .eq('pre_reservation_id', id)
      .order('created_at', { ascending: false });

    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as VerificationEvent[];
  }

  /** Verification timing metrics (view `pre_reservation_verification_times`). */
  async getTimes(id: string): Promise<VerificationTimes | null> {
    const { data, error } = await this.supabase.client
      .from('pre_reservation_verification_times')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (error) {
      throw toAppError(error);
    }
    return (data ?? null) as VerificationTimes | null;
  }

  /** Active products (with their provider snapshot) plus active add-ons, for the line form. */
  async listBookables(): Promise<BookableOption[]> {
    const [productsResult, addonsResult] = await Promise.all([
      this.supabase.client
        .from('products')
        .select(
          'id, name, type, provider_id, provider:providers(id, name, contact_phone, contact_email, is_active)',
        )
        .eq('status', 'active')
        .order('name'),
      this.supabase.client.from('add_ons').select('id, name').eq('is_active', true).order('name'),
    ]);
    if (productsResult.error) {
      throw toAppError(productsResult.error);
    }
    if (addonsResult.error) {
      throw toAppError(addonsResult.error);
    }

    const products: BookableOption[] = ((productsResult.data ?? []) as ProductCatalogRow[]).map(
      (row) => ({
        id: row.id,
        name: row.name,
        kind: row.type,
        provider_id: row.provider_id,
        provider: single(row.provider),
      }),
    );
    const addons: BookableOption[] = (
      (addonsResult.data ?? []) as { id: string; name: string }[]
    ).map((row) => ({
      id: row.id,
      name: row.name,
      kind: 'addon',
      provider_id: null,
      provider: null,
    }));
    return [...products, ...addons];
  }

  async listOperators(): Promise<AssigneeOption[]> {
    const { data, error } = await this.supabase.client
      .from('user_profiles')
      .select('id, full_name')
      .eq('status', 'active')
      .in('role', ['operator', 'admin'])
      .order('full_name', { ascending: true });

    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as AssigneeOption[];
  }
}

/** PostgREST returns many-to-one embeds as objects, but the type allows arrays. */
function single<T>(value: T | T[] | null): T | null {
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function mapDetail(
  row: PreReservationDetailRow,
  items: PreReservationItem[],
  eligibility: { quote_eligible: boolean; has_quote_override: boolean } | null,
): PreReservationDetail {
  return {
    ...row,
    request: single(row.request),
    customer: single(row.customer),
    agent: single(row.agent),
    operator: single(row.operator),
    override_by: single(row.override_by),
    items,
    quote_eligible: eligibility?.quote_eligible ?? false,
    has_quote_override: eligibility?.has_quote_override ?? false,
  };
}
