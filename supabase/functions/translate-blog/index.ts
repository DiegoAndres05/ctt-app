// Authenticated proxy to the self-hosted translator (spec 017, ADR-0005).
//
// The browser never talks to LibreTranslate: this function requires the user's JWT
// (verify_jwt = true), checks role and the hourly character quota through
// consume_blog_translation_quota() using that same session, caps the size of one part and
// forwards the segments with a timeout. The panel sends a long article as several parts.
// Article text is never logged or stored (FR-014): logs carry only codes, counts and durations.
//
// Contract: specs/017-blog-translation/contracts/translate-blog.md

import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const LOCALES = new Set(['es', 'en']);
/** One part. Keep in sync with TRANSLATION_PART_* in the panel and c_max_request in 072. */
const MAX_SEGMENTS = 40;
const MAX_CHARACTERS = 5000;
const TRANSLATOR_TIMEOUT_MS = 55_000;

type Code =
  | 'VALIDATION_ERROR'
  | 'SESSION_EXPIRED'
  | 'FORBIDDEN'
  | 'TRANSLATION_TOO_LARGE'
  | 'TRANSLATION_RATE_LIMITED'
  | 'TRANSLATION_UNAVAILABLE';

const STATUS: Record<Code, number> = {
  VALIDATION_ERROR: 400,
  SESSION_EXPIRED: 401,
  FORBIDDEN: 403,
  TRANSLATION_TOO_LARGE: 413,
  TRANSLATION_RATE_LIMITED: 429,
  TRANSLATION_UNAVAILABLE: 503,
};

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (request.method !== 'POST') {
    return failure('VALIDATION_ERROR');
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const authorization = request.headers.get('Authorization');
  if (!supabaseUrl || !anonKey) {
    return failure('TRANSLATION_UNAVAILABLE');
  }
  if (!authorization) {
    return failure('SESSION_EXPIRED');
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return failure('VALIDATION_ERROR');
  }
  const parsed = readBody(body);
  if (typeof parsed === 'string') {
    return failure(parsed);
  }

  // Role and quota, as the calling user (RLS and auth.jwt() see the real session).
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: quotaError } = await supabase.rpc('consume_blog_translation_quota', {
    p_characters: parsed.characters,
  });
  if (quotaError) {
    const code = mapRpcError(quotaError.message);
    if (code === 'TRANSLATION_RATE_LIMITED') {
      return failure(code, { retryAt: readRetryAt(quotaError.details) });
    }
    return failure(code);
  }

  const translatorUrl = Deno.env.get('LIBRETRANSLATE_URL');
  if (!translatorUrl) {
    log('not_configured', parsed.segments.length, 0);
    return failure('TRANSLATION_UNAVAILABLE');
  }

  const started = Date.now();
  try {
    const response = await fetch(`${translatorUrl.replace(/\/+$/, '')}/translate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        q: parsed.segments,
        source: parsed.source,
        target: parsed.target,
        format: 'html',
        api_key: Deno.env.get('LIBRETRANSLATE_API_KEY') ?? '',
      }),
      signal: AbortSignal.timeout(TRANSLATOR_TIMEOUT_MS),
    });
    if (!response.ok) {
      log(`translator_http_${response.status}`, parsed.segments.length, Date.now() - started);
      return failure('TRANSLATION_UNAVAILABLE');
    }
    const result = (await response.json()) as { translatedText?: unknown };
    const translated = result.translatedText;
    if (
      !Array.isArray(translated) ||
      translated.length !== parsed.segments.length ||
      !translated.every((item) => typeof item === 'string')
    ) {
      log('translator_bad_response', parsed.segments.length, Date.now() - started);
      return failure('TRANSLATION_UNAVAILABLE');
    }
    log('ok', parsed.segments.length, Date.now() - started);
    return json({ segments: translated }, 200);
  } catch (error) {
    const reason =
      error instanceof DOMException && error.name === 'TimeoutError' ? 'timeout' : 'unreachable';
    log(`translator_${reason}`, parsed.segments.length, Date.now() - started);
    return failure('TRANSLATION_UNAVAILABLE');
  }
});

interface TranslateBody {
  source: string;
  target: string;
  segments: string[];
  characters: number;
}

function readBody(body: unknown): TranslateBody | Code {
  if (typeof body !== 'object' || body === null) {
    return 'VALIDATION_ERROR';
  }
  const { source, target, segments } = body as Record<string, unknown>;
  if (
    typeof source !== 'string' ||
    typeof target !== 'string' ||
    !LOCALES.has(source) ||
    !LOCALES.has(target) ||
    source === target ||
    !Array.isArray(segments) ||
    segments.length === 0 ||
    !segments.every((segment) => typeof segment === 'string' && segment.trim() !== '')
  ) {
    return 'VALIDATION_ERROR';
  }
  const characters = (segments as string[]).reduce((total, segment) => total + segment.length, 0);
  if (segments.length > MAX_SEGMENTS || characters > MAX_CHARACTERS) {
    return 'TRANSLATION_TOO_LARGE';
  }
  return { source, target, segments: segments as string[], characters };
}

function mapRpcError(message: string | undefined): Code {
  switch (message) {
    case 'FORBIDDEN':
    case 'SESSION_EXPIRED':
    case 'VALIDATION_ERROR':
    case 'TRANSLATION_RATE_LIMITED':
      return message;
    default:
      // A missing or invalid JWT surfaces as a PostgREST/auth error.
      return message?.includes('JWT') ? 'SESSION_EXPIRED' : 'TRANSLATION_UNAVAILABLE';
  }
}

function readRetryAt(details: string | undefined): string | null {
  try {
    const value = JSON.parse(details ?? '') as { retry_at?: unknown };
    return typeof value.retry_at === 'string' ? value.retry_at : null;
  } catch {
    return null;
  }
}

function log(outcome: string, segments: number, ms: number): void {
  console.log(JSON.stringify({ fn: 'translate-blog', outcome, segments, ms }));
}

function failure(code: Code, extra: Record<string, unknown> = {}): Response {
  return json({ code, ...extra }, STATUS[code]);
}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}
