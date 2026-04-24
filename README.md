# context-revive

> Your side project died at 80%. Bring it back in one prompt.

Claude Code forgets your project halfway through long sessions.
Auto-compaction eats architectural context, old tokens fall out of
the window, the agent starts asking questions the README answered.

`context-revive` generates a dense, deterministic brief and
re-injects it into the session on a fixed cadence — the Anthropic
pattern called **structured note-taking**, wired through the
`UserPromptSubmit` hook.

One bash script. Zero runtime dependencies on the hot path — the
`refresh` hook calls only `bash` and `git`. No Python, no Node, no
compiled binary.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/justi/context-revive/main/install.sh | bash
```

Requires:

- **Hot path (every refresh):** `bash`, `git`. Nothing else.
- **One-off setup:** `jq` for `revive install-hook`; `gh` is optional
  for best-quality PURPOSE extraction during `revive init`. Both are
  used once, never from the hook.

## Quick start

```bash
cd your-project
revive init              # scaffold .revive/static.md (PURPOSE auto-detected)
revive suggest | pbcopy  # generate DIFFERENTIATORS / INVARIANTS / GOTCHAS — paste into current session
revive audit   | pbcopy  # second-pass gap audit — paste into FRESH session
revive install-hook      # wire UserPromptSubmit into .claude/settings.json
revive show              # preview the brief
```

Every 5th prompt (or after 10 min / first call) Claude Code gets the
brief prepended to context — deterministic, <100ms, <10k chars
(Claude Code hook limit).

### Filling PURPOSE / DIFFERENTIATORS / INVARIANTS / GOTCHAS with your agent

Two-pass flow — designed deliberately:

1. **`revive suggest`** — generation pass. Prints a project-tailored
   LLM prompt that lists your actual CLAUDE.md / ADRs / HOT_FILES
   and asks the agent to fill any still-placeholder sections
   end-to-end. Paste it into Claude Code / Cursor / Aider — the
   agent previews the output, then edits `.revive/static.md`
   for you.

2. **`revive audit`** — gap-audit pass, in a **fresh agent session**.
   Prints a separate prompt that re-reads the file + artefacts and
   scans against a 6-category checklist (toolchain specifics,
   skill-file discipline, workflow dichotomies, privacy/OpSec,
   cross-ADR process rules, convention collisions). Proposes
   additional bullets for anything the generation pass missed.

The two steps use separate LLM calls on purpose: a single session
that both generates and audits its own output suffers from context
saturation (tired attention by STEP 2) and self-critique sycophancy
(agents tend to rubber-stamp their own recent writes). A fresh
session — new Claude Code window, `/clear` in the current one, new
Cursor chat tab — catches gaps the first pass can't.

Research is blunt: *"Human curation yields ~4% performance gains;
auto-generation reduces success rates by 0.5–2%"* — so the agent
is explicitly told NOT to rewrite sections that already contain
real content. Re-runs are idempotent; audit only ever APPENDS.

### Reset / regenerate from scratch

If `.revive/static.md` drifted (old PURPOSE extracted before v0.1.2
chain, stale rules, accidentally-preserved marketing tagline), start
over cleanly:

```bash
cd your-project
rm -rf .revive           # drop old static.md + any other revive state
revive init              # fresh scaffold with current chain
revive suggest | pbcopy  # agent prompt for DIFFERENTIATORS/INVARIANTS/GOTCHAS
#   → paste into Claude Code / Cursor / Aider session
#   → agent writes the file end-to-end
revive audit   | pbcopy  # second-pass gap audit
#   → paste into a FRESH session (/clear, new tab, etc.)
#   → agent proposes additional bullets the first pass missed
revive show              # verify
```

Lighter alternative: `revive init --force` regenerates only PURPOSE
(from the current chain) and preserves any user-edited
DIFFERENTIATORS / INVARIANTS / GOTCHAS.

## Brief format

```
<revive refresh="N">
# STATIC  (rarely changes — human-curated via `revive suggest`)
PURPOSE          what + business goal + hard constraint (2-3 sentences)
DIFFERENTIATORS  alternatives → our choice / rationale
INVARIANTS       rules whose breakage causes non-obvious damage
GOTCHAS          landmines whose fix isn't obvious from code alone

