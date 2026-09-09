import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type { Category } from '../../../../core/catalog/models/category.model';
import type {
  ExperienceDifficulty,
  ProductStatus,
} from '../../../../core/catalog/models/product.model';
import { CategoryService } from '../../../../core/catalog/services/category.service';
import { AddonService } from '../../../../core/catalog/services/addon.service';
import type { Addon, ProductAddonWithAddon } from '../../../../core/catalog/models/addon.model';
import {
  ProductService,
  type ProductDetail,
} from '../../../../core/catalog/services/product.service';
import { AuthService } from '../../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { PricingEditorComponent } from '../../pricing/pricing-editor/pricing-editor.component';

/**
 * Product detail: attributes, logical status, categories (User Story 1), eligible add-ons
 * (User Story 2), and pricing definition / admin override (User Story 4).
 */
@Component({
  selector: 'app-product-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, FormField, RouterLink, AlertComponent, SpinnerComponent, PricingEditorComponent],
  template: `
    <main class="page">
      <a routerLink="/catalog/products">Volver a productos</a>

      @if (loading()) {
        <app-spinner label="Cargando producto…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (product(); as item) {
        <h1>{{ item.name }}</h1>
        <dl>
          <dt>Tipo</dt>
          <dd>{{ item.type === 'experience' ? 'Experiencia' : item.type === 'accommodation' ? 'Alojamiento' : 'Paquete' }}</dd>
          <dt>Estado</dt>
          <dd>{{ statusLabel(item.status) }}</dd>
          <dt>Alta</dt>
          <dd>{{ item.created_at | date: 'short' }}</dd>
        </dl>

        <form class="card" (submit)="onSaveAttributes($event)" novalidate>
          <h2>Atributos</h2>
          <label for="name">Nombre</label>
          <input id="name" type="text" [formField]="attrForm.name" />

          <label for="description">Descripción</label>
          <textarea id="description" rows="3" [formField]="attrForm.description"></textarea>

          @if (item.type === 'experience') {
            <label for="duration">Duración (minutos)</label>
            <input id="duration" type="number" [formField]="attrForm.durationMinutes" />

            <label for="difficulty">Dificultad</label>
            <select id="difficulty" [formField]="attrForm.difficulty">
              <option value="">Sin especificar</option>
              <option value="easy">Fácil</option>
              <option value="moderate">Moderada</option>
              <option value="hard">Difícil</option>
            </select>

            <label for="meeting-point">Punto de encuentro</label>
            <input id="meeting-point" type="text" [formField]="attrForm.meetingPoint" />

            <label for="min-capacity">Capacidad mínima</label>
            <input id="min-capacity" type="number" [formField]="attrForm.minCapacity" />

            <label for="max-capacity">Capacidad máxima</label>
            <input id="max-capacity" type="number" [formField]="attrForm.maxCapacity" />
          }

          @if (item.type === 'accommodation') {
            <label for="property-type">Tipo de inmueble</label>
            <input id="property-type" type="text" [formField]="attrForm.propertyType" />

            <label for="location">Ubicación</label>
            <input id="location" type="text" [formField]="attrForm.location" />

            <label for="check-in">Check-in</label>
            <input id="check-in" type="time" [formField]="attrForm.checkIn" />

            <label for="check-out">Check-out</label>
            <input id="check-out" type="time" [formField]="attrForm.checkOut" />

            <label for="max-occupancy">Ocupación máxima</label>
            <input id="max-occupancy" type="number" [formField]="attrForm.maxOccupancy" />
          }

          <button type="submit" [disabled]="attrForm().submitting()">
            {{ attrForm().submitting() ? 'Guardando…' : 'Guardar atributos' }}
          </button>
        </form>

        <app-pricing-editor [productId]="item.id" [allowOverride]="canOverridePrice()" />

        <form class="card" (submit)="onSaveStatus($event)" novalidate>
          <h2>Estado comercial</h2>
          <p class="notice">
            Un producto solo puede activarse si tiene un esquema de precio vigente.
          </p>
          <label for="status">Estado</label>
          <select id="status" [formField]="statusForm.status">
            <option value="active">Activo</option>
            <option value="inactive">Inactivo</option>
          </select>
          <button type="submit" [disabled]="statusForm().submitting()">
            {{ statusForm().submitting() ? 'Actualizando…' : 'Actualizar estado' }}
          </button>
        </form>

        <form class="card" (submit)="onSaveCategories($event)" novalidate>
          <h2>Categorías</h2>
          @for (category of categories(); track category.id) {
            <label class="check">
              <input
                type="checkbox"
                [checked]="selectedCategoryIds().includes(category.id)"
                (change)="toggleCategory(category.id)"
              />
              {{ category.name }}
            </label>
          }
          <button type="submit">Guardar categorías</button>
        </form>

        <section class="card">
          <h2>Complementos elegibles</h2>
          @if (linkedAddons().length === 0) {
            <p class="notice">Este producto no tiene complementos vinculados.</p>
          } @else {
            <table>
              <thead>
                <tr>
                  <th>Complemento</th>
                  <th>Obligatorio</th>
                  <th>Cantidad máx.</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                @for (link of linkedAddons(); track link.id) {
                  <tr>
                    <td>{{ link.add_ons?.name ?? link.addon_id }}</td>
                    <td>{{ link.is_mandatory ? 'Sí' : 'No' }}</td>
                    <td>{{ link.max_quantity ?? '—' }}</td>
                    <td>
                      <button type="button" (click)="onUnlinkAddon(link.id)">Quitar</button>
                    </td>
                  </tr>
                }
              </tbody>
            </table>
          }

          <form class="link-form" (submit)="onLinkAddon($event)" novalidate>
            <h3>Vincular complemento</h3>
            <label for="addon">Complemento</label>
            <select id="addon" [formField]="linkForm.addonId">
              <option value="">Selecciona un complemento</option>
              @for (addon of availableAddons(); track addon.id) {
                <option [value]="addon.id">{{ addon.name }}</option>
              }
            </select>

            <label class="check" for="mandatory">
              <input id="mandatory" type="checkbox" [formField]="linkForm.isMandatory" />
              Obligatorio
            </label>

            <label for="max-quantity">Cantidad máxima (opcional)</label>
            <input id="max-quantity" type="number" [formField]="linkForm.maxQuantity" />

            <button type="submit" [disabled]="linkForm().submitting() || availableAddons().length === 0">
              {{ linkForm().submitting() ? 'Vinculando…' : 'Vincular' }}
            </button>
          </form>
        </section>

        @if (actionError(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }
        @if (notice(); as message) {
          <app-alert kind="success">{{ message }}</app-alert>
        }
      } @else {
        <app-alert kind="info">
          El producto no existe o no pertenece a tu organización.
        </app-alert>
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
      margin: 0;
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

    .card {
      display: grid;
      gap: 0.5rem;
      width: min(32rem, 100%);
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

    .notice {
      margin: 0;
    }

    button {
      margin-top: 0.25rem;
      padding: 0.6rem 1rem;
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    th,
    td {
      text-align: left;
      padding: 0.35rem 0.4rem;
      border-bottom: 1px solid #ddd;
    }

    .link-form {
      display: grid;
      gap: 0.5rem;
    }

    h3 {
      margin: 0.5rem 0 0;
    }
  `,
})
export class ProductDetailComponent {
  private readonly productsApi = inject(ProductService);
  private readonly categoriesApi = inject(CategoryService);
  private readonly addonsApi = inject(AddonService);
  private readonly auth = inject(AuthService);

