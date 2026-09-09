// Public onboarding endpoint (User Story 5 / FR-008).
//
// Coordinates three stores that cannot share a single PostgreSQL transaction:
//   1. create the auth user through the Admin API (bcrypt in auth.users — FR-007);
//   2. invoke public.register_agency, which inserts the tenant and the admin profile atomically;
//   3. if the RPC fails, delete the auth user so the three stores do not drift.
//
// JWT verification is disabled in config.toml: this is a public form. Authorization is the
// service role key (never shipped to the browser) plus the RPC's own tenant-safety checks.
// The application role still travels in `app_role`, never in the reserved `role` claim
// (ADR-0002). Credentials are never logged.

import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MIN_PASSWORD_LENGTH = 8;
const MAX_PASSWORD_BYTES = 72;
const MAX_TEXT_LENGTH = 255;

type ContractCode =
  | 'VALIDATION_ERROR'
  | 'EMAIL_ALREADY_EXISTS'
  | 'AGENCY_SLUG_EXISTS'
  | 'REGISTRATION_FAILED';

interface RegisterAgencyBody {
  agency_name?: unknown;
  full_name?: unknown;
  email?: unknown;
  password?: unknown;
}

interface RegisterAgencyRpcResult {
  organization_id: string;
  slug: string;
  name: string;
  user_id: string;
  email: string;
  full_name: string;
  role: 'admin';
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ code: 'VALIDATION_ERROR' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');

  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return jsonResponse({ code: 'REGISTRATION_FAILED' }, 500);
  }

  let body: RegisterAgencyBody;
  try {
    body = (await request.json()) as RegisterAgencyBody;
  } catch {
    return jsonResponse({ code: 'VALIDATION_ERROR' }, 400);
  }

  const agencyName = readText(body.agency_name);
  const fullName = readText(body.full_name);
  const email = readText(body.email)?.toLowerCase();
  const password = typeof body.password === 'string' ? body.password : '';

  if (
    !agencyName ||
    agencyName.length > MAX_TEXT_LENGTH ||
    !fullName ||
    fullName.length > MAX_TEXT_LENGTH ||
    !email ||
    !isEmail(email) ||
    password.length < MIN_PASSWORD_LENGTH ||
    byteLength(password) > MAX_PASSWORD_BYTES
  ) {
    return jsonResponse({ code: 'VALIDATION_ERROR' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  });

  if (createError || !created.user) {
    const code = mapAuthCreateError(createError?.message);
    return jsonResponse({ code }, statusFor(code));
  }

  const userId = created.user.id;
  let rolledBack = false;

  const rollback = async (): Promise<void> => {
    if (rolledBack) {
      return;
    }
    rolledBack = true;
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error('[register-agency] failed to roll back auth user', userId);
    }
  };

  try {
    const { data: rpcData, error: rpcError } = await admin.rpc('register_agency', {
      p_agency_name: agencyName,
      p_admin_user_id: userId,
      p_full_name: fullName,
      p_email: email,
    });

    if (rpcError) {
      await rollback();
      const code = mapRpcError(rpcError.message);
      return jsonResponse({ code }, statusFor(code));
    }

    const registered = rpcData as RegisterAgencyRpcResult | null;
    if (!registered?.organization_id || !registered.user_id) {
      await rollback();
      return jsonResponse({ code: 'REGISTRATION_FAILED' }, 500);
    }

    // Sign-in goes through GoTrue so custom_access_token_hook injects organization_id and
    // app_role, and password_verification_hook records login_success. The password is the one
    // the founder just chose; it is not logged.
    const anon = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: sessionData, error: signInError } = await anon.auth.signInWithPassword({
      email,
      password,
    });

    if (signInError || !sessionData.session) {
      // Tenant and profile already exist; do not delete the auth user. The founder can sign
      // in from the login screen. Returning 500 without a session is still a failed onboarding
      // from the client's point of view.
      return jsonResponse({ code: 'REGISTRATION_FAILED' }, 500);
    }

    return jsonResponse(
      {
        data: {
          organization: {
            id: registered.organization_id,
            name: registered.name,
            slug: registered.slug,
          },
          user: {
            id: registered.user_id,
            email: registered.email,
            full_name: registered.full_name,
            role: 'admin' as const,
          },
          session: {
            access_token: sessionData.session.access_token,
            refresh_token: sessionData.session.refresh_token,
            expires_in: sessionData.session.expires_in,
          },
        },
      },
      201,
    );
  } catch (failure) {
    await rollback();
    const message = failure instanceof Error ? failure.message : '';
    const code = mapRpcError(message);
    return jsonResponse({ code }, statusFor(code));
  }
});

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function readText(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function byteLength(value: string): number {
  return new TextEncoder().encode(value).length;
}

function mapAuthCreateError(message: string | undefined): ContractCode {
  const text = (message ?? '').toLowerCase();
  if (text.includes('already') || text.includes('registered') || text.includes('exists')) {
    return 'EMAIL_ALREADY_EXISTS';
  }
  if (text.includes('password') || text.includes('invalid') || text.includes('email')) {
    return 'VALIDATION_ERROR';
  }
  return 'REGISTRATION_FAILED';
}

function mapRpcError(message: string): ContractCode {
  if (message.includes('EMAIL_ALREADY_EXISTS')) {
    return 'EMAIL_ALREADY_EXISTS';
  }
  if (message.includes('AGENCY_SLUG_EXISTS')) {
    return 'AGENCY_SLUG_EXISTS';
  }
  if (message.includes('VALIDATION_ERROR')) {
    return 'VALIDATION_ERROR';
  }
  return 'REGISTRATION_FAILED';
}

function statusFor(code: ContractCode): number {
  switch (code) {
    case 'VALIDATION_ERROR':
      return 400;
    case 'EMAIL_ALREADY_EXISTS':
    case 'AGENCY_SLUG_EXISTS':
      return 409;
    default:
      return 500;
  }
}
