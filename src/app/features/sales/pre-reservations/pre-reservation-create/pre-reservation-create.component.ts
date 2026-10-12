import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { form, FormField } from '@angular/forms/signals';
import { Router, RouterLink } from '@angular/router';
import type { RequestDetail } from '../../../../core/customers/models/request.model';
import {
  RequestService,
  type AssigneeOption,
} from '../../../../core/customers/services/request.service';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import {
  PreReservationService,
  type BookableOption,
  type BookableProvider,
} from '../../../../core/pre-reservations/services/pre-reservation.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../../shared/components/unsaved-changes.guard';
import {
  buildCreatePayload,
  draftsFromRequest,
  emptyItemDraft,
  emptyPreReservationDraft,
  validateItemDrafts,
  type PreReservationDraft,
  type PreReservationIssue,
  type PreReservationItemDraft,
} from './pre-reservation-payload';

/**
 * Converts a request into a pre-reservation (US1).
 *
 * The service lines come pre-filled from the request interests that carry a product; the
 * agent adjusts dates and passengers, may add manual-provider lines and alternatives, and
 * `create` does the rest. Line validation is an affordance — `create_pre_reservation`
 * repeats every rule server-side.
 */
@Component({
  selector: 'app-pre-reservation-create',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <div class="stack">
      @if (!requestId()) {
        <h1>Nueva pre-reserva</h1>
        <p>Abre una solicitud y usa “Crear pre-reserva”.</p>
        <p><a class="button-link" routerLink="/sales/requests">Ir a solicitudes</a></p>
      } @else if (loading()) {
        <app-spinner label="Cargando solicitud…" />
      } @else if (request(); as current) {
        <h1>Nueva pre-reserva para {{ current.reference }}</h1>

        <app-alert kind="info">
          Una pre-reserva no es una reserva confirmada: requiere verificar disponibilidad con los
          proveedores.
        </app-alert>

        <form (submit)="onSubmit($event)" novalidate>
          <section class="section" [class.incomplete]="itemsIncomplete()">
            <h2>Servicios</h2>
            @for (item of draft().items; track $index) {
              <fieldset class="plain item-row">
                <legend>Servicio {{ $index + 1 }}</legend>

                <label [attr.for]="'pr-kind-' + $index">Tipo</label>
                <select
                  [id]="'pr-kind-' + $index"
                  [value]="item.kind"
                  (change)="onKind($index, $event)"
                >
                  <option value="product">Producto</option>
                  <option value="addon">Complemento</option>
                </select>

                <label class="req" [attr.for]="'pr-bookable-' + $index">
                  {{ item.kind === 'product' ? 'Producto' : 'Complemento' }}
                </label>
                <select
                  [id]="'pr-bookable-' + $index"
                  [value]="bookableValue(item)"
                  (change)="onBookable($index, $event)"
                >
                  <option value="">Elige…</option>
                  @for (option of optionsFor(item.kind); track option.id) {
                    <option [value]="option.id">{{ option.name }}</option>
                  }
                </select>
                @if (issue('item-' + $index + '.bookable'); as message) {
                  <p class="field-error">{{ message }}</p>
                }

                <label class="req" [attr.for]="'pr-start-' + $index">Desde</label>
                <input
                  [id]="'pr-start-' + $index"
                  type="date"
                  [min]="today"
                  [value]="item.startDate"
                  (change)="onDate($index, 'startDate', $event)"
                />
                @if (issue('item-' + $index + '.startDate'); as message) {
                  <p class="field-error">{{ message }}</p>
                }

                <label [class.req]="isAccommodation(item)" [attr.for]="'pr-end-' + $index">
                  Hasta
                </label>
                <input
                  [id]="'pr-end-' + $index"
                  type="date"
                  [min]="item.startDate || today"
                  [value]="item.endDate"
                  (change)="onDate($index, 'endDate', $event)"
                />
                @if (issue('item-' + $index + '.endDate'); as message) {
                  <p class="field-error">{{ message }}</p>
                }

                <label class="req" [attr.for]="'pr-adults-' + $index">Adultos</label>
                <input
                  [id]="'pr-adults-' + $index"
                  type="number"
                  min="1"
                  max="99"
                  [value]="item.adults"
                  (input)="onNumber($index, 'adults', $event)"
                />
                @if (issue('item-' + $index + '.adults'); as message) {
                  <p class="field-error">{{ message }}</p>
                }

                <label [attr.for]="'pr-children-' + $index">Niños</label>
                <input
                  [id]="'pr-children-' + $index"
                  type="number"
                  min="0"
                  max="99"
                  [value]="item.children"
                  (input)="onNumber($index, 'children', $event)"
                />
                @if (issue('item-' + $index + '.children'); as message) {
                  <p class="field-error">{{ message }}</p>
                }

                <label [attr.for]="'pr-quantity-' + $index">Cantidad</label>
                <input
                  [id]="'pr-quantity-' + $index"
                  type="number"
                  min="1"
                  max="99"
                  [value]="item.quantity"
                  (input)="onNumber($index, 'quantity', $event)"
                />
                @if (issue('item-' + $index + '.quantity'); as message) {
                  <p class="field-error">{{ message }}</p>
                }

                @if (providerOf(item); as provider) {
                  <p class="notice">
                    Proveedor: {{ provider.name }} ·
                    {{ provider.contact_phone || 'sin teléfono' }} ·
                    {{ provider.contact_email || 'sin correo' }}
                  </p>
                } @else {
                  <label [attr.for]="'pr-provider-' + $index">Proveedor</label>
                  <input
                    [id]="'pr-provider-' + $index"
                    type="text"
                    [value]="item.providerName"
                    (input)="onProvider($index, 'providerName', $event)"
                  />
                  <label [attr.for]="'pr-phone-' + $index">Teléfono del proveedor</label>
                  <input
                    [id]="'pr-phone-' + $index"
                    type="tel"
                    [value]="item.providerPhone"
                    (input)="onProvider($index, 'providerPhone', $event)"
                  />
                  <label [attr.for]="'pr-email-' + $index">Correo del proveedor</label>
                  <input
                    [id]="'pr-email-' + $index"
                    type="email"
                    [value]="item.providerEmail"
                    (input)="onProvider($index, 'providerEmail', $event)"
                  />
                }

                <label [attr.for]="'pr-alt-' + $index">Es alternativa de</label>
                <select
                  [id]="'pr-alt-' + $index"
                  [value]="item.alternativeOf ?? ''"
                  (change)="onAlternative($index, $event)"
                >
                  <option value="">No es alternativa</option>
                  @for (principal of principalOptions($index); track principal.index) {
                    <option [value]="principal.index">{{ principal.label }}</option>
                  }
                </select>
                <p class="hint">
                  Las alternativas se verifican, pero no cuentan para el estado de la pre-reserva.
                </p>
                @if (issue('item-' + $index + '.alternativeOf'); as message) {
                  <p class="field-error">{{ message }}</p>
                }

                <div class="actions">
                  <button type="button" (click)="removeItem($index)">Quitar</button>
                </div>
              </fieldset>
            }
            @if (issue('items'); as message) {
              <p class="field-error">{{ message }}</p>
            }
            <div class="actions">
              <button type="button" (click)="addItem()">Agregar servicio</button>
            </div>
          </section>

          <section class="section">
            <h2>Verificación</h2>
            <label for="assigned-operator">Operador asignado</label>
            <select id="assigned-operator" [formField]="createForm.assignedOperatorId">
              <option value="">Sin asignar</option>
              @for (person of operators(); track person.id) {
                <option [value]="person.id">{{ person.full_name }}</option>
              }
            </select>
            <p class="hint">
              Puedes dejarlo sin asignar; quien gestione la verificación aparecerá en el detalle.
            </p>
          </section>

          <div class="actions">
            <button class="primary" type="submit" [disabled]="saving()">
              {{ saving() ? 'Creando…' : 'Crear pre-reserva' }}
            </button>
            <a class="button-link" [routerLink]="['/sales/requests', current.id]">Cancelar</a>
          </div>

          @if (error(); as failure) {
            <app-alert kind="error">{{ failure.message }}</app-alert>
          }
        </form>
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
        <p><a class="button-link" routerLink="/sales/requests">Ir a solicitudes</a></p>
      } @else {
        <app-alert kind="error">No encontramos esta solicitud.</app-alert>
        <p><a class="button-link" routerLink="/sales/requests">Ir a solicitudes</a></p>
      }
    </div>
  `,
  styles: `
    .stack,
    form {
      display: grid;
      gap: 0.85rem;
    }

    .item-row {
      padding: 0.75rem;
      border: 1px solid #e7e5e4;
      border-radius: 0.35rem;
    }
  `,
})
export class PreReservationCreateComponent implements UnsavedChangesHost {
  private readonly requests = inject(RequestService);
  private readonly preReservations = inject(PreReservationService);
  private readonly router = inject(Router);

  /** Bound from `?requestId=<uuid>` by `withComponentInputBinding()`. */
  readonly requestId = input<string | undefined>(undefined);

  protected readonly today = todayIso();
  protected readonly request = signal<RequestDetail | null>(null);
  protected readonly bookables = signal<BookableOption[]>([]);
  protected readonly operators = signal<AssigneeOption[]>([]);
  protected readonly draft = signal<PreReservationDraft>(emptyPreReservationDraft());
  protected readonly createForm = form(this.draft);
  protected readonly issues = signal<PreReservationIssue[]>([]);
  protected readonly loading = signal(true);
  protected readonly saving = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly itemsIncomplete = computed(() =>
    this.issues().some((issue) => issue.field === 'items' || issue.field.startsWith('item-')),
  );
  private baseline = JSON.stringify(emptyPreReservationDraft());
  private allowLeave = false;

  constructor() {
    effect(() => {
      const requestId = this.requestId();
      untracked(() => void this.load(requestId));
    });
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

  protected optionsFor(kind: 'product' | 'addon'): BookableOption[] {
    return this.bookables().filter((option) =>
      kind === 'product' ? option.kind !== 'addon' : option.kind === 'addon',
    );
  }

  protected bookableValue(item: PreReservationItemDraft): string {
    return (item.kind === 'product' ? item.productId : item.addonId) ?? '';
  }

  protected isAccommodation(item: PreReservationItemDraft): boolean {
    return item.itemKind === 'accommodation';
  }

  /** Read-only provider snapshot of the selected product, when it has an active provider. */
  protected providerOf(item: PreReservationItemDraft): BookableProvider | null {
    if (item.kind !== 'product' || !item.productId || !item.productHasProvider) {
      return null;
    }
    return this.bookables().find((option) => option.id === item.productId)?.provider ?? null;
  }

  /** Main rows above this one, so an alternative can only point backwards. */
  protected principalOptions(index: number): { index: number; label: string }[] {
    const items = this.draft().items;
    const options: { index: number; label: string }[] = [];
    for (let position = 0; position < index; position++) {
      const item = items[position];
      if (item.alternativeOf === null) {
        options.push({ index: position, label: lineLabel(item, position, this.bookables()) });
      }
    }
    return options;
  }

  protected addItem(): void {
    this.draft.update((current) => ({
      ...current,
      items: [...current.items, emptyItemDraft()],
    }));
  }

  protected removeItem(index: number): void {
    this.draft.update((current) => ({
      ...current,
      items: current.items
        .filter((_, position) => position !== index)
        .map((item) => {
          if (item.alternativeOf === null || item.alternativeOf < index) {
            return item;
          }
          if (item.alternativeOf === index) {
            return { ...item, alternativeOf: null };
          }
          return { ...item, alternativeOf: item.alternativeOf - 1 };
        }),
    }));
  }

  protected onKind(index: number, event: Event): void {
    const kind = (event.target as HTMLSelectElement).value === 'addon' ? 'addon' : 'product';
    this.patchItem(index, {
      kind,
      productId: null,
      addonId: null,
      itemKind: null,
      productHasProvider: false,
      providerName: '',
      providerPhone: '',
      providerEmail: '',
    });
  }

  protected onBookable(index: number, event: Event): void {
    const id = (event.target as HTMLSelectElement).value;
    const item = this.draft().items[index];
    if (!item) {
      return;
    }
    if (!id) {
      this.patchItem(
        index,
        item.kind === 'product'
          ? {
              productId: null,
              itemKind: null,
              productHasProvider: false,
              providerName: '',
              providerPhone: '',
              providerEmail: '',
            }
          : { addonId: null },
      );
      return;
    }
    const bookable = this.bookables().find((option) => option.id === id);
    if (!bookable) {
      return;
    }
    if (item.kind === 'addon') {
      this.patchItem(index, { addonId: bookable.id });
      return;
    }
    const provider = bookable.provider && bookable.provider.is_active ? bookable.provider : null;
    this.patchItem(index, {
      productId: bookable.id,
      itemKind: bookable.kind,
      productHasProvider: provider !== null,
      providerName: provider?.name ?? '',
      providerPhone: provider?.contact_phone ?? '',
      providerEmail: provider?.contact_email ?? '',
    });
  }

  protected onDate(index: number, field: 'startDate' | 'endDate', event: Event): void {
    const value = textValue(event);
    this.patchItem(index, field === 'startDate' ? { startDate: value } : { endDate: value });
  }

  protected onNumber(index: number, field: 'adults' | 'children' | 'quantity', event: Event): void {
    const value = numberValue(event);
    this.patchItem(
      index,
      field === 'adults'
        ? { adults: value }
        : field === 'children'
          ? { children: value }
          : { quantity: value },
    );
  }

  protected onProvider(
    index: number,
    field: 'providerName' | 'providerPhone' | 'providerEmail',
    event: Event,
  ): void {
    const value = textValue(event);
    this.patchItem(
      index,
      field === 'providerName'
        ? { providerName: value }
        : field === 'providerPhone'
          ? { providerPhone: value }
          : { providerEmail: value },
    );
  }

  protected onAlternative(index: number, event: Event): void {
    const raw = (event.target as HTMLSelectElement).value;
    this.patchItem(index, { alternativeOf: raw === '' ? null : Number(raw) });
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    const requestId = this.requestId();
    if (!requestId) {
      return;
    }

    const found = validateItemDrafts(this.draft().items, this.today);
    this.issues.set(found);
    if (found.length > 0) {
      return;
    }

    this.saving.set(true);
    this.error.set(null);
    try {
      const draft = this.draft();
      const result = await this.preReservations.create(
        requestId,
        buildCreatePayload(draft.items, draft.assignedOperatorId),
      );
      this.allowLeave = true;
      await this.router.navigate(['/sales/pre-reservations', result.pre_reservation_id]);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  private patchItem(index: number, patch: Partial<PreReservationItemDraft>): void {
    this.draft.update((current) => ({
      ...current,
      items: current.items.map((item, position) =>
        position === index ? { ...item, ...patch } : item,
      ),
    }));
  }

  private async load(requestId: string | undefined): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.request.set(null);
    if (!requestId) {
      this.loading.set(false);
      return;
    }
    try {
      const [request, bookables, operators] = await Promise.all([
        this.requests.getById(requestId),
        this.preReservations.listBookables(),
        this.preReservations.listOperators(),
      ]);
      this.request.set(request);
      this.bookables.set(bookables);
      this.operators.set(operators);
      this.draft.set({
        items: request ? draftsFromRequest(request, bookables) : [],
        assignedOperatorId: '',
      });
      this.issues.set([]);
      this.baseline = JSON.stringify(this.draft());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}

function lineLabel(
  item: PreReservationItemDraft,
  index: number,
  bookables: BookableOption[],
): string {
  const id = item.kind === 'product' ? item.productId : item.addonId;
  const bookable = id ? bookables.find((option) => option.id === id) : undefined;
  const name = bookable ? ` — ${bookable.name}` : '';
  return `Servicio ${index + 1}${name}`;
}

function textValue(event: Event): string {
  return (event.target as HTMLInputElement).value;
}

function numberValue(event: Event): number {
  const value = (event.target as HTMLInputElement).valueAsNumber;
  return Number.isFinite(value) ? value : 0;
}

function todayIso(now = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Bogota',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}
