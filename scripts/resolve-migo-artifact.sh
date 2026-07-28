#!/usr/bin/env bash
# resolve-migo-artifact.sh <platform> <dest>
#
# Obtains a migo runtime artifact for one platform.
#
#   default          discover the matching asset on the release named by
#                    migo-version.txt, download it, then verify it against
#                    the release attestation published beside it
#   MIGO_LOCAL_REPO  use the artifact built inside that migo checkout instead
#
# MIGO_PROFILE selects the product profile (default full), in both modes.
# GITHUB_TOKEN, if set, is sent as a bearer token on GitHub API/download
# requests (needed for private repos or to dodge unauthenticated rate
# limits); it is optional otherwise.
set -euo pipefail

PLATFORM="${1:?usage: resolve-migo-artifact.sh <platform> <dest>}"
DEST="${2:?usage: resolve-migo-artifact.sh <platform> <dest>}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${MIGO_PROFILE:-full}"
REPO="minigame-labs/migo"

# Each platform names the version file holding its release tag. They are
# separate because the platforms release independently: the Android runtime and
# the Linux SDK are cut from different tags, and folding them into one pin would
# force a lockstep neither side actually has.
case "$PLATFORM" in
  android-aar) VERSION_FILE="$ROOT_DIR/migo-version.txt" ;;
  linux-sdk)   VERSION_FILE="$ROOT_DIR/migo-linux-version.txt" ;;
  *)
    echo "ERROR: unknown platform '$PLATFORM' (supported: android-aar, linux-sdk)" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$DEST")"

if [ -n "${MIGO_LOCAL_REPO:-}" ] && [ "$PLATFORM" = "linux-sdk" ]; then
  # The Linux SDK is a prefix tree, not a single file: build-linux-sdk.sh stages
  # it under dist/ and consumers point CMake or pkg-config at that prefix. So
  # DEST is a directory here, mirroring what the download path below unpacks.
  SRC="$MIGO_LOCAL_REPO/dist/migo-linux-x86_64"
  if [ ! -f "$SRC/lib/libmigo.a" ]; then
    echo "ERROR: no locally staged Linux SDK at $SRC" >&2
    echo "       build it with: bash scripts/build-linux-sdk.sh" >&2
    exit 3
  fi
  rm -rf "$DEST"
  mkdir -p "$DEST"
  cp -a "$SRC/." "$DEST/"
  echo "local:$(git -C "$MIGO_LOCAL_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  exit 0
fi

if [ -n "${MIGO_LOCAL_REPO:-}" ]; then
  # The debug AAR, not the release one: producing a release AAR requires the V8
  # provenance chain, which a plain checkout cannot satisfy.
  # build-aar.sh names its output migo-<product-profile>-<build-type>.aar, so the
  # profile is part of the filename and cannot be assumed away.
  SRC="$MIGO_LOCAL_REPO/platforms/android/dist/migo-${PROFILE}-debug.aar"
  if [ ! -f "$SRC" ]; then
    echo "ERROR: no locally built AAR at $SRC" >&2
    echo "       AARs present in that directory:" >&2
    ls "$MIGO_LOCAL_REPO/platforms/android/dist"/*.aar 2>/dev/null | sed 's|^|         |' >&2 \
      || echo "         (none)" >&2
    echo "       build it with: bash scripts/build-aar.sh debug --product-profile $PROFILE" >&2
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

if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: version pin for '$PLATFORM' not found at $VERSION_FILE" >&2
  exit 3
fi
TAG="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
if [ -z "$TAG" ]; then
  echo "ERROR: $VERSION_FILE is empty; it must hold a migo release tag" >&2
  exit 3
fi

# The temp dir must live next to DEST, not in the system default (/tmp): if
# they are different filesystems, the final `mv` below degrades from an
# atomic rename into copy-then-unlink, reintroducing the partial-file window
# that the attestation check below exists to prevent.
TMP="$(mktemp -d "$(dirname "$DEST")/.migo-resolve.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

RELEASE_JSON="$TMP/release.json"
RELEASE_API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
if ! curl -fsSL "${AUTH_HEADER[@]}" "$RELEASE_API" -o "$RELEASE_JSON"; then
  echo "ERROR: could not download the release metadata for tag '$TAG' of $REPO" >&2
  echo "       (GET $RELEASE_API)." >&2
  echo "       The tag comes from migo-version.txt; check that the release exists." >&2
  echo "       To build against a local migo checkout instead, set" >&2
  echo "       MIGO_LOCAL_REPO=/path/to/migo" >&2
  exit 4
fi

# Discover the asset instead of guessing its filename by concatenation:
# build-aar.sh names its output migo-<profile>-<build-type>.aar, and the
# release workflow always builds with build-type "release" (see
# release.yml). Discovery only pins that trailing profile/build-type tail;
# everything in front of it (product name, version) stays unconstrained.
# Each AAR is multi-ABI (Gradle picks the right .so per device at build
# time), so there is no ABI segment to match on at all.
if ! ASSET_URL="$(python3 "$ROOT_DIR/scripts/lib/select-release-asset.py" "$PLATFORM" "$PROFILE" < "$RELEASE_JSON")"; then
  echo "ERROR: could not select a '$PLATFORM' asset from release '$TAG' of $REPO." >&2
  exit 4
fi
ASSET="$(basename "$ASSET_URL")"

if ! curl -fsSL "${AUTH_HEADER[@]}" "$ASSET_URL" -o "$TMP/artifact.bin"; then
  echo "ERROR: could not download $ASSET from release '$TAG' of $REPO." >&2
  exit 4
fi

# Verification is not optional: an unverified download is otherwise
# indistinguishable from a good one until the build fails somewhere
# unrelated. Migo's release pipeline (build-aar.sh) publishes an attestation
# beside each AAR (<asset>.attestation.json) -- not a bare <asset>.sha256 --
# so that is what's fetched and checked here.
if ! curl -fsSL "${AUTH_HEADER[@]}" "$ASSET_URL.attestation.json" -o "$TMP/attestation.json"; then
  echo "ERROR: release '$TAG' publishes $ASSET but no $ASSET.attestation.json" >&2
  exit 4
fi

ACTUAL_SIZE="$(wc -c < "$TMP/artifact.bin" | tr -d ' ')"
ACTUAL_SHA256="$(sha256sum "$TMP/artifact.bin" | awk '{print $1}')"
if ! python3 "$ROOT_DIR/scripts/lib/verify-attestation.py" "$ASSET" "$ACTUAL_SIZE" "$ACTUAL_SHA256" \
     < "$TMP/attestation.json"; then
  rm -f "$TMP/artifact.bin"
  echo "ERROR: attestation verification failed for $ASSET from release '$TAG' of $REPO." >&2
  exit 5
fi

if [ "$PLATFORM" = "linux-sdk" ]; then
  # The tarball carries a single top-level migo-linux-x86_64/ directory; strip it
  # so DEST itself becomes the prefix, which is what CMake and pkg-config want.
  rm -rf "$DEST"
  mkdir -p "$DEST"
  tar xzf "$TMP/artifact.bin" -C "$DEST" --strip-components=1
else
  mv "$TMP/artifact.bin" "$DEST"
fi
echo "$TAG"
