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
import { AuthService } from '../../../../core/auth/services/auth.service';
import { customerDisplayName } from '../../../../core/customers/models/customer.model';
import {
  RequestService,
  type AssigneeOption,
} from '../../../../core/customers/services/request.service';
import { toAppError } from '../../../../core/error/error-handler';
import {
  PRE_RESERVATION_STATUS_LABELS,
  type PreReservationListRow,
  type PreReservationStatus,
} from '../../../../core/pre-reservations/models/pre-reservation.model';
import { PreReservationService } from '../../../../core/pre-reservations/services/pre-reservation.service';
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

const STATUSES: PreReservationStatus[] = [
  'pending_verification',
  'partially_verified',
  'verified',
  'requires_adjustment',
  'expired',
  'cancelled',
];

/**
 * Pre-reservation inbox (US1). Pre-reservations are always created from a request, so the
 * list has no create button; expired holds are swept by `listPage` before every read.
 */
@Component({
  selector: 'app-pre-reservation-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, DataTableComponent],
  template: `
    <app-data-table
      title="Pre-reservas"
      [loading]="loading()"
      [error]="error()"
      [total]="total()"
      [page]="query().page"
      [filtered]="filteredActive()"
      emptyMessage="Todavía no hay pre-reservas."
      loadingLabel="Cargando pre-reservas…"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      <div dataTableFilters class="filters-bar">
        <label for="pre-res-q">
          Buscar
          <input
            id="pre-res-q"
            type="search"
            [value]="searchDraft()"
            (input)="onSearch($event)"
            placeholder="Referencia, solicitud o cliente"
          />
        </label>
        <label for="pre-res-status">
          Estado
          <select id="pre-res-status" [value]="query().status" (change)="onStatus($event)">
            <option value="">Todos</option>
            @for (status of statuses; track status) {
              <option [value]="status">{{ statusLabel(status) }}</option>
            }
          </select>
        </label>
        <label for="pre-res-assignee">
          Responsable
          <select id="pre-res-assignee" [value]="query().assignee" (change)="onAssignee($event)">
            <option value="">Todas</option>
            <option value="me">Mías</option>
            @for (person of responsibles(); track person.id) {
              <option [value]="person.id">{{ person.full_name }}</option>
            }
          </select>
        </label>
      </div>

      <table class="data">
        <thead>
          <tr>
            <th>Referencia</th>
            <th>Solicitud</th>
            <th>Cliente</th>
            <th>Estado</th>
            <th>Primer servicio</th>
            <th>Verificadas</th>
            <th>Vence</th>
            <th>Responsable</th>
            <th>Creada</th>
          </tr>
        </thead>
        <tbody>
          @for (row of rows(); track row.id) {
            <tr>
              <td>
                <a [routerLink]="['/sales/pre-reservations', row.id]">{{ row.reference }}</a>
              </td>
              <td>
                <a [routerLink]="['/sales/requests', row.request_id]">
                  {{ row.request_reference }}
                </a>
              </td>
              <td>{{ displayName(row) }}</td>
              <td>
                {{ statusLabel(row.status) }}
                @if (row.quote_eligible) {
                  <span> · Lista para cotizar</span>
                }
              </td>
              <td>{{ formatDay(row.first_service_date) }}</td>
              <td>{{ row.available_item_count }}/{{ row.primary_item_count }}</td>
              <td>{{ row.expires_at ? (row.expires_at | date: 'short') : '—' }}</td>
              <td>{{ row.responsible_agent_name || '—' }}</td>
              <td>{{ row.created_at | date: 'short' }}</td>
            </tr>
          }
        </tbody>
      </table>
    </app-data-table>
  `,
})
export class PreReservationListComponent {
  private readonly preReservations = inject(PreReservationService);
  private readonly requests = inject(RequestService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly statuses = STATUSES;
  protected readonly statusLabel = (status: PreReservationStatus) =>
    PRE_RESERVATION_STATUS_LABELS[status];
  protected readonly searchDraft = signal('');
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly rows = signal<PreReservationListRow[]>([]);
  protected readonly total = signal(0);
  protected readonly responsibles = signal<AssigneeOption[]>([]);
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

    void this.loadResponsibles();
  }

  protected displayName(row: PreReservationListRow): string {
    return customerDisplayName({
      first_name: row.customer_first_name,
      last_name: row.customer_last_name,
      is_anonymized: row.customer_is_anonymized,
    });
  }

  protected formatDay(value: string | null): string {
    return formatDay(value);
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

  protected onAssignee(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { assignee: (event.target as HTMLSelectElement).value }),
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
    const responsibleId = query.assignee === 'me' ? (this.auth.user()?.id ?? '') : query.assignee;
    try {
      // `listPage` sweeps expired holds first, so «Expirada» is always fresh (R-004).
      const page = await this.preReservations.listPage({
        q: query.q,
        status: query.status as PreReservationStatus | '',
        responsibleId,
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

  private async loadResponsibles(): Promise<void> {
    try {
      // Operators/admins from listOperators() plus every collaborator (agents included)
      // from the shared inbox directory: any member can end up being the responsible agent.
      const [operators, collaborators] = await Promise.all([
        this.preReservations.listOperators(),
        this.requests.listAssignees(),
      ]);
      const merged = new Map<string, AssigneeOption>();
      for (const person of [...collaborators, ...operators]) {
        merged.set(person.id, person);
      }
      this.responsibles.set(
        [...merged.values()].sort((a, b) => a.full_name.localeCompare(b.full_name)),
      );
    } catch {
      this.responsibles.set([]);
    }
  }
}

function formatDay(value: string | null): string {
  if (!value) {
    return '—';
  }
  const [year, month, day] = value.slice(0, 10).split('-');
  if (!year || !month || !day) {
    return value;
  }
  return `${day}/${month}/${year}`;
}
