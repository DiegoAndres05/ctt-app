import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { PublicCategory } from '../../../core/catalog/models/public-listing.model';
import { PublicListingService } from '../../../core/catalog/services/public-listing.service';
import { AuthService } from '../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../core/auth/models/user.model';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/**
 * Public catalog categories (feature 009). Operator/Admin write; RLS scopes rows.
 */
@Component({
  selector: 'app-public-categories',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header>
        <div>
          <a routerLink="/catalog">Catálogo</a>
          <h1>Categorías públicas</h1>
        </div>
      </header>

      <p class="notice">
        Filtros del catálogo público. No reemplazan las categorías internas del producto.
      </p>

      @if (loading()) {
        <app-spinner label="Cargando categorías…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else {
        <table>
          <thead>
            <tr>
              <th>Id</th>
              <th>Español</th>
              <th>Inglés</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            @for (category of categories(); track category.id) {
              <tr>
                <td>{{ category.id }}</td>
                <td>{{ category.name_es }}</td>
                <td>{{ category.name_en }}</td>
                <td>{{ category.is_active ? 'Activa' : 'Inactiva' }}</td>
                <td>
                  @if (canManage() && category.is_active) {
                    <button type="button" (click)="onDeactivate(category)">Desactivar</button>
                  }
                </td>
              </tr>
            }
          </tbody>
        </table>

        @if (canManage()) {
          <form class="card" (submit)="onCreate($event)" novalidate>
            <h2>Nueva categoría</h2>
            <label for="cat-id">Id (minúsculas y _)</label>
            <input id="cat-id" type="text" [formField]="createForm.id" />

            <label for="cat-es">Nombre (ES)</label>
            <input id="cat-es" type="text" [formField]="createForm.nameEs" />

            <label for="cat-en">Nombre (EN)</label>
            <input id="cat-en" type="text" [formField]="createForm.nameEn" />

            <button type="submit" [disabled]="createForm().submitting()">
              {{ createForm().submitting() ? 'Guardando…' : 'Crear categoría' }}
            </button>
          </form>
        }
      }

      @if (actionError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      }
      @if (notice(); as message) {
        <app-alert kind="success">{{ message }}</app-alert>
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

    h1,
    h2 {
      margin: 0.25rem 0 0;
    }

    .notice {
      margin: 0;
    }

    table {
      width: min(48rem, 100%);
      border-collapse: collapse;
    }

    th,
    td {
      text-align: left;
      padding: 0.4rem 0.5rem;
      border-bottom: 1px solid #ddd;
    }

    .card {
      display: grid;
      gap: 0.5rem;
      width: min(28rem, 100%);
    }

    label {
      font-weight: 600;
    }

    button {
      margin-top: 0.25rem;
      padding: 0.5rem 0.9rem;
    }
  `,
})
export class PublicCategoriesComponent {
  private readonly api = inject(PublicListingService);
  private readonly auth = inject(AuthService);

  protected readonly categories = signal<PublicCategory[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);

  protected readonly createDraft = signal({
    id: '',
    nameEs: '',
    nameEn: '',
  });

  protected readonly createForm = form(this.createDraft, (fields) => {
    required(fields.id);
    required(fields.nameEs);
    required(fields.nameEn);
  });

  constructor() {
    void this.refresh();
  }

  protected canManage(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'operator');
  }

  protected async onCreate(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.createForm, async (fields) => {
      try {
        await this.api.saveCategory({
          id: fields.id().value().trim().toLowerCase(),
          name_es: fields.nameEs().value().trim(),
          name_en: fields.nameEn().value().trim(),
          is_active: true,
        });
        this.createDraft.set({ id: '', nameEs: '', nameEn: '' });
        await this.refresh();
        this.notice.set('La categoría pública se creó.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onDeactivate(category: PublicCategory): Promise<void> {
    this.actionError.set(null);
    this.notice.set(null);
    try {
      await this.api.saveCategory({
        id: category.id,
        name_es: category.name_es,
        name_en: category.name_en,
        is_active: false,
      });
      await this.refresh();
      this.notice.set(`La categoría «${category.id}» quedó inactiva.`);
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    }
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.categories.set(await this.api.listCategories());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
