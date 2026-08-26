# Intel Mac: GBrain Codex + DeepSeek setup runbook

Use this runbook when repairing or setting up GBrain on the user's Intel MacBook Pro. The user does not use an Anthropic API key, does not need mail/calendar integrations, and does not need image features.

## Safety and scope

- Do not modify GBrain source manually. Use `gbrain-patchkit` only.
- Do not print, log, commit, or put `DEEPSEEK_API_KEY` in a command line visible to the conversation.
- The patchkit stores that key only in `~/.gbrain-patchkit/env.sh`, mode `600`.
- This overlay is deliberately pinned to GBrain `0.46.30.0`. If the installed version differs, stop before applying it and report the version; do not force the patch.
- Codex is intentionally non-tool-only. DeepSeek must remain the provider for subagents and Dream patterns.

## Procedure

1. Update patchkit and inspect its state:

   ```bash
   cd ~/.gbrain-patchkit
   git pull --ff-only
   git log -1 --oneline
   gbrain-patchkit doctor
   ```

2. Check prerequisites without changing configuration:

   ```bash
   uname -m
   bun --version
   codex --version
   gbrain --version
   ```

   Intel is expected to report `x86_64`. Bun and Codex CLI must both be installed; Codex CLI must already be logged in to the user's ChatGPT Pro account.

3. Confirm the GBrain version is exactly `0.46.30.0`. If not, stop and explain that patchkit needs an overlay refresh for that release.

4. Do **not** start `--prompt` in an agent-owned background terminal: the user may have no way to focus its hidden stdin. Instead, show the user this exact command and wait for them to run it in the macOS Terminal app themselves:

   ```bash
   cd ~/.gbrain-patchkit
   ./bin/gbrain-patchkit configure codex-deepseek --prompt
   ```

   The user enters the key only at that Terminal prompt and reports completion. The agent may then continue with:

   ```bash
   exec $SHELL -l
   gbrain-patchkit doctor
   ```

   The command installs/refreshes the patchkit shell hook, applies the Codex overlay, saves the DeepSeek key privately, and persists native GBrain routes:

   - DeepSeek `deepseek-v4-flash`: expansion, chat, facts, drift, evals, subagents, Dream patterns, Dream synthesis.
   - Codex `gpt-5.6`: think, auto-think, and Dream verdict/triage.
   - `agent.use_gateway_loop=true`.

5. Review doctor output. Configure OpenAI `text-embedding-3-small` separately for vector indexing/search. Its API supports shortened dimensions, including 1280, which preserves an existing 1280-wide vector schema. Do not configure ZeroEntropy, image, or mail/calendar integrations for this setup.

6. Before issuing any live inference request, ask the user for consent because it consumes Codex subscription quota or DeepSeek API credits. With consent, smoke-test one Codex think call and one DeepSeek-backed operation, then report the exact result.

## Expected outcome

With the stated exclusions, GBrain's text/memory, retrieval (once embeddings are configured), expansion, chat, facts, subagent, Dream patterns, and non-tool reasoning paths are routed without an Anthropic API key. Do not claim full health until doctor and the two approved live smoke tests pass on the Intel machine.
