#!/usr/bin/env bash
# resolve-migo-artifact.sh <platform> <dest>
#
# Obtains a migo runtime artifact for one platform.
#
#   default          download the release named by migo-version.txt, then
#                    verify its sha256 against the checksum published beside it
#   MIGO_LOCAL_REPO  use the artifact built inside that migo checkout instead
#
# MIGO_ABI selects the Android ABI (default arm64-v8a).
# MIGO_PROFILE selects the product profile in local mode (default full).
set -euo pipefail

PLATFORM="${1:?usage: resolve-migo-artifact.sh <platform> <dest>}"
DEST="${2:?usage: resolve-migo-artifact.sh <platform> <dest>}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABI="${MIGO_ABI:-arm64-v8a}"
REPO="minigame-labs/migo"

case "$PLATFORM" in
  android-aar) ;;
  *)
    echo "ERROR: unknown platform '$PLATFORM' (supported: android-aar)" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$DEST")"

if [ -n "${MIGO_LOCAL_REPO:-}" ]; then
  # The debug AAR, not the release one: producing a release AAR requires the V8
  # provenance chain, which a plain checkout cannot satisfy.
  # build-aar.sh names its output migo-<product-profile>-<build-type>.aar, so the
  # profile is part of the filename and cannot be assumed away.
  PROFILE="${MIGO_PROFILE:-full}"
  SRC="$MIGO_LOCAL_REPO/platforms/android/dist/migo-${PROFILE}-debug.aar"
  if [ ! -f "$SRC" ]; then
    echo "ERROR: no locally built AAR at $SRC" >&2
    echo "       AARs present in that directory:" >&2
    ls "$MIGO_LOCAL_REPO/platforms/android/dist"/*.aar 2>/dev/null | sed 's|^|         |' >&2 \
      || echo "         (none)" >&2
    echo "       build it with: bash scripts/build-aar.sh debug $ABI --product-profile $PROFILE" >&2
    exit 3
  fi
  # Land the file atomically: copy to a temp file beside the destination, then
  # rename it into place. If this is interrupted (SIGINT, disk full), the
  # destination either does not exist or holds the complete file -- never a
  # truncated one that a later Gradle build would consume as if it were valid.
  TMP_DEST="$(mktemp "$DEST.XXXXXX")"
  trap 'rm -f "$TMP_DEST"' EXIT
  cp "$SRC" "$TMP_DEST"
  mv "$TMP_DEST" "$DEST"
  trap - EXIT
  echo "local:$(git -C "$MIGO_LOCAL_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  exit 0
fi

VERSION_FILE="$ROOT_DIR/migo-version.txt"
if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: migo-version.txt not found at $VERSION_FILE" >&2
  exit 3
fi
TAG="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
if [ -z "$TAG" ]; then
  echo "ERROR: migo-version.txt is empty; it must hold a migo release tag" >&2
  exit 3
fi

ASSET="migo-runtime-${TAG}-full-${ABI}.aar"
BASE="https://github.com/$REPO/releases/download/$TAG"

# The temp dir must live next to DEST, not in the system default (/tmp): if
# they are different filesystems, the final `mv` below degrades from an
# atomic rename into copy-then-unlink, reintroducing the partial-file window
# that the checksum check below exists to prevent.
TMP="$(mktemp -d "$(dirname "$DEST")/.migo-resolve.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

if ! curl -fsSL "$BASE/$ASSET" -o "$TMP/artifact.aar"; then
  echo "ERROR: could not download $ASSET from release '$TAG' of $REPO." >&2
  echo "       The tag comes from migo-version.txt; check that the release" >&2
  echo "       exists and publishes an asset named $ASSET." >&2
  echo "       To build against a local migo checkout instead, set" >&2
  echo "       MIGO_LOCAL_REPO=/path/to/migo" >&2
  exit 4
fi

# Checksum verification is not optional: a truncated download is otherwise
# indistinguishable from a good one until the build fails somewhere unrelated.
if ! curl -fsSL "$BASE/$ASSET.sha256" -o "$TMP/artifact.sha256"; then
  echo "ERROR: release '$TAG' publishes $ASSET but no $ASSET.sha256" >&2
  exit 4
fi

EXPECTED="$(awk '{print $1; exit}' "$TMP/artifact.sha256")"
ACTUAL="$(sha256sum "$TMP/artifact.aar" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
  rm -f "$TMP/artifact.aar"
  echo "ERROR: sha256 mismatch for $ASSET (expected $EXPECTED, got $ACTUAL)" >&2
  exit 5
fi

mv "$TMP/artifact.aar" "$DEST"
echo "$TAG"
