import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/**
 * Catalog landing shell (Operator/Admin). Child screens for products, packages, add-ons and
 * pricing attach to `/catalog` in later stories; this route exists so navigation and the
 * role guard have a destination from day one.
 */
@Component({
  selector: 'app-catalog-shell',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <main class="page">
      <header>
        <div>
          <a routerLink="/dashboard">Panel</a>
          <h1>Catálogo</h1>
        </div>
      </header>

      <p>Gestión de productos turísticos, complementos y precios.</p>

      <nav>
        <a routerLink="/catalog/products">Productos</a>
        <a routerLink="/catalog/packages">Paquetes</a>
        <a routerLink="/catalog/addons">Complementos</a>
        <a routerLink="/catalog/public-categories">Categorías públicas</a>
        <a routerLink="/catalog/public-cutover">Cambio de fuente</a>
      </nav>
    </main>
  `,
  styles: `
    .page {
      padding: 1.5rem;
    }

    header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 1rem;
    }

    nav {
      display: flex;
      gap: 1rem;
    }
  `,
})
export class CatalogShellComponent {}
