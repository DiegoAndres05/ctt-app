import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { AuthService } from '../../auth/services/auth.service';
import { SupabaseService } from '../../auth/services/supabase.service';
import type { Category } from '../models/category.model';

export interface CreateCategoryInput {
  name: string;
  parentId?: string | null;
}

export interface UpdateCategoryInput {
  name: string;
  parentId?: string | null;
}

/**
 * Organization taxonomies and N:M product tagging. All writes go through PostgREST; RLS
 * restricts mutations to operator/admin of the caller's tenant.
 */
@Injectable({ providedIn: 'root' })
export class CategoryService {
  private readonly supabase = inject(SupabaseService);
  private readonly auth = inject(AuthService);

  async list(): Promise<Category[]> {
    const { data, error } = await this.supabase.client
      .from('categories')
      .select('*')
      .order('name', { ascending: true })
      .returns<Category[]>();

    if (error) {
      throw toAppError(error);
    }

    return data ?? [];
  }

  async create(input: CreateCategoryInput): Promise<Category> {
    const organizationId = this.requireOrganizationId();
    const name = input.name.trim();
    const { data, error } = await this.supabase.client
      .from('categories')
      .insert({
        organization_id: organizationId,
        name,
        slug: slugify(name),
        parent_id: input.parentId || null,
      })
      .select('*')
      .single<Category>();

    if (error) {
      throw toAppError(error);
    }

    return data;
  }

  async update(id: string, input: UpdateCategoryInput): Promise<Category> {
    const name = input.name.trim();
    const { data, error } = await this.supabase.client
      .from('categories')
      .update({
        name,
        slug: slugify(name),
        parent_id: input.parentId || null,
      })
      .eq('id', id)
      .select('*')
      .single<Category>();

    if (error) {
      throw toAppError(error);
    }

    return data;
  }

  async remove(id: string): Promise<void> {
    const { error } = await this.supabase.client.from('categories').delete().eq('id', id);

    if (error) {
      throw toAppError(error);
    }
  }

  async listAssignedIds(productId: string): Promise<string[]> {
    const { data, error } = await this.supabase.client
      .from('product_categories')
      .select('category_id')
      .eq('product_id', productId);

    if (error) {
      throw toAppError(error);
    }

    return (data ?? []).map((row) => row.category_id);
  }

  async replaceAssignments(productId: string, categoryIds: string[]): Promise<void> {
    const organizationId = this.requireOrganizationId();
    const uniqueIds = [...new Set(categoryIds.filter(Boolean))];

    const { error: deleteError } = await this.supabase.client
      .from('product_categories')
      .delete()
      .eq('product_id', productId);

    if (deleteError) {
      throw toAppError(deleteError);
    }

    if (uniqueIds.length === 0) {
      return;
    }

    const { error: insertError } = await this.supabase.client.from('product_categories').insert(
      uniqueIds.map((categoryId) => ({
        product_id: productId,
        category_id: categoryId,
        organization_id: organizationId,
      })),
    );

    if (insertError) {
      throw toAppError(insertError);
    }
  }

  private requireOrganizationId(): string {
    const organizationId = this.auth.user()?.organizationId;
    if (!organizationId) {
      throw toAppError(new Error('MISSING_TENANT_CONTEXT'));
    }
    return organizationId;
  }
}

/** Organization-scoped URL-safe identifier derived from the category name. */
export function slugify(value: string): string {
  const slug = value
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
  return slug || 'categoria';
}
