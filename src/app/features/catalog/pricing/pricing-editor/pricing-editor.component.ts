import {
  ChangeDetectionStrategy,
  Component,
  effect,
  inject,
  input,
  output,
  signal,
  untracked,
} from '@angular/core';
import { DatePipe } from '@angular/common';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type { ChargeType, PricingScheme, ResolvedPrice } from '../../../../core/catalog/models/pricing.model';
import { PricingService } from '../../../../core/catalog/services/pricing.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

type PricingKind = 'base' | 'season';

/**
 * Define and version a product tariff (Operator/Admin). Manual override is rendered only when
 * the parent passes `allowOverride` (Admin).
 */
@Component({
  selector: 'app-pricing-editor',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, FormField, AlertComponent, SpinnerComponent],
  template: `
    <section class="card">
      <h2>Precios</h2>

      @if (loading()) {
        <app-spinner label="Cargando tarifas…" />
      } @else {
        @if (currentSchemes().length === 0) {
          <p class="notice">Este producto aún no tiene un esquema de precio vigente.</p>
        } @else {
          <table>
            <thead>
              <tr>
                <th>Tipo</th>
                <th>Cobro</th>
                <th>Moneda</th>
                <th>Monto</th>
                <th>Temporada</th>
                <th>Vigente desde</th>
              </tr>
            </thead>
            <tbody>
              @for (scheme of currentSchemes(); track scheme.id) {
                <tr>
                  <td>{{ scheme.season_start ? 'Temporada' : 'Base' }}</td>
                  <td>{{ chargeLabel(scheme.charge_type) }}</td>
                  <td>{{ scheme.currency }}</td>
                  <td>{{ scheme.base_amount }}</td>
                  <td>
                    @if (scheme.season_start && scheme.season_end) {
                      {{ scheme.season_start }} – {{ scheme.season_end }}
                    } @else {
                      —
                    }
                  </td>
                  <td>{{ scheme.valid_from | date: 'short' }}</td>
                </tr>
              }
            </tbody>
          </table>
        }

        @if (!readOnly()) {
        <form class="editor" (submit)="onSave($event)" novalidate>
          <h3>Definir o versionar tarifa</h3>
          <p class="notice">
            Un cambio de monto cierra la versión actual y crea una nueva. Los históricos no se
            modifican.
          </p>

          <label for="kind">Esquema</label>
          <select id="kind" [formField]="priceForm.kind">
            <option value="base">Precio base</option>
            <option value="season">Precio de temporada</option>
          </select>

          <label for="charge-type">Tipo de cobro</label>
          <select id="charge-type" [formField]="priceForm.chargeType">
            <option value="per_person">Por persona</option>
            <option value="per_night">Por noche</option>
            <option value="per_group">Por grupo</option>
          </select>

          <label for="currency">Moneda (ISO 4217)</label>
          <input id="currency" type="text" [formField]="priceForm.currency" />

          <label for="amount">Monto</label>
          <input id="amount" type="number" step="0.01" [formField]="priceForm.baseAmount" />

          @if (priceForm.kind().value() === 'season') {
            <label for="season-start">Inicio de temporada</label>
            <input id="season-start" type="date" [formField]="priceForm.seasonStart" />

            <label for="season-end">Fin de temporada</label>
            <input id="season-end" type="date" [formField]="priceForm.seasonEnd" />
          }

          <button type="submit" [disabled]="priceForm().submitting()">
            {{ priceForm().submitting() ? 'Guardando…' : 'Guardar tarifa' }}
          </button>
        </form>
        }

        <form class="editor" (submit)="onResolve($event)" novalidate>
          <h3>Consultar tarifa vigente</h3>
          <label for="on-date">Fecha</label>
          <input id="on-date" type="date" [formField]="resolveForm.onDate" />
          <button type="submit" [disabled]="resolveForm().submitting()">Consultar</button>
          @if (resolved(); as price) {
            <p class="notice">
              {{ price.amount }} {{ price.currency }}
              ({{ price.source === 'season' ? 'temporada' : 'base' }})
            </p>
          }
        </form>

        @if (allowOverride() && !readOnly()) {
          <form class="editor" (submit)="onOverride($event)" novalidate>
            <h3>Sobreescritura manual</h3>
            <p class="notice">Solo administradores. Queda registrada en auditoría.</p>

            <label for="override-amount">Nuevo monto</label>
            <input
              id="override-amount"
              type="number"
              step="0.01"
              [formField]="overrideForm.newAmount"
            />

            <label for="override-reason">Motivo</label>
            <textarea id="override-reason" rows="2" [formField]="overrideForm.reason"></textarea>

            <button type="submit" [disabled]="overrideForm().submitting()">
              {{ overrideForm().submitting() ? 'Aplicando…' : 'Aplicar sobreescritura' }}
            </button>
          </form>
        }

        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }
        @if (notice(); as message) {
          <app-alert kind="success">{{ message }}</app-alert>
        }
      }
    </section>
  `,
  styles: `
    .card {
      display: grid;
      gap: 0.5rem;
      width: min(40rem, 100%);
    }

    h2,
    h3 {
      margin: 0;
    }

    h3 {
      margin-top: 0.5rem;
    }

    .notice {
      margin: 0;
    }

    .editor {
      display: grid;
      gap: 0.5rem;
    }

    label {
      font-weight: 600;
    }

    button {
      margin-top: 0.25rem;
      padding: 0.6rem 1rem;
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    th,
    td {
      text-align: left;
      padding: 0.35rem 0.4rem;
      border-bottom: 1px solid #ddd;
    }
  `,
})
export class PricingEditorComponent {
  private readonly pricingApi = inject(PricingService);

