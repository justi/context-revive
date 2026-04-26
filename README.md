# context-revive

> Your side project died at 80%. Bring it back in one prompt.

**Re-inject a dense, deterministic project brief into Claude Code every few
prompts, before context rot degrades the agent.** You edit `.revive/static.md`
once (or let an LLM draft it from your ADRs); the brief auto-refreshes on a
cadence, wired through the `UserPromptSubmit` hook.

One bash script, zero runtime on the hot path. Works with any agent via paste
(`revive show | pbcopy`); Claude Code gets first-class hook integration.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/justi/context-revive/main/install.sh | bash
```

Requires `bash` + `git`. Optional: `jq` (for `install-hook`), `gh` (for
best-quality PURPOSE auto-detection).

## Do I need this?

Use this if you keep hitting the same failure in Claude Code: 30 prompts in,
the agent forgets an ADR, re-suggests an approach you already rejected, or
asks questions `CLAUDE.md` already answered. You probably don't need it if
your sessions are short (<15 prompts), CLAUDE.md stays under 1k tokens, or
you already restart sessions frequently.

Not a replacement for `CLAUDE.md`, Cursor Rules, or `AGENTS.md` — those load
once at session start and get summarized away by AutoCompact. This keeps
your curated facts *fresh in the recent attention window*, complementary to
them.

## Example

After `revive init` + `revive suggest` on a repo with a handful of ADRs and
a detailed `CLAUDE.md`, Claude Code's `UserPromptSubmit` hook receives a
block like this on every 5th prompt (generic illustration — your content
and numbers will differ):

```
<revive refresh="7">
# STATIC  (from .revive/static.md — human-curated, stable across refreshes)
PURPOSE: Background-job scheduler for small Go services. Success metric is
zero surprise job failures after a deploy — goal: replace ops-managed cron
with code-defined schedules that survive rollouts. Constraint: job state
lives in the app's own Postgres; no new infrastructure.

DIFFERENTIATORS:
  - Traditional cron → schedules defined in code, survive deploys
  - Managed SaaS schedulers → zero new infrastructure; reuses app Postgres
  - Temporal / DAG workflow engines → single-step jobs only; keep it small

INVARIANTS:
  - Every schedule change ships with a migration; never edit rows in prod.
  - Jobs must be idempotent — retries on deploy-overlap are expected.
  - Worker binary must not grow past 30 MB (embedded-device deploy target).

GOTCHAS:
  - `make test` runs integration against a real Postgres — set TEST_DATABASE_URL.
  - `bin/deploy` always runs `schedule:apply` last; reordering breaks overlap detection.

# DYNAMIC  (regenerated per refresh from git + fs)
STATE: branch=main
  9e8a1f2 fix(scheduler): handle DST transitions in cron parser
      ↪ Cron parser was skipping jobs during spring-forward. Added unit tests for …
  c4b2d30 feat: add schedule:diff command for deploy previews

HOT_FILES: (last 20 commits, last change shown)
  12× internal/scheduler/parser.go  ↪ "fix(scheduler): handle DST transitions in cron parser"
   8× cmd/worker/main.go            ↪ "feat: add schedule:diff command for deploy previews"
   5× internal/db/schema.sql        ↪ "chore: add index on next_run_at"
