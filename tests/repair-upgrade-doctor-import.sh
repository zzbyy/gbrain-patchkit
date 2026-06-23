#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCHKIT_BIN="$ROOT/bin/gbrain-patchkit"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gbrain-patchkit-doctor-import.XXXXXX")"
REPO="$TMP_ROOT/gbrain"

mkdir -p "$REPO/src/commands" "$REPO/src" "$REPO/skills"
git -C "$TMP_ROOT" init -q gbrain
git -C "$REPO" config user.name "Patchkit Test"
git -C "$REPO" config user.email "patchkit-test@example.invalid"

cat > "$REPO/package.json" <<'JSON'
{"name": "gbrain"}
JSON
touch "$REPO/src/cli.ts"
touch "$REPO/skills/RESOLVER.md"
cat > "$REPO/src/commands/doctor.ts" <<'TS'
import type { BrainEngine } from '../core/engine.ts';
import { categorizeCheck, type CheckCategory } from '../core/doctor-categories.ts';
import type { DbUrlSource } from '../core/config.ts';
import { gbrainPath } from '../core/config.ts';
import { dirname, isAbsolute, join, resolve as resolvePath } from 'path';
import { fileURLToPath } from 'url';
import { existsSync, readFileSync, readdirSync, statSync } from 'fs';

export interface DoctorReport {
  checks: Check[];
}

export interface Check {
  name: string;
  category?: CheckCategory;
}

export async function buildChecks(_engine: BrainEngine, _dbSource?: DbUrlSource): Promise<Check[]> {
  return [];
}
TS
git -C "$REPO" add package.json src/cli.ts skills/RESOLVER.md src/commands/doctor.ts
git -C "$REPO" commit -q -m baseline

cat > "$REPO/src/commands/doctor.ts" <<'TS'
import type { BrainEngine } from '../core/engine.ts';
import { categorizeCheck, type CheckCategory } from '../core/doctor-categories.ts';
import type { DbUrlSource } from '../core/config.ts';
import { gbrainPath, loadConfig } from '../core/config.ts';
import { dirname, isAbsolute, join, resolve as resolvePath } from 'path';
import { fileURLToPath } from 'url';
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from 'fs';

export interface DoctorReport {
  checks: Check[];
}

export interface Check {
  name: string;
  category?: CheckCategory;
}

export async function buildChecks(_engine: BrainEngine, _dbSource?: DbUrlSource): Promise<Check[]> {
  return [];
}
TS
git -C "$REPO" stash push -q -m local-doctor-import src/commands/doctor.ts

cat > "$REPO/src/commands/doctor.ts" <<'TS'
import type { BrainEngine } from '../core/engine.ts';
import { categorizeCheck, type CheckCategory } from '../core/doctor-categories.ts';
import { rankIssues, type RankedIssue } from '../core/doctor-cause-rank.ts';
import type { DbUrlSource } from '../core/config.ts';
import { gbrainPath } from '../core/config.ts';
import { dirname, isAbsolute, join, resolve as resolvePath } from 'path';
import { fileURLToPath } from 'url';
import { existsSync, readFileSync, readdirSync, statSync } from 'fs';
import {
  extractEntityRefs,
  isGlobalBasenameEnabled,
  buildBasenameIndex,
  queryBasenameIndex,
} from '../core/link-extraction.ts';
import { isSourceUnchangedSinceSync } from '../core/git-head.ts';
// v0.41.32.0: remote staleness reads the stored newest_content_at column via
// this pure comparator (no git subprocess on the HTTP MCP doctor path).
import { lagFromContentMs } from '../core/source-health.ts';
import { CHUNKER_VERSION } from '../core/chunkers/code.ts';
import { LINK_EXTRACTOR_VERSION_TS } from '../core/link-extraction.ts';
import { isUndefinedColumnError } from '../core/utils.ts';
// issue #1777: hidden_by_search_policy - count chunked pages withheld from
// default search by the hard-exclude prefix policy. Reuses the canonical
// exclude resolver + LIKE escaper + visibility clause so the doctor count can't
// drift from what search actually filters.
import { resolveHardExcludes, DEFAULT_HARD_EXCLUDES } from '../core/search/source-boost.ts';
import { escapeLikePattern, buildVisibilityClause } from '../core/search/sql-ranking.ts';

export interface DoctorReport {
  checks: Check[];
}

export interface Check {
  name: string;
  category?: CheckCategory;
}

export async function buildChecks(_engine: BrainEngine, _dbSource?: DbUrlSource): Promise<Check[]> {
  return [];
}
TS
git -C "$REPO" add src/commands/doctor.ts
git -C "$REPO" commit -q -m upstream-doctor-imports

if git -C "$REPO" stash pop -q; then
  echo "expected stash-pop conflict, got clean pop" >&2
  exit 1
fi

GBRAIN_PATCHKIT_HOME="$ROOT" GBRAIN_SOURCE_DIR="$REPO" "$PATCHKIT_BIN" repair-upgrade

if [ -n "$(git -C "$REPO" diff --name-only --diff-filter=U)" ]; then
  echo "unmerged paths remain" >&2
  git -C "$REPO" diff --name-only --diff-filter=U >&2
  exit 1
fi
if grep -qE '^(<<<<<<<|=======|>>>>>>>)' "$REPO/src/commands/doctor.ts"; then
  echo "conflict markers remain" >&2
  exit 1
fi

grep -q "import { gbrainPath, loadConfig } from '../core/config.ts';" "$REPO/src/commands/doctor.ts"
grep -q "import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from 'fs';" "$REPO/src/commands/doctor.ts"
grep -q "import { rankIssues, type RankedIssue } from '../core/doctor-cause-rank.ts';" "$REPO/src/commands/doctor.ts"
grep -q "import { escapeLikePattern, buildVisibilityClause } from '../core/search/sql-ranking.ts';" "$REPO/src/commands/doctor.ts"

echo "repair-upgrade doctor import conflict: ok"
