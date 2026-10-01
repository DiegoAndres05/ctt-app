import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type {
  PackageConsistency,
  ProductType,
} from '../../../../core/catalog/models/product.model';
import {
  ProductService,
  type PackageDetail,
  type ProductListItem,
} from '../../../../core/catalog/services/product.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { ListingPreviewCardComponent } from '../../../../shared/components/listing-preview/listing-preview-card.component';
import {
  toPreviewListing,
  type PreviewLocale,
} from '../../../../shared/components/listing-preview/preview-listing.model';
import type { UnsavedChangesHost } from '../../../../shared/components/unsaved-changes.guard';

interface BuilderItem {
  component_product_id: string;
  name: string;
  type: ProductType;
  day_number: number | null;
  sort_order: number;
}

/**
 * Compose a predefined package: select experiences/accommodations and set itinerary day/night
 * (User Story 3). Nested packages are rejected by `create_package`.
 */
@Component({
  selector: 'app-package-builder',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent, ListingPreviewCardComponent],
  template: `
    <div class="editor-layout">
    <main class="editor-main">
      <a routerLink="/cms/packages">Cancelar</a>

      @if (loading()) {
        <app-spinner label="Cargando paquete…" />
      } @else if (loadError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else {
        @if (consistencyWarning(); as warning) {
          <app-alert kind="info">{{ warning }}</app-alert>
        }

        @if (existing(); as pkg) {
          <section class="card">
            <h1>{{ pkg.name }}</h1>
            <dl>
              <dt>Estado</dt>
              <dd>{{ pkg.status === 'draft' ? 'Borrador' : pkg.status === 'active' ? 'Activo' : 'Inactivo' }}</dd>
              <dt>Días</dt>
              <dd>{{ pkg.package.total_days ?? '—' }}</dd>
              <dt>Noches</dt>
              <dd>{{ pkg.package.total_nights ?? '—' }}</dd>
            </dl>
            <h2>Itinerario</h2>
            <ul>
              @for (item of pkg.items; track item.id) {
                <li>
                  Día {{ item.day_number ?? '—' }} · {{ componentName(item.component_product_id) }}
                </li>
              }
            </ul>
          </section>
        } @else {
          <form class="card" (submit)="onSubmit($event)" novalidate>
            <h1>Nuevo paquete</h1>
            <p class="notice">
              El precio del paquete se define de forma explícita en la ficha del producto, no como
              suma de componentes.
            </p>

            <label class="req" for="name">Nombre</label>
            <input id="name" type="text" [formField]="builderForm.name" />
            @if (builderForm.name().touched() && builderForm.name().invalid()) {
              <p class="field-error">Ingresa el nombre del paquete.</p>
            }

            <label for="description">Descripción</label>
            <textarea id="description" rows="3" [formField]="builderForm.description"></textarea>

            <label for="total-days">Días de itinerario</label>
            <input id="total-days" type="number" [formField]="builderForm.totalDays" />

            <label for="total-nights">Noches de itinerario</label>
            <input id="total-nights" type="number" [formField]="builderForm.totalNights" />

            <fieldset>
              <legend>Componentes</legend>
              <p class="notice">Selecciona experiencias o alojamientos y el día del itinerario.</p>

              <label for="component">Producto</label>
              <select id="component" [formField]="builderForm.pickerProductId">
                <option value="">Selecciona un componente</option>
                @for (product of candidates(); track product.id) {
                  <option [value]="product.id">{{ product.name }} ({{ typeLabel(product.type) }})</option>
                }
              </select>

              <label for="day-number">Día</label>
              <input id="day-number" type="number" [formField]="builderForm.pickerDayNumber" />

              <button type="button" (click)="addItem()">Añadir al itinerario</button>

              @if (items().length === 0) {
                <p class="notice">Aún no hay componentes en el paquete.</p>
              } @else {
                <ul>
                  @for (item of items(); track item.sort_order + item.component_product_id) {
                    <li>
                      Día {{ item.day_number ?? '—' }} · {{ item.name }} ({{ typeLabel(item.type) }})
                      <button type="button" (click)="removeItem(item.sort_order)">Quitar</button>
                    </li>
                  }
                </ul>
              }
            </fieldset>

            <div class="actions">
              <button class="primary" type="submit" [disabled]="builderForm().submitting()">
                {{ builderForm().submitting() ? 'Guardando…' : 'Guardar borrador' }}
              </button>
              <a class="button-link" routerLink="/cms/packages">Cancelar</a>
            </div>

            @if (error(); as failure) {
              <app-alert kind="error">{{ failure.message }}</app-alert>
            }
          </form>
        }
      }
    </main>
    <aside class="preview-column">
      <div class="locale-toggle" role="group" aria-label="Idioma de la vista previa">
        <button type="button" [class.primary]="previewLocale() === 'es'" (click)="previewLocale.set('es')">ES</button>
        <button type="button" [class.primary]="previewLocale() === 'en'" (click)="previewLocale.set('en')">EN</button>
      </div>
      <app-listing-preview-card [listing]="preview()" />
    </aside>
    </div>
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
      width: min(36rem, 100%);
    }

    label,
    legend {
      font-weight: 600;
    }

    fieldset {
      border: 1px solid #ddd;
      padding: 0.75rem;
      display: grid;
      gap: 0.35rem;
    }

    .notice {
      margin: 0;
      font-weight: 400;
    }

    .field-error {
      color: #b3261e;
      margin: 0;
    }

    ul {
      margin: 0;
      padding-left: 1.2rem;
      display: grid;
      gap: 0.35rem;
    }

    dl {
      display: grid;
      grid-template-columns: auto 1fr;
      gap: 0.25rem 1rem;
    }

    dt {
      font-weight: 600;
    }

    dd {
      margin: 0;
    }

    button {
      margin-top: 0.5rem;
      padding: 0.6rem 1rem;
    }
  `,
})
export class PackageBuilderComponent implements UnsavedChangesHost {
  private readonly productsApi = inject(ProductService);
  private readonly router = inject(Router);