</revive>
```

Ask this Claude Code *"what's the success metric for this project?"* — the
agent answers *"zero surprise job failures after a deploy"* straight from
the brief, not by re-reading files. 30 prompts in, 100 prompts in, the
answer stays.

## Quick start

```bash
cd your-project
revive init              # scaffold .revive/static.md; PURPOSE auto-detected, 3 sections left as placeholders
revive suggest | pbcopy  # paste into active agent — agent rewrites PURPOSE/DIFFERENTIATORS/INVARIANTS/GOTCHAS
revive audit   | pbcopy  # paste into a FRESH session — agent proposes bullets the first pass missed
revive install-hook      # wire UserPromptSubmit hook into .claude/settings.json
revive show              # preview the assembled brief (forced emit, ignores cadence)
```

The two-pass flow (`suggest` then `audit` in a fresh session) is deliberate:
a single session that both generates and audits its own output suffers from
context saturation and self-critique sycophancy. Fresh context finds gaps
the generation pass can't. `suggest` rewrites placeholder sections;
`audit` only APPENDS bullets to existing sections after your approval.

## Most useful next

Everything below is optional — the quick start gives you a working hook.

- **[What the source file looks like](#what-revivestaticmd-looks-like)** —
  four sections, flat text, 2–5 KB typical.
- **[How often the brief is injected](#how-often-the-brief-is-injected)** —
  cadence rules, env vars for tuning (`REVIVE_REFRESH_EVERY`,
  `REVIVE_REFRESH_TIME_GAP`).
- **[Token cost](#token-cost-in-practice)** — measured ~2–3k tokens per
  emit, ~1.5% of Opus 4.7 1M context across a 30-prompt session.
- **[Reset / regenerate from scratch](#reset--regenerate-from-scratch)** —
  `rm -rf .revive && revive init && revive suggest | pbcopy` when
  `.revive/static.md` has drifted.
- **[Upgrade to a new release](#upgrade-to-a-new-version)** — re-run
  `install.sh`. Per-project state preserved.

## Reference

### What `.revive/static.md` looks like

Four flat sections. Immediately after `revive init`, the file has
`PURPOSE` filled (auto-detected — see the chain in Design notes) and
three placeholder sections waiting for your edits:

```
PURPOSE: <auto-detected from gh / manifest / CLAUDE.md / README>
DIFFERENTIATORS:
  - (what sets this project apart; edit this file)
INVARIANTS:
  - (top-5 architectural rules; edit this file)
GOTCHAS:
  - (landmines you keep stepping on; edit this file)
```

`PURPOSE` is **one physical line in the file** — no `\n` in the middle,
even when it holds 2–3 sentences and wraps visually in your editor
(up to 400 characters). The three other sections are bullet lists
under a section header.

After `revive suggest` + `revive audit` (or a hand edit), the file
looks like:

```
PURPOSE: Background-job scheduler for small Go services. Success metric is zero surprise job failures after a deploy — goal: replace ops-managed cron with code-defined schedules that survive rollouts. Constraint: job state lives in the app's own Postgres; no new infrastructure.
DIFFERENTIATORS:
  - Traditional cron → schedules defined in code, survive deploys
  - Managed SaaS schedulers → zero new infrastructure; reuses app Postgres
  - Temporal / DAG workflow engines → single-step jobs only; keep it small
INVARIANTS:
  - Every schedule change ships with a migration; never edit rows in prod.
  - Jobs must be idempotent — retries on deploy-overlap are expected.
  - Worker binary must not grow past 30 MB (embedded-device deploy target).
GOTCHAS:
  - `make test` runs integration against a real Postgres — set TEST_DATABASE_URL.
  - `bin/deploy` always runs `schedule:apply` last; reordering breaks overlap detection.
