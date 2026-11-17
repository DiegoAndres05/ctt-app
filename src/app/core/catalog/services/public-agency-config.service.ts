import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../error/error-handler';
import { AuthService } from '../../auth/services/auth.service';
import { SupabaseService } from '../../auth/services/supabase.service';
import type {
  GeneratedPublicAccessKey,
  PublicAccessKey,
  PublicProfile,
  PublicProfileSettings,
  PublicSourceConfig,
  PublicTaxonomyValue,
  SavePublicProfilePayload,
  SaveTaxonomyValuePayload,
  TaxonomyKind,
} from '../models/public-agency-config.model';

const CATALOG_MEDIA_BUCKET = 'catalog-media';
const MAX_LOGO_BYTES = 2 * 1024 * 1024;
const LOGO_TYPES: Readonly<Record<string, string>> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/webp': 'webp',
};

/**
 * Agency-owned public configuration (feature 016). Every call is scoped by the backend to the
 * caller's organization; roles are re-checked in the SECURITY DEFINER RPCs.
 */
@Injectable({ providedIn: 'root' })
export class PublicAgencyConfigService {
  private readonly supabase = inject(SupabaseService);
  private readonly auth = inject(AuthService);

  // -------------------------------------------------------------------------
  // Taxonomies (US1)
  // -------------------------------------------------------------------------

  async listTaxonomy(): Promise<PublicTaxonomyValue[]> {
    const data = await this.rpc<PublicTaxonomyValue[]>('list_public_taxonomy_values');
    return Array.isArray(data) ? data : [];
  }

  async listTaxonomyOf(kind: TaxonomyKind): Promise<PublicTaxonomyValue[]> {
    return (await this.listTaxonomy()).filter((value) => value.kind === kind);
  }

  saveTaxonomyValue(payload: SaveTaxonomyValuePayload): Promise<PublicTaxonomyValue> {
    return this.rpc<PublicTaxonomyValue>('save_public_taxonomy_value', { p_payload: payload });
  }

  async deleteTaxonomyValue(kind: TaxonomyKind, code: string): Promise<void> {
    await this.rpc('delete_public_taxonomy_value', { p_kind: kind, p_code: code });
  }

  async deleteCategory(id: string): Promise<void> {
    await this.rpc('delete_public_category', { p_id: id });
  }

  // -------------------------------------------------------------------------
  // Public profile (US3)
  // -------------------------------------------------------------------------

  getProfile(): Promise<PublicProfileSettings> {
    return this.rpc<PublicProfileSettings>('get_public_profile');
  }

  saveProfile(payload: SavePublicProfilePayload): Promise<PublicProfile> {
    return this.rpc<PublicProfile>('save_public_profile', { p_payload: payload });
  }

  /** Uploads a logo into the agency folder of `catalog-media` and returns its storage path. */
  async uploadLogo(file: File): Promise<string> {
    if (file.size > MAX_LOGO_BYTES) {
      throw toAppError({ message: 'IMAGE_TOO_LARGE' });
    }
    const ext = LOGO_TYPES[file.type.toLowerCase()];
    if (!ext) {
      throw toAppError({ message: 'IMAGE_TYPE_NOT_ALLOWED' });
    }
    const organizationId = this.auth.organizationId();
    if (!organizationId) {
      throw toAppError({ message: 'MISSING_TENANT_CONTEXT' });
    }

    const path = `${organizationId}/profile/logo-${Date.now()}.${ext}`;
    const { error } = await this.supabase.client.storage
      .from(CATALOG_MEDIA_BUCKET)
      .upload(path, file, { contentType: file.type, upsert: false });
    if (error) {
      throw toAppError(error);
    }
    return path;
  }

  mediaUrl(ref: string | null | undefined): string | null {
    if (!ref) {
      return null;
    }
    if (/^https?:\/\//i.test(ref)) {
      return ref;
    }
    return this.supabase.client.storage.from(CATALOG_MEDIA_BUCKET).getPublicUrl(ref).data.publicUrl;
  }

  // -------------------------------------------------------------------------
  // Public access keys (US2, Administrator only)
  // -------------------------------------------------------------------------

  async listKeys(): Promise<PublicAccessKey[]> {
    const data = await this.rpc<PublicAccessKey[]>('list_public_access_keys');
    return Array.isArray(data) ? data : [];
  }

  generateKey(): Promise<GeneratedPublicAccessKey> {
    return this.rpc<GeneratedPublicAccessKey>('generate_public_access_key');
  }

  async revokeKey(keyId: string): Promise<void> {
    await this.rpc('revoke_public_access_key', { p_key_id: keyId });
  }

  // -------------------------------------------------------------------------
  // Source policy (US4, US5)
  // -------------------------------------------------------------------------

  async getSourceConfig(): Promise<PublicSourceConfig | null> {
    const { data, error } = await this.supabase.client
      .from('public_source_config')
      .select('organization_id, migration_required, organization_identifier_until')
      .maybeSingle();
    if (error) {
      throw toAppError(error);
    }
    return (data as PublicSourceConfig | null) ?? null;
  }

  async setMigrationRequired(required: boolean): Promise<void> {
    await this.rpc('set_public_source_migration', { p_migration_required: required });
  }

  async endIdentifierTransition(): Promise<void> {
    await this.rpc('end_organization_identifier_transition');
  }

  private async rpc<T>(name: string, args?: Record<string, unknown>): Promise<T> {
    const { data, error } = await this.supabase.client.rpc(name, args);
    if (error) {
      throw toAppError(error);
    }
    return data as T;
  }
}
