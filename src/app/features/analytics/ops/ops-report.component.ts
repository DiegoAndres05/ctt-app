import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { OpsTimesReport, StaleItem } from '../../../core/analytics/models/analytics.model';
import { AnalyticsService } from '../../../core/analytics/services/analytics.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import { monthStart, today } from '../funnel/funnel-report.component';

@Component({
  selector: 'app-ops-report',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [AlertComponent, SpinnerComponent],
  template: `
    <div class="stack">
      <h1>Tiempos operativos</h1>
      <form class="filters" (submit)="onLoad($event)">
        <label>Desde <input type="date" [value]="from()" (input)="from.set($any($event.target).value)" /></label>
        <label>Hasta <input type="date" [value]="to()" (input)="to.set($any($event.target).value)" /></label>
        <button class="primary" type="submit" [disabled]="loading()">Consultar</button>
      </form>
      @if (loading()) {
        <app-spinner label="Cargando tiempos…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (times(); as t) {
        <dl>
          <div><dt>Respuesta a solicitud (h)</dt><dd>{{ t.avg_request_response_hours ?? '—' }}</dd></div>
          <div><dt>Verificación (h)</dt><dd>{{ t.avg_verification_hours ?? '—' }}</dd></div>
          <div><dt>Emisión de cotización (h)</dt><dd>{{ t.avg_quotation_issue_hours ?? '—' }}</dd></div>
        </dl>
        <h2>Atención requerida</h2>
        @if (stale().length === 0) {
          <p>Nada pendiente de atención.</p>
        } @else {
          <ul>
            @for (item of stale(); track item.id) {
              <li>{{ item.reference }} · {{ item.kind }} · {{ item.age_hours }} h · {{ item.status }}</li>
            }
          </ul>
        }
      }
    </div>
  `,
  styles: `
    .stack { display: grid; gap: 1rem; max-width: 40rem; }
    dl div { display: flex; justify-content: space-between; }
  `,
})
export class OpsReportComponent {
  private readonly analytics = inject(AnalyticsService);
  protected readonly from = signal(monthStart());
  protected readonly to = signal(today());
  protected readonly loading = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly times = signal<OpsTimesReport | null>(null);
  protected readonly stale = signal<StaleItem[]>([]);

  constructor() {
    void this.load();
  }

  protected onLoad(event: Event): void {
    event.preventDefault();
    void this.load();
  }

  private async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const [times, stale] = await Promise.all([
        this.analytics.opsTimes(this.from(), this.to(), null),
        this.analytics.staleQueue(),
      ]);
      this.times.set(times);
      this.stale.set(stale);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
