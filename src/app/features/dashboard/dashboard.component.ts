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
import {
  formatRate,
  type FunnelReport,
  type FunnelStage,
  type FunnelStageId,
  type OpsTimesReport,
  type ProductRankRow,
  type SalesSummary,
  type StaleItem,
} from '../../core/analytics/models/analytics.model';
import { AnalyticsService } from '../../core/analytics/services/analytics.service';
import {
  REQUEST_STATUS_LABELS,
  type RequestStatus,
} from '../../core/customers/models/request.model';
import {
  PRE_RESERVATION_STATUS_LABELS,
  type PreReservationStatus,
} from '../../core/pre-reservations/models/pre-reservation.model';
import { hasRoleAtLeast } from '../../core/auth/models/user.model';
import { AuthService } from '../../core/auth/services/auth.service';
import { SupabaseService } from '../../core/auth/services/supabase.service';
import { toAppError, type AppError } from '../../core/error/error-handler';
import { AlertComponent } from '../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../shared/components/spinner/spinner.component';
import { monthStart, today } from '../analytics/funnel/funnel-report.component';

/** Cards on the home screen. Verified is the operational bottleneck; confirmed is the outcome. */
const KPI_STAGES: readonly { stage: FunnelStageId; emphasis?: boolean }[] = [
  { stage: 'requests' },
  { stage: 'verified' },
  { stage: 'quotations_issued' },
  { stage: 'reservations_confirmed', emphasis: true },
];

const ATTENTION_LIMIT = 5;

