#!/usr/bin/env bash
# Exercises scripts/lib/select-release-asset.py directly via stdin. This is
# the correct seam for testing profile/ABI matching: it needs no network
# access and no trust-anchor override on resolve-migo-artifact.sh itself.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="$ROOT_DIR/scripts/lib/select-release-asset.py"

fail() { echo "FAIL: $1" >&2; exit 1; }

run() { python3 "$SELECTOR" "$1" "$2" <<<"$3"; }

# 1. Exactly one match resolves to its download URL.
OUT="$(run full arm64-v8a '{"assets":[
  {"name":"migo-runtime-0.9.0-full-arm64-v8a.aar","browser_download_url":"https://example/full.aar"},
  {"name":"migo-runtime-0.9.0-full-x86_64.aar","browser_download_url":"https://example/full-x86.aar"}
]}')" || fail "one-match case did not exit 0"
[ "$OUT" = "https://example/full.aar" ] || fail "one-match case resolved the wrong URL: $OUT"

# 2. Zero matches: fails and lists every asset name the release publishes.
set +e
ERR="$(run full arm64-v8a '{"assets":[
  {"name":"migo-runtime-0.9.0-slim-arm64-v8a.aar","browser_download_url":"https://example/slim.aar"}
]}' 2>&1 1>/dev/null)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "zero-match case should fail"
echo "$ERR" | grep -q "migo-runtime-0.9.0-slim-arm64-v8a.aar" \
  || fail "zero-match case did not list the published asset: $ERR"

# 3. More than one match: refuses and lists every candidate, picks none.
set +e
ERR="$(run full arm64-v8a '{"assets":[
  {"name":"migo-runtime-0.9.0-full-arm64-v8a.aar","browser_download_url":"https://example/a.aar"},
  {"name":"migo-runtime-0.9.1-full-arm64-v8a.aar","browser_download_url":"https://example/b.aar"}
]}' 2>&1 1>/dev/null)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "ambiguous case should fail"
echo "$ERR" | grep -q "migo-runtime-0.9.0-full-arm64-v8a.aar" \
  || fail "ambiguous case missing first candidate: $ERR"
echo "$ERR" | grep -q "migo-runtime-0.9.1-full-arm64-v8a.aar" \
  || fail "ambiguous case missing second candidate: $ERR"

# 4. "full" must not match inside a longer word (e.g. "fullsize").
set +e
run full arm64-v8a '{"assets":[
  {"name":"migo-runtime-0.9.0-fullsize-arm64-v8a.aar","browser_download_url":"https://example/x.aar"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "'fullsize' must not satisfy profile 'full'"

# 5. The ABI match must be structural (the name's trailing "-"-segments),
#    not a delimiter-bounded substring search: a name with an extra "-debug"
#    suffix after the ABI contains "arm64-v8a" bounded by "-" on both sides,
#    but its actual trailing segments are ["v8a", "debug"], not
#    ["arm64", "v8a"] -- it must NOT match.
set +e
run full arm64-v8a '{"assets":[
  {"name":"migo-runtime-0.9.0-full-arm64-v8a-debug.aar","browser_download_url":"https://example/y.aar"}
]}' >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "'...-arm64-v8a-debug.aar' must not satisfy abi 'arm64-v8a'"

# 6. The plain (non-debug) name for the same profile/ABI must still match.
OUT="$(run full arm64-v8a '{"assets":[
  {"name":"migo-runtime-0.9.0-full-arm64-v8a.aar","browser_download_url":"https://example/plain.aar"}
]}')" || fail "plain arm64-v8a name should match"
[ "$OUT" = "https://example/plain.aar" ] || fail "plain-name case resolved the wrong URL: $OUT"

echo "OK: select-release-asset contract holds (6 checks)"
