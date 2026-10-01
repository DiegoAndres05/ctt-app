import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { AuthService } from '../../auth/services/auth.service';
import { SupabaseService } from '../../auth/services/supabase.service';
import type {
  AttachPublicImageResult,
  CutoverStatus,
  GuestReview,
  PublicCategory,
  PublicCutoverItem,
  PublicImage,
  PublicImageRole,
  PublicListing,
  PublicSite,
  PublicSiteProjection,
  PublishPublicListingResult,
  SaveGuestReviewPayload,
  SavePublicCategoryPayload,
  SavePublicListingPayload,
  SavedPublicListing,
  UnpublishPublicListingResult,
} from '../models/public-listing.model';

const CATALOG_MEDIA_BUCKET = 'catalog-media';
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/jpg']);

/**
 * Tenant-scoped public listings (feature 009). Reads go through PostgREST (RLS).
 * Writes go through SECURITY DEFINER RPCs that re-check `app_role` and `organization_id`.
 */
@Injectable({ providedIn: 'root' })
export class PublicListingService {
  private readonly supabase = inject(SupabaseService);
  private readonly auth = inject(AuthService);

  /** Public URL for a cover ref that is either an external URL or a storage path. */
  mediaUrl(ref: string | null | undefined): string | null {
    if (!ref) {
      return null;
    }
    if (/^https?:\/\//i.test(ref)) {
      return ref;
    }
    return this.supabase.client.storage.from(CATALOG_MEDIA_BUCKET).getPublicUrl(ref).data.publicUrl;
  }

  async getByProductId(productId: string): Promise<PublicListing | null> {
    const { data, error } = await this.supabase.client
      .from('public_listings')
      .select('*')
      .eq('product_id', productId)
      .maybeSingle();

    if (error) {
      throw toAppError(error);
    }

    return data ? coerceListing(data as PublicListing) : null;
  }

  async listImages(listingId: string, activeOnly = true): Promise<PublicImage[]> {
    let query = this.supabase.client
      .from('public_images')
      .select('*')
      .eq('listing_id', listingId)
      .order('sort_order', { ascending: true });

    if (activeOnly) {
      query = query.is('replaced_at', null);
    }

    const { data, error } = await query.returns<PublicImage[]>();

    if (error) {
      throw toAppError(error);
    }

    return data ?? [];
  }

  async listGuestReviews(listingId: string): Promise<GuestReview[]> {
    const { data, error } = await this.supabase.client
      .from('guest_reviews')
      .select('*')
      .eq('listing_id', listingId)
      .order('reviewed_on', { ascending: false })
      .returns<GuestReview[]>();

    if (error) {
      throw toAppError(error);
    }

    return data ?? [];
  }

  async listCategories(activeOnly = false): Promise<PublicCategory[]> {
    let query = this.supabase.client
      .from('public_categories')
      .select('*')
      .order('id', { ascending: true });

    if (activeOnly) {
      query = query.eq('is_active', true);
    }

    const { data, error } = await query.returns<PublicCategory[]>();

    if (error) {
      throw toAppError(error);
    }

    return data ?? [];
  }

