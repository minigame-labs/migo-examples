#!/usr/bin/env python3
"""Selects a GitHub release asset for one artifact kind.

Reads a "get a release by tag" JSON response (as returned by
https://api.github.com/repos/<repo>/releases/tags/<tag>) from stdin, and
prints the `browser_download_url` of the matching asset:

  android-aar   exact filename "migo-android-java.aar"
  linux-sdk     ".tar.gz"  ending, structurally, in ["linux", "x86_64"]
  windows-sdk   ".tar.gz"  ending, structurally, in ["windows", "x86_64"]

e.g. "migo-android-java.aar" and "migo-sdk-linux-x86_64.tar.gz".

android-aar is matched by exact name because publish-release.sh publishes one
universal AAR per release -- Gradle picks the ABI at build time and there is
no profile split, so there is no variable segment left to match structurally
against. `profile` is still accepted for this kind, for a uniform call
signature across kinds, but is otherwise ignored.

linux-sdk/windows-sdk still discover their asset rather than guess its whole
name: everything before the trailing target segments (product name, version)
is deliberately unconstrained -- that's the point of discovering the asset
instead of guessing its whole name.

There is deliberately no ABI parameter for these kinds: the Linux/Windows SDK
is one tarball per target triple, so the target is exactly what its trailing
segments carry.

IMPORTANT -- what the linux-sdk/windows-sdk structural match deliberately
does NOT establish: matching the target tail does not prove the asset is a
Migo artifact at all. An asset named "something-linux-x86_64.tar.gz" attached
to the same tagged release would structurally match here. That is accepted on
purpose: constraining the product-name prefix too would walk this back toward
the filename guessing this design exists to escape. Identity -- "is this
really the artifact it claims to be" -- is established downstream, by the
release attestation (verify-attestation.py), whose `package_file` must equal
the asset's own name. Do not treat a match from this script alone as proof of
what it returned.

Exit codes:
  0  exactly one match; its download URL is on stdout
  1  no match, or more than one match; a diagnostic listing is on stderr
  2  usage error
"""
import json
import sys

# The one android-aar asset a release publishes; see the module docstring for
# why this kind is matched by exact name instead of structurally.
ANDROID_AAR_FILENAME = "migo-android-java.aar"

# linux-sdk/windows-sdk map to (filename suffix, trailing "-"-separated
# segments). Adding a platform means adding a row here, not a second matching
# rule elsewhere. Note: their assets may be named migo-{linux,windows}-x86_64.tar.gz
# (without "sdk") so we accept both forms.
STRUCTURAL_KINDS = {
    "linux-sdk": lambda profile: (".tar.gz", ["linux", "x86_64"]),
    "windows-sdk": lambda profile: (".tar.gz", ["windows", "x86_64"]),
}
KINDS = {"android-aar", *STRUCTURAL_KINDS}


def matches_trailing(name, suffix, trailing):
    """True if `name` ends in `suffix` and its stem's final segments match.

    Strips the suffix and splits the rest on "-"; the final len(trailing)
    segments must equal `trailing` exactly.

    This is deliberately a structural check on trailing segments, not a
    substring search: a name like "migo-runtime-0.9.0-full-arm64-v8a.aar" (an
    artifact from an older, retired naming scheme) does not end in
    "-full-release" and correctly does not match, even though it contains
    "full" as a delimiter-bounded substring elsewhere in the name.
    """
    if not name.endswith(suffix):
        return False
    stem = name[: -len(suffix)]
    segments = stem.split("-")
    return len(segments) >= len(trailing) and segments[-len(trailing):] == trailing


def select(release, kind, profile):
    """Returns (matches, all_names) for a parsed release JSON object."""
    assets = release.get("assets", []) or []
    all_names = [a.get("name", "") for a in assets]
    if kind == "android-aar":
        matches = [a for a in assets if a.get("name", "") == ANDROID_AAR_FILENAME]
    else:
        suffix, trailing = STRUCTURAL_KINDS[kind](profile)
        matches = [
            a for a in assets if matches_trailing(a.get("name", ""), suffix, trailing)
        ]
    return matches, all_names


def main(argv):
    if len(argv) != 3:
        print(
            "usage: select-release-asset.py <kind> <profile> < release.json",
            file=sys.stderr,
        )
        print(f"  kinds: {', '.join(sorted(KINDS))}", file=sys.stderr)
        return 2
    kind, profile = argv[1], argv[2]
    if kind not in KINDS:
        print(
            f"ERROR: unknown artifact kind {kind!r} "
            f"(known: {', '.join(sorted(KINDS))})",
            file=sys.stderr,
        )
        return 2

    try:
        release = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"ERROR: release JSON is not valid JSON: {exc}", file=sys.stderr)
        return 1

    matches, all_names = select(release, kind, profile)

    if len(matches) == 1:
        print(matches[0].get("browser_download_url", ""))
        return 0

    if len(matches) == 0:
        print(
            f"ERROR: no asset in this release matches kind '{kind}' "
            f"(profile '{profile}').",
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
        f"ERROR: {len(matches)} assets in this release match kind "
        f"'{kind}' (profile '{profile}'); refusing to guess which one to use.",
        file=sys.stderr,
    )
    print("       candidates:", file=sys.stderr)
    for asset in matches:
        print(f"         {asset.get('name', '')}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
