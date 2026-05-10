# gbrain-patchkit

Standalone companion tool for [gbrain](https://github.com/garrytan/gbrain) that lets you run the Anthropic-shaped parts of gbrain through cheaper models and keep those patches alive across upgrades.

It uses two mechanisms:

1. A Bun preload that redirects direct `@anthropic-ai/sdk` Messages calls to your Anthropic-compatible model endpoint, for MiniMax-style providers.
2. Small idempotent source patches that add missing OpenAI-compatible expansion touchpoints to gbrain recipes, for DeepSeek and LiteLLM/Kimi/MiniMax proxy setups.

## Why this exists

Current gbrain has two different LLM surfaces:

- Provider-gateway calls such as query expansion. These can use GBrain recipes like `deepseek:*` or `litellm:*` once the patchkit recipe patches are applied.
- Direct Anthropic Messages calls in `think`, dream/cycle significance/synthesis, and Minions subagents. These still construct an Anthropic SDK client, so patchkit redirects them at runtime.

If you don't have an Anthropic key, set a provider key in the scoped patchkit env as `ANTHROPIC_API_KEY` and point `ANTHROPIC_BASE_URL` at an Anthropic-compatible endpoint. The preload swaps Claude-family model IDs at call time using `GBRAIN_ANTHROPIC_MODEL_MAP`, `GBRAIN_SUBAGENT_MODEL`, and `GBRAIN_THINK_MODEL`.

For query expansion through non-Anthropic providers, patchkit adds source-level recipe capabilities and reapplies them after every upgrade.

## Install (one line)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zzbyy/gbrain-patchkit/main/install.sh)"
```

The installer clones this repo into `~/.gbrain-patchkit/`, adds a PATH export + a `gbrain` shell wrapper to your `~/.zshrc` (or `~/.bashrc`), and launches an interactive onboarding wizard that asks you for:

1. **OpenAI API key** — for embeddings only. Create a [restricted key](https://platform.openai.com/api-keys) with just `Embeddings: Request` enabled. Required for vector search.
2. **MiniMax API key** (or any other Anthropic-compatible provider key) — for query expansion and `gbrain agent run`. Optional; skip it and search still works (just without the expansion recall boost).
3. **Anthropic-compatible base URL** — e.g. `https://api.minimaxi.chat/anthropic`. Verify the current endpoint in your provider's docs.
4. **Model names** — the IDs to substitute for Claude-family direct Anthropic SDK calls.

All four land in `~/.gbrain-patchkit/env.sh` with `600` perms. Nothing is sent anywhere.

## Prerequisites

- `bash`, `git`, `python3` (all ship with macOS)
- `gbrain` already installed somewhere on `PATH` (e.g. `bun install -g github:garrytan/gbrain`)
- Optionally `curl` — used only to smoke-test your OpenAI key during onboarding

## How the runtime override works

The installer adds two wrappers around `gbrain`:

1. a shell function in your shell rc for interactive shells, and
2. a `~/.local/bin/gbrain` command shim for non-interactive callers that do not source shell rc files, such as agents, cron jobs, launchd tasks, and scripts.

The interactive shell wrapper looks like this:

```bash
gbrain() {
  local rc
  (
    [ -f "$HOME/.gbrain-patchkit/env.sh" ] && . "$HOME/.gbrain-patchkit/env.sh"
    if [ -n "${GBRAIN_ENTRY:-}" ] && [ -f "$GBRAIN_ENTRY" ] \
       && [ -n "${GBRAIN_OVERRIDE_JS:-}" ] && [ -f "$GBRAIN_OVERRIDE_JS" ] \
       && command -v bun >/dev/null 2>&1; then
      exec bun --preload "$GBRAIN_OVERRIDE_JS" "$GBRAIN_ENTRY" "$@"
    fi
    exec command gbrain "$@"
  )
  rc=$?
  return $rc
}
```

`env.sh` exports `GBRAIN_ENTRY` (the resolved path to `~/gbrain/src/cli.ts`), `GBRAIN_OVERRIDE_JS` (the preload), and `GBRAIN_SOURCE_DIR` (the gbrain repo root, used by the preload's module resolver). The wrapper invokes `bun --preload <override> <cli.ts>` directly: Bun runs the preload before any application code, and the preload monkey-patches `@anthropic-ai/sdk`'s `Messages.prototype.create` and `.stream`.

The model replacement is family-based and optionally exact-model based:

```bash
export GBRAIN_ANTHROPIC_MODEL_MAP='{"haiku":"MiniMax-M2.7","sonnet":"MiniMax-M2.7","opus":"MiniMax-M2.7"}'
```

Legacy fallbacks still work: `GBRAIN_EXPANSION_MODEL` for Haiku-shaped calls, `GBRAIN_SUBAGENT_MODEL` for Sonnet-shaped calls, and `GBRAIN_THINK_MODEL` for Opus-shaped calls.

(The wrapper bypasses the `bun link` shim and calls Bun directly because Bun has no env-var equivalent for `--preload` — `BUN_PRELOAD` is not a thing in Bun 1.3.x. The CLI flag is the only reliable hook point.)

The non-interactive command shim performs the same flow from an executable: it sources `~/.gbrain-patchkit/env.sh` in its own process, invokes `bun --preload <override> <cli.ts>` when runtime override metadata is present, and otherwise falls back to the native `gbrain` binary. This fixes callers that see `/Users/zz/.bun/bin/gbrain` directly because they never loaded `.zshrc`/`.bashrc`.

The keys + model choices live in `env.sh`, scoped to the wrapper process so they don't leak into Claude Code, codex, or other Anthropic-SDK tools running in the same parent shell.

The runtime override does not modify `~/gbrain`. The enabled recipe patches do modify `~/gbrain/src/core/ai/recipes/*.ts`, but only through marker-based idempotent substitutions. After a successful `gbrain upgrade`, the wrapper runs `gbrain-patchkit post-upgrade` to refresh pointers and reapply enabled patches.

For cheap query expansion without using your OpenAI key beyond embeddings:

```bash
# DeepSeek direct
export DEEPSEEK_API_KEY=...
export GBRAIN_EXPANSION_MODEL=deepseek:deepseek-chat

# Or through a local LiteLLM proxy for MiniMax/Kimi/etc.
export LITELLM_BASE_URL=http://localhost:4000
export GBRAIN_EXPANSION_MODEL=litellm:minimax-m2.7
```

Put those exports in `~/.gbrain-patchkit/env.sh` so they are scoped to `gbrain`.

### Drift detection

If a future Anthropic SDK release reshapes its `Messages` resource so the preload's hook target moves, the runtime override silently no-ops and prints one stderr line at startup. `gbrain-patchkit doctor` runs an SDK shape smoke test (`bun -e "require('@anthropic-ai/sdk/resources/messages.js').Messages.prototype.create"`) and reports pass/fail loudly, so you find out fast.

### Legacy source-patch path (still available)

The source-patch mechanism is still available for code the runtime override cannot reach. The two original `GBRAIN_EXPANSION_MODEL` / `GBRAIN_SUBAGENT_MODEL` substitutions stay disabled because the preload handles direct Anthropic SDK calls. The enabled defaults patch provider recipes for cheap query expansion.

## Commands

```
gbrain-patchkit onboard        interactive setup (keys, URL, models, env + hook + smoke test)
gbrain-patchkit migrate        switch existing source-patch installs to runtime override (idempotent)
gbrain-patchkit post-upgrade   refresh runtime pointers + reapply enabled source patches
gbrain-patchkit upgrade        stash → git pull ~/gbrain → bun install → pop → post-upgrade
gbrain-patchkit doctor         verify env + preload + SDK shape + patch state
gbrain-patchkit env            open env.sh in $EDITOR
gbrain-patchkit edit           open substitutions.json in $EDITOR (custom source patches)
gbrain-patchkit apply          apply every enabled substitution
gbrain-patchkit check          show status of every substitution
gbrain-patchkit revert         undo every substitution
gbrain-patchkit locate         print the resolved gbrain source directory
gbrain-patchkit update         git pull inside the install dir
gbrain-patchkit uninstall      remove the shell hook (leaves files for you to rm)
```

### Upgrading from the source-patch version

If you installed an older patchkit that wrote to `~/gbrain/src/`:

```bash
gbrain-patchkit update     # pull the new patchkit (brings anthropic-override.js)
gbrain-patchkit migrate    # revert obsolete source patches, wire runtime override pointers,
                           # smoke-test the SDK, optionally fix the cli.ts mode flip
exec $SHELL -l             # reload your shell so the new env.sh is sourced
gbrain-patchkit doctor     # verify everything green
```

After this, use `gbrain-patchkit upgrade` or `gbrain upgrade` through the patchkit wrapper so enabled recipe patches are reapplied after the pull.

## Files

```
~/.gbrain-patchkit/
├── bin/gbrain-patchkit          (tool, shipped in this repo)
├── bin/gbrain                   (non-interactive command shim, symlinked to ~/.local/bin/gbrain)
├── anthropic-override.js        (Bun preload — runtime SDK override, shipped in this repo)
├── install.sh                   (installer, shipped in this repo)
├── README.md                    (this file)
├── substitutions.default.json   (shipped default substitutions)
├── substitutions.json           (user's substitution config, seeded from default on install)
├── env.sh                       (user's keys + models + runtime pointers, 600 perms, sourced from shell rc)
└── apply.log                    (append-only audit log for source-patch operations)
```

`substitutions.json` and `env.sh` are user data — they aren't tracked by the repo and survive `gbrain-patchkit update`. `substitutions.default.json` is the shipped template; the installer seeds `substitutions.json` from it only if the user file doesn't already exist.

## Custom source patches (advanced)

The runtime override (`anthropic-override.js`) handles direct Anthropic SDK model substitutions. Source patches handle provider recipe gaps and anything the runtime override cannot reach. Add an entry to `~/.gbrain-patchkit/substitutions.json` with `enabled: true`, then run `gbrain-patchkit apply`.

```json
{
  "name": "make embedding dim configurable",
  "enabled": true,
  "file": "src/core/embedding.ts",
  "marker": "GBRAIN_EMBED_DIM_OVERRIDE",
  "find": "const DIMENSIONS = 1536;",
  "replace": "const DIMENSIONS = /*GBRAIN_EMBED_DIM_OVERRIDE*/ Number(process.env.GBRAIN_EMBED_DIM ?? 1536);"
}
```

Three rules:

1. **`find`** must appear exactly **once** in the target file (ambiguous matches are refused).
2. **`marker`** must appear in `replace` but **not** in `find` — that's how re-runs detect already-patched state.
3. **`file`** is a repo-relative path under the resolved gbrain source dir.

Caveat: source patches make the gbrain working tree dirty. Use `gbrain-patchkit upgrade` or the patchkit `gbrain upgrade` wrapper so the tool stashes, upgrades, and reapplies patches in a controlled order.

## Scope & safety

- **Local only.** Nothing in this tool phones home. The only outbound request is an optional OpenAI embedding smoke-test during `onboard`, using the key you just pasted.
- **Idempotent.** `apply` is safe to run any number of times. `revert` undoes only the substitutions the tool made.
- **Atomic file writes.** Every patched file is written via a temp-file + rename.
- **Secret hygiene.** `env.sh` is created with `umask 077` and `chmod 600`. It's sourced from your shell rc, not exported in scripts that Git tracks.
- **No sudo required.** Everything lives under `~/.gbrain-patchkit/`.

## Uninstall

```bash
gbrain-patchkit uninstall    # remove shell hook block from rc file
rm -rf ~/.gbrain-patchkit    # remove tool + config + env
```

Revert patches before uninstalling if you want the gbrain source left clean:

```bash
gbrain-patchkit revert
gbrain-patchkit uninstall
rm -rf ~/.gbrain-patchkit
```

## Upstream status

The ideal long-term fix is upstream provider-neutral coverage for all think/dream/minion paths. When gbrain stops constructing direct Anthropic SDK clients for those paths and exposes MiniMax/Kimi/DeepSeek recipes natively, this patchkit can shrink back to upgrade hygiene or be uninstalled.

## Known wart (upstream): cli.ts mode flip

Bun re-chmods `~/gbrain/src/cli.ts` from 644 → 755 on every `bun link`/`bun install` (it auto-marks files with shebangs executable). The runtime override doesn't care — Bun reads `cli.ts` via `fs`, not `exec`, so gbrain still runs even when the mode bit is "wrong." But the mode flip alone leaves the gbrain tree dirty enough to abort `git pull`.

Three ways to handle it:

1. **`gbrain-patchkit upgrade`** (recommended) — runs the full ritual: stash any dirt, `git pull`, `bun install`, pop the stash, run `gbrain post-upgrade`. You never touch `~/gbrain` yourself. Use this in place of the manual `cd ~/gbrain && git pull && bun install && gbrain post-upgrade` sequence.

2. **One-time index fix** — `gbrain-patchkit migrate` offers it: `git -C ~/gbrain update-index --chmod=+x src/cli.ts`. After that, future bun installs find the index already aligned and stop reporting it as modified. This is the only place patchkit touches `~/gbrain`, and only with consent.

3. **Manual stash dance** — `cd ~/gbrain && git stash && git pull && git stash pop` every time you want to upgrade. Identical to (1) but you run it yourself.

## License

MIT. See [LICENSE](LICENSE).
