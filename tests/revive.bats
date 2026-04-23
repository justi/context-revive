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
  [[ "$output" == *"HOT_FILES:"* ]]
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

@test "hot_files reports no-history when repo is empty" {
  # nuke initial commit to get a genuinely empty repo
  rm -rf .git
  git init -q
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

@test "brief stays under 1500 chars even with rich history" {
  for i in $(seq 1 15); do
    echo "$i" > "file$i.rb"
    git add "file$i.rb"
    git commit -qm "add file$i with a reasonably descriptive commit message"
  done
  run "$REVIVE" show
  [ "${#output}" -lt 1500 ]
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
