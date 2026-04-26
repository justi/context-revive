PURPOSE: Bash CLI that injects a deterministic project brief into Claude Code on a cadence via UserPromptSubmit. Solves context rot. Constraint: zero LLM calls, <100 ms hot path, single bash file — `git` required, `jq` optional.
DIFFERENTIATORS:
  - Two-layer brief: STATIC `.revive/static.md` (curated) + DYNAMIC (regenerated from git per refresh).
  - Hot path is shell + git. No LLM, no python/node, no daemon. <100 ms.
  - Cadence-gated (every 5th prompt or >10 min gap).
  - Auto-generated tree/dep-graph rejected — 2026 research shows it reduces agent success.
INVARIANTS:
  - <100 ms, zero LLM calls on hot path. `BRIEF_CHAR_BUDGET` (2200) is a printed diagnostics target, not enforced — `show` reports overage but doesn't truncate.
  - STATIC vs DYNAMIC strictly separated. Never inject auto-generated content into static.md.
  - `cmd_refresh` always exits 0. Hook failures silent — never break a Claude Code session.
  - Bash + git only on hot path. `jq` is the sole optional dep. Push back on anything new.
GOTCHAS:
  - bats `run` merges stderr into `$output`. For stdout-only assertions use `--separate-stderr`. Each `[[ ]]` / `[ ]` needs `|| return 1` — bats fails only on the LAST status.
  - `set -euo pipefail`: `cmd | head | ... || true` needed in HOT_FILES, else pipefail trips when no commits match filters.
  - `cmd_doctor` falls back to grep on settings.json when the jq path fails (jq absent OR `jq -e` errors out OR malformed JSON) — manually-installed hooks still get detected.
  - `purpose_from_*` chain: first hit wins (gh description → manifest → CLAUDE.md → README). `init --force` re-detects.
