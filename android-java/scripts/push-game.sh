#!/usr/bin/env bash
# push-game.sh [GAME]
#
# Deploys a game into the demo app's private storage, under a game id equal
# to its directory's name. The private directory is not writable by adb push
# on a non-rooted device, so the content goes through /data/local/tmp and is
# copied in with run-as.
#
# GAME may be:
#   - a bare name (no "/"), resolved to <repo-root>/games/<name>; the game id
#     is the name. This is how you reach the games shipped in this repo
#     (currently just "demo", a self-check probe) -- real games normally
#     live outside it.
#   - a path to a game directory anywhere on disk (contains a "/", or names
#     an existing directory); the game id is that directory's basename.
#
# Either way the resulting game id must be a safe identifier: ASCII letters,
# digits, underscore and hyphen, 1-64 characters (the rule documented in
# android-java/README.md), since it is interpolated into device-side shell
# commands and a filesystem path below.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAMES_DIR="$HERE/../../games"
ARG="${1:-demo}"
PKG="com.minigame.androiddemo"
STAGE="/data/local/tmp/migo-demo-game"

if [[ "$ARG" == */* || -d "$ARG" ]]; then
  GAME_DIR="$ARG"
  TRIMMED="${GAME_DIR%/}"
  GAME_ID="${TRIMMED##*/}"
else
  GAME_ID="$ARG"
  GAME_DIR="$GAMES_DIR/$GAME_ID"
fi

# Validate before anything else touches the device (or even looks at the
# filesystem beyond the -d test above): a bad id must never reach an adb
# shell command or a run-as path.
if ! [[ "$GAME_ID" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
  echo "ERROR: invalid game id '$GAME_ID' -- must match ^[A-Za-z0-9_-]{1,64}\$" >&2
  echo "       (ASCII letters, digits, underscore, hyphen; 1-64 characters)" >&2
  exit 2
fi

ADB=(adb)
[ -n "${SERIAL:-}" ] && ADB=(adb -s "$SERIAL")

if [ ! -f "$GAME_DIR/game.js" ]; then
  echo "ERROR: no game.js found at $GAME_DIR/game.js" >&2
  if [ "$GAME_DIR" = "$GAMES_DIR/$GAME_ID" ]; then
    echo "       available: $(ls "$GAMES_DIR" 2>/dev/null | tr '\n' ' ')" >&2
  fi
  exit 2
fi

# Clean up the device-side staging directory on every exit path, not just the
# success one -- otherwise a failure between creating it and the final rm
# leaves it behind on the device.
cleanup() {
  "${ADB[@]}" shell "rm -rf $STAGE" > /dev/null 2>&1 || true
}
trap cleanup EXIT

"${ADB[@]}" shell "rm -rf $STAGE && mkdir -p $STAGE"
"${ADB[@]}" push "$GAME_DIR/." "$STAGE/" > /dev/null
"${ADB[@]}" shell "run-as $PKG sh -c 'rm -rf files/migo/games/$GAME_ID/code && mkdir -p files/migo/games/$GAME_ID/code'"
"${ADB[@]}" shell "run-as $PKG sh -c 'cp -r $STAGE/. files/migo/games/$GAME_ID/code/'"

# Verify rather than assume: a silent run-as failure would otherwise look like
# success. The sentinel is matched whole-line because `ls`-style errors quote the
# path back at you -- a substring match on the filename would be satisfied by the
# very error that means the file is missing. `test` is invoked through `sh -c`,
# not directly: on some devices (confirmed on an API29 x86_64 emulator) run-as
# can exec real binaries like `ls` but not `test`, which is only a shell
# builtin there -- a bare `run-as $PKG test ...` fails with "exec failed for
# test: Permission denied" even though the deploy succeeded.
if ! "${ADB[@]}" shell "run-as $PKG sh -c 'test -f files/migo/games/$GAME_ID/code/game.js && echo MIGO_PUSH_OK'" \
     | tr -d '\r' | grep -qx MIGO_PUSH_OK; then
  echo "ERROR: game.js is not present in the app's private storage after deploy" >&2
  exit 3
fi

echo "OK: deployed $GAME_DIR to $PKG as gameId '$GAME_ID'"
