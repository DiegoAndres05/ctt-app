import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { AuthService } from '../../../core/auth/services/auth.service';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { AppRole, UserProfile, UserStatus } from '../../../core/auth/models/user.model';
import { UserService } from '../services/user.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/**
 * Collaborator detail: role and status changes (User Story 3).
 */
@Component({
  selector: 'app-user-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <a routerLink="/settings/users">← Usuarios</a>

      @if (loading()) {
        <app-spinner />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (profile(); as user) {
        <header class="page-head">
          <h1>{{ user.full_name }}</h1>
          <p class="hint">{{ user.email }}</p>
        </header>

        <section class="card">
          <h2>Datos de la cuenta</h2>
          <dl class="facts">
            <div>
              <dt>Correo</dt>
              <dd>{{ user.email }}</dd>
            </div>
            <div>
              <dt>Alta</dt>
              <dd>{{ user.created_at | date: 'short' }}</dd>
            </div>
            <div>
              <dt>Última actividad</dt>
              <dd>{{ user.last_activity_at ? (user.last_activity_at | date: 'short') : '—' }}</dd>
            </div>
            <div>
              <dt>Cambio de contraseña pendiente</dt>
              <dd>{{ user.must_change_password ? 'Sí' : 'No' }}</dd>
            </div>
          </dl>
        </section>

        @if (isSelf()) {
          <app-alert kind="info">
            No puedes cambiar tu propio rol ni desactivar tu cuenta.
          </app-alert>
        } @else {
          <div class="forms">
            <form class="card" (submit)="onSaveRole($event)" novalidate>
              <h2>Rol</h2>
              <div class="field">
                <label for="role">Rol asignado</label>
                <select id="role" [formField]="roleForm.role">
                  <option value="admin">Administrador</option>
                  <option value="operator">Operador</option>
                  <option value="agent">Agente</option>
                </select>
              </div>
              <div class="form-actions">
                <button class="primary" type="submit" [disabled]="roleForm().submitting()">
                  {{ roleForm().submitting() ? 'Guardando…' : 'Cambiar rol' }}
                </button>
              </div>
            </form>

            <form class="card" (submit)="onSaveStatus($event)" novalidate>
              <h2>Estado</h2>
              <div class="field">
                <label for="status">Estado de la cuenta</label>
                <select id="status" [formField]="statusForm.status">
                  <option value="active">Activo</option>
                  <option value="inactive">Inactivo</option>
                </select>
              </div>
              <div class="form-actions">
                <button class="primary" type="submit" [disabled]="statusForm().submitting()">
                  {{ statusForm().submitting() ? 'Guardando…' : 'Actualizar estado' }}
                </button>
              </div>
            </form>
          </div>
        }

        @if (actionError(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }

        @if (notice(); as message) {
          <app-alert kind="success">{{ message }}</app-alert>
        }
      } @else {
        <p>El colaborador no existe o no pertenece a tu organización.</p>
      }
    </main>
  `,
  styles: `
    .page {
      display: grid;
      gap: 1rem;
      max-width: 52rem;
    }

    h2 {
      margin: 0;
    }

    .card {
      display: grid;
      gap: 0.85rem;
      align-content: start;
    }

    .forms {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(min(18rem, 100%), 1fr));
      gap: 1rem;
    }
  `,
})
export class UserDetailComponent {
  private readonly usersApi = inject(UserService);
  private readonly auth = inject(AuthService);

  /** Bound from the `:id` route param. */
  readonly id = input.required<string>();

  protected readonly profile = signal<UserProfile | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);

  protected readonly roleDraft = signal({ role: 'agent' as AppRole });
  protected readonly statusDraft = signal({ status: 'active' as UserStatus });

  protected readonly roleForm = form(this.roleDraft, (fields) => {
    required(fields.role);
  });

  protected readonly statusForm = form(this.statusDraft, (fields) => {
    required(fields.status);
  });

  constructor() {
    effect(() => {
      const id = this.id();
      untracked(() => {
        void this.refresh(id);
      });
    });
  }

  protected isSelf(): boolean {
    return this.auth.user()?.id === this.id();
  }

  protected async onSaveRole(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.roleForm, async (fields) => {
      try {
        const updated = await this.usersApi.updateRole(this.id(), fields.role().value());
        this.roleDraft.set({ role: updated.role });
        const current = this.profile();
        if (current) {
          this.profile.set({ ...current, role: updated.role, updated_at: updated.updated_at });
        }
        this.notice.set('El rol se actualizó. El cambio rige de inmediato en el servidor.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onSaveStatus(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.statusForm, async (fields) => {
      try {
        const updated = await this.usersApi.toggleStatus(this.id(), fields.status().value());
        this.statusDraft.set({ status: updated.status });
        const current = this.profile();
        if (current) {
          this.profile.set({
            ...current,
            status: updated.status,
            updated_at: updated.updated_at,
          });
        }
        this.notice.set(
          updated.status === 'inactive'
            ? 'La cuenta quedó desactivada. El acceso se corta en la siguiente interacción.'
            : 'La cuenta quedó activa.',
        );
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  private async refresh(id: string): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.actionError.set(null);
    this.notice.set(null);
    try {
      const user = await this.usersApi.getById(id);
      this.profile.set(user);
      if (user) {
        this.roleDraft.set({ role: user.role });
        this.statusDraft.set({ status: user.status });
      }
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
