#!/usr/bin/env bash
# Exercises scripts/lib/select-release-asset.py directly via stdin. This is
# the correct seam for testing profile matching: it needs no network access
# and no trust-anchor override on resolve-migo-artifact.sh itself.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="$ROOT_DIR/scripts/lib/select-release-asset.py"

fail() { echo "FAIL: $1" >&2; exit 1; }

run() { python3 "$SELECTOR" android-aar "$1" <<<"$2"; }
run_kind() { python3 "$SELECTOR" "$1" "$2" <<<"$3"; }

# A realistic release.yml asset list: it uploads the whole dist directory
# (platforms/android/dist/* plus reports/*.json), so a real release carries
# both AARs, their attestations, size/checksum reports, and version metadata
# -- not just the two .aar files.
REALISTIC_RELEASE='{"assets":[
  {"name":"migo-full-release.aar","browser_download_url":"https://example/migo-full-release.aar"},
  {"name":"migo-full-release.aar.attestation.json","browser_download_url":"https://example/full.attestation.json"},
  {"name":"migo-slim-release.aar","browser_download_url":"https://example/migo-slim-release.aar"},
  {"name":"migo-slim-release.aar.attestation.json","browser_download_url":"https://example/slim.attestation.json"},
  {"name":"SHA256SUMS.txt","browser_download_url":"https://example/SHA256SUMS.txt"},
  {"name":"version.json","browser_download_url":"https://example/version.json"},
  {"name":"size-report-full.txt","browser_download_url":"https://example/size-report-full.txt"},
  {"name":"size-report-slim.txt","browser_download_url":"https://example/size-report-slim.txt"},
  {"name":"power-compare-summary.json","browser_download_url":"https://example/power-compare-summary.json"}
]}'

# 1. Exactly one match for "full" against the realistic asset list, despite
#    the profile name also appearing inside non-.aar filenames
#    ("migo-full-release.aar.attestation.json", "size-report-full.txt").
OUT="$(run full "$REALISTIC_RELEASE")" || fail "full profile did not resolve against a realistic asset list"
[ "$OUT" = "https://example/migo-full-release.aar" ] \
  || fail "full profile resolved the wrong URL: $OUT"

# 2. Exactly one match for "slim" against the same list.
OUT="$(run slim "$REALISTIC_RELEASE")" || fail "slim profile did not resolve against a realistic asset list"
[ "$OUT" = "https://example/migo-slim-release.aar" ] \
  || fail "slim profile resolved the wrong URL: $OUT"

# 3. Zero matches: fails and lists every asset name the release publishes.
set +e
ERR="$(run full '{"assets":[
  {"name":"migo-slim-release.aar","browser_download_url":"https://example/slim.aar"}
]}' 2>&1 1>/dev/null)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "zero-match case should fail"
echo "$ERR" | grep -q "migo-slim-release.aar" \
  || fail "zero-match case did not list the published asset: $ERR"

# 4. More than one match: refuses and lists every candidate, picks none.
set +e
ERR="$(run full '{"assets":[
  {"name":"migo-full-release.aar","browser_download_url":"https://example/a.aar"},
  {"name":"migo-runtime-full-release.aar","browser_download_url":"https://example/b.aar"}
]}' 2>&1 1>/dev/null)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "ambiguous case should fail"
echo "$ERR" | grep -q "migo-full-release.aar" \
  || fail "ambiguous case missing first candidate: $ERR"
echo "$ERR" | grep -q "migo-runtime-full-release.aar" \
  || fail "ambiguous case missing second candidate: $ERR"

# 5. A July-15-style leftover from the retired naming scheme
#    (migo-runtime-<version>-<profile>-<abi>.aar) must NOT match: its
#    trailing segments are [arm64, v8a], not [full, release], even though
#    "full" appears elsewhere in the name.
set +e
run full '{"assets":[
  {"name":"migo-runtime-0.9.0-full-arm64-v8a.aar","browser_download_url":"https://example/leftover.aar"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "the retired migo-runtime-*-arm64-v8a.aar naming must not match profile 'full'"

# 6. A differently-profiled release build must not match ("full" must not be
#    satisfied by migo-slim-release.aar).
set +e
run full '{"assets":[
  {"name":"migo-slim-release.aar","browser_download_url":"https://example/slim.aar"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "'migo-slim-release.aar' must not satisfy profile 'full'"

# 7. The linux-sdk kind matches its own trailing segments (["linux","x86_64"])
#    against the real Linux SDK release, and does NOT match an AAR sitting in
#    the same release. A kind that matched across artifact types would hand the
#    Android build a tarball, or the Linux build an AAR.
LINUX_RELEASE='{"assets":[
  {"name":"migo-sdk-linux-x86_64.tar.gz","browser_download_url":"https://example/sdk.tar.gz"},
  {"name":"migo-sdk-linux-x86_64.tar.gz.attestation.json","browser_download_url":"https://example/att"},
  {"name":"migo-full-release.aar","browser_download_url":"https://example/full.aar"}
]}'
URL="$(run_kind linux-sdk full "$LINUX_RELEASE")" \
  || fail "linux-sdk did not resolve against a realistic Linux release"
[ "$URL" = "https://example/sdk.tar.gz" ] \
  || fail "linux-sdk resolved the wrong asset: $URL"

# 8. An unknown kind is refused rather than silently treated as some default.
set +e
python3 "$SELECTOR" no-such-kind full <<<"$LINUX_RELEASE" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -eq 2 ] || fail "an unknown artifact kind must exit 2, got $STATUS"

echo "OK: select-release-asset contract holds (8 checks)"
