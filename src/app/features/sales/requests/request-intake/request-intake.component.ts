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
      <header class="page-head">
        <h1>Nueva solicitud</h1>
        <p class="hint">Los campos con <span class="req-star">*</span> son obligatorios.</p>
      </header>

      <form (submit)="onSubmit($event)" novalidate>
        <section class="section" [class.incomplete]="sectionIncomplete('channel')">
          <h2>Canal</h2>
          <div class="form-grid">
            <div class="field">
              <label for="channel">¿Por dónde llegó?</label>
              <select id="channel" [formField]="intakeForm.channel">
                @for (channel of channels; track channel) {
                  <option [value]="channel">{{ channelLabel(channel) }}</option>
                }
              </select>
            </div>
          </div>
        </section>

        <section class="section" [class.incomplete]="sectionIncomplete('customer')">
          <h2>Cliente</h2>
          @if (draft().customerId) {
            <div class="selected">
              <p>
                <span class="hint">Cliente seleccionado</span>
                <strong>{{ selectedName() }}</strong>
              </p>
              <button type="button" (click)="useNewCustomer()">Cambiar</button>
            </div>
          } @else {
            <div class="field search">
              <label for="customer-q">Buscar cliente existente</label>
              <input
                id="customer-q"
                type="search"
                [value]="searchDraft()"
                (input)="onSearch($event)"
                placeholder="Nombre, correo o teléfono"
              />
              @if (matches().length > 0) {
                <ul class="matches">
                  @for (match of matches(); track match.id) {
                    <li>
                      <button type="button" (click)="selectCustomer(match)">
                        {{ display(match) }}
                      </button>
                    </li>
                  }
                </ul>
              }
            </div>

            <p class="divider"><span>o registra un cliente nuevo</span></p>

            <div class="form-grid">
              <div class="field req">
                <label for="first-name">Nombre</label>
                <input id="first-name" type="text" [formField]="intakeForm.firstName" />
                @if (issue('firstName'); as message) {
                  <p class="field-error">{{ message }}</p>
                }
              </div>
              <div class="field">
                <label for="last-name">Apellido</label>
                <input id="last-name" type="text" [formField]="intakeForm.lastName" />
              </div>
              <div class="field">
                <label for="email">Correo</label>
                <input id="email" type="email" [formField]="intakeForm.email" />
                @if (issue('email'); as message) {
                  <p class="field-error">{{ message }}</p>
                }
              </div>
              <div class="field">
                <label for="phone">Teléfono</label>
                <input id="phone" type="tel" [formField]="intakeForm.phone" />
              </div>
              <div class="field">
                <label for="country">País</label>
                <input id="country" type="text" [formField]="intakeForm.countryCode" />
              </div>
            </div>
            <p class="hint">Necesitamos al menos un correo o un teléfono para contactarlo.</p>
          }
        </section>

        <section class="section" [class.incomplete]="sectionIncomplete('travel')">
          <h2>Viaje</h2>
          <div class="form-grid">
            <div class="field">
              <label for="start">Fecha de inicio</label>
              <input id="start" type="date" [min]="today" [formField]="intakeForm.travelStart" />
              @if (issue('travelStart'); as message) {
                <p class="field-error">{{ message }}</p>
              }
            </div>
            <div class="field">
              <label for="end">Fecha de fin</label>
              <input
                id="end"
                type="date"
                [min]="draft().travelStart || today"
                [formField]="intakeForm.travelEnd"
              />
              @if (issue('travelEnd'); as message) {
                <p class="field-error">{{ message }}</p>
              }
            </div>
            <div class="field req">
              <label for="adults">Adultos</label>
              <input id="adults" type="number" [formField]="intakeForm.adults" />
              @if (issue('adults'); as message) {
                <p class="field-error">{{ message }}</p>
              }
            </div>
            <div class="field">
              <label for="children">Niños</label>
              <input id="children" type="number" [formField]="intakeForm.children" />
            </div>
          </div>
        </section>

        <section class="section" [class.incomplete]="sectionIncomplete('items')">
          <h2>Intereses</h2>
          <p class="hint">Elige un producto del catálogo o describe lo que busca el cliente.</p>
          @for (item of draft().items; track $index) {
            <div class="item-row">
              <div class="field product">
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
              </div>
              <div class="field">
                <label [attr.for]="'free-' + $index">Descripción</label>
                <input
                  [id]="'free-' + $index"
                  type="text"
                  [value]="item.freeText"
                  (input)="onFreeText($index, $event)"
                />
              </div>
              <div class="field qty">
                <label [attr.for]="'qty-' + $index">Cantidad</label>
                <input
                  [id]="'qty-' + $index"
                  type="number"
                  min="1"
                  max="99"
                  [value]="item.quantity"
                  (input)="onQuantity($index, $event)"
                />
              </div>
              @if (draft().items.length > 1) {
                <button type="button" class="remove danger" (click)="removeItem($index)">
                  Quitar
                </button>
              }
              @if (issue('item-' + $index); as message) {
                <p class="field-error span-all">{{ message }}</p>
              }
            </div>
          }
          @if (issue('items'); as message) {
            <p class="field-error">{{ message }}</p>
          }
          <button type="button" (click)="addItem()">+ Agregar interés</button>
        </section>

        <section class="section">
          <h2>Notas del cliente</h2>
          <div class="field">
            <label for="requirements">Requerimientos especiales</label>
            <textarea
              id="requirements"
              rows="3"
              placeholder="Alergias, movilidad, celebraciones…"
              [formField]="intakeForm.specialRequirements"
            ></textarea>
          </div>
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

        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }

        <div class="form-actions">
          <button class="primary" type="submit" [disabled]="saving()">
            {{ saving() ? 'Guardando…' : 'Guardar solicitud' }}
          </button>
          <a class="button-link" routerLink="/sales/requests">Cancelar</a>
        </div>
      </form>
    </div>
  `,
  styles: `
    .stack,
    form {
      display: grid;
      gap: 1rem;
    }

    .section {
      gap: 0.85rem;
    }

    .selected {
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem;
      align-items: center;
      justify-content: space-between;
      padding: 0.75rem 0.9rem;
      border: 1px solid var(--color-primary-border);
      border-radius: var(--radius-md);
      background: var(--color-primary-tint);
    }

    .selected p {
      display: grid;
      margin: 0;
    }

    .search {
      max-width: 36rem;
    }

    .matches {
      display: grid;
      margin: 0;
      padding: 0.25rem;
      list-style: none;
      border: 1px solid var(--color-border-strong);
      border-radius: var(--radius-md);
      background: var(--color-surface);
      box-shadow: 0 8px 24px rgb(15 23 42 / 8%);
    }

    .matches button {
      width: 100%;
      justify-content: flex-start;
      border: 0;
      font-weight: 500;
    }

    .matches button:hover {
      background: var(--color-primary-tint);
    }

    .item-row {
      display: grid;
      grid-template-columns: minmax(12rem, 1.2fr) minmax(12rem, 1.5fr) 6rem auto;
      gap: 0.75rem;
      align-items: end;
      max-width: 60rem;
      padding: 0.85rem;
      border: 1px solid var(--color-border);
      border-radius: var(--radius-md);
      background: var(--color-surface-muted);
    }

    .item-row .span-all {
      grid-column: 1 / -1;
    }

    .remove {
      min-height: 2.5rem;
    }

    @media (max-width: 760px) {
      .item-row {
        grid-template-columns: 1fr 6rem;
      }

      .item-row .product,
      .item-row .field:not(.product, .qty) {
        grid-column: 1 / -1;
      }
    }

    .check {
      display: flex;
      gap: 0.5rem;
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
