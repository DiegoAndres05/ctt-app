import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { toAppError, type AppError } from '../../core/error/error-handler';
import {
  QUOTATION_ADJUSTMENT_DIRECTION_LABELS,
  QUOTATION_STATUS_LABELS,
  type PublicQuotation,
  type PublicQuotationAdjustment,
  type QuotationAdjustmentDirection,
  type QuotationStatus,
} from '../../core/quotations/models/quotation.model';
import { QuotationService } from '../../core/quotations/services/quotation.service';
import { AlertComponent } from '../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../shared/components/spinner/spinner.component';

type Phase = 'loading' | 'ready' | 'failed';

/**
 * Public, read-only proposal page (US3 + US4, `/q/:token`).
 *
 * Renders exactly what `get_public_quotation` returns: the server owns every amount and
 * this screen never sums or recomputes one (FR-002). The token arrives as the route
 * parameter, travels only in the RPC calls and is never rendered. No session, no shell,
 * no customer data — the RPC payload carries none (FR-007).
 *
 * Acceptance is the client's two-step action of FR-010: «Aceptar propuesta» reveals
 * «Confirmar aceptación», which calls `accept_public_quotation` with `p_confirmed: true`.
 * The page never navigates to the reservations module (feature 006 owns that).
 */
@Component({
  selector: 'app-public-quotation',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, AlertComponent, SpinnerComponent],
  template: `
    <main class="public-page">
      <article class="proposal">
        @if (phase() === 'loading') {
          <app-spinner label="Cargando propuesta…" />
        } @else if (phase() === 'failed') {
          <h1>Propuesta</h1>
          @if (error(); as failure) {
            <app-alert kind="error">{{ failure.message }}</app-alert>
          }
          <p class="notice">
            No pudimos mostrar esta propuesta en este momento. Vuelve a intentarlo más tarde.
          </p>
        } @else if (proposal(); as quote) {
          @if (quote.available) {
            <header class="heading">
              <h1>Propuesta {{ quote.reference }}</h1>
              <p class="meta">
                Versión {{ quote.version_number }} · {{ statusLabel(quote.status) }}
              </p>
              <p class="meta">
                {{ quote.party_adults }} {{ quote.party_adults === 1 ? 'adulto' : 'adultos' }} ·
                {{ quote.party_children }}
                {{ quote.party_children === 1 ? 'niño' : 'niños' }}
              </p>
            </header>

            @if (error(); as failure) {
              <app-alert kind="error">{{ failure.message }}</app-alert>
            }
            @if (accepted()) {
              <app-alert kind="success">
                Propuesta aceptada. La reserva se confirma en el módulo de reservas.
              </app-alert>
            } @else if (quote.status === 'expired') {
              <app-alert kind="warning">
                Esta propuesta expiró. Hay que emitir una versión nueva.
              </app-alert>
            } @else if (quote.status === 'rejected') {
              <app-alert kind="warning">
                Esta propuesta fue rechazada. Contacta a la agencia si quieres retomarla.
              </app-alert>
            }

            <section class="section">
              <h2>Itinerario</h2>
              <div class="table-wrap">
                <table class="data">
                  <thead>
                    <tr>
                      <th>Servicio</th>
                      <th>Fechas</th>
                      <th>Base</th>
                      <th>Precio unitario</th>
                      <th>Impuesto (%)</th>
                      <th>Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    @for (line of quote.lines; track $index) {
                      <tr>
                        <td>{{ line.label }}</td>
                        <td>{{ dates(line.start_date, line.end_date) }}</td>
                        <td>{{ line.charge_basis }}</td>
                        <td>{{ line.unit_price }} {{ quote.currency }}</td>
                        <td>{{ line.tax_rate }}</td>
                        <td>{{ line.line_total }} {{ quote.currency }}</td>
                      </tr>
                    }
                  </tbody>
                </table>
              </div>
            </section>

            @if (quote.adjustments.length > 0) {
              <section class="section">
                <h2>Ajustes</h2>
                <ul class="adjustments">
                  @for (adjustment of quote.adjustments; track $index) {
                    <li>
                      {{ adjustment.label }} · {{ directionLabel(adjustment.direction) }} ·
                      {{ adjustmentValue(adjustment, quote.currency) }}
                    </li>
                  }
                </ul>
              </section>
            }

            <section class="section">
              <h2>Desglose</h2>
              <dl class="totals">
                <div>
                  <dt>Subtotal</dt>
                  <dd>{{ quote.subtotal }} {{ quote.currency }}</dd>
                </div>
                <div>
                  <dt>Impuestos</dt>
                  <dd>{{ quote.tax_total }} {{ quote.currency }}</dd>
                </div>
                <div>
                  <dt>Ajustes</dt>
                  <dd>{{ quote.adjustment_total }} {{ quote.currency }}</dd>
                </div>
                <div>
                  <dt>Total</dt>
                  <dd>{{ quote.total }} {{ quote.currency }}</dd>
                </div>
              </dl>
              <p class="hint">
                Los importes los calcula y guarda la agencia; esta página solo los muestra.
              </p>
            </section>

            @if (quote.inclusions) {
              <section class="section">
                <h2>Inclusiones</h2>
                <p>{{ quote.inclusions }}</p>
              </section>
            }
            @if (quote.exclusions) {
              <section class="section">
                <h2>Exclusiones</h2>
                <p>{{ quote.exclusions }}</p>
              </section>
            }

            <section class="section">
              <h2>Condiciones y vigencia</h2>
              <p>Condiciones: {{ quote.terms || '—' }}</p>
              <p>
                Vigencia:
                {{ quote.valid_until ? (quote.valid_until | date: 'medium') : '—' }}
              </p>
            </section>

            @if (!accepted() && quote.can_accept) {
              <section class="section">
                <h2>Respuesta</h2>
                @if (confirmPending()) {
                  <p>
                    Aceptas la propuesta {{ quote.reference }} por {{ quote.total }}
                    {{ quote.currency }}. Confirma para registrar tu aceptación.
                  </p>
                  <div class="actions">
                    <button
                      class="primary"
                      type="button"
                      (click)="onConfirmAccept()"
                      [disabled]="accepting()"
                    >
                      Confirmar aceptación
                    </button>
                    <button
                      type="button"
                      (click)="confirmPending.set(false)"
                      [disabled]="accepting()"
                    >
                      Cancelar
                    </button>
                  </div>
                } @else {
                  <div class="actions">
                    <button
                      class="primary"
                      type="button"
                      (click)="confirmPending.set(true)"
                      [disabled]="accepting()"
                    >
                      Aceptar propuesta
                    </button>
                    <button type="button" (click)="changesHint.set(true)">
                      Requiere modificaciones
                    </button>
                  </div>
                }
                @if (changesHint()) {
                  <p class="notice">
                    ¿Necesitas cambios en la propuesta? Contacta a la agencia: prepararemos una
                    versión nueva contigo. Esta página no registra ese pedido.
                  </p>
                }
              </section>
            } @else if (quote.status === 'issued') {
              <app-alert kind="warning">
                Esta propuesta expiró. Hay que emitir una versión nueva.
              </app-alert>
            }
          } @else {
            <h1>Propuesta</h1>
            <app-alert kind="warning">Esta propuesta ya no está disponible.</app-alert>
            <p class="notice">Contacta a la agencia si necesitas más información sobre tu viaje.</p>
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

    .proposal {
      display: grid;
      gap: 0.85rem;
      width: min(44rem, 100%);
    }

    .heading {
      display: grid;
      gap: 0.15rem;
    }

    .heading h1 {
      margin: 0;
    }

    .meta {
      margin: 0;
      color: #44403c;
    }

    .table-wrap {
      overflow-x: auto;
    }

    .totals {
      display: grid;
      gap: 0.25rem;
      margin: 0;
    }

    .totals div {
      display: flex;
      justify-content: space-between;
      gap: 0.5rem;
    }

    .totals dd {
      margin: 0;
    }

    .adjustments {
      display: grid;
      gap: 0.25rem;
      margin: 0;
      padding: 0;
      list-style: none;
    }

    @media print {
      .public-page {
        padding: 0;
      }
    }
  `,
})
export class PublicQuotationComponent {
  private readonly quotes = inject(QuotationService);

