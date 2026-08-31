#!/usr/bin/env bash
# Install OpenOSINT into a repo-local venv so the MCP server can start.
#
# Safe to re-run: it skips the install when the pinned version is already
# present, which keeps it cheap as a SessionStart hook.
#
#   scripts/openosint-setup.sh            # core install (Python tools only)
#   scripts/openosint-setup.sh --binaries # also install holehe / sherlock
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$REPO_ROOT/.venv-openosint"
OPENOSINT_VERSION="${OPENOSINT_VERSION:-2.27.0}"
WANT_BINARIES=0
[[ "${1:-}" == "--binaries" ]] && WANT_BINARIES=1

if [[ -x "$VENV/bin/openosint-mcp" ]]; then
  installed="$("$VENV/bin/python" -c \
    'import importlib.metadata as m; print(m.version("openosint"))' 2>/dev/null || echo none)"
  if [[ "$installed" == "$OPENOSINT_VERSION" && $WANT_BINARIES -eq 0 ]]; then
    echo "OpenOSINT $installed already installed."
    exit 0
  fi
fi

echo "Installing OpenOSINT $OPENOSINT_VERSION into $VENV ..."
python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet "openosint==${OPENOSINT_VERSION}"

if [[ $WANT_BINARIES -eq 1 ]]; then
  # search_email and search_username shell out to these; without them those two
  # tools report a missing binary and every other tool still works.
  echo "Installing holehe and sherlock ..."
  "$VENV/bin/pip" install --quiet holehe sherlock-project || {
    echo "Optional binaries failed to install; core tools are unaffected." >&2
  }
fi

"$VENV/bin/python" -c 'import importlib.metadata as m; \
print("OpenOSINT", m.version("openosint"), "ready")'
