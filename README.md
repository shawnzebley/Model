# Model

Team Work

## OpenOSINT

The OpenOSINT toolkit is wired into this repo so its reconnaissance tools are
available to Claude. Ask in plain language — "run DNS and WHOIS on
example.com" — and the `osint-recon` skill picks the tools.

- **Claude Code**: works out of the box in any session opened here. All 23
  tools, set up automatically on session start.
- **claude.ai chat and Cowork**: need a deployed HTTPS connector, because those
  surfaces cannot reach a local server. See
  [deploy/openosint-cloud/README.md](deploy/openosint-cloud/README.md) — 7
  infrastructure tools.

Setup, API keys, and the full tool list: [docs/openosint.md](docs/openosint.md).

For authorized security research only.
