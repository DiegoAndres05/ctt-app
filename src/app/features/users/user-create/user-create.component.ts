import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { email, form, FormField, minLength, required, submit } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { AppRole } from '../../../core/auth/models/user.model';
import { UserService } from '../services/user.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import type { UnsavedChangesHost } from '../../../shared/components/unsaved-changes.guard';

const MIN_PASSWORD_LENGTH = 8;

/**
 * Invite a collaborator with a temporary password (User Story 3, FR-006).
 */
@Component({
  selector: 'app-user-create',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent],
  template: `
    <main class="page">
      <a routerLink="/settings/users">Cancelar</a>
      <form class="card" (submit)="onSubmit($event)" novalidate>
        <h1>Nuevo colaborador</h1>
        <p class="notice">
          Recibirá una contraseña temporal y deberá cambiarla en su primer inicio de sesión.
        </p>

        <label for="full-name">Nombre completo</label>
        <input id="full-name" type="text" autocomplete="name" [formField]="createForm.fullName" />
        @if (createForm.fullName().touched() && createForm.fullName().invalid()) {
          <p class="field-error">Ingresa el nombre completo.</p>
        }

        <label for="email">Correo corporativo</label>
        <input id="email" type="email" autocomplete="email" [formField]="createForm.email" />
        @if (createForm.email().touched() && createForm.email().invalid()) {
          <p class="field-error">Ingresa un correo electrónico válido.</p>
        }

        <label for="role">Rol</label>
        <select id="role" [formField]="createForm.role">
          <option value="operator">Operador</option>
          <option value="agent">Agente</option>
        </select>

        <label for="temporary-password">Contraseña temporal</label>
        <input
          id="temporary-password"
          type="password"
          autocomplete="new-password"
          [formField]="createForm.temporaryPassword"
        />
        @if (createForm.temporaryPassword().touched() && createForm.temporaryPassword().invalid()) {
          <p class="field-error">La contraseña temporal debe tener al menos 8 caracteres.</p>
        }

        <button type="submit" [disabled]="createForm().submitting()">
          {{ createForm().submitting() ? 'Creando…' : 'Crear colaborador' }}
        </button>

        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }
      </form>
    </main>
  `,
  styles: `
    .page {
      padding: 1.5rem;
      display: grid;
      gap: 1rem;
      justify-items: start;
    }

    .card {
      display: grid;
      gap: 0.5rem;
      width: min(24rem, 100%);
    }

    label {
      font-weight: 600;
    }

    .field-error {
      color: #b3261e;
      margin: 0;
    }

    .notice {
      margin: 0;
    }

    button {
      margin-top: 0.75rem;
      padding: 0.6rem 1rem;
    }
  `,
})
export class UserCreateComponent implements UnsavedChangesHost {
  private readonly usersApi = inject(UserService);
  private readonly router = inject(Router);

  protected readonly draft = signal({
    fullName: '',
    email: '',
    role: 'agent' as Exclude<AppRole, 'admin'>,
    temporaryPassword: '',
  });

  protected readonly createForm = form(this.draft, (fields) => {
    required(fields.fullName);
    required(fields.email);
    email(fields.email);
    required(fields.role);
    required(fields.temporaryPassword);
    minLength(fields.temporaryPassword, MIN_PASSWORD_LENGTH);
  });

  protected readonly error = signal<AppError | null>(null);

  hasUnsavedChanges(): boolean {
    const draft = this.draft();
    return Boolean(draft.fullName.trim() || draft.email.trim() || draft.temporaryPassword);
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);

    await submit(this.createForm, async (fields) => {
      try {
        const created = await this.usersApi.create({
          fullName: fields.fullName().value(),
          email: fields.email().value(),
          role: fields.role().value(),
          temporaryPassword: fields.temporaryPassword().value(),
        });
        this.draft.set({ fullName: '', email: '', role: 'agent', temporaryPassword: '' });
        await this.router.navigate(['/settings/users', created.id]);
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }
}
