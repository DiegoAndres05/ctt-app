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
import type { Category } from '../../../../core/catalog/models/category.model';
import type { PackageConsistency, ProductStatus } from '../../../../core/catalog/models/product.model';
import { CategoryService } from '../../../../core/catalog/services/category.service';
import {
  ProductService,
  type ProductListPublicStatus,
  type ProductListRow,
} from '../../../../core/catalog/services/product.service';
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

/**
 * Predefined packages. Agents open rows in consulta; operators and admins can create.
 * Inactive components stay a warning and never hide the package.
 */
@Component({
  selector: 'app-package-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, AlertComponent, DataTableComponent],
  template: `
    @if (hasInconsistent()) {
      <app-alert kind="info">
        Hay paquetes con componentes inactivos. El paquete no se desactiva automáticamente; revisa
        la composición antes de ofrecerlo.
      </app-alert>
    }

    <app-data-table
      title="Paquetes"
      [loading]="loading()"
      [error]="error()"
      [total]="total()"
      [page]="query().page"
      [filtered]="filteredActive()"
      emptyMessage="No hay paquetes predefinidos en esta organización."
      loadingLabel="Cargando paquetes…"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      @if (canCreate()) {
        <a dataTableCreate class="primary button-link" routerLink="/cms/packages/new">Nuevo paquete</a>
      }

      <div dataTableFilters class="filters-bar">
        <label for="pkg-q">
          Buscar
          <input id="pkg-q" type="search" [value]="searchDraft()" (input)="onSearch($event)" placeholder="Nombre" />
        </label>
        <label for="pkg-status">
          Estado del producto
          <select id="pkg-status" [value]="query().status" (change)="onStatus($event)">
            <option value="">Todos</option>
            <option value="draft">Borrador</option>
            <option value="active">Activo</option>
            <option value="inactive">Inactivo</option>
          </select>
        </label>
        <label for="pkg-public">
          Estado de la ficha
          <select id="pkg-public" [value]="query().publicStatus" (change)="onPublicStatus($event)">
            <option value="">Todos</option>
            <option value="none">Sin ficha</option>
            <option value="draft">Borrador</option>
            <option value="published">Publicada</option>
            <option value="unpublished">Despublicada</option>
            <option value="sold_out">Agotada</option>
          </select>
        </label>
        <label for="pkg-category">
          Categoría
          <select id="pkg-category" [value]="query().categoryId" (change)="onCategory($event)">
            <option value="">Todas</option>
            @for (category of categories(); track category.id) {
              <option [value]="category.id">{{ category.name }}</option>
            }
          </select>
        </label>
      </div>

      <table class="data">
        <thead>
          <tr>
            <th>Foto</th>
            <th>Nombre</th>
            <th>Categoría</th>
            <th>Estado</th>
            <th>Ficha pública</th>
            <th>Precio</th>
            <th>Consistencia</th>
          </tr>
        </thead>
        <tbody>
          @for (row of rows(); track row.id) {
            <tr>
              <td>
                @if (row.cover_thumb) {
                  <img class="thumb" [src]="row.cover_thumb" alt="" />
                } @else {
                  <span class="thumb"></span>
                }
              </td>
              <td><a [routerLink]="['/cms/packages', row.id]">{{ row.name }}</a></td>
              <td>{{ row.category_names.join(', ') || '—' }}</td>
              <td>{{ statusLabel(row.status) }}</td>
              <td>{{ publicStatusLabel(row.public_status) }}</td>
              <td>{{ priceLabel(row) }}</td>
              <td>{{ warningFor(row.id) ?? 'Consistente' }}</td>
            </tr>
          }
        </tbody>
      </table>
    </app-data-table>
  `,
  styles: `
    :host {
      display: grid;
      gap: 0.75rem;
    }
  `,
})
export class PackageListComponent {
  private readonly productsApi = inject(ProductService);
  private readonly categoriesApi = inject(CategoryService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly searchDraft = signal('');
  protected readonly categories = signal<Category[]>([]);
  protected readonly rows = signal<ProductListRow[]>([]);
  protected readonly total = signal(0);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  private readonly consistency = signal<Map<string, PackageConsistency>>(new Map());
  private appliedQ = '';
  private request = 0;

  protected readonly filteredActive = computed(() => hasActiveListFilters(this.query()));

  private readonly commitSearch = debounce((value: string) => {
    this.write(withListFilterChange(this.query(), { q: value.trim() }));
  }, LIST_SEARCH_DEBOUNCE_MS);

  constructor() {
    this.destroyRef.onDestroy(() => this.commitSearch.cancel());
    void this.categoriesApi
      .list()
      .then((rows) => this.categories.set(rows))
      .catch(() => undefined);
    void this.productsApi
      .getPackageConsistency()
      .then((reports) => this.consistency.set(new Map(reports.map((report) => [report.package_id, report]))))
      .catch(() => undefined);

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
        void this.refresh(query);
      });
    });
  }

  protected canCreate(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'operator');
  }

  protected hasInconsistent(): boolean {
    return [...this.consistency().values()].some((entry) => !entry.consistent);
  }

  protected warningFor(packageId: string): string | null {
    const entry = this.consistency().get(packageId);
    if (!entry || entry.consistent) {
      return null;
    }
    const names = entry.inactive_components.map((component) => component.name).join(', ');
    return names ? `Inconsistente: ${names}` : 'Inconsistente';
  }

  protected statusLabel(status: ProductStatus): string {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'active':
        return 'Activo';
      case 'inactive':
        return 'Inactivo';
    }
  }

  protected publicStatusLabel(status: ProductListPublicStatus): string {
    switch (status) {
      case 'none':
        return 'Sin ficha';
      case 'draft':
        return 'Borrador';
      case 'published':
        return 'Publicada';
      case 'unpublished':
        return 'Despublicada';
      case 'sold_out':
        return 'Agotada';
    }
  }

  protected priceLabel(row: ProductListRow): string {
    if (row.display_price == null || Number.isNaN(row.display_price)) {
      return '—';
    }
    return `${row.display_price} ${row.currency ?? ''}`.trim();
  }

  protected onSearch(event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.searchDraft.set(value);
    this.commitSearch(value);
  }

  protected onStatus(event: Event): void {
    this.write(withListFilterChange(this.query(), { status: (event.target as HTMLSelectElement).value }));
  }

  protected onPublicStatus(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { publicStatus: (event.target as HTMLSelectElement).value }),
    );
  }

  protected onCategory(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { categoryId: (event.target as HTMLSelectElement).value }),
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

  private async refresh(query: ListQuery): Promise<void> {
    const request = ++this.request;
    this.loading.set(true);
    this.error.set(null);
    try {
      const page = await this.productsApi.listPage({
        type: 'package',
        q: query.q,
        status: (query.status || undefined) as ProductStatus | undefined,
        publicStatus: (query.publicStatus || undefined) as ProductListPublicStatus | undefined,
        categoryId: query.categoryId || undefined,
        page: query.page,
      });
      if (request !== this.request) {
        return;
      }
      const pages = pageCount(page.total);
      if (page.total > 0 && query.page > pages) {
        this.write({ ...query, page: pages });
        return;
      }
      this.rows.set(page.rows);
      this.total.set(page.total);
    } catch (failure) {
      if (request === this.request) {
        this.error.set(toAppError(failure).message);
      }
    } finally {
      if (request === this.request) {
        this.loading.set(false);
      }
    }
  }
}
