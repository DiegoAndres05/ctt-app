export const environment = {
  production: true,
  supabaseUrl: 'http://localhost:4200/supabase',
  supabaseAnonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  sessionIdleTimeoutMs: 8 * 60 * 60 * 1000,
  sessionAbsoluteTimeoutMs: 24 * 60 * 60 * 1000,
};
