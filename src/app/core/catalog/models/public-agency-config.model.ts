/**
 * Agency-owned public configuration (feature 016): taxonomies, public profile, public access
 * keys and source policy. Row and payload shapes mirror the RPCs in
 * `supabase/migrations/059`–`063` (snake_case).
 */

export type TaxonomyKind = 'lodging_type' | 'amenity';

/** Row returned by `list_public_taxonomy_values` / `save_public_taxonomy_value`. */
export interface PublicTaxonomyValue {
  id: string;
  kind: TaxonomyKind;
  code: string;
  name_es: string;
  name_en: string;
  is_active: boolean;
  sort_order: number;
  /** True when a listing of the agency references the value; it can then only be deactivated. */
  in_use: boolean;
}

export interface SaveTaxonomyValuePayload {
  kind: TaxonomyKind;
  code: string;
  name_es: string;
  name_en: string;
  is_active: boolean;
  sort_order?: number;
}

export type PublicLanguage = 'es' | 'en';

export const SOCIAL_NETWORKS = [
  'instagram',
  'facebook',
  'tiktok',
  'youtube',
  'x',
  'linkedin',
  'tripadvisor',
] as const;

export type SocialNetwork = (typeof SOCIAL_NETWORKS)[number];

export const SOCIAL_NETWORK_LABELS: Readonly<Record<SocialNetwork, string>> = {
  instagram: 'Instagram',
  facebook: 'Facebook',
  tiktok: 'TikTok',
  youtube: 'YouTube',
  x: 'X',
  linkedin: 'LinkedIn',
  tripadvisor: 'Tripadvisor',
};

/** Shape returned by `get_public_profile` and `save_public_profile`. */
export interface PublicProfile {
  commercial_name: string;
  logo_ref: string | null;
  primary_color: string | null;
  contact_email: string | null;
  contact_phone: string | null;
  whatsapp: string | null;
  social_links: Partial<Record<SocialNetwork, string>>;
  languages: PublicLanguage[];
  currency: string;
  updated_at: string | null;
  updated_by_name: string | null;
}

export interface PublicProfileSettings extends PublicProfile {
  supported_currencies: string[];
  social_networks: string[];
}

export interface SavePublicProfilePayload {
  commercial_name: string;
  logo_ref: string | null;
  primary_color: string | null;
  contact_email: string | null;
  contact_phone: string | null;
  whatsapp: string | null;
  social_links: Partial<Record<SocialNetwork, string>>;
  languages: PublicLanguage[];
  currency: string;
}

export type PublicProfileField = keyof SavePublicProfilePayload;

export type PublicAccessKeyStatus = 'current' | 'grace' | 'expired' | 'revoked';

/** Metadata row from `list_public_access_keys`. Never carries the key itself. */
export interface PublicAccessKey {
  id: string;
  key_prefix: string;
  status: PublicAccessKeyStatus;
  created_at: string;
  created_by_name: string | null;
  expires_at: string | null;
  revoked_at: string | null;
  revoked_by_name: string | null;
  last_used_at: string | null;
}

/** Result of `generate_public_access_key`. `key` is shown once and never stored by the panel. */
export interface GeneratedPublicAccessKey {
  key: string;
  id: string;
  key_prefix: string;
  created_at: string;
  previous_key_id?: string;
  previous_key_expires_at?: string;
}

/** Days the previous key keeps working after a regeneration (clarification 2026-11-13). */
export const KEY_ROTATION_GRACE_DAYS = 7;

/** Row of `public.public_source_config`. */
export interface PublicSourceConfig {
  organization_id: string;
  migration_required: boolean;
  organization_identifier_until: string | null;
}

export const KEY_STATUS_LABELS: Readonly<Record<PublicAccessKeyStatus, string>> = {
  current: 'Vigente',
  grace: 'En transición',
  expired: 'Vencida',
  revoked: 'Revocada',
};

const CODE_PATTERN = /^[a-z0-9]+(_[a-z0-9]+)*$/;

/** Stable identifier rule shared with the SQL check constraints. */
export function isValidTaxonomyCode(code: string): boolean {
  return code.length > 0 && code.length <= 40 && CODE_PATTERN.test(code);
}

/** Suggests a code from a label: «Vista al mar» → `vista_al_mar`. */
export function suggestTaxonomyCode(label: string): string {
  return label
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40)
    .replace(/_+$/g, '');
}

/** True while the CTT organization-identifier access is still accepted. */
export function isIdentifierAccessOpen(
  config: PublicSourceConfig | null,
  now: Date = new Date(),
): boolean {
  if (!config?.migration_required || !config.organization_identifier_until) {
    return false;
  }
  return new Date(config.organization_identifier_until).getTime() > now.getTime();
}

const HEX_COLOR = /^#[0-9A-F]{6}$/;
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PHONE = /^\+?[0-9 ()-]{7,25}$/;
const HTTPS_URL = /^https:\/\/\S+$/;

/**
 * Client-side mirror of `save_public_profile` validation. Returns the first message per field;
 * the server stays the authority.
 */
export function validatePublicProfile(
  payload: SavePublicProfilePayload,
  supportedCurrencies: readonly string[],
): Partial<Record<PublicProfileField, string>> {
  const errors: Partial<Record<PublicProfileField, string>> = {};
  const name = payload.commercial_name.trim();

  if (!name) {
    errors.commercial_name = 'Ingresa el nombre comercial.';
  } else if (name.length > 120) {
    errors.commercial_name = 'Usa como máximo 120 caracteres.';
  }
  if (payload.primary_color && !HEX_COLOR.test(payload.primary_color.toUpperCase())) {
    errors.primary_color = 'Usa un color en formato #RRGGBB.';
  }
  if (payload.contact_email && !EMAIL.test(payload.contact_email.trim())) {
    errors.contact_email = 'El correo no tiene un formato válido.';
  }
  if (payload.contact_phone && !PHONE.test(payload.contact_phone.trim())) {
    errors.contact_phone = 'Usa solo números, espacios, paréntesis, guiones y el signo +.';
  }
  if (payload.whatsapp && !PHONE.test(payload.whatsapp.trim())) {
    errors.whatsapp = 'Usa solo números, espacios, paréntesis, guiones y el signo +.';
  }
  const badLink = Object.values(payload.social_links).some(
    (url) => url && url.trim() !== '' && !HTTPS_URL.test(url.trim()),
  );
  if (badLink) {
    errors.social_links = 'Cada enlace debe empezar por https://.';
  }
  if (payload.languages.length === 0) {
    errors.languages = 'Elige al menos un idioma.';
  }
  if (!supportedCurrencies.includes(payload.currency)) {
    errors.currency = 'Elige una moneda de la lista.';
  }
  return errors;
}