  /** The opaque public token, bound from the `q/:token` route parameter. */
  readonly token = input.required<string>();

  protected readonly phase = signal<Phase>('loading');
  protected readonly proposal = signal<PublicQuotation | null>(null);
  protected readonly error = signal<AppError | null>(null);
  protected readonly accepting = signal(false);
  /** Step one of the two-step acceptance (FR-010): nothing is sent until the client confirms. */
  protected readonly confirmPending = signal(false);
  /** Local success state; the server is the authority and a re-read shows `accepted` anyway. */
  protected readonly accepted = signal(false);
  /** The "Requiere modificaciones" hint (spec clarification 2026-10-04: contact the agency). */
  protected readonly changesHint = signal(false);

  constructor() {
    effect(() => {
      const token = this.token();
      untracked(() => void this.load(token));
    });
  }

  protected statusLabel(status: QuotationStatus): string {
    return QUOTATION_STATUS_LABELS[status];
  }

  protected directionLabel(direction: QuotationAdjustmentDirection): string {
    return QUOTATION_ADJUSTMENT_DIRECTION_LABELS[direction];
  }

  /** Paints the adjustment value exactly as stored: percent points or an absolute amount. */
  protected adjustmentValue(adjustment: PublicQuotationAdjustment, currency: string): string {
    return adjustment.kind === 'percent'
      ? `${adjustment.value} %`
      : `${adjustment.value} ${currency}`;
  }

  protected dates(start: string, end: string | null): string {
    const first = formatDay(start);
    return end ? `${first} – ${formatDay(end)}` : first;
  }

  protected async onConfirmAccept(): Promise<void> {
    if (this.accepting()) {
      return;
    }
    this.accepting.set(true);
    this.error.set(null);
    try {
      const result = await this.quotes.acceptPublic(this.token(), true);
      if (!result.available) {
        // The link stopped working while the client was confirming: show the reason.
        await this.load(this.token());
        return;
      }
      this.accepted.set(true);
      this.confirmPending.set(false);
    } catch (failure) {
      const appError = toAppError(failure);
      // QUOTATION_STALE leaves the version expired server-side: refresh, then explain.
      if (appError.code === 'QUOTATION_STALE') {
        await this.load(this.token());
      }
      this.error.set(appError);
    } finally {
      this.accepting.set(false);
    }
  }

  private async load(token: string): Promise<void> {
    this.phase.set('loading');
    this.proposal.set(null);
    this.error.set(null);
    this.accepted.set(false);
    this.confirmPending.set(false);
    this.changesHint.set(false);
    try {
      const proposal = await this.quotes.getPublic(token);
      this.proposal.set(proposal);
      this.accepted.set(proposal.available && proposal.status === 'accepted');
      this.phase.set('ready');
    } catch (failure) {
      this.error.set(toAppError(failure));
      this.phase.set('failed');
    }
  }
}

/** `dd/mm/yyyy` for the itinerary dates the RPC returns as `yyyy-mm-dd`. */
function formatDay(value: string | null): string {
  if (!value) {
    return '—';
  }
  const [year, month, day] = value.slice(0, 10).split('-');
  if (!year || !month || !day) {
    return value;
  }
  return `${day}/${month}/${year}`;
}
