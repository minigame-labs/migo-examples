#!/usr/bin/env bash
# Package every host example as a self-contained zip, for a release.
#
#   bash scripts/package-release.sh <tag> <output-dir>
#
# One zip per host directory, named migo-examples-<version>-<directory>.zip.
# Each holds that directory and everything it runs with -- the games it loads by
# name, the scripts that resolve and verify the runtime, the pin files naming
# which release -- so an unpacked zip builds exactly as a checkout of this tag
# does. Built with `git archive` from the tagged commit, so the bytes depend on
# the commit alone and the same tag always packages to the same files.
#
# A release names what it pins: every pin file must name <tag>, or this refuses
# to package. Otherwise a zip published as v0.9.18 would resolve some other
# runtime the first time it is built.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ne 2 ]; then
  echo "usage: $0 <tag> <output-dir>" >&2
  exit 2
fi
TAG="$1"
OUT="$2"
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "the tag must be a release version, vX.Y.Z: $TAG" >&2
  exit 2
fi
VERSION="${TAG#v}"

PINS=(migo-version.txt migo-linux-version.txt migo-windows-version.txt migo-ohos-version.txt migo-apple-version.txt)
for pin in "${PINS[@]}"; do
  pinned="$(tr -d '[:space:]' < "$pin")"
  if [ "$pinned" != "$TAG" ]; then
    echo "$pin pins $pinned, not $TAG: pin every platform to the release before tagging it" >&2
    exit 1
  fi
done

EXAMPLES=(android-java linux-cmake windows-cmake openharmony apple-swift)
SHARED=(games scripts LICENSE README.md README.zh-CN.md "${PINS[@]}")
for example in "${EXAMPLES[@]}"; do
  if [ -z "$(git ls-files -- "$example")" ]; then
    echo "$example has no tracked files: the list above and the repository disagree" >&2
    exit 1
  fi
done

mkdir -p "$OUT"
for example in "${EXAMPLES[@]}"; do
  name="migo-examples-$VERSION-$example"
  git archive --format=zip --prefix="$name/" -o "$OUT/$name.zip" HEAD -- "$example" "${SHARED[@]}"
  echo "$name.zip"
done
(cd "$OUT" && sha256sum migo-examples-"$VERSION"-*.zip > SHA256SUMS.txt)
