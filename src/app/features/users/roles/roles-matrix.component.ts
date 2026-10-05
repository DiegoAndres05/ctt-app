import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { roleLabel, type AppRole } from '../../../core/auth/models/user.model';
import { toAppError } from '../../../core/error/error-handler';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import { UserService } from '../services/user.service';

interface MatrixRow {
  section: string;
  admin: string;
  operator: string;
  agent: string;
}

const MATRIX: readonly MatrixRow[] = [
  { section: 'Dashboard', admin: 'Consulta', operator: 'Consulta', agent: 'Consulta' },
  {
    section: 'Usuarios, roles y auditoría',
    admin: 'Administra',
    operator: '—',
    agent: '—',
  },
  {
    section: 'Experiencias, alojamientos y paquetes',
    admin: 'Administra',
    operator: 'Edita',
    agent: 'Consulta',
  },
  {
    section: 'Ajustes del catálogo',
    admin: 'Administra',
    operator: 'Edita',
    agent: '—',
  },
  { section: 'Publicación del sitio', admin: 'Administra', operator: '—', agent: '—' },
];

const ROLE_COPY: Readonly<Record<AppRole, string>> = {
  admin: 'Administra la organización, los colaboradores y todo el CMS.',
  operator:
    'Edita el catálogo y las fichas públicas. No administra usuarios ni la publicación del sitio.',
  agent: 'Consulta experiencias, alojamientos y paquetes. No crea ni publica.',
};

/**
 * Read-only picture of the three application roles. Selecting one opens the user list filtered.
 */
@Component({
  selector: 'app-roles-matrix',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <section class="stack">
      <h1>Roles y permisos</h1>
      <p class="notice">
        Consulta de los roles existentes. No se crean roles ni se cambian sus permisos.
      </p>

      @if (loading()) {
        <app-spinner label="Cargando colaboradores…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure }}</app-alert>
      } @else {
        <ul class="roles">
          @for (role of roles; track role) {
            <li>
              <h2>{{ roleLabel(role) }}</h2>
              <p>{{ ROLE_COPY[role] }}</p>
              <p>{{ count(role) }} activos</p>
              <a [routerLink]="['/settings/users']" [queryParams]="{ role }"
                >Ver {{ roleLabel(role) }}</a
              >
            </li>
          }
        </ul>

        <table class="data">
          <thead>
            <tr>
              <th>Sección</th>
              <th>Administrador</th>
              <th>Operador</th>
              <th>Agente</th>
            </tr>
          </thead>
          <tbody>
            @for (row of matrix; track row.section) {
              <tr>
                <td>{{ row.section }}</td>
                <td>{{ row.admin }}</td>
                <td>{{ row.operator }}</td>
                <td>{{ row.agent }}</td>
              </tr>
            }
          </tbody>
        </table>
      }
    </section>
  `,
  styles: `
    .stack {
      display: grid;
      gap: 1rem;
    }

    h1,
    h2 {
      margin: 0;
    }

    .roles {
      list-style: none;
      margin: 0;
      padding: 0;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
      gap: 0.75rem;
    }

    .roles li {
      display: grid;
      gap: 0.35rem;
      padding: 0.9rem;
      background: #fff;
      border: 1px solid #e7e5e4;
      border-radius: 0.5rem;
    }

    p {
      margin: 0;
    }
  `,
})
export class RolesMatrixComponent {
  private readonly usersApi = inject(UserService);

  protected readonly roleLabel = roleLabel;
  protected readonly roles: readonly AppRole[] = ['admin', 'operator', 'agent'];
  protected readonly matrix = MATRIX;
  protected readonly ROLE_COPY = ROLE_COPY;
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  private readonly counts = signal<Readonly<Record<AppRole, number>>>({
    admin: 0,
    operator: 0,
    agent: 0,
  });

  constructor() {
    void this.refresh();
  }

  protected count(role: AppRole): number {
    return this.counts()[role];
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const users = await this.usersApi.list();
      const next = { admin: 0, operator: 0, agent: 0 };
      for (const user of users) {
        if (user.status === 'active') {
          next[user.role] += 1;
        }
      }
      this.counts.set(next);
    } catch (failure) {
      this.error.set(toAppError(failure).message);
    } finally {
      this.loading.set(false);
    }
  }
}
