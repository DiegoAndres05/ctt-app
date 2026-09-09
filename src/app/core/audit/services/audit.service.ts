import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { SupabaseService } from '../../auth/services/supabase.service';
import {
  AUDIT_PAGE_SIZE_DEFAULT,
  AUDIT_PAGE_SIZE_MAX,
  type AuditEvent,
  type AuditEventFilter,
  type AuditLogEntry,
} from '../models/audit-event.model';

export interface AuditEventPage {
  events: AuditLogEntry[];
  count: number;
  limit: number;
  offset: number;
}

/**
 * Read-only query surface for the immutable security log.
 *
 * Tenant scope comes from the JWT via RLS (`admin_select`); this service never accepts an
 * organization id. There is no update or delete method: the database rejects both.
 */
@Injectable({ providedIn: 'root' })
export class AuditService {
  private readonly supabase = inject(SupabaseService);

  async list(filter: AuditEventFilter = {}): Promise<AuditEventPage> {
    const limit = clamp(filter.limit ?? AUDIT_PAGE_SIZE_DEFAULT, 1, AUDIT_PAGE_SIZE_MAX);
    const offset = Math.max(filter.offset ?? 0, 0);

    let query = this.supabase.client
      .schema('audit')
      .from('audit_events')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (filter.eventType) {
      query = query.eq('event_type', filter.eventType);
    }
    if (filter.actorId) {
      query = query.eq('actor_id', filter.actorId);
    }
    if (filter.from) {
      query = query.gte('created_at', filter.from);
    }
    if (filter.to) {
      query = query.lte('created_at', filter.to);
    }

    const { data, error, count } = await query.returns<AuditEvent[]>();

    if (error) {
      throw toAppError(error);
    }

    const rows = data ?? [];
    const names = await this.actorNames(rows);

    return {
      events: rows.map((event) => ({
        ...event,
        actor_name: event.actor_id ? (names.get(event.actor_id) ?? null) : null,
      })),
      count: count ?? 0,
      limit,
      offset,
    };
  }

  private async actorNames(events: AuditEvent[]): Promise<Map<string, string>> {
    const ids = [
      ...new Set(events.map((event) => event.actor_id).filter((id): id is string => id != null)),
    ];
    if (ids.length === 0) {
      return new Map();
    }

    const { data, error } = await this.supabase.client
      .from('user_profiles')
      .select('id, full_name')
      .in('id', ids);

    if (error) {
      throw toAppError(error);
    }

    return new Map((data ?? []).map((row) => [row.id as string, row.full_name as string]));
  }
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
