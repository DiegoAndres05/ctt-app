import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import type { Category } from '../../../../core/catalog/models/category.model';
import type { ProductStatus, ProductType } from '../../../../core/catalog/models/product.model';
import { CategoryService } from '../../../../core/catalog/services/category.service';
import {
  ProductService,
  type ProductListPublicStatus,
  type ProductListRow,
} from '../../../../core/catalog/services/product.service';
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

/**
 * Experience or accommodation list. The route data `productType` picks the mode.
 * Agents can open a row; creation stays with operator and admin.
 */
@Component({
  selector: 'app-product-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, DataTableComponent],
  template: `
    <app-data-table
      [title]="title()"
      [loading]="loading()"
      [error]="error()"
      [total]="total()"
      [page]="query().page"
      [filtered]="filteredActive()"
      [emptyMessage]="emptyMessage()"
      [loadingLabel]="loadingLabel()"
      (pageChange)="onPage($event)"
      (clearFilters)="onClear()"
    >
      @if (canCreate()) {
        <a dataTableCreate class="primary button-link" [routerLink]="createLink()">{{
          createLabel()
        }}</a>
      }

      <div dataTableFilters class="filters-bar">
        <label [attr.for]="fieldId('q')">
          Buscar
          <input
            [id]="fieldId('q')"
            type="search"
            [value]="searchDraft()"
            (input)="onSearch($event)"
            placeholder="Nombre"
          />
        </label>
        <label [attr.for]="fieldId('status')">
          Estado del producto
          <select [id]="fieldId('status')" [value]="query().status" (change)="onStatus($event)">
            <option value="">Todos</option>
            <option value="draft">Borrador</option>
            <option value="active">Activo</option>
            <option value="inactive">Inactivo</option>
          </select>
        </label>
        <label [attr.for]="fieldId('public')">
          Estado de la ficha
          <select
            [id]="fieldId('public')"
            [value]="query().publicStatus"
            (change)="onPublicStatus($event)"
          >
            <option value="">Todos</option>
            <option value="none">Sin ficha</option>
            <option value="draft">Borrador</option>
            <option value="published">Publicada</option>
            <option value="unpublished">Despublicada</option>
            <option value="sold_out">Agotada</option>
          </select>
        </label>
        <label [attr.for]="fieldId('category')">
          Categoría
          <select
            [id]="fieldId('category')"
            [value]="query().categoryId"
            (change)="onCategory($event)"
          >
            <option value="">Todas</option>
            @for (category of categories(); track category.id) {
              <option [value]="category.id">{{ category.name }}</option>
            }
          </select>
        </label>
        @if (productType() === 'experience') {
          <label [attr.for]="fieldId('placement')">
            Ubicación pública
            <select
              [id]="fieldId('placement')"
              [value]="query().placement"
              (change)="onPlacement($event)"
            >
              <option value="">Todas</option>
              <option value="catalog">Catálogo</option>
              <option value="yacht">Yates</option>
            </select>
          </label>
        }
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
            @if (productType() === 'experience') {
              <th>Ubicación</th>
            }
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
              <td>
                <a [routerLink]="[detailLink(), row.id]">{{ row.name }}</a>
              </td>
              <td>{{ row.category_names.join(', ') || '—' }}</td>
              <td>{{ statusLabel(row.status) }}</td>
              <td>{{ publicStatusLabel(row.public_status) }}</td>
              <td>{{ priceLabel(row) }}</td>
              @if (productType() === 'experience') {
                <td>{{ placementLabel(row.placement) }}</td>
              }
            </tr>
          }
        </tbody>
      </table>
    </app-data-table>
  `,
})
export class ProductListComponent {
  private readonly productsApi = inject(ProductService);
  private readonly categoriesApi = inject(CategoryService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  readonly productType = input<'experience' | 'accommodation'>('experience');

  private readonly params = toSignal(this.route.queryParamMap, { requireSync: true });
  protected readonly query = computed(() => parseListQuery(this.params()));
  protected readonly searchDraft = signal('');
  protected readonly categories = signal<Category[]>([]);
  protected readonly rows = signal<ProductListRow[]>([]);
  protected readonly total = signal(0);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  private appliedQ = '';
  private request = 0;

  protected readonly filteredActive = computed(() => hasActiveListFilters(this.query()));
  protected readonly title = computed(() =>
    this.productType() === 'accommodation' ? 'Alojamientos' : 'Experiencias',
  );
  protected readonly emptyMessage = computed(() =>
    this.productType() === 'accommodation'
      ? 'No hay alojamientos en el catálogo.'
      : 'No hay experiencias en el catálogo.',
  );
  protected readonly loadingLabel = computed(() =>
    this.productType() === 'accommodation' ? 'Cargando alojamientos…' : 'Cargando experiencias…',
  );
  protected readonly createLabel = computed(() =>
    this.productType() === 'accommodation' ? 'Nuevo alojamiento' : 'Nueva experiencia',
  );

  private readonly commitSearch = debounce((value: string) => {
    this.write(withListFilterChange(this.query(), { q: value.trim() }));
  }, LIST_SEARCH_DEBOUNCE_MS);

  constructor() {
    this.destroyRef.onDestroy(() => this.commitSearch.cancel());
    void this.categoriesApi
      .list()
      .then((rows) => this.categories.set(rows))
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
      const type = this.productType();
      untracked(() => {
        void this.refresh(query, type);
      });
    });
  }

  protected canCreate(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'operator');
  }

  protected createLink(): string {
    return this.productType() === 'accommodation'
      ? '/cms/accommodations/new'
      : '/cms/experiences/new';
  }

  protected detailLink(): string {
    return this.productType() === 'accommodation' ? '/cms/accommodations' : '/cms/experiences';
  }

  protected fieldId(name: string): string {
    return `${this.productType()}-${name}`;
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

  protected placementLabel(placement: ProductListRow['placement']): string {
    if (placement === 'yacht') {
      return 'Yates';
    }
    if (placement === 'catalog') {
      return 'Catálogo';
    }
    return '—';
  }

  protected priceLabel(row: ProductListRow): string {
    if (row.display_price == null || Number.isNaN(row.display_price)) {
      return '—';
    }
    const currency = row.currency || 'COP';
    try {
      return new Intl.NumberFormat('es-CO', {
        style: 'currency',
        currency,
        maximumFractionDigits: 0,
      }).format(row.display_price);
    } catch {
      return `${row.display_price} ${currency}`;
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

  protected onPublicStatus(event: Event): void {
    this.write(
      withListFilterChange(this.query(), {
        publicStatus: (event.target as HTMLSelectElement).value,
      }),
    );
  }

  protected onCategory(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { categoryId: (event.target as HTMLSelectElement).value }),
    );
  }

  protected onPlacement(event: Event): void {
    this.write(
      withListFilterChange(this.query(), { placement: (event.target as HTMLSelectElement).value }),
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

  private async refresh(query: ListQuery, type: ProductType): Promise<void> {
    const request = ++this.request;
    this.loading.set(true);
    this.error.set(null);
    try {
      const page = await this.productsApi.listPage({
        type,
        q: query.q,
        status: (query.status || undefined) as ProductStatus | undefined,
        publicStatus: (query.publicStatus || undefined) as ProductListPublicStatus | undefined,
        placement:
          type === 'experience'
            ? ((query.placement || undefined) as 'catalog' | 'yacht' | undefined)
            : undefined,
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
