#!/usr/bin/env python3
"""Selects a GitHub release asset matching a product profile and ABI.

Reads a "get a release by tag" JSON response (as returned by
https://api.github.com/repos/<repo>/releases/tags/<tag>) from stdin, and
prints the `browser_download_url` of the single `.aar` asset whose name
contains both PROFILE and ABI as delimiter-bounded segments, e.g. "full" and
"arm64-v8a" in "migo-runtime-0.9.0-full-arm64-v8a.aar".

This exists so resolve-migo-artifact.sh never has to guess an asset filename
by string concatenation: the version segment embedded in a release asset name
is a product version, which need not equal the git tag used to fetch it.

Exit codes:
  0  exactly one match; its download URL is on stdout
  1  no match, or more than one match; a diagnostic listing is on stderr
  2  usage error
"""
import json
import re
import sys


def has_segment(name, needle):
    """True if `needle` occurs in `name` bounded by non-alnum chars or ends.

    A plain substring check would let profile "full" match an asset named
    "...fullsize...". Splitting the name on a fixed delimiter such as "-"
    would break an ABI like "arm64-v8a", which itself contains a hyphen, into
    two tokens. Bounding the substring itself (rather than pre-splitting)
    avoids both failure modes.
    """
    pattern = r"(?:^|[^A-Za-z0-9])" + re.escape(needle) + r"(?:[^A-Za-z0-9]|$)"
    return re.search(pattern, name) is not None


def select(release, profile, abi):
    """Returns (matches, all_names) for a parsed release JSON object."""
    assets = release.get("assets", []) or []
    all_names = [a.get("name", "") for a in assets]
    matches = [
        a
        for a in assets
        if a.get("name", "").endswith(".aar")
        and has_segment(a.get("name", ""), profile)
        and has_segment(a.get("name", ""), abi)
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
