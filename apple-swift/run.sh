#!/usr/bin/env bash
# Build and run the Apple example against a resolved Migo SDK.
#
# Usage: bash apple-swift/run.sh <macos|ios-simulator> [SECONDS]
#   macos          build the macOS app and run it
#   ios-simulator  build the iOS app, install it on a booted (or the first
#                  available) iPhone simulator and launch it
#   SECONDS        quit after this long and exit 0 only if the game became
#                  ready and was given frames (default: run until closed;
#                  on the simulator, 15)
#
# Opening MigoExample.xcodeproj in Xcode does the same; this script is what a
# terminal or CI uses.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PLATFORM="${1:?usage: run.sh <macos|ios-simulator> [SECONDS]}"
SECONDS_TO_RUN="${2:-}"
DERIVED="$HERE/build"

# The resolver verifies the download against the release attestation; it is
# not a plain fetch.
echo "==> resolving the Migo Apple SDK"
bash "$ROOT/scripts/resolve-migo-artifact.sh" --if-stale apple-sdk "$HERE/sdk"

build() {
  echo "==> building $1 for $2"
  xcodebuild build -project "$HERE/MigoExample.xcodeproj" -scheme "$1" \
    -destination "$2" -configuration Debug -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation -quiet
}

case "$PLATFORM" in
  macos)
    build MigoExample-macOS "platform=macOS"
    APP="$DERIVED/Build/Products/Debug/MigoExample.app"
    echo "==> running"
    exec "$APP/Contents/MacOS/MigoExample" ${SECONDS_TO_RUN:+-MigoExampleRunSeconds "$SECONDS_TO_RUN"}
    ;;
  ios-simulator)
    UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items()
           if "iOS" in runtime for d in ds if d["name"].startswith("iPhone")]
booted = [d for d in devices if d["state"] == "Booted"]
print((booted or devices)[0]["udid"] if devices else "")')"
    [ -n "$UDID" ] || { echo "ERROR: no iPhone simulator is installed (Xcode > Settings > Components)" >&2; exit 2; }
    build MigoExample-iOS "platform=iOS Simulator,id=$UDID"
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/MigoExample.app"
    xcrun simctl boot "$UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null
    xcrun simctl install "$UDID" "$APP"
    echo "==> running on simulator $UDID"
    # --console-pty streams the app's standard output here and returns when
    # the app exits.
    xcrun simctl launch --console-pty --terminate-running-process "$UDID" com.example.migo.ios \
      -MigoExampleRunSeconds "${SECONDS_TO_RUN:-15}"
    ;;
  *)
    echo "ERROR: unknown platform '$PLATFORM' (macos or ios-simulator)" >&2
    exit 2
    ;;
esac
