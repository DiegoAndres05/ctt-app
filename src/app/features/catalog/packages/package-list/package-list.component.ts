import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type { PackageConsistency, ProductStatus } from '../../../../core/catalog/models/product.model';
import {
  ProductService,
  type ProductListItem,
} from '../../../../core/catalog/services/product.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

/**
 * Predefined packages in the catalog (User Story 3). Operator/Admin via `roleGuard`; RLS
 * still scopes the rows. Inconsistency from inactive components is a warning only.
 */
@Component({
  selector: 'app-package-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header>
        <div>
          <a routerLink="/catalog">Catálogo</a>
          <h1>Paquetes</h1>
        </div>
        <a routerLink="/catalog/packages/new">Nuevo paquete</a>
      </header>

      @if (loading()) {
        <app-spinner label="Cargando paquetes…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (packages().length === 0) {
        <p>No hay paquetes predefinidos en esta organización.</p>
      } @else {
        @if (hasInconsistent()) {
          <app-alert kind="info">
            Hay paquetes con componentes inactivos. El paquete no se desactiva automáticamente;
            revisa la composición antes de ofrecerlo.
          </app-alert>
        }
        <table>
          <thead>
            <tr>
              <th>Nombre</th>
              <th>Estado</th>
              <th>Consistencia</th>
            </tr>
          </thead>
          <tbody>
            @for (pkg of packages(); track pkg.id) {
              <tr>
                <td>
                  <a [routerLink]="['/catalog/packages', pkg.id]">{{ pkg.name }}</a>
                </td>
                <td>{{ statusLabel(pkg.status) }}</td>
                <td>
                  @if (warningFor(pkg.id); as warning) {
                    Inconsistente: {{ warning }}
                  } @else {
                    Consistente
                  }
                </td>
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
export class PackageListComponent {
  private readonly productsApi = inject(ProductService);

  protected readonly packages = signal<ProductListItem[]>([]);
  protected readonly consistency = signal<Map<string, PackageConsistency>>(new Map());
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);

  constructor() {
    void this.refresh();
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
    return names || 'componentes inactivos';
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

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const [packages, reports] = await Promise.all([
        this.productsApi.listPackages(),
        this.productsApi.getPackageConsistency(),
      ]);
      this.packages.set(packages);
      this.consistency.set(new Map(reports.map((report) => [report.package_id, report])));
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
