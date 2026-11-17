import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { form, FormField, required, submit, validate } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { PublicCategory } from '../../../core/catalog/models/public-listing.model';
import {
  isValidTaxonomyCode,
  suggestTaxonomyCode,
} from '../../../core/catalog/models/public-agency-config.model';
import { PublicListingService } from '../../../core/catalog/services/public-listing.service';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { AuthService } from '../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../core/auth/models/user.model';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../shared/components/unsaved-changes.guard';

const EMPTY_DRAFT = { id: '', nameEs: '', nameEn: '' };

/**
 * Public catalog categories owned by the agency (features 009 and 016). Operator/Admin write.
 * A category used by listings can be deactivated but not deleted; protected categories
 * (the ones a migrated site already links to) cannot be deleted either.
 */
@Component({
  selector: 'app-public-categories',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header class="page-head">
        <a routerLink="/cms/settings">Ajustes del catálogo</a>
        <h1>Categorías públicas</h1>
        <p class="hint">
          Los filtros con los que el viajero recorre tu catálogo público. Son de tu agencia: puedes
          renombrarlas, desactivarlas o crear las tuyas. No reemplazan las categorías internas.
        </p>
      </header>

      @if (loading()) {
        <app-spinner label="Cargando categorías…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else {
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Identificador</th>
                <th>Español</th>
                <th>Inglés</th>
                <th>Estado</th>
                @if (canManage()) {
                  <th><span class="visually-hidden">Acciones</span></th>
                }
              </tr>
            </thead>
            <tbody>
              @for (category of categories(); track category.id) {
                <tr [class.muted]="!category.is_active">
                  <td>
                    <code>{{ category.id }}</code>
                    @if (category.protected) {
                      <span class="badge" title="La usa el sitio migrado: no se puede eliminar"
                        >Protegida</span
                      >
                    }
                  </td>
                  <td>{{ category.name_es }}</td>
                  <td>{{ category.name_en }}</td>
                  <td>{{ category.is_active ? 'Activa' : 'Inactiva' }}</td>
                  @if (canManage()) {
                    <td class="row-actions">
                      <button type="button" class="link" (click)="onEdit(category)">Editar</button>
                      <button type="button" class="link" (click)="onToggle(category)">
                        {{ category.is_active ? 'Desactivar' : 'Activar' }}
                      </button>
                      @if (!category.protected) {
                        <button type="button" class="link danger" (click)="onDelete(category)">
                          Eliminar
                        </button>
                      }
                    </td>
                  }
                </tr>
              } @empty {
                <tr>
                  <td colspan="5">Tu agencia aún no tiene categorías públicas.</td>
                </tr>
              }
            </tbody>
          </table>
        </div>

        @if (canManage()) {
          <form class="card" (submit)="onSave($event)" novalidate>
            <h2>{{ editingId() ? 'Editar «' + editingId() + '»' : 'Nueva categoría' }}</h2>
            <div class="form-grid">
              <div class="field req">
                <label for="cat-es">Nombre en español</label>
                <input
                  id="cat-es"
                  type="text"
                  [formField]="createForm.nameEs"
                  (blur)="suggestId()"
                />
                @if (createForm.nameEs().touched() && createForm.nameEs().invalid()) {
                  <p class="field-error">Ingresa el nombre en español.</p>
                }
              </div>
              <div class="field req">
                <label for="cat-en">Nombre en inglés</label>
                <input id="cat-en" type="text" [formField]="createForm.nameEn" />
                @if (createForm.nameEn().touched() && createForm.nameEn().invalid()) {
                  <p class="field-error">Ingresa el nombre en inglés.</p>
                }
              </div>
              @if (!editingId()) {
                <div class="field req">
                  <label for="cat-id">Identificador</label>
                  <input id="cat-id" type="text" [formField]="createForm.id" />
                  @if (createForm.id().touched() && createForm.id().invalid()) {
                    <p class="field-error">
                      Usa minúsculas, números y guion bajo, p. ej. «islas_rosario».
                    </p>
                  } @else {
                    <p class="hint">
                      Va en los filtros y direcciones del sitio. No cambia después.
                    </p>
                  }
                </div>
              }
            </div>
            <div class="form-actions">
              <button class="primary" type="submit" [disabled]="createForm().submitting()">
                {{
                  createForm().submitting()
                    ? 'Guardando…'
                    : editingId()
                      ? 'Guardar cambios'
                      : 'Crear categoría'
                }}
              </button>
              @if (editingId()) {
                <button type="button" (click)="cancelEdit()">Cancelar</button>
              }
            </div>
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
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    th,
    td {
      text-align: left;
      padding: 0.5rem;
      border-bottom: 1px solid var(--color-border);
      vertical-align: middle;
    }

    tr.muted td {
      color: var(--color-text-muted);
    }

    .badge {
      margin-left: 0.4rem;
      font-size: 0.75rem;
      padding: 0.1rem 0.45rem;
      border-radius: 999px;
      background: var(--color-surface-muted, rgba(0, 0, 0, 0.06));
    }

    .row-actions {
      white-space: nowrap;
      text-align: right;
    }

    .row-actions button + button {
      margin-left: 0.5rem;
    }

    .card {
      max-width: 48rem;
    }
  `,
})
export class PublicCategoriesComponent implements UnsavedChangesHost {
  private readonly api = inject(PublicListingService);
  private readonly config = inject(PublicAgencyConfigService);
  private readonly auth = inject(AuthService);

  protected readonly categories = signal<PublicCategory[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly editingId = signal<string | null>(null);

  protected readonly canManage = computed(() => hasRoleAtLeast(this.auth.role(), 'operator'));

  protected readonly createDraft = signal({ ...EMPTY_DRAFT });

  protected readonly createForm = form(this.createDraft, (fields) => {
    required(fields.nameEs);
    required(fields.nameEn);
    validate(fields.id, ({ value }) =>
      this.editingId() || isValidTaxonomyCode(value().trim())
        ? undefined
        : { kind: 'code', message: 'Identificador inválido' },
    );
  });

  constructor() {
    void this.refresh();
  }

  hasUnsavedChanges(): boolean {
    const draft = this.createDraft();
    return Boolean(draft.id.trim() || draft.nameEs.trim() || draft.nameEn.trim());
  }

  protected suggestId(): void {
    const draft = this.createDraft();
    if (!this.editingId() && !draft.id.trim() && draft.nameEs.trim()) {
      this.createDraft.update((current) => ({ ...current, id: suggestTaxonomyCode(draft.nameEs) }));
    }
  }

  protected onEdit(category: PublicCategory): void {
    this.notice.set(null);
    this.actionError.set(null);
    this.editingId.set(category.id);
    this.createDraft.set({ id: category.id, nameEs: category.name_es, nameEn: category.name_en });
  }

  protected cancelEdit(): void {
    this.editingId.set(null);
    this.createDraft.set({ ...EMPTY_DRAFT });
    this.createForm().reset();
  }

  protected async onSave(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.createForm, async (fields) => {
      const editing = this.editingId();
      const existing = editing ? this.categories().find((item) => item.id === editing) : null;
      try {
        await this.api.saveCategory({
          id: editing ?? fields.id().value().trim().toLowerCase(),
          name_es: fields.nameEs().value().trim(),
          name_en: fields.nameEn().value().trim(),
          is_active: existing?.is_active ?? true,
        });
        this.cancelEdit();
        await this.refresh();
        this.notice.set(editing ? 'Los cambios se guardaron.' : 'La categoría pública se creó.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onToggle(category: PublicCategory): Promise<void> {
    this.actionError.set(null);
    this.notice.set(null);
    try {
      await this.api.saveCategory({
        id: category.id,
        name_es: category.name_es,
        name_en: category.name_en,
        is_active: !category.is_active,
      });
      await this.refresh();
      this.notice.set(
        category.is_active
          ? `«${category.name_es}» quedó inactiva. Las fichas que ya la usan la conservan; no se podrá elegir en fichas nuevas.`
          : `«${category.name_es}» está activa de nuevo.`,
      );
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    }
  }

  protected async onDelete(category: PublicCategory): Promise<void> {
    this.actionError.set(null);
    this.notice.set(null);
    if (
      !confirm(`¿Eliminar la categoría «${category.name_es}»? Esta acción no se puede deshacer.`)
    ) {
      return;
    }
    try {
      await this.config.deleteCategory(category.id);
      if (this.editingId() === category.id) {
        this.cancelEdit();
      }
      await this.refresh();
      this.notice.set(`La categoría «${category.name_es}» se eliminó.`);
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
