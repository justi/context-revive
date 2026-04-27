#!/usr/bin/env bats
# Run with: bats tests/

bats_require_minimum_version 1.5.0

setup() {
  REVIVE="${BATS_TEST_DIRNAME}/../bin/revive"
  WORKDIR="${BATS_TEST_DIRNAME}/../.tmp-test-$$-${BATS_TEST_NUMBER}"
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"
  # -b main: pin default branch name for portability across hosts whose
  # init.defaultBranch may be `master` or something else.
  git init -q -b main
  git config user.email test@example.com
  git config user.name test
  git commit -q --allow-empty -m "initial commit"
  # isolate HOME so tests don't touch real ~/.context-revive
  export HOME="$WORKDIR/home"
  mkdir -p "$HOME"
}

teardown() {
  cd "${BATS_TEST_DIRNAME}/.."
  rm -rf "$WORKDIR"
}

# --- meta ---

@test "prints version" {
  run "$REVIVE" version
  [ "$status" -eq 0 ]
  [[ "$output" == revive* ]]
}

@test "prints usage on no args" {
  run "$REVIVE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: revive"* ]]
}

@test "unknown command exits non-zero" {
  run "$REVIVE" bogus
  [ "$status" -eq 1 ]
}

# --- brief structure ---

@test "show wraps brief in <revive> tags" {
  run "$REVIVE" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"<revive refresh="* ]]
  [[ "$output" == *"</revive>"* ]]
}

@test "show includes STATIC and DYNAMIC sections" {
  run "$REVIVE" show
  [[ "$output" == *"# STATIC"* ]]
  [[ "$output" == *"# DYNAMIC"* ]]
  [[ "$output" == *"STATE:"* ]]
  [[ "$output" == *"HOT_FILES:"* ]]
  # TODO section is now conditionally omitted when no plan.md/TODO.md
  # exists (v0.1.7 placeholder-skip); don't assert presence here.
}

@test "todo: detects docs/TODO.md when no root-level source exists" {
  mkdir -p docs
  printf -- "- first docs todo\n- second\n" > docs/TODO.md
  run "$REVIVE" show
  [[ "$output" == *"TODO: (from docs/TODO.md)"* ]] || return 1
  [[ "$output" == *"first docs todo"* ]]           || return 1
}

@test "todo: root plan.md wins over docs/TODO.md" {
  mkdir -p docs
  printf -- "- docs todo\n" > docs/TODO.md
  printf -- "- root plan\n" > plan.md
  run "$REVIVE" show
  [[ "$output" == *"TODO: (from plan.md)"* ]] || return 1
  [[ "$output" == *"root plan"* ]]             || return 1
  [[ "$output" != *"docs todo"* ]]             || return 1
}

@test "purpose: capped at first sentence boundary" {
  # Multi-sentence manifest description: only the first sentence should land.
  printf '{"description":"Baby roleplay sim. A long second sentence that should be trimmed away entirely. And a third."}\n' > package.json
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"Baby roleplay sim."* ]]          || return 1
  [[ "$output" != *"long second sentence"* ]]        || return 1
  [[ "$output" != *"And a third"* ]]                 || return 1
}

@test "purpose: hard-capped at 400 chars when no sentence boundary exists" {
  local long
  long=$(printf 'X%.0s' {1..600})
  printf '{"description":"%s"}\n' "$long" > package.json
  run "$REVIVE" init
  run cat .revive/static.md
  local purpose_line
  purpose_line=$(printf '%s\n' "$output" | grep '^PURPOSE:' || true)
  # Exact expected length: "PURPOSE: " (9 chars) + 400 chars of X = 409.
  # Tight bounds catch off-by-one in the cap (Copilot review).
  [ "${#purpose_line}" -eq 409 ] || return 1
}

@test "purpose: short PURPOSE stays untouched by cap" {
  printf '{"description":"Short purpose."}\n' > package.json
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"PURPOSE: Short purpose."* ]] || return 1
}

@test "show emits TODO section when plan.md exists, omits it when absent" {
  # Note: bats-core only fails a test based on the LAST command's exit
  # status, so we chain [[ ]] with `|| return 1` to make each assertion
  # actually fail the test. See commit body for v0.1.7 for details.
  run "$REVIVE" show
  [[ "$output" != *"TODO:"*  ]]          || return 1
  [[ "$output" != *"no plan.md"* ]]      || return 1
  printf -- "- first\n- second\n- third\n" > plan.md
  run "$REVIVE" show
  [[ "$output" == *"TODO: (from plan.md)"* ]] || return 1
  [[ "$output" == *"first"* ]]                || return 1
}

@test "hot_files shows N× count prefix and last commit msg" {
  echo "hello" > a.rb
  git add a.rb
  git commit -qm "add a.rb"
  echo "world" >> a.rb
  git add a.rb
  git commit -qm "update a.rb"
  run "$REVIVE" show
  [[ "$output" == *"× a.rb"* ]]
  [[ "$output" == *"update a.rb"* ]]
}

@test "hot_files filters lock and vendor noise" {
  mkdir -p vendor
  echo x > package-lock.json
  echo y > vendor/ignored.rb
  echo z > real.rb
  git add .
  git commit -qm "mixed commit"
  run "$REVIVE" show
  [[ "$output" == *"real.rb"* ]]
  [[ "$output" != *"package-lock.json"* ]]
  [[ "$output" != *"vendor/ignored.rb"* ]]
}

@test "hot_files filters package-lock.json (JS ecosystem)" {
  echo '{}' > package-lock.json
  git add package-lock.json
  git commit -qm "bump package-lock"
  echo 'console.log(1)' > src.js
  git add src.js
  git commit -qm "add src.js"
  run "$REVIVE" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"src.js"* ]]
  [[ "$output" != *"package-lock.json"* ]]
}

@test "hot_files filters pnpm-lock.yaml (JS ecosystem)" {
  echo 'lockfile: 5' > pnpm-lock.yaml
  git add pnpm-lock.yaml
  git commit -qm "bump pnpm"
  echo 'x' > app.ts
  git add app.ts
  git commit -qm "add app.ts"
  run "$REVIVE" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"app.ts"* ]]
  [[ "$output" != *"pnpm-lock.yaml"* ]]
}

