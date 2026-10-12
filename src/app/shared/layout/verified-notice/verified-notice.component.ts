import { ChangeDetectionStrategy, Component, DestroyRef, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../../core/auth/services/auth.service';
import {
  PreReservationRealtimeService,
  type VerifiedPreReservation,
} from '../../../core/pre-reservations/services/pre-reservation-realtime.service';
import { AlertComponent } from '../../components/alert/alert.component';

/**
 * Global «totally verified» notice (FR-010, contracts §6.4).
 *
 * Mounted once inside `AdminShellComponent`, it subscribes on behalf of the agent and
 * shows the last verified pre-reservation until the notice is closed. The subscription
 * lives and dies with the shell (tasks T036/T037).
 */
@Component({
  selector: 'app-verified-notice',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, AlertComponent],
  template: `
    @if (notice(); as row) {
      <div class="notice">
        <app-alert kind="success">
          La pre-reserva {{ row.reference }} quedó totalmente verificada.
          <a [routerLink]="['/sales/pre-reservations', row.id]">Ver pre-reserva</a>
          <button type="button" (click)="dismiss()">Cerrar</button>
        </app-alert>
      </div>
    }
  `,
  styles: `
    :host {
      display: block;
    }

    .notice {
      margin-bottom: 1rem;
    }

    a,
    button {
      margin-left: 0.75rem;
    }
  `,
})
export class VerifiedNoticeComponent {
  private readonly auth = inject(AuthService);
  private readonly realtime = inject(PreReservationRealtimeService);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly notice = signal<VerifiedPreReservation | null>(null);

  constructor() {
    // The shell mounts only after authGuard has settled the session (request-list does
    // the same), so the identity is available right here.
    const organizationId = this.auth.organizationId();
    const userId = this.auth.user()?.id;
    if (organizationId && userId) {
      const stop = this.realtime.watchVerified(organizationId, userId, (row) =>
        this.notice.set(row),
      );
      this.destroyRef.onDestroy(stop);
    }
  }

  protected dismiss(): void {
    this.notice.set(null);
  }
}
