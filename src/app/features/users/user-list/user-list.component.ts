import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { UserProfile } from '../../../core/auth/models/user.model';
import { UserService } from '../services/user.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/**
 * Organization roster (User Story 3). Admin-only via `roleGuard`; RLS still scopes the rows.
 */
@Component({
  selector: 'app-user-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header>
        <div>
          <a routerLink="/dashboard">Panel</a>
          <h1>Usuarios</h1>
        </div>
        <a routerLink="/users/new">Nuevo colaborador</a>
      </header>

      @if (loading()) {
        <app-spinner />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (users().length === 0) {
        <p>No hay colaboradores en esta organización.</p>
      } @else {
        <table>
          <thead>
            <tr>
              <th>Nombre</th>
              <th>Correo</th>
              <th>Rol</th>
              <th>Estado</th>
              <th>Última actividad</th>
            </tr>
          </thead>
          <tbody>
            @for (user of users(); track user.id) {
              <tr>
                <td>
                  <a [routerLink]="['/users', user.id]">{{ user.full_name }}</a>
                </td>
                <td>{{ user.email }}</td>
                <td>{{ roleLabel(user.role) }}</td>
                <td>{{ user.status === 'active' ? 'Activo' : 'Inactivo' }}</td>
                <td>{{ user.last_activity_at ? (user.last_activity_at | date: 'short') : '—' }}</td>
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
export class UserListComponent {
  private readonly usersApi = inject(UserService);

  protected readonly users = signal<UserProfile[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);

  constructor() {
    void this.refresh();
  }

  protected roleLabel(role: UserProfile['role']): string {
    switch (role) {
      case 'admin':
        return 'Administrador';
      case 'operator':
        return 'Operador';
      case 'agent':
        return 'Agente';
    }
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.users.set(await this.usersApi.list());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