# Codex P1: pipeline under set -euo pipefail must not abort when all recent
# commits touch only filtered paths.
@test "hot_files does not abort when all recent history is filtered noise" {
  echo '{}' > package-lock.json
  git add package-lock.json
  git commit -qm "lockfile only 1"
  echo '{"v":2}' > package-lock.json
  git add package-lock.json
  git commit -qm "lockfile only 2"
  run "$REVIVE" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"HOT_FILES:"* ]]
  [[ "$output" == *"no files touched"* ]]
}

@test "refresh stays silent-failure safe when history is filter-only" {
  echo '{}' > yarn.lock
  git add yarn.lock
  git commit -qm "lock"
  run "$REVIVE" refresh
  [ "$status" -eq 0 ]
}

@test "hot_files reports no-history when repo is empty" {
  # nuke initial commit to get a genuinely empty repo
  rm -rf .git
  git init -q -b main
  git config user.email test@example.com
  git config user.name test
  run "$REVIVE" show
  [[ "$output" == *"HOT_FILES:"* ]]
  [[ "$output" == *"no history"* ]]
}

@test "hot_files ranks by frequency (most-touched first)" {
  for i in 1 2 3 4; do
    echo "$i" > frequent.rb
    git add frequent.rb
    git commit -qm "touch frequent #$i"
  done
  echo x > rare.rb
  git add rare.rb
  git commit -qm "add rare once"
  run "$REVIVE" show
  # frequent.rb must appear before rare.rb in output
  local fpos rpos
  fpos=$(echo "$output" | grep -n 'frequent.rb' | head -1 | cut -d: -f1)
  rpos=$(echo "$output" | grep -n 'rare.rb' | head -1 | cut -d: -f1)
  [ -n "$fpos" ] && [ -n "$rpos" ]
  [ "$fpos" -lt "$rpos" ]
}

@test "hot_files caps window at 20 commits" {
  for i in $(seq 1 25); do
    echo "$i" > loop.rb
    git add loop.rb
    git commit -qm "commit $i"
  done
  run "$REVIVE" show
  # extract the count prefix for loop.rb — must be <= 20
  local count
  count=$(echo "$output" | awk '/× loop.rb$/ {gsub(/×/,""); print $1; exit}')
  [ -n "$count" ]
  [ "$count" -le 20 ]
}

@test "hot_files handles deleted files" {
  echo tmp > gone.rb
  git add gone.rb
  git commit -qm "add gone.rb"
  git rm -q gone.rb
  git commit -qm "remove gone.rb"
  run "$REVIVE" show
  [[ "$output" == *"gone.rb"* ]]
  [[ "$output" == *"remove gone.rb"* ]]
}

@test "hot_files handles paths with spaces" {
  echo foo > "my file.rb"
  git add "my file.rb"
  git commit -qm "add spaced file"
  echo bar >> "my file.rb"
  git add "my file.rb"
  git commit -qm "update spaced file"
  run "$REVIVE" show
  [[ "$output" == *"my file.rb"* ]]
}

@test "hot_files handles deeply nested paths" {
  mkdir -p a/b/c/d/e
  echo deep > a/b/c/d/e/leaf.rb
  git add a/b/c/d/e/leaf.rb
  git commit -qm "add deep"
  run "$REVIVE" show
  [[ "$output" == *"a/b/c/d/e/leaf.rb"* ]]
}

@test "hot_files survives commit messages with quotes and special chars" {
  echo x > weird.rb
  git add weird.rb
  git commit -qm 'fix: handle "quoted" input & $edge cases'
  run "$REVIVE" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"weird.rb"* ]]
  [[ "$output" == *"quoted"* ]]
}

@test "hot_files ignores merge commits' lack of file list" {
  # create a divergent branch and merge — merges have no files by default
  echo main-work > main.rb
  git add main.rb
  git commit -qm "main work"
  git checkout -qb feature
  echo feature-work > feat.rb
  git add feat.rb
  git commit -qm "feature work"
  git checkout -q main
  git merge -q --no-ff feature -m "merge feature"
  run "$REVIVE" show
  [ "$status" -eq 0 ]
  # both files should appear (from their own commits, not the merge)
  [[ "$output" == *"main.rb"* ]]
  [[ "$output" == *"feat.rb"* ]]
}

@test "hot_files limits output to top 5 files" {
  for f in one two three four five six seven; do
    echo x > "$f.rb"
    git add "$f.rb"
    git commit -qm "add $f"
  done
  run "$REVIVE" show
  local count
  count=$(echo "$output" | grep -cE '^\s+[0-9]+×\s')
  [ "$count" -le 5 ]
}

# ------------------- PURPOSE chain (v0.1.2) ----------------------------

@test "purpose chain: pyproject description wins over README" {
  cat > pyproject.toml <<'EOF'
[project]
name = "example"
description = "A Python thing from pyproject"
version = "0.0.1"
EOF
  echo "this should lose" > README.md
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"A Python thing from pyproject"* ]]
  [[ "$output" != *"this should lose"* ]]
}

@test "purpose chain: package.json description wins over README" {
  printf '{"name":"x","description":"A Node thing from package.json"}\n' > package.json
  echo "loser" > README.md
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"A Node thing from package.json"* ]]
}

@test "purpose chain: Cargo.toml description wins over README" {
  cat > Cargo.toml <<'EOF'
[package]
name = "x"
description = "A Rust thing from Cargo"
version = "0.1.0"
EOF
  echo "loser" > README.md
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"A Rust thing from Cargo"* ]]
}

@test "purpose chain: gemspec summary wins over README" {
  cat > example.gemspec <<'EOF'
Gem::Specification.new do |s|
  s.name    = "example"
  s.summary = "A gem from the gemspec"
end
EOF
  echo "loser" > README.md
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"A gem from the gemspec"* ]]
}

@test "purpose chain: composer.json description wins over README" {
  printf '{"name":"x","description":"PHP thing from composer"}\n' > composer.json
  echo "loser" > README.md
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"PHP thing from composer"* ]]
}

# Codex P2: wrapped CLAUDE.md paragraphs were truncated to the first line.
@test "purpose chain: CLAUDE.md captures hard-wrapped paragraph across lines" {
  cat > CLAUDE.md <<'EOF'
# Project

## What this project is

This is a description that spans across
multiple lines because the author wrapped at
80 columns, and all three lines matter.

## Something else
EOF
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"spans across multiple lines"* ]]
  [[ "$output" == *"all three lines matter"* ]]
}

