import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../core/auth/models/user.model';

interface SettingsLink {
  path: string;
  title: string;
  description: string;
  adminOnly?: boolean;
}

const INTERNAL: readonly SettingsLink[] = [
  {
    path: '/cms/settings/categories',
    title: 'Categorías internas',
    description: 'Clasifican los productos dentro del panel.',
  },
  {
    path: '/cms/settings/addons',
    title: 'Adicionales',
    description: 'Complementos que se suman a una reserva.',
  },
];

const PUBLIC_SITE: readonly SettingsLink[] = [
  {
    path: '/cms/settings/public-profile',
    title: 'Perfil público',
    description: 'Nombre, logo, color, contacto, redes, idiomas y moneda.',
  },
  {
    path: '/cms/settings/public-categories',
    title: 'Categorías públicas',
    description: 'Los filtros con los que el viajero recorre tu catálogo.',
  },
  {
    path: '/cms/settings/public-taxonomies',
    title: 'Tipos y amenidades',
    description: 'Tipos de alojamiento y amenidades que eligen las fichas.',
  },
  {
    path: '/cms/settings/public-key',
    title: 'Clave pública',
    description: 'Conecta tu página web o vitrina con tu catálogo.',
    adminOnly: true,
  },
  {
    path: '/cms/settings/cutover',
    title: 'Publicación del sitio',
    description: 'Migración desde un sitio existente o publicación directa.',
    adminOnly: true,
  },
  {
    path: '/cms/settings/blog-migration',
    title: 'Migración del blog',
    description: 'Copia el blog anterior conservando sus direcciones antes de cambiar de fuente.',
    adminOnly: true,
  },
];

/**
 * CMS settings hub. Admin-only entries are hidden for other roles; their routes keep the guard.
 */
@Component({
  selector: 'app-catalog-settings',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <section class="stack">
      <header class="page-head">
        <h1>Ajustes del catálogo</h1>
      </header>

      <h2>Sitio público</h2>
      <ul class="links">
        @for (link of publicSite(); track link.path) {
          <li>
            <a [routerLink]="link.path">{{ link.title }}</a>
            <span class="hint">{{ link.description }}</span>
          </li>
        }
      </ul>

      <h2>Catálogo interno</h2>
      <ul class="links">
        @for (link of internal; track link.path) {
          <li>
            <a [routerLink]="link.path">{{ link.title }}</a>
            <span class="hint">{{ link.description }}</span>
          </li>
        }
      </ul>
    </section>
  `,
  styles: `
    .stack {
      display: grid;
      gap: 0.75rem;
    }

    h1,
    h2 {
      margin: 0;
    }

    h2 {
      margin-top: 0.5rem;
      font-size: 1rem;
    }

    .links {
      margin: 0;
      padding: 0;
      list-style: none;
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(min(16rem, 100%), 1fr));
      gap: 0.75rem;
    }

    .links li {
      display: grid;
      gap: 0.25rem;
      padding: 0.85rem 1rem;
      border: 1px solid var(--color-border);
      border-radius: 0.75rem;
      background: var(--color-surface);
    }

    .links a {
      font-weight: 600;
    }
  `,
})
export class CatalogSettingsComponent {
  private readonly auth = inject(AuthService);

  protected readonly internal = INTERNAL;
  protected readonly publicSite = computed(() => {
    const isAdmin = hasRoleAtLeast(this.auth.role(), 'admin');
    return PUBLIC_SITE.filter((link) => isAdmin || !link.adminOnly);
  });
}