  async saveListing(payload: SavePublicListingPayload): Promise<SavedPublicListing> {
    const { data, error } = await this.supabase.client.rpc('save_public_listing', {
      p_payload: payload,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as SavedPublicListing;
  }

  async publishListing(listingId: string): Promise<PublishPublicListingResult> {
    const { data, error } = await this.supabase.client.rpc('publish_public_listing', {
      p_listing_id: listingId,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as PublishPublicListingResult;
  }

  async unpublish(listingId: string): Promise<UnpublishPublicListingResult> {
    const { data, error } = await this.supabase.client.rpc('unpublish_public_listing', {
      p_listing_id: listingId,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as UnpublishPublicListingResult;
  }

  async setSoldOut(listingId: string, soldOut: boolean): Promise<{ sold_out: boolean }> {
    const { data, error } = await this.supabase.client.rpc('set_public_listing_sold_out', {
      p_listing_id: listingId,
      p_sold_out: soldOut,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as { sold_out: boolean };
  }

  async attachImage(input: {
    listingId: string;
    role: PublicImageRole;
    storagePath?: string | null;
    externalRef?: string | null;
    sortOrder?: number;
    byteSize?: number | null;
    contentType?: string | null;
  }): Promise<AttachPublicImageResult> {
    const { data, error } = await this.supabase.client.rpc('attach_public_image', {
      p_listing_id: input.listingId,
      p_role: input.role,
      p_storage_path: input.storagePath ?? null,
      p_external_ref: input.externalRef ?? null,
      p_sort_order: input.sortOrder ?? 0,
      p_byte_size: input.byteSize ?? null,
      p_content_type: input.contentType ?? null,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as AttachPublicImageResult;
  }

  /**
   * Uploads a cover/gallery file to `catalog-media` then calls `attach_public_image`.
   * Path prefix is `{organization_id}/{listing_id}/…` so storage policies match.
   */
  async uploadAndAttachImage(input: {
    listingId: string;
    role: PublicImageRole;
    file: File;
    sortOrder?: number;
  }): Promise<AttachPublicImageResult> {
    if (input.file.size > MAX_IMAGE_BYTES) {
      throw toAppError({ message: 'IMAGE_TOO_LARGE' });
    }
    if (!ALLOWED_IMAGE_TYPES.has(input.file.type.toLowerCase())) {
      throw toAppError({ message: 'IMAGE_TYPE_NOT_ALLOWED' });
    }

    const organizationId = this.auth.organizationId();
    if (!organizationId) {
      throw toAppError({ message: 'MISSING_TENANT_CONTEXT' });
    }

    const ext = extensionForMime(input.file.type) ?? 'bin';
    const storagePath = `${organizationId}/${input.listingId}/${input.role}-${Date.now()}.${ext}`;

    const { error: uploadError } = await this.supabase.client.storage
      .from(CATALOG_MEDIA_BUCKET)
      .upload(storagePath, input.file, {
        contentType: input.file.type,
        upsert: false,
      });

    if (uploadError) {
      throw toAppError(uploadError);
    }

    return this.attachImage({
      listingId: input.listingId,
      role: input.role,
      storagePath,
      sortOrder: input.sortOrder ?? 0,
      byteSize: input.file.size,
      contentType: input.file.type,
    });
  }

  async reorderGallery(listingId: string, imageIds: string[]): Promise<void> {
    const { error } = await this.supabase.client.rpc('reorder_public_gallery', {
      p_listing_id: listingId,
      p_image_ids: imageIds,
    });

    if (error) {
      throw toAppError(error);
    }
  }

  async saveGuestReview(payload: SaveGuestReviewPayload): Promise<{ id: string }> {
    const { data, error } = await this.supabase.client.rpc('save_guest_review', {
      p_payload: payload,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as { id: string };
  }

  async saveCategory(payload: SavePublicCategoryPayload): Promise<{
    id: string;
    name_es: string;
    name_en: string;
    is_active: boolean;
  }> {
    const { data, error } = await this.supabase.client.rpc('save_public_category', {
      p_payload: payload,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as {
      id: string;
      name_es: string;
      name_en: string;
      is_active: boolean;
    };
  }

  async getSite(): Promise<PublicSite | null> {
    const { data, error } = await this.supabase.client
      .from('public_sites')
      .select('*')
      .maybeSingle();

    if (error) {
      throw toAppError(error);
    }

    return (data as PublicSite | null) ?? null;
  }

  async listCutoverItems(): Promise<PublicCutoverItem[]> {
    const { data, error } = await this.supabase.client
      .from('public_cutover_items')
      .select('*')
      .order('public_slug', { ascending: true })
      .returns<PublicCutoverItem[]>();

    if (error) {
      throw toAppError(error);
    }

    return data ?? [];
  }

  async getCutoverStatus(): Promise<CutoverStatus> {
    const [site, items, published] = await Promise.all([
      this.getSite(),
      this.listCutoverItems(),
      this.listPublishedSlugs(),
    ]);

    const publishedSet = new Set(published);
    const missing_slugs = items
      .map((item) => item.public_slug)
      .filter((slug) => !publishedSet.has(slug));

    return { site, items, missing_slugs };
  }

  async completeCutover(): Promise<{ source: 'panel'; cutover_completed_at: string }> {
    const { data, error } = await this.supabase.client.rpc('complete_public_cutover');

    if (error) {
      throw toAppError(error);
    }

    return data as { source: 'panel'; cutover_completed_at: string };
  }

  async getPublicSite(organizationId: string): Promise<PublicSiteProjection> {
    const { data, error } = await this.supabase.client.rpc('get_public_site', {
      p_organization_id: organizationId,
    });

    if (error) {
      throw toAppError(error);
    }

    const row = (data ?? {}) as Partial<PublicSiteProjection>;
    return {
      source: row.source ?? 'legacy',
      offers: Array.isArray(row.offers) ? row.offers : [],
      lodgings: Array.isArray(row.lodgings) ? row.lodgings : [],
      yachts: Array.isArray(row.yachts) ? row.yachts : [],
    };
  }

  private async listPublishedSlugs(): Promise<string[]> {
    const { data, error } = await this.supabase.client
      .from('public_listings')
      .select('public_slug, status, products!inner(status)')
      .eq('status', 'published')
      .eq('products.status', 'active');

    if (error) {
      throw toAppError(error);
    }

    return ((data ?? []) as { public_slug: string }[]).map((row) => row.public_slug);
  }
}

function coerceListing(row: PublicListing): PublicListing {
  return {
    ...row,
    display_price: row.display_price == null ? null : Number(row.display_price),
    original_price: row.original_price == null ? null : Number(row.original_price),
    rating: row.rating == null ? null : Number(row.rating),
    includes: Array.isArray(row.includes) ? row.includes : [],
    warnings: Array.isArray(row.warnings) ? row.warnings : [],
    yacht_lines: Array.isArray(row.yacht_lines) ? row.yacht_lines : [],
    lodging: row.lodging ?? null,
  };
}

function extensionForMime(mime: string): string | null {
  switch (mime.toLowerCase()) {
    case 'image/jpeg':
    case 'image/jpg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    default:
      return null;
  }
}
