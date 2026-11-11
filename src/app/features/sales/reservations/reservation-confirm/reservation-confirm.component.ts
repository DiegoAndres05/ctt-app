import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type { QuotationDetail } from '../../../../core/quotations/models/quotation.model';
import { QuotationService } from '../../../../core/quotations/services/quotation.service';
import {
  ID_DOCUMENT_TYPE_LABELS,
  PAYMENT_METHOD_LABELS,
  publicVoucherUrl,
  type IdDocumentType,
  type PaymentMethod,
  type ReservationPassengerInput,
} from '../../../../core/reservations/models/reservation.model';
import { ReservationService } from '../../../../core/reservations/services/reservation.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../../shared/components/unsaved-changes.guard';

interface PassengerDraft {
  first_name: string;
  last_name: string;
  document_type: IdDocumentType;
  document_number: string;
}

@Component({
  selector: 'app-reservation-confirm',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <div class="stack">
      <a class="button-link" routerLink="/sales/reservations">Volver a reservas</a>
      <h1>Confirmar reserva</h1>

      @if (loading()) {
        <app-spinner label="Cargando cotización…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (quotation(); as quote) {
        @if (success(); as result) {
          <app-alert kind="success">
            Reserva {{ result.reference }} confirmada. El voucher se muestra una sola vez.
          </app-alert>
          <p>Enlace público del voucher (cópielo ahora):</p>
          <pre><a [href]="publicLink(result.voucher_token)" target="_blank" rel="noopener">{{
            publicLink(result.voucher_token)
          }}</a></pre>
          <a class="primary button-link" [routerLink]="['/sales/reservations', result.version_id]">
            Ir al detalle
          </a>
        } @else {
          <p>
            Cotización {{ quote.reference ?? quote.id }} · {{ quote.total }} {{ quote.currency }} ·
            {{ expectedPax() }} pasajeros
          </p>
          <p>El depósito no se cobra en línea. Registre el abono ya recibido.</p>

          <form (submit)="onSubmit($event)" class="stack">
            <label>
              Monto del depósito
              <input
                type="number"
                min="0.01"
                step="0.01"
                [value]="amount()"
                (input)="amount.set($any($event.target).value)"
              />
            </label>
            <label>
              Fecha de pago
              <input
                type="date"
                [value]="paidOn()"
                (input)="paidOn.set($any($event.target).value)"
              />
            </label>
            <label>
              Método
              <select [value]="method()" (change)="method.set($any($event.target).value)">
                @for (option of methods; track option) {
                  <option [value]="option">{{ methodLabel(option) }}</option>
                }
              </select>
            </label>
            <label>
              Referencia de transferencia
              <input [value]="transferRef()" (input)="transferRef.set($any($event.target).value)" />
            </label>
            <label>
              Teléfonos de asistencia
              <input [value]="phones()" (input)="phones.set($any($event.target).value)" />
            </label>

            <h2>Pasajeros</h2>
            @for (pax of passengers(); track $index; let i = $index) {
              <fieldset>
                <legend>Pasajero {{ i + 1 }}</legend>
                <label>
                  Nombre
                  <input
                    [value]="pax.first_name"
                    (input)="patchPax(i, 'first_name', $any($event.target).value)"
                  />
                </label>
                <label>
                  Apellido
                  <input
                    [value]="pax.last_name"
                    (input)="patchPax(i, 'last_name', $any($event.target).value)"
                  />
                </label>
                <label>
                  Documento
                  <select
                    [value]="pax.document_type"
                    (change)="patchPax(i, 'document_type', $any($event.target).value)"
                  >
                    @for (doc of documents; track doc) {
                      <option [value]="doc">{{ documentLabel(doc) }}</option>
                    }
                  </select>
                </label>
                <label>
                  Número
                  <input
                    [value]="pax.document_number"
                    (input)="patchPax(i, 'document_number', $any($event.target).value)"
                  />
                </label>
              </fieldset>
            }

            <button class="primary" type="submit" [disabled]="saving()">Confirmar reserva</button>
          </form>
        }
      }
    </div>
  `,
  styles: `
    .stack {
      display: grid;
      gap: 0.75rem;
      max-width: 40rem;
    }
    fieldset {
      display: grid;
      gap: 0.4rem;
    }
  `,
})
export class ReservationConfirmComponent implements UnsavedChangesHost {
  private readonly route = inject(ActivatedRoute);
  private readonly quotations = inject(QuotationService);
  private readonly reservations = inject(ReservationService);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly quotation = signal<QuotationDetail | null>(null);
  protected readonly loading = signal(true);
  protected readonly saving = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly success = signal<{
    reference: string;
    voucher_token: string;
    version_id: string;
  } | null>(null);
  protected readonly amount = signal('0');
  protected readonly paidOn = signal(new Date().toISOString().slice(0, 10));
  protected readonly method = signal<PaymentMethod>('bank_transfer');
  protected readonly transferRef = signal('');
  protected readonly phones = signal('');
  protected readonly passengers = signal<PassengerDraft[]>([]);
  protected readonly methods: PaymentMethod[] = ['bank_transfer', 'cash', 'card_manual', 'other'];
  protected readonly documents: IdDocumentType[] = ['cc', 'ce', 'passport', 'ti', 'other'];
  protected readonly methodLabel = (m: PaymentMethod) => PAYMENT_METHOD_LABELS[m];
  protected readonly documentLabel = (d: IdDocumentType) => ID_DOCUMENT_TYPE_LABELS[d];
  protected readonly expectedPax = computed(() => {
    const quote = this.quotation();
    return quote ? quote.party_adults + quote.party_children : 0;
  });
  private dirty = false;

  constructor() {
    effect(() => {
      const id = this.params().get('quotationVersionId');
      untracked(() => {
        void this.load(id);
      });
    });
  }

  /** Full `/r/<token>` link shown once after confirming (D2, stabilization 2026-11-11). */
  protected publicLink(token: string): string {
    return publicVoucherUrl(window.location.origin, token);
  }

  hasUnsavedChanges(): boolean {
    return this.dirty && this.success() === null;
  }

  protected patchPax(index: number, field: keyof PassengerDraft, value: string): void {
    this.dirty = true;
    this.passengers.update((rows) =>
      rows.map((row, i) => (i === index ? { ...row, [field]: value } : row)),
    );
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    const quote = this.quotation();
    if (!quote) {
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    try {
      const passengers: ReservationPassengerInput[] = this.passengers().map((row) => ({
        first_name: row.first_name.trim(),
        last_name: row.last_name.trim(),
        document_type: row.document_type,
        document_number: row.document_number.trim(),
      }));
      const result = await this.reservations.confirm(
        quote.id,
        {
          amount: Number(this.amount()),
          currency: quote.currency,
          paid_on: this.paidOn(),
          method: this.method(),
          transfer_reference: this.transferRef().trim(),
        },
        passengers,
        this.phones().trim(),
      );
      this.dirty = false;
      this.success.set({
        reference: result.reference,
        voucher_token: result.voucher_token,
        version_id: result.version_id,
      });
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  private async load(quotationVersionId: string | null): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.success.set(null);
    if (!quotationVersionId) {
      this.error.set({
        code: 'VALIDATION_ERROR',
        message: 'Falta el identificador de la cotización.',
      });
      this.loading.set(false);
      return;
    }
    try {
      const quote = await this.quotations.getById(quotationVersionId);
      if (!quote) {
        this.error.set({
          code: 'VALIDATION_ERROR',
          message: 'No se encontró la cotización.',
        });
        this.quotation.set(null);
        return;
      }
      this.quotation.set(quote);
      const count = Math.max(1, quote.party_adults + quote.party_children);
      this.passengers.set(
        Array.from({ length: count }, () => ({
          first_name: '',
          last_name: '',
          document_type: 'cc' as IdDocumentType,
          document_number: '',
        })),
      );
      this.amount.set(String(quote.total));
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
