#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCHKIT_BIN="$ROOT/bin/gbrain-patchkit"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gbrain-patchkit-overlay-snapshot.XXXXXX")"
REPO="$TMP_ROOT/gbrain"
PATCHKIT_HOME="$TMP_ROOT/patchkit"
PATCH="$PATCHKIT_HOME/patches/local-overlay.patch"

mkdir -p "$REPO/src" "$REPO/test" "$REPO/.codegraph"
git -C "$TMP_ROOT" init -q gbrain
git -C "$REPO" config user.name "Patchkit Test"
git -C "$REPO" config user.email "patchkit-test@example.invalid"

cat > "$REPO/package.json" <<'JSON'
{"name": "gbrain"}
JSON
cat > "$REPO/src/cli.ts" <<'TS'
console.log('gbrain');
TS
cat > "$REPO/src/existing.ts" <<'TS'
export const existing = 1;
TS
git -C "$REPO" add package.json src/cli.ts src/existing.ts
git -C "$REPO" commit -q -m baseline

cat > "$REPO/src/existing.ts" <<'TS'
export const existing = 2;
TS
cat > "$REPO/src/new-overlay.ts" <<'TS'
export const overlay = true;
TS
cat > "$REPO/.codegraph/.gitignore" <<'TXT'
*
TXT
cat > "$REPO/2026-05-29T10-22-44.767Z-openclaw-backup.tar.gz" <<'TXT'
not really a tarball
TXT

GBRAIN_PATCHKIT_HOME="$PATCHKIT_HOME" GBRAIN_SOURCE_DIR="$REPO" "$PATCHKIT_BIN" overlay-snapshot

test -s "$PATCH"
grep -q "src/existing.ts" "$PATCH"
grep -q "src/new-overlay.ts" "$PATCH"
if grep -q ".codegraph\\|openclaw-backup\\|2026-05-29" "$PATCH"; then
  echo "overlay patch included untracked artifacts" >&2
  exit 1
fi

echo "overlay-snapshot skips untracked artifacts: ok"
