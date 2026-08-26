# gbrain-patchkit

Run GBrain on a Mac without an Anthropic API key:

- **Codex CLI / ChatGPT Pro** handles non-tool reasoning (`think`, `auto_think`, Dream verdict).
- **DeepSeek API** handles chat, expansion, facts, subagents, and Dream patterns.

The supported profile is GBrain **`0.46.30.0`**. Patchkit refuses to apply its Codex overlay to another version rather than modifying unknown upstream code.

## What you normally do

On the target Mac, in the macOS **Terminal.app**:

```bash
cd ~/.gbrain-patchkit
git pull --ff-only
./bin/gbrain-patchkit configure codex-deepseek --prompt
```

Enter the DeepSeek key only when Terminal shows `Paste DeepSeek API key:`. It is hidden while typing and is saved in `~/.gbrain-patchkit/env.sh` with permissions `600`.

Then verify:

```bash
exec $SHELL -l
gbrain-patchkit doctor
```

Requirements: an installed/logged-in `codex` CLI, Bun, and GBrain `0.46.30.0`. Intel Macs are supported (`uname -m` should be `x86_64`).

## If you use an agent

Give the agent this instruction:

```text
Read AGENTS.md and INTEL_CODEX_DEEPSEEK_AGENT_RUNBOOK.md in ~/.gbrain-patchkit.
Inspect prerequisites and doctor output, but do not start a secret-input prompt in a background terminal.
Ask me to run the one Terminal command from the README when the DeepSeek key is needed.
After I confirm it completed, continue with doctor. Ask permission before any real model request.
```

Why one manual step? A secret must not be pasted into chat or an inaccessible agent-owned terminal. You only need to enter it once; the agent handles the checks and subsequent repair work.

## What `configure codex-deepseek` changes

It applies the Codex overlay and persists GBrain-native routing:

| Workload | Provider |
| --- | --- |
| expansion, chat, facts, drift, evals | `deepseek:deepseek-v4-flash` |
| subagents, Dream patterns, Dream synthesis | `deepseek:deepseek-v4-flash` + gateway loop |
| think, auto-think, Dream verdict/triage | `codex:gpt-5.6` via Codex CLI subscription |

The utility, reasoning, deep, and subagent tier fallbacks also resolve to
`deepseek:deepseek-v4-flash`, so unlisted GBrain features do not fall back to
Anthropic or a previously configured OpenRouter route.

It does not configure mail, calendar, image, or embedding providers. Vector retrieval needs a separately configured embedding provider; OpenAI `text-embedding-3-small` supports shortened dimensions such as 1280.

## Everyday commands

```bash
gbrain-patchkit doctor          # inspect setup and overlay state
gbrain-patchkit overlay-check   # check whether Codex overlay is applied
gbrain-patchkit upgrade         # upgrade GBrain and replay patchkit changes
gbrain-patchkit env             # edit the private runtime environment
```

For a new installation:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zzbyy/gbrain-patchkit/main/install.sh)"
```

## Safety

- Never paste `DEEPSEEK_API_KEY` into chat, git, or a command history shared with others.
- Codex deliberately does **not** run tool calls; DeepSeek owns tool-capable flows.
- Before a live Codex or DeepSeek smoke test, get user confirmation because it consumes subscription quota or API credits.
- For the exact agent repair sequence, read [INTEL_CODEX_DEEPSEEK_AGENT_RUNBOOK.md](INTEL_CODEX_DEEPSEEK_AGENT_RUNBOOK.md).

## License

MIT. See [LICENSE](LICENSE).
