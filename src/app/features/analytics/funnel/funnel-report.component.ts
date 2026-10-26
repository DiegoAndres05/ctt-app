import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import { formatRate, type FunnelReport } from '../../../core/analytics/models/analytics.model';
import { AnalyticsService } from '../../../core/analytics/services/analytics.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

@Component({
  selector: 'app-funnel-report',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [AlertComponent, SpinnerComponent],
  template: `
    <div class="stack">
      <h1>Embudo comercial</h1>
      <form class="filters" (submit)="onLoad($event)">
        <label>Desde <input type="date" [value]="from()" (input)="from.set($any($event.target).value)" /></label>
        <label>Hasta <input type="date" [value]="to()" (input)="to.set($any($event.target).value)" /></label>
        <label>
          Canal
          <select [value]="channel()" (change)="channel.set($any($event.target).value)">
            <option value="">Todos</option>
            <option value="web">Web</option>
            <option value="whatsapp">WhatsApp</option>
            <option value="phone">Teléfono</option>
            <option value="in_person">Presencial</option>
          </select>
        </label>
        <button class="primary" type="submit" [disabled]="loading()">Consultar</button>
        <button type="button" (click)="onCsv()" [disabled]="!report()">Descargar CSV</button>
      </form>
      @if (loading()) {
        <app-spinner label="Cargando embudo…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (report(); as data) {
        @if (data.stages.every((s) => s.count === 0)) {
          <p>No hay movimientos en este período.</p>
        } @else {
          <ol class="funnel">
            @for (stage of data.stages; track stage.stage) {
              <li>
                <strong>{{ stage.label }}</strong>
                <span>{{ stage.count }}</span>
                <span>vs anterior {{ formatRate(stage.conversion_from_previous) }}</span>
                <span>vs solicitudes {{ formatRate(stage.conversion_from_top) }}</span>
                <div class="bar" [style.width.%]="barWidth(stage.conversion_from_top)"></div>
              </li>
            }
          </ol>
        }
      }
    </div>
  `,
  styles: `
    .stack { display: grid; gap: 1rem; max-width: 40rem; }
    .filters { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: end; }
    .funnel { list-style: none; padding: 0; display: grid; gap: 0.75rem; }
    .bar { height: 0.5rem; background: #44403c; margin-top: 0.25rem; }
  `,
})
export class FunnelReportComponent {
  private readonly analytics = inject(AnalyticsService);
  protected readonly from = signal(monthStart());
  protected readonly to = signal(today());
  protected readonly channel = signal('');
  protected readonly loading = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly report = signal<FunnelReport | null>(null);
  protected readonly formatRate = formatRate;

  constructor() {
    void this.load();
  }

  protected barWidth(rate: number | null): number {
    return rate == null ? 0 : Math.round(rate * 100);
  }

  protected onLoad(event: Event): void {
    event.preventDefault();
    void this.load();
  }

  protected onCsv(): void {
    const data = this.report();
    if (!data) {
      return;
    }
    this.analytics.downloadCsv(
      `embudo-${data.from}.csv`,
      data.stages as unknown as Record<string, unknown>[],
    );
  }

  private async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.report.set(
        await this.analytics.funnel(this.from(), this.to(), this.channel() || null),
      );
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}

export function monthStart(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
}

export function today(): string {
  return new Date().toISOString().slice(0, 10);
}
