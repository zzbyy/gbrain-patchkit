#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCHKIT_BIN="$ROOT/bin/gbrain-patchkit"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gbrain-patchkit-known-conflicts.XXXXXX")"
REPO="$TMP_ROOT/gbrain"

mkdir -p "$REPO/src/commands" "$REPO/src/core" "$REPO/src/core/context" "$REPO/src" "$REPO/skills"
git -C "$TMP_ROOT" init -q gbrain
git -C "$REPO" config user.name "Patchkit Test"
git -C "$REPO" config user.email "patchkit-test@example.invalid"

cat > "$REPO/package.json" <<'JSON'
{"name": "gbrain"}
JSON
touch "$REPO/src/cli.ts"
touch "$REPO/skills/RESOLVER.md"

cat > "$REPO/src/commands/doctor.ts" <<'TS'
import { gbrainPath, loadConfig } from '../core/config.ts';
import { dirname, isAbsolute, join, resolve as resolvePath } from 'path';
import { fileURLToPath } from 'url';
import { existsSync, readFileSync, readdirSync, statSync } from 'fs';

export async function checkSubagentCapability(engine: any): Promise<any> {
  const { isAnthropicProvider } = await import('../core/model-config.ts');
  const cfg = loadConfig();
  const chatModel = cfg?.chat_model;
  if (chatModel && !isAnthropicProvider(chatModel) && !process.env.ANTHROPIC_API_KEY) {
    return { status: 'warn' };
  }
  return { status: 'ok' };
}
TS

cat > "$REPO/src/core/doctor-categories.ts" <<'TS'
export const META_CHECK_NAMES: ReadonlySet<string> = new Set([
  'schema_version',
  'slug_fallback_audit',
  'upgrade_errors',
]);
TS

cat > "$REPO/src/core/pglite-engine.ts" <<'TS'
export class PGLiteEngine {
  db: any;
  async getTags(slug: string, opts?: { sourceId?: string }): Promise<string[]> {
    const { rows } = await this.db.query(
      `SELECT tag FROM tags WHERE slug = $1 ORDER BY tag`,
      [slug]
    );
    return (rows as { tag: string }[]).map(r => r.tag);
  }
}
TS

cat > "$REPO/src/core/postgres-engine.ts" <<'TS'
export class PostgresEngine {
  sql: any;
  async getTags(slug: string, opts?: { sourceId?: string }): Promise<string[]> {
    const sql = this.sql;
    const rows = await sql`
      SELECT tag FROM tags WHERE slug = ${slug} ORDER BY tag
    `;
    return rows.map((r: any) => r.tag as string);
  }
}
TS

cat > "$REPO/src/core/pglite-lock.ts" <<'TS'
const LOCK_FILE = 'lock';

export interface LockHandle {
  lockDir: string;
  acquired: boolean;
}

export async function acquireLock(lockData: any, lockDir: string): Promise<LockHandle> {
  const lockPid = lockData.pid as number;
  if (!isProcessAlive(lockPid)) {
    cleanup(lockDir);
  } else {
    await wait();
  }
  return { lockDir, acquired: true };
}

function isProcessAlive(_pid: number): boolean { return true; }
function cleanup(_dir: string): void {}
function wait(): Promise<void> { return Promise.resolve(); }
TS

git -C "$REPO" add package.json src/cli.ts skills/RESOLVER.md src
git -C "$REPO" commit -q -m baseline

cat > "$REPO/src/commands/doctor.ts" <<'TS'
import { gbrainPath, loadConfig } from '../core/config.ts';
import { dirname, isAbsolute, join, resolve as resolvePath } from 'path';
import { fileURLToPath } from 'url';
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from 'fs';

function configuredLocalStorageRoot(): string | null {
  const storageCfg = loadConfig()?.storage;
  if (!storageCfg || typeof storageCfg !== 'object') return null;
  const localPath = (storageCfg as { localPath?: unknown }).localPath;
  if (typeof localPath !== 'string' || !localPath) return null;
  return realpathSync(localPath);
}

