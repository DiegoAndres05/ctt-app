import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../../core/auth/services/auth.service';
import { customerDisplayName } from '../../../../core/customers/models/customer.model';
import type { AssigneeOption } from '../../../../core/customers/services/request.service';
import { toAppError } from '../../../../core/error/error-handler';
import {
  AVAILABILITY_STATUS_LABELS,
  type VerificationQueueRow,
} from '../../../../core/pre-reservations/models/verification.model';
import { providerContactLinks } from '../../../../core/pre-reservations/provider-contact-links';
import {
  AvailabilityVerificationService,
  type VerificationQueueStatus,
} from '../../../../core/pre-reservations/services/availability-verification.service';
import { PreReservationService } from '../../../../core/pre-reservations/services/pre-reservation.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { DataTableComponent } from '../../../../shared/components/data-table/data-table.component';
import {
  LIST_SEARCH_DEBOUNCE_MS,
  debounce,
  emptyListQuery,
  hasActiveListFilters,
  listQueryToParams,
  pageCount,
  parseListQuery,
  withListFilterChange,
  type ListQuery,
} from '../../../../shared/components/data-table/list-query';
import { VerificationOutcomeFormComponent } from '../verification-outcome-form/verification-outcome-form.component';

/** Estado filter of the queue (contracts §6.4); `''` is the «Requieren acción» default. */
const STATUS_OPTIONS: readonly { value: VerificationQueueStatus; label: string }[] = [
  { value: '', label: 'Requieren acción' },
  { value: 'pending', label: 'Pendientes' },
  { value: 'available', label: 'Disponibles' },
  { value: 'unavailable', label: 'No disponibles' },
  { value: 'alternative_suggested', label: 'Alternativa sugerida' },
  { value: 'all', label: 'Todas' },
];

/** One rendered body entry: a data row, or a provider header when grouping is on. */
type QueueEntry =
  { kind: 'group'; key: string; label: string } | { kind: 'row'; row: VerificationQueueRow };

