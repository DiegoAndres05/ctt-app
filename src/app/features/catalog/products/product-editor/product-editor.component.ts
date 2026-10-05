import { DatePipe } from '@angular/common';
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
import { AuthService } from '../../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import type { Addon, ProductAddonWithAddon } from '../../../../core/catalog/models/addon.model';
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
  type GuestReview,
  type LodgingAmenity,
  type PublicCategory,
  type PublicImage,
  type PublicListing,
  type PublicPlacement,
} from '../../../../core/catalog/models/public-listing.model';
import { AddonService } from '../../../../core/catalog/services/addon.service';
import { CategoryService, slugify } from '../../../../core/catalog/services/category.service';
import { PricingService } from '../../../../core/catalog/services/pricing.service';
import {
  ProductService,
  type ProductDetail,
} from '../../../../core/catalog/services/product.service';
import { PublicListingService } from '../../../../core/catalog/services/public-listing.service';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { ListingPreviewCardComponent } from '../../../../shared/components/listing-preview/listing-preview-card.component';
import {
  toPreviewListing,
  type PreviewLocale,
} from '../../../../shared/components/listing-preview/preview-listing.model';
import type { UnsavedChangesHost } from '../../../../shared/components/unsaved-changes.guard';
import { PricingEditorComponent } from '../../pricing/pricing-editor/pricing-editor.component';
import { ProductEditorHandoff } from './editor-handoff';
import {
  buildSavePayload,
  defaultPlacement,
  draftFromListing,
  emptyPublicDraft,
  optionalNumber,
  placementLabel,
  placementOptions,
  toTimeInput,
  type PublicDraft,
} from './listing-draft';
import { publishGates } from './publish-gates';

type EditorType = Exclude<ProductType, 'package'>;

interface AttrDraft {
  name: string;
  description: string;
  durationMinutes: number;
  difficulty: ExperienceDifficulty | '';
  meetingPoint: string;
  minCapacity: number;
  maxCapacity: number;
  propertyType: string;
  location: string;
  checkIn: string;
  checkOut: string;
  maxOccupancy: number;
}

/**
 * One screen to create and edit an experience or accommodation, including the 009 public ficha.
 * The first save creates the draft product and its listing so images and price unlock in place.
 */
