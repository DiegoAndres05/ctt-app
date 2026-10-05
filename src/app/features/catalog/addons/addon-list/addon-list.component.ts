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
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import type { Addon, AddonUnit } from '../../../../core/catalog/models/addon.model';
import { AddonService } from '../../../../core/catalog/services/addon.service';
import { toAppError } from '../../../../core/error/error-handler';
import { DataTableComponent } from '../../../../shared/components/data-table/data-table.component';
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
} from '../../../../shared/components/data-table/list-query';

/**
 * Independent add-ons. Operator/Admin via the settings route; the list still hides
 * creation when the session is below operator.
 */
@Component({
  selector: 'app-addon-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, DataTableComponent],
  template: `
    <app-data-table
      title="Adicionales"
      [loading]="loading()"
      [error]="error()"
      [total]="filtered().length"
      [page]="query().page"
      [filtered]="filteredActive()"
      emptyMessage="No hay adicionales en esta organización."
      loadingLabel="Cargando adicionales…"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      @if (canCreate()) {
        <a dataTableCreate class="primary button-link" routerLink="/cms/settings/addons/new">
          Nuevo adicional
        </a>
      }

      <div dataTableFilters class="filters-bar">
        <label for="addon-q">
          Buscar
          <input
            id="addon-q"
            type="search"
            [value]="searchDraft()"
            (input)="onSearch($event)"
            placeholder="Nombre"
          />
        </label>
        <label for="addon-status">
          Estado
          <select id="addon-status" [value]="query().status" (change)="onStatus($event)">
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
            <th>Unidad</th>
            <th>Estado</th>
          </tr>
        </thead>
        <tbody>
          @for (addon of pageRows(); track addon.id) {
            <tr>
              <td>
                <a [routerLink]="['/cms/settings/addons', addon.id]">{{ addon.name }}</a>
              </td>
              <td>{{ unitLabel(addon.unit) }}</td>
              <td>{{ addon.is_active ? 'Activo' : 'Inactivo' }}</td>
            </tr>
          }
        </tbody>
      </table>
    </app-data-table>
  `,
})
export class AddonListComponent {
  private readonly addonsApi = inject(AddonService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly searchDraft = signal('');
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  private readonly addons = signal<Addon[]>([]);
  private appliedQ = '';

  protected readonly filtered = computed(() => {
    const query = this.query();
    const q = query.q.trim().toLowerCase();
    return this.addons().filter((addon) => {
      if (q && !addon.name.toLowerCase().includes(q)) {
        return false;
      }
      if (query.status === 'active' && !addon.is_active) {
        return false;
      }
      if (query.status === 'inactive' && addon.is_active) {
        return false;
      }
      return true;
    });
  });
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
      if (!this.loading() && total > 0 && query.page > pageCount(total)) {
        untracked(() => this.write({ ...query, page: pageCount(total) }));
      }
    });
    void this.refresh();
  }

  protected canCreate(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'operator');
  }

  protected unitLabel(unit: AddonUnit): string {
    switch (unit) {
      case 'per_person':
        return 'Por persona';
      case 'per_unit':
        return 'Por unidad';
      case 'per_service':
        return 'Por servicio';
    }
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
    void this.router.navigate([], { relativeTo: this.route, queryParams: listQueryToParams(next) });
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.addons.set(await this.addonsApi.list());
    } catch (failure) {
      this.error.set(toAppError(failure).message);
    } finally {
      this.loading.set(false);
    }
  }
}
