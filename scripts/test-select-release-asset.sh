#!/usr/bin/env bash
# Exercises scripts/lib/select-release-asset.py directly via stdin. This is
# the correct seam for testing asset matching: it needs no network access
# and no trust-anchor override on resolve-migo-artifact.sh itself.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="$ROOT_DIR/scripts/lib/select-release-asset.py"

fail() { echo "FAIL: $1" >&2; exit 1; }

run_kind() { python3 "$SELECTOR" "$1" "$2" "$3" <<<"$4"; }

# A realistic release: one universal Android AAR, its C API tarballs for both
# ABIs, and the Linux/Windows/OpenHarmony SDK tarballs for both architectures
# they publish -- verified against an actual migo release (v0.9.3-rc.2, minus
# the two arches that release predates) rather than invented.
REALISTIC_RELEASE='{"assets":[
  {"name":"migo-0.9.3-android.aar","browser_download_url":"https://example/android.aar"},
  {"name":"migo-0.9.3-android.aar.attestation.json","browser_download_url":"https://example/android.aar.attestation.json"},
  {"name":"migo-0.9.3-capi-android-arm64.tar.gz","browser_download_url":"https://example/capi-android-arm64.tar.gz"},
  {"name":"migo-0.9.3-capi-android-x86_64.tar.gz","browser_download_url":"https://example/capi-android-x86_64.tar.gz"},
  {"name":"migo-0.9.3-capi-linux-x86_64.tar.gz","browser_download_url":"https://example/capi-linux-x86_64.tar.gz"},
  {"name":"migo-0.9.3-capi-linux-arm64.tar.gz","browser_download_url":"https://example/capi-linux-arm64.tar.gz"},
  {"name":"migo-0.9.3-capi-windows-x86_64.tar.gz","browser_download_url":"https://example/capi-windows-x86_64.tar.gz"},
  {"name":"migo-0.9.3-capi-windows-arm64.tar.gz","browser_download_url":"https://example/capi-windows-arm64.tar.gz"},
  {"name":"migo-0.9.3-capi-ohos-x86_64.tar.gz","browser_download_url":"https://example/capi-ohos-x86_64.tar.gz"},
  {"name":"migo-0.9.3-capi-ohos-arm64.tar.gz","browser_download_url":"https://example/capi-ohos-arm64.tar.gz"}
]}'

# 1. android-aar matches the one universal AAR structurally (ending in
#    ["android"]), regardless of what profile or arch is passed -- there is
#    no ABI/profile split to select between: one AAR is multi-ABI, and the
#    product profile is an internal build axis a consumer cannot choose.
OUT="$(run_kind android-aar full x86_64 "$REALISTIC_RELEASE")" \
  || fail "android-aar did not resolve against a realistic asset list"
[ "$OUT" = "https://example/android.aar" ] \
  || fail "android-aar resolved the wrong URL: $OUT"

OUT="$(run_kind android-aar slim arm64 "$REALISTIC_RELEASE")" \
  || fail "android-aar did not resolve with different profile/arch values"
[ "$OUT" = "https://example/android.aar" ] \
  || fail "android-aar resolved a different URL for different profile/arch: $OUT"

# 2. Zero matches: fails and lists every asset name the release publishes.
set +e
ERR="$(run_kind android-aar full x86_64 '{"assets":[
  {"name":"migo-0.9.3-capi-android-arm64.tar.gz","browser_download_url":"https://example/capi.tar.gz"}
]}' 2>&1 1>/dev/null)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "zero-match case should fail"
echo "$ERR" | grep -q "migo-0.9.3-capi-android-arm64.tar.gz" \
  || fail "zero-match case did not list the published asset: $ERR"

# 3. The retired per-profile naming scheme (migo-<profile>-release.aar) must
#    NOT satisfy android-aar any more: Gradle's internal task name reaching
#    consumers is exactly what commit 915aaa0 stopped keying on.
set +e
run_kind android-aar full x86_64 '{"assets":[
  {"name":"migo-full-release.aar","browser_download_url":"https://example/old.aar"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "the retired migo-<profile>-release.aar naming must not satisfy android-aar"

# 4. linux-sdk/windows-sdk/ohos-sdk each match their own (platform, arch)
#    trailing segments, and do NOT match an asset from a different platform
#    or the other architecture sitting in the same release. A kind that
#    matched across platforms or architectures would hand a build the wrong
#    bytes silently.
for spec in \
  "linux-sdk   x86_64  https://example/capi-linux-x86_64.tar.gz" \
  "linux-sdk   arm64   https://example/capi-linux-arm64.tar.gz" \
  "windows-sdk x86_64  https://example/capi-windows-x86_64.tar.gz" \
  "windows-sdk arm64   https://example/capi-windows-arm64.tar.gz" \
  "ohos-sdk    x86_64  https://example/capi-ohos-x86_64.tar.gz" \
  "ohos-sdk    arm64   https://example/capi-ohos-arm64.tar.gz" \
; do
  read -r kind arch want <<<"$spec"
  URL="$(run_kind "$kind" full "$arch" "$REALISTIC_RELEASE")" \
    || fail "$kind ($arch) did not resolve against a realistic release"
  [ "$URL" = "$want" ] || fail "$kind ($arch) resolved the wrong asset: $URL"
done

# 5. linux-sdk still refuses to guess between two candidates: unlike
#    android-aar, its match is structural (a trailing-segment suffix), so an
#    unrelated asset attached to the same release can still collide with it.
set +e
ERR="$(run_kind linux-sdk full x86_64 '{"assets":[
  {"name":"migo-linux-x86_64.tar.gz","browser_download_url":"https://example/a.tar.gz"},
  {"name":"migo-sdk-linux-x86_64.tar.gz","browser_download_url":"https://example/b.tar.gz"}
]}' 2>&1 1>/dev/null)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "ambiguous linux-sdk case should fail"
echo "$ERR" | grep -q "migo-linux-x86_64.tar.gz" \
  || fail "ambiguous case missing first candidate: $ERR"
echo "$ERR" | grep -q "migo-sdk-linux-x86_64.tar.gz" \
  || fail "ambiguous case missing second candidate: $ERR"

# 6. A July-15-style leftover from the retired naming scheme
#    (migo-runtime-<version>-<profile>-<abi>.aar) must NOT match linux-sdk
#    either: its trailing segments are [arm64, v8a], not [linux, x86_64].
set +e
run_kind linux-sdk full x86_64 '{"assets":[
  {"name":"migo-runtime-0.9.0-full-arm64-v8a.aar","browser_download_url":"https://example/leftover.aar"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "the retired migo-runtime-*-arm64-v8a.aar naming must not match linux-sdk"

# 7. linux-sdk for one arch must not match the other arch's asset -- the
#    regression this whole rewrite exists to catch: a merge once left arch
#    hardcoded to x86_64 for every kind, silently ignoring the argument.
set +e
run_kind linux-sdk full arm64 '{"assets":[
  {"name":"migo-0.9.3-capi-linux-x86_64.tar.gz","browser_download_url":"https://example/x64-only.tar.gz"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "linux-sdk arm64 must not match an x86_64-only release"

# 8. An unknown kind is refused rather than silently treated as some default.
set +e
python3 "$SELECTOR" no-such-kind full x86_64 <<<"$REALISTIC_RELEASE" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -eq 2 ] || fail "an unknown artifact kind must exit 2, got $STATUS"

echo "OK: select-release-asset contract holds (8 checks)"
