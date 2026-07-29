#!/usr/bin/env bash
# Build and run the Windows example against a resolved Migo SDK.
#
# Runs from WSL but builds and executes on Windows: the compile needs MSVC and
# the program needs a real HWND.
#
# Usage: bash windows-cmake/run.sh [GAME] [SECONDS]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
GAME="${1:-demo}"
SECONDS_TO_RUN="${2:-15}"
PREFIX="$HERE/sdk"

case "$GAME" in
  */*) GAME_DIR="$GAME" ;;
  *)   GAME_DIR="$ROOT/games/$GAME" ;;
esac
GAME_ID="$(basename "$GAME_DIR")"
[[ -f "$GAME_DIR/game.js" ]] || { echo "ERROR: no game at $GAME_DIR (expected game.js)" >&2; exit 2; }

if [[ ! -f "$PREFIX/lib/cmake/migo/migo-config.cmake" ]]; then
  echo "==> resolving the Migo Windows SDK"
  bash "$ROOT/scripts/resolve-migo-artifact.sh" windows-sdk "$PREFIX"
fi

# Build and run on a Windows local disk. cargo and cl are both unusable with a
# UNC working directory, and the executable needs its DLLs on a real path.
WIN_ROOT="/mnt/c/Windows/Temp/migo-windows-example"
rm -rf "$WIN_ROOT"
mkdir -p "$WIN_ROOT/src" "$WIN_ROOT/files/migo/games/$GAME_ID/code"
cp "$HERE/main.c" "$HERE/CMakeLists.txt" "$WIN_ROOT/src/"
cp -a "$PREFIX/." "$WIN_ROOT/sdk/"
cp "$GAME_DIR"/* "$WIN_ROOT/files/migo/games/$GAME_ID/code/"

VSWHERE="/mnt/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
[[ -f "$VSWHERE" ]] || { echo "ERROR: Visual Studio Build Tools not found" >&2; exit 3; }
VS_ROOT="$("$VSWHERE" -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
    -latest -format value -property installationPath | tr -d '\r')"

BAT=/mnt/c/Windows/Temp/migo-win-example.bat
cat > "$BAT" <<BATCH
@echo off
call "$VS_ROOT\\VC\\Auxiliary\\Build\\vcvars64.bat" >nul
cd /d C:\\Windows\\Temp\\migo-windows-example
cmake -S src -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=C:\\Windows\\Temp\\migo-windows-example\\sdk || exit /b 90
cmake --build build || exit /b 91
build\\migo-windows-example.exe C:\\Windows\\Temp\\migo-windows-example\\files $GAME_ID $SECONDS_TO_RUN
exit /b %errorlevel%
BATCH

echo "==> building and running '$GAME_ID' for ${SECONDS_TO_RUN}s on Windows"
( cd /tmp && cmd.exe /c "$(wslpath -w "$BAT")" )
