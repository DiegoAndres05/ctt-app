/**
 * Organization (tenant) domain types.
 *
 * Row shapes mirror `public.organizations` column-for-column, including snake_case naming,
 * so that what PostgREST returns can be consumed without a translation layer and so the
 * correspondence with `specs/001-auth-tenant-access/data-model.md` stays checkable by eye.
 */

/** Mirrors the `public.organization_status` enum. */
export type OrganizationStatus = 'active' | 'suspended' | 'inactive';

/** A row of `public.organizations`. */
export interface Organization {
  id: string;
  name: string;
  slug: string;
  status: OrganizationStatus;
  settings: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
}
