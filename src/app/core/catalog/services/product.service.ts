import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { SupabaseService } from '../../auth/services/supabase.service';
import type {
  Accommodation,
  Experience,
  Package,
  PackageConsistency,
  PackageItem,
  Product,
  ProductStatus,
  ProductType,
} from '../models/product.model';

const LIST_LIMIT = 50;

/** Nested PostgREST shape for a product list/detail row. */
interface ProductRow extends Product {
  product_categories?: { category_id: string }[] | null;
  experiences?: Experience | Experience[] | null;
  accommodations?: Accommodation | Accommodation[] | null;
}

export interface ProductListFilters {
  type?: ProductType | '';
  status?: ProductStatus | '';
  categoryId?: string;
}

export interface ProductListItem extends Product {
  category_ids: string[];
}

export interface ProductDetail extends Product {
  experience: Experience | null;
  accommodation: Accommodation | null;
  category_ids: string[];
}

export interface CreateProductInput {
  type: Exclude<ProductType, 'package'>;
  name: string;
  description?: string | null;
  providerId?: string | null;
  categoryIds?: string[];
  experience?: {
    duration_minutes: number;
    difficulty?: Experience['difficulty'];
    meeting_point?: string | null;
    min_capacity: number;
    max_capacity: number;
  };
  accommodation?: {
    property_type: string;
    location: string;
    check_in?: string | null;
    check_out?: string | null;
    max_occupancy: number;
    occupancy_rules?: Record<string, unknown> | null;
  };
}

export interface CreatedProduct {
  id: string;
  status: ProductStatus;
}

export interface ProductStatusUpdate {
  id: string;
  status: ProductStatus;
}

export interface CreatePackageItemInput {
  component_product_id: string;
  sort_order: number;
  day_number: number | null;
}

export interface CreatePackageInput {
  name: string;
  description?: string | null;
  providerId?: string | null;
  categoryIds?: string[];
  totalDays: number | null;
  totalNights: number | null;
  items: CreatePackageItemInput[];
}

export interface PackageDetail extends Product {
  package: Package;
  items: PackageItem[];
  category_ids: string[];
}

interface PackageRow extends Package {
  package_items?: PackageItem[] | null;
}

interface PackageConsistencyPayload {
  packages?: PackageConsistency[] | null;
}

export interface UpdateProductInput {
  name: string;
  description: string | null;
  providerId: string | null;
  experience?: {
    duration_minutes: number;
    difficulty: Experience['difficulty'];
    meeting_point: string | null;
    min_capacity: number;
    max_capacity: number;
  };
  accommodation?: {
    property_type: string;
    location: string;
    check_in: string | null;
    check_out: string | null;
    max_occupancy: number;
    occupancy_rules: Record<string, unknown> | null;
  };
}

/**
 * Tenant-scoped catalog products. Listing and edits go through PostgREST (RLS). Create and
 * status changes go through SECURITY DEFINER RPCs that re-check `app_role` and `organization_id`.
 */
@Injectable({ providedIn: 'root' })
export class ProductService {
  private readonly supabase = inject(SupabaseService);

  async list(filters: ProductListFilters = {}): Promise<ProductListItem[]> {
    const categoryJoin = filters.categoryId ? 'product_categories!inner(category_id)' : 'product_categories(category_id)';

    let query = this.supabase.client
      .from('products')
      .select(`*, ${categoryJoin}`)
      .order('name', { ascending: true })
      .limit(LIST_LIMIT);

    if (filters.type) {
      query = query.eq('type', filters.type);
    }
    if (filters.status) {
      query = query.eq('status', filters.status);
    }
    if (filters.categoryId) {
      query = query.eq('product_categories.category_id', filters.categoryId);
    }

    const { data, error } = await query.returns<ProductRow[]>();

    if (error) {
      throw toAppError(error);
    }

    return (data ?? []).map((row) => ({
      ...row,
      category_ids: categoryIds(row),
    }));
  }

  async getById(id: string): Promise<ProductDetail | null> {
    const { data, error } = await this.supabase.client
      .from('products')
      .select('*, experiences(*), accommodations(*), product_categories(category_id)')
      .eq('id', id)
      .maybeSingle<ProductRow>();

    if (error) {
      throw toAppError(error);
    }

    if (!data) {
      return null;
    }

    return {
      ...data,
      experience: one(data.experiences),
      accommodation: one(data.accommodations),
      category_ids: categoryIds(data),
    };
  }