```

The file is checked in. `revive show` assembles the brief around it on each
refresh. Placeholder-only sections (still saying *"(edit this file)"*) are
suppressed from the emitted brief — no noise injected to the agent.

### How often the brief is injected

Emits when ANY of these is true:

1. **First prompt of the session** (counter = 1).
2. **Every 5th prompt after that**, via `REVIVE_REFRESH_EVERY` (default `5`).
3. **Gap of >10 minutes** since the last emit, via `REVIVE_REFRESH_TIME_GAP`
   (default `600` seconds).

Prompts between emits see nothing from revive — silent skip, zero cost.
Tune in your shell:

```bash
export REVIVE_REFRESH_EVERY=3        # every 3rd prompt
export REVIVE_REFRESH_TIME_GAP=300   # 5-minute gap threshold
```

### Token cost in practice

Measured on a rich-architecture project (Python + Streamlit + 19 ADRs,
`.revive/static.md` ≈ 4 KB with 12 INVARIANTS, 8 GOTCHAS):

| Scope | Tokens | % of Opus 4.7 1M |
|---|---|---|
| Brief per emit | ~2–3k | ~0.25% |
| 30-prompt session (6 emits) | ~15k | ~1.5% |
| Claude Code hook hard cap | 10k chars per emit | — |

English-only repos land closer to ~1.5k per emit; Polish/mixed with unicode
glyphs runs higher. Measure your own by running `/context` before and after
a prompt that triggers the hook — the delta in `Messages` is the emit cost.

### Reset / regenerate from scratch

If `.revive/static.md` drifted (old extractor, stale rules, marketing-tagline
PURPOSE slipped in):

```bash
cd your-project
rm -rf .revive
revive init
revive suggest | pbcopy          # paste → agent rewrites the file end-to-end
revive audit   | pbcopy          # paste into FRESH session → agent fills gaps
revive show                      # verify
```

Lighter alternative: `revive init --force` regenerates only `PURPOSE` and
preserves user-edited `DIFFERENTIATORS` / `INVARIANTS` / `GOTCHAS`.

### Upgrade to a new version

```bash
curl -fsSL https://raw.githubusercontent.com/justi/context-revive/main/install.sh | bash
revive version
```

Re-writes `~/.local/bin/revive`. Per-project `.revive/static.md` files and
Claude Code hook settings are not touched. Release notes flag when a
version adds a new section and you may want `revive init --force` to
regenerate scaffolding.

## Design notes

### What goes in (evidence-backed non-inferable facts)

- **PURPOSE** — one physical line, ≤400 chars, typically 2–3 sentences
  covering what the project is, its business goal, and the one hard
  constraint that shapes design decisions. Auto-detected via a chain:
  `gh repo view --json description` → manifest `description`
  (pyproject, package.json, Cargo, gemspec, composer) → `CLAUDE.md`
  first paragraph → filtered README prose. First hit wins.
- **DIFFERENTIATORS, INVARIANTS, GOTCHAS** — human-curated (via `suggest` +
  `audit`, user-reviewed). Research: *"Human curation yields ~4%
  performance gains; auto-generation reduces success rates by 0.5–2%"*
  ([Augment Code, 2026][augment]).
- **STATE** — `git` branch + last 3 commits (subject only for
  subject-only commits; subject plus the first paragraph of the
  body, truncated to ~100 chars, for commits that carry a body).
  Squash-merge bodies typically hold the PR description, so this
  surfaces PR context for free without a `gh` API call.
- **HOT_FILES** — top 5 files by commit-frequency over the last 20 commits,
  each annotated with the last commit subject.
- **COMMANDS** — exact test / lint / build / dev / setup
  invocations. Source priority: `.revive/commands.md` override →
  Rails `bin/*` (if `Gemfile` or `*.gemspec` present) →
  `package.json` `scripts` → `Makefile` targets → Rails `bin/*`
  fallback. Whole section is suppressed if no source matches.

### What we deliberately don't inject

Auto-generated architecture overview, directory tree, dependency graph,
full file contents, LLM-summarized anything on the hot path. Evidence:
*"Directory trees cause stale structural references that mislead agents"*,
and auto-generated summaries reduce agent success rate by 0.5–2% while
increasing cost 20%+ ([Augment Code, 2026][augment]). If you want an
architecture summary in the brief, write it by hand into `INVARIANTS`.

### Complementary to AutoCompact

Anthropic's AutoCompact fires at the context-window ceiling — it
summarises the conversation to make room. revive addresses a different
failure: **context rot**, where the agent forgets as tokens drift out of
attention long before AutoCompact triggers. Cadence-based re-injection
keeps key facts in the recent window ([Zylos, 2026][zylos] splits context
into stable prefix + fresh suffix — our STATIC/DYNAMIC split maps cleanly).

### Why a shell script?

Zero runtime. `<100ms` cold start. Transparent — `cat $(which revive)`.
One file to audit, no dependency tree. The point of this repo is that it
works on any dev machine without installing a language toolchain.

[augment]: https://www.augmentcode.com/guides/how-to-build-agents-md
[zylos]: https://zylos.ai/research/2026-03-17-dynamic-context-assembly-projection-llm-agent-runtimes

## Status

Pre-alpha. Weekend MVP in active dogfooding. **v0.1.18** — README rewrite
(action-first), CI on every PR (shellcheck + 111 bats tests); see
[Releases](https://github.com/justi/context-revive/releases) for history.

## License

MIT