# Codex P3: gemspec sed stripped interior apostrophes of double-quoted strings.
@test "purpose chain: gemspec preserves apostrophes inside double-quoted summary" {
  cat > example.gemspec <<'EOF'
Gem::Specification.new do |s|
  s.name    = "example"
  s.summary = "It's a Ruby gem that's useful"
end
EOF
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"It's a Ruby gem that's useful"* ]]
}

@test "purpose chain: gemspec with single-quoted summary still works" {
  cat > example.gemspec <<'EOF'
Gem::Specification.new do |s|
  s.name    = "example"
  s.summary = 'Single-quoted summary here'
end
EOF
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"Single-quoted summary here"* ]]
}

# Codex P2: composer.json fallback path when jq unavailable or fails.
@test "purpose chain: composer.json extraction works via grep fallback" {
  printf '{"name":"acme/widget","description":"Composer grep-path description","require":{}}\n' > composer.json
  # Shim jq to simulate unavailable/broken. command -v will still find it,
  # so we also have the in-function behavior of treating empty jq output as
  # "try grep fallback".
  mkdir -p "$WORKDIR/shim"
  cat > "$WORKDIR/shim/jq" <<'EOF'
#!/usr/bin/env bash
# always return empty to force the grep fallback
exit 0
EOF
  chmod +x "$WORKDIR/shim/jq"
  PATH="$WORKDIR/shim:$PATH" "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"Composer grep-path description"* ]]
}

@test "purpose chain: CLAUDE.md 'What this project is' wins over README" {
  cat > CLAUDE.md <<'EOF'
# Project

## What this project is

A tool that does the thing agents need.

## Something else
EOF
  echo "loser" > README.md
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"A tool that does the thing agents need"* ]]
}

@test "purpose chain: README filter strips blockquote markers" {
  cat > README.md <<'EOF'
# Title

> This is the real description, inside a blockquote.
EOF
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"This is the real description"* ]]
  [[ "$output" != *"> This"* ]]
}

@test "purpose chain: README filter strips horizontal rulers and badges" {
  cat > README.md <<'EOF'
# Title

[![Build](https://img.shields.io/badge/build-passing-green)](https://example.com)
─────────────────────────

Real purpose sentence here.
EOF
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"Real purpose sentence here"* ]]
  [[ "$output" != *"────"* ]]
  [[ "$output" != *"shields.io"* ]]
}

@test "purpose chain: README filter strips bullet-link-only lines" {
  cat > README.md <<'EOF'
# Title

First real sentence here.
- [CLAUDE.md](/path/to/CLAUDE.md) — irrelevant nav link
EOF
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"First real sentence here"* ]]
  [[ "$output" != *"CLAUDE.md"* ]]
}

@test "purpose chain: placeholder when no sources exist" {
  # workdir already has no manifest files from setup
  run "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"describe this project"* ]]
}

# ------------------- COMMANDS section (v0.1.2) -------------------------

@test "commands: user override .revive/commands.md wins" {
  mkdir -p .revive
  cat > .revive/commands.md <<'EOF'
test: bin/override-test
lint: bin/override-lint
EOF
  # even with a competing package.json present
  printf '{"scripts":{"test":"jest"}}\n' > package.json
  run "$REVIVE" show
  [[ "$output" == *"COMMANDS:"* ]]
  [[ "$output" == *"bin/override-test"* ]]
  [[ "$output" != *"jest"* ]]
}

@test "commands: extracted from package.json scripts" {
  printf '{"scripts":{"test":"vitest","lint":"eslint .","build":"tsc"}}\n' > package.json
  run "$REVIVE" show
  [[ "$output" == *"COMMANDS:"* ]]
  [[ "$output" == *"test: vitest"* ]]
  [[ "$output" == *"lint: eslint ."* ]]
  [[ "$output" == *"build: tsc"* ]]
}

@test "commands: Rails bin/* wins over package.json when Gemfile present" {
  echo 'source "https://rubygems.org"' > Gemfile
  mkdir -p bin
  printf '#!/bin/sh\nexec bin/rails server "$@"\n' > bin/dev
  printf '#!/bin/sh\nexec rspec "$@"\n' > bin/rspec
  chmod +x bin/dev bin/rspec
  printf '{"scripts":{"test":"vitest"}}\n' > package.json
  run "$REVIVE" show
  [[ "$output" == *"run: bin/dev"* ]]
  [[ "$output" == *"test: bin/rspec"* ]]
  [[ "$output" != *"vitest"* ]]
}

@test "commands: Makefile targets extracted when no manifest" {
  cat > Makefile <<'EOF'
test:
	go test ./...

lint:
	golangci-lint run
EOF
  run "$REVIVE" show
  [[ "$output" == *"COMMANDS:"* ]]
  [[ "$output" == *"test: make test"* ]]
  [[ "$output" == *"lint: make lint"* ]]
}

@test "commands: section omitted entirely when no sources found" {
  # empty workdir has no Gemfile, package.json, Makefile, bin/*
  run "$REVIVE" show
  [[ "$output" != *"COMMANDS:"* ]]
  [[ "$output" != *"(no commands"* ]]
}

# ------------------- STATIC placeholder-skip (v0.1.2) ------------------

@test "static placeholder INVARIANTS/GOTCHAS bullets are suppressed" {
  "$REVIVE" init
  run "$REVIVE" show
  [[ "$output" == *"INVARIANTS:"* ]]
  [[ "$output" == *"GOTCHAS:"* ]]
  # but the "(edit this file)" placeholder bullets must not leak into the brief
  [[ "$output" != *"edit this file"* ]]
}

@test "static keeps non-placeholder bullets intact" {
  mkdir -p .revive
  cat > .revive/static.md <<'EOF'
PURPOSE: Real purpose here.
INVARIANTS:
  - Never commit to main directly.
  - Always run tests before pushing.
GOTCHAS:
  - Rate limit is 100 req/min.
EOF
  run "$REVIVE" show
  [[ "$output" == *"Never commit to main directly"* ]]
  [[ "$output" == *"Rate limit is 100 req/min"* ]]
}

# ------------------- misc ---------------------------------------------