@Component({
  selector: 'app-dashboard',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <section class="home">
      <header class="hero">
        <div>
          <p class="eyebrow">
            @if (funnel()?.scope === 'self') {
              Tus casos ·
            }
            {{ periodLabel }}
          </p>
          <h1>Hola, {{ name() || 'equipo' }}</h1>
          @if (organization(); as org) {
            <p class="lede">{{ org }}</p>
          }
        </div>
        <div class="actions">
          <a class="btn primary" routerLink="/sales/requests/new">Nueva solicitud</a>
          <a class="btn" routerLink="/reports/funnel">Ver embudo</a>
        </div>
      </header>

      @if (loading()) {
        <app-spinner label="Cargando el panel…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (funnel(); as report) {
        <div class="kpis">
          @for (card of kpis(); track card.stage) {
            <a class="kpi" [class.emphasis]="card.emphasis" [routerLink]="card.path">
              <span>{{ card.label }}</span>
              <strong>{{ card.count }}</strong>
              <small>{{ card.note }}</small>
            </a>
          }
        </div>

        <div class="grid">
          <article class="card">
            <header class="card-head">
              <h2>Embudo</h2>
              <a routerLink="/reports/funnel">Detalle</a>
            </header>
            @if (report.stages.every((stage) => stage.count === 0)) {
              <p class="empty">No hay movimientos en este período.</p>
            } @else {
              <ol class="funnel">
                @for (stage of report.stages; track stage.stage) {
                  <li>
                    <div class="stage-line">
                      <a [routerLink]="stagePath(stage.stage)">{{ stage.label }}</a>
                      <strong>{{ stage.count }}</strong>
                    </div>
                    <div class="bar" aria-hidden="true">
                      <span [style.width.%]="barWidth(stage)"></span>
                    </div>
                    <p class="meta">{{ stageCaption(stage) }}</p>
                  </li>
                }
              </ol>
            }
          </article>

          <div class="side">
            <article class="card" [class.attention]="stale().length > 0">
              <header class="card-head">
                <h2>Atención</h2>
                <a routerLink="/reports/ops">Tiempos</a>
              </header>
              @if (stale().length === 0) {
                <p class="empty">Nada pendiente de atención.</p>
              } @else {
                <ul class="queue">
                  @for (item of attention(); track item.id) {
                    <li>
                      <a [routerLink]="itemPath(item)">{{ item.reference }}</a>
                      <span>{{ kindLabel(item.kind) }} · {{ statusText(item) }}</span>
                      <small>{{ ageText(item.age_hours) }}</small>
                    </li>
                  }
                </ul>
                @if (attentionExtra() > 0) {
                  <a class="more" routerLink="/reports/ops"
                    >{{ attentionExtra() }} más en tiempos</a
                  >
                }
              }
            </article>

            @if (commercial()) {
              <article class="card">
                <header class="card-head">
                  <h2>Ingresos</h2>
                  <a routerLink="/reports/products">Productos</a>
                </header>
                @if (financeError(); as message) {
                  <app-alert kind="error">{{ message }}</app-alert>
                } @else if (sales().length === 0) {
                  <p class="empty">Sin importes de reserva en este período.</p>
                } @else {
                  @for (row of sales(); track row.currency) {
                    <dl class="figures">
                      <div>
                        <dt>Neto {{ row.currency }}</dt>
                        <dd>{{ money(row.net, row.currency) }}</dd>
                      </div>
                      <div>
                        <dt>Recaudado</dt>
                        <dd>{{ money(row.paid_total, row.currency) }}</dd>
                      </div>
                      <div>
                        <dt>Saldo</dt>
                        <dd>{{ money(row.balance, row.currency) }}</dd>
                      </div>
                    </dl>
                  }
                }
              </article>
            }

            <article class="card">
              <header class="card-head">
                <h2>Tiempos medios</h2>
              </header>
              @if (times(); as timing) {
                @if (noMeasuredTimes(timing)) {
                  <p class="empty">Todavía no hay tiempos medidos en este período.</p>
                } @else {
                  <dl class="figures">
                    <div>
                      <dt>Respuesta a la solicitud</dt>
                      <dd>{{ hours(timing.avg_request_response_hours) }}</dd>
                    </div>
                    <div>
                      <dt>Verificación</dt>
                      <dd>{{ hours(timing.avg_verification_hours) }}</dd>
                    </div>
                    <div>
                      <dt>Emisión de cotización</dt>
                      <dd>{{ hours(timing.avg_quotation_issue_hours) }}</dd>
                    </div>
                  </dl>
                  <p class="meta">
                    Muestras: {{ timing.sample_request }} solicitudes ·
                    {{ timing.sample_verification }} verificaciones ·
                    {{ timing.sample_quotation }} cotizaciones
                  </p>
                }
              }
            </article>
          </div>
        </div>

        @if (commercial()) {
          <article class="card">
            <header class="card-head">
              <h2>Servicios con reserva</h2>
              <a routerLink="/reports/products">Ranking</a>
            </header>
            @if (products().length === 0) {
              <p class="empty">Todavía no hay servicios reservados en este período.</p>
            } @else {
              <ol class="rank">
                @for (row of products(); track $index; let index = $index) {
                  <li>
                    <span class="rank-name">{{ index + 1 }}. {{ row.item_label }}</span>
                    <span class="detail"
                      >{{ countPhrase(row.reservation_count, 'reserva', 'reservas') }} ·
                      {{ countPhrase(row.traveler_count, 'viajero', 'viajeros') }}</span
                    >
                    <strong>{{ money(row.revenue, row.currency) }}</strong>
                  </li>
                }
              </ol>
            }
          </article>
        }
      }
    </section>
  `,
  styles: `
    .home {
      display: grid;
      gap: 1rem;
      color: #1e293b;
    }
    h1,
    h2,
    p {
      margin: 0;
    }
    .hero {
      display: flex;
      justify-content: space-between;
      gap: 1rem;
      align-items: end;
    }
    .eyebrow {
      color: #0f766e;
      font-size: 0.9rem;
      font-weight: 600;
    }
    h1 {
      font-size: 1.75rem;
      letter-spacing: -0.03em;
      margin-top: 0.2rem;
    }
    .lede {
      color: #64748b;
      margin-top: 0.15rem;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      padding: 0.55rem 0.9rem;
      border-radius: 0.5rem;
      border: 1px solid #dbe3ee;
      background: #fff;
      color: #1e293b;
      text-decoration: none;
      font-weight: 600;
    }
    .btn.primary {
      background: #0f766e;
      border-color: #0f766e;
      color: #fff;
    }
    .btn:hover {
      border-color: #0f766e;
    }
    .btn:focus-visible,
    .kpi:focus-visible,
    .card a:focus-visible {
      outline: 2px solid #0f766e;
      outline-offset: 2px;
    }
    .kpis {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 0.75rem;
    }
    .kpi,
    .card {
      background: #fff;
      border: 1px solid #e7edf4;
      border-radius: 0.75rem;
      box-shadow: 0 1px 2px rgb(15 23 42 / 4%);
    }
    .kpi {
      display: grid;
      gap: 0.15rem;
      padding: 0.9rem 1rem 0.8rem;
      text-decoration: none;
      color: inherit;
      border-bottom: 3px solid #99f6e4;
    }
    .kpi strong {
      font-size: 1.85rem;
      letter-spacing: -0.03em;
      line-height: 1.1;
    }
    .kpi span,
    .kpi small {
      color: #64748b;
    }
    .kpi small {
      font-size: 0.8rem;
    }
    .kpi.emphasis {
      background: #0f766e;
      color: #fff;
      border-bottom-color: #115e59;
    }
    .kpi.emphasis span,
    .kpi.emphasis small {
      color: #ccfbf1;
    }
    .kpi:hover {
      border-color: #5eead4;
    }
    .grid {
      display: grid;
      grid-template-columns: minmax(0, 1.45fr) minmax(17rem, 0.85fr);
      gap: 0.75rem;
      align-items: start;
    }
    .side {
      display: grid;
      gap: 0.75rem;
    }
    .card {
      padding: 1rem 1.05rem 1.05rem;
    }
    .card-head {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 0.5rem;
      margin-bottom: 0.8rem;
    }
    .card-head h2 {
      font-size: 1rem;
    }
    .card-head a,
    .more {
      color: #0f766e;
      font-weight: 700;
      text-decoration: none;
    }
    .more {
      display: inline-block;
      margin-top: 0.7rem;
    }
    .funnel,
    .queue,
    .rank {
      list-style: none;
      margin: 0;
      padding: 0;
    }
    .funnel {
      display: grid;
      gap: 0.85rem;
    }
    .stage-line,
    .figures div {
      display: flex;
      justify-content: space-between;
      gap: 0.75rem;
      align-items: baseline;
    }
    .stage-line a {
      color: inherit;
      font-weight: 600;
      text-decoration: none;
    }
    .stage-line strong {
      font-variant-numeric: tabular-nums;
    }
    .bar {
      height: 0.55rem;
      margin: 0.4rem 0 0.25rem;
      background: #f1f5f9;
      border-radius: 99px;
      overflow: hidden;
    }
    .card.attention {
      border-color: #fdba74;
      box-shadow: inset 3px 0 0 #c2410c;
    }
    .bar span {
      display: block;
      height: 100%;
      background: #0f766e;
      border-radius: inherit;
    }
    .meta,
    .empty,
    .queue span,
    .queue small,
    .figures dt {
      color: #64748b;
    }
    .meta,
    .empty,
    .queue span,
    .queue small {
      font-size: 0.85rem;
    }
    .queue {
      display: grid;
      gap: 0.65rem;
    }
    .queue li {
      display: grid;
      gap: 0.1rem;
      padding-bottom: 0.55rem;
      border-bottom: 1px solid #f1f5f9;
    }
    .queue a {
      color: #0f766e;
      font-weight: 700;
      text-decoration: none;
    }
    .figures {
      display: grid;
      gap: 0.45rem;
      margin: 0;
    }
    .figures dd {
      margin: 0;
      font-weight: 700;
      font-variant-numeric: tabular-nums;
    }
    .rank {
      display: grid;
      gap: 0.85rem;
    }
    .rank li {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
    }
    .rank-name {
      font-weight: 600;
    }
    .detail {
      grid-column: 1;
      color: #64748b;
      font-size: 0.85rem;
    }
    .rank strong {
      grid-row: 1 / span 2;
      grid-column: 2;
      align-self: center;
    }
    @media (max-width: 980px) {
      .hero {
        align-items: start;
        flex-direction: column;
      }
      .kpis {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .grid {
        grid-template-columns: 1fr;
      }
      .side {
        order: -1;
      }
      .rank li {
        flex-wrap: wrap;
      }
    }
    @media (max-width: 560px) {
      .kpis {
        grid-template-columns: 1fr;
      }
    }
  `,
})
export class DashboardComponent {
  private readonly auth = inject(AuthService);
  private readonly analytics = inject(AnalyticsService);
  private readonly supabase = inject(SupabaseService);

  protected readonly formatRate = formatRate;
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly financeError = signal<string | null>(null);
  protected readonly funnel = signal<FunnelReport | null>(null);
  protected readonly times = signal<OpsTimesReport | null>(null);
  protected readonly stale = signal<StaleItem[]>([]);
  protected readonly sales = signal<SalesSummary[]>([]);
  protected readonly products = signal<ProductRankRow[]>([]);
  protected readonly organization = signal<string | null>(null);

  protected readonly commercial = computed(() => hasRoleAtLeast(this.auth.role(), 'operator'));
  protected readonly name = computed(() => this.auth.profile()?.full_name ?? '');
  protected readonly periodLabel = formatMonth(monthStart());
  protected readonly attention = computed(() => this.stale().slice(0, ATTENTION_LIMIT));
  protected readonly attentionExtra = computed(() =>
    Math.max(0, this.stale().length - ATTENTION_LIMIT),
  );
  protected readonly kpis = computed(() => {
    const stages = this.funnel()?.stages ?? [];
    return KPI_STAGES.map((card) => {
      const stage = stages.find((item) => item.stage === card.stage);
      return {
        stage: card.stage,
        emphasis: card.emphasis === true,
        label: stage?.label ?? card.stage,
        count: stage?.count ?? 0,
        note: stageNote(stage),
        path: this.stagePath(card.stage),
      };
    });
  });

  constructor() {
    effect(() => {
      const role = this.auth.role();
      if (!role) {
        return;
      }
      untracked(() => {
        void this.load(hasRoleAtLeast(role, 'operator'));
      });
    });

    effect(() => {
      const organizationId = this.auth.organizationId();
      if (!organizationId) {
        return;
      }
      untracked(() => {
        void this.loadOrganization(organizationId);
      });
    });
  }

  protected stagePath(stage: FunnelStageId): string {
    if (stage === 'verified' && !this.commercial()) {
      return '/sales/pre-reservations';
    }
    return STAGE_PATHS[stage];
  }

  protected stageCaption(stage: FunnelStage): string {
    if (stage.conversion_from_previous == null) {
      return 'Punto de partida';
    }
    return `${formatRate(stage.conversion_from_previous)} de la etapa anterior · ${formatRate(stage.conversion_from_top)} de las solicitudes`;
  }

  protected barWidth(stage: FunnelStage): number {
    if (stage.conversion_from_top == null) {
      return 0;
    }
    return Math.round(stage.conversion_from_top * 100);
  }

  protected itemPath(item: StaleItem): string[] {
    const root = item.kind === 'request' ? '/sales/requests' : '/sales/pre-reservations';
    return [root, item.id];
  }

  protected kindLabel(kind: StaleItem['kind']): string {
    return kind === 'request' ? 'Solicitud' : 'Pre-reserva';
  }

  protected statusText(item: StaleItem): string {
    if (item.kind === 'request' && isRequestStatus(item.status)) {
      return REQUEST_STATUS_LABELS[item.status];
    }
    if (item.kind === 'pre_reservation' && isPreReservationStatus(item.status)) {
      return PRE_RESERVATION_STATUS_LABELS[item.status];
    }
    return item.status;
  }

  protected ageText(hoursValue: number): string {
    if (hoursValue >= 48) {
      const days = Math.round(hoursValue / 24);
      return this.countPhrase(days, 'día', 'días');
    }
    if (hoursValue >= 24) {
      return '1 día';
    }
    return `${formatAmount(hoursValue)} h`;
  }

  protected countPhrase(count: number, one: string, many: string): string {
    return `${formatAmount(count)} ${count === 1 ? one : many}`;
  }

  protected hours(value: number | null): string {
    return value == null ? '—' : `${formatAmount(value)} h`;
  }

  protected money(amount: number, currency: string): string {
    try {
      return new Intl.NumberFormat('es-CO', {
        style: 'currency',
        currency,
        maximumFractionDigits: 2,
      }).format(amount);
    } catch {
      return `${formatAmount(amount)} ${currency}`;
    }
  }

  protected noMeasuredTimes(timing: OpsTimesReport): boolean {
    return (
      timing.avg_request_response_hours == null &&
      timing.avg_verification_hours == null &&
      timing.avg_quotation_issue_hours == null
    );
  }

  private async load(commercial: boolean): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.financeError.set(null);
    const from = monthStart();
    const to = today();
    try {
      const [funnel, times, stale] = await Promise.all([
        this.analytics.funnel(from, to, null),
        this.analytics.opsTimes(from, to, null),
        this.analytics.staleQueue(),
      ]);
      this.funnel.set(funnel);
      this.times.set(times);
      this.stale.set(stale);
    } catch (failure) {
      this.error.set(toAppError(failure));
      this.loading.set(false);
      return;
    }

    if (commercial) {
      try {
        const [sales, products] = await Promise.all([
          this.analytics.salesSummary(from, to),
          this.analytics.productRanking(from, to, 3),
        ]);
        this.sales.set(sales);
        this.products.set(products);
      } catch (failure) {
        this.financeError.set(toAppError(failure).message);
      }
    }
    this.loading.set(false);
  }

  private async loadOrganization(organizationId: string): Promise<void> {
    const { data } = await this.supabase.client
      .from('organizations')
      .select('name')
      .eq('id', organizationId)
      .maybeSingle<{ name: string }>();
    this.organization.set(data?.name ?? null);
  }
}

const STAGE_PATHS: Record<FunnelStageId, string> = {
  requests: '/sales/requests',
  pre_reservations: '/sales/pre-reservations',
  verified: '/sales/verification',
  quotations_issued: '/sales/quotations',
  reservations_confirmed: '/sales/reservations',
};

function stageNote(stage: FunnelStage | undefined): string {
  if (!stage || stage.stage === 'requests') {
    return 'Inicio del embudo';
  }
  return `Vs anterior ${formatRate(stage.conversion_from_previous)}`;
}

function formatMonth(iso: string): string {
  const [year, month] = iso.split('-').map(Number);
  if (!year || !month) {
    return iso;
  }
  const label = new Intl.DateTimeFormat('es-CO', {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(Date.UTC(year, month - 1, 1)));
  return label.charAt(0).toUpperCase() + label.slice(1);
}

function formatAmount(value: number): string {
  return new Intl.NumberFormat('es-CO', { maximumFractionDigits: 1 }).format(value);
}

function isRequestStatus(value: string): value is RequestStatus {
  return value in REQUEST_STATUS_LABELS;
}

function isPreReservationStatus(value: string): value is PreReservationStatus {
  return value in PRE_RESERVATION_STATUS_LABELS;
}
