import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { SupabaseService } from '../../auth/services/supabase.service';
import { LIST_PAGE_SIZE } from '../../../shared/components/data-table/list-query';
import { toSearchOrFilter } from '../search-pattern';
import type { Customer, CustomerContactInput, CustomerListRow } from '../models/customer.model';

/**
 * Customer directory and profile edits. Writes go through `update_customer` and
 * `anonymize_customer`; the table itself is SELECT-only for collaborators.
 */
@Injectable({ providedIn: 'root' })
export class CustomerService {
  private readonly supabase = inject(SupabaseService);

  async listPage(input: {
    q?: string;
    page: number;
  }): Promise<{ rows: CustomerListRow[]; total: number }> {
    const page = Math.max(1, Math.floor(input.page) || 1);
    const from = (page - 1) * LIST_PAGE_SIZE;
    const to = from + LIST_PAGE_SIZE - 1;

    let query = this.supabase.client
      .from('customer_list')
      .select('*', { count: 'exact' })
      .order('last_request_at', { ascending: false, nullsFirst: false })
      .range(from, to);

    const filter = toSearchOrFilter(
      input.q ?? '',
      ['first_name', 'last_name', 'email'],
      ['phone_e164'],
    );
    if (filter) {
      query = query.or(filter);
    }

    const { data, error, count } = await query;
    if (error) {
      throw toAppError(error);
    }
    return { rows: (data ?? []) as CustomerListRow[], total: count ?? 0 };
  }

  async getById(id: string): Promise<Customer | null> {
    const { data, error } = await this.supabase.client
      .from('customers')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (error) {
      throw toAppError(error);
    }
    return (data as Customer | null) ?? null;
  }

  async search(q: string, limit = 10): Promise<CustomerListRow[]> {
    const filter = toSearchOrFilter(q, ['first_name', 'last_name', 'email'], ['phone_e164']);
    if (!filter) {
      return [];
    }

    const { data, error } = await this.supabase.client
      .from('customer_list')
      .select('*')
      .eq('is_anonymized', false)
      .or(filter)
      .order('last_request_at', { ascending: false, nullsFirst: false })
      .limit(limit);

    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as CustomerListRow[];
  }

  async update(id: string, input: CustomerContactInput): Promise<Customer> {
    const { data, error } = await this.supabase.client.rpc('update_customer', {
      p_customer_id: id,
      p_payload: input,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as Customer;
  }

  async anonymize(id: string, reason: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('anonymize_customer', {
      p_customer_id: id,
      p_reason: reason,
    });
    if (error) {
      throw toAppError(error);
    }
  }
}