@test "brief stays under 1800 chars even with rich history" {
  for i in $(seq 1 15); do
    echo "$i" > "file$i.rb"
    git add "file$i.rb"
    git commit -qm "add file$i with a reasonably descriptive commit message"
  done
  run "$REVIVE" show
  [ "${#output}" -lt 1800 ]
}

@test "state: commit body excerpt rendered under subject when present" {
  # Create a commit with a real body paragraph
  echo "a" > f.txt
  git add f.txt
  git commit -q -m "fix(core): guard against empty input" -m "Empty input crashed the parser because the regex matched nothing."
  run "$REVIVE" show
  [[ "$output" == *"fix(core): guard against empty input"* ]]   || return 1
  [[ "$output" == *"↪ Empty input crashed the parser"* ]]       || return 1
}

@test "state: no body line emitted for subject-only commits" {
  # Setup's initial commit was created with --allow-empty and no body.
  # Add another subject-only commit to be sure.
  echo x > g.txt
  git add g.txt
  git commit -q -m "chore: add g"
  run "$REVIVE" show
  [[ "$output" == *"chore: add g"* ]] || return 1
  # The bullet immediately after "chore: add g" must not be an arrow line.
  # Extract the line following the subject and check it's not `↪`.
  local next_line
  next_line=$(printf '%s\n' "$output" | grep -A1 'chore: add g' | tail -1)
  [[ "$next_line" != *"↪"* ]] || return 1
}

@test "state: long body paragraph truncated to ~100 chars with ellipsis" {
  echo y > h.txt
  git add h.txt
  local long_body
  long_body=$(printf 'x %.0s' {1..120})
  git commit -q -m "fix: long body" -m "$long_body"
  run "$REVIVE" show
  # Find the ↪ line in output
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ -n "$body_line" ]]           || return 1
  [[ "$body_line" == *"…"* ]]     || return 1
  # Line is: "      ↪ <100 chars>…" — total 6+2+100+1 ≈ 109-110 chars
  [ "${#body_line}" -le 115 ] || return 1
}

@test "state: body paragraph collapses multi-line wrap into one line" {
  echo z > i.txt
  git add i.txt
  # Body with hard-wrapped lines (no blank line between them)
  git commit -q -m "fix: wrapped body" -m "Line one of the paragraph
Line two still same paragraph
Line three still same."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Line one of the paragraph Line two still same paragraph Line three still same."* ]] || return 1
}

# Codex P2: PR templates start with `## Summary` + blank line; body
# extractor was returning the heading instead of the actual description.
@test "state: body extraction skips leading markdown heading (PR template)" {
  echo t > tpl.txt
  git add tpl.txt
  git commit -q -m "feat: with template body" -m "## Summary

Actual description lives below the heading.

## Test Plan
- [x] one"
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ -n "$body_line" ]]                                      || return 1
  [[ "$body_line" == *"Actual description lives below"* ]]   || return 1
  [[ "$body_line" != *"## Summary"* ]]                       || return 1
}

@test "state: body extraction skips leading single-line HTML comment" {
  echo u > htmlcomment.txt
  git add htmlcomment.txt
  git commit -q -m "fix: with html comment" -m "<!-- Closes #42 -->

Real rationale after the HTML comment marker."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Real rationale after"* ]]  || return 1
  [[ "$body_line" != *"<!--"* ]]                   || return 1
  [[ "$body_line" != *"Closes #42"* ]]             || return 1
}

@test "state: body extraction skips multi-line HTML comment block" {
  echo v > multi.txt
  git add multi.txt
  git commit -q -m "feat: multi-line comment" -m "<!--
  Please describe the change here.
  Delete this template before merging.
-->

Genuine first paragraph of the PR body."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Genuine first paragraph"* ]]         || return 1
  [[ "$body_line" != *"Please describe"* ]]                 || return 1
  [[ "$body_line" != *"Delete this template"* ]]            || return 1
}

# Codex P2 on v0.1.10: lines with prose + inline HTML comment were being
# dropped entirely. Strip only the comment, preserve the content.
@test "state: inline HTML comment stripped, prose on same line preserved" {
  echo k > k.txt
  git add k.txt
  git commit -q -m "fix: closes issue" -m "Fix parser crash on empty input <!-- closes #42 -->

Second paragraph should not leak."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Fix parser crash on empty input"* ]] || return 1
  [[ "$body_line" != *"<!--"* ]]                             || return 1
  [[ "$body_line" != *"closes #42"* ]]                       || return 1
  [[ "$body_line" != *"Second paragraph"* ]]                 || return 1
}

@test "state: leading inline HTML comment stripped, trailing prose kept" {
  echo l > l.txt
  git add l.txt
  git commit -q -m "fix: with leading comment" -m "<!-- note --> Real rationale text here."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Real rationale text here."* ]] || return 1
  [[ "$body_line" != *"<!--"* ]]                      || return 1
}

@test "state: multiple inline HTML comments all stripped within one line" {
  echo m > m.txt
  git add m.txt
  git commit -q -m "fix: many inline comments" -m "First <!-- a --> then <!-- b --> last bit."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"First"* ]]         || return 1
  [[ "$body_line" == *"then"* ]]          || return 1
  [[ "$body_line" == *"last bit."* ]]     || return 1
  [[ "$body_line" != *"<!--"* ]]          || return 1
}

# Codex v0.1.11 P2a: comment-only line inside a paragraph was prematurely
# terminating the first paragraph.
@test "state: comment-only line within paragraph does not terminate it" {
  echo z1 > z1.txt
  git add z1.txt
  git commit -q -m "fix: interleaved comment" -m "Line one of paragraph.
<!-- mid-paragraph note -->
Line two of paragraph."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Line one of paragraph."* ]]   || return 1
  [[ "$body_line" == *"Line two of paragraph."* ]]   || return 1
  [[ "$body_line" != *"<!--"* ]]                     || return 1
}

@test "state: multi-line comment block inside paragraph does not terminate it" {
  echo z2 > z2.txt
  git add z2.txt
  git commit -q -m "fix: block comment mid-para" -m "Line one of paragraph.
<!--
  block of comment
  across multiple lines
-->
Line two of paragraph."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Line one of paragraph."* ]]   || return 1
  [[ "$body_line" == *"Line two of paragraph."* ]]   || return 1
  [[ "$body_line" != *"block of comment"* ]]         || return 1
}

