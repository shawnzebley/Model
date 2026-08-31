---
name: osint-recon
description: Run OSINT reconnaissance against a domain, IP, email, username, phone number, or GitHub account using the openosint MCP tools, and write up the findings. Use when the user asks to investigate, recon, profile, enumerate, or look up a target — subdomains, DNS and WHOIS records, breach exposure, IP reputation, exposed services, social accounts — or names a target and asks what is publicly known about it. For authorized security research only.
---

# OSINT recon with OpenOSINT

The `openosint` MCP server exposes 23 tools that shell out to real binaries and
APIs. The AI issues the tool call; the tool executes and returns what it found.
Never write a finding the tools did not return.

## Authorization comes first

These tools touch third-party infrastructure and surface data about real people.
Before the first call, confirm the target is one the user is authorized to
investigate — their own asset, an engagement in scope, a bug-bounty target, or a
CTF. If that is unclear from the request, ask in one sentence and wait.

Decline targets that are plainly a private individual the user has no stated
relationship to, and say why in a sentence without lecturing.

## Pick tools by target type

| Target | Start with | Then pivot to |
|---|---|---|
| Domain | `search_dns`, `search_whois` | `search_domain` (subdomains), `search_footprint`, `search_github` |
| IP | `search_ip`, `search_abuseipdb` | `search_shodan`, `search_censys`, `search_virustotal`, `search_ip2location` |
| Email | `search_email`, `search_breach` | `search_username` on the local part, `search_paste`, `generate_dorks` |
| Username | `search_username` | `search_github`, `search_paste`, `generate_dorks` |
| Phone | `search_phone` | `generate_dorks` |
| GitHub user/org | `search_github` | `search_email` on any address it exposes |
| Anything, no leads yet | `generate_dorks` | `search_dorks_live`, `scrape_url` |

`investigate_multi` runs several targets in one pass. `graph_export`,
`graph_neighbors`, and `graph_review_candidates` read the entity graph that
earlier runs populated — they do not fetch anything new.

## What works without setup

Keyless and ready: `search_dns`, `search_whois`, `search_ip` (richer with
`IPINFO_TOKEN`), `search_paste`, `generate_dorks`, and the `graph_*` tools.

Needs a key in `.env` (see `.env.example`): `search_breach` (HIBP),
`search_shodan`, `search_virustotal`, `search_censys`, `search_abuseipdb`,
`search_ip2location`, `search_github`, `search_dorks_live` and `scrape_url`
(Bright Data).

Needs an external binary, installed by `scripts/openosint-setup.sh --binaries`:
`search_email` (holehe), `search_username` (sherlock). `search_domain`
(sublist3r) and `search_phone` (phoneinfoga) need those binaries on `PATH`.

When a tool reports a missing key or binary, say which one and what it would
add — then keep going with the tools that do work. A blocked tool is not a
blocked investigation.

## How to run an investigation

1. Start broad and cheap: DNS and WHOIS for a domain, `search_ip` for an
   address. These are fast and cost nothing.
2. Pivot on what comes back, not on guesses. An MX record pointing at a
   provider, an email in a WHOIS record, a username in a GitHub profile — each
   is a lead for the next tool. Say which finding drove each pivot.
3. Stop when the leads stop. Running every tool on every target is noise.

## Reporting

Write findings as prose with the evidence attached, not a dump of raw tool
output. For each finding give the value, the tool that produced it, and what it
implies. Keep the raw output available for anything a reader would want to
verify.

Separate what the tools confirmed from what you infer. "Two subdomains resolve
to the same Cloudflare IP" is a finding; "they are probably the same
application" is an inference, and it needs to be labeled as one.

Say what you did not check. An investigation that skipped breach data because
no HIBP key is set is a different investigation from one that checked and found
nothing — the reader cannot tell the difference unless you say so.
