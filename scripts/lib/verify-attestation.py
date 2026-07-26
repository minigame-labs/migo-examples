#!/usr/bin/env python3
"""Verifies a downloaded artifact against its release attestation.

Reads a migo release attestation JSON (as published beside each release AAR,
named <asset>.attestation.json) from stdin, and checks it against three
positional arguments: the expected asset filename, the actual downloaded
size in bytes, and the actual downloaded sha256 hex digest.

Migo's release pipeline (build-aar.sh) writes this file, not a bare
<asset>.sha256 -- looking for a ".sha256" file would fail closed against
every genuine release, for a reason that has nothing to do with the release
being bad. The attestation also gives a check a bare checksum cannot:
`package_file` lets this catch an attestation that verifies a *different*
artifact byte-for-byte, not just a corrupted one.

`package_index_file`/`package_index_sha256` describe the AAR's internal
contents (a manifest of what is packed inside it) and are the engine's
concern, not this resolver's; they are read but never checked here.

Exit codes:
  0  attestation is well-formed and matches on schema, filename, size, sha256
  1  attestation is malformed, has an unrecognized schema, or doesn't match
  2  usage error
"""
import json
import sys

SCHEMA_PREFIX = "migo-release-attestation/"


def verify(attestation, expected_filename, expected_size, expected_sha256):
    """Returns None if `attestation` (a parsed dict) verifies, else an error string.

    Checked in this order so the schema gate always runs first: an unknown
    schema means the fields below may not mean what we think, so nothing
    past it should be trusted even if it happens to line up.
    """
    schema = attestation.get("schema", "")
    if not schema.startswith(SCHEMA_PREFIX):
        return (
            f"unrecognized attestation schema '{schema}' "
            f"(expected a schema starting with '{SCHEMA_PREFIX}')"
        )

    package_file = attestation.get("package_file")
    if package_file != expected_filename:
        return (
            f"attestation is for '{package_file}', not the downloaded "
            f"asset '{expected_filename}'"
        )

    package_size = attestation.get("package_size_bytes")
    if package_size != expected_size:
        return (
            f"size mismatch: attestation says {package_size} bytes, "
            f"downloaded file is {expected_size} bytes"
        )

    package_sha256 = attestation.get("package_sha256")
    if package_sha256 != expected_sha256:
        return (
            f"sha256 mismatch: attestation says {package_sha256}, "
            f"downloaded file is {expected_sha256}"
        )

    return None


def main(argv):
    if len(argv) != 4:
        print(
            "usage: verify-attestation.py <expected-filename> "
            "<expected-size-bytes> <expected-sha256> < attestation.json",
            file=sys.stderr,
        )
        return 2
    expected_filename, expected_size_arg, expected_sha256 = argv[1], argv[2], argv[3]

    try:
        expected_size = int(expected_size_arg)
    except ValueError:
        print(
            f"ERROR: expected-size-bytes must be an integer, got '{expected_size_arg}'",
            file=sys.stderr,
        )
        return 2

    try:
        attestation = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"ERROR: attestation JSON is not valid JSON: {exc}", file=sys.stderr)
        return 1

    error = verify(attestation, expected_filename, expected_size, expected_sha256)
    if error is not None:
        print(f"ERROR: attestation check failed: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
