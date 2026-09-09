import { ErrorHandler, Injectable, isDevMode } from '@angular/core';
import type { AuthErrorCode } from '../auth/models/auth.model';

/**
 * Application-wide error normalization and logging.
 *
 * Two rules shape this file. Failures are never swallowed: anything unexpected reaches the
 * console with enough context to diagnose it. And nothing sensitive is ever written to a log:
 * credentials and tokens are stripped before anything is emitted.
 */

/** A failure translated into something the UI can act on. */
export interface AppError {
  code: AuthErrorCode;
  /** Safe to show to an end user; never contains internal details or identifiers. */
  message: string;
  /** Original failure, kept for logging only. */
  cause?: unknown;
}

/** Keys whose values must never appear in a log line. */
const REDACTED_KEYS = [
  'password',
  'new_password',
  'current_password',
  'temporary_password',
  'access_token',
  'refresh_token',
  'apikey',
  'authorization',
];

const USER_FACING_MESSAGES: Readonly<Record<AuthErrorCode, string>> = {
  VALIDATION_ERROR: 'Revisa los datos ingresados e inténtalo de nuevo.',
  // Deliberately identical for unknown address and wrong password: telling them apart
  // would let an attacker enumerate valid accounts.
  INVALID_CREDENTIALS: 'Correo o contraseña incorrectos.',
  ACCOUNT_LOCKED: 'La cuenta está bloqueada temporalmente. Inténtalo más tarde.',
  ACCOUNT_INACTIVE: 'La cuenta está desactivada. Contacta a un administrador.',
  INVALID_CURRENT_PASSWORD: 'La contraseña actual es incorrecta.',
  WEAK_PASSWORD: 'La nueva contraseña no cumple los requisitos mínimos.',
  PASSWORD_UNCHANGED: 'La nueva contraseña debe ser distinta de la actual.',
  INSUFFICIENT_PERMISSIONS: 'No tienes permisos para realizar esta acción.',
  EMAIL_ALREADY_EXISTS: 'Ya existe una cuenta con ese correo.',
  AGENCY_SLUG_EXISTS: 'Ya existe una agencia con ese nombre.',
  REGISTRATION_FAILED: 'No se pudo completar el registro. Inténtalo de nuevo.',
  MISSING_TENANT_CONTEXT: 'Tu sesión no tiene una organización asociada. Vuelve a iniciar sesión.',
  SESSION_EXPIRED: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  UNKNOWN_ERROR: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
};

/** PostgreSQL SQLSTATEs the database raises deliberately as part of the security design. */
const POSTGRES_CODE_MAP: Readonly<Record<string, AuthErrorCode>> = {
  // Raised by the RLS column-scope guard and by permission denials.
  '42501': 'INSUFFICIENT_PERMISSIONS',
  // Row-level security policy rejected the write.
  '42P17': 'INSUFFICIENT_PERMISSIONS',
};

/** Translates an arbitrary failure into a stable, displayable {@link AppError}. */
export function toAppError(error: unknown): AppError {
  const code = resolveErrorCode(error);
  return { code, message: USER_FACING_MESSAGES[code], cause: error };
}

/** The codes carried in an error message, longest first so no code shadows a prefix of another. */
const MESSAGE_CODES = (Object.keys(USER_FACING_MESSAGES) as AuthErrorCode[]).sort(
  (a, b) => b.length - a.length,
);

function resolveErrorCode(error: unknown): AuthErrorCode {
  if (typeof error !== 'object' || error === null) {
    return 'UNKNOWN_ERROR';
  }

  const candidate = error as {
    code?: unknown;
    status?: unknown;
    message?: unknown;
    details?: unknown;
  };

  if (typeof candidate.code === 'string') {
    const mapped = POSTGRES_CODE_MAP[candidate.code];
    if (mapped) {
      return mapped;
    }
    if (candidate.code in USER_FACING_MESSAGES) {
      return candidate.code as AuthErrorCode;
    }
    // Unique violation: emails and agency slugs are the only unique keys the UI can hit.
    // Distinguish them from the constraint name / detail so a slug clash is not reported
    // as a duplicate address (T046).
    if (candidate.code === '23505') {
      const blob = `${stringify(candidate.message)} ${stringify(candidate.details)}`;
      return blob.toLowerCase().includes('slug') ? 'AGENCY_SLUG_EXISTS' : 'EMAIL_ALREADY_EXISTS';
    }
  }

  // Two server-side contracts surface their outcome as text rather than as a status code, so
  // the message has to be read to tell them apart (see supabase/migrations/008_us1_auth_functions.sql):
  //   * the RPCs raise the contract's error code as the exception message;
  //   * the password verification hook prefixes its rejection with the code, and Supabase Auth
  //     relays that message verbatim.
  // Anything not carrying a known code falls through to the status checks below, which keep
  // the coarse `INVALID_CREDENTIALS` answer.
  if (typeof candidate.message === 'string') {
    const message = candidate.message;
    const matched = MESSAGE_CODES.find((code) => message.includes(code));
    if (matched) {
      return matched;
    }
  }

  if (candidate.status === 401 || candidate.status === 400) {
    return 'INVALID_CREDENTIALS';
  }
  if (candidate.status === 403) {
    return 'INSUFFICIENT_PERMISSIONS';
  }

  return 'UNKNOWN_ERROR';
}

function stringify(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

/**
 * Returns a copy of `value` with credential-bearing fields replaced by a marker.
 * Deep, because Supabase errors nest the offending request body.
 */
export function redact(value: unknown, depth = 0): unknown {
  if (depth > 4 || typeof value !== 'object' || value === null) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => redact(item, depth + 1));
  }

  const result: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    result[key] = REDACTED_KEYS.includes(key.toLowerCase())
      ? '[redacted]'
      : redact(nested, depth + 1);
  }
  return result;
}

/**
 * Last line of defence for errors that reach Angular unhandled.
 *
 * Registered in `app.config.ts`. In production this is where a telemetry sink would be
 * attached; the console is the sink for now, and the redaction above is what makes either
 * destination safe.
 */
@Injectable()
export class AppErrorHandler implements ErrorHandler {
  handleError(error: unknown): void {
    const appError = toAppError(error);

    console.error('[cttadmin]', appError.code, appError.message, {
      detail: redact(unwrap(error)),
    });

    if (isDevMode()) {
      console.error(error);
    }
  }
}

/** Angular wraps errors thrown during change detection; the inner error is the useful one. */
function unwrap(error: unknown): unknown {
  if (typeof error === 'object' && error !== null && 'rejection' in error) {
    return (error as { rejection: unknown }).rejection;
  }
  return error;
}
