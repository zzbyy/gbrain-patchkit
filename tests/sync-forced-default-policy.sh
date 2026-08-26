#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCHKIT_BIN="$ROOT/bin/gbrain-patchkit"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gbrain-patchkit-force-policy.XXXXXX")"
REPO="$TMP_ROOT/gbrain"
PATCHKIT_HOME="$TMP_ROOT/patchkit"

mkdir -p "$REPO/src" "$PATCHKIT_HOME"
printf '%s\n' '{"name": "gbrain"}' > "$REPO/package.json"
printf '%s\n' 'original' > "$REPO/src/example.txt"

printf '%s\n' \
  '{' \
  '  "substitutions": [{' \
  '    "name": "retired upstream patch",' \
  '    "enabled": false,' \
  '    "disabled_by": "upstream",' \
  '    "force_default_policy": true,' \
  '    "file": "src/example.txt",' \
  '    "marker": "PATCHED",' \
  '    "find": "original",' \
  '    "replace": "PATCHED"' \
  '  }]' \
  '}' > "$PATCHKIT_HOME/substitutions.default.json"

printf '%s\n' \
  '{' \
  '  "substitutions": [{' \
  '    "name": "retired upstream patch",' \
  '    "enabled": true,' \
  '    "file": "src/example.txt",' \
  '    "marker": "PATCHED",' \
  '    "find": "old form",' \
  '    "replace": "old patched form"' \
  '  }]' \
  '}' > "$PATCHKIT_HOME/substitutions.json"

GBRAIN_PATCHKIT_HOME="$PATCHKIT_HOME" GBRAIN_SOURCE_DIR="$REPO" "$PATCHKIT_BIN" check >/dev/null

python3 - "$PATCHKIT_HOME/substitutions.json" <<'PY'
import json, pathlib, sys
sub = json.loads(pathlib.Path(sys.argv[1]).read_text())["substitutions"][0]
assert sub["enabled"] is False
assert sub["disabled_by"] == "upstream"
assert sub["force_default_policy"] is True
assert sub["find"] == "original"
PY

grep -qx 'original' "$REPO/src/example.txt"
echo "forced default policy retires stale installed substitutions: ok"
