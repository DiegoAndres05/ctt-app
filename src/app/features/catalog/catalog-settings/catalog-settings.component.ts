import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../core/auth/models/user.model';

/**
 * CMS settings hub. Publicación del sitio stays admin-only; the route guard still applies.
 */
@Component({
  selector: 'app-catalog-settings',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <section class="stack">
      <h1>Ajustes del catálogo</h1>
      <p class="notice">
        Categorías operativas, categorías públicas, adicionales y la publicación del sitio.
      </p>
      <ul>
        <li><a routerLink="/cms/settings/categories">Categorías</a></li>
        <li><a routerLink="/cms/settings/public-categories">Categorías públicas</a></li>
        <li><a routerLink="/cms/settings/addons">Adicionales</a></li>
        @if (canPublishSite()) {
          <li><a routerLink="/cms/settings/cutover">Publicación del sitio</a></li>
        }
      </ul>
    </section>
  `,
  styles: `
    .stack {
      display: grid;
      gap: 0.75rem;
    }

    h1 {
      margin: 0;
    }

    ul {
      margin: 0;
      padding-left: 1.1rem;
      display: grid;
      gap: 0.4rem;
    }
  `,
})
export class CatalogSettingsComponent {
  private readonly auth = inject(AuthService);

  protected canPublishSite(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'admin');
  }
}
