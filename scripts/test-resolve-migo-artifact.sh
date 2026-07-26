#!/usr/bin/env bash
# Exercises resolve-migo-artifact.sh without needing a real migo release: the
# local mode is driven against a fake repo tree, and the default mode is only
# checked for the failure it must produce while no runtime release exists.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT_DIR/scripts/resolve-migo-artifact.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Unknown platform is rejected.
if bash "$RESOLVER" no-such-platform "$WORK/out.aar" >/dev/null 2>&1; then
  fail "unknown platform was accepted"
fi

# 2. Local mode copies the locally built debug AAR.
FAKE_REPO="$WORK/migo"
mkdir -p "$FAKE_REPO/platforms/android/dist"
echo "fake-aar-bytes" > "$FAKE_REPO/platforms/android/dist/migo-full-debug.aar"
MIGO_LOCAL_REPO="$FAKE_REPO" bash "$RESOLVER" android-aar "$WORK/local.aar" >/dev/null
[ -f "$WORK/local.aar" ] || fail "local mode produced no file"
grep -q "fake-aar-bytes" "$WORK/local.aar" || fail "local mode copied the wrong bytes"

# 5. A dist directory holding only differently-profiled AARs must not satisfy the
#    default profile. This is the bug the first implementation had: assuming a
#    bare migo-debug.aar name that build-aar.sh never produces.
WRONG_PROFILE="$WORK/wrongprofile"
mkdir -p "$WRONG_PROFILE/platforms/android/dist"
echo "slim" > "$WRONG_PROFILE/platforms/android/dist/migo-slim-debug.aar"
if MIGO_LOCAL_REPO="$WRONG_PROFILE" bash "$RESOLVER" android-aar "$WORK/wrong.aar" >/dev/null 2>&1; then
  fail "default profile resolved against a slim-only dist directory"
fi
MIGO_LOCAL_REPO="$WRONG_PROFILE" MIGO_PROFILE=slim bash "$RESOLVER" android-aar "$WORK/slim.aar" >/dev/null \
  || fail "MIGO_PROFILE=slim did not resolve the slim AAR"

# 3. Local mode fails loudly when the local build is missing, rather than
#    silently falling back to a download the user did not ask for.
EMPTY_REPO="$WORK/empty"
mkdir -p "$EMPTY_REPO"
if MIGO_LOCAL_REPO="$EMPTY_REPO" bash "$RESOLVER" android-aar "$WORK/none.aar" >/dev/null 2>&1; then
  fail "local mode succeeded with no locally built AAR"
fi

# 4. Default mode must fail with a message naming the missing release, not with
#    a bare curl/gh error.
set +e
OUT="$(bash "$RESOLVER" android-aar "$WORK/dl.aar" 2>&1)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "default mode succeeded although no runtime release exists"
echo "$OUT" | grep -q "migo-version.txt" \
  || fail "default-mode failure does not point at the version pin: $OUT"

echo "OK: resolver contract holds (5 checks)"