  /** Product whose tariffs are being edited. */
  readonly productId = input.required<string>();
  /** When true, the admin-only manual override form is shown. */
  readonly allowOverride = input(false);
  /** Hides tariff mutations. Agents can still see the current schemes. */
  readonly readOnly = input(false);
  readonly tariffSaved = output<void>();

  protected readonly currentSchemes = signal<PricingScheme[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly resolved = signal<ResolvedPrice | null>(null);

  protected readonly priceDraft = signal({
    kind: 'base' as PricingKind,
    chargeType: 'per_person' as ChargeType,
    currency: 'COP',
    baseAmount: 0,
    seasonStart: '',
    seasonEnd: '',
  });

  protected readonly resolveDraft = signal({
    onDate: todayIsoDate(),
  });

  protected readonly overrideDraft = signal({
    newAmount: 0,
    reason: '',
  });

  protected readonly priceForm = form(this.priceDraft, (fields) => {
    required(fields.kind);
    required(fields.chargeType);
    required(fields.currency);
    required(fields.baseAmount);
  });

  protected readonly resolveForm = form(this.resolveDraft, (fields) => {
    required(fields.onDate);
  });

  protected readonly overrideForm = form(this.overrideDraft, (fields) => {
    required(fields.newAmount);
    required(fields.reason);
  });

  constructor() {
    effect(() => {
      const productId = this.productId();
      untracked(() => {
        void this.refresh(productId);
      });
    });
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

  protected async onSave(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);
    this.notice.set(null);

    await submit(this.priceForm, async (fields) => {
      try {
        const kind = fields.kind().value();
        const seasonStart = kind === 'season' ? fields.seasonStart().value() : null;
        const seasonEnd = kind === 'season' ? fields.seasonEnd().value() : null;
        if (kind === 'season' && (!seasonStart || !seasonEnd)) {
          this.error.set(toAppError(new Error('INVALID_SEASON_RANGE')));
          return undefined;
        }

        await this.pricingApi.upsert({
          productId: this.productId(),
          currency: fields.currency().value(),
          baseAmount: fields.baseAmount().value(),
          chargeType: fields.chargeType().value(),
          seasonStart,
          seasonEnd,
        });
        await this.refresh(this.productId());
        this.notice.set('La tarifa se guardó. Las versiones anteriores quedan históricas.');
        this.tariffSaved.emit();
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onResolve(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);
    this.resolved.set(null);

    await submit(this.resolveForm, async (fields) => {
      try {
        const price = await this.pricingApi.resolvePrice(
          this.productId(),
          fields.onDate().value(),
          this.priceDraft().chargeType,
        );
        this.resolved.set(price);
        if (!price) {
          this.notice.set('No hay una tarifa vigente para esa fecha y tipo de cobro.');
        }
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onOverride(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);
    this.notice.set(null);

    await submit(this.overrideForm, async (fields) => {
      try {
        const result = await this.pricingApi.applyOverride({
          productId: this.productId(),
          newAmount: fields.newAmount().value(),
          reason: fields.reason().value(),
          chargeType: this.priceDraft().chargeType,
        });
        await this.refresh(this.productId());
        this.notice.set(
          `Sobreescritura aplicada: ${result.previous_amount} → ${result.new_amount}.`,
        );
        this.overrideDraft.set({ newAmount: 0, reason: '' });
        this.tariffSaved.emit();
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }

  private async refresh(productId: string): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const current = await this.pricingApi.listCurrentForProduct(productId);
      this.currentSchemes.set(current);
      const preferred =
        current.find((row) => row.season_start == null) ?? current[0] ?? null;
      if (preferred) {
        this.priceDraft.set({
          kind: preferred.season_start ? 'season' : 'base',
          chargeType: preferred.charge_type,
          currency: preferred.currency,
          baseAmount: preferred.base_amount,
          seasonStart: preferred.season_start ?? '',
          seasonEnd: preferred.season_end ?? '',
        });
        this.overrideDraft.set({
          newAmount: preferred.base_amount,
          reason: '',
        });
      }
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}

function todayIsoDate(): string {
  return new Date().toISOString().slice(0, 10);
}
