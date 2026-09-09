import { ChangeDetectionStrategy, Component, inject, input, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { email, form, FormField, required, submit } from '@angular/forms/signals';
import { AuthService } from '../../../core/auth/services/auth.service';
import type { LoginRedirectReason } from '../../../core/auth/guards/auth.guard';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/** Explanations for a navigation that `authGuard` turned away. */
const REDIRECT_MESSAGES: Readonly<Record<LoginRedirectReason, string>> = {
  expired:
    'Tu sesión expiró por inactividad o alcanzó su duración máxima. Vuelve a iniciar sesión.',
  'missing-tenant': 'Tu sesión no tiene una organización asociada. Vuelve a iniciar sesión.',
};

/**
 * Sign-in screen (User Story 1).
 *
 * The form validates shape only — a missing address, a malformed one, an empty password. It
 * says nothing about whether an account exists, and the failure message is whatever
 * `toAppError` produced, which collapses every credential problem into one wording.
 */
@Component({
  selector: 'app-login',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="auth-page">
      <form class="auth-card" (submit)="onSubmit($event)" novalidate>
        <h1>Iniciar sesión</h1>

        @if (redirectMessage(); as notice) {
          <app-alert kind="info">{{ notice }}</app-alert>
        }

        <label for="email">Correo corporativo</label>
        <input id="email" type="email" autocomplete="username" [formField]="loginForm.email" />
        @if (loginForm.email().touched() && loginForm.email().invalid()) {
          <p class="field-error">Ingresa un correo electrónico válido.</p>
        }

        <label for="password">Contraseña</label>
        <input
          id="password"
          type="password"
          autocomplete="current-password"
          [formField]="loginForm.password"
        />
        @if (loginForm.password().touched() && loginForm.password().invalid()) {
          <p class="field-error">Ingresa tu contraseña.</p>
        }

        <button type="submit" [disabled]="loginForm().submitting()">
          {{ loginForm().submitting() ? 'Verificando…' : 'Entrar' }}
        </button>

        @if (loginForm().submitting()) {
          <app-spinner label="Verificando credenciales…" />
        }

        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }

        <p class="notice">¿Primera vez? <a routerLink="/register">Registrar mi agencia</a></p>
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
export class LoginComponent {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  /** Where to go after signing in; bound from the query string by the router. */
  readonly returnUrl = input('/dashboard');
  readonly reason = input<LoginRedirectReason | undefined>(undefined);

  protected readonly credentials = signal({ email: '', password: '' });

  protected readonly loginForm = form(this.credentials, (credentials) => {
    required(credentials.email);
    email(credentials.email);
    required(credentials.password);
  });

  protected readonly error = signal<AppError | null>(null);

  protected readonly redirectMessage = () => {
    const reason = this.reason();
    return reason ? REDIRECT_MESSAGES[reason] : null;
  };

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);

    await submit(this.loginForm, async (credentials) => {
      try {
        await this.auth.signIn(credentials.email().value(), credentials.password().value());
      } catch (failure) {
        // Deliberately not attached to a field: the server never says which input was wrong,
        // and pointing at one would invent information the response does not contain.
        this.error.set(toAppError(failure));
        return undefined;
      }

      await this.router.navigateByUrl(this.safeReturnUrl());
      return undefined;
    });
  }

  /**
   * Keeps the post-login redirect inside the application.
   *
   * `returnUrl` arrives from the query string, so an absolute or protocol-relative value would
   * turn the login screen into an open redirect.
   */
  private safeReturnUrl(): string {
    const target = this.returnUrl() ?? '/dashboard';
    return target.startsWith('/') && !target.startsWith('//') ? target : '/dashboard';
  }
}
