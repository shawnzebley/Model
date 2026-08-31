#!/usr/bin/env bash
# Assemble a deployable OpenOSINT Cloud gateway in a build directory.
#
# Clones OpenOSINT at a pinned tag, applies the /mcp lifespan fix, and drops in
# the Heroku overlay (Procfile, requirements.txt, .python-version). The result
# is a git repo ready for `git push heroku HEAD:main`.
#
# Upstream source is not vendored here — this script fetches it, so the pin
# below is the only thing to bump when a new release lands.
#
#   deploy/openosint-cloud/build.sh [build-dir]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$REPO_ROOT/deploy/openosint-cloud"
BUILD_DIR="${1:-$REPO_ROOT/.build/openosint-cloud}"

UPSTREAM="https://github.com/OpenOSINT/OpenOSINT"
# Pinned to the release this was tested against. Tag v2.27.0 = 42e770d.
PIN_TAG="v2.27.0"
PIN_SHA="42e770d9a8ad46991749e155d2cae7d3db83d7b1"

if [[ -e "$BUILD_DIR" ]]; then
  echo "Build dir $BUILD_DIR already exists. Remove it first:" >&2
  echo "  rm -rf $BUILD_DIR" >&2
  exit 1
fi

echo "Cloning $UPSTREAM at $PIN_TAG ..."
mkdir -p "$(dirname "$BUILD_DIR")"
git clone --quiet --depth 1 --branch "$PIN_TAG" "$UPSTREAM" "$BUILD_DIR"

cd "$BUILD_DIR"
actual="$(git rev-parse HEAD)"
if [[ "$actual" != "$PIN_SHA" ]]; then
  echo "Pin mismatch: expected $PIN_SHA, got $actual." >&2
  echo "The tag moved. Re-verify the source before deploying." >&2
  exit 1
fi

echo "Applying patches ..."
for p in "$HERE"/patches/*.patch; do
  git apply "$p"
  echo "  applied $(basename "$p")"
done

echo "Installing Heroku overlay ..."
# Upstream's Procfile runs the web UI (`openosint web`), not the cloud gateway.
# Ours replaces it with the ASGI entry point cloud/main.py documents.
cp "$HERE/Procfile" "$HERE/requirements.txt" "$HERE/.python-version" "$BUILD_DIR/"

git add -A
git -c user.email=deploy@localhost -c user.name=deploy commit --quiet \
  -m "Heroku overlay + /mcp session lifespan fix (built from $PIN_TAG)"

echo ""
echo "Build ready: $BUILD_DIR"
echo "Next: see deploy/openosint-cloud/README.md for the Heroku runbook."
