import { inject, Injectable } from '@angular/core';
import { SupabaseService } from '../../auth/services/supabase.service';
import { redact } from '../../error/error-handler';

/** Fallback cadence when Realtime cannot keep the subscription open (research R-011). */
const POLL_MS = 30_000;

/** Minimal shape the notice needs; the queue reference identifies the pre-reservation. */
export interface VerifiedPreReservation {
  id: string;
  reference: string;
}

/**
 * Tells the agent assigned to a pre-reservation when it becomes fully verified (FR-010).
 *
 * Realtime `UPDATE` events on `pre_reservations` are the primary signal; each id is
 * announced at most once per subscription. When the channel reports `CHANNEL_ERROR` or
 * `TIMED_OUT`, the service falls back to polling the agent's own verified pre-reservations
 * every 30 seconds with `verified_at >` the timestamp of the last query, so a failed
 * subscription only costs precision, never the notice itself.
 */
@Injectable({ providedIn: 'root' })
export class PreReservationRealtimeService {
  private readonly supabase = inject(SupabaseService);

  watchVerified(
    organizationId: string,
    userId: string,
    onVerified: (row: VerifiedPreReservation) => void,
  ): () => void {
    const notified = new Set<string>();
    let lastQueryAt = new Date().toISOString();
    let timer: ReturnType<typeof setInterval> | undefined;

    const announce = (row: VerifiedPreReservation): void => {
      if (notified.has(row.id)) {
        return;
      }
      notified.add(row.id);
      onVerified(row);
    };

    const poll = async (): Promise<void> => {
      const since = lastQueryAt;
      lastQueryAt = new Date().toISOString();
      const { data, error } = await this.supabase.client
        .from('pre_reservations')
        .select('id, reference, verified_at')
        .eq('responsible_agent_id', userId)
        .eq('status', 'verified')
        .gt('verified_at', since);
      if (error) {
        // No notice is lost to a failed read: the next tick retries with the same cutoff.
        lastQueryAt = since;
        console.warn('[cttadmin] could not poll verified pre-reservations', redact(error));
        return;
      }
      for (const row of (data ?? []) as VerifiedPreReservation[]) {
        announce(row);
      }
    };

    const startPolling = (): void => {
      if (timer) {
        return;
      }
      timer = setInterval(() => void poll(), POLL_MS);
    };

    const channel = this.supabase.client
      .channel(`pre-reservations:${organizationId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'pre_reservations',
          filter: `organization_id=eq.${organizationId}`,
        },
        (payload) => {
          const row = payload.new as Partial<VerifiedPreReservation> & {
            status?: string;
            responsible_agent_id?: string;
          };
          if (
            row.status !== 'verified' ||
            row.responsible_agent_id !== userId ||
            !row.id ||
            !row.reference
          ) {
            return;
          }
          announce({ id: row.id, reference: row.reference });
        },
      )
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          startPolling();
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
