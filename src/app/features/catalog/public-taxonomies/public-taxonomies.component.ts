import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { form, FormField, required, submit, validate } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import {
  isValidTaxonomyCode,
  suggestTaxonomyCode,
  type PublicTaxonomyValue,
  type TaxonomyKind,
} from '../../../core/catalog/models/public-agency-config.model';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { AuthService } from '../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../core/auth/models/user.model';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../shared/components/unsaved-changes.guard';

const KIND_COPY: Readonly<
  Record<TaxonomyKind, { tab: string; singular: string; create: string; example: string }>
> = {
  lodging_type: {
    tab: 'Tipos de alojamiento',
    singular: 'tipo',
    create: 'Nuevo tipo de alojamiento',
    example: 'glamping',
  },
  amenity: {
    tab: 'Amenidades',
    singular: 'amenidad',
    create: 'Nueva amenidad',
    example: 'vista_al_mar',
  },
};

const EMPTY_DRAFT = { code: '', nameEs: '', nameEn: '' };

/**
 * Agency-owned lodging types and amenities (feature 016, US1). Operator/Admin manage them;
 * a value used by listings can be deactivated but never deleted (FR-008).
 */
@Component({
  selector: 'app-public-taxonomies',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header class="page-head">
        <a routerLink="/cms/settings">Ajustes del catálogo</a>
        <h1>Tipos y amenidades</h1>
        <p class="hint">
          Lo que eligen las fichas de alojamiento y lo que el sitio muestra en español e inglés.
          Cada agencia tiene su propia lista.
        </p>
      </header>

      <div class="tabs" role="tablist" aria-label="Lista">
        @for (option of kinds; track option) {
          <button
            type="button"
            role="tab"
            [attr.aria-selected]="kind() === option"
            [class.active]="kind() === option"
            (click)="selectKind(option)"
          >
            {{ copy[option].tab }}
            <span class="count">{{ countOf(option) }}</span>
          </button>
        }
      </div>

      @if (loading()) {
        <app-spinner label="Cargando valores…" />
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
              @for (value of visible(); track value.id) {
                <tr [class.muted]="!value.is_active">
                  <td>
                    <code>{{ value.code }}</code>
                    @if (value.in_use) {
                      <span class="badge" title="Lo usa al menos una ficha">En uso</span>
                    }
                  </td>
                  <td>{{ value.name_es }}</td>
                  <td>{{ value.name_en }}</td>
                  <td>{{ value.is_active ? 'Activo' : 'Inactivo' }}</td>
                  @if (canManage()) {
                    <td class="row-actions">
                      <button type="button" class="link" (click)="onEdit(value)">Editar</button>
                      <button type="button" class="link" (click)="onToggle(value)">
                        {{ value.is_active ? 'Desactivar' : 'Activar' }}
                      </button>
                      @if (!value.in_use) {
                        <button type="button" class="link danger" (click)="onDelete(value)">
                          Eliminar
                        </button>
                      }
                    </td>
                  }
                </tr>
              } @empty {
                <tr>
                  <td colspan="5">No hay valores en esta lista.</td>
                </tr>
              }
            </tbody>
          </table>
        </div>

        @if (canManage()) {
          <form class="card" (submit)="onSave($event)" novalidate>
            <h2>{{ editing() ? 'Editar «' + editing()!.code + '»' : copy[kind()].create }}</h2>
            <div class="form-grid">
              <div class="field req">
                <label for="tax-es">Nombre en español</label>
                <input
                  id="tax-es"
                  type="text"
                  [formField]="valueForm.nameEs"
                  (blur)="suggestCode()"
                />
                @if (valueForm.nameEs().touched() && valueForm.nameEs().invalid()) {
                  <p class="field-error">Ingresa el nombre en español.</p>
                }
              </div>
              <div class="field req">
                <label for="tax-en">Nombre en inglés</label>
                <input id="tax-en" type="text" [formField]="valueForm.nameEn" />
                @if (valueForm.nameEn().touched() && valueForm.nameEn().invalid()) {
                  <p class="field-error">Ingresa el nombre en inglés.</p>
                }
              </div>
              @if (!editing()) {
                <div class="field req">
                  <label for="tax-code">Identificador</label>
                  <input id="tax-code" type="text" [formField]="valueForm.code" />
                  @if (valueForm.code().touched() && valueForm.code().invalid()) {
                    <p class="field-error">
                      Usa minúsculas, números y guion bajo, p. ej. «{{ copy[kind()].example }}».
                    </p>
                  } @else {
                    <p class="hint">Es lo que guarda la ficha. No cambia después.</p>
                  }
                </div>
              }
            </div>
            <div class="form-actions">
              <button class="primary" type="submit" [disabled]="valueForm().submitting()">
                {{
                  valueForm().submitting() ? 'Guardando…' : editing() ? 'Guardar cambios' : 'Crear'
                }}
              </button>
              @if (editing()) {
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

    .tabs {
      display: flex;
      gap: 0.25rem;
      border-bottom: 1px solid var(--color-border);
      overflow-x: auto;
    }

    .tabs button {
      border: 0;
      border-bottom: 2px solid transparent;
      border-radius: 0;
      background: none;
      padding: 0.6rem 0.9rem;
      font-weight: 600;
      color: var(--color-text-muted);
      white-space: nowrap;
    }

    .tabs button.active {
      color: var(--color-text);
      border-bottom-color: var(--color-primary);
    }

    .count {
      margin-left: 0.35rem;
      font-weight: 400;
      font-size: 0.8rem;
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
      background: var(--color-surface-sunken);
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
export class PublicTaxonomiesComponent implements UnsavedChangesHost {
  private readonly api = inject(PublicAgencyConfigService);
  private readonly auth = inject(AuthService);

  protected readonly kinds: readonly TaxonomyKind[] = ['lodging_type', 'amenity'];
  protected readonly copy = KIND_COPY;

  protected readonly kind = signal<TaxonomyKind>('lodging_type');
  protected readonly values = signal<PublicTaxonomyValue[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly editing = signal<PublicTaxonomyValue | null>(null);

  protected readonly canManage = computed(() => hasRoleAtLeast(this.auth.role(), 'operator'));
  protected readonly visible = computed(() =>
    this.values().filter((value) => value.kind === this.kind()),
  );

  protected readonly draft = signal({ ...EMPTY_DRAFT });

  protected readonly valueForm = form(this.draft, (fields) => {
    required(fields.nameEs);
    required(fields.nameEn);
    validate(fields.code, ({ value }) =>
      this.editing() || isValidTaxonomyCode(value().trim())
        ? undefined
        : { kind: 'code', message: 'Identificador inválido' },
    );
  });

  constructor() {
    void this.refresh();
  }

  hasUnsavedChanges(): boolean {
    const draft = this.draft();
    return Boolean(draft.code.trim() || draft.nameEs.trim() || draft.nameEn.trim());
  }

  protected countOf(kind: TaxonomyKind): number {
    return this.values().filter((value) => value.kind === kind && value.is_active).length;
  }

  protected selectKind(kind: TaxonomyKind): void {
    this.kind.set(kind);
    this.cancelEdit();
    this.notice.set(null);
    this.actionError.set(null);
  }

  protected suggestCode(): void {
    const draft = this.draft();
    if (!this.editing() && !draft.code.trim() && draft.nameEs.trim()) {
      this.draft.update((current) => ({ ...current, code: suggestTaxonomyCode(draft.nameEs) }));
    }
  }

  protected onEdit(value: PublicTaxonomyValue): void {
    this.notice.set(null);
    this.actionError.set(null);
    this.editing.set(value);
    this.draft.set({ code: value.code, nameEs: value.name_es, nameEn: value.name_en });
  }

  protected cancelEdit(): void {
    this.editing.set(null);
    this.draft.set({ ...EMPTY_DRAFT });
    this.valueForm().reset();
  }

  protected async onSave(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.valueForm, async (fields) => {
      const editing = this.editing();
      try {
        await this.api.saveTaxonomyValue({
          kind: this.kind(),
          code: editing?.code ?? fields.code().value().trim().toLowerCase(),
          name_es: fields.nameEs().value().trim(),
          name_en: fields.nameEn().value().trim(),
          is_active: editing?.is_active ?? true,
        });
        this.cancelEdit();
        await this.refresh();
        this.notice.set(editing ? 'Los cambios se guardaron.' : 'El valor se creó.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onToggle(value: PublicTaxonomyValue): Promise<void> {
    this.actionError.set(null);
    this.notice.set(null);
    try {
      await this.api.saveTaxonomyValue({
        kind: value.kind,
        code: value.code,
        name_es: value.name_es,
        name_en: value.name_en,
        is_active: !value.is_active,
      });
      await this.refresh();
      this.notice.set(
        value.is_active
          ? value.in_use
            ? `«${value.name_es}» quedó inactivo. Las fichas que ya lo tienen lo siguen mostrando; no se podrá elegir de nuevo.`
            : `«${value.name_es}» quedó inactivo.`
          : `«${value.name_es}» está activo de nuevo.`,
      );
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    }
  }

  protected async onDelete(value: PublicTaxonomyValue): Promise<void> {
    this.actionError.set(null);
    this.notice.set(null);
    if (!confirm(`¿Eliminar «${value.name_es}»? Esta acción no se puede deshacer.`)) {
      return;
    }
    try {
      await this.api.deleteTaxonomyValue(value.kind, value.code);
      if (this.editing()?.id === value.id) {
        this.cancelEdit();
      }
      await this.refresh();
      this.notice.set(`«${value.name_es}» se eliminó.`);
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    }
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.values.set(await this.api.listTaxonomy());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
