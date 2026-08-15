#!/usr/bin/env python3
"""Selects a GitHub release asset for one artifact kind.

Reads a "get a release by tag" JSON response (as returned by
https://api.github.com/repos/<repo>/releases/tags/<tag>) from stdin, and
prints the `browser_download_url` of the single asset whose filename ends,
structurally, in the trailing segments that kind is defined by:

  android-aar   ".aar"     ending in ["android"]
  linux-sdk     ".tar.gz"  ending, structurally, in ["linux", <arch>]
  windows-sdk   ".tar.gz"  ending, structurally, in ["windows", <arch>]
  ohos-sdk      ".tar.gz"  ending, structurally, in ["ohos", <arch>]

e.g. "migo-0.9.1-android.aar" and "migo-0.9.1-capi-linux-x86_64.tar.gz".

This exists so resolve-migo-artifact.sh never has to guess an asset filename
by string concatenation: everything before the trailing profile/build-type
segments (product name, version) is deliberately unconstrained -- that's the
point of discovering the asset instead of guessing its whole name.

There is deliberately no ABI and no profile parameter for android-aar. Migo
publishes exactly one AAR, named migo-<version>-android.aar: it is multi-ABI
(Gradle picks the right .so per device at build time, and an integrator prunes
with abiFilters), and the product profile is an internal build axis a consumer
cannot choose. So "android" is the whole distinguishing tail. The other three
kinds are the opposite: one tarball per (platform, arch), so arch is exactly
what their trailing segments carry -- ohos-sdk always shipped this way (no fat
package across arm64/x86_64; see build-ohos-sdk.sh), and linux-sdk/windows-sdk
joined it once their release jobs started publishing an arm64 tarball
alongside x86_64.

The previous tail was [<profile>, "release"], matching migo-full-release.aar.
That was Gradle's internal <profile><buildType> task name reaching consumers,
and migo stopped publishing it -- so keying on it here would break at the next
tag. Note the local-build path in resolve-migo-artifact.sh is unaffected:
non-publishable AAR variants keep their descriptive names, so
migo-<profile>-debug.aar is still what a local debug build produces.

IMPORTANT -- what this selector deliberately does NOT establish: matching
the profile/build-type tail does not prove the asset is a Migo artifact at
all. An asset named "something-full-release.aar" attached to the same
tagged release would structurally match here. That is accepted on purpose:
constraining the product-name prefix too would walk this back toward the
filename guessing this design exists to escape. Identity -- "is this really
the artifact it claims to be" -- is established downstream, by the release
attestation (verify-attestation.py), whose `package_file` must equal the
asset's own name. Do not "tighten" this rule into a hardcoded filename, and
do not treat a match from this script alone as proof of what it returned.

Exit codes:
  0  exactly one match; its download URL is on stdout
  1  no match, or more than one match; a diagnostic listing is on stderr
  2  usage error
"""
import json
import sys

# Each kind maps to (filename suffix, trailing "-"-separated segments). Adding a
# platform means adding a row here, not a second matching rule elsewhere.
# `profile` is accepted and ignored by every kind: only the full profile is
# published, so it is not a selector dimension. `arch` is likewise accepted and
# ignored by android-aar (one multi-ABI AAR), but is the whole point for the
# other three: each publishes one tarball per (platform, arch).
STRUCTURAL_KINDS = {
    "android-aar": lambda profile, arch: (".aar", ["android"]),
    "linux-sdk": lambda profile, arch: (".tar.gz", ["linux", arch]),
    "windows-sdk": lambda profile, arch: (".tar.gz", ["windows", arch]),
    "ohos-sdk": lambda profile, arch: (".tar.gz", ["ohos", arch]),
}
KINDS = set(STRUCTURAL_KINDS)


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


def select(release, kind, profile, arch):
    """Returns (matches, all_names) for a parsed release JSON object."""
    assets = release.get("assets", []) or []
    all_names = [a.get("name", "") for a in assets]
    suffix, trailing = STRUCTURAL_KINDS[kind](profile, arch)
    matches = [
        a for a in assets if matches_trailing(a.get("name", ""), suffix, trailing)
    ]
    return matches, all_names


def main(argv):
    if len(argv) != 4:
        print(
            "usage: select-release-asset.py <kind> <profile> <arch> < release.json",
            file=sys.stderr,
        )
        print("  <arch> is ignored except by linux-sdk/windows-sdk/ohos-sdk", file=sys.stderr)
        print(f"  kinds: {', '.join(sorted(KINDS))}", file=sys.stderr)
        return 2
    kind, profile, arch = argv[1], argv[2], argv[3]
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

    matches, all_names = select(release, kind, profile, arch)

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
