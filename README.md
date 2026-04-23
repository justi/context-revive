# context-revive

> Your side project died at 80%. Bring it back in one prompt.

Claude Code forgets your project halfway through long sessions.
Auto-compaction eats architectural context, old tokens fall out of
the window, the agent starts asking questions the README answered.

`context-revive` generates a dense, deterministic brief and
re-injects it into the session on a fixed cadence — the Anthropic
pattern called **structured note-taking**, wired through the
`UserPromptSubmit` hook.

One bash script. Zero runtime. No Python, no Node, no binary.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/justi/context-revive/main/install.sh | bash
```

Requires: `bash`, `git`, `jq` (only for `install-hook`).

## Quick start

```bash
cd your-project
revive init              # scaffold .revive/static.md
revive install-hook      # wire UserPromptSubmit into .claude/settings.json
revive show              # preview the brief
```

Every 5th prompt (or after 10 min / first call) Claude Code gets the
brief prepended to context — deterministic, <1500 chars, <100ms.

## Brief format

```
<revive refresh="N">
# STATIC  (rarely changes — edit by hand)
PURPOSE, INVARIANTS, GOTCHAS

# DYNAMIC (regenerated per refresh)
STATE    last 3 commits + active branch
TODO     3 newest items from plan.md / TODO.md
MODULES  up to 10 auto-detected entry points
</revive>
```

## Why a shell script?

- **Zero runtime** — bash is on every dev machine.
- **<100ms cold start** — hot-path friendly.
- **Transparent** — `cat $(which revive)` and read it all.
- **One file to audit** — no dependency tree.

## Why not a longer CLAUDE.md?

CLAUDE.md loads once at session start. Sixty prompts later it's
compacted. `context-revive` refreshes on cadence so the brief stays
in the recent window where the agent actually attends.

## Status

Pre-alpha. Weekend MVP.

## License

MIT
