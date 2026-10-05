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
import {
  customerDisplayName,
  type CustomerListRow,
} from '../../../../core/customers/models/customer.model';
import { CustomerService } from '../../../../core/customers/services/customer.service';
import { toAppError } from '../../../../core/error/error-handler';
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

@Component({
  selector: 'app-customer-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, DataTableComponent],
  template: `
    <app-data-table
      title="Clientes"
      [loading]="loading()"
      [error]="error()"
      [total]="total()"
      [page]="query().page"
      [filtered]="filteredActive()"
      emptyMessage="Todavía no hay clientes. Se crean al registrar solicitudes."
      loadingLabel="Cargando clientes…"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      <div dataTableFilters class="filters-bar">
        <label for="customer-q">
          Buscar
          <input
            id="customer-q"
            type="search"
            [value]="searchDraft()"
            (input)="onSearch($event)"
            placeholder="Nombre, correo o teléfono"
          />
        </label>
      </div>

      <table class="data">
        <thead>
          <tr>
            <th>Nombre</th>
            <th>Correo</th>
            <th>Teléfono</th>
            <th>País</th>
            <th>Solicitudes</th>
            <th>Última solicitud</th>
          </tr>
        </thead>
        <tbody>
          @for (row of rows(); track row.id) {
            <tr>
              <td>
                <a [routerLink]="['/sales/customers', row.id]">{{ display(row) }}</a>
              </td>
              <td>{{ row.email || '—' }}</td>
              <td>{{ row.phone_e164 || '—' }}</td>
              <td>{{ row.country_code || '—' }}</td>
              <td>{{ row.request_count }}</td>
              <td>{{ row.last_request_at ? (row.last_request_at | date: 'short') : '—' }}</td>
            </tr>
          }
        </tbody>
      </table>
    </app-data-table>
  `,
})
export class CustomerListComponent {
  private readonly customers = inject(CustomerService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly searchDraft = signal('');
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly rows = signal<CustomerListRow[]>([]);
  protected readonly total = signal(0);
  protected readonly filteredActive = computed(() => hasActiveListFilters(this.query()));
  private appliedQ = '';

  private readonly commitSearch = debounce((value: string) => {
    this.write(withListFilterChange(this.query(), { q: value.trim() }));
  }, LIST_SEARCH_DEBOUNCE_MS);

  constructor() {
    this.destroyRef.onDestroy(() => this.commitSearch.cancel());

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

  protected display(row: CustomerListRow): string {
    return customerDisplayName(row);
  }

  protected onSearch(event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.searchDraft.set(value);
    this.commitSearch(value);
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
      const page = await this.customers.listPage({ q: query.q, page: query.page });
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
