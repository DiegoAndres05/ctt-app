import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { SupabaseService } from '../../auth/services/supabase.service';
import { LIST_PAGE_SIZE } from '../../../shared/components/data-table/list-query';
import { toSearchOrFilter } from '../search-pattern';
import type { Customer } from '../models/customer.model';
import type {
  CaptureResult,
  InboundMessage,
  ManualRequestStatus,
  RequestChannel,
  RequestDetail,
  RequestItem,
  RequestListRow,
  RequestNote,
  RequestStatus,
  SubmittedContact,
} from '../models/request.model';

export interface AssistedRequestPayload {
  channel: 'whatsapp' | 'phone' | 'in_person';
  customer_id?: string;
  contact?: {
    first_name: string;
    last_name: string | null;
    email: string | null;
    phone: string | null;
    country_code: string | null;
  };
  privacy_notice_given: boolean;
  idempotency_key: string;
  travel_start_date: string | null;
  travel_end_date: string | null;
  adults: number;
  children: number;
  special_requirements: string | null;
  items: { product_id?: string; free_text?: string; quantity: number }[];
}

export interface RequestPageQuery {
  q?: string;
  status?: RequestStatus | '';
  channel?: RequestChannel | '';
  /** Collaborator id, or `none` for unassigned. `me` is resolved by the caller. */
  assignee?: string;
  customerId?: string;
  page: number;
}

export interface AssigneeOption {
  id: string;
  full_name: string;
}

interface RequestDetailRow {
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
  customer: Customer | Customer[] | null;
  items: (Omit<RequestItem, 'product'> & {
    product: { id: string; name: string; type: string } | null;
  })[];
  assignee: { id: string; full_name: string } | { id: string; full_name: string }[] | null;
}

const DETAIL_SELECT =
  '*, customer:customers(*), items:customer_request_items(*, product:products(id, name, type)), assignee:user_profiles!customer_requests_assigned_to_fkey(id, full_name)';

/**
 * Reads the request inbox and applies the workflow RPCs.
 * Direct table writes are revoked; mutations go through SECURITY DEFINER functions.
 */
@Injectable({ providedIn: 'root' })
export class RequestService {
  private readonly supabase = inject(SupabaseService);

  async listPage(input: RequestPageQuery): Promise<{ rows: RequestListRow[]; total: number }> {
    const page = Math.max(1, Math.floor(input.page) || 1);
    const from = (page - 1) * LIST_PAGE_SIZE;
    const to = from + LIST_PAGE_SIZE - 1;

    let query = this.supabase.client
      .from('customer_request_list')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (input.status) {
      query = query.eq('status', input.status);
    }
    if (input.channel) {
      query = query.eq('channel', input.channel);
    }
    if (input.assignee === 'none') {
      query = query.is('assigned_to', null);
    } else if (input.assignee) {
      query = query.eq('assigned_to', input.assignee);
    }
    if (input.customerId) {
      query = query.eq('customer_id', input.customerId);
    }

    const filter = toSearchOrFilter(
      input.q ?? '',
      ['reference', 'customer_first_name', 'customer_last_name', 'customer_email'],
      ['customer_phone_e164'],
    );
    if (filter) {
      query = query.or(filter);
    }

    const { data, error, count } = await query;
    if (error) {
      throw toAppError(error);
    }
    return { rows: (data ?? []) as RequestListRow[], total: count ?? 0 };
  }

  async getById(id: string): Promise<RequestDetail | null> {
    const { data, error } = await this.supabase.client
      .from('customer_requests')
      .select(DETAIL_SELECT)
      .eq('id', id)
      .maybeSingle();

    if (error) {
      throw toAppError(error);
    }
    if (!data) {
      return null;
    }
    return mapDetail(data as RequestDetailRow);
  }

  async listMessages(requestId: string): Promise<InboundMessage[]> {
    const { data, error } = await this.supabase.client
      .from('inbound_messages')
      .select('id, profile_name, message_type, body, provider_timestamp')
      .eq('request_id', requestId)
      .order('provider_timestamp', { ascending: true });

    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as InboundMessage[];
  }

  async listNotes(target: { requestId: string } | { customerId: string }): Promise<RequestNote[]> {
    let query = this.supabase.client
      .from('request_notes')
      .select('*, author:user_profiles!request_notes_author_fkey(full_name)')
      .order('created_at', { ascending: false });

    query =
      'requestId' in target
        ? query.eq('request_id', target.requestId)
        : query.eq('customer_id', target.customerId);

    const { data, error } = await query;
    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as RequestNote[];
  }

  async createAssisted(payload: AssistedRequestPayload): Promise<CaptureResult> {
    const { data, error } = await this.supabase.client.rpc('create_assisted_request', {
      p_payload: payload,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as CaptureResult;
  }

  async assign(requestId: string, assigneeId: string | null): Promise<void> {
    const { error } = await this.supabase.client.rpc('assign_request', {
      p_request_id: requestId,
      p_assignee_id: assigneeId,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async setStatus(requestId: string, status: ManualRequestStatus, reason?: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('set_request_status', {
      p_request_id: requestId,
      p_status: status,
      p_reason: reason ?? null,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async addNote(
    target: { requestId: string } | { customerId: string },
    content: string,
  ): Promise<void> {
    const { error } = await this.supabase.client.rpc('add_request_note', {
      p_request_id: 'requestId' in target ? target.requestId : null,
      p_customer_id: 'customerId' in target ? target.customerId : null,
      p_content: content,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  async listAssignees(): Promise<AssigneeOption[]> {
    const { data, error } = await this.supabase.client
      .from('user_profiles')
      .select('id, full_name')
      .eq('status', 'active')
      .order('full_name', { ascending: true });

    if (error) {
      throw toAppError(error);
    }
    return (data ?? []) as AssigneeOption[];
  }
}

function mapDetail(row: RequestDetailRow): RequestDetail {
  const customer = Array.isArray(row.customer) ? row.customer[0] : row.customer;
  const assignee = Array.isArray(row.assignee) ? (row.assignee[0] ?? null) : row.assignee;
  if (!customer) {
    throw toAppError({ message: 'VALIDATION_ERROR' });
  }

  const items: RequestItem[] = (row.items ?? [])
    .map((item) => ({
      id: item.id,
      product_id: item.product_id,
      public_slug: item.public_slug,
      free_text: item.free_text,
      quantity: item.quantity,
      position: item.position,
      product: item.product
        ? { id: item.product.id, name: item.product.name, product_type: item.product.type }
        : null,
    }))
    .sort((a, b) => a.position - b.position);

  return {
    id: row.id,
    organization_id: row.organization_id,
    reference: row.reference,
    customer_id: row.customer_id,
    channel: row.channel,
    status: row.status,
    assigned_to: row.assigned_to,
    assigned_at: row.assigned_at,
    travel_start_date: row.travel_start_date,
    travel_end_date: row.travel_end_date,
    adults: row.adults,
    children: row.children,
    special_requirements: row.special_requirements,
    locale: row.locale,
    source_page: row.source_page,
    submitted_contact: row.submitted_contact,
    contact_review_required: row.contact_review_required,
    privacy_consent_at: row.privacy_consent_at,
    discard_reason: row.discard_reason,
    first_handled_at: row.first_handled_at,
    closed_at: row.closed_at,
    created_at: row.created_at,
    customer,
    items,
    assignee,
  };
}
