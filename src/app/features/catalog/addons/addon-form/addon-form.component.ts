import {
  ChangeDetectionStrategy,
  Component,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type { AddonUnit } from '../../../../core/catalog/models/addon.model';
import { AddonService } from '../../../../core/catalog/services/addon.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../../shared/components/unsaved-changes.guard';

/**
 * Create or edit an add-on (User Story 2).
 */
@Component({
  selector: 'app-addon-form',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <a routerLink="/cms/settings/addons">Cancelar</a>

      @if (loading()) {
        <app-spinner label="Cargando complemento…" />
      } @else if (loadError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else {
        <form class="section" (submit)="onSubmit($event)" novalidate>
          <h1>{{ isEdit() ? 'Editar complemento' : 'Nuevo complemento' }}</h1>

          <label class="req" for="name">Nombre</label>
          <input id="name" type="text" [formField]="addonForm.name" />
          @if (addonForm.name().touched() && addonForm.name().invalid()) {
            <p class="field-error">Ingresa el nombre del complemento.</p>
          }

          <label for="description">Descripción</label>
          <textarea id="description" rows="3" [formField]="addonForm.description"></textarea>

          <label for="unit">Unidad</label>
          <select id="unit" [formField]="addonForm.unit">
            <option value="per_person">Por persona</option>
            <option value="per_unit">Por unidad</option>
            <option value="per_service">Por servicio</option>
          </select>

          <label class="check" for="is-active">
            <input id="is-active" type="checkbox" [formField]="addonForm.isActive" />
            Activo
          </label>

          <div class="actions">
            <button class="primary" type="submit" [disabled]="addonForm().submitting()">
              {{ addonForm().submitting() ? 'Guardando…' : 'Guardar' }}
            </button>
            <a class="button-link" routerLink="/cms/settings/addons">Cancelar</a>
          </div>

          @if (error(); as failure) {
            <app-alert kind="error">{{ failure.message }}</app-alert>
          }
        </form>
      }
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

    .check {
      font-weight: 400;
      display: flex;
      gap: 0.4rem;
      align-items: center;
    }

    .field-error {
      color: #b3261e;
      margin: 0;
    }

    button {
      margin-top: 0.75rem;
      padding: 0.6rem 1rem;
    }
  `,
})
export class AddonFormComponent implements UnsavedChangesHost {
  private readonly addonsApi = inject(AddonService);
  private readonly router = inject(Router);

  /** Bound from the `:id` route param when editing. */
  readonly id = input<string | undefined>();

  protected readonly loading = signal(false);
  protected readonly loadError = signal<AppError | null>(null);
  protected readonly error = signal<AppError | null>(null);
  private baseline = '';
  private allowLeave = false;

  protected readonly draft = signal({
    name: '',
    description: '',
    unit: 'per_person' as AddonUnit,
    isActive: true,
  });

  protected readonly addonForm = form(this.draft, (fields) => {
    required(fields.name);
    required(fields.unit);
  });

  constructor() {
    this.baseline = JSON.stringify(this.draft());
    effect(() => {
      const id = this.id();
      untracked(() => {
        if (id) {
          void this.load(id);
        }
      });
    });
  }

  hasUnsavedChanges(): boolean {
    if (this.allowLeave) {
      return false;
    }
    return JSON.stringify(this.draft()) !== this.baseline;
  }

  protected isEdit(): boolean {
    return Boolean(this.id());
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);

    await submit(this.addonForm, async (fields) => {
      try {
        const payload = {
          name: fields.name().value(),
          description: fields.description().value() || null,
          unit: fields.unit().value(),
          isActive: fields.isActive().value(),
        };
        const id = this.id();
        if (id) {
          await this.addonsApi.update(id, payload);
          this.draft.set({
            name: payload.name,
            description: payload.description ?? '',
            unit: payload.unit,
            isActive: payload.isActive,
          });
          this.baseline = JSON.stringify(this.draft());
        } else {
          const created = await this.addonsApi.create(payload);
          this.allowLeave = true;
          await this.router.navigate(['/cms/settings/addons', created.id]);
        }
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }

  private async load(id: string): Promise<void> {
    this.loading.set(true);
    this.loadError.set(null);
    try {
      const addon = await this.addonsApi.getById(id);
      if (!addon) {
        this.loadError.set(toAppError(new Error('VALIDATION_ERROR')));
        return;
      }
      this.draft.set({
        name: addon.name,
        description: addon.description ?? '',
        unit: addon.unit,
        isActive: addon.is_active,
      });
      this.baseline = JSON.stringify(this.draft());
    } catch (failure) {
      this.loadError.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
