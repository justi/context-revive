#!/usr/bin/env bats
# Run with: bats tests/

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
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  [[ "$output" == *"INVARIANTS"* ]]
  [[ "$output" == *"GOTCHAS"* ]]
  [[ "$output" == *"non-inferable"* ]]
  # meta-comments must go to stderr, not stdout — so `| pbcopy` stays clean
  [[ "$output" != *"Paste this prompt"* ]]
  [[ "$output" != *"BEGIN PROMPT"* ]]
}

@test "suggest prompt instructs agent to edit .revive/static.md end-to-end" {
  run "$REVIVE" suggest
  [ "$status" -eq 0 ]
  # step 1: preview
  [[ "$output" == *"STEP 1"* ]]
  [[ "$output" == *"preview"* ]]
  # step 2: edit the file in place
  [[ "$output" == *"STEP 2"* ]]
  [[ "$output" == *".revive/static.md"* ]]
  # guard against creating the file if it doesn't exist
  [[ "$output" == *"revive init"* ]]
}

@test "suggest prints pipe-to-clipboard hint on stderr only" {
  local stdout stderr
  stdout=$("$REVIVE" suggest 2>/dev/null)
  stderr=$("$REVIVE" suggest 2>&1 >/dev/null)
  [[ "$stderr" == *"pbcopy"* ]]
  [[ "$stdout" != *"pbcopy"* ]]
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
