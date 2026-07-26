#!/usr/bin/env bash
# Exercises scripts/lib/verify-attestation.py directly via stdin: the seam
# where attestation-vs-download matching lives, tested without a network
# dependency. The passing fixture is the real attestation published beside
# migo-full-release.aar, reproduced verbatim (not invented).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="$ROOT_DIR/scripts/lib/verify-attestation.py"

fail() { echo "FAIL: $1" >&2; exit 1; }

run() { python3 "$VERIFIER" "$1" "$2" "$3" <<<"$4"; }

REAL_FILE="migo-full-release.aar"
REAL_SIZE="35912726"
REAL_SHA256="ebdd7428b8a0a6b270949235527e47262f4a9b6d87ff6ce501c58db18aa23957"
WRONG_SHA256="$(printf '0%.0s' $(seq 1 64))"

# The real attestation from platforms/android/dist/migo-full-release.aar.attestation.json
# in the migo repo, reproduced verbatim.
REAL_ATTESTATION='{
  "schema": "migo-release-attestation/v1",
  "package_file": "migo-full-release.aar",
  "package_size_bytes": 35912726,
  "package_sha256": "ebdd7428b8a0a6b270949235527e47262f4a9b6d87ff6ce501c58db18aa23957",
  "package_index_file": "package-index.json",
  "package_index_sha256": "e4e276962aa08f4ddc28711477c97e8ad0bc47ba42c1c29b5ee9b3471deb15c7"
}'

# 1. The real attestation verifies against its own real values.
run "$REAL_FILE" "$REAL_SIZE" "$REAL_SHA256" "$REAL_ATTESTATION" \
  || fail "the real attestation should verify against its own real values"

# 2. Wrong package_file: the attestation belongs to a different artifact.
set +e
run "migo-slim-release.aar" "$REAL_SIZE" "$REAL_SHA256" "$REAL_ATTESTATION" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "mismatched package_file should fail"

# 3. Wrong size.
set +e
run "$REAL_FILE" "1" "$REAL_SHA256" "$REAL_ATTESTATION" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "mismatched size should fail"

# 4. Wrong digest.
set +e
run "$REAL_FILE" "$REAL_SIZE" "$WRONG_SHA256" "$REAL_ATTESTATION" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "mismatched sha256 should fail"

# 5. Unknown schema fails even though every other field matches: an unknown
#    schema means the fields below may not mean what we think.
BAD_SCHEMA='{
  "schema": "something-else/v1",
  "package_file": "migo-full-release.aar",
  "package_size_bytes": 35912726,
  "package_sha256": "ebdd7428b8a0a6b270949235527e47262f4a9b6d87ff6ce501c58db18aa23957"
}'
set +e
run "$REAL_FILE" "$REAL_SIZE" "$REAL_SHA256" "$BAD_SCHEMA" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "unrecognized schema should fail"

# 6. Malformed JSON fails.
set +e
run "$REAL_FILE" "$REAL_SIZE" "$REAL_SHA256" "not json" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "malformed JSON should fail"

# 7. A well-formed but unknown schema version must be refused, not admitted
#    because it happens to start with the same prefix as a known schema.
#    This is the whole point of the allowlist: a prefix test would let a
#    future migo-release-attestation/v2 -- same field names, possibly
#    different semantics -- pass silently. Everything else here (filename,
#    size, digest) is byte-identical to the passing real fixture, so a
#    green result on this case would mean the schema gate isn't gating.
UNKNOWN_VERSION='{
  "schema": "migo-release-attestation/v2",
  "package_file": "migo-full-release.aar",
  "package_size_bytes": 35912726,
  "package_sha256": "ebdd7428b8a0a6b270949235527e47262f4a9b6d87ff6ce501c58db18aa23957",
  "package_index_file": "package-index.json",
  "package_index_sha256": "e4e276962aa08f4ddc28711477c97e8ad0bc47ba42c1c29b5ee9b3471deb15c7"
}'
set +e
run "$REAL_FILE" "$REAL_SIZE" "$REAL_SHA256" "$UNKNOWN_VERSION" >/dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "an unknown schema version (v2) must not be accepted just because v1 is known"

echo "OK: verify-attestation contract holds (7 checks)"
