import { inject, Injectable } from '@angular/core';
import { SupabaseService } from '../../auth/services/supabase.service';

const POLL_MS = 10_000;

/**
 * Signals that a request was inserted. The payload is ignored; the list reloads.
 * If Realtime cannot subscribe, the caller is invoked every 10 seconds instead.
 */
@Injectable({ providedIn: 'root' })
export class RequestRealtimeService {
  private readonly supabase = inject(SupabaseService);

  watchNewRequests(organizationId: string, onInsert: () => void): () => void {
    let timer: ReturnType<typeof setInterval> | undefined;
    const channel = this.supabase.client
      .channel(`sales-requests:${organizationId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'customer_requests',
          filter: `organization_id=eq.${organizationId}`,
        },
        () => onInsert(),
      )
      .subscribe((status) => {
        if ((status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') && !timer) {
          timer = setInterval(onInsert, POLL_MS);
        }
      });

    return () => {
      if (timer) {
        clearInterval(timer);
      }
      void this.supabase.client.removeChannel(channel);
    };
  }
}
