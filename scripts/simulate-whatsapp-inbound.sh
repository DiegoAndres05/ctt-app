#!/usr/bin/env bash
# Signs fixtures/text-message.json with the local app secret and POSTs it to the
# whatsapp-inbound Edge Function. No real Meta credentials are required.
#
# Quickstart scenario 6:
#   ./scripts/simulate-whatsapp-inbound.sh                         # requests_created: 1
#   ./scripts/simulate-whatsapp-inbound.sh                         # same wamid → duplicates: 1
#   WAMID=wamid.local-2 ./scripts/simulate-whatsapp-inbound.sh     # messages_attached: 1
#   PHONE_NUMBER_ID=unknown ./scripts/simulate-whatsapp-inbound.sh # ignored: 1
#   SECRET=otro ./scripts/simulate-whatsapp-inbound.sh             # 401 INVALID_SIGNATURE
#
# SECRET, if unset, is read from supabase/functions/.env (WHATSAPP_APP_SECRET).
# URL defaults to the local functions gateway.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${URL:-http://127.0.0.1:54321/functions/v1/whatsapp-inbound}"
WAMID="${WAMID:-wamid.local-1}"
PHONE_NUMBER_ID="${PHONE_NUMBER_ID:-local-dev-phone-number-id}"
FIXTURE="$ROOT/supabase/functions/whatsapp-inbound/fixtures/text-message.json"

if [[ -z "${SECRET:-}" ]]; then
  ENV_FILE="$ROOT/supabase/functions/.env"
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "WHATSAPP_APP_SECRET is not set and $ENV_FILE is missing." >&2
    echo "Copy supabase/functions/.env.example to supabase/functions/.env." >&2
    exit 1
  fi
  SECRET="$(grep -E '^WHATSAPP_APP_SECRET=' "$ENV_FILE" | head -n 1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
fi

if [[ -z "$SECRET" ]]; then
  echo "WHATSAPP_APP_SECRET is empty." >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

sed \
  -e "s|wamid.local-1|${WAMID}|g" \
  -e "s|local-dev-phone-number-id|${PHONE_NUMBER_ID}|g" \
  "$FIXTURE" >"$tmp"

signature="$(openssl dgst -sha256 -hmac "$SECRET" -hex "$tmp" | awk '{print $NF}')"

curl --silent --show-error \
  --data-binary @"$tmp" \
  -H "X-Hub-Signature-256: sha256=${signature}" \
  -H 'Content-Type: application/json' \
  "$URL"
echo
