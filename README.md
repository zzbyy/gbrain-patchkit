# gbrain-patchkit

Standalone companion tool for [gbrain](https://github.com/garrytan/gbrain) that lets you swap gbrain's hardcoded Anthropic model IDs for any Anthropic-compatible endpoint — MiniMax, a self-hosted [litellm](https://github.com/BerriAI/litellm) gateway, or anything else that speaks the Anthropic Messages API.

Set it up once. `~/gbrain` stays untouched, `git pull` works normally, and there's nothing to reapply after upgrades.

## Why this exists

gbrain hardcodes two model IDs in source:

- `src/core/search/expansion.ts` — Claude Haiku, for query expansion at search time
- `src/core/minions/handlers/subagent.ts` — Claude Sonnet, default for `gbrain agent run`

If you don't have an Anthropic key (MiniMax-only, litellm, Ollama, etc.), those code paths fail. `gbrain-patchkit` redirects them to whatever endpoint + models you pick by setting `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` and `GBRAIN_EXPANSION_MODEL` / `GBRAIN_SUBAGENT_MODEL` in a scoped env file, then loading a Bun preload that intercepts the Anthropic SDK in-process and swaps model IDs at call time.

The Anthropic SDK already reads `ANTHROPIC_BASE_URL` from env natively, so redirecting to MiniMax requires no source change. The preload handles the model-ID part. **Net result: zero modifications to `~/gbrain`.**

## Install (one line)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zzbyy/gbrain-patchkit/main/install.sh)"
```

The installer clones this repo into `~/.gbrain-patchkit/`, adds a PATH export + a `gbrain` shell wrapper to your `~/.zshrc` (or `~/.bashrc`), and launches an interactive onboarding wizard that asks you for:

1. **OpenAI API key** — for embeddings only. Create a [restricted key](https://platform.openai.com/api-keys) with just `Embeddings: Request` enabled. Required for vector search.
2. **MiniMax API key** (or any other Anthropic-compatible provider key) — for query expansion and `gbrain agent run`. Optional; skip it and search still works (just without the expansion recall boost).
3. **Anthropic-compatible base URL** — e.g. `https://api.minimaxi.chat/anthropic`. Verify the current endpoint in your provider's docs.
4. **Model names** — the IDs to substitute for Haiku (expansion) and Sonnet (subagent).

All four land in `~/.gbrain-patchkit/env.sh` with `600` perms. Nothing is sent anywhere.

## Prerequisites

- `bash`, `git`, `python3` (all ship with macOS)
- `gbrain` already installed somewhere on `PATH` (e.g. `bun install -g github:garrytan/gbrain`)
- Optionally `curl` — used only to smoke-test your OpenAI key during onboarding

## How the runtime override works

The installer adds a wrapper function around `gbrain` in your shell rc:

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

`env.sh` exports `GBRAIN_ENTRY` (the resolved path to `~/gbrain/src/cli.ts`), `GBRAIN_OVERRIDE_JS` (the preload), and `GBRAIN_SOURCE_DIR` (the gbrain repo root, used by the preload's module resolver). The wrapper invokes `bun --preload <override> <cli.ts>` directly: Bun runs the preload before any application code, and the preload monkey-patches `@anthropic-ai/sdk`'s `Messages.prototype.create` and `.stream` so outbound `claude-haiku-*` calls get routed to `GBRAIN_EXPANSION_MODEL` and `claude-sonnet-*` calls to `GBRAIN_SUBAGENT_MODEL`. Because matching is by model *family*, upstream version bumps (`claude-haiku-4-5-...` → `claude-haiku-5-...`) don't break anything — there are no version strings to chase.

(The wrapper bypasses the `bun link` shim and calls Bun directly because Bun has no env-var equivalent for `--preload` — `BUN_PRELOAD` is not a thing in Bun 1.3.x. The CLI flag is the only reliable hook point.)

The keys + model choices live in `env.sh`, scoped to a subshell so they don't leak into Claude Code, codex, or other Anthropic-SDK tools running in the same parent shell.

`~/gbrain` is never modified. `cd ~/gbrain && git pull origin master && bun install` runs without conflict. There's no "reapply after upgrade" step — the override engages on every `gbrain` invocation regardless of upstream version.

### Drift detection

If a future Anthropic SDK release reshapes its `Messages` resource so the preload's hook target moves, the runtime override silently no-ops and prints one stderr line at startup. `gbrain-patchkit doctor` runs an SDK shape smoke test (`bun -e "require('@anthropic-ai/sdk/resources/messages.js').Messages.prototype.create"`) and reports pass/fail loudly, so you find out fast.

### Legacy source-patch path (still available)

The pre-runtime-override mechanism — find/replace edits committed to `~/gbrain/src/...` — is still available for users who want to add custom source modifications the runtime override can't address (e.g. patching constants outside the SDK call path). Add entries to `~/.gbrain-patchkit/substitutions.json` and run `gbrain-patchkit apply`. The two original default substitutions (`GBRAIN_EXPANSION_MODEL` / `GBRAIN_SUBAGENT_MODEL`) ship with `enabled: false` and should be left disabled — the runtime override handles them.

## Commands

```
gbrain-patchkit onboard        interactive setup (keys, URL, models, env + hook + smoke test)
gbrain-patchkit migrate        switch existing source-patch installs to runtime override (idempotent)
gbrain-patchkit upgrade        stash → git pull ~/gbrain → bun install → pop → post-upgrade
gbrain-patchkit doctor         verify env + preload + SDK shape + patch state
gbrain-patchkit env            open env.sh in $EDITOR
gbrain-patchkit edit           open substitutions.json in $EDITOR (custom source patches)
gbrain-patchkit apply          apply every enabled substitution (legacy source-patch path)
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
gbrain-patchkit migrate    # revert any active source patches, wire BUN_PRELOAD into env.sh,
                           # smoke-test the SDK, optionally fix the cli.ts mode flip
exec $SHELL -l             # reload your shell so the new env.sh is sourced
gbrain-patchkit doctor     # verify everything green
```

After this, `cd ~/gbrain && git pull origin master && bun install` runs without conflict, and there is nothing to reapply after the pull.

## Files

```
~/.gbrain-patchkit/
├── bin/gbrain-patchkit          (tool, shipped in this repo)
├── anthropic-override.js        (Bun preload — runtime SDK override, shipped in this repo)
├── install.sh                   (installer, shipped in this repo)
├── README.md                    (this file)
├── substitutions.default.json   (shipped default substitutions, all disabled)
├── substitutions.json           (user's substitution config, seeded from default on install)
├── env.sh                       (user's keys + models + BUN_PRELOAD, 600 perms, sourced from shell rc)
└── apply.log                    (append-only audit log for source-patch operations)
```

`substitutions.json` and `env.sh` are user data — they aren't tracked by the repo and survive `gbrain-patchkit update`. `substitutions.default.json` is the shipped template; the installer seeds `substitutions.json` from it only if the user file doesn't already exist.

## Custom source patches (advanced)

The runtime override (`anthropic-override.js`) handles the two default model substitutions. If you need to modify gbrain source for something the runtime override can't reach — a non-SDK constant, a guard clause, an injected import — fall back to the legacy source-patch path: add an entry to `~/.gbrain-patchkit/substitutions.json` with `enabled: true`, then run `gbrain-patchkit apply`.

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

Caveat: source patches make the gbrain working tree dirty and `git pull` will abort until you `gbrain-patchkit revert`. The runtime override exists specifically to avoid this dance — prefer extending `anthropic-override.js` when feasible.

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

The ideal long-term fix is making gbrain itself read `GBRAIN_EXPANSION_MODEL` and `GBRAIN_SUBAGENT_MODEL` natively — a two-line change. If/when that lands upstream, the runtime override becomes redundant (it'll still run harmlessly, since the env var precedence will already match what the preload would have substituted). At that point you can either leave it in place or run `gbrain-patchkit uninstall` to drop the shell hook entirely.

## Known wart (upstream): cli.ts mode flip

Bun re-chmods `~/gbrain/src/cli.ts` from 644 → 755 on every `bun link`/`bun install` (it auto-marks files with shebangs executable). The runtime override doesn't care — Bun reads `cli.ts` via `fs`, not `exec`, so gbrain still runs even when the mode bit is "wrong." But the mode flip alone leaves the gbrain tree dirty enough to abort `git pull`.

Three ways to handle it:

1. **`gbrain-patchkit upgrade`** (recommended) — runs the full ritual: stash any dirt, `git pull`, `bun install`, pop the stash, run `gbrain post-upgrade`. You never touch `~/gbrain` yourself. Use this in place of the manual `cd ~/gbrain && git pull && bun install && gbrain post-upgrade` sequence.

2. **One-time index fix** — `gbrain-patchkit migrate` offers it: `git -C ~/gbrain update-index --chmod=+x src/cli.ts`. After that, future bun installs find the index already aligned and stop reporting it as modified. This is the only place patchkit touches `~/gbrain`, and only with consent.

3. **Manual stash dance** — `cd ~/gbrain && git stash && git pull && git stash pop` every time you want to upgrade. Identical to (1) but you run it yourself.

## License

MIT. See [LICENSE](LICENSE).
