PURPOSE: Bash CLI that injects a deterministic <2200-char project brief into Claude Code on a cadence via UserPromptSubmit. Solves context rot. Constraint: zero LLM calls, <100ms hot path, single bash file with `git` + `jq`.
DIFFERENTIATORS:
  - Two-layer brief: STATIC `.revive/static.md` (curated) + DYNAMIC (regenerated from git per refresh).
  - Hot path is shell + git. No LLM, no python/node, no daemon. <100 ms.
  - Cadence-gated (every 5th prompt or >10 min gap).
  - Auto-generated tree/dep-graph rejected — 2026 research shows it reduces agent success.
INVARIANTS:
  - Brief <2200 chars, <100 ms, zero LLM calls on hot path. Exceeding these blocks release.
  - STATIC vs DYNAMIC strictly separated. Never inject auto-generated content into static.md.
  - `cmd_refresh` always exits 0. Hook failures silent — never break a Claude Code session.
  - Bash + git only. `jq` is the sole optional dep. Push back on anything new.
GOTCHAS:
  - bats `run` merges stderr into `$output`. For stdout-only assertions use `--separate-stderr`. Each `[[ ]]` / `[ ]` needs `|| return 1` — bats fails only on the LAST status.
  - `set -euo pipefail`: `cmd | head | ... || true` needed in HOT_FILES, else pipefail trips when no commits match filters.
  - `command -v jq` finds broken jq. `cmd_doctor` falls back to grep on settings.json when jq query fails.
  - `purpose_from_*` chain: first hit wins (gh description → manifest → CLAUDE.md → README). `init --force` re-detects.
