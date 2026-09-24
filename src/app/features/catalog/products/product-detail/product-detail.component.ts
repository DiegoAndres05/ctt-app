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
  ProductType,
} from '../../../../core/catalog/models/product.model';
import {
  LODGING_AMENITIES,
  LODGING_TYPES,
  YACHT_ICONS,
  type BilingualPair,
  type GuestReview,
  type LodgingAmenity,
  type LodgingDetails,
  type LodgingType,
  type PublicCategory,
  type PublicImage,
  type PublicListing,
  type PublicPlacement,
  type YachtIcon,
  type YachtLine,
} from '../../../../core/catalog/models/public-listing.model';
import { CategoryService } from '../../../../core/catalog/services/category.service';
import { AddonService } from '../../../../core/catalog/services/addon.service';
import type { Addon, ProductAddonWithAddon } from '../../../../core/catalog/models/addon.model';
import {
  ProductService,
  type ProductDetail,
} from '../../../../core/catalog/services/product.service';
import { PublicListingService } from '../../../../core/catalog/services/public-listing.service';
import { AuthService } from '../../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { PricingEditorComponent } from '../../pricing/pricing-editor/pricing-editor.component';

/**
 * Product detail: attributes, logical status, categories (User Story 1), eligible add-ons
 * (User Story 2), pricing (User Story 4), and public listing ficha (feature 009).
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

        <section class="card public-card">
          <h2>Ficha pública</h2>
          <p class="notice">
            Contenido que ve la página pública. El precio de vitrina no versiona la tarifa.
          </p>

          @if (listing(); as pub) {
            <dl class="listing-meta">
              <dt>Estado ficha</dt>
              <dd>{{ listingStatusLabel(pub.status) }}</dd>
              <dt>Portada</dt>
              <dd>{{ pub.cover_image_ref || 'Sin portada' }}</dd>
              @if (pub.first_published_at) {
                <dt>Primera publicación</dt>
                <dd>{{ pub.first_published_at | date: 'short' }}</dd>
              }
            </dl>
          } @else {
            <p class="notice">Aún no hay ficha pública para este producto.</p>
          }

          <fieldset [disabled]="!canEditPublic()">
            <form class="public-form" (submit)="onSavePublicDraft($event)" novalidate>
              <label for="pub-placement">Sección</label>
              @if (slugLocked()) {
                <p class="notice">{{ placementLabel(publicDraft().placement) }} (fija tras publicar)</p>
              } @else {
                <select id="pub-placement" [formField]="publicForm.placement">
                  @for (option of placementOptions(); track option) {
                    <option [value]="option">{{ placementLabel(option) }}</option>
                  }
                </select>
              }

              <label for="pub-slug">Slug público</label>
              @if (slugLocked()) {
                <p class="notice">{{ publicDraft().publicSlug }} (inmutable tras publicar)</p>
              } @else {
                <input id="pub-slug" type="text" [formField]="publicForm.publicSlug" />
              }

              <label for="name-es">Nombre (ES)</label>
              <input id="name-es" type="text" [formField]="publicForm.nameEs" />

              <label for="name-en">Nombre (EN)</label>
              <input id="name-en" type="text" [formField]="publicForm.nameEn" />

              <label for="desc-es">Descripción (ES)</label>
              <textarea id="desc-es" rows="3" [formField]="publicForm.descriptionEs"></textarea>

              <label for="desc-en">Descripción (EN)</label>
              <textarea id="desc-en" rows="3" [formField]="publicForm.descriptionEn"></textarea>

              <label class="check" for="featured">
                <input id="featured" type="checkbox" [formField]="publicForm.featured" />
                Destacada
              </label>

              @if (publicDraft().placement === 'catalog') {
                <label for="pub-category">Categoría pública</label>
                <select id="pub-category" [formField]="publicForm.publicCategoryId">
                  <option value="">Selecciona</option>
                  @for (category of publicCategories(); track category.id) {
                    <option [value]="category.id">{{ category.name_es }} / {{ category.name_en }}</option>
                  }
                </select>

                <label for="pub-location">Ubicación</label>
                <input id="pub-location" type="text" [formField]="publicForm.location" />

                <label for="pub-meeting">Punto de encuentro</label>
                <input id="pub-meeting" type="text" [formField]="publicForm.meetingPoint" />

                <label for="pub-schedule">Horario</label>
                <input id="pub-schedule" type="text" [formField]="publicForm.schedule" />

                <label for="pub-duration">Duración (texto)</label>
                <input id="pub-duration" type="text" [formField]="publicForm.duration" />

                <label for="pub-includes">Inclusiones (una por línea: ES ||| EN)</label>
                <textarea id="pub-includes" rows="4" [formField]="publicForm.includesText"></textarea>
              }

              @if (publicDraft().placement === 'lodging') {
                <label for="lodging-type">Tipo de hospedaje</label>
                <select id="lodging-type" [formField]="publicForm.lodgingType">
                  @for (type of lodgingTypes; track type) {
                    <option [value]="type">{{ type }}</option>
                  }
                </select>

                <label for="loc-es">Ubicación (ES)</label>
                <input id="loc-es" type="text" [formField]="publicForm.locationEs" />

                <label for="loc-en">Ubicación (EN)</label>
                <input id="loc-en" type="text" [formField]="publicForm.locationEn" />

                <label for="hood-es">Barrio (ES)</label>
                <input id="hood-es" type="text" [formField]="publicForm.neighborhoodEs" />

                <label for="hood-en">Barrio (EN)</label>
                <input id="hood-en" type="text" [formField]="publicForm.neighborhoodEn" />

                <label for="bedrooms">Habitaciones</label>
                <input id="bedrooms" type="number" [formField]="publicForm.bedrooms" />

                <label for="bathrooms">Baños</label>
                <input id="bathrooms" type="number" [formField]="publicForm.bathrooms" />

                <label for="max-guests">Huéspedes máx.</label>
                <input id="max-guests" type="number" [formField]="publicForm.maxGuests" />

                <label for="map-url">Mapa (https)</label>
                <input id="map-url" type="url" [formField]="publicForm.mapUrl" />

                <label for="tags">Etiquetas (separadas por coma)</label>
                <input id="tags" type="text" [formField]="publicForm.tagsText" />

                <fieldset class="amenities">
                  <legend>Amenidades</legend>
                  @for (amenity of lodgingAmenities; track amenity) {
                    <label class="check">
                      <input
                        type="checkbox"
                        [checked]="selectedAmenities().includes(amenity)"
                        (change)="toggleAmenity(amenity)"
                      />
                      {{ amenity }}
                    </label>
                  }
                </fieldset>
              }

              @if (publicDraft().placement === 'yacht') {
                <label for="yacht-lines">Líneas de yate (una por línea: kind|icon|ES|||EN)</label>
                <textarea
                  id="yacht-lines"
                  rows="5"
                  [formField]="publicForm.yachtLinesText"
                  placeholder="capacity|people|Hasta 12|||Up to 12"
                ></textarea>
                <p class="hint">kind: capacity o feature. icon opcional ({{ yachtIcons.join(', ') }}).</p>
              }

              @if (publicDraft().placement !== 'yacht' || publicDraft().displayPrice) {
                <label for="display-price">Precio de vitrina</label>
                <input
                  id="display-price"
                  type="number"
                  step="0.01"
                  [formField]="publicForm.displayPrice"
                />

                <label for="original-price">Precio anterior (opcional)</label>
                <input
                  id="original-price"
                  type="number"
                  step="0.01"
                  [formField]="publicForm.originalPrice"
                />

                <label for="currency">Moneda</label>
                <input id="currency" type="text" [formField]="publicForm.currency" />
              } @else {
                <label for="display-price-opt">Precio de vitrina (opcional en yate)</label>
                <input
                  id="display-price-opt"
                  type="number"
                  step="0.01"
                  [formField]="publicForm.displayPrice"
                />

                <label for="currency-opt">Moneda</label>
                <input id="currency-opt" type="text" [formField]="publicForm.currency" />
              }

              <label for="rating">Valoración (0–5)</label>
              <input id="rating" type="number" step="0.1" [formField]="publicForm.rating" />

              <label for="warnings">Avisos (una por línea: ES ||| EN)</label>
              <textarea id="warnings" rows="3" [formField]="publicForm.warningsText"></textarea>

              @if (canEditPublic()) {
                <button type="submit" [disabled]="publicForm().submitting() || publicBusy()">
                  {{ publicForm().submitting() || publicBusy() ? 'Guardando…' : 'Guardar borrador' }}
                </button>
              }
            </form>

            @if (canEditPublic() && listing(); as pub) {
              <div class="actions">
                <button type="button" [disabled]="publicBusy()" (click)="onPublish()">
                  Publicar
                </button>
                @if (pub.status === 'published') {
                  <button type="button" [disabled]="publicBusy()" (click)="onUnpublish()">
                    Despublicar
                  </button>
                  <label class="check">
                    <input
                      type="checkbox"
                      [checked]="pub.sold_out"
                      [disabled]="publicBusy()"
                      (change)="onToggleSoldOut($event)"
                    />
                    Agotado
                  </label>
                }
              </div>

              <div class="cover-block">
                <h3>Imagen de portada</h3>
                <label for="cover-file">Subir archivo (JPEG/PNG/WebP ≤ 10 MB)</label>
                <input
                  id="cover-file"
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  (change)="onCoverFileSelected($event)"
                />

                <label for="cover-ref">O referencia externa</label>
                <div class="row">
                  <input id="cover-ref" type="text" [value]="coverExternalRef()" (input)="onCoverRefInput($event)" />
                  <button type="button" [disabled]="publicBusy() || !coverExternalRef().trim()" (click)="onAttachExternalCover()">
                    Adjuntar
                  </button>
                </div>
              </div>

              @if (pub.placement === 'lodging') {
                <div class="gallery-block">
                  <h3>Galería</h3>
                  @if (images().length === 0) {
                    <p class="notice">Sin imágenes activas.</p>
                  } @else {
                    <ul>
                      @for (image of images(); track image.id) {
                        <li>
                          {{ image.role }} · {{ image.external_ref || image.storage_path }}
                          (orden {{ image.sort_order }})
                        </li>
                      }
                    </ul>
                  }
                  <label for="gallery-file">Añadir a galería</label>
                  <input
                    id="gallery-file"
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    (change)="onGalleryFileSelected($event)"
                  />
                </div>

                <div class="reviews-block">
                  <h3>Opiniones de huéspedes</h3>
                  @if (reviews().length === 0) {
                    <p class="notice">Sin opiniones.</p>
                  } @else {
                    <ul>
                      @for (review of reviews(); track review.id) {
                        <li>
                          {{ review.author }} · {{ review.rating }}/5 · {{ review.reviewed_on }}
                          — {{ review.text_es }}
                        </li>
                      }
                    </ul>
                  }

                  <form class="link-form" (submit)="onSaveReview($event)" novalidate>
                    <label for="rev-author">Autor</label>
                    <input id="rev-author" type="text" [formField]="reviewForm.author" />

                    <label for="rev-rating">Valoración (1–5)</label>
                    <input id="rev-rating" type="number" [formField]="reviewForm.rating" />

                    <label for="rev-date">Fecha</label>
                    <input id="rev-date" type="date" [formField]="reviewForm.reviewedOn" />

                    <label for="rev-es">Texto (ES)</label>
                    <textarea id="rev-es" rows="2" [formField]="reviewForm.textEs"></textarea>

                    <label for="rev-en">Texto (EN)</label>
                    <textarea id="rev-en" rows="2" [formField]="reviewForm.textEn"></textarea>

                    <button type="submit" [disabled]="reviewForm().submitting()">
                      {{ reviewForm().submitting() ? 'Guardando…' : 'Añadir opinión' }}
                    </button>
                  </form>
                </div>
              }
            }
          </fieldset>

          @if (!canEditPublic()) {
            <p class="notice">Tu rol solo puede consultar la ficha pública.</p>
          }
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
    h2,
    h3 {
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

    .card,
    .public-card {
      display: grid;
      gap: 0.5rem;
      width: min(36rem, 100%);
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

    .notice,
    .hint {
      margin: 0;
      font-weight: 400;
    }

    .hint {
      font-size: 0.85rem;
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

    .link-form,
    .public-form,
    .cover-block,
    .gallery-block,
    .reviews-block {
      display: grid;
      gap: 0.5rem;
    }

    .actions,
    .row {
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem;
      align-items: center;
    }

    fieldset {
      border: none;
      margin: 0;
      padding: 0;
      display: grid;
      gap: 0.5rem;
    }

    .amenities {
      display: grid;
      gap: 0.25rem;
    }

    ul {
      margin: 0;
      padding-left: 1.1rem;
    }
  `,
})
export class ProductDetailComponent {
  private readonly productsApi = inject(ProductService);
  private readonly categoriesApi = inject(CategoryService);
  private readonly addonsApi = inject(AddonService);
  private readonly publicApi = inject(PublicListingService);
  private readonly auth = inject(AuthService);

  /** Bound from the `:id` route param. */
  readonly id = input.required<string>();

  protected readonly lodgingTypes = LODGING_TYPES;
  protected readonly lodgingAmenities = LODGING_AMENITIES;
  protected readonly yachtIcons = YACHT_ICONS;

  protected readonly product = signal<ProductDetail | null>(null);
  protected readonly categories = signal<Category[]>([]);
  protected readonly selectedCategoryIds = signal<string[]>([]);
  protected readonly catalogAddons = signal<Addon[]>([]);
  protected readonly linkedAddons = signal<ProductAddonWithAddon[]>([]);
  protected readonly listing = signal<PublicListing | null>(null);
  protected readonly publicCategories = signal<PublicCategory[]>([]);
  protected readonly images = signal<PublicImage[]>([]);
  protected readonly reviews = signal<GuestReview[]>([]);
  protected readonly selectedAmenities = signal<LodgingAmenity[]>([]);
  protected readonly coverExternalRef = signal('');
  protected readonly loading = signal(true);
  protected readonly publicBusy = signal(false);
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

  protected readonly publicDraft = signal(emptyPublicDraft('catalog'));

  protected readonly publicForm = form(this.publicDraft, (fields) => {
    required(fields.publicSlug);
    required(fields.placement);
  });

  protected readonly reviewDraft = signal({
    author: '',
    rating: 5,
    reviewedOn: '',
    textEs: '',
    textEn: '',
  });

  protected readonly reviewForm = form(this.reviewDraft, (fields) => {
    required(fields.author);
    required(fields.textEs);
    required(fields.textEn);
    required(fields.reviewedOn);
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

  protected listingStatusLabel(status: PublicListing['status']): string {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'published':
        return 'Publicada';
      case 'unpublished':
        return 'Despublicada';
    }
  }

  protected placementLabel(placement: PublicPlacement): string {
    switch (placement) {
      case 'catalog':
        return 'Catálogo (ofertas)';
      case 'lodging':
        return 'Alojamiento';
      case 'yacht':
        return 'Yate';
    }
  }

  protected canOverridePrice(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'admin');
  }

  protected canEditPublic(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'operator');
  }

  protected slugLocked(): boolean {
    return this.listing()?.first_published_at != null;
  }

  protected placementOptions(): PublicPlacement[] {
    const type = this.product()?.type;
    if (type === 'accommodation') {
      return ['lodging'];
    }
    if (type === 'package') {
      return ['catalog'];
    }
    if (type === 'experience') {
      return ['catalog', 'yacht'];
    }
    return ['catalog'];
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

  protected toggleAmenity(amenity: LodgingAmenity): void {
    const current = this.selectedAmenities();
    this.selectedAmenities.set(
      current.includes(amenity)
        ? current.filter((item) => item !== amenity)
        : [...current, amenity],
    );
  }

  protected onCoverRefInput(event: Event): void {
    this.coverExternalRef.set((event.target as HTMLInputElement).value);
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

  protected async onSavePublicDraft(event: Event): Promise<void> {
    event.preventDefault();
    if (!this.canEditPublic()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.publicForm, async () => {
      try {
        this.publicBusy.set(true);
        const saved = await this.publicApi.saveListing(this.buildSavePayload());
        await this.refreshPublic(this.id());
        this.notice.set(
          saved.status === 'published'
            ? 'La ficha pública se actualizó (sigue publicada).'
            : 'Borrador de ficha pública guardado.',
        );
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      } finally {
        this.publicBusy.set(false);
      }
      return undefined;
    });
  }

  protected async onPublish(): Promise<void> {
    const listing = this.listing();
    if (!listing || !this.canEditPublic()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    this.publicBusy.set(true);
    try {
      await this.publicApi.saveListing(this.buildSavePayload());
      await this.publicApi.publishListing(listing.id);
      await this.refreshPublic(this.id());
      this.notice.set('La ficha pública quedó publicada.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onUnpublish(): Promise<void> {
    const listing = this.listing();
    if (!listing || !this.canEditPublic()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    this.publicBusy.set(true);
    try {
      await this.publicApi.unpublish(listing.id);
      await this.refreshPublic(this.id());
      this.notice.set('La ficha pública se despublicó.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onToggleSoldOut(event: Event): Promise<void> {
    const listing = this.listing();
    if (!listing || !this.canEditPublic()) {
      return;
    }
    const soldOut = (event.target as HTMLInputElement).checked;
    this.actionError.set(null);
    this.notice.set(null);
    this.publicBusy.set(true);
    try {
      await this.publicApi.setSoldOut(listing.id, soldOut);
      await this.refreshPublic(this.id());
      this.notice.set(soldOut ? 'Marcada como agotada.' : 'Disponible de nuevo para solicitudes.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onCoverFileSelected(event: Event): Promise<void> {
    const listing = this.listing();
    const file = (event.target as HTMLInputElement).files?.[0];
    (event.target as HTMLInputElement).value = '';
    if (!listing || !file || !this.canEditPublic()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    this.publicBusy.set(true);
    try {
      await this.publicApi.uploadAndAttachImage({
        listingId: listing.id,
        role: 'cover',
        file,
      });
      await this.refreshPublic(this.id());
      this.notice.set('Portada actualizada.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onAttachExternalCover(): Promise<void> {
    const listing = this.listing();
    const ref = this.coverExternalRef().trim();
    if (!listing || !ref || !this.canEditPublic()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    this.publicBusy.set(true);
    try {
      await this.publicApi.attachImage({
        listingId: listing.id,
        role: 'cover',
        externalRef: ref,
      });
      this.coverExternalRef.set('');
      await this.refreshPublic(this.id());
      this.notice.set('Portada por referencia externa adjuntada.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onGalleryFileSelected(event: Event): Promise<void> {
    const listing = this.listing();
    const file = (event.target as HTMLInputElement).files?.[0];
    (event.target as HTMLInputElement).value = '';
    if (!listing || !file || !this.canEditPublic()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    this.publicBusy.set(true);
    try {
      const nextOrder = this.images().reduce((max, image) => Math.max(max, image.sort_order), -1) + 1;
      await this.publicApi.uploadAndAttachImage({
        listingId: listing.id,
        role: 'gallery',
        file,
        sortOrder: nextOrder,
      });
      await this.refreshPublic(this.id());
      this.notice.set('Imagen añadida a la galería.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onSaveReview(event: Event): Promise<void> {
    event.preventDefault();
    const listing = this.listing();
    if (!listing || !this.canEditPublic()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);

    await submit(this.reviewForm, async (fields) => {
      try {
        await this.publicApi.saveGuestReview({
          listing_id: listing.id,
          author: fields.author().value().trim(),
          rating: fields.rating().value(),
          reviewed_on: fields.reviewedOn().value(),
          text_es: fields.textEs().value().trim(),
          text_en: fields.textEn().value().trim(),
        });
        this.reviewDraft.set({
          author: '',
          rating: 5,
          reviewedOn: '',
          textEs: '',
          textEn: '',
        });
        this.reviews.set(await this.publicApi.listGuestReviews(listing.id));
        this.notice.set('Opinión guardada.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  private buildSavePayload() {
    const draft = this.publicDraft();
    const placement = draft.placement;
    const displayPrice = optionalNumber(draft.displayPrice);
    const originalPrice = optionalNumber(draft.originalPrice);
    const rating = optionalNumber(draft.rating);

    return {
      product_id: this.id(),
      placement,
      public_slug: draft.publicSlug.trim().toLowerCase(),
      name_es: draft.nameEs.trim() || null,
      name_en: draft.nameEn.trim() || null,
      description_es: draft.descriptionEs.trim() || null,
      description_en: draft.descriptionEn.trim() || null,
      featured: draft.featured,
      rating,
      display_price: displayPrice,
      original_price: originalPrice,
      currency: draft.currency.trim().toUpperCase() || null,
      warnings: parseBilingualLines(draft.warningsText),
      includes: placement === 'catalog' ? parseBilingualLines(draft.includesText) : [],
      public_category_id: placement === 'catalog' ? draft.publicCategoryId || null : null,
      location: placement === 'catalog' ? draft.location.trim() || null : null,
      meeting_point: placement === 'catalog' ? draft.meetingPoint.trim() || null : null,
      schedule: placement === 'catalog' ? draft.schedule.trim() || null : null,
      duration: placement === 'catalog' ? draft.duration.trim() || null : null,
      max_guests:
        placement === 'lodging'
          ? draft.maxGuests
          : optionalNumber(String(draft.maxGuests || '')),
      lodging: placement === 'lodging' ? this.buildLodgingDetails(draft) : null,
      yacht_lines: placement === 'yacht' ? parseYachtLines(draft.yachtLinesText) : [],
    };
  }

  private buildLodgingDetails(draft: ReturnType<typeof emptyPublicDraft>): LodgingDetails {
    return {
      lodging_type: draft.lodgingType as LodgingType,
      location_es: draft.locationEs.trim(),
      location_en: draft.locationEn.trim(),
      neighborhood_es: draft.neighborhoodEs.trim(),
      neighborhood_en: draft.neighborhoodEn.trim(),
      bedrooms: draft.bedrooms,
      bathrooms: draft.bathrooms,
      amenities: [...this.selectedAmenities()],
      tags: draft.tagsText
        .split(',')
        .map((tag) => tag.trim())
        .filter(Boolean),
      map_url: draft.mapUrl.trim() || null,
    };
  }

  private async refresh(id: string): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.actionError.set(null);
    this.notice.set(null);
    try {
      const [item, taxonomy, addons, links, publicCats] = await Promise.all([
        this.productsApi.getById(id),
        this.categoriesApi.list(),
        this.addonsApi.list(),
        this.addonsApi.listForProduct(id),
        this.publicApi.listCategories(true),
      ]);
      this.product.set(item);
      this.categories.set(taxonomy);
      this.catalogAddons.set(addons);
      this.linkedAddons.set(links);
      this.publicCategories.set(publicCats);
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
        await this.refreshPublic(id, item.type);
      } else {
        this.listing.set(null);
        this.images.set([]);
        this.reviews.set([]);
      }
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }

  private async refreshPublic(productId: string, productType?: ProductType): Promise<void> {
    const type = productType ?? this.product()?.type ?? 'experience';
    const listing = await this.publicApi.getByProductId(productId);
    this.listing.set(listing);
    this.applyListingToDraft(listing, type);

    if (listing) {
      const [images, reviews] = await Promise.all([
        this.publicApi.listImages(listing.id),
        listing.placement === 'lodging'
          ? this.publicApi.listGuestReviews(listing.id)
          : Promise.resolve([] as GuestReview[]),
      ]);
      this.images.set(images);
      this.reviews.set(reviews);
    } else {
      this.images.set([]);
      this.reviews.set([]);
    }
  }

  private applyListingToDraft(listing: PublicListing | null, productType: ProductType): void {
    const placement = listing?.placement ?? defaultPlacement(productType);
    const lodging = listing?.lodging;
    this.selectedAmenities.set((lodging?.amenities ?? []) as LodgingAmenity[]);
    this.publicDraft.set({
      ...emptyPublicDraft(placement),
      placement,
      publicSlug: listing?.public_slug ?? '',
      nameEs: listing?.name_es ?? '',
      nameEn: listing?.name_en ?? '',
      descriptionEs: listing?.description_es ?? '',
      descriptionEn: listing?.description_en ?? '',
      featured: listing?.featured ?? false,
      publicCategoryId: listing?.public_category_id ?? '',
      location: listing?.location ?? '',
      meetingPoint: listing?.meeting_point ?? '',
      schedule: listing?.schedule ?? '',
      duration: listing?.duration ?? '',
      displayPrice: listing?.display_price == null ? '' : String(listing.display_price),
      originalPrice: listing?.original_price == null ? '' : String(listing.original_price),
      currency: listing?.currency ?? 'COP',
      rating: listing?.rating == null ? '' : String(listing.rating),
      includesText: formatBilingualLines(listing?.includes ?? []),
      warningsText: formatBilingualLines(listing?.warnings ?? []),
      lodgingType: lodging?.lodging_type ?? 'casa',
      locationEs: lodging?.location_es ?? '',
      locationEn: lodging?.location_en ?? '',
      neighborhoodEs: lodging?.neighborhood_es ?? '',
      neighborhoodEn: lodging?.neighborhood_en ?? '',
      bedrooms: lodging?.bedrooms ?? 0,
      bathrooms: lodging?.bathrooms ?? 0,
      maxGuests: listing?.max_guests ?? 2,
      mapUrl: lodging?.map_url ?? '',
      tagsText: (lodging?.tags ?? []).join(', '),
      yachtLinesText: formatYachtLines(listing?.yacht_lines ?? []),
    });
  }
}

function defaultPlacement(type: ProductType): PublicPlacement {
  if (type === 'accommodation') {
    return 'lodging';
  }
  return 'catalog';
}

function emptyPublicDraft(placement: PublicPlacement) {
  return {
    placement,
    publicSlug: '',
    nameEs: '',
    nameEn: '',
    descriptionEs: '',
    descriptionEn: '',
    featured: false,
    publicCategoryId: '',
    location: '',
    meetingPoint: '',
    schedule: '',
    duration: '',
    displayPrice: '',
    originalPrice: '',
    currency: 'COP',
    rating: '',
    includesText: '',
    warningsText: '',
    lodgingType: 'casa' as LodgingType,
    locationEs: '',
    locationEn: '',
    neighborhoodEs: '',
    neighborhoodEn: '',
    bedrooms: 0,
    bathrooms: 0,
    maxGuests: 2,
    mapUrl: '',
    tagsText: '',
    yachtLinesText: '',
  };
}

function parseBilingualLines(text: string): BilingualPair[] {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [es, en] = line.split('|||').map((part) => part.trim());
      return { es: es ?? '', en: en ?? '' };
    });
}

function formatBilingualLines(pairs: BilingualPair[]): string {
  return pairs.map((pair) => `${pair.es} ||| ${pair.en}`).join('\n');
}

function parseYachtLines(text: string): YachtLine[] {
  const capacity: YachtLine[] = [];
  const feature: YachtLine[] = [];

  for (const raw of text.split('\n').map((line) => line.trim()).filter(Boolean)) {
    const [meta, texts] = splitOnce(raw, '|||');
    const [kindRaw, iconRaw, esPart] = (meta ?? '').split('|').map((part) => part.trim());
    const kind = kindRaw === 'feature' ? 'feature' : 'capacity';
    const icon = (iconRaw || null) as YachtIcon | null;
    const text_es = (esPart ?? '').trim();
    const text_en = (texts ?? '').trim();
    const line: YachtLine = {
      kind,
      position: 0,
      icon: icon && (YACHT_ICONS as readonly string[]).includes(icon) ? icon : null,
      text_es,
      text_en,
    };
    if (kind === 'feature') {
      feature.push(line);
    } else {
      capacity.push(line);
    }
  }

  return [
    ...capacity.map((line, index) => ({ ...line, position: index })),
    ...feature.map((line, index) => ({ ...line, position: index })),
  ];
}

function formatYachtLines(lines: YachtLine[]): string {
  return [...lines]
    .sort((a, b) => {
      if (a.kind === b.kind) {
        return a.position - b.position;
      }
      return a.kind === 'capacity' ? -1 : 1;
    })
    .map((line) => `${line.kind}|${line.icon ?? ''}|${line.text_es}|||${line.text_en}`)
    .join('\n');
}

function splitOnce(value: string, separator: string): [string, string] {
  const index = value.indexOf(separator);
  if (index < 0) {
    return [value, ''];
  }
  return [value.slice(0, index), value.slice(index + separator.length)];
}

function optionalNumber(value: string | number | null | undefined): number | null {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

function toTimeInput(value: string | null | undefined): string {
  if (!value) {
    return '';
  }
  return value.length >= 5 ? value.slice(0, 5) : value;
}
