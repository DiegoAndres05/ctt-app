/**
 * Local development environment. Defaults point at the Supabase local stack
 * started with `supabase start`; replace the anon key with the one it prints.
 */
export const environment = {
  production: false,
  supabaseUrl: 'http://127.0.0.1:54321',
  supabaseAnonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  sessionIdleTimeoutMs: 8 * 60 * 60 * 1000,
  sessionAbsoluteTimeoutMs: 24 * 60 * 60 * 1000,
};
