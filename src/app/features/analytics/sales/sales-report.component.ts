import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { ProductRankRow, SalesSummary } from '../../../core/analytics/models/analytics.model';
import { AnalyticsService } from '../../../core/analytics/services/analytics.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import { monthStart, today } from '../funnel/funnel-report.component';

@Component({
  selector: 'app-sales-report',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [AlertComponent, SpinnerComponent],
  template: `
    <div class="stack">
      <h1>Productos e ingresos</h1>
      <form class="filters" (submit)="onLoad($event)">
        <label>Desde <input type="date" [value]="from()" (input)="from.set($any($event.target).value)" /></label>
        <label>Hasta <input type="date" [value]="to()" (input)="to.set($any($event.target).value)" /></label>
        <button class="primary" type="submit" [disabled]="loading()">Consultar</button>
        <button type="button" (click)="onCsv()" [disabled]="rows().length === 0">Descargar CSV</button>
      </form>
      @if (loading()) {
        <app-spinner label="Cargando ranking…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else {
        @if (summaries().length === 0 && rows().length === 0) {
          <p>No hay movimientos en este período.</p>
        }
        @for (s of summaries(); track s.currency) {
          <p>
            {{ s.currency }} · Brutos {{ s.gross }} · Cancelados {{ s.cancelled }} · Netos {{ s.net }}
            · Recaudado {{ s.paid_total }} · Saldo {{ s.balance }}
          </p>
        }
        @if (rows().length > 0) {
          <table class="data">
            <thead>
              <tr>
                <th>Servicio</th>
                <th>Reservas</th>
                <th>Viajeros</th>
                <th>Ingresos</th>
              </tr>
            </thead>
            <tbody>
              @for (row of rows(); track $index) {
                <tr>
                  <td>{{ row.item_label }}</td>
                  <td>{{ row.reservation_count }}</td>
                  <td>{{ row.traveler_count }}</td>
                  <td>{{ row.revenue }} {{ row.currency }}</td>
                </tr>
              }
            </tbody>
          </table>
        }
      }
    </div>
  `,
  styles: `
    .stack { display: grid; gap: 1rem; max-width: 48rem; }
  `,
})
export class SalesReportComponent {
  private readonly analytics = inject(AnalyticsService);
  protected readonly from = signal(monthStart());
  protected readonly to = signal(today());
  protected readonly loading = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly summaries = signal<SalesSummary[]>([]);
  protected readonly rows = signal<ProductRankRow[]>([]);

  constructor() {
    void this.load();
  }

  protected onLoad(event: Event): void {
    event.preventDefault();
    void this.load();
  }

  protected onCsv(): void {
    this.analytics.downloadCsv(
      `productos-${this.from()}.csv`,
      this.rows() as unknown as Record<string, unknown>[],
    );
  }

  private async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const [summaries, rows] = await Promise.all([
        this.analytics.salesSummary(this.from(), this.to()),
        this.analytics.productRanking(this.from(), this.to()),
      ]);
      this.summaries.set(summaries);
      this.rows.set(rows);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