# Codex v0.1.11 P2b: inline <!-- ... --> whose body contains ">" broke the
# regex-based strip.
@test "state: inline HTML comment containing '>' still strips correctly" {
  echo z3 > z3.txt
  git add z3.txt
  git commit -q -m "fix: gt in comment" -m "Handle case where x > 0 <!-- repro: x > 0 crashed --> properly."
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Handle case where x > 0"* ]]  || return 1
  [[ "$body_line" == *"properly."* ]]                || return 1
  [[ "$body_line" != *"<!--"* ]]                     || return 1
  [[ "$body_line" != *"repro: x > 0 crashed"* ]]     || return 1
}

@test "state: body excerpt is empty when body is only template (no real content)" {
  echo w > onlytmpl.txt
  git add onlytmpl.txt
  git commit -q -m "chore: only template" -m "## Summary

## Test Plan"
  run "$REVIVE" show
  # The subject line must appear, but no body line should follow it.
  [[ "$output" == *"chore: only template"* ]] || return 1
  local next_line
  next_line=$(printf '%s\n' "$output" | grep -A1 'chore: only template' | tail -1)
  [[ "$next_line" != *"↪"* ]] || return 1
}

@test "state: body extraction stops at first blank line (skips trailers)" {
  echo w > j.txt
  git add j.txt
  git commit -q -m "feat: with trailers" -m "Real first paragraph content.

Co-Authored-By: Bot <bot@example.com>"
  run "$REVIVE" show
  local body_line
  body_line=$(printf '%s\n' "$output" | grep '↪' | head -1)
  [[ "$body_line" == *"Real first paragraph content."* ]] || return 1
  [[ "$body_line" != *"Co-Authored-By"* ]]                || return 1
}

@test "show reports git branch in STATE" {
  run "$REVIVE" show
  [[ "$output" == *"branch="* ]]
}

@test "brief stays under 1800-char budget on minimal repo" {
  run "$REVIVE" show
  # show prints budget line to stderr; the brief is stdout
  local brief_len=${#output}
  [ "$brief_len" -lt 1800 ]
}

# --- init ---

@test "init creates .revive/static.md" {
  run "$REVIVE" init
  [ "$status" -eq 0 ]
  [ -f ".revive/static.md" ]
}

@test "init refuses to overwrite existing static.md" {
  "$REVIVE" init
  run "$REVIVE" init
  [ "$status" -eq 1 ]
  [[ "$output" == *"exists"* ]]
  [[ "$output" == *"--force"* ]]
}

@test "init --force regenerates PURPOSE from chain" {
  # seed with a bad PURPOSE like the pre-v0.1.2 naive extractor produced
  mkdir -p .revive
  cat > .revive/static.md <<'EOF'
PURPOSE: ───── old garbage purpose ─────
INVARIANTS:
  - (top-5 architectural rules; edit this file)
GOTCHAS:
  - (landmines you keep stepping on; edit this file)
EOF
  # provide a high-quality source for the chain
  printf '{"name":"x","description":"Clean new description from package.json"}\n' > package.json

  run "$REVIVE" init --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"regenerated"* ]]

  run cat .revive/static.md
  [[ "$output" == *"Clean new description from package.json"* ]]
  [[ "$output" != *"old garbage purpose"* ]]
}

@test "init --force preserves user-edited INVARIANTS and GOTCHAS" {
  mkdir -p .revive
  cat > .revive/static.md <<'EOF'
PURPOSE: old stale purpose
INVARIANTS:
  - Never commit secrets.
  - Always sign commits.
GOTCHAS:
  - API rate limit is 10/sec — retry with exponential backoff.
EOF
  printf '{"description":"fresh purpose"}\n' > package.json

  run "$REVIVE" init --force
  [ "$status" -eq 0 ]

  run cat .revive/static.md
  [[ "$output" == *"fresh purpose"* ]]
  # user rules must survive
  [[ "$output" == *"Never commit secrets"* ]]
  [[ "$output" == *"Always sign commits"* ]]
  [[ "$output" == *"API rate limit is 10/sec"* ]]
}

@test "init -f short flag works the same as --force" {
  "$REVIVE" init
  run "$REVIVE" init -f
  [ "$status" -eq 0 ]
  [[ "$output" == *"regenerated"* ]]
}

@test "suggest prints core prompt sections on stdout" {
  run --separate-stderr "$REVIVE" suggest
  [ "$status" -eq 0 ]
  [[ "$output" == *"INVARIANTS"* ]] || return 1
  [[ "$output" == *"GOTCHAS"* ]] || return 1
  [[ "$output" == *"non-inferable"* ]] || return 1
  # meta-comments must go to stderr, not stdout — so `| pbcopy` stays clean
  [[ "$output" != *"Paste this prompt"* ]] || return 1
  [[ "$output" != *"BEGIN PROMPT"* ]] || return 1
}

@test "suggest prompt instructs agent to edit .revive/static.md end-to-end" {
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  # step 1: preview
  [[ "$output" == *"STEP 1"* ]] || return 1
  [[ "$output" == *"preview"* ]] || return 1
  # step 2: edit the file in place
  [[ "$output" == *"STEP 2"* ]] || return 1
  [[ "$output" == *".revive/static.md"* ]] || return 1
  # guard against creating the file if it doesn't exist
  [[ "$output" == *"revive init"* ]] || return 1
}

@test "suggest prompt requests PURPOSE as Deliverable 1 (v0.1.13)" {
  # After v0.1.14 DIFFERENTIATORS slots in as Deliverable 2 — keep this
  # test narrow: PURPOSE must be Deliverable 1.
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deliverable 1 — PURPOSE"* ]] || return 1
}

@test "suggest PURPOSE deliverable requires business goals (v0.1.14)" {
  # Marketing one-liners are no longer "substantive" — PURPOSE must
  # cover what + why (business goal) + essential constraint.
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'business goal or success criterion' || return 1
  printf '%s\n' "$output" | grep -qF 'All three must be present'           || return 1
  # Placeholder classification must explicitly cover marketing-tagline state
  printf '%s\n' "$output" | grep -qF "what success"                         || return 1
}

# DIFFERENTIATORS section (v0.1.14)

