import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type { Category } from '../../../../core/catalog/models/category.model';
import type { ProductStatus, ProductType } from '../../../../core/catalog/models/product.model';
import { CategoryService } from '../../../../core/catalog/services/category.service';
import {
  ProductService,
  type ProductListItem,
} from '../../../../core/catalog/services/product.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

/**
 * Internal catalog of experiences and accommodations (User Story 1). Operator/Admin via
 * `roleGuard`; RLS still scopes the rows.
 */
@Component({
  selector: 'app-product-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header>
        <div>
          <a routerLink="/catalog">Catálogo</a>
          <h1>Productos</h1>
        </div>
        <a routerLink="/catalog/products/new">Nuevo producto</a>
      </header>

      <form class="filters" (submit)="onFilter($event)">
        <label for="type-filter">Tipo</label>
        <select id="type-filter" [value]="typeFilter()" (change)="onTypeChange($event)">
          <option value="">Todos</option>
          <option value="experience">Experiencia</option>
          <option value="accommodation">Alojamiento</option>
          <option value="package">Paquete</option>
        </select>

        <label for="status-filter">Estado</label>
        <select id="status-filter" [value]="statusFilter()" (change)="onStatusChange($event)">
          <option value="">Todos</option>
          <option value="draft">Borrador</option>
          <option value="active">Activo</option>
          <option value="inactive">Inactivo</option>
        </select>

        <label for="category-filter">Categoría</label>
        <select id="category-filter" [value]="categoryFilter()" (change)="onCategoryChange($event)">
          <option value="">Todas</option>
          @for (category of categories(); track category.id) {
            <option [value]="category.id">{{ category.name }}</option>
          }
        </select>

        <button type="submit">Filtrar</button>
      </form>

      @if (loading()) {
        <app-spinner label="Cargando productos…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (products().length === 0) {
        <p>No hay productos en el catálogo con esos filtros.</p>
      } @else {
        <table>
          <thead>
            <tr>
              <th>Nombre</th>
              <th>Tipo</th>
              <th>Estado</th>
              <th>Alta</th>
            </tr>
          </thead>
          <tbody>
            @for (product of products(); track product.id) {
              <tr>
                <td>
                  <a [routerLink]="['/catalog/products', product.id]">{{ product.name }}</a>
                </td>
                <td>{{ typeLabel(product.type) }}</td>
                <td>{{ statusLabel(product.status) }}</td>
                <td>{{ product.created_at | date: 'short' }}</td>
              </tr>
            }
          </tbody>
        </table>
      }
    </main>
  `,
  styles: `
    .page {
      padding: 1.5rem;
      display: grid;
      gap: 1rem;
    }

    header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 1rem;
    }

    h1 {
      margin: 0.25rem 0 0;
    }

    .filters {
      display: flex;
      flex-wrap: wrap;
      align-items: end;
      gap: 0.75rem;
    }

    label {
      font-weight: 600;
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    th,
    td {
      text-align: left;
      padding: 0.4rem 0.5rem;
      border-bottom: 1px solid #ddd;
    }
  `,
})
export class ProductListComponent {
  private readonly productsApi = inject(ProductService);
  private readonly categoriesApi = inject(CategoryService);

  protected readonly products = signal<ProductListItem[]>([]);
  protected readonly categories = signal<Category[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);

  protected readonly typeFilter = signal<ProductType | ''>('');
  protected readonly statusFilter = signal<ProductStatus | ''>('');
  protected readonly categoryFilter = signal('');

  constructor() {
    void this.bootstrap();
  }

  protected typeLabel(type: ProductType): string {
    switch (type) {
      case 'experience':
        return 'Experiencia';
      case 'accommodation':
        return 'Alojamiento';
      case 'package':
        return 'Paquete';
    }
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

  protected onFilter(event: Event): void {
    event.preventDefault();
    void this.refresh();
  }

  protected onTypeChange(event: Event): void {
    this.typeFilter.set((event.target as HTMLSelectElement).value as ProductType | '');
  }

  protected onStatusChange(event: Event): void {
    this.statusFilter.set((event.target as HTMLSelectElement).value as ProductStatus | '');
  }

  protected onCategoryChange(event: Event): void {
    this.categoryFilter.set((event.target as HTMLSelectElement).value);
  }

  private async bootstrap(): Promise<void> {
    try {
      this.categories.set(await this.categoriesApi.list());
    } catch (failure) {
      this.error.set(toAppError(failure));
      this.loading.set(false);
      return;
    }
    await this.refresh();
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.products.set(
        await this.productsApi.list({
          type: this.typeFilter() || undefined,
          status: this.statusFilter() || undefined,
          categoryId: this.categoryFilter() || undefined,
        }),
      );
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
