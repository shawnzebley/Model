#!/usr/bin/env bash
# Deploy the OpenOSINT Cloud gateway to Heroku, end to end.
#
#   deploy/openosint-cloud/deploy-heroku.sh <app-name>
#
# Creates real, billable infrastructure and puts a service on the public
# internet. It prompts before the first creating step and is safe to re-run:
# existing app, addon, and config vars are reused rather than replaced.
#
# Run this from your own machine — it needs the Heroku CLI and network access
# to heroku.com.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$REPO_ROOT/deploy/openosint-cloud"
BUILD_DIR="$REPO_ROOT/.build/openosint-cloud"

APP="${1:-}"
if [[ -z "$APP" ]]; then
  echo "Usage: $0 <app-name>" >&2
  exit 1
fi

command -v heroku >/dev/null 2>&1 || {
  echo "Heroku CLI not found. Install: https://devcenter.heroku.com/articles/heroku-cli" >&2
  exit 1
}
heroku auth:whoami >/dev/null 2>&1 || {
  echo "Not logged in. Run: heroku login" >&2
  exit 1
}

echo "Deploying as $(heroku auth:whoami) to app '$APP'."
read -r -p "Continue? [y/N] " reply
[[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "Aborted."; exit 1; }

# ── 1. build ──────────────────────────────────────────────────────────────────
if [[ ! -d "$BUILD_DIR" ]]; then
  "$HERE/build.sh"
else
  echo "Reusing existing build at $BUILD_DIR"
fi
# dbsetup.py runs on the dyno, so it has to be inside the pushed repo.
cp "$HERE/dbsetup.py" "$BUILD_DIR/dbsetup.py"
cd "$BUILD_DIR"
git add -A
git -c user.email=deploy@localhost -c user.name=deploy diff --cached --quiet || \
  git -c user.email=deploy@localhost -c user.name=deploy commit --quiet -m "Add dbsetup.py"

# ── 2. app ────────────────────────────────────────────────────────────────────
if heroku apps:info -a "$APP" >/dev/null 2>&1; then
  echo "App '$APP' exists — reusing."
else
  echo "Creating app '$APP' ..."
  heroku create "$APP"
fi

# ── 3. postgres ───────────────────────────────────────────────────────────────
if heroku config:get DATABASE_URL -a "$APP" | grep -q .; then
  echo "Postgres already attached."
else
  echo "Provisioning Postgres (essential-0, billable) ..."
  heroku addons:create heroku-postgresql:essential-0 -a "$APP" --wait
fi

# ── 4. secrets ────────────────────────────────────────────────────────────────
# Both are required once DATABASE_URL is set: the app refuses to boot without
# SESSION_SECRET_KEY, and CONFIG_ENCRYPTION_KEY is the Fernet key encrypting
# stored BYOK secrets. Never regenerate CONFIG_ENCRYPTION_KEY on an existing
# deploy — it would orphan every stored key.
set_if_absent() {
  local name="$1" value="$2"
  if heroku config:get "$name" -a "$APP" | grep -q .; then
    echo "$name already set — keeping it."
  else
    echo "Setting $name ..."
    heroku config:set "$name=$value" -a "$APP" >/dev/null
  fi
}
set_if_absent SESSION_SECRET_KEY \
  "$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')"
set_if_absent CONFIG_ENCRYPTION_KEY \
  "$(python3 -c 'from cryptography.fernet import Fernet;print(Fernet.generate_key().decode())')"

# ── 5. push ───────────────────────────────────────────────────────────────────
echo "Pushing ..."
heroku git:remote -a "$APP" >/dev/null
git push heroku HEAD:main

# ── 6. schema + key ───────────────────────────────────────────────────────────
echo "Loading schema and minting an API key ..."
heroku run python dbsetup.py -a "$APP"

cat <<NOTE

Deployed. Connector URL:

  https://$APP.herokuapp.com/mcp/

Add it in claude.ai and in Cowork under Settings -> Connectors -> Add custom
connector, with Bearer auth and the API key printed above.

Verify first:

  deploy/openosint-cloud/verify.sh https://$APP.herokuapp.com <api-key>

search_dns and search_domain work immediately. For search_ip, search_abuseipdb,
search_virustotal, and search_censys, store your own upstream keys — see
"Store BYOK keys" in deploy/openosint-cloud/README.md.
NOTE