export async function checkSubagentCapability(engine: any): Promise<any> {
  const { isAnthropicProvider } = await import('../core/model-config.ts');
  const cfg = loadConfig();
  const chatModel = cfg?.chat_model;
  const useGatewayLoopRaw = await engine.getConfig('agent.use_gateway_loop').catch(() => null);
  const useGatewayLoop = useGatewayLoopRaw === 'true' || useGatewayLoopRaw === '1';
  if (chatModel && !isAnthropicProvider(chatModel) && !process.env.ANTHROPIC_API_KEY && !useGatewayLoop) {
    return { status: 'warn' };
  }
  return { status: 'ok' };
}
TS

cat > "$REPO/src/core/doctor-categories.ts" <<'TS'
export const META_CHECK_NAMES: ReadonlySet<string> = new Set([
  'schema_version',
  'slug_fallback_audit',
  'type_proliferation',
  'upgrade_errors',
]);
TS

cat > "$REPO/src/core/pglite-engine.ts" <<'TS'
export class PGLiteEngine {
  db: any;
  async getTags(slug: string, opts?: { sourceId?: string }): Promise<string[]> {
    const sourceId = opts?.sourceId ?? 'default';
    const { rows } = await this.db.query(
      `SELECT t.tag
       FROM tags t
       JOIN pages p ON p.id = t.page_id
       WHERE p.slug = $1 AND p.source_id = $2
       ORDER BY t.tag`,
      [slug, sourceId]
    );
    return (rows as { tag: string }[]).map(r => r.tag);
  }
}
TS

cat > "$REPO/src/core/postgres-engine.ts" <<'TS'
export class PostgresEngine {
  sql: any;
  async getTags(slug: string, opts?: { sourceId?: string }): Promise<string[]> {
    const sql = this.sql;
    const sourceId = opts?.sourceId ?? 'default';
    const rows = await sql`
      SELECT t.tag
      FROM tags t
      JOIN pages p ON p.id = t.page_id
      WHERE p.slug = ${slug} AND p.source_id = ${sourceId}
      ORDER BY t.tag
    `;
    return rows.map((r: any) => r.tag as string);
  }
}
TS

cat > "$REPO/src/core/pglite-lock.ts" <<'TS'
const LOCK_FILE = 'lock';

export interface LockHandle {
  lockDir: string;
  acquired: boolean;
}

export async function acquireLock(lockData: any, lockDir: string): Promise<LockHandle> {
  const lockPid = lockData.pid as number;
  if (!isProcessAlive(lockPid)) {
    cleanup(lockDir);
  } else {
    // Lock is held by a live process. Do not age this out.
    await wait();
  }
  return { lockDir, acquired: true };
}

function isProcessAlive(_pid: number): boolean { return true; }
function cleanup(_dir: string): void {}
function wait(): Promise<void> { return Promise.resolve(); }
TS

git -C "$REPO" stash push -q -m local-overlay src

cat > "$REPO/src/commands/doctor.ts" <<'TS'
import { gbrainPath, loadConfig } from '../core/config.ts';
import { reflexEnabled } from '../core/context/reflex.ts';
import { resolveSocketPath } from '../core/context/resolve-ipc.ts';
import { homedir } from 'os';
import { dirname, isAbsolute, join, resolve as resolvePath } from 'path';
import { fileURLToPath } from 'url';
import { existsSync, readFileSync, readdirSync, statSync } from 'fs';

export async function checkSubagentCapability(engine: any): Promise<any> {
  const { isAnthropicProvider } = await import('../core/model-config.ts');
  const cfg = loadConfig();
  const chatModel = cfg?.chat_model;
  const gatewayLoopRaw = await engine.getConfig('agent.use_gateway_loop').catch(() => null);
  const gatewayLoopEnabled = typeof gatewayLoopRaw === 'string'
    && ['true', '1', 'yes', 'on'].includes(gatewayLoopRaw.trim().toLowerCase());
  if (chatModel && !isAnthropicProvider(chatModel) && !process.env.ANTHROPIC_API_KEY && !gatewayLoopEnabled) {
    return { status: 'warn' };
  }
  return { status: 'ok' };
}
TS

