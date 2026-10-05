import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AuthService } from '../../core/auth/services/auth.service';

/**
 * Post-login home. Indicators belong to a later feature; this screen only greets
 * the collaborator and does not repeat the sidebar.
 */
@Component({
  selector: 'app-dashboard',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="dashboard">
      <h1>Hola, {{ name() }}</h1>
      <p>
        Este es tu panel. Los indicadores de la operación llegarán más adelante; mientras tanto usa
        el menú lateral para entrar a cada sección.
      </p>
    </section>
  `,
  styles: `
    .dashboard {
      display: grid;
      gap: 0.5rem;
      max-width: 40rem;
    }

    h1 {
      margin: 0;
    }

    p {
      margin: 0;
      color: #44403c;
    }
  `,
})
export class DashboardComponent {
  private readonly auth = inject(AuthService);

  protected name(): string {
    return this.auth.profile()?.full_name || this.auth.user()?.email || 'colaborador';
  }
}
