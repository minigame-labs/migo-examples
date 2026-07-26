#!/usr/bin/env python3
"""Selects a GitHub release asset matching a product profile.

Reads a "get a release by tag" JSON response (as returned by
https://api.github.com/repos/<repo>/releases/tags/<tag>) from stdin, and
prints the `browser_download_url` of the single `.aar` asset whose filename
ends, structurally, in "-<profile>-release", e.g. "full-release" in
"migo-full-release.aar".

This exists so resolve-migo-artifact.sh never has to guess an asset filename
by string concatenation: everything before the trailing profile/build-type
segments (product name, version) is deliberately unconstrained -- that's the
point of discovering the asset instead of guessing its whole name.

There is deliberately no ABI parameter: build-aar.sh names its output
migo-<profile>-<build-type>.aar with no ABI segment, and the release
workflow (release.yml) always builds with build-type "release". Each AAR is
multi-ABI -- Gradle picks the right .so per device at build time -- so there
is nothing for an ABI to select between at the asset level.

Exit codes:
  0  exactly one match; its download URL is on stdout
  1  no match, or more than one match; a diagnostic listing is on stderr
  2  usage error
"""
import json
import sys

BUILD_TYPE = "release"


def matches_profile(name, profile):
    """True if `name` (an asset filename) structurally ends in profile-release.

    Strips the ".aar" suffix and splits the rest on "-". The final two
    segments must be exactly [profile, "release"].

    This is deliberately a structural check on trailing segments, not a
    substring search: a name like "migo-runtime-0.9.0-full-arm64-v8a.aar" (an
    artifact from an older, retired naming scheme) does not end in
    "-full-release" and correctly does not match, even though it contains
    "full" as a delimiter-bounded substring elsewhere in the name.
    """
    if not name.endswith(".aar"):
        return False
    stem = name[: -len(".aar")]
    segments = stem.split("-")
    return len(segments) >= 2 and segments[-2:] == [profile, BUILD_TYPE]


def select(release, profile):
    """Returns (matches, all_names) for a parsed release JSON object."""
    assets = release.get("assets", []) or []
    all_names = [a.get("name", "") for a in assets]
    matches = [a for a in assets if matches_profile(a.get("name", ""), profile)]
    return matches, all_names


def main(argv):
    if len(argv) != 2:
        print(
            "usage: select-release-asset.py <profile> < release.json",
            file=sys.stderr,
        )
        return 2
    profile = argv[1]

    try:
        release = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"ERROR: release JSON is not valid JSON: {exc}", file=sys.stderr)
        return 1

    matches, all_names = select(release, profile)

    if len(matches) == 1:
        print(matches[0].get("browser_download_url", ""))
        return 0

    if len(matches) == 0:
        print(
            f"ERROR: no asset in this release matches profile '{profile}'.",
            file=sys.stderr,
        )
        print("       assets published by this release:", file=sys.stderr)
        if all_names:
            for name in all_names:
                print(f"         {name}", file=sys.stderr)
        else:
            print("         (none)", file=sys.stderr)
        return 1

    print(
        f"ERROR: {len(matches)} assets in this release match profile "
        f"'{profile}'; refusing to guess which one to use.",
        file=sys.stderr,
    )
    print("       candidates:", file=sys.stderr)
    for asset in matches:
        print(f"         {asset.get('name', '')}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
