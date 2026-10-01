/**
 * Internal collaborator domain types.
 *
 * Row shapes mirror `public.user_profiles` column-for-column. No password material ever
 * appears here: credentials live in `auth.users` and are managed by Supabase Auth (FR-007).
 */

/** Mirrors the `public.app_role` enum. */
export type AppRole = 'admin' | 'operator' | 'agent';

/** Mirrors the `public.user_status` enum. */
export type UserStatus = 'active' | 'inactive';

/** A row of `public.user_profiles`. */
export interface UserProfile {
  id: string;
  organization_id: string;
  full_name: string;
  email: string;
  role: AppRole;
  status: UserStatus;
  must_change_password: boolean;
  failed_login_attempts: number;
  locked_until: string | null;
  last_activity_at: string | null;
  created_at: string;
  updated_at: string;
}

/**
 * Roles inherit downwards: an admin may perform any operator or agent action.
 * Higher number means broader authority.
 */
export const ROLE_RANK: Readonly<Record<AppRole, number>> = {
  admin: 3,
  operator: 2,
  agent: 1,
};

/**
 * Whether `actual` satisfies a requirement for at least `required`.
 *
 * This drives UI affordances only. Every authorization decision is re-evaluated in the
 * database by RLS, which does not trust anything the browser computed.
 */
export function hasRoleAtLeast(actual: AppRole | null, required: AppRole): boolean {
  return actual !== null && ROLE_RANK[actual] >= ROLE_RANK[required];
}

/** Spanish label for the application role shown in the shell, lists, and matrix. */
export function roleLabel(role: AppRole): string {
  switch (role) {
    case 'admin':
      return 'Administrador';
    case 'operator':
      return 'Operador';
    case 'agent':
      return 'Agente';
  }
}
