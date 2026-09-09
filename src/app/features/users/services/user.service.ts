import { inject, Injectable } from '@angular/core';
import { toAppError } from '../../../core/error/error-handler';
import { SupabaseService } from '../../../core/auth/services/supabase.service';
import type { AppRole, UserProfile, UserStatus } from '../../../core/auth/models/user.model';

/** Payload for `create_internal_user`. Admins invite operators and agents, never peers. */
export interface CreateInternalUserInput {
  fullName: string;
  email: string;
  role: Exclude<AppRole, 'admin'>;
  temporaryPassword: string;
}

export interface CreatedInternalUser {
  id: string;
  full_name: string;
  email: string;
  role: AppRole;
  status: UserStatus;
  must_change_password: boolean;
}

export interface UserRoleUpdate {
  id: string;
  role: AppRole;
  updated_at: string;
}

export interface UserStatusUpdate {
  id: string;
  status: UserStatus;
  updated_at: string;
}

/**
 * Tenant-scoped collaborator directory and the admin-only mutations that go with it.
 *
 * Listing reads `user_profiles` and is narrowed by RLS. Create / role / status go through
 * SECURITY DEFINER RPCs that re-check `app_role` and `organization_id` on the server.
 */
@Injectable({ providedIn: 'root' })
export class UserService {
  private readonly supabase = inject(SupabaseService);

  async list(): Promise<UserProfile[]> {
    const { data, error } = await this.supabase.client
      .from('user_profiles')
      .select('*')
      .order('full_name', { ascending: true })
      .returns<UserProfile[]>();

    if (error) {
      throw toAppError(error);
    }

    return data ?? [];
  }

  async getById(id: string): Promise<UserProfile | null> {
    const { data, error } = await this.supabase.client
      .from('user_profiles')
      .select('*')
      .eq('id', id)
      .maybeSingle<UserProfile>();

    if (error) {
      throw toAppError(error);
    }

    return data;
  }

  async create(input: CreateInternalUserInput): Promise<CreatedInternalUser> {
    const { data, error } = await this.supabase.client.rpc('create_internal_user', {
      p_full_name: input.fullName.trim(),
      p_email: input.email.trim().toLowerCase(),
      p_role: input.role,
      p_temporary_password: input.temporaryPassword,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as CreatedInternalUser;
  }

  async updateRole(userId: string, newRole: AppRole): Promise<UserRoleUpdate> {
    const { data, error } = await this.supabase.client.rpc('update_user_role', {
      p_user_id: userId,
      p_new_role: newRole,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as UserRoleUpdate;
  }

  async toggleStatus(userId: string, status: UserStatus): Promise<UserStatusUpdate> {
    const { data, error } = await this.supabase.client.rpc('toggle_user_status', {
      p_user_id: userId,
      p_status: status,
    });

    if (error) {
      throw toAppError(error);
    }

    return data as UserStatusUpdate;
  }
}
