import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { form, FormField, required, submit, validate } from '@angular/forms/signals';
import { Router, RouterLink } from '@angular/router';
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import { AuthService } from '../../../../core/auth/services/auth.service';
import type { ChargeType } from '../../../../core/catalog/models/pricing.model';
import { customerDisplayName } from '../../../../core/customers/models/customer.model';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import {
  PRE_RESERVATION_STATUS_LABELS,
  type PreReservationListRow,
} from '../../../../core/pre-reservations/models/pre-reservation.model';
import { PreReservationService } from '../../../../core/pre-reservations/services/pre-reservation.service';
import {
  QUOTATION_ADJUSTMENT_DIRECTION_LABELS,
  QUOTATION_ADJUSTMENT_KIND_LABELS,
  QUOTATION_STATUS_LABELS,
  type QuotationAdjustment,
  type QuotationAdjustmentDirection,
  type QuotationAdjustmentKind,
  type QuotationBreakdown,
  type QuotationDetail,
  type QuotationLine,
  type QuotationResponseKind,
  type QuotationStatus,
} from '../../../../core/quotations/models/quotation.model';
import {
  QuotationService,
  readQuotationToken,
} from '../../../../core/quotations/services/quotation.service';
import {
  LIST_SEARCH_DEBOUNCE_MS,
  debounce,
} from '../../../../shared/components/data-table/list-query';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../../shared/components/unsaved-changes.guard';

/**
 * A breakdown line: the RPC identifies the row as `line_id`, the detail read as `id`.
 * The UI needs whichever one the loaded source carries to target `set_quotation_line_tax`.
 */
type BreakdownLine = QuotationLine & { line_id?: string };

type Phase = 'loading' | 'creating' | 'picker' | 'editor' | 'failed';

/** Copy of contracts §7 for a validity the server rejects with either cap error. */
const VALIDITY_CAP_COPY = 'La vigencia no puede pasar de la retención ni de 30 días.';

/**
 * Statuses whose proposal already reached the customer (contracts §4): only these admit
 * the WhatsApp copy and the public link.
 */
const DELIVERED_STATUSES: readonly QuotationStatus[] = [
  'issued',
  'accepted',
  'rejected',
  'expired',
];

/** Success copy after «Registrar respuesta», plus the FR-011 version hint. */
const RESPONSE_NOTICES: Record<QuotationResponseKind, string> = {
  accepted: 'Respuesta registrada: la cotización quedó aceptada.',
  rejected: 'Respuesta registrada: la cotización quedó rechazada.',
  changes_requested:
    'Se registró «Requiere modificaciones». Cree una versión nueva para atender los cambios.',
};

const EMPTY_ADJUSTMENT = {
  label: '',
  direction: 'discount' as QuotationAdjustmentDirection,
  kind: 'percent' as QuotationAdjustmentKind,
  value: 0,
  target: '',
};

/**
 * Draft editor and detail screen for one quotation (US1 + US2).
 *
 * Reachable as `quotations/new` (pick a quotable pre-reservation, or create the draft
 * straight away from `?preReservationId=`), as `quotations/:versionId`, and later as the
 * target of the US4 response/version actions. Every amount on screen comes from the
 * server: `recalculate` and the other RPCs return the persisted breakdown and this
 * component never sums or multiplies one (FR-002). `unsavedChangesGuard` only fires while
 * the version is a `draft`.
 */
