#!/usr/bin/env bash
# Content in this repository must not call capabilities on a namespace that does
# not carry them. The forbidden set is parsed out of the migo runtime source
# rather than repeated here, so names added upstream are covered without editing
# this file.
#
# This gate reads MIGO_NAMESPACE_REF (default: master), which is deliberately
# NOT migo-version.txt. migo-version.txt names a runtime *artifact release*;
# this is a *source-level* contract about which capabilities the `wx` object
# carries. A content file calling a capability that is absent from `wx` is
# wrong at every runtime version, so this gate tracks the engine source
# directly instead of following the artifact pin (which today does not even
# resolve to an existing tag -- see resolve-migo-artifact.sh).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${MIGO_NAMESPACE_REF:-master}"
SOURCE_URL="https://raw.githubusercontent.com/minigame-labs/migo/$REF/engine/crates/runtime-v8/src/97_wx_namespace.js"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! curl -fsSL "$SOURCE_URL" -o "$TMP/97_wx_namespace.js"; then
  # Failing closed is the point: a skipped gate is how this class of bug
  # survives, since the symptom is a black screen with every host callback green.
  echo "ERROR: could not fetch the wx namespace source for ref '$REF'" >&2
  echo "       from $SOURCE_URL" >&2
  exit 1
fi

# Content JS lives under games/**; android-java/ holds no game content (it is
# the host app + build config), so it is not part of this scan.
python3 - "$ROOT_DIR/games" "$TMP/97_wx_namespace.js" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys

scan_root = pathlib.Path(sys.argv[1]).resolve()
text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

block = re.search(r"const _NON_WX = new Set\(\[(.*?)\]\);", text, re.S)
if block is None:
    print("ERROR: could not find the _NON_WX set in the fetched namespace source", file=sys.stderr)
    sys.exit(1)

forbidden = re.findall(r'"([^"]+)"', block.group(1))
if not forbidden:
    print("ERROR: the _NON_WX set parsed empty; the gate would pass vacuously", file=sys.stderr)
    sys.exit(1)

errors: list[str] = []
scanned = 0
if scan_root.is_dir():
    candidates = sorted(scan_root.rglob("*.js"))
else:
    candidates = []

for source_path in candidates:
    parts = source_path.parts
    if "build" in parts or ".git" in parts or "node_modules" in parts:
        continue
    scanned += 1
    source = source_path.read_text(encoding="utf-8")
    for name in forbidden:
        if re.search(r"\bwx\." + re.escape(name) + r"\b", source):
            errors.append(
                f"{source_path.relative_to(scan_root.parent)} calls wx.{name}, but {name} is "
                f"only exposed on `migo` (browser content reaches it through the "
                f"adapter as navigator.{name})"
            )

if scanned == 0:
    print("ERROR: no content JS found to scan; the gate would pass vacuously", file=sys.stderr)
    sys.exit(1)

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print(f"OK: {scanned} content sources use no wx-namespaced capability that wx does not carry")
PY
