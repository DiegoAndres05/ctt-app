import { ChangeDetectionStrategy, Component, inject, input } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../core/auth/models/user.model';
import { AlertComponent } from '../../shared/components/alert/alert.component';

/**
 * Landing screen for an authenticated collaborator.
 *
 * Deliberately minimal: it exists so that User Story 1 has the destination its acceptance
 * scenario calls for ("establece su contexto de identidad y lo redirige a su panel"), and it
 * renders that context so the tenant and role carried by the token are visible. The
 * operational screens arrive with their own user stories (users, audit).
 */
@Component({
  selector: 'app-dashboard',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, AlertComponent],
  template: `
    <main class="dashboard">
      <header>
        <h1>Panel</h1>
        <button type="button" (click)="onSignOut()">Cerrar sesión</button>
      </header>

      @if (denied()) {
        <app-alert kind="error">No tienes permisos para realizar esta acción.</app-alert>
      }

      @if (canManageCatalog()) {
        <nav>
          <a routerLink="/catalog">Catálogo</a>
          @if (canAdminister()) {
            <a routerLink="/users">Usuarios</a>
            <a routerLink="/audit">Auditoría</a>
          }
        </nav>
      }

      @if (auth.user(); as identity) {
        <dl>
          <dt>Colaborador</dt>
          <dd>{{ auth.profile()?.full_name ?? identity.email }}</dd>

          <dt>Rol</dt>
          <dd>{{ identity.role }}</dd>

          <dt>Organización</dt>
          <dd>{{ identity.organizationId }}</dd>
        </dl>
      }
    </main>
  `,
  styles: `
    .dashboard {
      padding: 1.5rem;
    }

    header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 1rem;
    }

    dl {
      display: grid;
      grid-template-columns: auto 1fr;
      gap: 0.25rem 1rem;
    }

    dt {
      font-weight: 600;
    }

    dd {
      margin: 0;
    }

    nav {
      display: flex;
      gap: 1rem;
    }
  `,
})
export class DashboardComponent {
  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  /** Set by `roleGuard` when a navigation was refused for lack of privileges. */
  readonly denied = input<string | undefined>(undefined);

  protected canAdminister(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'admin');
  }

  protected canManageCatalog(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'operator');
  }

  protected async onSignOut(): Promise<void> {
    await this.auth.signOut();
    await this.router.navigateByUrl('/login');
  }
}
