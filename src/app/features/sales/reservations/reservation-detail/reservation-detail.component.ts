import { DatePipe } from '@angular/common';
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
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import { AuthService } from '../../../../core/auth/services/auth.service';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import {
  ID_DOCUMENT_TYPE_LABELS,
  PAYMENT_METHOD_LABELS,
  RESERVATION_OPS_STATUS_LABELS,
  RESERVATION_STATUS_LABELS,
  isReservationTerminal,
  type PaymentMethod,
  type ReservationDetail,
  type ReservationItem,
  type ReservationPassengerInput,
  type ReservationStatus,
} from '../../../../core/reservations/models/reservation.model';
import { ReservationService } from '../../../../core/reservations/services/reservation.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

@Component({
  selector: 'app-reservation-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <div class="stack">
      <a class="button-link" routerLink="/sales/reservations">Volver a reservas</a>

      @if (loading()) {
        <app-spinner label="Cargando reserva…" />
      } @else if (detail(); as current) {
        <header>
          <h1>{{ current.reference }}</h1>
          <p>
            {{ statusLabel(current.status) }} · v{{ current.version_number }} ·
            {{ current.travel_start_date | date: 'mediumDate' }}
            @if (current.travel_end_date) {
              – {{ current.travel_end_date | date: 'mediumDate' }}
            }
          </p>
        </header>

        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }
        @if (notice(); as text) {
          <app-alert kind="success">{{ text }}</app-alert>
        }

        <dl>
          <div>
            <dt>Total</dt>
            <dd>{{ current.total }} {{ current.currency }}</dd>
          </div>
          <div>
            <dt>Pagado</dt>
            <dd>{{ current.paid_total }} {{ current.currency }}</dd>
          </div>
          <div>
            <dt>Saldo</dt>
            <dd>{{ current.balance }} {{ current.currency }}</dd>
          </div>
        </dl>

        @if (canOperate()) {
          <div class="actions">
            @if (current.status === 'confirmed') {
              <button type="button" (click)="onTransition('in_progress')" [disabled]="saving()">
                Pasar a en ejecución
              </button>
            }
            @if (current.status === 'in_progress') {
              <button type="button" (click)="onTransition('completed')" [disabled]="saving()">
                Completar
              </button>
            }
          </div>
        }

        @if (!isTerminal()) {
          <section>
            <h2>Cancelar</h2>
            <label>
              Motivo
              <textarea [value]="cancelReason()" (input)="cancelReason.set($any($event.target).value)"></textarea>
            </label>
            @if (current.status === 'in_progress') {
              <label>
                Informe de contingencia
                <textarea
                  [value]="contingency()"
                  (input)="contingency.set($any($event.target).value)"
                ></textarea>
              </label>
            }
            <button type="button" (click)="onCancel()" [disabled]="saving()">Cancelar reserva</button>
          </section>
        }

        <section>
          <h2>Pasajeros</h2>
          <ul>
            @for (pax of current.passengers; track pax.id) {
              <li>
                {{ pax.first_name }} {{ pax.last_name }} ·
                {{ documentLabel(pax.document_type) }} {{ pax.document_number }}
              </li>
            }
          </ul>
        </section>

        <section>
          <h2>Servicios</h2>
          @for (item of current.items; track item.id) {
            <article>
              <h3>{{ item.item_label }}</h3>
              <p>
                {{ item.start_date | date: 'mediumDate' }} ·
                {{ opsLabel(item.ops_status) }}
              </p>
              @if (canOperate()) {
                <div class="actions">
                  <button type="button" (click)="onCopyOrder(item)" [disabled]="saving()">
                    Copiar orden
                  </button>
                  <button type="button" (click)="onMarkSent(item.id)" [disabled]="saving()">
                    Marcar enviada
                  </button>
                  <label>
                    Nuevo proveedor
                    <select (change)="reassignTarget.set($any($event.target).value)">
                      <option value="">—</option>
                      @for (provider of providers(); track provider.id) {
                        <option [value]="provider.id">{{ provider.name }}</option>
                      }
                    </select>
                  </label>
                  <label>
                    Motivo de reasignación
                    <input [value]="reassignReason()" (input)="reassignReason.set($any($event.target).value)" />
                  </label>
                  <button type="button" (click)="onReassign(item.id)" [disabled]="saving()">
                    Reasignar
                  </button>
                </div>
              }
            </article>
          }
        </section>

        @if (!isTerminal()) {
          <section>
            <h2>Nueva versión (fechas)</h2>
            <p>Se conserva el total y los pagos de la familia. No edite la versión actual.</p>
            @for (item of versionItems(); track item.id; let i = $index) {
              <label>
                {{ item.item_label }} · inicio
                <input
                  type="date"
                  [value]="item.start_date"
                  (input)="patchItemDate(i, 'start_date', $any($event.target).value)"
                />
              </label>
            }
            <button type="button" (click)="onNewVersion()" [disabled]="saving()">Crear versión</button>
          </section>
        }

        <section>
          <h2>Abono extra</h2>
          <label>
            Monto
            <input type="number" min="0.01" step="0.01" [value]="payAmount()" (input)="payAmount.set($any($event.target).value)" />
          </label>
          <label>
            Fecha
            <input type="date" [value]="payOn()" (input)="payOn.set($any($event.target).value)" />
          </label>
          <label>
            Método
            <select [value]="payMethod()" (change)="payMethod.set($any($event.target).value)">
              @for (option of methods; track option) {
                <option [value]="option">{{ methodLabel(option) }}</option>
              }
            </select>
          </label>
          <label>
            Referencia
            <input [value]="payRef()" (input)="payRef.set($any($event.target).value)" />
          </label>
          <label>
            Comprobante
            <input type="file" (change)="onReceipt($event)" />
          </label>
          <button type="button" (click)="onRecordPayment()" [disabled]="saving()">Registrar abono</button>
        </section>

        <section>
          <h2>Voucher</h2>
          @if (voucherToken(); as token) {
            <p>Enlace: <a [href]="publicLink(token)" target="_blank" rel="noopener">{{ publicLink(token) }}</a></p>
          } @else {
            <app-alert kind="info">
              El voucher se mostró al confirmar. Un administrador puede reemitirlo.
            </app-alert>
            @if (isAdmin()) {
              <button type="button" (click)="onRotate()" [disabled]="saving()">Reemitir voucher</button>
            }
          }
          <div class="actions">
            <button type="button" (click)="onCopyWhatsapp()" [disabled]="saving()">Copiar para WhatsApp</button>
            <button type="button" (click)="onPrint()">Imprimir</button>
            @if (isAdmin()) {
              <button type="button" (click)="onVoid()" [disabled]="saving()">Anular voucher</button>
            }
          </div>
        </section>
      } @else {
        <app-alert kind="warning">No se encontró la reserva.</app-alert>
      }
    </div>
  `,
  styles: `
    .stack {
      display: grid;
      gap: 1rem;
      max-width: 48rem;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
    }
    dl {
      display: grid;
      gap: 0.35rem;
    }
    dl div {
      display: flex;
      justify-content: space-between;
    }
  `,
})
export class ReservationDetailComponent {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly reservations = inject(ReservationService);
  private readonly auth = inject(AuthService);

  private readonly params = toSignal(this.route.paramMap, { requireSync: true });
  protected readonly detail = signal<ReservationDetail | null>(null);
  protected readonly loading = signal(true);
  protected readonly saving = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly providers = signal<{ id: string; name: string }[]>([]);
  protected readonly cancelReason = signal('');
  protected readonly contingency = signal('');
  protected readonly reassignTarget = signal('');
  protected readonly reassignReason = signal('');
  protected readonly versionItems = signal<ReservationItem[]>([]);
  protected readonly payAmount = signal('');
  protected readonly payOn = signal(new Date().toISOString().slice(0, 10));
  protected readonly payMethod = signal<PaymentMethod>('bank_transfer');
  protected readonly payRef = signal('');
  protected readonly receiptFile = signal<File | null>(null);
  protected readonly voucherToken = signal<string | null>(null);
  protected readonly methods: PaymentMethod[] = ['bank_transfer', 'cash', 'card_manual', 'other'];
  protected readonly statusLabel = (s: ReservationStatus) => RESERVATION_STATUS_LABELS[s];
  protected readonly opsLabel = (s: ReservationItem['ops_status']) => RESERVATION_OPS_STATUS_LABELS[s];
  protected readonly methodLabel = (m: PaymentMethod) => PAYMENT_METHOD_LABELS[m];
  protected readonly documentLabel = (d: keyof typeof ID_DOCUMENT_TYPE_LABELS) =>
    ID_DOCUMENT_TYPE_LABELS[d];
  protected readonly canOperate = computed(() =>
    hasRoleAtLeast(this.auth.profile()?.role ?? null, 'operator'),
  );
  protected readonly isAdmin = computed(() => this.auth.profile()?.role === 'admin');
  protected readonly isTerminal = computed(() => {
    const status = this.detail()?.status;
    return status != null && isReservationTerminal(status);
  });

  constructor() {
    effect(() => {
      const id = this.params().get('id');
      untracked(() => {
        void this.load(id);
      });
    });
  }

  protected publicLink(token: string): string {
    return `${window.location.origin}/r/${encodeURIComponent(token)}`;
  }

  protected patchItemDate(index: number, field: 'start_date' | 'end_date', value: string): void {
    this.versionItems.update((rows) =>
      rows.map((row, i) => (i === index ? { ...row, [field]: value } : row)),
    );
  }

  protected onReceipt(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.receiptFile.set(input.files?.[0] ?? null);
  }

  protected async onTransition(to: ReservationStatus): Promise<void> {
    await this.run(async () => {
      const id = this.detail()?.id;
      if (!id) {
        return;
      }
      await this.reservations.transition(id, to);
      this.notice.set('Estado actualizado.');
      await this.reload();
    });
  }

  protected async onCancel(): Promise<void> {
    await this.run(async () => {
      const current = this.detail();
      if (!current) {
        return;
      }
      await this.reservations.cancel(
        current.id,
        this.cancelReason().trim(),
        current.status === 'in_progress' ? this.contingency().trim() : null,
      );
      this.notice.set('Reserva cancelada.');
      await this.reload();
    });
  }

  protected async onCopyOrder(item: ReservationItem): Promise<void> {
    await this.run(async () => {
      const payload = await this.reservations.providerOrderText(item.id);
      await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
      this.notice.set('Orden copiada.');
    });
  }

  protected async onMarkSent(itemId: string): Promise<void> {
    await this.run(async () => {
      await this.reservations.markOrderSent(itemId, 'print');
      this.notice.set('Orden marcada como enviada.');
      await this.reload();
    });
  }

  protected async onReassign(itemId: string): Promise<void> {
    await this.run(async () => {
      const providerId = this.reassignTarget();
      if (!providerId) {
        return;
      }
      await this.reservations.reassignProvider(itemId, providerId, this.reassignReason().trim());
      this.notice.set('Proveedor reasignado.');
      await this.reload();
    });
  }

  protected async onNewVersion(): Promise<void> {
    await this.run(async () => {
      const current = this.detail();
      if (!current) {
        return;
      }
      const passengers: ReservationPassengerInput[] = current.passengers.map((pax) => ({
        first_name: pax.first_name,
        last_name: pax.last_name,
        document_type: pax.document_type,
        document_number: pax.document_number,
        date_of_birth: pax.date_of_birth,
        special_requirements: pax.special_requirements,
      }));
      const created = await this.reservations.createVersion(
        current.id,
        this.versionItems(),
        passengers,
      );
      this.notice.set('Versión nueva creada.');
      await this.router.navigate(['/sales/reservations', created.version_id]);
    });
  }

  protected async onRecordPayment(): Promise<void> {
    await this.run(async () => {
      const current = this.detail();
      const orgId = this.auth.profile()?.organization_id;
      if (!current || !orgId) {
        return;
      }
      let receiptPath: string | null = null;
      const file = this.receiptFile();
      if (file) {
        receiptPath = await this.reservations.uploadReceipt(orgId, current.family_id, file);
      }
      await this.reservations.recordPayment(current.family_id, {
        amount: Number(this.payAmount()),
        currency: current.currency,
        paid_on: this.payOn(),
        method: this.payMethod(),
        transfer_reference: this.payRef().trim(),
        receipt_path: receiptPath,
      });
      this.notice.set('Abono registrado.');
      this.payAmount.set('');
      this.payRef.set('');
      this.receiptFile.set(null);
      await this.reload();
    });
  }

  protected async onCopyWhatsapp(): Promise<void> {
    await this.run(async () => {
      const id = this.detail()?.id;
      if (!id) {
        return;
      }
      const text = await this.reservations.whatsappText(id);
      await navigator.clipboard.writeText(text);
      this.notice.set('Texto copiado para WhatsApp.');
    });
  }

  protected onPrint(): void {
    window.print();
  }

  protected async onVoid(): Promise<void> {
    await this.run(async () => {
      const familyId = this.detail()?.family_id;
      if (!familyId) {
        return;
      }
      await this.reservations.voidVoucher(familyId);
      this.voucherToken.set(null);
      this.notice.set('Voucher anulado.');
    });
  }

  protected async onRotate(): Promise<void> {
    await this.run(async () => {
      const familyId = this.detail()?.family_id;
      if (!familyId) {
        return;
      }
      const token = await this.reservations.rotateVoucher(familyId);
      this.voucherToken.set(token);
      this.notice.set('Voucher reemitido. Cópielo ahora.');
    });
  }

  private async load(id: string | null): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    if (!id) {
      this.detail.set(null);
      this.loading.set(false);
      return;
    }
    try {
      const [detail, providers] = await Promise.all([
        this.reservations.getById(id),
        this.reservations.listProviders(),
      ]);
      this.detail.set(detail);
      this.providers.set(providers);
      this.versionItems.set(detail?.items ?? []);
      this.voucherToken.set(detail ? this.reservations.readStoredToken(detail.family_id) : null);
    } catch (failure) {
      this.error.set(toAppError(failure));
      this.detail.set(null);
    } finally {
      this.loading.set(false);
    }
  }

  private async reload(): Promise<void> {
    await this.load(this.params().get('id'));
  }

  private async run(action: () => Promise<void>): Promise<void> {
    this.saving.set(true);
    this.error.set(null);
    try {
      await action();
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }
}
