import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import {
  email,
  form,
  FormField,
  minLength,
  required,
  submit,
  validate,
} from '@angular/forms/signals';
import { AuthService } from '../../../core/auth/services/auth.service';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

const MIN_PASSWORD_LENGTH = 8;
const MAX_TEXT_LENGTH = 255;

/**
 * Public agency onboarding (User Story 5, FR-008).
 *
 * Creates the tenant and its founding administrator through the `register-agency` Edge
 * Function. The form only checks shape; uniqueness of email and slug is decided on the server
 * and surfaced as `EMAIL_ALREADY_EXISTS` / `AGENCY_SLUG_EXISTS`.
 */
@Component({
  selector: 'app-register',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="auth-page">
      <form class="auth-card" (submit)="onSubmit($event)" novalidate>
        <h1>Registrar mi agencia</h1>
        <p class="notice">
          Crea tu organización y entra como administrador. No hace falta una invitación.
        </p>

        <label for="agency-name">Nombre comercial de la agencia</label>
        <input
          id="agency-name"
          type="text"
          autocomplete="organization"
          [formField]="registerForm.agencyName"
        />
        @if (registerForm.agencyName().touched() && registerForm.agencyName().invalid()) {
          <p class="field-error">
            Ingresa el nombre comercial de la agencia (máximo 255 caracteres).
          </p>
        }

        <label for="full-name">Nombre completo</label>
        <input id="full-name" type="text" autocomplete="name" [formField]="registerForm.fullName" />
        @if (registerForm.fullName().touched() && registerForm.fullName().invalid()) {
          <p class="field-error">Ingresa tu nombre completo.</p>
        }

        <label for="email">Correo corporativo</label>
        <input id="email" type="email" autocomplete="username" [formField]="registerForm.email" />
        @if (registerForm.email().touched() && registerForm.email().invalid()) {
          <p class="field-error">Ingresa un correo electrónico válido.</p>
        }

        <label for="password">Contraseña</label>
        <input
          id="password"
          type="password"
          autocomplete="new-password"
          [formField]="registerForm.password"
        />
        @if (registerForm.password().touched() && registerForm.password().invalid()) {
          <p class="field-error">La contraseña debe tener al menos 8 caracteres.</p>
        }

        <button type="submit" [disabled]="registerForm().submitting()">
          {{ registerForm().submitting() ? 'Creando agencia…' : 'Registrar agencia' }}
        </button>

        @if (registerForm().submitting()) {
          <app-spinner label="Creando organización y administrador…" />
        }

        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }

        <p class="notice">¿Ya tienes cuenta? <a routerLink="/login">Iniciar sesión</a></p>
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
export class RegisterComponent {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly draft = signal({
    agencyName: '',
    fullName: '',
    email: '',
    password: '',
  });

  protected readonly registerForm = form(this.draft, (fields) => {
    required(fields.agencyName);
    validate(fields.agencyName, ({ value }) =>
      value().trim().length > MAX_TEXT_LENGTH ? { kind: 'maxlength' } : undefined,
    );
    required(fields.fullName);
    validate(fields.fullName, ({ value }) =>
      value().trim().length > MAX_TEXT_LENGTH ? { kind: 'maxlength' } : undefined,
    );
    required(fields.email);
    email(fields.email);
    required(fields.password);
    minLength(fields.password, MIN_PASSWORD_LENGTH);
  });

  protected readonly error = signal<AppError | null>(null);

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);

    await submit(this.registerForm, async (fields) => {
      try {
        await this.auth.registerAgency({
          agencyName: fields.agencyName().value(),
          fullName: fields.fullName().value(),
          email: fields.email().value(),
          password: fields.password().value(),
        });
      } catch (failure) {
        this.error.set(toAppError(failure));
        return undefined;
      }

      this.draft.set({ agencyName: '', fullName: '', email: '', password: '' });
      await this.router.navigateByUrl('/dashboard');
      return undefined;
    });
  }
}
