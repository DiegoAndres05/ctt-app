import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { form, FormField } from '@angular/forms/signals';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { customerDisplayName } from '../../../../core/customers/models/customer.model';
import type { CustomerListRow } from '../../../../core/customers/models/customer.model';
import {
  ASSISTED_CHANNELS,
  REQUEST_CHANNEL_LABELS,
  type AssistedChannel,
} from '../../../../core/customers/models/request.model';
import { CustomerService } from '../../../../core/customers/services/customer.service';
import { RequestService } from '../../../../core/customers/services/request.service';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import type { UnsavedChangesHost } from '../../../../shared/components/unsaved-changes.guard';
import {
  LIST_SEARCH_DEBOUNCE_MS,
  debounce,
} from '../../../../shared/components/data-table/list-query';
import { SupabaseService } from '../../../../core/auth/services/supabase.service';
import {
  buildAssistedRequestPayload,
  emptyIntakeDraft,
  validateIntakeDraft,
  type IntakeDraft,
  type IntakeIssue,
} from './intake-payload';

interface ProductOption {
  id: string;
  name: string;
  type: string;
}

@Component({
  selector: 'app-request-intake',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent],
  template: `
    <div class="stack">
      <h1>Nueva solicitud</h1>

      <form (submit)="onSubmit($event)" novalidate>
        <section class="section" [class.incomplete]="sectionIncomplete('channel')">
          <h2>Canal</h2>
          <label for="channel">Canal</label>
          <select id="channel" [formField]="intakeForm.channel">
            @for (channel of channels; track channel) {
              <option [value]="channel">{{ channelLabel(channel) }}</option>
            }
          </select>
        </section>

        <section class="section" [class.incomplete]="sectionIncomplete('customer')">
          <h2>Cliente</h2>
          @if (draft().customerId) {
            <p>Cliente seleccionado: {{ selectedName() }}</p>
            <button type="button" (click)="useNewCustomer()">Cliente nuevo</button>
          } @else {
            <label for="customer-q">Buscar cliente</label>
            <input
              id="customer-q"
              type="search"
              [value]="searchDraft()"
              (input)="onSearch($event)"
              placeholder="Nombre, correo o teléfono"
            />
            @if (matches().length > 0) {
              <ul>
                @for (match of matches(); track match.id) {
                  <li>
                    <button type="button" (click)="selectCustomer(match)">
                      {{ display(match) }}
                    </button>
                  </li>
                }
              </ul>
            }
            <p>O registra un cliente nuevo.</p>
            <label class="req" for="first-name">Nombre</label>
            <input id="first-name" type="text" [formField]="intakeForm.firstName" />
            @if (issue('firstName'); as message) {
              <p class="field-error">{{ message }}</p>
            }
            <label for="last-name">Apellido</label>
            <input id="last-name" type="text" [formField]="intakeForm.lastName" />
            <label for="email">Correo</label>
            <input id="email" type="email" [formField]="intakeForm.email" />
            @if (issue('email'); as message) {
              <p class="field-error">{{ message }}</p>
            }
            <p>Ingresa correo o teléfono.</p>
            <label for="phone">Teléfono</label>
            <input id="phone" type="tel" [formField]="intakeForm.phone" />
            <label for="country">País</label>
            <input id="country" type="text" [formField]="intakeForm.countryCode" />
          }
        </section>

        <section class="section" [class.incomplete]="sectionIncomplete('travel')">
          <h2>Viaje</h2>
          <label for="start">Inicio</label>
          <input id="start" type="date" [min]="today" [formField]="intakeForm.travelStart" />
          @if (issue('travelStart'); as message) {
            <p class="field-error">{{ message }}</p>
          }
          <label for="end">Fin</label>
          <input
            id="end"
            type="date"
            [min]="draft().travelStart || today"
            [formField]="intakeForm.travelEnd"
          />
          @if (issue('travelEnd'); as message) {
            <p class="field-error">{{ message }}</p>
          }
          <label class="req" for="adults">Adultos</label>
          <input id="adults" type="number" [formField]="intakeForm.adults" />
          @if (issue('adults'); as message) {
            <p class="field-error">{{ message }}</p>
          }
          <label for="children">Niños</label>
          <input id="children" type="number" [formField]="intakeForm.children" />
        </section>

        <section class="section" [class.incomplete]="sectionIncomplete('items')">
          <h2>Intereses</h2>
          @for (item of draft().items; track $index) {
            <div class="item-row">
              <label [attr.for]="'product-' + $index">Producto</label>
              <select
                [id]="'product-' + $index"
                [value]="item.productId ?? ''"
                (change)="onProduct($index, $event)"
              >
                <option value="">Texto libre</option>
                @for (product of products(); track product.id) {
                  <option [value]="product.id">{{ product.name }}</option>
                }
              </select>
              <label [attr.for]="'free-' + $index">Texto libre</label>
              <input
                [id]="'free-' + $index"
                type="text"
                [value]="item.freeText"
                (input)="onFreeText($index, $event)"
              />
              <label [attr.for]="'qty-' + $index">Cantidad</label>
              <input
                [id]="'qty-' + $index"
                type="number"
                min="1"
                max="99"
                [value]="item.quantity"
                (input)="onQuantity($index, $event)"
              />
              @if (issue('item-' + $index); as message) {
                <p class="field-error">{{ message }}</p>
              }
              @if (draft().items.length > 1) {
                <button type="button" (click)="removeItem($index)">Quitar</button>
              }
            </div>
          }
          @if (issue('items'); as message) {
            <p class="field-error">{{ message }}</p>
          }
          <button type="button" (click)="addItem()">Agregar interés</button>
        </section>

        <section class="section">
          <h2>Notas del cliente</h2>
          <label for="requirements">Requerimientos</label>
          <textarea
            id="requirements"
            rows="3"
            [formField]="intakeForm.specialRequirements"
          ></textarea>
        </section>

        <section class="section" [class.incomplete]="sectionIncomplete('privacy')">
          <h2>Privacidad</h2>
          <label class="check" for="privacy">
            <input id="privacy" type="checkbox" [formField]="intakeForm.privacyNoticeGiven" />
            Informé al cliente sobre el tratamiento de sus datos
          </label>
          @if (issue('privacyNoticeGiven'); as message) {
            <p class="field-error">{{ message }}</p>
          }
        </section>

        <div class="actions">
          <button class="primary" type="submit" [disabled]="saving()">
            {{ saving() ? 'Guardando…' : 'Guardar solicitud' }}
          </button>
          <a class="button-link" routerLink="/sales/requests">Cancelar</a>
        </div>

        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }
      </form>
    </div>
  `,
  styles: `
    .stack,
    form,
    .item-row {
      display: grid;
      gap: 0.75rem;
    }

    .check {
      display: flex;
      gap: 0.4rem;
      align-items: center;
      font-weight: 400;
    }
  `,
})
export class RequestIntakeComponent implements UnsavedChangesHost {
  private readonly requests = inject(RequestService);
  private readonly customers = inject(CustomerService);
  private readonly supabase = inject(SupabaseService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  protected readonly channels = ASSISTED_CHANNELS;
  protected readonly channelLabel = (channel: AssistedChannel) => REQUEST_CHANNEL_LABELS[channel];
  protected readonly today = todayIso();
  protected readonly draft = signal<IntakeDraft>(emptyIntakeDraft());
  protected readonly intakeForm = form(this.draft);
  protected readonly issues = signal<IntakeIssue[]>([]);
  protected readonly error = signal<AppError | null>(null);
  protected readonly saving = signal(false);
  protected readonly products = signal<ProductOption[]>([]);
  protected readonly matches = signal<CustomerListRow[]>([]);
  protected readonly searchDraft = signal('');
  protected readonly selectedName = signal('');
  private baseline = '';
  private allowLeave = false;
  private readonly idempotencyKey = crypto.randomUUID();

  private readonly commitSearch = debounce((value: string) => {
    void this.search(value);
  }, LIST_SEARCH_DEBOUNCE_MS);

  constructor() {
    const params = this.route.snapshot.queryParamMap;
    const channel = params.get('channel');
    const customerId = params.get('customerId');
    this.draft.set({
      ...emptyIntakeDraft(isAssistedChannel(channel) ? channel : 'whatsapp'),
      customerId,
    });
    this.baseline = JSON.stringify(this.draft());
    if (customerId) {
      void this.labelCustomer(customerId);
    }
    void this.loadProducts();
  }

  hasUnsavedChanges(): boolean {
    if (this.allowLeave) {
      return false;
    }
    return JSON.stringify(this.draft()) !== this.baseline;
  }

  protected issue(field: string): string | null {
    return this.issues().find((item) => item.field === field)?.message ?? null;
  }

  protected sectionIncomplete(
    section: 'channel' | 'customer' | 'travel' | 'items' | 'privacy',
  ): boolean {
    return this.issues().some((item) => fieldSection(item.field) === section);
  }

  protected display(row: CustomerListRow): string {
    return customerDisplayName(row);
  }

  protected onSearch(event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.searchDraft.set(value);
    this.commitSearch(value);
  }

  protected selectCustomer(row: CustomerListRow): void {
    this.draft.update((current) => ({ ...current, customerId: row.id }));
    this.selectedName.set(customerDisplayName(row));
    this.matches.set([]);
    this.searchDraft.set('');
  }

  protected useNewCustomer(): void {
    this.draft.update((current) => ({ ...current, customerId: null }));
    this.selectedName.set('');
  }

  protected addItem(): void {
    this.draft.update((current) => ({
      ...current,
      items: [...current.items, { productId: null, freeText: '', quantity: 1 }],
    }));
  }

  protected removeItem(index: number): void {
    this.draft.update((current) => ({
      ...current,
      items: current.items.filter((_, itemIndex) => itemIndex !== index),
    }));
  }

  protected onProduct(index: number, event: Event): void {
    const value = (event.target as HTMLSelectElement).value;
    this.patchItem(index, { productId: value || null });
  }

  protected onFreeText(index: number, event: Event): void {
    this.patchItem(index, { freeText: (event.target as HTMLInputElement).value });
  }

  protected onQuantity(index: number, event: Event): void {
    const quantity = Number((event.target as HTMLInputElement).value);
    this.patchItem(index, { quantity: Number.isFinite(quantity) ? quantity : 1 });
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    const found = validateIntakeDraft(this.draft(), this.today);
    this.issues.set(found);
    if (found.length > 0) {
      return;
    }

    this.saving.set(true);
    this.error.set(null);
    try {
      const result = await this.requests.createAssisted(
        buildAssistedRequestPayload(this.draft(), this.idempotencyKey),
      );
      this.allowLeave = true;
      await this.router.navigate(['/sales/requests', result.request_id], {
        state: { deduplicated: result.deduplicated },
      });
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  private patchItem(index: number, patch: Partial<IntakeDraft['items'][number]>): void {
    this.draft.update((current) => ({
      ...current,
      items: current.items.map((item, itemIndex) =>
        itemIndex === index ? { ...item, ...patch } : item,
      ),
    }));
  }

  private async search(value: string): Promise<void> {
    try {
      this.matches.set(await this.customers.search(value));
    } catch (failure) {
      this.error.set(toAppError(failure));
    }
  }

  private async labelCustomer(id: string): Promise<void> {
    try {
      const customer = await this.customers.getById(id);
      if (!customer || customer.is_anonymized) {
        this.useNewCustomer();
        return;
      }
      this.selectedName.set(customerDisplayName(customer));
      this.baseline = JSON.stringify(this.draft());
    } catch (failure) {
      this.error.set(toAppError(failure));
    }
  }

  private async loadProducts(): Promise<void> {
    const { data, error } = await this.supabase.client
      .from('products')
      .select('id, name, type')
      .eq('status', 'active')
      .order('name', { ascending: true });
    if (error) {
      this.error.set(toAppError(error));
      return;
    }
    this.products.set((data ?? []) as ProductOption[]);
  }
}

function isAssistedChannel(value: string | null): value is AssistedChannel {
  return ASSISTED_CHANNELS.some((channel) => channel === value);
}

function fieldSection(
  field: string,
): 'channel' | 'customer' | 'travel' | 'items' | 'privacy' | null {
  if (field === 'firstName' || field === 'email' || field === 'phone' || field === 'customer') {
    return 'customer';
  }
  if (
    field === 'travelStart' ||
    field === 'travelEnd' ||
    field === 'adults' ||
    field === 'children'
  ) {
    return 'travel';
  }
  if (field === 'items' || field.startsWith('item-')) {
    return 'items';
  }
  if (field === 'privacyNoticeGiven') {
    return 'privacy';
  }
  if (field === 'channel') {
    return 'channel';
  }
  return null;
}

function todayIso(now = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Bogota',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}
