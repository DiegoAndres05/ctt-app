import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute } from '@angular/router';
import { toAppError, type AppError } from '../../core/error/error-handler';
import {
  RESERVATION_STATUS_LABELS,
  type PublicVoucher,
  type ReservationStatus,
} from '../../core/reservations/models/reservation.model';
import { ReservationService } from '../../core/reservations/services/reservation.service';
import { AlertComponent } from '../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../shared/components/spinner/spinner.component';

@Component({
  selector: 'app-public-voucher',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, AlertComponent, SpinnerComponent],
  template: `
    <main class="public-page">
      <article class="voucher">
        @if (loading()) {
          <app-spinner label="Cargando voucher…" />
        } @else if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        } @else if (voucher(); as data) {
          @if (data.available) {
            <header>
              <h1>Voucher {{ data.reference }}</h1>
              <p>{{ statusLabel(data.status) }}</p>
              <p>
                {{ data.travel_start_date | date: 'mediumDate' }}
                @if (data.travel_end_date) {
                  – {{ data.travel_end_date | date: 'mediumDate' }}
                }
              </p>
            </header>
            <section>
              <h2>Pasajeros</h2>
              <ul>
                @for (pax of data.passengers; track $index) {
                  <li>{{ pax.first_name }} {{ pax.last_name }}</li>
                }
              </ul>
            </section>
            <section>
              <h2>Itinerario</h2>
              <ul>
                @for (item of data.items; track $index) {
                  <li>
                    {{ item.title }} · {{ item.start_date | date: 'mediumDate' }}
                    @if (item.end_date) {
                      – {{ item.end_date | date: 'mediumDate' }}
                    }
                    · x{{ item.quantity }}
                  </li>
                }
              </ul>
            </section>
            <section>
              <h2>Asistencia</h2>
              <p>{{ data.assistance_phones || '—' }}</p>
            </section>
            <section>
              <h2>Políticas</h2>
              <p>{{ data.terms }}</p>
            </section>
            <button type="button" (click)="print()">Imprimir</button>
          } @else {
            <h1>Voucher</h1>
            <app-alert kind="warning">Este voucher ya no está disponible.</app-alert>
          }
        }
      </article>
    </main>
  `,
  styles: `
    .public-page {
      display: grid;
      place-items: start center;
      min-height: 100vh;
      padding: 1rem;
    }
    .voucher {
      display: grid;
      gap: 0.85rem;
      width: min(40rem, 100%);
    }
    @media (max-width: 360px) {
      .public-page {
        padding: 0.5rem;
      }
    }
  `,
})
export class PublicVoucherComponent {
  private readonly route = inject(ActivatedRoute);
  private readonly reservations = inject(ReservationService);
  private readonly params = toSignal(this.route.paramMap, { requireSync: true });
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly voucher = signal<PublicVoucher | null>(null);
  protected readonly statusLabel = (status: ReservationStatus) => RESERVATION_STATUS_LABELS[status];

  constructor() {
    effect(() => {
      const token = this.params().get('token');
      untracked(() => {
        void this.load(token);
      });
    });
  }

  protected print(): void {
    window.print();
  }

  private async load(token: string | null): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.voucher.set(await this.reservations.getPublicVoucher(token ?? ''));
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
