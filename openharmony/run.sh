#!/usr/bin/env bash
# Build and run the OpenHarmony example against a resolved Migo SDK, on a
# connected device or emulator.
#
# Usage: bash openharmony/run.sh [ARCH]
#   ARCH   x86_64 (the emulator's architecture, default) or aarch64 (real
#          hardware)
#
# Requires DevEco Studio (hvigor lives in it) and a real Windows disk: hvigor
# rejects a UNC project path outright, and this repo may itself be checked out
# on one (a WSL distro's filesystem, a network share). The project is synced
# to a local Windows directory before building, the same way the SDK/engine
# repo's own OpenHarmony host does it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ARCH="${1:-x86_64}"
case "$ARCH" in
  x86_64|aarch64) ;;
  *) echo "usage: $0 [x86_64|aarch64]" >&2; exit 2 ;;
esac

info() { echo -e "\033[0;36m[ohos-example] $*\033[0m"; }
err()  { echo -e "\033[0;31m[ohos-example] $*\033[0m" >&2; }
ok()   { echo -e "\033[0;32m[ohos-example] $*\033[0m"; }

# This script's own CLI keeps the Rust-triple-style "aarch64" a real-hardware
# user would type, but two other things downstream have their own,
# different word for the same architecture, and neither is "aarch64":
#   MIGO_ARCH        resolve-migo-artifact.sh / select-release-asset.py match
#                     migo's *published* tarball names, which say "arm64"
#                     (migo-<version>-capi-ohos-arm64.tar.gz) -- migo's own
#                     release job iterates `arm64 x86_64`, never "aarch64".
#   OHOS_LIB_ARCH     CMakeLists.txt's `libs/${OHOS_ARCH}/libmigo_capi.a` is
#                     read at hvigor/CMake time, where OHOS_ARCH is set by
#                     ohos.toolchain.cmake to "arm64-v8a" (or "x86_64"),
#                     OpenHarmony's own ABI directory name -- the same one
#                     Android uses, not migo's release-asset word either.
MIGO_ARCH="$ARCH"
OHOS_LIB_ARCH="$ARCH"
if [ "$ARCH" = "aarch64" ]; then
  MIGO_ARCH="arm64"
  OHOS_LIB_ARCH="arm64-v8a"
fi

SDK="$HERE/sdk-$ARCH"
if [ ! -f "$SDK/lib/libmigo_capi.a" ]; then
  info "resolving the Migo OpenHarmony SDK ($ARCH)"
  MIGO_ARCH="$MIGO_ARCH" bash "$ROOT/scripts/resolve-migo-artifact.sh" ohos-sdk "$SDK"
fi

# Staged where CMakeLists.txt expects them -- same layout the SDK/engine
# repo's own build-ohos-host.sh produces, so nothing here is example-specific.
CPP_DIR="$HERE/entry/src/main/cpp"
mkdir -p "$CPP_DIR/libs/$OHOS_LIB_ARCH" "$CPP_DIR/migo-include"
cp "$SDK/lib/libmigo_capi.a" "$CPP_DIR/libs/$OHOS_LIB_ARCH/"
rm -rf "$CPP_DIR/migo-include/migo"
cp -r "$SDK/include/migo" "$CPP_DIR/migo-include/"

DEVECO_HOME="${DEVECO_HOME:-/mnt/c/Program Files/Huawei/DevEco Studio}"
HVIGOR="$DEVECO_HOME/tools/hvigor/bin/hvigorw.js"
if [ ! -f "$HVIGOR" ]; then
  err "hvigor not found at $HVIGOR"
  err "set DEVECO_HOME to the DevEco Studio installation"
  exit 1
fi
command -v wslpath >/dev/null 2>&1 || {
  err "wslpath not found: this needs a Windows-side DevEco install reached"
  err "through WSL. On a native Linux DevEco install, run hvigor directly"
  err "against $HERE instead of this script."
  exit 1
}

WIN_DIR="${MIGO_OHOS_WIN_DIR:-C:\\migo-ohos-example}"
WIN_DIR_WSL="$(wslpath -u "$WIN_DIR")"
info "syncing the project to $WIN_DIR"
mkdir -p "$WIN_DIR_WSL"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude 'build/' --exclude '.hvigor/' --exclude 'oh_modules/' \
    --exclude 'sdk-x86_64/' --exclude 'sdk-aarch64/' \
    "$HERE/" "$WIN_DIR_WSL/"