# DYNAMIC (regenerated per refresh)
STATE      last 3 commits + active branch; fix/feat commits also
           surface the first paragraph of their body (PR description
           for squash-merge workflows)
TODO       first items from plan.md / TODO.md / ROADMAP.md
           (searches root + docs/)
HOT_FILES  top 5 files by commit-frequency (last 20 commits), each
           annotated with the last commit subject that touched it
COMMANDS   exact test/lint/build/dev/setup scripts (from package.json
           / Gemfile + bin/* / Makefile, or .revive/commands.md override)
</revive>
```

## Design — what goes in the brief, and why

2026 research on context engineering for coding agents converges on
one principle: **re-inject only what the agent can't re-derive from
code on its own.** We follow that evidence, section by section.

### What goes in (evidence-backed non-inferable facts)

- **PURPOSE** — a curated 1-liner. Extracted from a fallback chain:
  `gh repo view --json description` → `pyproject.toml` /
  `package.json` / `Cargo.toml` / `*.gemspec` / `composer.json`
  description → `CLAUDE.md` "What this project is" section →
  filtered README prose. First hit wins.
- **DIFFERENTIATORS**, **INVARIANTS**, **GOTCHAS** — user-curated
  (typically via `revive suggest`, reviewed before file write).
  Research is blunt: *"Human curation yields ~4% performance gains;
  auto-generation reduces success rates by 0.5–2%"* ([Augment Code,
  2026][augment]).
- **STATE** — current branch + last 3 commits. Pure `git` output,
  zero interpretation.
- **TODO** — first bullets from `plan.md` / `TODO.md` / `ROADMAP.md`.
  Again, whatever the repo already has.
- **HOT_FILES** — top 5 files by commit-frequency over the last 20
  commits, each annotated with the last commit subject that touched
  it. Framework-agnostic signal of "where work actually concentrates"
  (Rails `bin/kamal` / `bin/brakeman` scaffolding can't compete with
  files you keep reaching for).
- **COMMANDS** — exact invocations: `test:`, `lint:`, `build:`,
  `dev:`. Extracted from `package.json scripts` / `Makefile` /
  Rails `bin/*`, or overridden by `.revive/commands.md`. These are
  the canonical class of non-inferable facts an agent needs ([AGENTS.md
  guide, 2026][augment]).

### What we deliberately don't inject

- ❌ **Auto-generated architecture overview** — the Augment Code
  research on `AGENTS.md` is explicit: *"Directory trees cause stale
  structural references that mislead agents"*, and auto-generated
  overviews **reduce** agent success rate by 0.5–2% while increasing
  cost 20%+. If you want an architecture summary, write it by hand
  into `INVARIANTS` / `GOTCHAS`.
- ❌ **Directory tree / file listing** — same reasoning. The agent
  has `Glob` and `Read`. Any dump we inject goes stale the first
  time you move a file.
- ❌ **Dependency graph** — same class of stale-snapshot hazard.
- ❌ **Full file contents or patches** — blows any sane budget; the
  agent has `Read` for the files `HOT_FILES` points to.
- ❌ **LLM-summarized anything** in the hot path. Zero-LLM by
  design — the brief must be deterministic and <100ms so the hook
  never stalls a prompt.

### Substrate / projection separation

Current 2026 consensus ([Zylos, 2026][zylos]) splits context into
a stable cacheable prefix and a fresh per-turn suffix. Our brief
maps cleanly: `STATIC` is the cacheable prefix (one human-curated
file per project), `DYNAMIC` is the fresh suffix regenerated every
emit.

### Refresh cadence

Emit every 5 prompts OR >10 minutes gap OR first call of the
session. This is complementary to Anthropic's AutoCompact (which
fires at context-window ceiling): we address **context rot** —
the agent forgetting as tokens drift out of attention — which
happens long before AutoCompact triggers.

[augment]: https://www.augmentcode.com/guides/how-to-build-agents-md
[zylos]: https://zylos.ai/research/2026-03-17-dynamic-context-assembly-projection-llm-agent-runtimes

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