  /** Bound from the `:id` route param when viewing an existing package. */
  readonly id = input<string | undefined>();

  protected readonly loading = signal(true);
  protected readonly loadError = signal<AppError | null>(null);
  protected readonly error = signal<AppError | null>(null);
  protected readonly candidates = signal<ProductListItem[]>([]);
  protected readonly items = signal<BuilderItem[]>([]);
  protected readonly existing = signal<PackageDetail | null>(null);
  protected readonly existingConsistency = signal<PackageConsistency | null>(null);
  protected readonly previewLocale = signal<PreviewLocale>('es');
  private allowLeave = false;

  protected readonly preview = computed(() => {
    const existing = this.existing();
    const locale = this.previewLocale();
    return toPreviewListing({
      variant: 'catalog',
      locale,
      titleEs: existing?.name ?? this.draft().name,
      titleEn: '',
      descriptionEs: existing?.description ?? this.draft().description,
      descriptionEn: '',
      categoryLabelEs: '',
      categoryLabelEn: '',
      location: '',
      imageUrl: null,
      displayPrice: null,
      currency: 'COP',
      soldOut: false,
    });
  });

  protected readonly draft = signal({
    name: '',
    description: '',
    totalDays: 1,
    totalNights: 0,
    pickerProductId: '',
    pickerDayNumber: 1,
  });

  protected readonly builderForm = form(this.draft, (fields) => {
    required(fields.name);
  });

  constructor() {
    effect(() => {
      const id = this.id();
      untracked(() => {
        void this.bootstrap(id);
      });
    });
  }

  hasUnsavedChanges(): boolean {
    if (this.allowLeave || this.existing()) {
      return false;
    }
    return this.draft().name.trim().length > 0 || this.draft().description.trim().length > 0 || this.items().length > 0;
  }

  protected typeLabel(type: ProductType): string {
    switch (type) {
      case 'experience':
        return 'Experiencia';
      case 'accommodation':
        return 'Alojamiento';
      case 'package':
        return 'Paquete';
    }
  }

  protected componentName(productId: string): string {
    return this.candidates().find((product) => product.id === productId)?.name ?? productId;
  }

  protected consistencyWarning(): string | null {
    const report = this.existingConsistency();
    if (!report || report.consistent) {
      return null;
    }
    const names = report.inactive_components.map((component) => component.name).join(', ');
    return names
      ? `Este paquete es inconsistente porque tiene componentes inactivos: ${names}. El paquete no se desactiva automáticamente.`
      : 'Este paquete es inconsistente porque tiene componentes inactivos. El paquete no se desactiva automáticamente.';
  }

  protected addItem(): void {
    this.error.set(null);
    const productId = this.builderForm.pickerProductId().value();
    const dayNumber = this.builderForm.pickerDayNumber().value();
    const product = this.candidates().find((candidate) => candidate.id === productId);
    if (!product) {
      this.error.set(toAppError(new Error('VALIDATION_ERROR')));
      return;
    }
    if (product.type === 'package') {
      this.error.set(toAppError(new Error('PACKAGE_NESTING_NOT_ALLOWED')));
      return;
    }
    const next = this.items();
    this.items.set([
      ...next,
      {
        component_product_id: product.id,
        name: product.name,
        type: product.type,
        day_number: dayNumber >= 1 ? dayNumber : null,
        sort_order: next.length,
      },
    ]);
  }

  protected removeItem(sortOrder: number): void {
    this.items.set(
      this.items()
        .filter((item) => item.sort_order !== sortOrder)
        .map((item, index) => ({ ...item, sort_order: index })),
    );
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);

    await submit(this.builderForm, async (fields) => {
      try {
        const selected = this.items();
        if (selected.length === 0) {
          this.error.set(toAppError(new Error('VALIDATION_ERROR')));
          return undefined;
        }

        const created = await this.productsApi.createPackage({
          name: fields.name().value(),
          description: fields.description().value(),
          totalDays: fields.totalDays().value(),
          totalNights: fields.totalNights().value(),
          items: selected.map((item) => ({
            component_product_id: item.component_product_id,
            sort_order: item.sort_order,
            day_number: item.day_number,
          })),
        });
        this.allowLeave = true;
        await this.router.navigate(['/cms/packages', created.id]);
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }

  private async bootstrap(id: string | undefined): Promise<void> {
    this.loading.set(true);
    this.loadError.set(null);
    this.error.set(null);
    try {
      const [experiences, accommodations] = await Promise.all([
        this.productsApi.list({ type: 'experience' }),
        this.productsApi.list({ type: 'accommodation' }),
      ]);
      this.candidates.set([...experiences, ...accommodations]);

      if (!id) {
        this.existing.set(null);
        this.existingConsistency.set(null);
        return;
      }

      const detail = await this.productsApi.getPackageById(id);
      if (!detail) {
        this.loadError.set(toAppError(new Error('VALIDATION_ERROR')));
        return;
      }
      this.existing.set(detail);
      const reports = await this.productsApi.getPackageConsistency(id);
      this.existingConsistency.set(reports[0] ?? null);
    } catch (failure) {
      this.loadError.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
