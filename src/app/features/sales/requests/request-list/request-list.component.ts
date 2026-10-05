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
  REQUEST_CHANNEL_LABELS,
  REQUEST_STATUS_LABELS,
  type RequestChannel,
  type RequestListRow,
  type RequestStatus,
} from '../../../../core/customers/models/request.model';
import { RequestRealtimeService } from '../../../../core/customers/services/request-realtime.service';
import {
  RequestService,
  type AssigneeOption,
} from '../../../../core/customers/services/request.service';
import { toAppError } from '../../../../core/error/error-handler';
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

const STATUSES: RequestStatus[] = ['received', 'in_review', 'discarded', 'pre_reservation'];
const CHANNELS: RequestChannel[] = ['web', 'whatsapp', 'phone', 'in_person'];

@Component({
  selector: 'app-request-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, DataTableComponent, AlertComponent],
  template: `
    @if (notice()) {
      <app-alert kind="info">Llegó una solicitud nueva.</app-alert>
    }

    <app-data-table
      title="Solicitudes"
      [loading]="loading()"
      [error]="error()"
      [total]="total()"
      [page]="query().page"
      [filtered]="filteredActive()"
      emptyMessage="Todavía no hay solicitudes."
      loadingLabel="Cargando solicitudes…"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      <a dataTableCreate class="primary button-link" routerLink="/sales/requests/new">
        Nueva solicitud
      </a>

      <div dataTableFilters class="filters-bar">
        <label for="request-q">
          Buscar
          <input
            id="request-q"
            type="search"
            [value]="searchDraft()"
            (input)="onSearch($event)"
            placeholder="Referencia, nombre, correo o teléfono"
          />
        </label>
        <label for="request-status">
          Estado
          <select id="request-status" [value]="query().status" (change)="onStatus($event)">
            <option value="">Todos</option>
            @for (status of statuses; track status) {
              <option [value]="status">{{ statusLabel(status) }}</option>
            }
          </select>
        </label>
        <label for="request-channel">
          Canal
          <select id="request-channel" [value]="query().channel" (change)="onChannel($event)">
            <option value="">Todos</option>
            @for (channel of channels; track channel) {
              <option [value]="channel">{{ channelLabel(channel) }}</option>
            }
          </select>
        </label>
        <label for="request-assignee">
          Responsable
          <select id="request-assignee" [value]="query().assignee" (change)="onAssignee($event)">
            <option value="">Todos</option>
            <option value="me">Mías</option>
            <option value="none">Sin asignar</option>
            @for (person of assignees(); track person.id) {
              <option [value]="person.id">{{ person.full_name }}</option>
            }
          </select>
        </label>
      </div>

      <table class="data">
        <thead>
          <tr>
            <th>Referencia</th>
            <th>Cliente</th>
            <th>Canal</th>
            <th>Estado</th>
            <th>Fechas de viaje</th>
            <th>Viajeros</th>
            <th>Responsable</th>
            <th>Recibida</th>
          </tr>
        </thead>
        <tbody>
          @for (row of rows(); track row.id) {
            <tr>
              <td>
                <a [routerLink]="['/sales/requests', row.id]">{{ row.reference }}</a>
              </td>
              <td>{{ displayName(row) }}</td>
              <td>{{ channelLabel(row.channel) }}</td>
              <td>
                {{ statusLabel(row.status) }}
                @if (row.contact_review_required) {
                  <span> · Datos a revisar</span>
                }
              </td>
              <td>{{ travelDates(row) }}</td>
              <td>{{ travelers(row) }}</td>
              <td>{{ row.assignee_name || '—' }}</td>
              <td>{{ row.created_at | date: 'short' }}</td>
            </tr>
          }
        </tbody>
      </table>
    </app-data-table>
  `,
})
export class RequestListComponent {
  private readonly requests = inject(RequestService);
  private readonly realtime = inject(RequestRealtimeService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly statuses = STATUSES;
  protected readonly channels = CHANNELS;
  protected readonly statusLabel = (status: RequestStatus) => REQUEST_STATUS_LABELS[status];
  protected readonly channelLabel = (channel: RequestChannel) => REQUEST_CHANNEL_LABELS[channel];
  protected readonly searchDraft = signal('');
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly rows = signal<RequestListRow[]>([]);
  protected readonly total = signal(0);
  protected readonly assignees = signal<AssigneeOption[]>([]);
  protected readonly notice = signal(false);
  protected readonly filteredActive = computed(() => hasActiveListFilters(this.query()));
  private appliedQ = '';
  private noticeTimer: ReturnType<typeof setTimeout> | undefined;

  private readonly commitSearch = debounce((value: string) => {
    this.write(withListFilterChange(this.query(), { q: value.trim() }));
  }, LIST_SEARCH_DEBOUNCE_MS);

  constructor() {
    this.destroyRef.onDestroy(() => {
      this.commitSearch.cancel();
      if (this.noticeTimer) {
        clearTimeout(this.noticeTimer);
      }
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

    void this.loadAssignees();

    const organizationId = this.auth.organizationId();
    if (organizationId) {
      const stop = this.realtime.watchNewRequests(organizationId, () => {
        this.notice.set(true);
        if (this.noticeTimer) {
          clearTimeout(this.noticeTimer);
        }
        this.noticeTimer = setTimeout(() => this.notice.set(false), 5000);
        void this.load(this.query());
      });
      this.destroyRef.onDestroy(stop);
    }
  }

  protected displayName(row: RequestListRow): string {
    return customerDisplayName({
      first_name: row.customer_first_name,
      last_name: row.customer_last_name,
      is_anonymized: row.customer_is_anonymized,
    });
  }

  protected travelDates(row: RequestListRow): string {
    const start = formatDay(row.travel_start_date);
    const end = formatDay(row.travel_end_date);
    if (start === '—' && end === '—') {
      return '—';
    }
    if (end === '—') {
      return start;
    }
    if (start === '—') {
      return end;
    }
    return `${start} – ${end}`;
  }

  protected travelers(row: RequestListRow): string {
    const adults = `${row.adults} adultos`;
    return row.children > 0 ? `${adults}, ${row.children} niños` : adults;
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

  protected onChannel(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { channel: (event.target as HTMLSelectElement).value }),
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
    const assignee = query.assignee === 'me' ? (this.auth.user()?.id ?? '') : query.assignee;
    try {
      const page = await this.requests.listPage({
        q: query.q,
        status: query.status as RequestStatus | '',
        channel: query.channel as RequestChannel | '',
        assignee,
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

  private async loadAssignees(): Promise<void> {
    try {
      this.assignees.set(await this.requests.listAssignees());
    } catch {
      this.assignees.set([]);
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
