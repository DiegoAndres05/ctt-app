import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { form, FormField, required, submit } from '@angular/forms/signals';
import type { Category } from '../../../core/catalog/models/category.model';
import { CategoryService } from '../../../core/catalog/services/category.service';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../shared/components/unsaved-changes.guard';

/**
 * Operational categories used to tag products. Not the public site filters.
 */
@Component({
  selector: 'app-category-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <section class="editor-main">
      <h1>Categorías</h1>
      <p class="notice">Taxonomía interna del catálogo. No reemplaza las categorías públicas.</p>

      @if (loading()) {
        <app-spinner label="Cargando categorías…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else {
        @if (categories().length === 0) {
          <p>No hay categorías en esta organización.</p>
        } @else {
          <table class="data">
            <thead>
              <tr>
                <th>Nombre</th>
                <th>Identificador</th>
              </tr>
            </thead>
            <tbody>
              @for (category of categories(); track category.id) {
                <tr>
                  <td>{{ category.name }}</td>
                  <td>{{ category.slug }}</td>
                </tr>
              }
            </tbody>
          </table>
        }

        <form class="section" [class.incomplete]="nameInvalid()" (submit)="onCreate($event)" novalidate>
          <h2>Nueva categoría</h2>
          <label class="req" for="category-name">Nombre</label>
          <input id="category-name" type="text" [formField]="createForm.name" />
          @if (createForm.name().touched() && createForm.name().invalid()) {
            <p class="field-error">Ingresa el nombre de la categoría.</p>
          }
          <div class="actions">
            <button class="primary" type="submit" [disabled]="createForm().submitting()">
              {{ createForm().submitting() ? 'Guardando…' : 'Guardar' }}
            </button>
            <a class="button-link" routerLink="/cms/settings">Cancelar</a>
          </div>
        </form>
      }

      @if (actionError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      }
    </section>
  `,
})
export class CategoryListComponent implements UnsavedChangesHost {
  private readonly categoriesApi = inject(CategoryService);

  protected readonly categories = signal<Category[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly draft = signal({ name: '' });
  protected readonly createForm = form(this.draft, (fields) => {
    required(fields.name);
  });

  constructor() {
    void this.refresh();
  }

  hasUnsavedChanges(): boolean {
    return this.draft().name.trim().length > 0;
  }

  protected nameInvalid(): boolean {
    return this.createForm.name().touched() && this.createForm.name().invalid();
  }

  protected async onCreate(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    await submit(this.createForm, async (fields) => {
      try {
        await this.categoriesApi.create({ name: fields.name().value() });
        this.draft.set({ name: '' });
        await this.refresh();
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.categories.set(await this.categoriesApi.list());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