@Component({
  selector: 'app-quotation-editor',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <div class="stack">
      <a class="button-link" routerLink="/sales/quotations">Volver a cotizaciones</a>

      @if (phase() === 'loading') {
        <app-spinner label="Cargando cotización…" />
      } @else if (phase() === 'creating') {
        <app-spinner label="Creando borrador…" />
      } @else if (detail(); as current) {
        <header class="heading">
          <h1>{{ current.reference ?? 'Cotización sin emitir' }}</h1>
          <p>{{ statusLabel(current.status) }} · v{{ current.version_number }}</p>
        </header>

        @if (errorMessage(); as message) {
          <app-alert kind="error">{{ message }}</app-alert>
        }
        @if (notice(); as text) {
          <app-alert kind="success">
            {{ text }}
            @if (publicLink(); as link) {
              <a [href]="link" target="_blank" rel="noopener noreferrer">{{ link }}</a>
            }
          </app-alert>
        }
        @if (current.status === 'superseded') {
          <app-alert kind="info">
            Superada por nueva versión. Esta versión ya no admite respuestas ni cambios.
          </app-alert>
        }

        <section class="section">
          <h2>Desglose</h2>

          @if (breakdown(); as prices) {
            <dl class="totals">
              <div>
                <dt>Subtotal</dt>
                <dd>{{ prices.subtotal }} {{ prices.currency }}</dd>
              </div>
              <div>
                <dt>Impuestos</dt>
                <dd>{{ prices.tax_total }} {{ prices.currency }}</dd>
              </div>
              <div>
                <dt>Ajustes</dt>
                <dd>{{ prices.adjustment_total }} {{ prices.currency }}</dd>
              </div>
              <div>
                <dt>Total</dt>
                <dd>{{ prices.total }} {{ prices.currency }}</dd>
              </div>
            </dl>
          }

          @if (pendingCurrencies().length > 0) {
            <fieldset class="plain">
              <legend>Tasa de cambio</legend>
              <p class="hint">Falta la tasa de cambio para emitir.</p>
              @for (currency of pendingCurrencies(); track currency) {
                <label [attr.for]="'rate-' + currency">Tasa de cambio ({{ currency }})</label>
                <div class="rate-row">
                  <input
                    [id]="'rate-' + currency"
                    type="number"
                    min="0"
                    step="0.000001"
                    [value]="rateDraft()[currency] ?? ''"
                    (input)="onRateInput(currency, $event)"
                  />
                  <button type="button" (click)="saveRate(currency)" [disabled]="saving()">
                    Guardar tasa
                  </button>
                </div>
              }
            </fieldset>
          }

          <div class="table-wrap">
            <table class="data">
              <thead>
                <tr>
                  <th>Servicio</th>
                  <th>Fechas</th>
                  <th>Tipo de cobro</th>
                  <th>Base</th>
                  <th>Precio unitario</th>
                  <th>Impuesto (%)</th>
                  <th>Ajuste</th>
                  <th>Total</th>
                </tr>
              </thead>
              <tbody>
                @for (line of lines(); track lineId(line)) {
                  <tr>
                    <td>
                      {{ line.item_label }}
                      <span class="muted">{{ linePax(line) }}</span>
                    </td>
                    <td>{{ lineDates(line) }}</td>
                    <td>{{ chargeLabel(line.charge_type) }} · base {{ line.charge_basis }}</td>
                    <td>{{ line.line_base }}</td>
                    <td>{{ line.unit_price }}</td>
                    <td>
                      @if (isDraft()) {
                        <input
                          type="number"
                          min="0"
                          max="100"
                          step="0.01"
                          [value]="line.tax_rate"
                          (change)="onTaxChange(line, $event)"
                          [disabled]="saving()"
                          [attr.aria-label]="'Impuesto (%) de ' + line.item_label"
                        />
                      } @else {
                        {{ line.tax_rate }}
                      }
                    </td>
                    <td>{{ line.line_adjustment }}</td>
                    <td>{{ line.line_total }}</td>
                  </tr>
                }
              </tbody>
            </table>
          </div>

          <p class="hint">
            Los importes los calcula y guarda el servidor; el navegador no suma ni multiplica nada.
          </p>
          @if (isDraft()) {
            <div class="actions">
              <button type="button" (click)="onRecalculate()" [disabled]="saving()">
                Recalcular
              </button>
            </div>
          }
        </section>

        <section class="section">
          <h2>Ajustes</h2>
          @if (adjustments().length === 0) {
            <p class="notice">Todavía no hay ajustes.</p>
          } @else {
            <div class="table-wrap">
              <table class="data">
                <thead>
                  <tr>
                    <th>Etiqueta</th>
                    <th>Alcance</th>
                    <th>Dirección</th>
                    <th>Tipo</th>
                    <th>Valor</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  @for (adjustment of adjustments(); track adjustment.id) {
                    <tr>
                      <td>{{ adjustment.label }}</td>
                      <td>{{ scopeLabel(adjustment) }}</td>
                      <td>{{ directionLabel(adjustment.direction) }}</td>
                      <td>{{ kindLabel(adjustment.kind) }}</td>
                      <td>{{ valueLabel(adjustment) }}</td>
                      <td>
                        @if (isDraft()) {
                          <button
                            type="button"
                            (click)="onDeleteAdjustment(adjustment)"
                            [disabled]="saving()"
                          >
                            Eliminar
                          </button>
                        }
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          }

          @if (isDraft()) {
            <form (submit)="onSaveAdjustment($event)" novalidate>
              <h3>Nuevo ajuste</h3>

              <label class="req" for="adjustment-label">Etiqueta</label>
              <input id="adjustment-label" type="text" [formField]="adjustmentForm.label" />
              @if (adjustmentForm.label().touched() && adjustmentForm.label().invalid()) {
                <p class="field-error">El ajuste necesita una etiqueta.</p>
              }

              <label for="adjustment-direction">Dirección</label>
              <select id="adjustment-direction" [formField]="adjustmentForm.direction">
                <option value="discount">Descuento</option>
                <option value="surcharge">Suplemento</option>
              </select>

              <label for="adjustment-kind">Tipo</label>
              <select id="adjustment-kind" [formField]="adjustmentForm.kind">
                <option value="percent">Porcentaje</option>
                <option value="amount">Monto fijo</option>
              </select>

              <label class="req" for="adjustment-value">Valor</label>
              <input
                id="adjustment-value"
                type="number"
                step="0.01"
                [formField]="adjustmentForm.value"
              />
              @if (adjustmentForm.value().touched() && adjustmentForm.value().invalid()) {
                <p class="field-error">El valor debe ser mayor que cero.</p>
              }

              <label for="adjustment-target">Aplicar a</label>
              <select id="adjustment-target" [formField]="adjustmentForm.target">
                <option value="">Toda la cotización</option>
                @for (line of lines(); track lineId(line)) {
                  <option [value]="line.pre_reservation_item_id">{{ line.item_label }}</option>
                }
              </select>
              <p class="hint">
                Un agente ajusta hasta un 15 % acumulado; por encima el ajuste lo autoriza un
                administrador.
              </p>

              <div class="actions">
                <button class="primary" type="submit" [disabled]="saving()">Agregar ajuste</button>
              </div>
            </form>
          }
        </section>

        <section class="section">
          <h2>Textos de la propuesta</h2>
          @if (isDraft()) {
            <form (submit)="onSaveTexts($event)" novalidate>
              <label for="inclusions">Inclusiones</label>
              <textarea id="inclusions" rows="4" [formField]="textsForm.inclusions"></textarea>

              <label for="exclusions">Exclusiones</label>
              <textarea id="exclusions" rows="4" [formField]="textsForm.exclusions"></textarea>

              <label for="notes">Notas internas</label>
              <textarea id="notes" rows="3" [formField]="textsForm.notes"></textarea>
              <p class="hint">Las notas internas nunca aparecen en la propuesta pública.</p>

              <div class="actions">
                <button class="primary" type="submit" [disabled]="saving()">Guardar textos</button>
              </div>
            </form>
          } @else {
            <h3>Inclusiones</h3>
            <p>{{ current.inclusions || '—' }}</p>
            <h3>Exclusiones</h3>
            <p>{{ current.exclusions || '—' }}</p>
            @if (current.commercial_notes) {
              <h3>Notas internas</h3>
              <p>{{ current.commercial_notes }}</p>
            }
          }
        </section>

        <section class="section">
          <h2>Condiciones y vigencia</h2>
          @if (isDraft()) {
            <form (submit)="onIssue($event)" novalidate>
              <label class="req" for="terms">Condiciones de la propuesta</label>
              <textarea id="terms" rows="5" [formField]="termsForm.terms"></textarea>
              @if (termsForm.terms().touched() && termsForm.terms().invalid()) {
                <p class="field-error">Faltan las condiciones de la propuesta.</p>
              }

              <label for="valid-until">Vigencia</label>
              <input id="valid-until" type="datetime-local" [formField]="termsForm.validUntil" />
              <p class="hint">
                Déjala vacía para la vigencia por defecto (48 horas). Nunca pasa de la retención de
                la pre-reserva ni de 30 días.
              </p>

              <div class="actions">
                <button class="primary" type="submit" [disabled]="saving()">
                  {{ saving() ? 'Emitiendo…' : 'Emitir cotización' }}
                </button>
              </div>
            </form>
          } @else {
            <p>Condiciones: {{ current.terms || '—' }}</p>
            <p>Vigencia: {{ current.valid_until ? (current.valid_until | date: 'short') : '—' }}</p>
            @if (publicLink(); as link) {
              <p>
                Enlace público:
                <a [href]="link" target="_blank" rel="noopener noreferrer">{{ link }}</a>
              </p>
            }
          }
        </section>

        @if (isDelivered()) {
          <section class="section">
            <h2>Entrega al cliente</h2>
            <p class="hint">
              El texto de WhatsApp lo arma el servidor con la referencia, el itinerario y el total
              congelado; el enlace público se agrega con el token guardado al emitir.
            </p>
            @if (publicLink()) {
              <div class="actions">
                <button type="button" (click)="onCopyWhatsApp()" [disabled]="saving()">
                  Copiar para WhatsApp
                </button>
                <button type="button" (click)="onPrint()">Imprimir</button>
              </div>
            } @else {
              <app-alert kind="warning">
                El enlace se mostró al emitir. Si se perdió, anule y emita una versión nueva.
              </app-alert>
              <div class="actions">
                <button type="button" (click)="onPrint()">Imprimir</button>
              </div>
            }
          </section>
        }

        @if (canRecordResponse()) {
          <section class="section">
            <h2>Registrar respuesta</h2>
            <p class="hint">
              Registra la respuesta del cliente sobre la propuesta emitida; queda auditada con
              origen agente.
            </p>
            <div class="actions">
              <button type="button" (click)="onRecordResponse('accepted')" [disabled]="saving()">
                Aceptada
              </button>
              <button type="button" (click)="onRecordResponse('rejected')" [disabled]="saving()">
                Rechazada
              </button>
              <button
                type="button"
                (click)="onRecordResponse('changes_requested')"
                [disabled]="saving()"
              >
                Registrar «Requiere modificaciones»
              </button>
            </div>
          </section>
        }

        @if (canCreateVersion()) {
          <section class="section">
            <h2>Versionado</h2>
            <p class="hint">
              La versión actual queda «Superada por nueva versión» y la nueva abre como borrador con
              las tarifas vigentes. El enlace público sigue siendo el mismo.
            </p>
            <div class="actions">
              <button type="button" (click)="onCreateVersion()" [disabled]="saving()">
                Crear nueva versión
              </button>
            </div>
          </section>
        }

        @if (isAdmin() && canVoid()) {
          <section class="section">
            <h2>Anular cotización</h2>
            <p class="hint">
              Anula la propuesta: el enlace público deja de funcionar. Una cotización aceptada no se
              anula.
            </p>
            <label class="req" for="void-reason">Motivo de la anulación</label>
            <input
              id="void-reason"
              type="text"
              maxlength="500"
              [value]="voidReason()"
              (input)="onVoidReasonInput($event)"
              [disabled]="saving()"
            />
            <div class="actions">
              <button type="button" (click)="onVoid()" [disabled]="saving()">
                Anular cotización
              </button>
            </div>
          </section>
        }

        @if (isAdmin()) {
          <section class="section">
            <h2>Plantilla de condiciones</h2>
            <p class="hint">
              Texto con el que empiezan las cotizaciones nuevas de la organización.
            </p>
            <form (submit)="onSaveDefaults($event)" novalidate>
              <label class="req" for="defaults-terms">Condiciones por defecto</label>
              <textarea id="defaults-terms" rows="5" [formField]="defaultsForm.terms"></textarea>
              @if (defaultsForm.terms().touched() && defaultsForm.terms().invalid()) {
                <p class="field-error">Faltan las condiciones de la propuesta.</p>
              }

              <div class="actions">
                <button type="submit" [disabled]="saving()">Guardar plantilla</button>
              </div>
            </form>
          </section>
        }
      } @else if (phase() === 'failed') {
        @if (notFound()) {
          <app-alert kind="error">No encontramos esta cotización.</app-alert>
        } @else if (errorMessage(); as message) {
          <app-alert kind="error">{{ message }}</app-alert>
        }
        <p><a class="button-link" routerLink="/sales/quotations">Ir a cotizaciones</a></p>
      } @else {
        <h1>Nueva cotización</h1>
        <p>Elige una pre-reserva cotizable; el borrador lo calcula el servidor.</p>

        @if (errorMessage(); as message) {
          <app-alert kind="error">{{ message }}</app-alert>
        }

        <section class="section">
          <h2>Pre-reserva</h2>

          <label for="candidate-search">Buscar</label>
          <input
            id="candidate-search"
            type="search"
            [value]="candidateQuery()"
            (input)="onCandidateSearch($event)"
            placeholder="Referencia o cliente"
          />

          <label class="req" for="candidate">Pre-reserva cotizable</label>
          <select id="candidate" [value]="picked()" (change)="onCandidateChange($event)">
            <option value="">Elige…</option>
            @for (row of candidates(); track row.id) {
              <option [value]="row.id">{{ candidateLabel(row) }}</option>
            }
          </select>
          @if (candidatesLoading()) {
            <p class="notice">Buscando pre-reservas…</p>
          } @else if (candidates().length === 0) {
            <p class="notice">
              No hay pre-reservas cotizables todavía. Verifica la disponibilidad en Pre-reservas.
            </p>
          }

          <div class="actions">
            <button class="primary" type="button" (click)="onCreateDraft()" [disabled]="!picked()">
              Crear borrador
            </button>
            <a class="button-link" routerLink="/sales/pre-reservations">Ir a pre-reservas</a>
          </div>
        </section>
      }
    </div>
  `,
  styles: `
    .stack {
      display: grid;
      gap: 0.85rem;
    }

    .heading {
      display: flex;
      align-items: baseline;
      gap: 1rem;
    }

    .heading h1,
    .heading p {
      margin: 0;
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
      gap: 0.5rem;
    }

    .totals dt {
      min-width: 7rem;
    }

    .totals dd {
      margin: 0;
    }

    .muted {
      display: block;
      font-size: 0.85rem;
      opacity: 0.8;
    }

    .rate-row {
      display: flex;
      gap: 0.5rem;
      align-items: center;
    }

    .rate-row input {
      max-width: 12rem;
    }

    form {
      display: grid;
      gap: 0.5rem;
    }

    h3 {
      margin: 0;
    }
  `,
})
export class QuotationEditorComponent implements UnsavedChangesHost {
  private readonly quotes = inject(QuotationService);
  private readonly preReservations = inject(PreReservationService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  /** Bound from `quotations/:versionId`; undefined on `quotations/new`. */
  readonly versionId = input<string | undefined>(undefined);
  /** Bound from `?preReservationId=<uuid>`: the screen creates the draft and rewrites the URL. */
  readonly preReservationId = input<string | undefined>(undefined);

  protected readonly phase = signal<Phase>('loading');
  protected readonly detail = signal<QuotationDetail | null>(null);
  protected readonly breakdown = signal<QuotationBreakdown | null>(null);
  protected readonly error = signal<AppError | null>(null);
  protected readonly notFound = signal(false);
  protected readonly notice = signal<string | null>(null);
  protected readonly saving = signal(false);
  protected readonly publicLink = signal<string | null>(null);

  protected readonly candidates = signal<PreReservationListRow[]>([]);
  protected readonly candidatesLoading = signal(false);
  protected readonly candidateQuery = signal('');
  protected readonly picked = signal('');

  protected readonly textsDraft = signal({ inclusions: '', exclusions: '', notes: '' });
  protected readonly textsForm = form(this.textsDraft);

  protected readonly adjustmentDraft = signal({ ...EMPTY_ADJUSTMENT });
  protected readonly adjustmentForm = form(this.adjustmentDraft, (fields) => {
    required(fields.label, { message: 'El ajuste necesita una etiqueta.' });
    validate(fields.value, ({ value }) =>
      value() > 0 ? undefined : { kind: 'positive', message: 'El valor debe ser mayor que cero.' },
    );
  });

  protected readonly termsDraft = signal({ terms: '', validUntil: '' });
  protected readonly termsForm = form(this.termsDraft, (fields) => {
    required(fields.terms, { message: 'Faltan las condiciones de la propuesta.' });
  });

  protected readonly defaultsDraft = signal({ terms: '' });
  protected readonly defaultsForm = form(this.defaultsDraft, (fields) => {
    required(fields.terms, { message: 'Faltan las condiciones de la propuesta.' });
  });

  protected readonly rateDraft = signal<Record<string, string>>({});
  protected readonly voidReason = signal('');

  /** The server owns every amount: these just paint the persisted breakdown. */
  protected readonly lines = computed<BreakdownLine[]>(
    () => this.breakdown()?.lines ?? this.detail()?.lines ?? [],
  );
  protected readonly adjustments = computed<QuotationAdjustment[]>(
    () => this.detail()?.adjustments ?? [],
  );
  protected readonly isDraft = computed(() => this.detail()?.status === 'draft');
  protected readonly isAdmin = computed(() => hasRoleAtLeast(this.auth.role(), 'admin'));

  /** The proposal already reached the customer: WhatsApp copy and public link apply (US3). */
  protected readonly isDelivered = computed(() => {
    const status = this.detail()?.status;
    return status != null && DELIVERED_STATUSES.includes(status);
  });

  /** Only an `issued` version admits a response (contracts §5). */
  protected readonly canRecordResponse = computed(() => this.detail()?.status === 'issued');

  /** Only `issued`, `rejected` and `expired` can be superseded by a new version (contracts §5). */
  protected readonly canCreateVersion = computed(() => {
    const status = this.detail()?.status;
    return status === 'issued' || status === 'rejected' || status === 'expired';
  });

  /** `accepted`, `voided` and `superseded` are closed for voiding (contracts §5). */
  protected readonly canVoid = computed(() => {
    const status = this.detail()?.status;
    return (
      status != null && status !== 'accepted' && status !== 'voided' && status !== 'superseded'
    );
  });

  /**
   * Currencies still missing a rate: whatever the RPC reported, otherwise the lines whose
   * tariff currency differs and carry no rate. A filter, never an amount (FR-002).
   */
  protected readonly pendingCurrencies = computed<string[]>(() => {
    const reported = this.breakdown()?.pending_currencies;
    if (reported) {
      return reported;
    }
    const currency = this.detail()?.currency;
    if (!currency) {
      return [];
    }
    const pending = new Set<string>();
    for (const line of this.lines()) {
      if (line.exchange_rate == null && line.tariff_currency !== currency) {
        pending.add(line.tariff_currency);
      }
    }
    return [...pending];
  });

  /** The cap errors share one sentence (contracts §7); everything else keeps its message. */
  protected readonly errorMessage = computed<string | null>(() => {
    const failure = this.error();
    if (!failure) {
      return null;
    }
    if (failure.code === 'VALIDITY_EXCEEDS_HOLD' || failure.code === 'VALIDITY_EXCEEDS_30_DAYS') {
      return VALIDITY_CAP_COPY;
    }
    return failure.message;
  });

  protected readonly statusLabel = (status: QuotationStatus) => QUOTATION_STATUS_LABELS[status];
  protected readonly directionLabel = (direction: QuotationAdjustmentDirection) =>
    QUOTATION_ADJUSTMENT_DIRECTION_LABELS[direction];
  protected readonly kindLabel = (kind: QuotationAdjustmentKind) =>
    QUOTATION_ADJUSTMENT_KIND_LABELS[kind];

  private textsBaseline = '';
  private termsBaseline = '';
  private draftStartedFor: string | null = null;
  private defaultsLoadedFor: string | null = null;

  private readonly commitCandidateSearch = debounce((value: string) => {
    void this.loadCandidates(value.trim());
  }, LIST_SEARCH_DEBOUNCE_MS);

  constructor() {
    this.destroyRef.onDestroy(() => {
      this.commitCandidateSearch.cancel();
    });

    effect(() => {
      const versionId = this.versionId();
      const preReservationId = this.preReservationId();
      untracked(() => {
        if (versionId) {
          void this.load(versionId);
        } else if (preReservationId) {
          void this.startDraft(preReservationId);
        } else {
          this.showPicker();
        }
      });
    });
  }

  /**
   * `unsavedChangesGuard` only matters while the version is a draft: issued money and
   * texts are frozen by the server and can no longer be edited here.
   */
  hasUnsavedChanges(): boolean {
    if (this.allowLeave() || this.detail()?.status !== 'draft') {
      return false;
    }
    return (
      this.textsSnapshot() !== this.textsBaseline || this.termsSnapshot() !== this.termsBaseline
    );
  }

  protected lineId(line: BreakdownLine): string {
    return line.line_id ?? line.id;
  }

  protected linePax(line: BreakdownLine): string {
    const adults = `${line.adults} ${line.adults === 1 ? 'adulto' : 'adultos'}`;
    const children =
      line.children > 0 ? ` · ${line.children} ${line.children === 1 ? 'niño' : 'niños'}` : '';
    return `${adults}${children} · cantidad ${line.quantity}`;
  }

  protected lineDates(line: BreakdownLine): string {
    const start = formatDay(line.start_date);
    return line.end_date ? `${start} – ${formatDay(line.end_date)}` : start;
  }

  protected chargeLabel(chargeType: ChargeType): string {
    switch (chargeType) {
      case 'per_person':
        return 'Por persona';
      case 'per_night':
        return 'Por noche';
      case 'per_group':
        return 'Por grupo';
    }
  }

  protected scopeLabel(adjustment: QuotationAdjustment): string {
    if (!adjustment.pre_reservation_item_id) {
      return 'Global';
    }
    const line = this.lines().find(
      (candidate) => candidate.pre_reservation_item_id === adjustment.pre_reservation_item_id,
    );
    return line?.item_label ?? 'Línea';
  }

  protected valueLabel(adjustment: QuotationAdjustment): string {
    if (adjustment.kind === 'percent') {
      return `${adjustment.value} %`;
    }
    const currency = this.detail()?.currency;
    return currency ? `${adjustment.value} ${currency}` : `${adjustment.value}`;
  }

  protected candidateLabel(row: PreReservationListRow): string {
    const customer = customerDisplayName({
      first_name: row.customer_first_name,
      last_name: row.customer_last_name,
      is_anonymized: row.customer_is_anonymized,
    });
    return `${row.reference} · ${customer} · ${PRE_RESERVATION_STATUS_LABELS[row.status]}`;
  }

  protected onCandidateSearch(event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.candidateQuery.set(value);
    this.commitCandidateSearch(value);
  }

  protected onCandidateChange(event: Event): void {
    this.picked.set((event.target as HTMLSelectElement).value);
  }

  protected onCreateDraft(): void {
    const preReservationId = this.picked();
    if (preReservationId) {
      void this.startDraft(preReservationId);
    }
  }

  protected onRateInput(currency: string, event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.rateDraft.update((current) => ({ ...current, [currency]: value }));
  }

  protected async saveRate(currency: string): Promise<void> {
    const rate = Number(this.rateDraft()[currency]);
    if (!Number.isFinite(rate) || rate <= 0) {
      this.error.set(toAppError({ message: 'EXCHANGE_RATE_INVALID' }));
      return;
    }
    if (await this.mutate((versionId) => this.quotes.setExchangeRate(versionId, currency, rate))) {
      this.rateDraft.update((current) => {
        const next = { ...current };
        delete next[currency];
        return next;
      });
    }
  }

  protected async onTaxChange(line: BreakdownLine, event: Event): Promise<void> {
    const rate = (event.target as HTMLInputElement).valueAsNumber;
    if (!Number.isFinite(rate) || rate < 0 || rate > 100) {
      this.error.set(toAppError({ message: 'TAX_RATE_OUT_OF_RANGE' }));
      await this.reload();
      return;
    }
    await this.mutate(() => this.quotes.setTax(this.lineId(line), rate));
  }

  protected async onRecalculate(): Promise<void> {
    const versionId = this.detail()?.id;
    if (!versionId || this.saving()) {
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    this.notice.set(null);
    try {
      // The screen paints exactly what the RPC returned; the reload only refreshes the
      // rows that do not travel in the breakdown (texts, adjustments, reference).
      const prices = await this.quotes.recalculate(versionId);
      await this.reload(prices);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  protected async onSaveAdjustment(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);
    this.notice.set(null);
    await submit(this.adjustmentForm, async (fields) => {
      const versionId = this.detail()?.id;
      if (!versionId) {
        return undefined;
      }
      try {
        await this.quotes.saveAdjustment(versionId, {
          pre_reservation_item_id: fields.target().value() || null,
          label: fields.label().value().trim(),
          direction: fields.direction().value(),
          kind: fields.kind().value(),
          value: fields.value().value(),
        });
        this.adjustmentDraft.set({ ...EMPTY_ADJUSTMENT });
        this.notice.set('Ajuste guardado.');
        await this.reload();
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onDeleteAdjustment(adjustment: QuotationAdjustment): Promise<void> {
    if (!window.confirm('¿Eliminar este ajuste de la propuesta?')) {
      return;
    }
    await this.mutate(() => this.quotes.deleteAdjustment(adjustment.id));
  }

  protected async onSaveTexts(event: Event): Promise<void> {
    event.preventDefault();
    const versionId = this.detail()?.id;
    if (!versionId) {
      return;
    }
    const texts = this.textsDraft();
    const saved = await this.mutate(() =>
      this.quotes.setTexts(versionId, {
        inclusions: texts.inclusions,
        exclusions: texts.exclusions,
        notes: texts.notes,
      }),
    );
    if (saved) {
      this.textsBaseline = this.textsSnapshot();
      this.notice.set('Los textos de la propuesta se guardaron.');
    }
  }

  protected async onIssue(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);
    this.notice.set(null);
    await submit(this.termsForm, async (fields) => {
      const versionId = this.detail()?.id;
      if (!versionId) {
        return undefined;
      }
      this.saving.set(true);
      try {
        const validUntil = fields.validUntil().value();
        await this.quotes.setTerms(
          versionId,
          fields.terms().value(),
          validUntil ? new Date(validUntil).toISOString() : null,
        );
        this.termsBaseline = this.termsSnapshot();
        const issued = await this.quotes.issue(versionId);
        this.notice.set(
          `Cotización ${issued.reference} emitida. El enlace público se muestra una sola vez.`,
        );
        await this.reload();
      } catch (failure) {
        this.error.set(toAppError(failure));
      } finally {
        this.saving.set(false);
      }
      return undefined;
    });
  }

  protected async onSaveDefaults(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);
    this.notice.set(null);
    await submit(this.defaultsForm, async (fields) => {
      try {
        await this.quotes.saveDefaults(fields.terms().value());
        this.notice.set('La plantilla de condiciones se guardó.');
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected onVoidReasonInput(event: Event): void {
    this.voidReason.set((event.target as HTMLInputElement).value);
  }

  /**
   * Copies the server-built WhatsApp body plus the public link (T023, research R-009).
   * The RPC carries no URL; the `Detalle:` line uses the token kept in `sessionStorage`
   * at issue time, so the button is only offered while that token is still around.
   */
  protected async onCopyWhatsApp(): Promise<void> {
    const versionId = this.detail()?.id;
    const token = versionId ? readQuotationToken(versionId) : null;
    if (!versionId || !token || this.saving()) {
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    this.notice.set(null);
    try {
      const body = await this.quotes.whatsappText(versionId);
      await navigator.clipboard.writeText(`${body}\nDetalle: ${window.location.origin}/q/${token}`);
      this.notice.set('Texto de WhatsApp copiado al portapapeles.');
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  /** Browser print dialog for the proposal detail (T023, research R-009). */
  protected onPrint(): void {
    window.print();
  }

  /** Agent-registered response on the issued version (T028, contracts §5). */
  protected async onRecordResponse(kind: QuotationResponseKind): Promise<void> {
    const versionId = this.detail()?.id;
    if (!versionId || this.saving()) {
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    this.notice.set(null);
    try {
      await this.quotes.recordResponse(versionId, kind);
      this.notice.set(RESPONSE_NOTICES[kind]);
      await this.reload();
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  /**
   * Supersedes this version and opens draft vN+1 (T028, FR-006): the editor follows the
   * new draft so the agent keeps working on the fresh tariffs.
   */
  protected async onCreateVersion(): Promise<void> {
    const versionId = this.detail()?.id;
    if (!versionId || this.saving()) {
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    this.notice.set(null);
    try {
      const draft = await this.quotes.createVersion(versionId);
      await this.router.navigate(['/sales/quotations', draft.version_id]);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  /** Admin-only void with a mandatory reason (T028, FR-012): the public link dies with it. */
  protected async onVoid(): Promise<void> {
    const versionId = this.detail()?.id;
    if (!versionId || this.saving()) {
      return;
    }
    const reason = this.voidReason().trim();
    if (!reason) {
      this.error.set(toAppError({ message: 'VOID_REASON_REQUIRED' }));
      return;
    }
    if (!window.confirm('¿Anular esta cotización? El enlace público dejará de funcionar.')) {
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    this.notice.set(null);
    try {
      await this.quotes.voidQuotation(versionId, reason);
      this.voidReason.set('');
      this.notice.set('Cotización anulada. El enlace público dejó de funcionar.');
      await this.reload();
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  /** True while the guard may warn: flipped off around navigations we caused ourselves. */
  private allowLeave(): boolean {
    return this.phase() === 'creating';
  }

  private textsSnapshot(): string {
    return JSON.stringify(this.textsDraft());
  }

  private termsSnapshot(): string {
    return JSON.stringify(this.termsDraft());
  }

  private showPicker(): void {
    this.phase.set('picker');
    this.detail.set(null);
    this.breakdown.set(null);
    void this.loadCandidates(this.candidateQuery().trim());
  }

  private async loadCandidates(query: string): Promise<void> {
    this.candidatesLoading.set(true);
    try {
      // `quote_eligible` mirrors `assert_pre_reservation_quotable`; the RPC decides anyway.
      const page = await this.preReservations.listPage({ q: query, page: 1 });
      this.candidates.set(page.rows.filter((row) => row.quote_eligible));
    } catch (failure) {
      this.error.set(toAppError(failure));
      this.candidates.set([]);
    } finally {
      this.candidatesLoading.set(false);
    }
  }

  /** `?preReservationId=`: create — or reopen — the draft, then rewrite the URL (T014). */
  private async startDraft(preReservationId: string): Promise<void> {
    if (this.draftStartedFor === preReservationId) {
      return;
    }
    this.draftStartedFor = preReservationId;
    this.phase.set('creating');
    this.error.set(null);
    this.notice.set(null);
    try {
      const draft = await this.quotes.createDraft(preReservationId);
      await this.router.navigate(['/sales/quotations', draft.version_id], { replaceUrl: true });
    } catch (failure) {
      this.error.set(toAppError(failure));
      this.draftStartedFor = null;
      this.showPicker();
    }
  }

  private async load(versionId: string): Promise<void> {
    this.phase.set('loading');
    this.detail.set(null);
    this.breakdown.set(null);
    this.notFound.set(false);
    this.error.set(null);
    this.notice.set(null);
    this.publicLink.set(null);
    try {
      const detail = await this.quotes.getById(versionId);
      if (!detail) {
        this.notFound.set(true);
        this.phase.set('failed');
        return;
      }
      this.applyDetail(detail);
      this.textsDraft.set({
        inclusions: detail.inclusions,
        exclusions: detail.exclusions,
        notes: detail.commercial_notes ?? '',
      });
      this.termsDraft.set({
        terms: detail.terms,
        validUntil: toLocalInput(detail.valid_until),
      });
      this.adjustmentDraft.set({ ...EMPTY_ADJUSTMENT });
      this.rateDraft.set({});
      this.voidReason.set('');
      this.textsBaseline = this.textsSnapshot();
      this.termsBaseline = this.termsSnapshot();
      this.phase.set('editor');
      void this.loadDefaults(detail.id);
    } catch (failure) {
      this.error.set(toAppError(failure));
      this.phase.set('failed');
    }
  }

  /** Server refresh after a mutation; keeps local draft texts that were not saved yet. */
  private async reload(breakdown?: QuotationBreakdown): Promise<void> {
    const versionId = this.versionId();
    if (!versionId) {
      return;
    }
    try {
      const detail = await this.quotes.getById(versionId);
      if (!detail) {
        this.notFound.set(true);
        this.phase.set('failed');
        return;
      }
      this.applyDetail(detail, breakdown);
    } catch (failure) {
      this.error.set(toAppError(failure));
    }
  }

  private applyDetail(detail: QuotationDetail, breakdown?: QuotationBreakdown): void {
    this.detail.set(detail);
    this.breakdown.set(breakdown ?? breakdownOf(detail));
    const token = DELIVERED_STATUSES.includes(detail.status) ? readQuotationToken(detail.id) : null;
    this.publicLink.set(token ? `${window.location.origin}/q/${token}` : null);
  }

  private async mutate(action: (versionId: string) => Promise<unknown>): Promise<boolean> {
    const versionId = this.detail()?.id;
    if (!versionId || this.saving()) {
      return false;
    }
    this.saving.set(true);
    this.error.set(null);
    this.notice.set(null);
    try {
      await action(versionId);
      await this.reload();
      return true;
    } catch (failure) {
      this.error.set(toAppError(failure));
      return false;
    } finally {
      this.saving.set(false);
    }
  }

  /** Admin-only terms template (T018); a failed read never blocks the editor. */
  private async loadDefaults(versionId: string): Promise<void> {
    if (!this.isAdmin() || this.defaultsLoadedFor === versionId) {
      return;
    }
    try {
      const terms = await this.quotes.getDefaults();
      this.defaultsDraft.set({ terms: terms ?? '' });
      this.defaultsLoadedFor = versionId;
    } catch {
      this.defaultsDraft.set({ terms: '' });
    }
  }
}

/**
 * The header amounts of a freshly loaded version, copied column-for-column from
 * `quotation_versions` (they are persisted by the pricing core, never summed here).
 */
function breakdownOf(detail: QuotationDetail): QuotationBreakdown {
  return {
    version_id: detail.id,
    version_number: detail.version_number,
    status: detail.status,
    currency: detail.currency,
    subtotal: detail.subtotal,
    tax_total: detail.tax_total,
    adjustment_total: detail.adjustment_total,
    total: detail.total,
    lines: detail.lines,
  };
}

/** `datetime-local` value for an instant, in the browser's timezone. */
function toLocalInput(iso: string | null): string {
  if (!iso) {
    return '';
  }
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  const pad = (value: number): string => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(
    date.getHours(),
  )}:${pad(date.getMinutes())}`;
}

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