@test "init scaffolds DIFFERENTIATORS section alongside others" {
  run "$REVIVE" init
  [ "$status" -eq 0 ]
  run cat .revive/static.md
  [[ "$output" == *"DIFFERENTIATORS:"* ]]                   || return 1
  [[ "$output" == *"what sets this project apart"* ]]       || return 1
  # section ordering: PURPOSE → DIFFERENTIATORS → INVARIANTS → GOTCHAS
  local purp_line diff_line inv_line got_line
  purp_line=$(printf '%s\n' "$output" | grep -n '^PURPOSE:'         | cut -d: -f1)
  diff_line=$(printf '%s\n' "$output" | grep -n '^DIFFERENTIATORS:' | cut -d: -f1)
  inv_line=$(printf '%s\n' "$output" | grep -n '^INVARIANTS:'       | cut -d: -f1)
  got_line=$(printf '%s\n' "$output" | grep -n '^GOTCHAS:'          | cut -d: -f1)
  [ "$purp_line" -lt "$diff_line" ] || return 1
  [ "$diff_line" -lt "$inv_line" ]  || return 1
  [ "$inv_line" -lt "$got_line" ]   || return 1
}

@test "show skips placeholder DIFFERENTIATORS bullets" {
  "$REVIVE" init
  run "$REVIVE" show
  # header stays for structure, placeholder bullet must not leak
  [[ "$output" == *"DIFFERENTIATORS:"* ]]        || return 1
  [[ "$output" != *"what sets this project"* ]]  || return 1
}

@test "show keeps substantive DIFFERENTIATORS bullets intact" {
  mkdir -p .revive
  cat > .revive/static.md <<'EOF'
PURPOSE: Test project.
DIFFERENTIATORS:
  - Unlike cron — code-defined schedules that survive deploys.
  - Unlike SaaS schedulers — zero new infrastructure.
INVARIANTS:
GOTCHAS:
EOF
  run "$REVIVE" show
  [[ "$output" == *"Unlike cron"* ]]              || return 1
  [[ "$output" == *"zero new infrastructure"* ]] || return 1
}

@test "init --force preserves substantive DIFFERENTIATORS across PURPOSE regen" {
  mkdir -p .revive
  cat > .revive/static.md <<'EOF'
PURPOSE: old stale purpose
DIFFERENTIATORS:
  - Custom differentiator 1.
  - Custom differentiator 2.
INVARIANTS:
  - user rule 1
GOTCHAS:
  - user gotcha 1
EOF
  printf '{"description":"fresh purpose"}\n' > package.json
  run "$REVIVE" init --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIFFERENTIATORS/INVARIANTS/GOTCHAS preserved"* ]] || return 1
  run cat .revive/static.md
  [[ "$output" == *"Custom differentiator 1."* ]] || return 1
  [[ "$output" == *"Custom differentiator 2."* ]] || return 1
  [[ "$output" == *"user rule 1"* ]]              || return 1
  [[ "$output" == *"user gotcha 1"* ]]            || return 1
  [[ "$output" == *"fresh purpose"* ]]            || return 1
}

@test "suggest prompt introduces DIFFERENTIATORS as Deliverable 2" {
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deliverable 1 — PURPOSE"* ]]          || return 1
  [[ "$output" == *"Deliverable 2 — DIFFERENTIATORS"* ]]  || return 1
  [[ "$output" == *"Deliverable 3 — INVARIANTS"* ]]       || return 1
  [[ "$output" == *"Deliverable 4 — GOTCHAS"* ]]          || return 1
}

# v0.1.15 — section limits raised for projects with formal architecture
# rule series; hard-cap guidance updated to reference the real hook limit.
@test "suggest prompt does NOT cap INVARIANTS at 5" {
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  # Must not carry the old "up to 5" language on INVARIANTS
  printf '%s\n' "$output" | grep -F 'INVARIANTS (up to 5)' && return 1
  # Must mention the project-size heuristic that allows more
  printf '%s\n' "$output" | grep -qF 'formal architecture-rules ADR' || return 1
}

# v0.1.17 — audit is now a SEPARATE command/LLM call, not STEP 3 in suggest.
# Keeps the suggest prompt focused on generation, gives the audit a fresh
# context window, and avoids self-critique sycophancy.
@test "suggest prompt no longer embeds a STEP 3 audit pass" {
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  # The old STEP 3 in-place audit is gone — audit is its own command
  printf '%s\n' "$output" | grep -qF 'STEP 3 — Audit pass' && return 1
  true
}

@test "suggest prompt points users at the separate audit command" {
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'revive audit' || return 1
  printf '%s\n' "$output" | grep -qF 'FRESH'        || return 1
}

@test "audit prints a standalone prompt with a clear scope banner" {
  run "$REVIVE" audit
  [ "$status" -eq 0 ] || return 1
  printf '%s\n' "$output" | grep -qF 'Audit the STATIC sections'  || return 1
  printf '%s\n' "$output" | grep -qF 'EDIT ONLY STATIC sections'  || return 1
  printf '%s\n' "$output" | grep -qF 'Never touch DYNAMIC'        || return 1
  printf '%s\n' "$output" | grep -qF 'Never REWRITE an existing'  || return 1
}

@test "audit checklist names all six commonly-missed categories" {
  run "$REVIVE" audit
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Toolchain specifics'       || return 1
  printf '%s\n' "$output" | grep -qF 'knowledge-file discipline' || return 1
  printf '%s\n' "$output" | grep -qF 'Workflow dichotomies'      || return 1
  printf '%s\n' "$output" | grep -qF 'Privacy / OpSec'           || return 1
  printf '%s\n' "$output" | grep -qF 'Cross-ADR process'         || return 1
  printf '%s\n' "$output" | grep -qF 'Convention collisions'     || return 1
}

@test "audit output uses structured GAP / SECTION / PROPOSED BULLET format" {
  run "$REVIVE" audit
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'GAP:'             || return 1
  printf '%s\n' "$output" | grep -qF 'SECTION:'         || return 1
  printf '%s\n' "$output" | grep -qF 'PROPOSED BULLET:' || return 1
}

@test "audit forbids padding and documents 'no gaps' as a valid outcome" {
  # "Audit: no gaps found." wraps across lines in the prompt — assert each
  # half separately (both are line-complete after wrap).
  run "$REVIVE" audit
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Audit: no gaps'     || return 1
  printf '%s\n' "$output" | grep -qF 'pad with marginal'  || return 1
  printf '%s\n' "$output" | grep -qF 'valid outcome'      || return 1
}

