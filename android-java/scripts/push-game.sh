#!/usr/bin/env bash
# push-game.sh [GAME_NAME]
#
# Deploys one of the games in ../../games into the demo app's private storage,
# under a game id equal to the directory name. The private directory is not
# writable by adb push on a non-rooted device, so the content goes through
# /data/local/tmp and is copied in with run-as.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAMES_DIR="$HERE/../../games"
GAME_ID="${1:-demo}"
GAME_DIR="$GAMES_DIR/$GAME_ID"
PKG="com.minigame.androiddemo"
STAGE="/data/local/tmp/migo-demo-game"

ADB=(adb)
[ -n "${SERIAL:-}" ] && ADB=(adb -s "$SERIAL")

if [ ! -f "$GAME_DIR/game.js" ]; then
  echo "ERROR: no game named '$GAME_ID' in $GAMES_DIR (expected $GAME_DIR/game.js)" >&2
  echo "       available: $(ls "$GAMES_DIR" 2>/dev/null | tr '\n' ' ')" >&2
  exit 2
fi

"${ADB[@]}" shell "rm -rf $STAGE && mkdir -p $STAGE"
"${ADB[@]}" push "$GAME_DIR/." "$STAGE/" > /dev/null
"${ADB[@]}" shell "run-as $PKG sh -c 'rm -rf files/migo/games/$GAME_ID/code && mkdir -p files/migo/games/$GAME_ID/code'"
"${ADB[@]}" shell "run-as $PKG sh -c 'cp -r $STAGE/. files/migo/games/$GAME_ID/code/'"
"${ADB[@]}" shell "rm -rf $STAGE"

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
