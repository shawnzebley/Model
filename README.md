# Model

Team Work

## OpenOSINT

The OpenOSINT toolkit is wired into this repo so Claude can run reconnaissance
tools directly. Ask in plain language — "run DNS and WHOIS on example.com" — and
the `osint-recon` skill picks the tools.

### Use it in Claude Code — nothing to host

Open a **Claude Code** session on this repo from any device (terminal, desktop
app, or [claude.ai/code](https://claude.ai/code) in a browser) and all 23 tools
are there. Setup runs automatically on session start. No server, no hosting, no
monthly cost.

This is the recommended way to use it.

### Why chat and Cowork are different

claude.ai chat and Cowork connect to MCP servers from Anthropic's
infrastructure, not from your machine, so they can only reach tools that are
already running on the public internet. Nothing in this repo — not `.mcp.json`,
not a skill, not a plugin — can give them a local tool. There is also no OSINT
connector in Claude's connector directory to switch on.

The only way to get these tools into chat or Cowork is to run a small HTTPS
service yourself. Two optional kits are here, both giving 7 infrastructure tools
rather than 23:

- **[deploy/openosint-worker/](deploy/openosint-worker/README.md)** — Cloudflare
  Worker. Free, no database, one `wrangler deploy`. Recommended.
- **[deploy/openosint-cloud/](deploy/openosint-cloud/README.md)** — upstream's
  own gateway on Heroku, ~$5/mo, adds credit metering and multi-user key storage.

Both are **optional** — skip them unless you specifically need chat or Cowork,
rather than Claude Code, to do this work.

Setup, API keys, and the full tool list: [docs/openosint.md](docs/openosint.md).

For authorized security research only.
