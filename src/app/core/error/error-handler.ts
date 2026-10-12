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
  PRODUCT_HAS_NO_VALID_PRICE:
    'El producto no puede activarse porque no tiene un esquema de precio vigente.',
  SEASON_OVERLAP: 'Ese rango de temporada se solapa con otra tarifa vigente.',
  INVALID_SEASON_RANGE: 'La fecha de inicio de temporada no puede ser posterior a la de fin.',
  INVALID_PRICE_TARGET: 'El precio debe aplicarse a un producto o a un complemento, no a ambos.',
  PACKAGE_NESTING_NOT_ALLOWED: 'Un paquete no puede incluir otro paquete.',
  PUBLIC_LISTING_INCOMPLETE:
    'La ficha pública está incompleta. Completa los campos obligatorios, la portada y los pares bilingües.',
  PUBLIC_SLUG_IMMUTABLE:
    'El slug o la sección pública no se pueden cambiar después de la primera publicación.',
  PUBLIC_SLUG_TAKEN: 'Otro producto de la agencia ya usa ese slug público.',
  PLACEMENT_PRODUCT_MISMATCH: 'Ese tipo de producto no admite la sección pública seleccionada.',
  ORIGINAL_PRICE_NOT_HIGHER: 'El precio anterior debe ser mayor que el precio de vitrina.',
  BILINGUAL_PAIR_INCOMPLETE: 'Cada ítem bilingüe debe tener texto en español y en inglés.',
  PRODUCT_NOT_ACTIVE: 'El producto debe estar activo para publicar la ficha pública.',
  COVER_REQUIRED: 'Una ficha publicada no puede quedarse sin imagen de portada.',
  IMAGE_TOO_LARGE: 'La imagen supera el límite de 10 MB.',
  IMAGE_TYPE_NOT_ALLOWED: 'Solo se permiten imágenes JPEG, PNG o WebP.',
  GALLERY_ONLY_FOR_LODGING: 'La galería solo está disponible en fichas de alojamiento.',
  CATEGORY_IN_USE: 'No se puede desactivar una categoría pública que aún usan fichas publicadas.',
  CUTOVER_INCOMPLETE:
    'Faltan fichas del manifiesto. Publica todos los ítems antes de completar el cambio de fuente.',
  CUTOVER_ALREADY_COMPLETED: 'El cambio de fuente a panel ya se completó.',
  CONSENT_REQUIRED:
    'Debes confirmar que el cliente fue informado sobre el tratamiento de sus datos.',
  CONTACT_REQUIRED: 'Ingresa el nombre y al menos un correo o un teléfono.',
  INVALID_EMAIL: 'El correo no tiene un formato válido.',
  INVALID_PHONE: 'El teléfono no es válido. Incluye el indicativo del país si no es de Colombia.',
  TRAVEL_DATE_IN_PAST: 'La fecha de inicio del viaje no puede estar en el pasado.',
  INVALID_DATE_RANGE: 'La fecha de fin no puede ser anterior a la de inicio.',
  LISTING_NOT_AVAILABLE: 'Uno de los productos no está disponible para solicitudes.',
  RATE_LIMITED: 'Se recibieron demasiadas solicitudes. Inténtalo más tarde.',
  INVALID_STATUS_TRANSITION: 'Ese cambio de estado no está permitido.',
  PRE_RESERVATION_REQUIRES_CONVERSION: 'La pre-reserva se crea desde el módulo de pre-reservas.',
  DISCARD_REASON_REQUIRED: 'Indica el motivo para descartar la solicitud.',
  REQUEST_CLOSED: 'La solicitud está cerrada y ya no admite cambios de gestión.',
  ASSIGNEE_NOT_IN_ORGANIZATION: 'El colaborador elegido no está activo en tu organización.',
  CUSTOMER_ANONYMIZED: 'El cliente fue anonimizado y no admite cambios.',
  CUSTOMER_CONTACT_TAKEN: 'Ese correo o teléfono ya pertenece a otro cliente.',
  PRE_RESERVATION_CLOSED: 'La pre-reserva está cancelada y ya no admite cambios.',
  PRE_RESERVATION_REQUIRES_ITEMS: 'La pre-reserva debe conservar al menos un servicio principal.',
  PRE_RESERVATION_NOT_VERIFIED: 'La pre-reserva aún no está totalmente verificada.',
  PRE_RESERVATION_EXPIRED:
    'La disponibilidad confirmada venció. Vuelve a verificar con el proveedor.',
  ITEM_NOT_BOOKABLE: 'El producto o complemento no está activo en el catálogo.',
  ITEM_WITHDRAWN: 'Ese servicio fue retirado de la pre-reserva.',
  CONTACT_PERSON_REQUIRED: 'Indica con quién hablaste en el proveedor.',
  HOLD_EXPIRY_IN_PAST: 'La fecha límite de retención debe ser futura.',
  ALTERNATIVE_SUGGESTION_REQUIRED: 'Describe la alternativa que sugirió el proveedor.',
  CANCEL_REASON_REQUIRED: 'Indica el motivo para cancelar la pre-reserva.',
  OVERRIDE_REASON_REQUIRED: 'Indica el motivo de la excepción.',
  OVERRIDE_NOT_REQUIRED: 'La pre-reserva ya está totalmente verificada; no necesita excepción.',
  ASSIGNEE_NOT_OPERATOR: 'Solo un operador o administrador activo puede verificar disponibilidad.',
  // Quotations (feature 005, specs/005-quotation-proposals/contracts/api-contracts.md §2–§5).
  TARIFF_NOT_FOUND: 'No hay tarifa vigente para este servicio.',
  AMBIGUOUS_TARIFF: 'Hay más de una tarifa vigente y ninguna coincide con el tipo de cobro.',
  EXCHANGE_RATE_REQUIRED: 'Falta la tasa de cambio para emitir.',
  EXCHANGE_RATE_INVALID: 'La tasa de cambio debe ser mayor que cero.',
  TAX_RATE_OUT_OF_RANGE: 'El impuesto debe estar entre 0 % y 100 %.',
  ADJUSTMENT_REQUIRES_ADMIN: 'Este ajuste supera el 15 % y requiere un administrador.',
  ADJUSTMENT_LABEL_REQUIRED: 'El ajuste necesita una etiqueta.',
  QUOTATION_FROZEN: 'La cotización emitida no se edita. Cree una versión nueva.',
  QUOTATION_ALREADY_OPEN: 'Ya hay una cotización abierta para esta pre-reserva.',
  QUOTATION_ALREADY_ACCEPTED: 'Esta pre-reserva ya tiene una cotización aceptada.',
  VALIDITY_EXCEEDS_HOLD: 'La vigencia no puede pasar de la retención de la pre-reserva.',
  VALIDITY_EXCEEDS_30_DAYS: 'La vigencia no puede pasar de 30 días.',
  TERMS_REQUIRED: 'Faltan las condiciones de la propuesta.',
  QUOTATION_STALE: 'La pre-reserva cambió después de emitir. Hay que crear una versión nueva.',
  QUOTATION_NOT_OPEN: 'Esta propuesta ya no admite esa respuesta.',
  QUOTATION_TERMINAL: 'Esta cotización está cerrada.',
  QUOTATION_NOT_ACCEPTED: 'Solo una cotización aceptada puede confirmarse como reserva.',
  QUOTATION_ACCEPTED: 'Una cotización aceptada no se anula.',
  VOID_REASON_REQUIRED: 'Indique el motivo de la anulación.',
  CONFIRMATION_REQUIRED: 'Confirme la aceptación para continuar.',
  FORBIDDEN: 'No tienes permisos para realizar esta acción.',
  UNKNOWN_ERROR: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
};

/** PostgreSQL SQLSTATEs the database raises deliberately as part of the security design. */
const POSTGRES_CODE_MAP: Readonly<Record<string, AuthErrorCode>> = {
  // Raised by the RLS column-scope guard and by permission denials.
  '42501': 'INSUFFICIENT_PERMISSIONS',
  // Row-level security policy rejected the write.
  '42P17': 'INSUFFICIENT_PERMISSIONS',
  // GiST EXCLUDE on overlapping seasonal tariffs (R-004).
  '23P01': 'SEASON_OVERLAP',
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
      const blob = `${stringify(candidate.message)} ${stringify(candidate.details)}`.toLowerCase();
      if (blob.includes('organizations') && blob.includes('slug')) {
        return 'AGENCY_SLUG_EXISTS';
      }
      if (blob.includes('email')) {
        return 'EMAIL_ALREADY_EXISTS';
      }
      return 'VALIDATION_ERROR';
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