@Component({
  selector: 'app-product-editor',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    DatePipe,
    FormField,
    RouterLink,
    AlertComponent,
    SpinnerComponent,
    PricingEditorComponent,
    ListingPreviewCardComponent,
  ],
  templateUrl: './product-editor.component.html',
})
export class ProductEditorComponent implements UnsavedChangesHost {
  private readonly productsApi = inject(ProductService);
  private readonly categoriesApi = inject(CategoryService);
  private readonly addonsApi = inject(AddonService);
  private readonly publicApi = inject(PublicListingService);
  private readonly pricingApi = inject(PricingService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly handoff = inject(ProductEditorHandoff);

  readonly id = input<string | undefined>();
  readonly productType = input<EditorType>('experience');

  protected readonly lodgingTypes = LODGING_TYPES;
  protected readonly lodgingAmenities = LODGING_AMENITIES;
  protected readonly yachtIcons = YACHT_ICONS;
  protected readonly placementLabel = placementLabel;

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
  protected readonly hasTariff = signal(false);
  protected readonly loading = signal(true);
  protected readonly saving = signal(false);
  protected readonly publicBusy = signal(false);
  protected readonly imageLoading = signal(false);
  protected readonly pendingCoverUrl = signal<string | null>(null);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly previewLocale = signal<PreviewLocale>('es');

  protected readonly attrDraft = signal<AttrDraft>(emptyAttr());
  protected readonly statusDraft = signal({
    status: 'inactive' as Extract<ProductStatus, 'active' | 'inactive'>,
  });
  protected readonly linkDraft = signal({ addonId: '', isMandatory: false, maxQuantity: 0 });
  protected readonly publicDraft = signal<PublicDraft>(emptyPublicDraft('catalog'));
  protected readonly reviewDraft = signal({
    author: '',
    rating: 5,
    reviewedOn: '',
    textEs: '',
    textEn: '',
  });

  protected readonly attrForm = form(this.attrDraft, (fields) => {
    required(fields.name);
  });
  protected readonly statusForm = form(this.statusDraft, (fields) => {
    required(fields.status);
  });
  protected readonly linkForm = form(this.linkDraft, (fields) => {
    required(fields.addonId);
  });
  protected readonly publicForm = form(this.publicDraft);
  protected readonly reviewForm = form(this.reviewDraft, (fields) => {
    required(fields.author);
    required(fields.textEs);
    required(fields.textEn);
    required(fields.reviewedOn);
  });

  private baseline = '';
  private ready = false;
  private allowLeave = false;

  protected readonly saved = computed(() => Boolean(this.product()?.id));
  protected readonly preview = computed(() => {
    const draft = this.publicDraft();
    const locale = this.previewLocale();
    const category = this.publicCategories().find((item) => item.id === draft.publicCategoryId);
    const variant =
      draft.placement === 'yacht' ? 'yacht' : draft.placement === 'lodging' ? 'lodging' : 'catalog';
    const location =
      variant === 'lodging'
        ? locale === 'en'
          ? draft.locationEn
          : draft.locationEs
        : draft.location;
    return toPreviewListing({
      variant,
      locale,
      titleEs: draft.nameEs,
      titleEn: draft.nameEn,
      descriptionEs: draft.descriptionEs,
      descriptionEn: draft.descriptionEn,
      categoryLabelEs: category?.name_es ?? '',
      categoryLabelEn: category?.name_en ?? '',
      location,
      imageUrl: this.pendingCoverUrl() ?? this.publicApi.mediaUrl(this.listing()?.cover_image_ref),
      displayPrice: optionalNumber(draft.displayPrice),
      currency: draft.currency,
      soldOut: this.listing()?.sold_out ?? false,
      lodgingType: draft.lodgingType,
      occupancy: draft.maxGuests,
      imageLoading: this.imageLoading(),
    });
  });
  protected readonly gates = computed(() =>
    publishGates({
      productStatus: this.product()?.status ?? null,
      hasTariff: this.hasTariff(),
      hasCover: Boolean(this.listing()?.cover_image_ref),
      draft: this.publicDraft(),
    }),
  );
  protected readonly canPublish = computed(() => this.gates().every((gate) => gate.ok));
  protected readonly basicIncomplete = computed(() => this.attrDraft().name.trim().length === 0);
  protected readonly operativeIncomplete = computed(() => {
    if (this.productType() !== 'accommodation' && this.product()?.type !== 'accommodation') {
      return false;
    }
    const draft = this.attrDraft();
    return draft.propertyType.trim().length === 0 || draft.location.trim().length === 0;
  });
  protected readonly publicIncomplete = computed(() => {
    const draft = this.publicDraft();
    return (
      !draft.nameEs.trim() ||
      !draft.nameEn.trim() ||
      !draft.descriptionEs.trim() ||
      !draft.descriptionEn.trim()
    );
  });

  constructor() {
    effect(() => {
      const id = this.id();
      const type = this.productType();
      untracked(() => {
        void this.load(id, type);
      });
    });
  }

  hasUnsavedChanges(): boolean {
    if (this.allowLeave || !this.canEdit() || !this.ready) {
      return false;
    }
    return this.snapshot() !== this.baseline;
  }

  protected canEdit(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'operator');
  }

