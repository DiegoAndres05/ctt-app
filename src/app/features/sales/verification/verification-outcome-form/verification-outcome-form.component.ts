import {
  ChangeDetectionStrategy,
  Component,
  effect,
  inject,
  input,
  output,
  signal,
  untracked,
} from '@angular/core';
import { form, FormField, required, submit, validate } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import {
  AVAILABILITY_STATUS_LABELS,
  CONTACT_METHOD_LABELS,
  type ProviderContactMethod,
  type RecordableAvailabilityStatus,
  type RecordOutcomeResult,
  type VerificationOutcomePayload,
  type VerificationQueueRow,
} from '../../../../core/pre-reservations/models/verification.model';
import { AvailabilityVerificationService } from '../../../../core/pre-reservations/services/availability-verification.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';

/** Outcomes `record_item_verification` accepts; `pending` is not recordable. */
const OUTCOME_STATUSES: RecordableAvailabilityStatus[] = [
  'available',
  'unavailable',
  'alternative_suggested',
];

const CONTACT_METHODS: ProviderContactMethod[] = ['phone', 'whatsapp', 'email', 'other'];

interface OutcomeDraft {
  status: RecordableAvailabilityStatus | '';
  contactPerson: string;
  contactMethod: ProviderContactMethod | '';
  /** `datetime-local` value; only honored with `available`, and it must be in the future. */
  holdExpiresAt: string;
  alternativeSuggestion: string;
  notes: string;
}

function emptyDraft(): OutcomeDraft {
  return {
    status: '',
    contactPerson: '',
    contactMethod: '',
    holdExpiresAt: '',
    alternativeSuggestion: '',
    notes: '',
  };
}

function isOutcomeStatus(value: string): value is RecordableAvailabilityStatus {
  return (OUTCOME_STATUSES as readonly string[]).includes(value);
}

/**
 * Maps the draft onto the `record_item_verification` payload (contracts §3.3): trims,
 * empties become `null`, and the hold is only sent with «Disponible».
 */
function buildPayload(draft: OutcomeDraft): VerificationOutcomePayload {
  const status = draft.status as RecordableAvailabilityStatus;
  const hold = status === 'available' ? draft.holdExpiresAt.trim() : '';
  return {
    status,
    contact_person: draft.contactPerson.trim(),
    contact_method: draft.contactMethod as ProviderContactMethod,
    hold_expires_at: hold ? new Date(hold).toISOString() : null,
    alternative_suggestion:
      status === 'alternative_suggested' ? draft.alternativeSuggestion.trim() : null,
    notes: draft.notes.trim() || null,
  };
}

/**
 * Records one availability outcome for a line (contracts §6.4).
 *
 * The queue (US2) deploys it under the row; the pre-reservation detail (US3) reuses it for
 * the same row actions. The parent reloads its data on `saved`.
 */
@Component({
  selector: 'app-verification-outcome-form',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, AlertComponent],
  template: `
    <form class="section" (submit)="onSubmit($event)" novalidate>
      <h2>Registrar resultado</h2>
      @if (item(); as row) {
        <p class="hint">{{ row.item_label }} · {{ row.reference }}</p>
      }

      <fieldset class="plain">
        <legend class="req">Resultado</legend>
        @for (option of outcomeStatuses; track option) {
          <label class="check">
            <input type="radio" [formField]="outcomeForm.status" [value]="option" />
            {{ statusLabel(option) }}
          </label>
        }
        @if (outcomeForm.status().touched()) {
          @for (failure of outcomeForm.status().errors(); track failure.kind) {
            <p class="field-error">{{ failure.message }}</p>
          }
        }
      </fieldset>

      <label class="req" for="contact-person">Persona de contacto en el proveedor</label>
      <input id="contact-person" type="text" [formField]="outcomeForm.contactPerson" />
      @if (outcomeForm.contactPerson().touched()) {
        @for (failure of outcomeForm.contactPerson().errors(); track failure.kind) {
          <p class="field-error">{{ failure.message }}</p>
        }
      }

      <label class="req" for="contact-method">Medio de contacto</label>
      <select id="contact-method" [formField]="outcomeForm.contactMethod">
        <option value="">Selecciona un medio</option>
        @for (method of contactMethods; track method) {
          <option [value]="method">{{ methodLabel(method) }}</option>
        }
      </select>
      @if (outcomeForm.contactMethod().touched()) {
        @for (failure of outcomeForm.contactMethod().errors(); track failure.kind) {
          <p class="field-error">{{ failure.message }}</p>
        }
      }

      @if (outcomeForm.status().value() === 'available') {
        <label for="hold-expires">Retención hasta</label>
        <input id="hold-expires" type="datetime-local" [formField]="outcomeForm.holdExpiresAt" />
        @if (outcomeForm.holdExpiresAt().touched()) {
          @for (failure of outcomeForm.holdExpiresAt().errors(); track failure.kind) {
            <p class="field-error">{{ failure.message }}</p>
          }
        }
      }

      @if (outcomeForm.status().value() === 'alternative_suggested') {
        <label class="req" for="alternative-suggestion">Alternativa sugerida</label>
        <textarea
          id="alternative-suggestion"
          rows="2"
          [formField]="outcomeForm.alternativeSuggestion"
        ></textarea>
        @if (outcomeForm.alternativeSuggestion().touched()) {
          @for (failure of outcomeForm.alternativeSuggestion().errors(); track failure.kind) {
            <p class="field-error">{{ failure.message }}</p>
          }
        }
      }

      <label for="outcome-notes">Notas</label>
      <textarea id="outcome-notes" rows="2" [formField]="outcomeForm.notes"></textarea>
      @if (outcomeForm.notes().touched()) {
        @for (failure of outcomeForm.notes().errors(); track failure.kind) {
          <p class="field-error">{{ failure.message }}</p>
        }
      }

      <div class="actions">
        <button class="primary" type="submit" [disabled]="outcomeForm().submitting()">
          {{ outcomeForm().submitting() ? 'Guardando…' : 'Guardar resultado' }}
        </button>
        <button type="button" (click)="cancelled.emit()">Cancelar</button>
      </div>

      @if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      }
    </form>
  `,
  styles: `
    legend.req::after {
      content: ' *';
      color: #b3261e;
    }
  `,
})
export class VerificationOutcomeFormComponent {
  private readonly verifications = inject(AvailabilityVerificationService);
  private appliedItemId = '';

