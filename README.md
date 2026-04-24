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

After `revive init` + `revive suggest` on a real repo (armillary, 19 ADRs),
Claude Code's `UserPromptSubmit` hook receives this on every 5th prompt:

```
<revive refresh="7">
# STATIC  (from .revive/static.md — human-curated, stable across refreshes)
PURPOSE: Local-first memory layer for solo devs carrying 50-200 git repos.
Success metric is DORMANT→ACTIVE transitions (ADR 0025), not MRR —
deliberately open-source, SQLite-only, no cloud.

DIFFERENTIATORS:
  - Pure activity ranking tools → ranks for revival value, not recency (ADR 0008)
  - Embeddings / semantic retrieval → ripgrep-only Steal v1, 40-line windows (ADR 0027)

INVARIANTS:
  - No migrations: bump PRAGMA user_version → drop + rebuild (ADR 0004). Never ALTER TABLE.
  - Services never `import streamlit`; must be importable + testable without it (ADR 0001 rules 2, 8)
  - Classification heuristics require panel review (Pieter/Marc/Arvid/Harry) BEFORE code.

GOTCHAS:
  - CI runs `ruff format --check`; local `ruff check .` passes while CI fails — run BOTH.
  - `~/Projects_new/` is auto-generated; v2/v3/v4 patterns there are NOT user behavior.

# DYNAMIC  (regenerated per refresh from git + fs)
STATE: branch=main
  a3c09e6 feat: implement ADR 0027 Steal — cross-repo ranked code retrieval
      ↪ Ripgrep-only v1 per panel review: 40-line windows, two ranking signals…
  e4fe8d4 refactor: split 5 oversized modules under 400-line target (#32)

HOT_FILES: (last 20 commits, last change shown)
  11× README.md       ↪ "docs: add docs/mcp.md — MCP runtime reference"
   3× cli.py          ↪ "refactor: split 5 oversized modules under 400-line target"
   3× detail.py       ↪ "refactor: split 5 oversized modules under 400-line target"
</revive>
```

Ask this Claude Code: *"What's the success metric for this project?"* — the
agent answers *"DORMANT→ACTIVE transitions (ADR 0025), not MRR"* straight
from the brief, not by re-reading files. 30 prompts in, 100 prompts in, the
answer stays.

## Quick start

```bash
cd your-project
revive init              # scaffold .revive/static.md (PURPOSE auto-detected)
revive suggest | pbcopy  # paste into active agent — fills DIFFERENTIATORS/INVARIANTS/GOTCHAS
revive audit   | pbcopy  # paste into FRESH session — second-pass gap audit
revive install-hook      # wire UserPromptSubmit into .claude/settings.json
revive show              # preview the brief
```

The two-pass flow (`suggest` then `audit` in a fresh session) is deliberate:
a single session that both generates and audits its own output suffers from
context saturation and self-critique sycophancy. Fresh context finds gaps
the generation pass can't.

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

Four flat sections you edit directly (or via `suggest` + `audit`):

```
PURPOSE: <2-3 sentence summary — what + business goal + hard constraint>
DIFFERENTIATORS:
  - <alternative> → <our choice / rationale>
INVARIANTS:
  - <rule whose breakage causes non-obvious damage>
GOTCHAS:
  - <landmine whose fix isn't obvious from code alone>
```

The file is checked in. `revive show` assembles the brief around it on each
refresh. Placeholder-only sections (still saying *"(edit this file)"*) are
suppressed from the brief — no noise.

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

- **PURPOSE** — curated 1-liner. Chain: `gh repo view --json description` →
  manifest `description` (pyproject, package.json, Cargo, gemspec,
  composer) → `CLAUDE.md` → filtered README. First hit wins.
- **DIFFERENTIATORS, INVARIANTS, GOTCHAS** — human-curated (via `suggest` +
  `audit`, user-reviewed). Research: *"Human curation yields ~4%
  performance gains; auto-generation reduces success rates by 0.5–2%"*
  ([Augment Code, 2026][augment]).
- **STATE** — `git` branch + last 3 commits, with body excerpt for
  fix/feat/refactor commits (surfaces PR descriptions for squash-merge
  workflows).
- **HOT_FILES** — top 5 files by commit-frequency over the last 20 commits,
  each annotated with the last commit subject.
- **COMMANDS** — exact test/lint/build/dev invocations from `package.json`
  / Rails `bin/*` / `Makefile` / `.revive/commands.md` override.

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

Pre-alpha. Weekend MVP in active dogfooding. **v0.1.17** — `revive audit`
as separate fresh-session LLM call; 111 bats tests pass; see
[Releases](https://github.com/justi/context-revive/releases) for history.

## License

MIT
