# gbrain-patchkit

Standalone companion tool for [gbrain](https://github.com/garrytan/gbrain) that lets you swap gbrain's hardcoded Anthropic model IDs for any Anthropic-compatible endpoint — MiniMax, a self-hosted [litellm](https://github.com/BerriAI/litellm) gateway, or anything else that speaks the Anthropic Messages API.

Patches auto-reapply after every `gbrain upgrade` so you set it up once and forget about it.

## Why this exists

gbrain hardcodes two model IDs in source:

- `src/core/search/expansion.ts` — Claude Haiku, for query expansion at search time
- `src/core/minions/handlers/subagent.ts` — Claude Sonnet, default for `gbrain agent run`

If you don't have an Anthropic key (MiniMax-only, litellm, Ollama, etc.), those code paths fail. `gbrain-patchkit` rewrites both lines to be env-driven (`GBRAIN_EXPANSION_MODEL`, `GBRAIN_SUBAGENT_MODEL`), stores your keys + model choices in `~/.gbrain-patchkit/env.sh`, and re-applies the patches automatically after every `gbrain upgrade`.

The Anthropic SDK already reads `ANTHROPIC_BASE_URL` from env natively, so redirecting to MiniMax requires no source change — only the model-ID override does.

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

## How the auto-reapply works

The installer adds a wrapper function around `gbrain` in your shell rc:

```bash
gbrain() {
  command gbrain "$@"
  local rc=$?
  if [ "${1-}" = "upgrade" ] && [ "$rc" -eq 0 ]; then
    command gbrain-patchkit apply --quiet || true
  fi
  return $rc
}
```

After a successful `gbrain upgrade`, patches reapply in-place. If the upstream gbrain release changes the hardcoded string the patches target (e.g. bumps Haiku to a new version), the tool detects drift and exits non-zero with a loud `DRIFT` warning — rather than silently mis-patching. You'd then run `gbrain-patchkit edit` and update the `find` string in `substitutions.json`.

## Commands

```
gbrain-patchkit onboard        interactive setup (keys, URL, models, patch, verify)
gbrain-patchkit apply          apply every enabled substitution (idempotent)
gbrain-patchkit check          show status of every substitution
gbrain-patchkit revert         undo every substitution
gbrain-patchkit doctor         verify env + patch state
gbrain-patchkit edit           open substitutions.json in $EDITOR
gbrain-patchkit env            open env.sh in $EDITOR
gbrain-patchkit locate         print the resolved gbrain source directory
gbrain-patchkit update         git pull inside the install dir
gbrain-patchkit uninstall      remove the shell hook (leaves files for you to rm)
```

## Files

```
~/.gbrain-patchkit/
├── bin/gbrain-patchkit          (tool, shipped in this repo)
├── install.sh                   (installer, shipped in this repo)
├── README.md                    (this file)
├── substitutions.default.json   (shipped default patches)
├── substitutions.json           (user's patch config, seeded from default on install)
├── env.sh                       (user's keys + models, 600 perms, sourced from shell rc)
└── apply.log                    (append-only audit log)
```

`substitutions.json` and `env.sh` are user data — they aren't tracked by the repo and survive `gbrain-patchkit update`. `substitutions.default.json` is the shipped template; the installer seeds `substitutions.json` from it only if the user file doesn't already exist.

## Adding your own substitutions

Open `~/.gbrain-patchkit/substitutions.json` (or `gbrain-patchkit edit`) and append to the array:

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

Run `gbrain-patchkit apply` to test. Run `gbrain-patchkit revert` to roll back.

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

The ideal long-term fix is making gbrain itself read `GBRAIN_EXPANSION_MODEL` and `GBRAIN_SUBAGENT_MODEL` natively — a two-line change. If/when that lands upstream, `gbrain-patchkit check` will show `drifted` or `patched` (depending on whether upstream keeps the marker), and you can simply disable the substitution in `substitutions.json` or uninstall the tool.

## License

MIT. See [LICENSE](LICENSE).
