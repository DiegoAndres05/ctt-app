import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, effect, inject, input, signal } from '@angular/core';
import { form, FormField, required } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { RequestNote } from '../../../core/customers/models/request.model';
import { RequestService } from '../../../core/customers/services/request.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';

type NoteTarget = { requestId: string } | { customerId: string };

/**
 * Append-only notes for a request or a customer.
 */
@Component({
  selector: 'app-notes-section',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, FormField, AlertComponent],
  template: `
    <section class="section">
      <h2>Notas</h2>
      <p class="hint">No escribas datos personales sensibles en las notas.</p>

      @if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      }

      @if (!readOnly()) {
        <form (submit)="onAdd($event)" novalidate>
          <label class="req" for="note-content">Nueva nota</label>
          <textarea id="note-content" rows="3" [formField]="noteForm.content"></textarea>
          @if (noteForm.content().touched() && noteForm.content().invalid()) {
            <p class="field-error">Escribe la nota.</p>
          }
          <button class="primary" type="submit" [disabled]="saving()">
            {{ saving() ? 'Guardando…' : 'Agregar nota' }}
          </button>
        </form>
      }

      @if (notes().length === 0) {
        <p>Todavía no hay notas.</p>
      } @else {
        <ul class="notes">
          @for (note of notes(); track note.id) {
            <li>
              <strong>{{ note.author?.full_name ?? 'Colaborador' }}</strong>
              <time [attr.datetime]="note.created_at">{{ note.created_at | date: 'short' }}</time>
              <p>{{ note.content }}</p>
            </li>
          }
        </ul>
      }
    </section>
  `,
  styles: `
    .hint {
      margin: 0;
      color: #57534e;
    }

    form {
      display: grid;
      gap: 0.4rem;
    }

    .notes {
      list-style: none;
      margin: 0;
      padding: 0;
      display: grid;
      gap: 0.75rem;
    }

    time {
      margin-left: 0.5rem;
      color: #57534e;
      font-size: 0.875rem;
    }
  `,
})
export class NotesSectionComponent {
  private readonly requests = inject(RequestService);

  readonly target = input.required<NoteTarget>();
  readonly readOnly = input(false);

  protected readonly notes = signal<RequestNote[]>([]);
  protected readonly error = signal<AppError | null>(null);
  protected readonly saving = signal(false);
  protected readonly draft = signal({ content: '' });
  protected readonly noteForm = form(this.draft, (fields) => {
    required(fields.content);
  });

  constructor() {
    effect(() => {
      const target = this.target();
      void this.load(target);
    });
  }

  protected async onAdd(event: Event): Promise<void> {
    event.preventDefault();
    const content = this.draft().content.trim();
    if (!content || content.length > 4000) {
      this.error.set(toAppError({ message: 'VALIDATION_ERROR' }));
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    try {
      await this.requests.addNote(this.target(), content);
      this.draft.set({ content: '' });
      await this.load(this.target());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.saving.set(false);
    }
  }

  private async load(target: NoteTarget): Promise<void> {
    try {
      this.notes.set(await this.requests.listNotes(target));
    } catch (failure) {
      this.error.set(toAppError(failure));
    }
  }
}
