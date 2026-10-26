import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { formatRate, type FunnelReport } from '../../core/analytics/models/analytics.model';
import { AnalyticsService } from '../../core/analytics/services/analytics.service';
import { hasRoleAtLeast } from '../../core/auth/models/user.model';
import { AuthService } from '../../core/auth/services/auth.service';
import { monthStart, today } from '../analytics/funnel/funnel-report.component';

@Component({
  selector: 'app-dashboard',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <section class="dashboard">
      <h1>Hola, {{ name() }}</h1>
      @if (showFunnel()) {
        <p>Embudo de este mes</p>
        @if (funnel(); as data) {
          <ul>
            @for (stage of data.stages; track stage.stage) {
              <li>{{ stage.label }}: {{ stage.count }} ({{ formatRate(stage.conversion_from_top) }})</li>
            }
          </ul>
          <a routerLink="/reports/funnel">Ver reportes</a>
        }
      } @else {
        <p>
          Este es tu panel. Los indicadores globales están en Reportes para operadores y
          administradores.
        </p>
      }
    </section>
  `,
  styles: `
    .dashboard {
      display: grid;
      gap: 0.5rem;
      max-width: 40rem;
    }
    h1,
    p {
      margin: 0;
    }
  `,
})
export class DashboardComponent {
  private readonly auth = inject(AuthService);
  private readonly analytics = inject(AnalyticsService);
  protected readonly formatRate = formatRate;
  protected readonly funnel = signal<FunnelReport | null>(null);
  protected readonly showFunnel = computed(() =>
    hasRoleAtLeast(this.auth.profile()?.role ?? null, 'operator'),
  );

  constructor() {
    effect(() => {
      if (!this.showFunnel()) {
        return;
      }
      untracked(() => {
        void this.analytics
          .funnel(monthStart(), today(), null)
          .then((data) => this.funnel.set(data))
          .catch(() => this.funnel.set(null));
      });
    });
  }

  protected name(): string {
    return this.auth.profile()?.full_name ?? '';
  }
}