cat > "$REPO/src/core/doctor-categories.ts" <<'TS'
export const META_CHECK_NAMES: ReadonlySet<string> = new Set([
  'schema_version',
  'slug_fallback_audit',
  'timeline_dedup_index',
  'upgrade_errors',
]);
TS

cat > "$REPO/src/core/pglite-engine.ts" <<'TS'
export class PGLiteEngine {
  db: any;
  async getTags(slug: string, opts?: { sourceId?: string; sourceIds?: string[] }): Promise<string[]> {
    const scope =
      opts?.sourceIds && opts.sourceIds.length > 0
        ? { sql: 'source_id = ANY($2::text[])', param: opts.sourceIds }
        : { sql: 'source_id = $2', param: opts?.sourceId ?? 'default' };
    const { rows } = await this.db.query(
      `SELECT DISTINCT tag FROM tags
       WHERE page_id IN (SELECT id FROM pages WHERE slug = $1 AND ${scope.sql})
       ORDER BY tag`,
      [slug, scope.param]
    );
    return (rows as { tag: string }[]).map(r => r.tag);
  }
}
TS

cat > "$REPO/src/core/postgres-engine.ts" <<'TS'
export class PostgresEngine {
  sql: any;
  async getTags(slug: string, opts?: { sourceId?: string; sourceIds?: string[] }): Promise<string[]> {
    const sql = this.sql;
    const scope =
      opts?.sourceIds && opts.sourceIds.length > 0
        ? sql`source_id = ANY(${opts.sourceIds}::text[])`
        : sql`source_id = ${opts?.sourceId ?? 'default'}`;
    const rows = await sql`
      SELECT DISTINCT tag FROM tags
      WHERE page_id IN (SELECT id FROM pages WHERE slug = ${slug} AND ${scope})
      ORDER BY tag
    `;
    return rows.map((r: any) => r.tag as string);
  }
}
TS

cat > "$REPO/src/core/pglite-lock.ts" <<'TS'
const LOCK_FILE = 'lock';

const HEARTBEAT_INTERVAL_MS = 30_000;

function stealGraceMs(): number {
  const env = parseInt(process.env.GBRAIN_PGLITE_LOCK_STEAL_GRACE_SECONDS ?? '', 10);
  return Number.isFinite(env) && env > 0 ? env * 1000 : 10 * 60 * 1000;
}

export interface LockHandle {
  lockDir: string;
  acquired: boolean;
}

export async function acquireLock(lockData: any, lockDir: string): Promise<LockHandle> {
  const lockPid = lockData.pid as number;
  const lockTime = lockData.acquired_at as number;
  const alive = isProcessAlive(lockPid);
  const lastRefresh = (lockData.refreshed_at as number | undefined) ?? lockTime;
  const sinceRefresh = Date.now() - lastRefresh;
  if (!alive) {
    cleanup(lockDir);
  } else if (sinceRefresh > stealGraceMs()) {
    cleanup(lockDir);
  } else {
    await wait();
  }
  return { lockDir, acquired: true };
}

function isProcessAlive(_pid: number): boolean { return true; }
function cleanup(_dir: string): void {}
function wait(): Promise<void> { return Promise.resolve(); }
TS

git -C "$REPO" add src
git -C "$REPO" commit -q -m upstream-upgrade

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
if rg -q '^(<<<<<<<|=======|>>>>>>>)' "$REPO/src"; then
  echo "conflict markers remain" >&2
  exit 1
fi

grep -q "realpathSync" "$REPO/src/commands/doctor.ts"
grep -q "reflexEnabled" "$REPO/src/commands/doctor.ts"
grep -q "gatewayLoopEnabled" "$REPO/src/commands/doctor.ts"
grep -q "'timeline_dedup_index'" "$REPO/src/core/doctor-categories.ts"
grep -q "'type_proliferation'" "$REPO/src/core/doctor-categories.ts"
grep -q "sourceIds" "$REPO/src/core/pglite-engine.ts"
grep -q "sourceIds" "$REPO/src/core/postgres-engine.ts"
grep -q "stealGraceMs" "$REPO/src/core/pglite-lock.ts"

echo "repair-upgrade known overlay conflicts: ok"