  async create(input: CreateProductInput): Promise<CreatedProduct> {
    const { data, error } = await this.supabase.client.rpc('create_product', {
      p_type: input.type,
      p_name: input.name.trim(),
      p_description: input.description?.trim() || null,
      p_provider_id: input.providerId || null,
      p_category_ids: input.categoryIds ?? [],
      p_experience: input.type === 'experience' ? (input.experience ?? null) : null,
      p_accommodation: input.type === 'accommodation' ? (input.accommodation ?? null) : null,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as CreatedProduct;
  }

  async update(id: string, input: UpdateProductInput): Promise<void> {
    const { error: productError } = await this.supabase.client
      .from('products')
      .update({
        name: input.name.trim(),
        description: input.description?.trim() || null,
        provider_id: input.providerId || null,
      })
      .eq('id', id);

    if (productError) {
      throw toAppError(productError);
    }

    if (input.experience) {
      const { error } = await this.supabase.client
        .from('experiences')
        .update({
          duration_minutes: input.experience.duration_minutes,
          difficulty: input.experience.difficulty,
          meeting_point: input.experience.meeting_point?.trim() || null,
          min_capacity: input.experience.min_capacity,
          max_capacity: input.experience.max_capacity,
        })
        .eq('id', id);

      if (error) {
        throw toAppError(error);
      }
    }

    if (input.accommodation) {
      const { error } = await this.supabase.client
        .from('accommodations')
        .update({
          property_type: input.accommodation.property_type.trim(),
          location: input.accommodation.location.trim(),
          check_in: input.accommodation.check_in || null,
          check_out: input.accommodation.check_out || null,
          max_occupancy: input.accommodation.max_occupancy,
          occupancy_rules: input.accommodation.occupancy_rules,
        })
        .eq('id', id);

      if (error) {
        throw toAppError(error);
      }
    }
  }

  async setStatus(productId: string, status: Extract<ProductStatus, 'active' | 'inactive'>): Promise<ProductStatusUpdate> {
    const { data, error } = await this.supabase.client.rpc('set_product_status', {
      p_product_id: productId,
      p_status: status,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as ProductStatusUpdate;
  }

  async listPackages(): Promise<ProductListItem[]> {
    return this.list({ type: 'package' });
  }

  async getPackageById(id: string): Promise<PackageDetail | null> {
    const product = await this.getById(id);
    if (!product || product.type !== 'package') {
      return null;
    }

    const { data, error } = await this.supabase.client
      .from('packages')
      .select('*, package_items(*)')
      .eq('id', id)
      .maybeSingle<PackageRow>();

    if (error) {
      throw toAppError(error);
    }

    if (!data) {
      return null;
    }

    const items = [...(data.package_items ?? [])].sort((a, b) => a.sort_order - b.sort_order);

    return {
      ...product,
      package: {
        id: data.id,
        organization_id: data.organization_id,
        total_days: data.total_days,
        total_nights: data.total_nights,
      },
      items,
      category_ids: product.category_ids,
    };
  }

  async createPackage(input: CreatePackageInput): Promise<CreatedProduct> {
    const { data, error } = await this.supabase.client.rpc('create_package', {
      p_name: input.name.trim(),
      p_description: input.description?.trim() || null,
      p_provider_id: input.providerId || null,
      p_category_ids: input.categoryIds ?? [],
      p_total_days: input.totalDays,
      p_total_nights: input.totalNights,
      p_items: input.items,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as CreatedProduct;
  }

  async getPackageConsistency(packageId?: string): Promise<PackageConsistency[]> {
    const { data, error } = await this.supabase.client.rpc('get_package_consistency', {
      p_package_id: packageId ?? null,
    });

    if (error) {
      throw toAppError(error);
    }

    return (data as PackageConsistencyPayload | null)?.packages ?? [];
  }
}

function categoryIds(row: ProductRow): string[] {
  return (row.product_categories ?? []).map((entry) => entry.category_id);
}

function one<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) {
    return null;
  }
  return Array.isArray(value) ? (value[0] ?? null) : value;
}
