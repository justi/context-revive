# CLAUDE.md — context-revive

Instructions for AI collaborators working on this repo.

## What this project is

`context-revive` is a shell-script CLI that generates a dense, deterministic
project brief and re-injects it into Claude Code sessions on a fixed cadence
via the `UserPromptSubmit` hook. It solves context rot in long agent sessions.

Single-file bash script (`bin/revive`). Zero runtime beyond bash + git.
Installed via `curl | bash` into `~/.local/bin/revive`.

## Design anchors (read before changing behavior)

- Brief output <1800 chars, <100ms, **zero LLM calls on the hot path**.
- Two-layer format: STATIC (user-edited `.revive/static.md`) + DYNAMIC
  (regenerated per refresh from `git` + filesystem).
- Cadence: every 5 prompts, or >10 min gap, or after `/compact` detected.
- Hook failures must be silent — Claude Code session continues without brief.
  Log to `~/.context-revive/hook.log`.
- **Inject only what the agent can't re-derive from code.** 2026 research on
  context engineering (AGENTS.md / Zylos substrate-projection / Augment Code)
  is explicit: auto-generated architecture overviews, directory trees, and
  dependency graphs reduce agent success rate. Stay with non-inferable facts.

See local `adr/` (private during early development) for full rationale.

## Stack discipline

- **Language:** bash (POSIX-compatible where possible; `#!/usr/bin/env bash`).
- **Dependencies:** `git` (required), `jq` (only for `install-hook`).
  Nothing else. No curl/wget in hot path, no python, no node.
- **Tests:** `bats` in `tests/*.bats`.
- **Lint:** `shellcheck bin/revive install.sh`.

If you're tempted to reach for Python/Node/Go — stop. The point of this repo
is that it doesn't need them. Push back on any dependency that isn't already
on every dev machine.

## Scope discipline

Not in v1 (explicitly deferred or deliberately rejected):
- tree-sitter or any language-aware parsing (regex + filename heuristics)
- per-fact provenance / scan_hash
- cross-project knowledge graph
- adaptive cadence / telemetry
- LLM-assisted init (`--with-llm`) — optional future
- **Auto-generated architecture / directory tree / dependency graph** —
  **rejected** based on 2026 research (reduces agent success rate; see
  README "Design — what goes in the brief, and why"). Do not add.

Push back if asked to add these.

## Conventions

- `set -euo pipefail` at the top of every script.
- Functions prefixed `cmd_` for subcommand handlers.
- No `eval`, no unquoted expansions, no `$(cat file)` when `< file` works.
- Commits: imperative mood, one concern per commit.
- ADRs in `adr/` (gitignored during early development).

## Typography

- Use em-dash (—), not double hyphen (--).
