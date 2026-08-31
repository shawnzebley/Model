#!/usr/bin/env bash
# Package the osint-recon skill as a zip for upload to claude.ai chat or Cowork
# (Customize -> Skills -> upload). Claude Code reads the skill from
# .claude/skills/ directly and needs no zip.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/.claude/skills/osint-recon"
OUT="${1:-$REPO_ROOT/.build/osint-recon-skill.zip}"

[[ -d "$SKILL_DIR" ]] || { echo "Skill not found: $SKILL_DIR" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# Zip the folder itself, not its contents — the upload expects a single
# top-level directory containing SKILL.md.
(cd "$(dirname "$SKILL_DIR")" && zip -q -r "$OUT" "$(basename "$SKILL_DIR")")

echo "Wrote $OUT"
