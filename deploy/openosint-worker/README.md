# OSINT MCP server on Cloudflare Workers

A small MCP server that gives **claude.ai chat** and **Cowork** a working set of
OSINT lookups. Runs on Cloudflare's free tier, needs no database, and deploys
with one command.

## Why this exists rather than hosting OpenOSINT itself

Chat and Cowork connect to MCP servers from Anthropic's infrastructure, so they
can only reach a public HTTPS endpoint — a local stdio server is not an option,
and neither surface reads this repo's `.mcp.json`.

OpenOSINT itself cannot run on Workers. It is Python that shells out to
`sherlock`, `sublist3r`, and `holehe`, and does raw UDP DNS; Workers have no
subprocesses and no UDP. So this is a **reimplementation over HTTP equivalents**,
not a port:

| OpenOSINT does | This does |
|---|---|
| UDP DNS via dnspython | DNS-over-HTTPS (`cloudflare-dns.com`) |
| WHOIS on TCP port 43 | RDAP, the JSON protocol that replaced it |
| `sublist3r` subprocess | certificate transparency logs (`crt.sh`) |
| HTTP API calls | the same HTTP API calls |

Consequence: this is **my code, not upstream's tested code**. The tradeoff
against `../openosint-cloud/` (Heroku) is spelled out at the bottom.

## Tools

| Tool | Credential | Notes |
|---|---|---|
| `search_dns` | none | records + SPF/DMARC findings |
| `search_whois` | none | registrar, dates, nameservers, status |
| `search_subdomains` | none | from certificates issued, not live hosts |
| `search_ip` | optional `IPINFO_TOKEN` | works anonymously, rate limited |
| `search_abuseipdb` | `ABUSEIPDB_API_KEY` | |
| `search_virustotal` | `VIRUSTOTAL_API_KEY` | domain or IP |
| `search_shodan` | `SHODAN_API_KEY` | |

Three work with no credentials at all. A tool whose key is missing says which
key it needs; the others are unaffected.

No breach, email, username, phone, or paste lookups — those need the local
Claude Code setup, which has all 23.

## Deploy

Needs Node and a Cloudflare account. From `deploy/openosint-worker/`:

```bash
npm install

# Generate a bearer token and store it as a secret. Save the value — you will
# paste it into the connector, and it is not recoverable afterwards.
node -e "console.log(crypto.randomUUID().replace(/-/g,'')+crypto.randomUUID().replace(/-/g,''))"
npx wrangler secret put MCP_TOKEN     # paste it at the prompt

npx wrangler deploy
```

`wrangler` opens a browser to authorize on first use. Deploy prints the URL,
something like `https://openosint-mcp.<your-subdomain>.workers.dev`.

Optional keys, each the same way:

```bash
npx wrangler secret put IPINFO_TOKEN
npx wrangler secret put ABUSEIPDB_API_KEY
npx wrangler secret put VIRUSTOTAL_API_KEY
npx wrangler secret put SHODAN_API_KEY
```

### Check it before wiring it up

```bash
curl https://openosint-mcp.<subdomain>.workers.dev/health

../openosint-cloud/verify.sh https://openosint-mcp.<subdomain>.workers.dev <MCP_TOKEN>
```

`verify.sh` confirms a real MCP initialize handshake. It is written against any
MCP endpoint, so it serves both deployments.

## Add it to chat and Cowork

Once per surface:

1. Settings → Connectors → **Add custom connector**
2. URL: `https://openosint-mcp.<subdomain>.workers.dev/mcp`
3. Authentication: Bearer token → your `MCP_TOKEN`
4. In **Cowork**, enable the connector for the session under Customize

Pair it with the skill: `scripts/package-skill.sh` produces a zip to upload
under Customize → Skills.

## Cost

Cloudflare's free tier covers 100,000 requests/day, which is far beyond
interactive use. No database, so nothing else accrues. Upstream APIs bill you
directly under your own keys.

## Design notes

- **Stateless.** MCP session ids are optional, so skipping them means no Durable
  Object and no storage. Responses are `application/json` rather than SSE, which
  Streamable HTTP permits, keeping this one fetch handler.
- **Auth precedes parsing**, so an unauthenticated caller cannot enumerate tool
  names. Compare is constant-time. (The Heroku gateway leaves `tools/list`
  open; this does not.)
- **A failed lookup is a reported result, not an exception** — the model sees
  what went wrong and can carry on.
- **Failure is never reported as absence.** DNS queries distinguish "the query
  failed" from "no such record", because collapsing them let a network error
  print `No SPF record — anyone can spoof email from this domain`: confident,
  alarming, and false. Partial failures are labelled as incomplete. This bug was
  real and caught in testing; keep the distinction if you extend the code.
- Inputs are validated against domain and IP shapes before being interpolated
  into any upstream URL.

## Which deployment to use

| | This Worker | `../openosint-cloud/` (Heroku) |
|---|---|---|
| Cost | free | ~$5/mo (Postgres) |
| Deploy | `wrangler deploy` | build, app, addon, secrets, schema |
| Code | reimplementation, mine | upstream's, patched |
| Tools | 7 (3 keyless) | 7 (2 keyless) |
| Extras | — | credit metering, BYOK key store, multi-user |

Prefer this one unless you need the metering and multi-tenant key storage the
Heroku gateway brings. Both are optional: Claude Code needs neither.
