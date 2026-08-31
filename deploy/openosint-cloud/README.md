# OpenOSINT Cloud gateway — deploy runbook

Stands up OpenOSINT's hosted MCP gateway on Heroku so the tools work in
**claude.ai chat** and **Cowork**, not just Claude Code.

## Why this is needed

Chat and Cowork connect to MCP servers from Anthropic's infrastructure, not from
your machine. They require a publicly reachable HTTPS endpoint speaking
Streamable HTTP or SSE — a local stdio server cannot be connected. The
`.mcp.json` at the repo root is Claude Code only; neither chat nor Cowork reads
it.

OpenOSINT ships the right thing for this: `cloud/` is a FastAPI app whose `/mcp`
mount is a FastMCP Streamable HTTP server with Bearer auth.

## What you get — and what you don't

The gateway exposes **7 tools**, not the 23 available locally:

`search_ip` · `search_ip2location` · `search_abuseipdb` · `search_dns` ·
`search_domain` · `search_virustotal` · `search_censys`

Infrastructure and host intelligence only. Upstream deliberately excludes
breach, email, username, phone, and paste lookups from the cloud allow-list —
`cloud/tools.py` says so, and there is a test guarding it. If you need those,
use the local Claude Code setup, which has all 23.

Credential model, from `cloud/key_sources.py`:

| Tool | Credential |
|---|---|
| `search_dns`, `search_domain` | none — work immediately |
| `search_ip2location` | platform: `IP2LOCATION_API_KEY` config var |
| `search_ip`, `search_abuseipdb`, `search_virustotal`, `search_censys` | BYOK: you store them via `POST /v1/keys` |

Every call decrements credits on your customer row.

## An upstream fix is applied

`cloud/main.py` mounts the MCP app as a sub-app, but mounting a Starlette
sub-app does not run its lifespan — so FastMCP's session manager task group is
never started and **every `/mcp` request returns 500**:

```
RuntimeError: Task group is not initialized. Make sure to use run().
```

Reproduced against `mcp` 1.29.1 with OpenOSINT v2.27.0. `patches/0001-*.patch`
makes the parent lifespan enter `session_manager.run()`. `build.sh` applies it.
Worth sending upstream — if a later release fixes it, drop the patch and bump
the pin in `build.sh`.

## Deploy

Prerequisites: Heroku CLI logged in (`heroku login`), Python 3, git. Run this
from your own machine — it needs network access to heroku.com.

### The short version

```bash
deploy/openosint-cloud/deploy-heroku.sh your-app-name
```

That builds, creates the app, provisions Postgres, generates and sets both
secrets, pushes, loads the schema, and mints an API key — printing the key at
the end. It prompts before creating anything and is safe to re-run: an existing
app, addon, and config vars are reused rather than replaced.

Then check it before wiring it up:

```bash
deploy/openosint-cloud/verify.sh https://your-app-name.herokuapp.com <api-key>
```

A clean run reports an MCP initialize handshake. A 500 almost always means the
lifespan patch did not make it into the deploy, and the script says so.

### Step by step

If you would rather run it yourself, or something above failed partway:

**1. Build.**

```bash
deploy/openosint-cloud/build.sh
```

Clones OpenOSINT at `v2.27.0` (SHA-pinned, aborting if the tag has moved),
applies the patch, and adds the Heroku overlay. Output: `.build/openosint-cloud`,
a git repo ready to push. The overlay replaces upstream's `Procfile` — theirs
runs the web UI (`openosint web`), not the gateway.

**2. Create the app.**

```bash
cd .build/openosint-cloud
APP=your-app-name

heroku create $APP
heroku addons:create heroku-postgresql:essential-0 -a $APP --wait

heroku config:set -a $APP \
  SESSION_SECRET_KEY="$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')" \
  CONFIG_ENCRYPTION_KEY="$(python3 -c 'from cryptography.fernet import Fernet;print(Fernet.generate_key().decode())')"

# Optional — enables search_ip2location for every key on this deploy
heroku config:set -a $APP IP2LOCATION_API_KEY=...
```

Both secrets are required once `DATABASE_URL` is set: the app refuses to boot
without `SESSION_SECRET_KEY`, and `CONFIG_ENCRYPTION_KEY` is the Fernet key
encrypting stored BYOK secrets. **Losing `CONFIG_ENCRYPTION_KEY`, or
regenerating it on an existing deploy, makes every stored BYOK key
unreadable** — keep a copy.

**3. Push, then load the schema and mint a key.**

```bash
cp ../../deploy/openosint-cloud/dbsetup.py .
git add -A && git commit -m "Add dbsetup.py"
git push heroku HEAD:main

heroku run python dbsetup.py -a $APP
```

`dbsetup.py` runs on the dyno, so no local `psql` is needed. It loads
`db/init.sql` and prints a freshly generated API key once — save it. Re-running
is safe; `--mint` alone adds another key without touching the schema.

`mint-key.sql` is there if you would rather do it in SQL with your own key.

### Store BYOK keys (optional)

For `search_ip`, `search_abuseipdb`, `search_virustotal`, `search_censys`:

```bash
curl -X POST https://$APP.herokuapp.com/v1/keys \
  -H "X-API-Key: <your-minted-key>" \
  -H 'Content-Type: application/json' \
  -d '{"provider":"ipinfo","secret":"<your-ipinfo-token>"}'
```

Providers: `ipinfo`, `abuseipdb`, `virustotal`, `censys`. Censys takes both
credentials as `<api_id>:<api_secret>`.

## Add it to chat and Cowork

Same connector, added once per surface:

1. Settings → Connectors → **Add custom connector**
2. URL: `https://your-app-name.herokuapp.com/mcp/`
3. Authentication: Bearer token → your minted key
4. In **Cowork**, enable the connector for the session under Customize

The `osint-recon` skill can go with it: zip
`.claude/skills/osint-recon/` and upload it under Customize → Skills. Its tool
table covers the full 23; only the 7 above exist on this connector.

## Operating notes

- **`tools/list` is not authenticated.** Auth is enforced per tool call, so an
  unauthenticated caller can enumerate tool *names* but cannot execute
  anything. Don't treat the URL as secret-bearing; the Bearer key is the
  control.
- **Credits are the spend cap.** Top up with
  `UPDATE customers SET credits = ... WHERE api_key = '...';`
- **Rotate a key** by inserting a new row and deleting the old one; BYOK secrets
  cascade-delete with the customer row.
- **25s tool timeout**, set below Heroku's 30s router limit. Subdomain
  enumeration on a large domain can hit it.
- Upstream's hosted service is invite-only and commercial. This is your own
  deploy of the MIT-licensed code — no relationship to their offering, and no
  support from them.
