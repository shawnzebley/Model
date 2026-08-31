# OpenOSINT setup

[OpenOSINT](https://github.com/OpenOSINT/OpenOSINT) is an OSINT toolkit that
ships an MCP server. This repo wires it in as a project-scoped MCP server plus
an `osint-recon` skill, so the tools are available in any Claude Code session
opened here.

## Which surface you are on

Claude Code and the Claude apps reach MCP servers differently, and that decides
what you can run where.

| Surface | Transport | Tools | Setup |
|---|---|---|---|
| **Claude Code** (this repo) | local stdio via `.mcp.json` | all 23 | automatic — read on |
| **claude.ai chat** | remote HTTPS connector | 7 | [deploy the gateway](../deploy/openosint-cloud/README.md) |
| **Cowork** | remote HTTPS connector | 7 | [deploy the gateway](../deploy/openosint-cloud/README.md) |

Chat and Cowork connect from Anthropic's infrastructure, not your machine, so
they need a publicly reachable HTTPS MCP endpoint — a local stdio server cannot
be connected, and neither surface reads this repo's `.mcp.json`. The gateway
deploy covers those two; the rest of this page is the Claude Code setup.

The skill works on all three. Claude Code reads it from `.claude/skills/`;
for chat and Cowork run `scripts/package-skill.sh` and upload the zip under
Customize → Skills.

## What got added

| File | Purpose |
|---|---|
| `.mcp.json` | Registers the `openosint` MCP server for this project |
| `scripts/openosint-mcp` | Launcher — resolves the binary, sources `.env` |
| `scripts/openosint-setup.sh` | Creates `.venv-openosint`, installs the pinned version |
| `.claude/settings.json` | SessionStart hook that runs the setup script |
| `.claude/skills/osint-recon/SKILL.md` | Tells Claude which tool fits which target |
| `.env.example` | Every API key the tools can use, all optional |
| `deploy/openosint-cloud/` | Heroku deploy for the chat/Cowork connector |
| `scripts/package-skill.sh` | Zips the skill for chat/Cowork upload |

## First run

The SessionStart hook installs OpenOSINT automatically, so a fresh session —
including a fresh cloud container — comes up ready. To do it by hand:

```bash
scripts/openosint-setup.sh              # core install
scripts/openosint-setup.sh --binaries   # also holehe + sherlock
```

Then restart Claude Code so it picks up `.mcp.json`, and approve the server when
prompted. `/mcp` shows it connected; the 23 tools appear as `openosint:*`.

## API keys

```bash
cp .env.example .env
```

Fill in what you have. The launcher sources `.env` before starting the server —
MCP servers get a bare environment, so this is what makes key-gated tools work.
`.env` is gitignored.

Nothing here is required. `search_dns`, `search_whois`, `search_ip`,
`search_paste`, `generate_dorks`, and the graph tools run with no key at all.

## The 23 tools

**Keyless:** `search_dns`, `search_whois`, `search_ip`, `search_paste`,
`generate_dorks`, `graph_export`, `graph_neighbors`, `graph_review_candidates`

**Key-gated:** `search_breach` (HIBP), `search_shodan`, `search_virustotal`,
`search_censys`, `search_abuseipdb`, `search_ip2location`, `search_github`,
`search_dorks_live` and `scrape_url` (Bright Data)

**Binary-gated:** `search_email` (holehe), `search_username` (sherlock),
`search_domain` (sublist3r), `search_phone` (phoneinfoga)

**Multi-target:** `investigate_multi`

A tool whose key or binary is missing returns an error naming what it needs; the
others are unaffected.

## Using it outside Claude Code

The venv carries the full CLI and web UI too:

```bash
.venv-openosint/bin/openosint dns example.com   # one-shot lookup
.venv-openosint/bin/openosint shell             # interactive REPL
.venv-openosint/bin/openosint web               # browser UI
```

The REPL and web UI drive the tools with their own LLM and need
`ANTHROPIC_API_KEY` (or an Ollama / OpenAI-compatible endpoint) in `.env`. The
MCP path does not — Claude Code is the model there.

## Scope

OpenOSINT is MIT-licensed and, per its own README, for authorized security
research. The `osint-recon` skill asks Claude to confirm authorization before
the first call against a target.