@Component({
  selector: 'app-verification-queue',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, DataTableComponent, AlertComponent, VerificationOutcomeFormComponent],
  template: `
    <app-data-table
      title="Verificación de disponibilidad"
      [loading]="loading()"
      [error]="error()"
      [total]="total()"
      [page]="query().page"
      [filtered]="filteredActive()"
      emptyMessage="No hay servicios pendientes de verificación."
      loadingLabel="Cargando verificaciones…"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      <div dataTableFilters class="filters-bar">
        <label for="queue-q">
          Buscar
          <input
            id="queue-q"
            type="search"
            [value]="searchDraft()"
            (input)="onSearch($event)"
            placeholder="Referencia, servicio, proveedor o cliente"
          />
        </label>
        <label for="queue-status">
          Estado
          <select id="queue-status" [value]="query().status" (change)="onStatus($event)">
            @for (option of statusOptions; track option.value) {
              <option [value]="option.value">{{ option.label }}</option>
            }
          </select>
        </label>
        <label for="queue-provider">
          Proveedor
          <select id="queue-provider" [value]="query().providerId" (change)="onProvider($event)">
            <option value="">Todos</option>
            <option value="none">Sin proveedor</option>
            @for (provider of providers(); track provider.id) {
              <option [value]="provider.id">{{ provider.name }}</option>
            }
          </select>
        </label>
        <label for="queue-assignee">
          Operador
          <select id="queue-assignee" [value]="query().assignee" (change)="onAssignee($event)">
            <option value="">Todos</option>
            <option value="me">Mías</option>
            <option value="none">Sin asignar</option>
            @for (operator of operators(); track operator.id) {
              <option [value]="operator.id">{{ operator.full_name }}</option>
            }
          </select>
        </label>
        <label class="check">
          <input
            type="checkbox"
            [checked]="query().group === 'provider'"
            (change)="onGroup($event)"
          />
          Agrupar por proveedor
        </label>
      </div>

      @if (actionError(); as failure) {
        <app-alert kind="error">{{ failure }}</app-alert>
      }

      <table class="data">
        <thead>
          <tr>
            <th>Fecha servicio</th>
            <th>Servicio</th>
            <th>Pasajeros</th>
            <th>Proveedor</th>
            <th>Pre-reserva</th>
            <th>Cliente</th>
            <th>Estado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          @for (entry of entries(); track entryKey(entry)) {
            @if (entry.kind === 'group') {
              <tr class="group-row">
                <td colspan="8">{{ entry.label }}</td>
              </tr>
            } @else {
              <tr>
                <td>{{ formatDay(entry.row.start_date) }}</td>
                <td>
                  @if (entry.row.is_alternative) {
                    <span class="tag">Alternativa</span>
                  }
                  {{ entry.row.item_label }}
                </td>
                <td>{{ pax(entry.row) }}</td>
                <td>
                  @if (entry.row.provider_name; as providerName) {
                    {{ providerName }}
                    @if (contactLinks(entry.row); as links) {
                      @if (links.tel) {
                        <a [href]="links.tel">Llamar</a>
                      }
                      @if (links.whatsapp) {
                        <a [href]="links.whatsapp" target="_blank" rel="noopener noreferrer">
                          WhatsApp
                        </a>
                      }
                      @if (links.mailto) {
                        <a [href]="links.mailto">Correo</a>
                      }
                    }
                  } @else {
                    Sin proveedor
                  }
                </td>
                <td>
                  <a [routerLink]="['/sales/pre-reservations', entry.row.pre_reservation_id]">
                    {{ entry.row.reference }}
                  </a>
                </td>
                <td>{{ customerName(entry.row) }}</td>
                <td>
                  {{ statusLabel(entry.row.verification_status) }}
                  @if (entry.row.hold_expired) {
                    <span> · Retención vencida</span>
                  } @else if (entry.row.verification_started_at) {
                    <span>
                      · En gestión por {{ entry.row.assigned_operator_name || 'operador' }}</span
                    >
                  }
                </td>
                <td class="row-actions">
                  <button
                    type="button"
                    (click)="start(entry.row)"
                    [disabled]="
                      entry.row.verification_started_at !== null ||
                      busyItemId() === entry.row.item_id
                    "
                  >
                    Iniciar gestión
                  </button>
                  <button
                    type="button"
                    (click)="toggleOutcome(entry.row)"
                    [disabled]="busyItemId() === entry.row.item_id"
                  >
                    Registrar resultado
                  </button>
                </td>
              </tr>
              @if (outcomeItem(); as openRow) {
                @if (openRow.item_id === entry.row.item_id) {
                  <tr class="outcome-row">
                    <td colspan="8">
                      <app-verification-outcome-form
                        [item]="openRow"
                        (saved)="onOutcomeSaved()"
                        (cancelled)="closeOutcome()"
                      />
                    </td>
                  </tr>
                }
              }
            }
          }
        </tbody>
      </table>
    </app-data-table>
  `,
  styles: `
    .group-row td {
      background: #f5f5f4;
      font-weight: 600;
    }

    .tag {
      display: inline-block;
      margin-right: 0.35rem;
      padding: 0 0.35rem;
      border-radius: 0.25rem;
      background: #fef3c7;
      color: #92400e;
      font-size: 0.75rem;
    }

    .row-actions button + button {
      margin-left: 0.4rem;
    }

    td a + a {
      margin-left: 0.4rem;
    }

    .outcome-row td {
      background: #fafaf9;
    }
  `,
})
export class VerificationQueueComponent {
  private readonly verifications = inject(AvailabilityVerificationService);
  private readonly preReservations = inject(PreReservationService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly statusOptions = STATUS_OPTIONS;
  protected readonly statusLabel = (status: VerificationQueueRow['verification_status']) =>
    AVAILABILITY_STATUS_LABELS[status];
  protected readonly searchDraft = signal('');
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly actionError = signal<string | null>(null);
  protected readonly rows = signal<VerificationQueueRow[]>([]);
  protected readonly total = signal(0);
  protected readonly providers = signal<{ id: string; name: string }[]>([]);
  protected readonly operators = signal<AssigneeOption[]>([]);
  protected readonly outcomeItem = signal<VerificationQueueRow | null>(null);
  protected readonly busyItemId = signal<string | null>(null);
  protected readonly filteredActive = computed(() => hasActiveListFilters(this.query()));
  private appliedQ = '';

  /** Body entries in render order; inserts provider headers when the grouping filter is on. */
  protected readonly entries = computed<QueueEntry[]>(() => {
    const grouped = this.query().group === 'provider';
    const rows = this.rows();
    if (!grouped) {
      return rows.map((row) => ({ kind: 'row' as const, row }));
    }
    const result: QueueEntry[] = [];
    let lastKey: string | null = null;
    for (const row of rows) {
      const key = row.provider_id ?? 'none';
      if (key !== lastKey) {
        lastKey = key;
        result.push({
          kind: 'group',
          key: `group:${key}`,
          label: row.provider_name ?? 'Sin proveedor',
        });
      }
      result.push({ kind: 'row', row });
    }
    return result;
  });

  private readonly commitSearch = debounce((value: string) => {
    this.write(withListFilterChange(this.query(), { q: value.trim() }));
  }, LIST_SEARCH_DEBOUNCE_MS);

  protected readonly entryKey = (entry: QueueEntry): string =>
    entry.kind === 'group' ? entry.key : entry.row.item_id;

  constructor() {
    this.destroyRef.onDestroy(() => {
      this.commitSearch.cancel();
    });

    effect(() => {
      const q = this.query().q;
      untracked(() => {
        if (q !== this.appliedQ) {
          this.appliedQ = q;
          this.searchDraft.set(q);
        }
      });
    });

    effect(() => {
      const query = this.query();
      untracked(() => {
        void this.load(query);
      });
    });

    void this.loadFilterOptions();
  }

  protected formatDay(value: string): string {
    const [year, month, day] = value.slice(0, 10).split('-');
    if (!year || !month || !day) {
      return value;
    }
    return `${day}/${month}/${year}`;
  }

  protected pax(row: VerificationQueueRow): string {
    const adults = `${row.adults} ${row.adults === 1 ? 'adulto' : 'adultos'}`;
    const children =
      row.children > 0 ? ` · ${row.children} ${row.children === 1 ? 'niño' : 'niños'}` : '';
    return `${adults}${children}`;
  }

  protected customerName(row: VerificationQueueRow): string {
    return customerDisplayName({
      first_name: row.customer_first_name,
      last_name: row.customer_last_name,
      is_anonymized: row.customer_is_anonymized,
    });
  }

  protected contactLinks(row: VerificationQueueRow): ReturnType<typeof providerContactLinks> {
    return providerContactLinks(row);
  }

  protected onSearch(event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.searchDraft.set(value);
    this.commitSearch(value);
  }

  protected onStatus(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { status: (event.target as HTMLSelectElement).value }),
    );
  }

  protected onProvider(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { providerId: (event.target as HTMLSelectElement).value }),
    );
  }

  protected onAssignee(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { assignee: (event.target as HTMLSelectElement).value }),
    );
  }

  protected onGroup(event: Event): void {
    const checked = (event.target as HTMLInputElement).checked;
    this.write(withListFilterChange(this.query(), { group: checked ? 'provider' : '' }));
  }

  protected onPage(page: number): void {
    this.write({ ...this.query(), page });
  }

  protected onClear(): void {
    this.searchDraft.set('');
    this.write(emptyListQuery());
  }

  /** Records the first provider contact on a line (RPC `start_item_verification`). */
  protected async start(row: VerificationQueueRow): Promise<void> {
    this.busyItemId.set(row.item_id);
    this.actionError.set(null);
    try {
      await this.verifications.start(row.item_id);
      await this.load(this.query());
    } catch (failure) {
      this.actionError.set(toAppError(failure).message);
    } finally {
      this.busyItemId.set(null);
    }
  }

  /** Deploys the outcome form under the row (toggles it closed on a second click). */
  protected toggleOutcome(row: VerificationQueueRow): void {
    if (this.outcomeItem()?.item_id === row.item_id) {
      this.outcomeItem.set(null);
      return;
    }
    this.outcomeItem.set(row);
  }

  protected onOutcomeSaved(): void {
    this.outcomeItem.set(null);
    void this.load(this.query());
  }

  protected closeOutcome(): void {
    this.outcomeItem.set(null);
  }

  private write(next: ListQuery): void {
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: listQueryToParams(next),
    });
  }

  private async load(query: ListQuery): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    // A new query re-reads the queue; any open outcome form belongs to a stale row.
    this.outcomeItem.set(null);
    const assignee = query.assignee === 'me' ? (this.auth.user()?.id ?? '') : query.assignee;
    try {
      // `queuePage` sweeps expired holds first (R-004), so «Retención vencida» is fresh.
      const page = await this.verifications.queuePage({
        q: query.q,
        status: query.status as VerificationQueueStatus,
        providerId: query.providerId,
        assignee,
        group: query.group,
        page: query.page,
      });
      this.rows.set(page.rows);
      this.total.set(page.total);
      const pages = pageCount(page.total);
      if (page.total > 0 && query.page > pages) {
        this.write({ ...query, page: pages });
      }
    } catch (failure) {
      this.error.set(toAppError(failure).message);
      this.rows.set([]);
      this.total.set(0);
    } finally {
      this.loading.set(false);
    }
  }

  private async loadFilterOptions(): Promise<void> {
    try {
      const [providers, operators] = await Promise.all([
        this.verifications.listProviders(),
        this.preReservations.listOperators(),
      ]);
      this.providers.set(providers);
      this.operators.set(operators);
    } catch {
      this.providers.set([]);
      this.operators.set([]);
    }
  }
}
