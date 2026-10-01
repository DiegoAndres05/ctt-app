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
import { roleLabel, type AppRole, type UserStatus } from '../../../core/auth/models/user.model';
import { toAppError } from '../../../core/error/error-handler';
import { DataTableComponent } from '../../../shared/components/data-table/data-table.component';
import {
  LIST_SEARCH_DEBOUNCE_MS,
  debounce,
  emptyListQuery,
  hasActiveListFilters,
  listQueryToParams,
  pageCount,
  pageSlice,
  parseListQuery,
  withListFilterChange,
  type ListQuery,
} from '../../../shared/components/data-table/list-query';
import { UserService, type UserListRow } from '../services/user.service';

/**
 * Organization roster. Admin-only via `roleGuard`; last access comes from `login_success`.
 */
@Component({
  selector: 'app-user-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, DataTableComponent],
  template: `
    <app-data-table
      title="Usuarios"
      [loading]="loading()"
      [error]="error()"
      [total]="filtered().length"
      [page]="query().page"
      [filtered]="filteredActive()"
      emptyMessage="No hay colaboradores en esta organización."
      loadingLabel="Cargando usuarios…"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      <a dataTableCreate class="primary button-link" routerLink="/settings/users/new">Nuevo usuario</a>

      <div dataTableFilters class="filters-bar">
        <label for="user-q">
          Buscar
          <input
            id="user-q"
            type="search"
            [value]="searchDraft()"
            (input)="onSearch($event)"
            placeholder="Nombre o correo"
          />
        </label>
        <label for="user-role">
          Rol
          <select id="user-role" [value]="query().role" (change)="onRole($event)">
            <option value="">Todos</option>
            <option value="admin">Administrador</option>
            <option value="operator">Operador</option>
            <option value="agent">Agente</option>
          </select>
        </label>
        <label for="user-status">
          Estado
          <select id="user-status" [value]="query().status" (change)="onStatus($event)">
            <option value="">Todos</option>
            <option value="active">Activo</option>
            <option value="inactive">Inactivo</option>
          </select>
        </label>
      </div>

      <table class="data">
        <thead>
          <tr>
            <th>Nombre</th>
            <th>Correo</th>
            <th>Rol</th>
            <th>Estado</th>
            <th>Último acceso</th>
          </tr>
        </thead>
        <tbody>
          @for (user of pageRows(); track user.id) {
            <tr>
              <td>
                <a [routerLink]="['/settings/users', user.id]">{{ user.full_name }}</a>
              </td>
              <td>{{ user.email }}</td>
              <td>{{ roleLabel(user.role) }}</td>
              <td>
                {{ user.status === 'active' ? 'Activo' : 'Inactivo' }}
                @if (user.must_change_password) {
                  · cambio de contraseña pendiente
                }
              </td>
              <td>{{ user.last_access_at ? (user.last_access_at | date: 'short') : '—' }}</td>
            </tr>
          }
        </tbody>
      </table>
    </app-data-table>
  `,
})
export class UserListComponent {
  private readonly usersApi = inject(UserService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly roleLabel = roleLabel;
  protected readonly searchDraft = signal('');
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  private readonly rows = signal<UserListRow[]>([]);
  private appliedQ = '';

  protected readonly filtered = computed(() => filterUsers(this.rows(), this.query()));
  protected readonly pageRows = computed(() => pageSlice(this.filtered(), this.query().page));
  protected readonly filteredActive = computed(() => hasActiveListFilters(this.query()));

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
      const total = this.filtered().length;
      const pages = pageCount(total);
      if (!this.loading() && total > 0 && query.page > pages) {
        untracked(() => this.write({ ...query, page: pages }));
      }
    });

    void this.refresh();
  }

  protected onSearch(event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.searchDraft.set(value);
    this.commitSearch(value);
  }

  protected onRole(event: Event): void {
    const role = (event.target as HTMLSelectElement).value;
    this.write(withListFilterChange(this.query(), { role }));
  }

  protected onStatus(event: Event): void {
    const status = (event.target as HTMLSelectElement).value;
    this.write(withListFilterChange(this.query(), { status }));
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

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.rows.set(await this.usersApi.listWithLastAccess());
    } catch (failure) {
      this.error.set(toAppError(failure).message);
    } finally {
      this.loading.set(false);
    }
  }
}

function filterUsers(rows: readonly UserListRow[], query: ListQuery): UserListRow[] {
  const q = query.q.trim().toLowerCase();
  return rows.filter((row) => {
    if (q && !row.full_name.toLowerCase().includes(q) && !row.email.toLowerCase().includes(q)) {
      return false;
    }
    if (query.role && row.role !== (query.role as AppRole)) {
      return false;
    }
    if (query.status && row.status !== (query.status as UserStatus)) {
      return false;
    }
    return true;
  });
}
