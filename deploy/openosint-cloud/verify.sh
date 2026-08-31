#!/usr/bin/env bash
# Check that a deployed gateway speaks MCP before wiring it into a connector.
#
#   deploy/openosint-cloud/verify.sh <base-url> <api-key>
#
# Example:
#   deploy/openosint-cloud/verify.sh https://my-app.herokuapp.com sk_xxx
set -euo pipefail

BASE="${1:-}"
KEY="${2:-}"
if [[ -z "$BASE" || -z "$KEY" ]]; then
  echo "Usage: $0 <base-url> <api-key>" >&2
  exit 1
fi
BASE="${BASE%/}"
URL="$BASE/mcp/"

body='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{
  "protocolVersion":"2025-06-18","capabilities":{},
  "clientInfo":{"name":"verify.sh","version":"1"}}}'

echo "POST $URL"
resp="$(curl -sS --max-time 30 -w $'\n__STATUS__%{http_code}' -X POST "$URL" \
  -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d "$body" 2>&1)" || {
    echo "Request failed — is the app up? (heroku logs --tail)" >&2
    exit 1
  }

status="${resp##*__STATUS__}"
payload="${resp%$'\n'__STATUS__*}"

echo "HTTP $status"
echo ""

if [[ "$status" == "200" ]]; then
  if grep -q '"serverInfo"' <<<"$payload"; then
    echo "OK — the endpoint completed an MCP initialize handshake."
    echo ""
    sed -n 's/.*"name":"\([^"]*\)".*"version":"\([^"]*\)".*/server: \1 \2/p' <<<"$payload" | head -1
    echo ""
    echo "Add this as a custom connector with Bearer auth:"
    echo "  $URL"
    exit 0
  fi
  echo "Unexpected 200 without serverInfo:"
  sed -e 's/^/  /' <<<"$payload" | head -20
  exit 1
fi

# Anything non-200 — surface the known failure modes by name.
if [[ "$status" == "500" ]]; then
  # Starlette returns a bare "Internal Server Error" body and logs the
  # traceback server-side, so the cause is not in this response. On /mcp a 500
  # is almost always the missing lifespan fix.
  echo "Most likely the /mcp lifespan fix is missing from this deploy." >&2
  echo "Confirm with:  heroku logs --tail -a <app>" >&2
  echo "and look for:  RuntimeError: Task group is not initialized" >&2
  echo "" >&2
  echo "If that is it, rebuild and push again:" >&2
  echo "  rm -rf .build && deploy/openosint-cloud/build.sh" >&2
elif [[ "$status" == "404" ]]; then
  echo "404 — check the trailing slash on /mcp/ and that the Procfile runs" >&2
  echo "'uvicorn cloud.main:app' rather than upstream's 'openosint web'." >&2
elif [[ "$status" == "503" || "$status" == "502" ]]; then
  echo "App is not serving. Check: heroku logs --tail -a <app>" >&2
fi

echo ""
sed -e 's/^/  /' <<<"$payload" | head -20
exit 1
