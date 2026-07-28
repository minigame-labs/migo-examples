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

# 4. Default mode must fail specifically because the release asset is not
#    available -- not because the version pin is missing or empty. Those are
#    different failures with different exit codes, and conflating them would let
#    a resolver that always died at the version-file stage pass this check
#    forever.
#
#    This points the pin at a tag that does not exist, rather than relying on
#    the real pin having no release behind it. An earlier version of this check
#    did the latter and passed only while the project had shipped nothing: the
#    day v0.9.0 was published the resolver started succeeding and this check
#    went red, having asserted a temporary state instead of an invariant.
VERSION_FILE="$ROOT_DIR/migo-version.txt"
VERSION_PIN="$(cat "$VERSION_FILE")"
restore_pin() { printf '%s\n' "$VERSION_PIN" > "$VERSION_FILE"; }
trap restore_pin EXIT
printf '%s\n' "tag-that-does-not-exist-contract-check" > "$VERSION_FILE"

set +e
OUT="$(bash "$RESOLVER" android-aar "$WORK/dl.aar" 2>&1)"
STATUS=$?
set -e
restore_pin
trap - EXIT

[ "$STATUS" -eq 4 ] \
  || fail "an unavailable release must fail with exit 4, got $STATUS: $OUT"
echo "$OUT" | grep -q "could not download" \
  || fail "the failure does not name the download as the cause: $OUT"
[ -f "$WORK/dl.aar" ] \
  && fail "default mode left a file at the destination despite failing"

# 6. Local mode must not leave a partial file at the destination when the
#    copy itself fails partway through: the destination is only ever
#    produced by an atomic rename of a fully-written temp file beside it.
#    Simulated deterministically with a file-size ulimit (standing in for
#    disk full or a SIGINT): the source is bigger than the limit, so `cp`
#    dies with SIGXFSZ after writing part of the temp file, and the script
#    must exit before ever reaching the rename.
BIG_REPO="$WORK/bigrepo"
mkdir -p "$BIG_REPO/platforms/android/dist"
BIG_SRC="$BIG_REPO/platforms/android/dist/migo-full-debug.aar"
dd if=/dev/urandom of="$BIG_SRC" bs=1M count=5 status=none
BIG_DEST="$WORK/interrupted.aar"

if ( ulimit -f 64 && MIGO_LOCAL_REPO="$BIG_REPO" bash "$RESOLVER" android-aar "$BIG_DEST" ) >/dev/null 2>&1; then
  fail "local mode should have failed when the copy hit the file-size limit (test setup problem)"
fi
[ -f "$BIG_DEST" ] \
  && fail "local mode left a file at the destination after the copy failed partway through"

echo "OK: resolver contract holds (6 checks)"
