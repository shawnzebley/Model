# Skills

Custom Claude skills for Sobieski fire life safety work. This directory is the
source of truth. Edit here, then re-upload to claude.ai so the skill syncs into
every session.

| Skill | Use it for |
|---|---|
| `content-engine` | Turning real jobs into LinkedIn posts and marketing copy |
| `account-review` | Finding expansion revenue and retention risk in existing accounts |

## Installing these on your account

Skills only load automatically once they are uploaded to your Claude account.
A copy sitting in this repo does not load on its own.

1. Download the `.zip` for the skill (see `dist/`, or zip the folder yourself)
2. claude.ai, Settings, Capabilities, Skills
3. Upload the zip
4. It syncs to every session, Claude Code included

To update a skill: edit here, commit, re-zip, re-upload. The upload replaces the
previous version.

## How these relate to the existing skills

- **Voice** lives in `shawn-voice`. Neither skill here restates it, both defer to
  it for anything customer-facing. If they ever conflict, `shawn-voice` wins.
- **Pricing** lives in `fire-inspection-quote` and its engine. `account-review`
  sizes opportunities in bands and hands off to the engine for real numbers. It
  never computes a price itself.
- **Output formats** use `docx`, `pdf`, `xlsx`, and `pptx` rather than
  reimplementing document generation.

## Source material

Both were adapted from open-source skills, not copied. The upstream versions are
written for SaaS and product marketing and are wrong for this business out of the
box, mainly on cadence, channel mix, and the assumption that expansion means
upselling features rather than performing work the code already requires.

- `content-engine` structure from [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) `social` and [thatrebeccarae/claude-marketing](https://github.com/thatrebeccarae/claude-marketing) `content-creator`, `social-media-strategy`
- `account-review` structure from [onewave-ai/claude-skills](https://github.com/onewave-ai/claude-skills) `expansion-revenue-finder`, `pipeline-health-analyzer`

## A caution on the code frequencies

`account-review/references/cycles.md` lists common NFPA 10, 25, and 72 baseline
frequencies as a checklist so nothing gets overlooked. Adopted editions and local
amendments vary. Verify against the edition adopted in the jurisdiction before any
frequency goes in front of a customer. The skill is written to say so when it is
working from the checklist rather than a verified adopted edition.