  readonly item = input.required<VerificationQueueRow>();
  readonly saved = output<RecordOutcomeResult>();
  readonly cancelled = output<void>();

  protected readonly outcomeStatuses = OUTCOME_STATUSES;
  protected readonly contactMethods = CONTACT_METHODS;
  protected readonly statusLabel = (status: RecordableAvailabilityStatus) =>
    AVAILABILITY_STATUS_LABELS[status];
  protected readonly methodLabel = (method: ProviderContactMethod) => CONTACT_METHOD_LABELS[method];

  protected readonly draft = signal<OutcomeDraft>(emptyDraft());

  protected readonly outcomeForm = form(this.draft, (fields) => {
    // Each rule mirrors what `record_item_verification` enforces (migration 039).
    validate(fields.status, ({ value }) =>
      isOutcomeStatus(value())
        ? undefined
        : { kind: 'required', message: 'Selecciona el resultado.' },
    );

    validate(fields.contactPerson, ({ value }) => {
      const person = value().trim();
      if (!person) {
        return { kind: 'required', message: 'Indica con quién hablaste en el proveedor.' };
      }
      if (person.length > 120) {
        return { kind: 'maxLength', message: 'Máximo 120 caracteres.' };
      }
      return undefined;
    });

    required(fields.contactMethod, { message: 'Selecciona el medio de contacto.' });

    validate(fields.holdExpiresAt, ({ value, valueOf }) => {
      if (valueOf(fields.status) !== 'available') {
        return undefined;
      }
      const raw = value().trim();
      if (!raw) {
        // La retención es opcional incluso con «Disponible».
        return undefined;
      }
      const parsed = Date.parse(raw);
      if (Number.isNaN(parsed)) {
        return { kind: 'invalid', message: 'Indica una fecha válida.' };
      }
      if (parsed <= Date.now()) {
        return {
          kind: 'past',
          message: 'La fecha límite de retención debe ser futura.',
        };
      }
      return undefined;
    });

    validate(fields.alternativeSuggestion, ({ value, valueOf }) => {
      if (valueOf(fields.status) !== 'alternative_suggested') {
        return undefined;
      }
      const suggestion = value().trim();
      if (!suggestion) {
        return {
          kind: 'required',
          message: 'Describe la alternativa que sugirió el proveedor.',
        };
      }
      if (suggestion.length > 1000) {
        return { kind: 'maxLength', message: 'Máximo 1000 caracteres.' };
      }
      return undefined;
    });

    validate(fields.notes, ({ value }) =>
      value().length > 2000 ? { kind: 'maxLength', message: 'Máximo 2000 caracteres.' } : undefined,
    );
  });

  protected readonly error = signal<AppError | null>(null);

  constructor() {
    // The parent may reuse one instance across rows (queue, detail): each line starts blank.
    effect(() => {
      const itemId = this.item().item_id;
      untracked(() => {
        if (this.appliedItemId === itemId) {
          return;
        }
        this.appliedItemId = itemId;
        this.draft.set(emptyDraft());
        this.error.set(null);
      });
    });
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);
    await submit(this.outcomeForm, async () => {
      try {
        const result = await this.verifications.record(
          this.item().item_id,
          buildPayload(this.draft()),
        );
        this.saved.emit(result);
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }
}
