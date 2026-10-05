import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, effect, inject, input, signal } from '@angular/core';
import { form, FormField } from '@angular/forms/signals';
import { RouterLink } from '@angular/router';
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import { AuthService } from '../../../../core/auth/services/auth.service';
import {
  DOCUMENT_TYPE_LABELS,
  customerDisplayName,
  type Customer,
  type DocumentType,
} from '../../../../core/customers/models/customer.model';
import {
  REQUEST_CHANNEL_LABELS,
  REQUEST_STATUS_LABELS,
  type RequestListRow,
} from '../../../../core/customers/models/request.model';
import { CustomerService } from '../../../../core/customers/services/customer.service';
import { RequestService } from '../../../../core/customers/services/request.service';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../../shared/components/unsaved-changes.guard';
import { NotesSectionComponent } from '../../shared/notes-section.component';

interface CustomerDraft {
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  countryCode: string;
  documentType: string;
  documentNumber: string;
}

const DOCUMENT_TYPES = Object.keys(DOCUMENT_TYPE_LABELS) as DocumentType[];

@Component({
  selector: 'app-customer-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    DatePipe,
    RouterLink,
    FormField,
    AlertComponent,
    SpinnerComponent,
    NotesSectionComponent,
  ],
  template: `
    <div class="stack">
      <a routerLink="/sales/customers">Volver a clientes</a>

      @if (loading()) {
        <app-spinner label="Cargando cliente…" />
      } @else if (loadError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (customer(); as current) {
        <h1>{{ display() }}</h1>

        @if (current.is_anonymized) {
          <app-alert kind="info">Este cliente fue anonimizado.</app-alert>
        }
        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }

        <form (submit)="onSave($event)" novalidate>
          <section
            class="section"
            [class.incomplete]="contactInvalid"
            [class.is-disabled]="locked()"
          >
            <h2>Datos de contacto</h2>
            @if (locked()) {
              <p>Nombre: {{ draft().firstName }}</p>
              <p>Apellido: {{ draft().lastName || '—' }}</p>
              <p>Correo: {{ draft().email || '—' }}</p>
              <p>Teléfono: {{ draft().phone || '—' }}</p>
              <p>País: {{ draft().countryCode || '—' }}</p>
            } @else {
              <label class="req" for="first-name">Nombre</label>
              <input id="first-name" type="text" [formField]="customerForm.firstName" />
              <label for="last-name">Apellido</label>
              <input id="last-name" type="text" [formField]="customerForm.lastName" />
              <label for="email">Correo</label>
              <input id="email" type="email" [formField]="customerForm.email" />
              <label for="phone">Teléfono</label>
              <input id="phone" type="tel" [formField]="customerForm.phone" />
              <p>Ingresa correo o teléfono.</p>
              @if (contactInvalid) {
                <p class="field-error">Ingresa correo o teléfono.</p>
              }
              <label for="country">País</label>
              <input id="country" type="text" [formField]="customerForm.countryCode" />
            }
          </section>

          <section class="section" [class.is-disabled]="locked()">
            <h2>Documento</h2>
            @if (locked()) {
              <p>Tipo: {{ draft().documentType ? documentLabel(draft().documentType) : '—' }}</p>
              <p>Número: {{ draft().documentNumber || '—' }}</p>
            } @else {
              <label for="document-type">Tipo</label>
              <select id="document-type" [formField]="customerForm.documentType">
                <option value="">Sin documento</option>
                @for (type of documentTypes; track type) {
                  <option [value]="type">{{ documentLabel(type) }}</option>
                }
              </select>
              <label for="document-number">Número</label>
              <input id="document-number" type="text" [formField]="customerForm.documentNumber" />
            }
          </section>

          @if (!locked()) {
            <div class="actions">
              <button class="primary" type="submit" [disabled]="saving()">
                {{ saving() ? 'Guardando…' : 'Guardar' }}
              </button>
            </div>
          }
        </form>

        <section class="section">
          <h2>Historial de solicitudes</h2>
          @if (history().length === 0) {
            <p>Este cliente todavía no tiene solicitudes.</p>
          } @else {
            <table class="data">
              <thead>
                <tr>
                  <th>Referencia</th>
                  <th>Canal</th>
                  <th>Estado</th>
                  <th>Fecha</th>
                </tr>
              </thead>
              <tbody>
                @for (row of history(); track row.id) {
                  <tr>
                    <td>
                      <a [routerLink]="['/sales/requests', row.id]">{{ row.reference }}</a>
                    </td>
                    <td>{{ channelLabel(row.channel) }}</td>
                    <td>{{ statusLabel(row.status) }}</td>
                    <td>{{ row.created_at | date: 'short' }}</td>
                  </tr>
                }
              </tbody>
            </table>
          }
          @if (!current.is_anonymized) {
            <a
              class="button-link"
              [routerLink]="['/sales/requests/new']"
              [queryParams]="{ customerId: current.id }"
            >
              Nueva solicitud para este cliente
            </a>
          }
        </section>

        <app-notes-section [target]="{ customerId: current.id }" [readOnly]="locked()" />

        @if (canAnonymize()) {
          <section class="section">
            <h2>Privacidad</h2>
            <p>
              Anonimizar borra el nombre, el contacto y los textos que escribió el cliente. El
              historial comercial se conserva. Esta acción no se puede deshacer.
            </p>
            <label class="req" for="anonymize-reason">Motivo</label>
            <textarea
              id="anonymize-reason"
              rows="2"
              [value]="reason()"
              (input)="onReason($event)"
            ></textarea>
            <button type="button" (click)="anonymize()" [disabled]="saving()">
              Anonimizar cliente
            </button>
          </section>
        }
      } @else {
        <p>No encontramos este cliente.</p>
      }
    </div>
  `,
  styles: `
    .stack,
    form {
      display: grid;
      gap: 0.85rem;
    }
  `,
})
export class CustomerDetailComponent implements UnsavedChangesHost {
  private readonly customers = inject(CustomerService);
  private readonly requests = inject(RequestService);
  private readonly auth = inject(AuthService);