else
  cp -ru "$HERE/." "$WIN_DIR_WSL/"
fi

# Two details below are load-bearing, both found by hitting them:
#   set "ERRORLEVEL="  an inherited variable of that name makes %errorlevel%
#                       expand to it forever, hiding every real failure.
#   HVIGOR_EXIT captured on the line right after node -- any command between,
#     even echo, would overwrite %errorlevel% with its own before it's read.
DEVECO_WIN="$(wslpath -w "$DEVECO_HOME")"
cat > "$WIN_DIR_WSL/build-hap.bat" <<BAT
@echo off
setlocal
set "ERRORLEVEL="
set "DEVECO=$DEVECO_WIN"
set "DEVECO_SDK_HOME=%DEVECO%\\sdk"
set "NODE_HOME=%DEVECO%\\tools\\node"
set "JAVA_HOME=%DEVECO%\\jbr"
set "PATH=%NODE_HOME%;%JAVA_HOME%\\bin;%PATH%"
cd /d $WIN_DIR
"%NODE_HOME%\\node.exe" "%DEVECO%\\tools\\hvigor\\bin\\hvigorw.js" --mode module -p product=default assembleHap --no-daemon
set HVIGOR_EXIT=%errorlevel%
echo BUILD_EXIT=%HVIGOR_EXIT%
exit /b %HVIGOR_EXIT%
BAT

info "building the HAP with hvigor"
# Run from a local directory: cmd.exe started from a UNC cwd prints a warning,
# falls back to C:\Windows, and the resulting failure reads like a compile
# error rather than what it is.
( cd /tmp && cmd.exe /c "$(wslpath -w "$WIN_DIR_WSL/build-hap.bat")" ) || {
  err "hvigor failed"
  exit 1
}

HAP="$WIN_DIR_WSL/entry/build/default/outputs/default/entry-default-unsigned.hap"
[ -f "$HAP" ] || { err "hvigor reported success but produced no HAP at $HAP"; exit 1; }
ok "HAP: $HAP ($(stat -c %s "$HAP") bytes)"

HDC="${MIGO_OHOS_HDC:-$DEVECO_HOME/sdk/default/openharmony/toolchains/hdc.exe}"
if [ ! -f "$HDC" ]; then
  err "hdc not found at $HDC"
  err "set MIGO_OHOS_HDC, or DEVECO_HOME to the DevEco Studio installation"
  exit 1
fi

# hdc.exe is a Windows binary reached through WSL interop, and cmd-launched
# processes refuse a UNC working directory -- same reason the hvigor build
# above runs from a local one.
cd /tmp

TARGETS="$("$HDC" list targets 2>/dev/null | tr -d '\r' | grep -v '^$' || true)"
if [ -z "$TARGETS" ] || [ "$TARGETS" = "[Empty]" ]; then
  err "no OpenHarmony target connected (hdc list targets is empty)"
  err "start the emulator in DevEco's Device Manager, or connect a device"
  exit 1
fi
info "target: $(echo "$TARGETS" | head -1)"

info "installing $(stat -c %s "$HAP") bytes"
"$HDC" shell "rm -rf /data/local/tmp/migoexample; mkdir -p /data/local/tmp/migoexample" >/dev/null
"$HDC" file send "$WIN_DIR\\entry\\build\\default\\outputs\\default\\entry-default-unsigned.hap" \
  /data/local/tmp/migoexample/entry.hap >/dev/null
INSTALL_OUT="$("$HDC" shell "bm install -p /data/local/tmp/migoexample" 2>&1 | tr -d '\r')"
case "$INSTALL_OUT" in
  *successfully*) ok "installed" ;;
  *) err "install failed: $INSTALL_OUT"; exit 1 ;;
esac

info "launching com.migo.ohoshost"
"$HDC" shell "aa force-stop com.migo.ohoshost" >/dev/null 2>&1 || true
LAUNCH="$("$HDC" shell "aa start -a EntryAbility -b com.migo.ohoshost" 2>&1 | tr -d '\r')"
case "$LAUNCH" in
  *successfully*) ok "launched -- the demo game is now running on-device" ;;
  *) err "launch failed: $LAUNCH"; exit 1 ;;
esac
