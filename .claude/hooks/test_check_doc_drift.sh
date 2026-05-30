#!/usr/bin/env bash
# Test harness for check-doc-drift.sh. Creates throwaway git repos,
# feeds fake PostToolUse JSON to the hook, and asserts on stdout.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-doc-drift.sh"

fails=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails+1)); }

# Track throwaway repos and remove them on exit.
TMP_REPOS=()
cleanup() { for d in "${TMP_REPOS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# run_hook <repo_dir> <command-string> -> echoes hook stdout
run_hook() {
  local repo="$1" cmd="$2"
  local json
  json="$(jq -n --arg c "$cmd" --arg d "$repo" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}')"
  printf '%s' "$json" | bash "$HOOK"
}

new_repo() {
  local d; d="$(mktemp -d)"
  TMP_REPOS+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  printf '%s' "$d"
}

commit() { # <repo> <msg>
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# --- Case 1: code changed, docs not -> drift message naming the file
r="$(new_repo)"
mkdir -p "$r/lib/app"; echo "v1" > "$r/lib/app/foo.ex"; commit "$r" "init"
echo "v2" > "$r/lib/app/foo.ex"; commit "$r" "change code"
out="$(run_hook "$r" "git commit -m 'change code'")"
if echo "$out" | jq -e '.hookSpecificOutput.additionalContext | test("lib/app/foo.ex")' >/dev/null 2>&1; then
  pass "code-only change emits drift context naming the file"
else
  fail "code-only change should emit drift context (got: $out)"
fi

# --- Case 2: code + CLAUDE.md changed -> silent
r="$(new_repo)"
mkdir -p "$r/lib"; echo "v1" > "$r/lib/foo.ex"; echo "doc" > "$r/CLAUDE.md"; commit "$r" "init"
echo "v2" > "$r/lib/foo.ex"; echo "doc2" > "$r/CLAUDE.md"; commit "$r" "code+doc"
out="$(run_hook "$r" "git commit -m 'code+doc'")"
[ -z "$out" ] && pass "code + CLAUDE.md change is silent" || fail "expected silence, got: $out"

# --- Case 3: code + skill changed -> silent
r="$(new_repo)"
mkdir -p "$r/lib" "$r/.claude/skills/codebase-map"
echo "v1" > "$r/lib/foo.ex"; echo "s" > "$r/.claude/skills/codebase-map/SKILL.md"; commit "$r" "init"
echo "v2" > "$r/lib/foo.ex"; echo "s2" > "$r/.claude/skills/codebase-map/SKILL.md"; commit "$r" "code+skill"
out="$(run_hook "$r" "git commit -m 'code+skill'")"
[ -z "$out" ] && pass "code + skill change is silent" || fail "expected silence, got: $out"

# --- Case 4: non-code change only -> silent
r="$(new_repo)"
mkdir -p "$r/docs"; echo "a" > "$r/docs/readme.md"; commit "$r" "init"
echo "b" > "$r/docs/readme.md"; commit "$r" "docs only"
out="$(run_hook "$r" "git commit -m 'docs only'")"
[ -z "$out" ] && pass "non-code change is silent" || fail "expected silence, got: $out"

# --- Case 5: migration change counts as code -> drift message
r="$(new_repo)"
mkdir -p "$r/priv/repo/migrations"; echo "x" > "$r/priv/repo/migrations/001_init.exs"; commit "$r" "init"
echo "y" > "$r/priv/repo/migrations/001_init.exs"; commit "$r" "migration"
out="$(run_hook "$r" "git commit -m 'migration'")"
echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && pass "migration change emits drift context" || fail "expected drift for migration, got: $out"

# --- Case 6: root commit (no HEAD~1) -> silent, no error
r="$(new_repo)"
mkdir -p "$r/lib"; echo "v1" > "$r/lib/foo.ex"; commit "$r" "root"
out="$(run_hook "$r" "git commit -m 'root'")"
[ -z "$out" ] && pass "root commit is silent" || fail "expected silence on root commit, got: $out"

# --- Case 7: non-git-commit command -> silent
r="$(new_repo)"
mkdir -p "$r/lib"; echo "v1" > "$r/lib/foo.ex"; commit "$r" "init"
echo "v2" > "$r/lib/foo.ex"; commit "$r" "c2"
out="$(run_hook "$r" "git status")"
[ -z "$out" ] && pass "non-commit command is silent" || fail "expected silence for non-commit, got: $out"

# --- Case 8: `git -C <path> commit` form is recognized -> drift message
r="$(new_repo)"
mkdir -p "$r/lib"; echo "v1" > "$r/lib/foo.ex"; commit "$r" "init"
echo "v2" > "$r/lib/foo.ex"; commit "$r" "code"
out="$(run_hook "$r" "git -C $r commit -m 'code'")"
echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && pass "git -C <path> commit form emits drift context" || fail "expected drift for 'git -C' form, got: $out"

# --- Case 9: a git command that merely mentions 'commit' does not misfire
r="$(new_repo)"
mkdir -p "$r/lib"; echo "v1" > "$r/lib/foo.ex"; commit "$r" "init"
echo "v2" > "$r/lib/foo.ex"; commit "$r" "c2"
out="$(run_hook "$r" "git log --grep commit")"
[ -z "$out" ] && pass "non-commit 'git log --grep commit' is silent" || fail "expected silence for 'git log', got: $out"

echo "---"
if [ "$fails" -eq 0 ]; then echo "ALL TESTS PASSED"; exit 0; else echo "$fails TEST(S) FAILED"; exit 1; fi
