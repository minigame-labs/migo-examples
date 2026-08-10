#!/usr/bin/env bash
# Exercises scripts/lib/select-release-asset.py directly via stdin. This is
# the correct seam for testing asset matching: it needs no network access
# and no trust-anchor override on resolve-migo-artifact.sh itself.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="$ROOT_DIR/scripts/lib/select-release-asset.py"

fail() { echo "FAIL: $1" >&2; exit 1; }

run_kind() { python3 "$SELECTOR" "$1" "$2" <<<"$3"; }

# A realistic publish-release.sh asset list: one universal Android AAR plus
# the Android C API tarballs, the Linux SDK tarball, and each asset's
# attestation -- not just the two files a given kind actually cares about.
REALISTIC_RELEASE='{"assets":[
  {"name":"migo-android-java.aar","browser_download_url":"https://example/migo-android-java.aar"},
  {"name":"migo-android-java.aar.attestation.json","browser_download_url":"https://example/java.attestation.json"},
  {"name":"migo-android-capi-arm64-v8a.tar.gz","browser_download_url":"https://example/capi-arm64.tar.gz"},
  {"name":"migo-android-capi-arm64-v8a.tar.gz.attestation.json","browser_download_url":"https://example/capi-arm64.attestation.json"},
  {"name":"migo-linux-x86_64.tar.gz","browser_download_url":"https://example/linux.tar.gz"},
  {"name":"migo-linux-x86_64.tar.gz.attestation.json","browser_download_url":"https://example/linux.attestation.json"}
]}'

# 1. android-aar matches the one universal AAR by exact name, regardless of
#    what profile is passed -- there is no profile split to select between
#    any more (publish-release.sh publishes a single AAR per release).
OUT="$(run_kind android-aar full "$REALISTIC_RELEASE")" \
  || fail "android-aar did not resolve against a realistic asset list"
[ "$OUT" = "https://example/migo-android-java.aar" ] \
  || fail "android-aar resolved the wrong URL: $OUT"

OUT="$(run_kind android-aar slim "$REALISTIC_RELEASE")" \
  || fail "android-aar did not resolve with a different profile value"
[ "$OUT" = "https://example/migo-android-java.aar" ] \
  || fail "android-aar resolved a different URL for a different profile: $OUT"

# 2. Zero matches: fails and lists every asset name the release publishes.
set +e
ERR="$(run_kind android-aar full '{"assets":[
  {"name":"migo-android-capi-arm64-v8a.tar.gz","browser_download_url":"https://example/capi.tar.gz"}
]}' 2>&1 1>/dev/null)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "zero-match case should fail"
echo "$ERR" | grep -q "migo-android-capi-arm64-v8a.tar.gz" \
  || fail "zero-match case did not list the published asset: $ERR"

# 3. The retired per-profile naming scheme (migo-<profile>-release.aar) must
#    NOT satisfy android-aar any more: exact-name matching means a leftover
#    asset from the old convention is invisible to the new one, not silently
#    accepted as a fallback.
set +e
run_kind android-aar full '{"assets":[
  {"name":"migo-full-release.aar","browser_download_url":"https://example/old.aar"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "the retired migo-<profile>-release.aar naming must not satisfy android-aar"

# 4. The linux-sdk kind matches its own trailing segments (["linux","x86_64"])
#    against the real Linux SDK release, and does NOT match the AAR sitting in
#    the same release. A kind that matched across artifact types would hand the
#    Android build a tarball, or the Linux build an AAR.
URL="$(run_kind linux-sdk full "$REALISTIC_RELEASE")" \
  || fail "linux-sdk did not resolve against a realistic release"
[ "$URL" = "https://example/linux.tar.gz" ] \
  || fail "linux-sdk resolved the wrong asset: $URL"

# 5. linux-sdk still refuses to guess between two candidates: unlike
#    android-aar, its match is structural (a trailing-segment suffix), so an
#    unrelated asset attached to the same release can still collide with it.
set +e
ERR="$(run_kind linux-sdk full '{"assets":[
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
run_kind linux-sdk full '{"assets":[
  {"name":"migo-runtime-0.9.0-full-arm64-v8a.aar","browser_download_url":"https://example/leftover.aar"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "the retired migo-runtime-*-arm64-v8a.aar naming must not match linux-sdk"

# 7. An unknown kind is refused rather than silently treated as some default.
set +e
python3 "$SELECTOR" no-such-kind full <<<"$REALISTIC_RELEASE" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -eq 2 ] || fail "an unknown artifact kind must exit 2, got $STATUS"

echo "OK: select-release-asset contract holds (7 checks)"
