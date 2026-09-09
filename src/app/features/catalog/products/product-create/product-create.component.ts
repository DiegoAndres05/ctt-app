import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type { Category } from '../../../../core/catalog/models/category.model';
import type { ExperienceDifficulty, ProductType } from '../../../../core/catalog/models/product.model';
import { CategoryService } from '../../../../core/catalog/services/category.service';
import { ProductService } from '../../../../core/catalog/services/product.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

type CreateProductType = Exclude<ProductType, 'package'>;

/**
 * Register an experience or accommodation in draft (User Story 1).
 */
@Component({
  selector: 'app-product-create',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <a routerLink="/catalog/products">Volver a productos</a>

      @if (loadingCategories()) {
        <app-spinner label="Cargando categorías…" />
      } @else {
        <form class="card" (submit)="onSubmit($event)" novalidate>
          <h1>Nuevo producto</h1>

          <label for="type">Tipo</label>
          <select id="type" [formField]="createForm.type">
            <option value="experience">Experiencia</option>
            <option value="accommodation">Alojamiento</option>
          </select>

          <label for="name">Nombre</label>
          <input id="name" type="text" [formField]="createForm.name" />
          @if (createForm.name().touched() && createForm.name().invalid()) {
            <p class="field-error">Ingresa el nombre del producto.</p>
          }

          <label for="description">Descripción</label>
          <textarea id="description" rows="3" [formField]="createForm.description"></textarea>

          <fieldset>
            <legend>Categorías</legend>
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
          </fieldset>

          @if (createForm.type().value() === 'experience') {
            <label for="duration">Duración (minutos)</label>
            <input id="duration" type="number" [formField]="createForm.durationMinutes" />

            <label for="difficulty">Dificultad</label>
            <select id="difficulty" [formField]="createForm.difficulty">
              <option value="">Sin especificar</option>
              <option value="easy">Fácil</option>
              <option value="moderate">Moderada</option>
              <option value="hard">Difícil</option>
            </select>

            <label for="meeting-point">Punto de encuentro</label>
            <input id="meeting-point" type="text" [formField]="createForm.meetingPoint" />

            <label for="min-capacity">Capacidad mínima</label>
            <input id="min-capacity" type="number" [formField]="createForm.minCapacity" />

            <label for="max-capacity">Capacidad máxima</label>
            <input id="max-capacity" type="number" [formField]="createForm.maxCapacity" />
          } @else {
            <label for="property-type">Tipo de inmueble</label>
            <input id="property-type" type="text" [formField]="createForm.propertyType" />
            @if (createForm.propertyType().touched() && createForm.propertyType().invalid()) {
              <p class="field-error">Ingresa el tipo de inmueble.</p>
            }

            <label for="location">Ubicación</label>
            <input id="location" type="text" [formField]="createForm.location" />
            @if (createForm.location().touched() && createForm.location().invalid()) {
              <p class="field-error">Ingresa la ubicación.</p>
            }

            <label for="check-in">Check-in</label>
            <input id="check-in" type="time" [formField]="createForm.checkIn" />

            <label for="check-out">Check-out</label>
            <input id="check-out" type="time" [formField]="createForm.checkOut" />

            <label for="max-occupancy">Ocupación máxima</label>
            <input id="max-occupancy" type="number" [formField]="createForm.maxOccupancy" />
          }

          <button type="submit" [disabled]="createForm().submitting()">
            {{ createForm().submitting() ? 'Creando…' : 'Crear producto' }}
          </button>

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
      width: min(32rem, 100%);
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
export class ProductCreateComponent {
  private readonly productsApi = inject(ProductService);
  private readonly categoriesApi = inject(CategoryService);
  private readonly router = inject(Router);

  protected readonly categories = signal<Category[]>([]);
  protected readonly selectedCategoryIds = signal<string[]>([]);
  protected readonly loadingCategories = signal(true);
  protected readonly error = signal<AppError | null>(null);

  protected readonly draft = signal({
    type: 'experience' as CreateProductType,
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

  protected readonly createForm = form(this.draft, (fields) => {
    required(fields.type);
    required(fields.name);
  });

  constructor() {
    void this.loadCategories();
  }

  protected toggleCategory(id: string): void {
    const current = this.selectedCategoryIds();
    this.selectedCategoryIds.set(
      current.includes(id) ? current.filter((item) => item !== id) : [...current, id],
    );
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.error.set(null);

    await submit(this.createForm, async (fields) => {
      const type = fields.type().value();
      try {
        if (type === 'experience') {
          const minCapacity = fields.minCapacity().value();
          const maxCapacity = fields.maxCapacity().value();
          if (maxCapacity < minCapacity) {
            this.error.set(toAppError(new Error('VALIDATION_ERROR')));
            return undefined;
          }
        } else {
          if (!fields.propertyType().value().trim() || !fields.location().value().trim()) {
            this.error.set(toAppError(new Error('VALIDATION_ERROR')));
            return undefined;
          }
        }

        const created = await this.productsApi.create({
          type,
          name: fields.name().value(),
          description: fields.description().value(),
          categoryIds: this.selectedCategoryIds(),
          experience:
            type === 'experience'
              ? {
                  duration_minutes: fields.durationMinutes().value(),
                  difficulty: (fields.difficulty().value() || null) as ExperienceDifficulty | null,
                  meeting_point: fields.meetingPoint().value() || null,
                  min_capacity: fields.minCapacity().value(),
                  max_capacity: fields.maxCapacity().value(),
                }
              : undefined,
          accommodation:
            type === 'accommodation'
              ? {
                  property_type: fields.propertyType().value(),
                  location: fields.location().value(),
                  check_in: fields.checkIn().value() || null,
                  check_out: fields.checkOut().value() || null,
                  max_occupancy: fields.maxOccupancy().value(),
                }
              : undefined,
        });
        await this.router.navigate(['/catalog/products', created.id]);
      } catch (failure) {
        this.error.set(toAppError(failure));
      }
      return undefined;
    });
  }

  private async loadCategories(): Promise<void> {
    this.loadingCategories.set(true);
    try {
      this.categories.set(await this.categoriesApi.list());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loadingCategories.set(false);
    }
  }
}
