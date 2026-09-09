/**
 * Default (production) environment.
 *
 * `supabaseAnonKey` is the public anon key: it is safe to ship to the browser because every
 * request it authorizes is still evaluated by Row Level Security. The service role key is
 * NEVER referenced from the frontend.
 *
 * Values below are placeholders and must be replaced by the deployment pipeline.
 */
export const environment = {
  production: true,
  supabaseUrl: 'SUPABASE_URL_PLACEHOLDER',
  supabaseAnonKey: 'SUPABASE_ANON_KEY_PLACEHOLDER',
  /** Session invalidated after this much inactivity (8h inactivity limit). */
  sessionIdleTimeoutMs: 8 * 60 * 60 * 1000,
  /** Session invalidated this long after it was issued, regardless of activity (24h absolute). */
  sessionAbsoluteTimeoutMs: 24 * 60 * 60 * 1000,
};
