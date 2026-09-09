/**
 * Local development environment. Defaults point at the Supabase local stack
 * started with `supabase start`; replace the anon key with the one it prints.
 */
export const environment = {
  production: false,
  supabaseUrl: 'http://127.0.0.1:54321',
  supabaseAnonKey: 'SUPABASE_LOCAL_ANON_KEY_PLACEHOLDER',
  sessionIdleTimeoutMs: 8 * 60 * 60 * 1000,
  sessionAbsoluteTimeoutMs: 24 * 60 * 60 * 1000,
};