  protected canOverridePrice(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'admin');
  }

  protected slugLocked(): boolean {
    return this.listing()?.first_published_at != null;
  }

  protected options(): PublicPlacement[] {
    return placementOptions(this.product()?.type ?? this.productType());
  }

  protected listLink(): string {
    return (this.product()?.type ?? this.productType()) === 'accommodation'
      ? '/cms/accommodations'
      : '/cms/experiences';
  }

  protected screenTitle(): string {
    const type = this.product()?.type ?? this.productType();
    const noun = type === 'accommodation' ? 'alojamiento' : 'experiencia';
    if (!this.product()) {
      return type === 'accommodation' ? 'Nuevo alojamiento' : 'Nueva experiencia';
    }
    return this.canEdit() ? `Editar ${noun}` : `Consultar ${noun}`;
  }

  protected availableAddons(): Addon[] {
    const linked = new Set(this.linkedAddons().map((row) => row.addon_id));
    return this.catalogAddons().filter((addon) => addon.is_active && !linked.has(addon.id));
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

  protected setLocale(locale: PreviewLocale): void {
    this.previewLocale.set(locale);
  }

  protected onCoverRefInput(event: Event): void {
    this.coverExternalRef.set((event.target as HTMLInputElement).value);
  }

  protected async onSaveDraft(): Promise<void> {
    if (!this.canEdit()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    await submit(this.attrForm, async () => {
      if (this.operativeIncomplete()) {
        this.actionError.set(toAppError(new Error('VALIDATION_ERROR')));
        return undefined;
      }
      this.saving.set(true);
      try {
        const existing = this.product();
        if (!existing) {
          await this.createDraft();
        } else {
          await this.persistProduct(existing);
          await this.persistListing(existing.id);
          this.captureBaseline();
          this.notice.set('Borrador guardado.');
          await this.refresh(existing.id, existing.type, false);
        }
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      } finally {
        this.saving.set(false);
      }
      return undefined;
    });
  }

  protected async onSaveStatus(event: Event): Promise<void> {
    event.preventDefault();
    if (!this.canEdit() || !this.product()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    await submit(this.statusForm, async (fields) => {
      try {
        const updated = await this.productsApi.setStatus(
          this.product()!.id,
          fields.status().value(),
        );
        const current = this.product();
        if (current) {
          this.product.set({ ...current, status: updated.status });
        }
        this.notice.set(
          updated.status === 'active'
            ? 'El producto quedó activo en el catálogo comercial.'
            : 'El producto quedó inactivo. No estará disponible para nuevas cotizaciones.',
        );
        this.captureBaseline();
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onLinkAddon(event: Event): Promise<void> {
    event.preventDefault();
    const product = this.product();
    if (!product || !this.canEdit()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    await submit(this.linkForm, async (fields) => {
      try {
        const maxQuantity = fields.maxQuantity().value();
        await this.addonsApi.linkToProduct({
          productId: product.id,
          addonId: fields.addonId().value(),
          isMandatory: fields.isMandatory().value(),
          maxQuantity: maxQuantity > 0 ? maxQuantity : null,
        });
        this.linkDraft.set({ addonId: '', isMandatory: false, maxQuantity: 0 });
        this.linkedAddons.set(await this.addonsApi.listForProduct(product.id));
        this.notice.set('El complemento quedó vinculado al producto.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onUnlinkAddon(linkId: string): Promise<void> {
    const product = this.product();
    if (!product || !this.canEdit()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    try {
      await this.addonsApi.unlinkFromProduct(linkId);
      this.linkedAddons.set(await this.addonsApi.listForProduct(product.id));
      this.notice.set('El complemento se desvinculó del producto.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    }
  }

  protected async onPublish(): Promise<void> {
    const listing = this.listing();
    const product = this.product();
    if (!listing || !product || !this.canEdit() || !this.canPublish()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    this.publicBusy.set(true);
    try {
      await this.persistListing(product.id);
      await this.publicApi.publishListing(listing.id);
      await this.refreshPublic(product.id, product.type);
      this.captureBaseline();
      this.notice.set('La ficha pública quedó publicada.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onUnpublish(): Promise<void> {
    const listing = this.listing();
    const product = this.product();
    if (!listing || !product || !this.canEdit()) {
      return;
    }
    this.publicBusy.set(true);
    this.actionError.set(null);
    this.notice.set(null);
    try {
      await this.publicApi.unpublish(listing.id);
      await this.refreshPublic(product.id, product.type);
      this.notice.set('La ficha pública se despublicó.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onToggleSoldOut(event: Event): Promise<void> {
    const listing = this.listing();
    const product = this.product();
    if (!listing || !product || !this.canEdit()) {
      return;
    }
    const soldOut = (event.target as HTMLInputElement).checked;
    this.publicBusy.set(true);
    this.actionError.set(null);
    this.notice.set(null);
    try {
      await this.publicApi.setSoldOut(listing.id, soldOut);
      await this.refreshPublic(product.id, product.type);
      this.notice.set(soldOut ? 'Marcada como agotada.' : 'Disponible de nuevo para solicitudes.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onCoverFileSelected(event: Event): Promise<void> {
    await this.attachFile(event, 'cover');
  }

  protected async onGalleryFileSelected(event: Event): Promise<void> {
    await this.attachFile(event, 'gallery');
  }

  protected async onAttachExternalCover(): Promise<void> {
    const product = this.product();
    const ref = this.coverExternalRef().trim();
    if (!product || !ref || !this.canEdit()) {
      return;
    }
    this.publicBusy.set(true);
    this.actionError.set(null);
    this.notice.set(null);
    try {
      const listing = await this.ensureListing(product.id);
      await this.publicApi.attachImage({ listingId: listing.id, role: 'cover', externalRef: ref });
      this.coverExternalRef.set('');
      await this.refreshPublic(product.id, product.type);
      this.notice.set('Portada por referencia externa adjuntada.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.publicBusy.set(false);
    }
  }

  protected async onSaveReview(event: Event): Promise<void> {
    event.preventDefault();
    const product = this.product();
    if (!product || !this.canEdit()) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    await submit(this.reviewForm, async (fields) => {
      try {
        const listing = await this.ensureListing(product.id);
        await this.publicApi.saveGuestReview({
          listing_id: listing.id,
          author: fields.author().value().trim(),
          rating: fields.rating().value(),
          reviewed_on: fields.reviewedOn().value(),
          text_es: fields.textEs().value().trim(),
          text_en: fields.textEn().value().trim(),
        });
        this.reviewDraft.set({ author: '', rating: 5, reviewedOn: '', textEs: '', textEn: '' });
        this.reviews.set(await this.publicApi.listGuestReviews(listing.id));
        this.notice.set('Opinión guardada.');
      } catch (failure) {
        this.actionError.set(toAppError(failure));
      }
      return undefined;
    });
  }

  protected async onTariffSaved(): Promise<void> {
    const product = this.product();
    if (!product) {
      return;
    }
    const current = await this.pricingApi.listCurrentForProduct(product.id);
    this.hasTariff.set(current.length > 0);
  }

  private async load(id: string | undefined, type: EditorType): Promise<void> {
    this.loading.set(true);
    this.ready = false;
    this.error.set(null);
    try {
      const [taxonomy, addons, publicCats] = await Promise.all([
        this.categoriesApi.list(),
        this.addonsApi.list(),
        this.publicApi.listCategories(true),
      ]);
      this.categories.set(taxonomy);
      this.catalogAddons.set(addons);
      this.publicCategories.set(publicCats);
      if (!id) {
        this.product.set(null);
        this.listing.set(null);
        this.attrDraft.set(emptyAttr());
        this.publicDraft.set(emptyPublicDraft(defaultPlacement(type)));
        this.selectedCategoryIds.set([]);
        this.selectedAmenities.set([]);
        this.captureBaseline();
        return;
      }
      await this.refresh(id, type, true);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }

  private async refresh(id: string, hintedType: ProductType, applyHandoff: boolean): Promise<void> {
    const item = await this.productsApi.getById(id);
    if (!item) {
      this.product.set(null);
      this.error.set(null);
      return;
    }
    if (item.type === 'package') {
      this.allowLeave = true;
      await this.router.navigate(['/cms/packages', item.id], { replaceUrl: true });
      return;
    }
    if (item.type !== hintedType) {
      this.allowLeave = true;
      const base = item.type === 'accommodation' ? '/cms/accommodations' : '/cms/experiences';
      await this.router.navigate([base, item.id], { replaceUrl: true });
      return;
    }

    const links = await this.addonsApi.listForProduct(id);
    this.product.set(item);
    this.linkedAddons.set(links);
    this.selectedCategoryIds.set(item.category_ids);
    this.statusDraft.set({ status: item.status === 'active' ? 'active' : 'inactive' });
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
    const tariffs = await this.pricingApi.listCurrentForProduct(id);
    this.hasTariff.set(tariffs.length > 0);
    this.captureBaseline();
    if (applyHandoff) {
      const pending = this.handoff.take(id);
      if (pending) {
        this.publicDraft.set(pending.draft);
        this.selectedAmenities.set(pending.amenities);
      }
    }
  }

  private async refreshPublic(productId: string, productType: ProductType): Promise<void> {
    const listing = await this.publicApi.getByProductId(productId);
    this.listing.set(listing);
    const applied = draftFromListing(listing, productType);
    this.selectedAmenities.set(applied.amenities);
    this.publicDraft.set(applied.draft);
    if (!listing) {
      this.images.set([]);
      this.reviews.set([]);
      return;
    }
    const [images, reviews] = await Promise.all([
      this.publicApi.listImages(listing.id),
      listing.placement === 'lodging'
        ? this.publicApi.listGuestReviews(listing.id)
        : Promise.resolve([] as GuestReview[]),
    ]);
    this.images.set(images);
    this.reviews.set(reviews);
  }

  private async createDraft(): Promise<void> {
    const type = this.productType();
    const attr = this.attrDraft();
    const created = await this.productsApi.create({
      type,
      name: attr.name,
      description: attr.description || null,
      categoryIds: this.selectedCategoryIds(),
      experience:
        type === 'experience'
          ? {
              duration_minutes: attr.durationMinutes,
              difficulty: attr.difficulty || undefined,
              meeting_point: attr.meetingPoint || null,
              min_capacity: attr.minCapacity,
              max_capacity: attr.maxCapacity,
            }
          : undefined,
      accommodation:
        type === 'accommodation'
          ? {
              property_type: attr.propertyType,
              location: attr.location,
              check_in: attr.checkIn || null,
              check_out: attr.checkOut || null,
              max_occupancy: attr.maxOccupancy,
            }
          : undefined,
    });
    try {
      await this.publicApi.saveListing(
        buildSavePayload(
          created.id,
          this.publicDraft(),
          this.selectedAmenities(),
          slugify(attr.name),
        ),
      );
    } catch (failure) {
      this.handoff.stash({
        productId: created.id,
        draft: this.publicDraft(),
        amenities: this.selectedAmenities(),
      });
      this.actionError.set(toAppError(failure));
    }
    this.allowLeave = true;
    const base = type === 'accommodation' ? '/cms/accommodations' : '/cms/experiences';
    await this.router.navigate([base, created.id], { replaceUrl: true });
  }

  private async persistProduct(item: ProductDetail): Promise<void> {
    const attr = this.attrDraft();
    await this.productsApi.update(item.id, {
      name: attr.name,
      description: attr.description || null,
      providerId: item.provider_id,
      experience:
        item.type === 'experience'
          ? {
              duration_minutes: attr.durationMinutes,
              difficulty: (attr.difficulty || null) as ExperienceDifficulty | null,
              meeting_point: attr.meetingPoint || null,
              min_capacity: attr.minCapacity,
              max_capacity: attr.maxCapacity,
            }
          : undefined,
      accommodation:
        item.type === 'accommodation'
          ? {
              property_type: attr.propertyType,
              location: attr.location,
              check_in: attr.checkIn || null,
              check_out: attr.checkOut || null,
              max_occupancy: attr.maxOccupancy,
              occupancy_rules: item.accommodation?.occupancy_rules ?? null,
            }
          : undefined,
    });
    await this.categoriesApi.replaceAssignments(item.id, this.selectedCategoryIds());
  }

  private async persistListing(productId: string): Promise<PublicListing | null> {
    const fallback = slugify(this.publicDraft().nameEs || this.attrDraft().name || 'ficha');
    await this.publicApi.saveListing(
      buildSavePayload(productId, this.publicDraft(), this.selectedAmenities(), fallback),
    );
    const type = this.product()?.type ?? this.productType();
    await this.refreshPublic(productId, type);
    return this.listing();
  }

  private async ensureListing(productId: string): Promise<PublicListing> {
    const current = this.listing();
    if (current) {
      return current;
    }
    const saved = await this.persistListing(productId);
    if (!saved) {
      throw toAppError(new Error('VALIDATION_ERROR'));
    }
    return saved;
  }

  private async attachFile(event: Event, role: 'cover' | 'gallery'): Promise<void> {
    const product = this.product();
    const file = (event.target as HTMLInputElement).files?.[0];
    (event.target as HTMLInputElement).value = '';
    if (!product || !file || !this.canEdit()) {
      return;
    }
    const local = role === 'cover' ? URL.createObjectURL(file) : null;
    if (local) {
      this.pendingCoverUrl.set(local);
    }
    this.imageLoading.set(role === 'cover');
    this.publicBusy.set(true);
    this.actionError.set(null);
    this.notice.set(null);
    try {
      const listing = await this.ensureListing(product.id);
      const nextOrder =
        role === 'gallery'
          ? this.images().reduce((max, image) => Math.max(max, image.sort_order), -1) + 1
          : 0;
      await this.publicApi.uploadAndAttachImage({
        listingId: listing.id,
        role,
        file,
        sortOrder: nextOrder,
      });
      await this.refreshPublic(product.id, product.type);
      this.notice.set(role === 'cover' ? 'Portada actualizada.' : 'Imagen añadida a la galería.');
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.imageLoading.set(false);
      this.publicBusy.set(false);
      if (local) {
        URL.revokeObjectURL(local);
        this.pendingCoverUrl.set(null);
      }
    }
  }

  private snapshot(): string {
    return JSON.stringify({
      attr: this.attrDraft(),
      pub: this.publicDraft(),
      categories: [...this.selectedCategoryIds()].sort(),
      amenities: [...this.selectedAmenities()].sort(),
      status: this.statusDraft(),
    });
  }

  private captureBaseline(): void {
    this.baseline = this.snapshot();
    this.ready = true;
  }
}

function emptyAttr(): AttrDraft {
  return {
    name: '',
    description: '',
    durationMinutes: 60,
    difficulty: '',
    meetingPoint: '',
    minCapacity: 1,
    maxCapacity: 10,
    propertyType: '',
    location: '',
    checkIn: '',
    checkOut: '',
    maxOccupancy: 2,
  };
}