  readonly id = input.required<string>();

  protected readonly documentTypes = DOCUMENT_TYPES;
  protected readonly documentLabel = (type: string) =>
    DOCUMENT_TYPE_LABELS[type as DocumentType] ?? type;
  protected readonly channelLabel = (channel: RequestListRow['channel']) =>
    REQUEST_CHANNEL_LABELS[channel];
  protected readonly statusLabel = (status: RequestListRow['status']) =>
    REQUEST_STATUS_LABELS[status];
  protected readonly loading = signal(true);
  protected readonly saving = signal(false);
  protected readonly loadError = signal<AppError | null>(null);
  protected readonly error = signal<AppError | null>(null);
  protected readonly customer = signal<Customer | null>(null);
  protected readonly history = signal<RequestListRow[]>([]);
  protected readonly reason = signal('');
  protected readonly showContactError = signal(false);
  protected readonly draft = signal<CustomerDraft>(emptyDraft());
  protected readonly customerForm = form(this.draft);
  private baseline = '';
  private allowLeave = false;

  constructor() {
    effect(() => {
      const id = this.id();
      void this.load(id);
    });
  }

  protected get contactInvalid(): boolean {
    return this.showContactError() && !this.draft().email.trim() && !this.draft().phone.trim();
  }

  protected locked(): boolean {
    return Boolean(this.customer()?.is_anonymized);
  }

  protected canAnonymize(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'admin') && !this.locked();
  }

  protected display(): string {
    const current = this.customer();
    return current ? customerDisplayName(current) : '';
  }

  hasUnsavedChanges(): boolean {
    if (this.allowLeave || this.locked()) {
      return false;
    }
    return JSON.stringify(this.draft()) !== this.baseline;
  }

  protected onReason(event: Event): void {
    this.reason.set((event.target as HTMLTextAreaElement).value);
  }

  protected async onSave(event: Event): Promise<void> {
    event.preventDefault();
    if (this.locked()) {
      return;
    }
    if (!this.draft().email.trim() && !this.draft().phone.trim()) {
      this.showContactError.set(true);
      return;
    }
    this.showContactError.set(false);
    this.saving.set(true);
    this.error.set(null);
    try {
      const updated = await this.customers.update(this.id(), {
        first_name: this.draft().firstName.trim(),
        last_name: emptyToNull(this.draft().lastName),
        email: emptyToNull(this.draft().email),
        phone: emptyToNull(this.draft().phone),
        country_code: emptyToNull(this.draft().countryCode.trim().toUpperCase()),
        document_type: (this.draft().documentType || null) as DocumentType | null,
        document_number: emptyToNull(this.draft().documentNumber),
      });
      this.apply(updated);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  protected async anonymize(): Promise<void> {
    const reason = this.reason().trim();
    if (!reason) {
      this.error.set(toAppError({ message: 'VALIDATION_ERROR' }));
      return;
    }
    if (!window.confirm('Esta acción no se puede deshacer. ¿Anonimizar este cliente?')) {
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    try {
      await this.customers.anonymize(this.id(), reason);
      this.allowLeave = true;
      await this.load(this.id());
      this.allowLeave = false;
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  private async load(id: string): Promise<void> {
    this.loading.set(true);
    this.loadError.set(null);
    try {
      const customer = await this.customers.getById(id);
      this.customer.set(customer);
      if (customer) {
        this.apply(customer);
        const page = await this.requests.listPage({ customerId: id, page: 1 });
        this.history.set(page.rows);
      }
    } catch (failure) {
      this.loadError.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }

  private apply(customer: Customer): void {
    this.customer.set(customer);
    this.draft.set({
      firstName: customer.first_name,
      lastName: customer.last_name ?? '',
      email: customer.email ?? '',
      phone: customer.phone_e164 ?? '',
      countryCode: (customer.country_code ?? '').trim(),
      documentType: customer.document_type ?? '',
      documentNumber: customer.document_number ?? '',
    });
    this.baseline = JSON.stringify(this.draft());
  }
}

function emptyDraft(): CustomerDraft {
  return {
    firstName: '',
    lastName: '',
    email: '',
    phone: '',
    countryCode: '',
    documentType: '',
    documentNumber: '',
  };
}

function emptyToNull(value: string): string | null {
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}
