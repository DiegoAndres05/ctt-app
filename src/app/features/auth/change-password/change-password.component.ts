import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { form, FormField, minLength, required, submit, validate } from '@angular/forms/signals';
import { AuthService } from '../../../core/auth/services/auth.service';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import { AlertComponent } from '../../../shared/components/alert/alert.component';

/** Matches the minimum the `change_password` function enforces (migration 008). */
const MIN_PASSWORD_LENGTH = 8;

/**
 * Password rotation screen (User Story 1).
 *
 * Reached voluntarily, or compulsorily via `passwordChangeGuard` while the collaborator still
 * holds the temporary password an administrator assigned. The rules below mirror what
 * `change_password` enforces so the user finds out about a problem before a round trip; the
 * database check is the one that decides.
 */
@Component({
  selector: 'app-change-password',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, AlertComponent],
  template: `
    <main class="auth-page">
      <form class="auth-card" (submit)="onSubmit($event)" novalidate>
        <h1>Cambiar contraseña</h1>

        @if (auth.mustChangePassword()) {
          <app-alert kind="info">
            Tu contraseña es temporal. Debes cambiarla antes de continuar.
          </app-alert>
        }

        <label for="current-password">Contraseña actual</label>
        <input
          id="current-password"
          type="password"
          autocomplete="current-password"
          [formField]="passwordForm.currentPassword"
        />
        @if (passwordForm.currentPassword().touched() && passwordForm.currentPassword().invalid()) {
          <p class="field-error">Ingresa tu contraseña actual.</p>
        }

        <label for="new-password">Nueva contraseña</label>
        <input
          id="new-password"
          type="password"
          autocomplete="new-password"
          [formField]="passwordForm.newPassword"
        />
        @if (passwordForm.newPassword().touched()) {
          @for (failure of passwordForm.newPassword().errors(); track failure.kind) {
            <p class="field-error">{{ failure.message }}</p>
          }
        }

        <label for="confirm-password">Repite la nueva contraseña</label>
        <input
          id="confirm-password"
          type="password"
          autocomplete="new-password"
          [formField]="passwordForm.confirmPassword"
        />
        @if (passwordForm.confirmPassword().touched()) {
          @for (failure of passwordForm.confirmPassword().errors(); track failure.kind) {
            <p class="field-error">{{ failure.message }}</p>
          }
        }

        <button type="submit" [disabled]="passwordForm().submitting()">
          {{ passwordForm().submitting() ? 'Guardando…' : 'Cambiar contraseña' }}
        </button>

        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }
      </form>
    </main>
  `,
  styles: `
    .auth-page {
      display: grid;
      place-items: center;
      min-height: 100vh;
      padding: 1.5rem;
    }

    .auth-card {
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
export class ChangePasswordComponent {
  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly passwords = signal({
    currentPassword: '',
    newPassword: '',
    confirmPassword: '',
  });

  protected readonly passwordForm = form(this.passwords, (passwords) => {
    required(passwords.currentPassword, { message: 'Ingresa tu contraseña actual.' });

    required(passwords.newPassword, { message: 'Ingresa una nueva contraseña.' });
    minLength(passwords.newPassword, MIN_PASSWORD_LENGTH, {
      message: `La nueva contraseña debe tener al menos ${MIN_PASSWORD_LENGTH} caracteres.`,
    });
    // The temporary password has to actually be retired, not re-submitted.
    validate(passwords.newPassword, ({ value, valueOf }) =>
      value() !== '' && value() === valueOf(passwords.currentPassword)
        ? { kind: 'unchanged', message: 'La nueva contraseña debe ser distinta de la actual.' }
        : undefined,
    );

    validate(passwords.confirmPassword, ({ value, valueOf }) =>
      value() !== valueOf(passwords.newPassword)
        ? { kind: 'mismatch', message: 'Las contraseñas no coinciden.' }
        : undefined,
    );
  });

  protected readonly error = signal<AppError | null>(null);

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);

    await submit(this.passwordForm, async (passwords) => {
      try {
        await this.auth.changePassword(
          passwords.currentPassword().value(),
          passwords.newPassword().value(),
        );
      } catch (failure) {
        this.error.set(toAppError(failure));
        return undefined;
      }

      // Nothing typed here should outlive the submission.
      this.passwords.set({ currentPassword: '', newPassword: '', confirmPassword: '' });
      await this.router.navigateByUrl('/dashboard');
      return undefined;
    });
  }
}
