#!/usr/bin/env bats
# Run with: bats tests/

setup() {
  REVIVE="${BATS_TEST_DIRNAME}/../bin/revive"
  WORKDIR="${BATS_TEST_DIRNAME}/../.tmp-test-$$-${BATS_TEST_NUMBER}"
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"
  git init -q
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
  [[ "$output" == *"TODO:"* ]]
  [[ "$output" == *"MODULES:"* ]]
}

@test "show reports git branch in STATE" {
  run "$REVIVE" show
  [[ "$output" == *"branch="* ]]
}

@test "brief stays under 1500-char budget on minimal repo" {
  run "$REVIVE" show
  # show prints budget line to stderr; the brief is stdout
  local brief_len=${#output}
  [ "$brief_len" -lt 1500 ]
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
