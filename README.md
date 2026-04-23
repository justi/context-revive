# context-revive

> Your side project died at 80%. Bring it back in one prompt.

Claude Code forgets your project halfway through long sessions. Auto-compaction
eats architectural context, old tokens fall out of the window, the agent starts
asking questions the README already answered.

`context-revive` generates a dense, deterministic brief about your project and
re-injects it into the session on a fixed cadence — the official Anthropic
pattern called **structured note-taking**, wired through the `UserPromptSubmit`
hook.

One shell script. Zero runtime. No Python, no Node, no compiled binary.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/justi/context-revive/main/install.sh | bash
```

Or manually:

```bash
curl -fsSL https://raw.githubusercontent.com/justi/context-revive/main/bin/revive \
  -o ~/.local/bin/revive && chmod +x ~/.local/bin/revive
```

Requires: `bash` (macOS/Linux/WSL), `git`, `jq` (for `install-hook` only).

## Quick start

```bash
cd your-project
revive init              # generate .revive/static.md (PURPOSE, INVARIANTS, GOTCHAS)
revive install-hook      # wire UserPromptSubmit hook into .claude/settings.json
revive show              # preview the brief that will be injected
```

From now on, every 5th prompt in Claude Code gets the current brief prepended
to context — deterministic, zero LLM calls, <1500 chars, <10ms.

## What goes in the brief

```
<revive refresh="N">
# STATIC  (rarely changes — edit by hand)
PURPOSE: one-paragraph product hook
INVARIANTS: top-5 architectural rules from ADR / CLAUDE.md
GOTCHAS: landmines you keep stepping on

# DYNAMIC (regenerated per refresh — deterministic)
STATE: last 3 commits + active branch
TODO: 3 newest items from plan.md / TODO.md
MODULES: up to 10 auto-detected entry points
</revive>
```

## Why not just a long CLAUDE.md?

CLAUDE.md is loaded once at session start. Sixty prompts later it's compacted,
paraphrased, or lost. `context-revive` refreshes on cadence so the brief is
always in the recent window where the agent actually attends to it.

## Why a shell script?

- **Zero runtime** — bash is already on every dev machine.
- **<10ms cold start** — hook runs on every Nth prompt; Python/Node startup
  would add perceptible latency on the hot path.
- **Transparent** — `cat $(which revive)` and read the whole thing.
- **One file to audit** — no dependency tree.

## Status

Pre-alpha. Weekend MVP in progress.

## License

MIT