@test "audit asks for confirmation before appending to the file" {
  run "$REVIVE" audit
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Append these N bullets' || return 1
  printf '%s\n' "$output" | grep -qF 'wait for my answer'     || return 1
}

@test "audit meta-hint on stderr references a FRESH session" {
  local stderr
  stderr=$("$REVIVE" audit 2>&1 >/dev/null)
  [[ "$stderr" == *"FRESH"* ]] || return 1
  [[ "$stderr" == *"pbcopy"* ]] || return 1
}

@test "audit appears in usage help" {
  run "$REVIVE" help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'audit' || return 1
}

@test "suggest prompt tells agent not to self-censor for aesthetic reasons" {
  # Aimed at the failure mode where agent caps at 5 INVARIANTS even
  # when the project has 9 canonical rules.
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Missing a rule because' || return 1
  printf '%s\n' "$output" | grep -qF "10,000"                  || return 1
}

@test "suggest prompt lists DIFFERENTIATORS placeholder marker" {
  # "what sets this project apart" wraps across two lines in the prompt;
  # assert the left half which is line-complete.
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'what sets this project' || return 1
}

@test "suggest prompt tells agent to preserve substantive sections across the board" {
  # Semantics: existing human-curated content in any STATIC section must
  # survive a re-run. Only placeholder sections get rewritten.
  # (String "preserved verbatim" is line-wrapped in the prompt; check
  # for the sentinel words on their own lines.)
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Treat existing human-' || return 1
  printf '%s\n' "$output" | grep -qF 'verbatim'              || return 1
  printf '%s\n' "$output" | grep -qF 'placeholder state'     || return 1
}

@test "suggest prompt lists placeholder markers for all three sections" {
  # Agent needs concrete markers to detect which sections are still
  # placeholders vs human-curated.
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'describe this project in 1-3 sentences' || return 1
  printf '%s\n' "$output" | grep -qF 'top-5 architectural rules'                || return 1
  printf '%s\n' "$output" | grep -qF 'landmines you keep stepping on'           || return 1
}

# Codex v0.1.13 P2a: the prompt header used to say "INVARIANTS and GOTCHAS"
# without mentioning PURPOSE, so the agent could ignore PURPOSE generation.
@test "suggest prompt header mentions PURPOSE as a deliverable" {
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  # The OPENING instruction must name PURPOSE, not only INVARIANTS/GOTCHAS.
  # Look in the first half of the prompt specifically.
  local head
  head=$(printf '%s\n' "$output" | head -10)
  [[ "$head" == *"PURPOSE"* ]] || return 1
}

# Codex v0.1.13 P2b: the "keep PURPOSE verbatim" path only works if the
# agent actually reads the current file. Ensure it's in the artefacts list.
@test "suggest prompt lists .revive/static.md as a bullet in the artefacts set" {
  # Must appear as an actual bullet entry ("  - .revive/static.md") inside
  # the "Files to read" block — not just in the STEP 2 instruction later.
  # Use grep -F (fixed string) to require that literal prefix+path combo.
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '  - .revive/static.md' || return 1
}

@test "suggest prompt tells agent to skip STEP 2 when nothing to fill" {
  # Full no-op path: if all three sections are already substantive, suggest
  # should short-circuit without editing the file. Prompt wraps across lines
  # so check the "Nothing to fill" sentinel and the "STEP 2 entirely" cue
  # separately (both are single-line).
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Nothing to fill'  || return 1
  printf '%s\n' "$output" | grep -qF 'STEP 2 entirely.' || return 1
}

@test "suggest prints meta-comment block on stderr only" {
  # The `# Paste this prompt ...` framing block goes to stderr so that
  # `revive suggest | pbcopy` doesn't ship framing into the clipboard.
  # (The prompt body itself may reference `pbcopy` / `revive audit` as
  # legitimate instructions to the agent — those belong on stdout.)
  local stdout stderr
  stdout=$("$REVIVE" suggest 2>/dev/null)
  stderr=$("$REVIVE" suggest 2>&1 >/dev/null)
  [[ "$stderr" == *"Paste this prompt into your current"* ]] || return 1
  [[ "$stdout" != *"Paste this prompt into your current"* ]] || return 1
}

@test "suggest lists CLAUDE.md when present" {
  echo "# Project" > CLAUDE.md
  run "$REVIVE" suggest
  [[ "$output" == *"- CLAUDE.md"* ]]
}

@test "suggest lists adr/ when present" {
  mkdir -p adr
  echo "# ADR 1" > adr/0001-foo.md
  run "$REVIVE" suggest
  [[ "$output" == *"adr/*.md"* ]]
}

@test "suggest lists HOT_FILES from recent commits" {
  echo a > foo.rb
  git add foo.rb
  git commit -qm "add foo"
  echo b >> foo.rb
  git add foo.rb
  git commit -qm "update foo"
  run "$REVIVE" suggest
  [[ "$output" == *"HOT_FILES"* ]]
  [[ "$output" == *"foo.rb"* ]]
}

@test "suggest output is self-contained (no revive-internal jargon in prompt body)" {
  run "$REVIVE" suggest
  # the prompt sent to the LLM must reference .revive/static.md explicitly
  # so it works when pasted fresh into any agent
  [[ "$output" == *".revive/static.md"* ]]
}

@test "init rejects unknown options" {
  run "$REVIVE" init --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "init uses README.md prose for PURPOSE" {
  printf '# My Project\n\nBuilds dense briefs for agents.\n' > README.md
  "$REVIVE" init
  run cat .revive/static.md
  [[ "$output" == *"Builds dense briefs"* ]]
}

# --- cadence ---

@test "refresh emits on first call" {
  run "$REVIVE" refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"<revive refresh=\"1\">"* ]]
}

@test "refresh skips calls 2-4, emits on call 5" {
  "$REVIVE" refresh >/dev/null
  run "$REVIVE" refresh
  [ -z "$output" ]
  run "$REVIVE" refresh
  [ -z "$output" ]
  run "$REVIVE" refresh
  [ -z "$output" ]
  run "$REVIVE" refresh
  [[ "$output" == *"<revive refresh=\"5\">"* ]]
}

