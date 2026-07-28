#!/usr/bin/env bash
# Build and run the Linux example against a resolved Migo SDK.
#
# Usage: bash linux-cmake/run.sh [GAME] [SECONDS]
#   GAME      a directory name under games/, or a path to a game directory
#   SECONDS   how long to run (default 15)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
GAME="${1:-demo}"
SECONDS_TO_RUN="${2:-15}"
PREFIX="$HERE/sdk"
RUN_ROOT="${MIGO_RUN_ROOT:-/tmp/migo-linux-example}"

case "$GAME" in
  */*) GAME_DIR="$GAME" ;;
  *)   GAME_DIR="$ROOT/games/$GAME" ;;
esac
GAME_ID="$(basename "$GAME_DIR")"
if [ ! -f "$GAME_DIR/game.js" ]; then
  echo "ERROR: no game at $GAME_DIR (expected game.js)" >&2
  exit 2
fi

# Resolve the SDK unless a prefix is already staged. The resolver verifies the
# download against the release attestation; it is not a plain fetch.
if [ ! -f "$PREFIX/lib/cmake/migo/migo-config.cmake" ]; then
  echo "==> resolving the Migo Linux SDK"
  bash "$ROOT/scripts/resolve-migo-artifact.sh" linux-sdk "$PREFIX"
fi

echo "==> building"
cmake -S "$HERE" -B "$HERE/build" -DCMAKE_PREFIX_PATH="$PREFIX" >/dev/null
cmake --build "$HERE/build" --parallel >/dev/null

# Content lives under <files>/migo/games/<id>/code/, which is where the engine
# looks it up by the content id passed to migo_session_load_content.
CODE_DIR="$RUN_ROOT/files/migo/games/$GAME_ID/code"
rm -rf "$RUN_ROOT"
mkdir -p "$CODE_DIR"
cp "$GAME_DIR"/* "$CODE_DIR/"

echo "==> running '$GAME_ID' for ${SECONDS_TO_RUN}s"
exec "$HERE/build/migo-linux-example" "$RUN_ROOT/files" "$GAME_ID" "$SECONDS_TO_RUN"