  /** Bound from the `:id` route param. */
  readonly id = input.required<string>();

  protected readonly product = signal<ProductDetail | null>(null);
  protected readonly categories = signal<Category[]>([]);
  protected readonly selectedCategoryIds = signal<string[]>([]);
  protected readonly catalogAddons = signal<Addon[]>([]);
  protected readonly linkedAddons = signal<ProductAddonWithAddon[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);

  protected readonly attrDraft = signal({
    name: '',
    description: '',
    durationMinutes: 60,
    difficulty: '' as ExperienceDifficulty | '',
    meetingPoint: '',
    minCapacity: 1,
    maxCapacity: 10,
    propertyType: '',
    location: '',
    checkIn: '',
    checkOut: '',
    maxOccupancy: 2,
  });

  protected readonly statusDraft = signal({
    status: 'inactive' as Extract<ProductStatus, 'active' | 'inactive'>,
  });

  protected readonly attrForm = form(this.attrDraft, (fields) => {
    required(fields.name);
  });

  protected readonly statusForm = form(this.statusDraft, (fields) => {
    required(fields.status);
  });

  protected readonly linkDraft = signal({
    addonId: '',
    isMandatory: false,
    maxQuantity: 0,
  });

  protected readonly linkForm = form(this.linkDraft, (fields) => {
    required(fields.addonId);
  });

  constructor() {
    effect(() => {
      const id = this.id();
      untracked(() => {
        void this.refresh(id);
      });
    });
  }

