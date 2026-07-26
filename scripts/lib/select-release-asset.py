#!/usr/bin/env python3
"""Selects a GitHub release asset matching a product profile and ABI.

Reads a "get a release by tag" JSON response (as returned by
https://api.github.com/repos/<repo>/releases/tags/<tag>) from stdin, and
prints the `browser_download_url` of the single `.aar` asset whose filename
ends, structurally, in <profile>-<abi's own "-"-separated segments>, e.g.
"full-arm64-v8a" in "migo-runtime-0.9.0-full-arm64-v8a.aar".

This exists so resolve-migo-artifact.sh never has to guess an asset filename
by string concatenation: the version segment embedded in a release asset name
is a product version, which need not equal the git tag used to fetch it. Only
the trailing profile/abi segments are pinned; everything before them (product
name, version) is deliberately unconstrained -- that's the point of
discovering the asset instead of guessing its whole name.

Exit codes:
  0  exactly one match; its download URL is on stdout
  1  no match, or more than one match; a diagnostic listing is on stderr
  2  usage error
"""
import json
import sys


def matches_profile_and_abi(name, profile, abi):
    """True if `name` (an asset filename) structurally ends in profile-abi.

    Strips the ".aar" suffix and splits the rest on "-". The ABI's own
    segments (ABI may itself contain "-", e.g. "arm64-v8a" -> ["arm64",
    "v8a"]) must be exactly the *final* segments of the name, and PROFILE
    must be the single segment immediately before them.

    This is deliberately a structural check, not a substring search: a name
    like "...-full-arm64-v8a-debug.aar" contains "arm64-v8a" as a
    delimiter-bounded substring, but its actual trailing segments are
    ["v8a", "debug"] -- not ["arm64", "v8a"] -- so it correctly does not
    match. A substring check would have matched it silently and picked the
    wrong artifact.
    """
    if not name.endswith(".aar"):
        return False
    stem = name[: -len(".aar")]
    segments = stem.split("-")
    abi_segments = abi.split("-")

    if len(segments) < len(abi_segments) + 1:
        return False
    if segments[-len(abi_segments):] != abi_segments:
        return False
    return segments[-len(abi_segments) - 1] == profile


def select(release, profile, abi):
    """Returns (matches, all_names) for a parsed release JSON object."""
    assets = release.get("assets", []) or []
    all_names = [a.get("name", "") for a in assets]
    matches = [
        a for a in assets if matches_profile_and_abi(a.get("name", ""), profile, abi)
    ]
    return matches, all_names


def main(argv):
    if len(argv) != 3:
        print(
            "usage: select-release-asset.py <profile> <abi> < release.json",
            file=sys.stderr,
        )
        return 2
    profile, abi = argv[1], argv[2]

    try:
        release = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"ERROR: release JSON is not valid JSON: {exc}", file=sys.stderr)
        return 1

    matches, all_names = select(release, profile, abi)

    if len(matches) == 1:
        print(matches[0].get("browser_download_url", ""))
        return 0

    if len(matches) == 0:
        print(
            f"ERROR: no asset in this release matches profile '{profile}' "
            f"and abi '{abi}'.",
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
        f"'{profile}' and abi '{abi}'; refusing to guess which one to use.",
        file=sys.stderr,
    )
    print("       candidates:", file=sys.stderr)
    for asset in matches:
        print(f"         {asset.get('name', '')}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
