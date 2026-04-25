#!/usr/bin/env bash
#
# gbrain-patchkit installer.
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zzbyy/gbrain-patchkit/main/install.sh)"
#
# What this does:
#   1. Clones (or updates) the gbrain-patchkit repo into ~/.gbrain-patchkit
#   2. Seeds substitutions.json from the bundled default if not already present
#   3. Ensures the tool is on PATH (adds to your shell rc)
#   4. Runs the interactive onboarding wizard — prompts for keys, URL, models
#   5. Applies the patches to your gbrain install
#
# Re-run-safe: won't overwrite an existing env.sh or substitutions.json.

set -euo pipefail

REPO_URL="${PATCHKIT_REPO_URL:-https://github.com/zzbyy/gbrain-patchkit.git}"
BRANCH="${PATCHKIT_BRANCH:-main}"
HOME_DIR="${GBRAIN_PATCHKIT_HOME:-$HOME/.gbrain-patchkit}"

say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

# Prereqs
for cmd in git bash python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "missing required command: $cmd"; exit 1
  fi
done

if [ ! -d "$HOME_DIR/.git" ]; then
  if [ -d "$HOME_DIR" ] && [ "$(ls -A "$HOME_DIR" 2>/dev/null)" ]; then
    say "[install] $HOME_DIR already exists but is not a git clone."
    say "[install] Backing up to $HOME_DIR.bak.$$ and cloning fresh."
    mv "$HOME_DIR" "$HOME_DIR.bak.$$"
  fi
  say "[install] cloning $REPO_URL -> $HOME_DIR"
  git clone --quiet --depth=1 --branch "$BRANCH" "$REPO_URL" "$HOME_DIR"
else
  say "[install] existing clone detected at $HOME_DIR — pulling latest"
  git -C "$HOME_DIR" fetch --quiet origin "$BRANCH"
  git -C "$HOME_DIR" reset --quiet --hard "origin/$BRANCH"
fi

chmod +x "$HOME_DIR/bin/gbrain-patchkit"

# Seed substitutions.json if user doesn't have one yet (preserves their edits)
if [ ! -f "$HOME_DIR/substitutions.json" ] && [ -f "$HOME_DIR/substitutions.default.json" ]; then
  cp "$HOME_DIR/substitutions.default.json" "$HOME_DIR/substitutions.json"
  say "[install] seeded substitutions.json from default"
fi

# Sanity check: anthropic-override.js must be present after clone/pull. The
# Bun preload referenced from env.sh points at this file; without it the
# runtime override silently no-ops.
if [ ! -f "$HOME_DIR/anthropic-override.js" ]; then
  err "[install] WARNING: $HOME_DIR/anthropic-override.js missing after clone/pull."
  err "[install]   Runtime override will not engage. Re-run the installer or"
  err "[install]   git -C $HOME_DIR pull to refresh."
fi

# Existing-install path: if env.sh is already there but doesn't yet export
# GBRAIN_ENTRY (the runtime-override marker), run migrate to wire it in
# (idempotent + revert any active source patches). Fresh installs go through
# onboard.
if [ -f "$HOME_DIR/env.sh" ] && ! grep -qE '^[[:space:]]*export[[:space:]]+GBRAIN_ENTRY=' "$HOME_DIR/env.sh" 2>/dev/null; then
  say ""
  say "[install] existing install detected without runtime-override config — running migrate"
  exec "$HOME_DIR/bin/gbrain-patchkit" migrate
fi

# Hand off to the onboard wizard (interactive)
say ""
exec "$HOME_DIR/bin/gbrain-patchkit" onboard