@test "counter file persists N and epoch" {
  "$REVIVE" refresh >/dev/null
  [ -f ".claude/revive-counter" ]
  run cat .claude/revive-counter
  [[ "$output" =~ ^[0-9]+:[0-9]+$ ]]
}

@test "refresh always exits 0 (silent failure contract)" {
  # break cwd permissions to force filesystem errors
  chmod 000 .claude 2>/dev/null || true
  run "$REVIVE" refresh
  chmod 755 .claude 2>/dev/null || true
  [ "$status" -eq 0 ]
}

# --- install-hook ---

@test "install-hook creates .claude/settings.json when missing" {
  run "$REVIVE" install-hook
  [ "$status" -eq 0 ]
  [ -f ".claude/settings.json" ]
}

@test "install-hook adds UserPromptSubmit entry" {
  "$REVIVE" install-hook
  run cat .claude/settings.json
  [[ "$output" == *"UserPromptSubmit"* ]]
  [[ "$output" == *"revive refresh"* ]]
}

@test "install-hook is idempotent" {
  "$REVIVE" install-hook
  run "$REVIVE" install-hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  # should still only be one entry
  local count
  count=$(grep -c 'revive refresh' .claude/settings.json)
  [ "$count" -eq 1 ]
}

@test "install-hook preserves existing settings keys" {
  mkdir -p .claude
  printf '{"theme":"dark"}\n' > .claude/settings.json
  "$REVIVE" install-hook
  run cat .claude/settings.json
  [[ "$output" == *"theme"* ]]
  [[ "$output" == *"UserPromptSubmit"* ]]
}

# --- doctor ---

@test "doctor fails when .revive/static.md is missing" {
  run "$REVIVE" doctor
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"FAIL"* ]] || return 1
  [[ "$output" == *".revive/static.md missing"* ]] || return 1
}

@test "doctor passes (with PURPOSE warn) right after init" {
  "$REVIVE" init
  run "$REVIVE" doctor
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"PURPOSE is still placeholder"* ]] || return 1
}

@test "doctor reports filled PURPOSE as OK once user edits static.md" {
  "$REVIVE" init
  # replace the placeholder line with a real one-liner
  awk '/\(describe this project/{print "Real purpose for the project."; next}1' \
    .revive/static.md > .revive/static.md.new
  mv .revive/static.md.new .revive/static.md
  run "$REVIVE" doctor
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"PURPOSE is filled in"* ]] || return 1
}

@test "doctor warns when no UserPromptSubmit hook is installed" {
  "$REVIVE" init
  run "$REVIVE" doctor
  [[ "$output" == *"no UserPromptSubmit hook found"* ]] || return 1
}

@test "doctor detects hook in local .claude/settings.json" {
  "$REVIVE" init
  "$REVIVE" install-hook
  run "$REVIVE" doctor
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"UserPromptSubmit hook installed in .claude/settings.json"* ]] || return 1
  [[ "$output" == *"PostCompact hook installed in .claude/settings.json"* ]] || return 1
  [[ "$output" != *"no UserPromptSubmit hook found"* ]] || return 1
  [[ "$output" != *"no PostCompact hook found"* ]] || return 1
}

@test "doctor warns when only UserPromptSubmit is wired (upgrade gap)" {
  # Simulates an upgraded install: settings.json has the legacy
  # UserPromptSubmit entry but PostCompact has not been added yet.
  "$REVIVE" init
  mkdir -p .claude
  cat > .claude/settings.json <<'JSON'
{ "hooks": { "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "revive refresh" } ] } ] } }
JSON
  run "$REVIVE" doctor
  [[ "$output" == *"UserPromptSubmit hook installed"* ]] || return 1
  [[ "$output" == *"no PostCompact hook found"* ]] || return 1
}

@test "doctor appears in usage help" {
  run "$REVIVE" help
  [[ "$output" == *"doctor"* ]] || return 1
}

# --- post-compact trigger ---

@test "mark-compact writes signal file in .claude/" {
  mkdir -p .claude
  run "$REVIVE" mark-compact
  [ "$status" -eq 0 ] || return 1
  [ -f .claude/revive-compact.signal ] || return 1
}

@test "mark-compact silently exits 0 when .claude/ cannot be created" {
  # parent dir un-writable: hook must still succeed (silent-failure contract)
  chmod -w .
  run "$REVIVE" mark-compact
  chmod +w .
  [ "$status" -eq 0 ] || return 1
}

@test "refresh emits immediately when post-compact signal exists" {
  # bump cadence so we'd normally skip — signal must override
  mkdir -p .claude
  : > .claude/revive-compact.signal
  REVIVE_REFRESH_EVERY=999 REVIVE_REFRESH_TIME_GAP=99999 \
    run "$REVIVE" refresh
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"<revive refresh="* ]] || return 1
}

@test "refresh removes the signal after consuming it" {
  mkdir -p .claude
  : > .claude/revive-compact.signal
  "$REVIVE" refresh >/dev/null
  [ ! -f .claude/revive-compact.signal ] || return 1
}

@test "post-compact emit advances the cadence counter" {
  # signal forces emit; counter must still tick so subsequent calls behave normally
  mkdir -p .claude
  : > .claude/revive-compact.signal
  "$REVIVE" refresh >/dev/null
  [ -f .claude/revive-counter ] || return 1
  run cat .claude/revive-counter
  [[ "$output" == 1:* ]] || return 1
}

@test "install-hook adds PostCompact entry alongside UserPromptSubmit" {
  "$REVIVE" install-hook
  run cat .claude/settings.json
  [[ "$output" == *"UserPromptSubmit"* ]] || return 1
  [[ "$output" == *"PostCompact"* ]] || return 1
  [[ "$output" == *"revive refresh"* ]] || return 1
  [[ "$output" == *"revive mark-compact"* ]] || return 1
}

@test "install-hook is idempotent for both hooks" {
  "$REVIVE" install-hook
  "$REVIVE" install-hook
  # exactly one of each, even after a second install
  local rc cc
  rc=$(grep -c 'revive refresh' .claude/settings.json)
  cc=$(grep -c 'revive mark-compact' .claude/settings.json)
  [ "$rc" -eq 1 ] || return 1
  [ "$cc" -eq 1 ] || return 1
}

@test "mark-compact appears in usage help" {
  run "$REVIVE" help
  [[ "$output" == *"mark-compact"* ]] || return 1
}
