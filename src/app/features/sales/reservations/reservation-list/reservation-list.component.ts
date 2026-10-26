import { DatePipe } from '@angular/common';
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
import { customerDisplayName } from '../../../../core/customers/models/customer.model';
import { toAppError } from '../../../../core/error/error-handler';
import {
  RESERVATION_STATUS_LABELS,
  type ReservationListRow,
  type ReservationStatus,
} from '../../../../core/reservations/models/reservation.model';
import { ReservationService } from '../../../../core/reservations/services/reservation.service';
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

const STATUSES: ReservationStatus[] = [
  'confirmed',
  'in_progress',
  'completed',
  'cancelled',
];

@Component({
  selector: 'app-reservation-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, DataTableComponent],
  template: `
    <app-data-table
      title="Reservas"
      [loading]="loading()"
      [error]="error()"
      [total]="total()"
      [page]="query().page"
      [filtered]="filteredActive()"
      emptyMessage="Todavía no hay reservas."
      loadingLabel="Cargando reservas…"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      <div dataTableFilters class="filters-bar">
        <label for="reservation-q">
          Buscar
          <input
            id="reservation-q"
            type="search"
            [value]="searchDraft()"
            (input)="onSearch($event)"
            placeholder="Localizador, cotización o cliente"
          />
        </label>
        <label for="reservation-status">
          Estado
          <select id="reservation-status" [value]="query().status" (change)="onStatus($event)">
            <option value="">Todos</option>
            @for (status of statuses; track status) {
              <option [value]="status">{{ statusLabel(status) }}</option>
            }
          </select>
        </label>
      </div>

      <table class="data">
        <thead>
          <tr>
            <th>Localizador</th>
            <th>Cliente</th>
            <th>Estado</th>
            <th>Viaje</th>
            <th>Total</th>
            <th>Saldo</th>
          </tr>
        </thead>
        <tbody>
          @for (row of rows(); track row.version_id) {
            <tr>
              <td>
                <a [routerLink]="['/sales/reservations', row.version_id]">{{ row.reference }}</a>
              </td>
              <td>{{ displayName(row) }}</td>
              <td>{{ statusLabel(row.status) }}</td>
              <td>
                {{ row.travel_start_date | date: 'mediumDate' }}
                @if (row.travel_end_date) {
                  – {{ row.travel_end_date | date: 'mediumDate' }}
                }
              </td>
              <td>{{ row.total }} {{ row.currency }}</td>
              <td>{{ row.balance }} {{ row.currency }}</td>
            </tr>
          }
        </tbody>
      </table>
    </app-data-table>
  `,
})
export class ReservationListComponent {
  private readonly reservations = inject(ReservationService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly statuses = STATUSES;
  protected readonly statusLabel = (status: ReservationStatus) => RESERVATION_STATUS_LABELS[status];
  protected readonly searchDraft = signal('');
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly rows = signal<ReservationListRow[]>([]);
  protected readonly total = signal(0);
  protected readonly filteredActive = computed(() => hasActiveListFilters(this.query()));
  private appliedQ = '';

  private readonly commitSearch = debounce((value: string) => {
    this.write(withListFilterChange(this.query(), { q: value.trim() }));
  }, LIST_SEARCH_DEBOUNCE_MS);

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
  }

  protected displayName(row: ReservationListRow): string {
    return customerDisplayName({
      first_name: row.customer_first_name,
      last_name: row.customer_last_name,
      is_anonymized: row.customer_is_anonymized,
    });
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

  protected onPage(page: number): void {
    this.write({ ...this.query(), page });
  }

  protected onClear(): void {
    this.searchDraft.set('');
    this.write(emptyListQuery());
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
    try {
      const page = await this.reservations.listPage({
        q: query.q,
        status: query.status as ReservationStatus | '',
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
}