  protected statusLabel(status: ProductStatus): string {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'active':
        return 'Activo';
      case 'inactive':
        return 'Inactivo';
    }
  }

  protected canOverridePrice(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'admin');
  }

  protected availableAddons(): Addon[] {
    const linked = new Set(this.linkedAddons().map((row) => row.addon_id));
    return this.catalogAddons().filter((addon) => addon.is_active && !linked.has(addon.id));
  }

  protected toggleCategory(id: string): void {
    const current = this.selectedCategoryIds();
    this.selectedCategoryIds.set(
      current.includes(id) ? current.filter((item) => item !== id) : [...current, id],
    );
  }

  protected async onSaveAttributes(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.attrForm, async (fields) => {
      const item = this.product();
      if (!item) {
        return undefined;
      }
      try {
        await this.productsApi.update(item.id, {
          name: fields.name().value(),
          description: fields.description().value() || null,
          providerId: item.provider_id,
          experience:
            item.type === 'experience'
              ? {
                  duration_minutes: fields.durationMinutes().value(),
                  difficulty: (fields.difficulty().value() || null) as ExperienceDifficulty | null,
                  meeting_point: fields.meetingPoint().value() || null,
                  min_capacity: fields.minCapacity().value(),
                  max_capacity: fields.maxCapacity().value(),
                }
              : undefined,
          accommodation:
            item.type === 'accommodation'
              ? {
                  property_type: fields.propertyType().value(),
                  location: fields.location().value(),
                  check_in: fields.checkIn().value() || null,
                  check_out: fields.checkOut().value() || null,
                  max_occupancy: fields.maxOccupancy().value(),
                  occupancy_rules: item.accommodation?.occupancy_rules ?? null,
                }
              : undefined,
        });
        await this.refresh(item.id);
        this.notice.set('Los atributos se actualizaron.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onSaveStatus(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.statusForm, async (fields) => {
      try {
        const updated = await this.productsApi.setStatus(this.id(), fields.status().value());
        const current = this.product();
        if (current) {
          this.product.set({ ...current, status: updated.status });
        }
        this.notice.set(
          updated.status === 'active'
            ? 'El producto quedó activo en el catálogo comercial.'
            : 'El producto quedó inactivo. No estará disponible para nuevas cotizaciones.',
        );
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onSaveCategories(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);
    try {
      await this.categoriesApi.replaceAssignments(this.id(), this.selectedCategoryIds());
      const current = this.product();
      if (current) {
        this.product.set({ ...current, category_ids: this.selectedCategoryIds() });
      }
      this.notice.set('Las categorías se actualizaron.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    }
  }

  protected async onLinkAddon(event: Event): Promise<void> {
    event.preventDefault();
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.linkForm, async (fields) => {
      try {
        const maxQuantity = fields.maxQuantity().value();
        await this.addonsApi.linkToProduct({
          productId: this.id(),
          addonId: fields.addonId().value(),
          isMandatory: fields.isMandatory().value(),
          maxQuantity: maxQuantity > 0 ? maxQuantity : null,
        });
        this.linkDraft.set({ addonId: '', isMandatory: false, maxQuantity: 0 });
        this.linkedAddons.set(await this.addonsApi.listForProduct(this.id()));
        this.notice.set('El complemento quedó vinculado al producto.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onUnlinkAddon(linkId: string): Promise<void> {
    this.actionError.set(null);
    this.notice.set(null);
    try {
      await this.addonsApi.unlinkFromProduct(linkId);
      this.linkedAddons.set(await this.addonsApi.listForProduct(this.id()));
      this.notice.set('El complemento se desvinculó del producto.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    }
  }

  private async refresh(id: string): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.actionError.set(null);
    this.notice.set(null);
    try {
      const [item, taxonomy, addons, links] = await Promise.all([
        this.productsApi.getById(id),
        this.categoriesApi.list(),
        this.addonsApi.list(),
        this.addonsApi.listForProduct(id),
      ]);
      this.product.set(item);
      this.categories.set(taxonomy);
      this.catalogAddons.set(addons);
      this.linkedAddons.set(links);
      if (item) {
        this.selectedCategoryIds.set(item.category_ids);
        this.statusDraft.set({
          status: item.status === 'active' ? 'active' : 'inactive',
        });
        this.attrDraft.set({
          name: item.name,
          description: item.description ?? '',
          durationMinutes: item.experience?.duration_minutes ?? 60,
          difficulty: item.experience?.difficulty ?? '',
          meetingPoint: item.experience?.meeting_point ?? '',
          minCapacity: item.experience?.min_capacity ?? 1,
          maxCapacity: item.experience?.max_capacity ?? 10,
          propertyType: item.accommodation?.property_type ?? '',
          location: item.accommodation?.location ?? '',
          checkIn: toTimeInput(item.accommodation?.check_in),
          checkOut: toTimeInput(item.accommodation?.check_out),
          maxOccupancy: item.accommodation?.max_occupancy ?? 2,
        });
      }
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}

function toTimeInput(value: string | null | undefined): string {
  if (!value) {
    return '';
  }
  return value.length >= 5 ? value.slice(0, 5) : value;
}
