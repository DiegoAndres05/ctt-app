import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { AuthService } from '../../auth/services/auth.service';
import { SupabaseService } from '../../auth/services/supabase.service';
import type { Addon, AddonUnit, ProductAddon, ProductAddonWithAddon } from '../models/addon.model';

export interface CreateAddonInput {
  name: string;
  description?: string | null;
  unit: AddonUnit;
  isActive?: boolean;
}

export interface UpdateAddonInput {
  name: string;
  description?: string | null;
  unit: AddonUnit;
  isActive: boolean;
}

export interface LinkAddonInput {
  productId: string;
  addonId: string;
  isMandatory: boolean;
  maxQuantity: number | null;
}

/**
 * Independent add-ons and their eligibility on products. Writes go through PostgREST; RLS
 * restricts mutations to operator/admin of the caller's tenant.
 */
@Injectable({ providedIn: 'root' })
export class AddonService {
  private readonly supabase = inject(SupabaseService);
  private readonly auth = inject(AuthService);

  async list(): Promise<Addon[]> {
    const { data, error } = await this.supabase.client
      .from('add_ons')
      .select('*')
      .order('name', { ascending: true })
      .returns<Addon[]>();

    if (error) {
      throw toAppError(error);
    }

    return data ?? [];
  }

  async getById(id: string): Promise<Addon | null> {
    const { data, error } = await this.supabase.client
      .from('add_ons')
      .select('*')
      .eq('id', id)
      .maybeSingle<Addon>();

    if (error) {
      throw toAppError(error);
    }

    return data;
  }

  async create(input: CreateAddonInput): Promise<Addon> {
    const organizationId = this.requireOrganizationId();
    const { data, error } = await this.supabase.client
      .from('add_ons')
      .insert({
        organization_id: organizationId,
        name: input.name.trim(),
        description: input.description?.trim() || null,
        unit: input.unit,
        is_active: input.isActive ?? true,
      })
      .select('*')
      .single<Addon>();

    if (error) {
      throw toAppError(error);
    }

    return data;
  }

  async update(id: string, input: UpdateAddonInput): Promise<Addon> {
    const { data, error } = await this.supabase.client
      .from('add_ons')
      .update({
        name: input.name.trim(),
        description: input.description?.trim() || null,
        unit: input.unit,
        is_active: input.isActive,
      })
      .eq('id', id)
      .select('*')
      .single<Addon>();

    if (error) {
      throw toAppError(error);
    }

    return data;
  }

  async remove(id: string): Promise<void> {
    const { error } = await this.supabase.client.from('add_ons').delete().eq('id', id);

    if (error) {
      throw toAppError(error);
    }
  }

  async listForProduct(productId: string): Promise<ProductAddonWithAddon[]> {
    const { data, error } = await this.supabase.client
      .from('product_addons')
      .select('*, add_ons(*)')
      .eq('product_id', productId)
      .returns<ProductAddonWithAddon[]>();

    if (error) {
      throw toAppError(error);
    }

    return data ?? [];
  }

  async linkToProduct(input: LinkAddonInput): Promise<ProductAddon> {
    const organizationId = this.requireOrganizationId();
    const { data, error } = await this.supabase.client
      .from('product_addons')
      .insert({
        organization_id: organizationId,
        product_id: input.productId,
        addon_id: input.addonId,
        is_mandatory: input.isMandatory,
        max_quantity: input.maxQuantity,
      })
      .select('*')
      .single<ProductAddon>();

    if (error) {
      throw toAppError(error);
    }

    return data;
  }

  async updateLink(
    id: string,
    patch: { isMandatory: boolean; maxQuantity: number | null },
  ): Promise<ProductAddon> {
    const { data, error } = await this.supabase.client
      .from('product_addons')
      .update({
        is_mandatory: patch.isMandatory,
        max_quantity: patch.maxQuantity,
      })
      .eq('id', id)
      .select('*')
      .single<ProductAddon>();

    if (error) {
      throw toAppError(error);
    }

    return data;
  }

  async unlinkFromProduct(id: string): Promise<void> {
    const { error } = await this.supabase.client.from('product_addons').delete().eq('id', id);

    if (error) {
      throw toAppError(error);
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
