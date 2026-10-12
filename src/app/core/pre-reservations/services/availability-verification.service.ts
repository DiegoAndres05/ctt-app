import { inject, Injectable } from '@angular/core';
import { LIST_PAGE_SIZE } from '../../../shared/components/data-table/list-query';
import { SupabaseService } from '../../auth/services/supabase.service';
import { toSearchOrFilter } from '../../customers/search-pattern';
import { toAppError } from '../../error/error-handler';
import type {
  AvailabilityStatus,
  RecordOutcomeResult,
  VerificationOutcomePayload,
  VerificationQueueRow,
} from '../models/verification.model';
import { PreReservationService } from './pre-reservation.service';

/**
 * Status filter of the queue (contracts §6.3): `''` (the default) narrows to the rows that
 * still need action, `all` disables the filter, anything else filters by line status.
 */
export type VerificationQueueStatus = AvailabilityStatus | 'all' | '';

export interface VerificationQueueQuery {
  /** Free text over reference, service, provider or customer (contracts §5). */
  q?: string;
  /** `''` = «Requieren acción», `all` = sin filtro, or one verification status. */
  status?: VerificationQueueStatus;
  /** Provider uuid, or `none` for lines without provider. */
  providerId?: string;
  /** Collaborator uuid; `me` is resolved by the caller. */
  assignee?: string;
  /** `provider` orders the queue grouped by provider name. */
  group?: string;
  page: number;
}

export interface VerificationProviderOption {
  id: string;
  name: string;
}

const QUEUE_SEARCH_COLUMNS = [
  'reference',
  'item_label',
  'provider_name',
  'customer_first_name',
  'customer_last_name',
];

/**
 * Reads the availability verification queue and applies the verification RPCs (migration
 * 039). Reads go through the `availability_verification_queue` view under RLS; mutations go
 * through SECURITY DEFINER functions, because direct table writes are revoked.
 */
@Injectable({ providedIn: 'root' })
export class AvailabilityVerificationService {
  private readonly supabase = inject(SupabaseService);
  private readonly preReservations = inject(PreReservationService);

  /**
   * One page of the queue (20 rows), sweeping expired holds first (R-004): the sweep only
   * logs a failure, so the read that triggered it always follows.
   */
  async queuePage(input: VerificationQueueQuery): Promise<{
    rows: VerificationQueueRow[];
    total: number;
  }> {
    await this.preReservations.sweepExpired();

    const page = Math.max(1, Math.floor(input.page) || 1);
    const from = (page - 1) * LIST_PAGE_SIZE;
    const to = from + LIST_PAGE_SIZE - 1;

    let query = this.supabase.client
      .from('availability_verification_queue')
      .select('*', { count: 'exact' })
      .range(from, to);

    if (!input.status) {
      query = query.eq('needs_action', true);
    } else if (input.status !== 'all') {
      query = query.eq('verification_status', input.status);
    }

    if (input.providerId === 'none') {
      query = query.is('provider_id', null);
    } else if (input.providerId) {
      query = query.eq('provider_id', input.providerId);
    }

    if (input.assignee === 'none') {
      query = query.is('assigned_operator_id', null);
    } else if (input.assignee) {
      query = query.eq('assigned_operator_id', input.assignee);
    }

    const filter = toSearchOrFilter(input.q ?? '', QUEUE_SEARCH_COLUMNS);
    if (filter) {
      query = query.or(filter);
    }

    if (input.group === 'provider') {
      query = query
        .order('provider_name', { nullsFirst: false })
        .order('start_date')
        .order('item_created_at');
    } else {
      query = query.order('start_date').order('item_created_at');
    }

    const { data, error, count } = await query;
    if (error) {
      throw toAppError(error);
    }
    return { rows: (data ?? []) as VerificationQueueRow[], total: count ?? 0 };
  }

  /** Active providers for the queue filter (contracts §5). */
  async listProviders(): Promise<VerificationProviderOption[]> {
    const { data, error } = await this.supabase.client
      .from('providers')
      .select('id, name')
      .eq('is_active', true)
      .order('name', { ascending: true });

    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as VerificationProviderOption[];
  }

  /**
   * Records the first provider contact on a line (RPC `start_item_verification`).
   * Idempotent in the database; operator/admin only.
   */
  async start(itemId: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('start_item_verification', {
      p_item_id: itemId,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  /** Records one availability outcome (RPC `record_item_verification`, contracts §3.3). */
  async record(itemId: string, payload: VerificationOutcomePayload): Promise<RecordOutcomeResult> {
    const { data, error } = await this.supabase.client.rpc('record_item_verification', {
      p_item_id: itemId,
      p_payload: payload,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as RecordOutcomeResult;
  }

  /** Assigns or clears the verification operator (RPC `assign_pre_reservation_operator`). */
  assignOperator(preReservationId: string, operatorId: string | null): Promise<void> {
    return this.preReservations.assignOperator(preReservationId, operatorId);
  }
}
