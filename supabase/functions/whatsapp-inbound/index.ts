// WhatsApp Cloud API inbound adapter (feature 003 / FR-009).
//
// Meta calls this function directly. JWT verification is disabled in config.toml because
// the caller is Meta, not a signed-in collaborator. Authorization is the HMAC in
// X-Hub-Signature-256 (WHATSAPP_APP_SECRET). The raw body is forwarded to
// public.ingest_whatsapp_webhook, which is the only code that understands Meta's JSON.
//
// Without WHATSAPP_APP_SECRET the adapter answers CHANNEL_NOT_CONFIGURED and does nothing.
// Logs contain the outcome code and counters only — never the body, a phone, or the signature.

import { createClient } from 'npm:@supabase/supabase-js@2';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === 'GET') {
    return verifyHandshake(request);
  }
  if (request.method === 'POST') {
    return ingest(request);
  }
  return json({ code: 'VALIDATION_ERROR' }, 405);
});

function verifyHandshake(request: Request): Response {
  const verifyToken = Deno.env.get('WHATSAPP_VERIFY_TOKEN');
  if (!verifyToken) {
    console.log(JSON.stringify({ code: 'CHANNEL_NOT_CONFIGURED' }));
    return json({ code: 'CHANNEL_NOT_CONFIGURED' }, 503);
  }

  const url = new URL(request.url);
  const mode = url.searchParams.get('hub.mode');
  const token = url.searchParams.get('hub.verify_token');
  const challenge = url.searchParams.get('hub.challenge');

  if (mode === 'subscribe' && token === verifyToken && challenge) {
    console.log(JSON.stringify({ code: 'VERIFIED' }));
    return new Response(challenge, { status: 200, headers: { 'Content-Type': 'text/plain' } });
  }

  console.log(JSON.stringify({ code: 'FORBIDDEN' }));
  return new Response('Forbidden', { status: 403 });
}

async function ingest(request: Request): Promise<Response> {
  const appSecret = Deno.env.get('WHATSAPP_APP_SECRET');
  if (!appSecret) {
    console.log(JSON.stringify({ code: 'CHANNEL_NOT_CONFIGURED' }));
    return json({ code: 'CHANNEL_NOT_CONFIGURED' }, 503);
  }

  const rawBody = await request.text();
  const signature = request.headers.get('X-Hub-Signature-256');
  const valid = await verifySignature(appSecret, rawBody, signature);
  if (!valid) {
    console.log(JSON.stringify({ code: 'INVALID_SIGNATURE' }));
    return json({ code: 'INVALID_SIGNATURE' }, 401);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    console.log(JSON.stringify({ code: 'VALIDATION_ERROR' }));
    return json({ code: 'VALIDATION_ERROR' }, 400);
  }

  if (!isWhatsappPayload(payload)) {
    console.log(JSON.stringify({ code: 'VALIDATION_ERROR' }));
    return json({ code: 'VALIDATION_ERROR' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.log(JSON.stringify({ code: 'INGEST_FAILED' }));
    return json({ code: 'INGEST_FAILED' }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await admin.rpc('ingest_whatsapp_webhook', { p_payload: payload });
  if (error || !data || typeof data !== 'object') {
    console.log(JSON.stringify({ code: 'INGEST_FAILED' }));
    return json({ code: 'INGEST_FAILED' }, 500);
  }

  const counters = data as Record<string, unknown>;
  console.log(
    JSON.stringify({
      code: 'OK',
      processed: counters['processed'],
      duplicates: counters['duplicates'],
      ignored: counters['ignored'],
      requests_created: counters['requests_created'],
      messages_attached: counters['messages_attached'],
    }),
  );
  return json(counters, 200);
}

function isWhatsappPayload(value: unknown): value is { object: string } {
  return (
    typeof value === 'object' &&
    value !== null &&
    'object' in value &&
    (value as { object?: unknown }).object === 'whatsapp_business_account'
  );
}

async function verifySignature(
  secret: string,
  rawBody: string,
  header: string | null,
): Promise<boolean> {
  if (!header || !header.startsWith('sha256=')) {
    return false;
  }
  const presented = header.slice('sha256='.length).trim().toLowerCase();
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  const expected = [...new Uint8Array(mac)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return timingSafeEqual(expected, presented);
}

/** Compares hex strings without short-circuiting on the first mismatch. */
function timingSafeEqual(expected: string, presented: string): boolean {
  const left = new TextEncoder().encode(expected);
  const right = new TextEncoder().encode(presented);
  const length = Math.max(left.length, right.length);
  let diff = left.length ^ right.length;
  for (let index = 0; index < length; index += 1) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return diff === 0;
}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}
