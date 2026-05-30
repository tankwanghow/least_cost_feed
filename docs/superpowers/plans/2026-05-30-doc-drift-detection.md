# Doc-Drift Detection on Commit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a `git commit` made through Claude's Bash tool, automatically detect when code changed but the docs (`CLAUDE.md` / the codebase-map skill) did not, and surface that to Claude so it can confirm real drift and ask permission to update.

**Architecture:** A Claude Code `PostToolUse` hook matches `Bash` calls containing `git commit` and runs a deterministic shell script. The script diffs the just-made commit, and if `lib/**/*.ex` or migrations changed without a matching doc change, it emits `hookSpecificOutput.additionalContext` instructing Claude to review for drift. The script never edits anything. A new `codebase-map` project skill is the second drift-tracked artifact.

**Tech Stack:** Bash 5.2, `jq`, git, Claude Code hooks (`PostToolUse`), Markdown skill file.

---

## File Structure

- **Create** `.claude/hooks/check-doc-drift.sh` — the candidate-drift detector. Reads PostToolUse JSON on stdin, diffs the last commit, emits `additionalContext` when code changed without docs. One responsibility: detection + messaging. Never mutates files.
- **Create** `.claude/hooks/test_check_doc_drift.sh` — standalone bash test harness. Builds throwaway git repos in `mktemp -d`, feeds fake hook JSON to the script, asserts stdout. One responsibility: verify the detector.
- **Modify** `.claude/settings.json` — add a `hooks.PostToolUse` entry (matcher `Bash`) wiring the script. Existing `permissions` block preserved.
- **Create** `.claude/skills/codebase-map/SKILL.md` — architecture/codebase-map project skill; the second drift-tracked artifact; self-documents the drift rule.
- **Modify** `CLAUDE.md` — add a short "Documentation drift detection" subsection so the workflow is discoverable.

Note: implementing this plan only touches `.claude/`, `CLAUDE.md`, and `docs/` — never `lib/` — so the work itself will not trigger the drift hook.

---

## Task 1: Drift-detection script (with test harness)

**Files:**
- Create: `.claude/hooks/test_check_doc_drift.sh`
- Create: `.claude/hooks/check-doc-drift.sh`

- [ ] **Step 1: Write the failing test harness**

Create `.claude/hooks/test_check_doc_drift.sh`:

```bash
#!/usr/bin/env bash
# Test harness for check-doc-drift.sh. Creates throwaway git repos,
# feeds fake PostToolUse JSON to the hook, and asserts on stdout.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-doc-drift.sh"

fails=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails+1)); }

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

echo "---"
if [ "$fails" -eq 0 ]; then echo "ALL TESTS PASSED"; exit 0; else echo "$fails TEST(S) FAILED"; exit 1; fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash .claude/hooks/test_check_doc_drift.sh`
Expected: FAIL — the harness errors / all cases fail because `check-doc-drift.sh` does not exist yet (e.g. `bash: .../check-doc-drift.sh: No such file or directory`), ending with `TEST(S) FAILED` and a non-zero exit.

- [ ] **Step 3: Write the script**

Create `.claude/hooks/check-doc-drift.sh`:

```bash
#!/usr/bin/env bash
# Claude Code PostToolUse hook: after a `git commit`, detect when code changed
# but docs (CLAUDE.md / codebase-map skill) did not, and tell Claude to review.
# This script is a detector only — it never edits files.
set -uo pipefail

CODE_RE='^(lib/.*\.ex|priv/repo/migrations/.*)$'
DOC_RE='^(CLAUDE\.md|\.claude/skills/codebase-map/SKILL\.md)$'

input="$(cat)"

command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
case "$command" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

# Need a parent commit to diff against; skip the root-commit case.
git rev-parse --verify HEAD~1 >/dev/null 2>&1 || exit 0

changed="$(git diff --name-only HEAD~1 HEAD)"

code_files="$(printf '%s\n' "$changed" | grep -E "$CODE_RE" || true)"
doc_hits="$(printf '%s\n' "$changed" | grep -Ec "$DOC_RE" || true)"

if [ -n "$code_files" ] && [ "$doc_hits" -eq 0 ]; then
  sha="$(git rev-parse --short HEAD)"
  files="$(printf '%s' "$code_files" | paste -sd, -)"
  msg="Commit ${sha} changed code (${files}) but did not update CLAUDE.md or .claude/skills/codebase-map/SKILL.md. Run 'git show ${sha}' and compare against the documented architecture, Common Commands, and Optimization Flow. If the docs are genuinely stale, tell the user exactly what is out of date and ask permission before updating CLAUDE.md and the codebase-map skill. If it is an internal refactor with no documented-behavior change, do nothing."
  jq -n --arg ctx "$msg" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
fi

exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash .claude/hooks/test_check_doc_drift.sh`
Expected: 7 `PASS:` lines and `ALL TESTS PASSED`, exit 0.

- [ ] **Step 5: Make the script executable and commit**

```bash
chmod +x .claude/hooks/check-doc-drift.sh .claude/hooks/test_check_doc_drift.sh
git add .claude/hooks/check-doc-drift.sh .claude/hooks/test_check_doc_drift.sh
git commit -m "Add doc-drift detector script and tests"
```

---

## Task 2: Wire the PostToolUse hook into settings.json

**Files:**
- Modify: `.claude/settings.json`

- [ ] **Step 1: Write the failing test**

Run this verification command (it is the test for this task):

```bash
jq -e '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[] | select(.command | test("check-doc-drift.sh"))' .claude/settings.json
```

Expected now: FAIL (no output / exit 1) — the hook is not wired yet. Also confirm permissions still parse: `jq -e '.permissions.allow | length > 0' .claude/settings.json` should print a number > 0.

- [ ] **Step 2: Add the hook entry**

Edit `.claude/settings.json` so it has BOTH the existing `permissions` block (unchanged) and a new `hooks` block. The resulting top-level shape:

```json
{
  "permissions": { "allow": [ "...existing entries, leave exactly as-is..." ] },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/check-doc-drift.sh\""
          }
        ]
      }
    ]
  }
}
```

Do this as a precise edit: add a `,` after the closing `}` of the `permissions` value, then insert the `"hooks": { ... }` key. Do not retype or reorder the `permissions.allow` array.

- [ ] **Step 3: Run the test to verify it passes**

Run: `jq -e '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[] | select(.command | test("check-doc-drift.sh"))' .claude/settings.json`
Expected: PASS — prints the matching hook object, exit 0.
Also run: `jq -e '.permissions.allow | length > 0' .claude/settings.json`
Expected: prints the original count (permissions preserved).

- [ ] **Step 4: Commit**

```bash
git add .claude/settings.json
git commit -m "Wire PostToolUse hook for doc-drift detection"
```

---

## Task 3: Create the codebase-map skill

**Files:**
- Create: `.claude/skills/codebase-map/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `.claude/skills/codebase-map/SKILL.md` with this exact content:

````markdown
---
name: codebase-map
description: Use when navigating or modifying the LeastCostFeed codebase - maps module layout, the optimization flow, and key-file responsibilities. Kept in sync with lib/ via the doc-drift hook.
---

# LeastCostFeed Codebase Map

A deeper companion to `CLAUDE.md` for navigating `lib/`. When code under `lib/`
changes, the doc-drift hook (`.claude/hooks/check-doc-drift.sh`) flags this file
and `CLAUDE.md` for review.

## Domain layer — `lib/least_cost_feed/`

- `entities.ex` — core context: all user-scoped CRUD, queries, cost-sync logic.
- `entities/` — Ecto schemas: `formula.ex`, `formula_ingredient.ex`,
  `formula_nutrient.ex`, `formula_premix_ingredient.ex`, `formula_version.ex`,
  `ingredient.ex`, `ingredient_composition.ex`, `nutrient.ex`.
- `glpsol_file_gen.ex` — generates MathProg `.mod` content, pipes it to
  `glpsol --math /dev/stdin`, parses solver output (proportions, actual nutrient
  values, shadow prices). Returns `{:ok, ingredients, nutrients}` or
  `{:error, reason, output}`.
- `nutrient_relaxer.ex` — elastic-slack relaxation to diagnose infeasible
  formulas (which constraints to loosen and by how much).
- `efc_predict.ex` — egg/feed prediction support.
- `user_accounts.ex` / `user_accounts/` — auth (bcrypt, session tokens, email
  confirmation): `user.ex`, `user_token.ex`, `user_notifier.ex`.
- `helpers.ex`, `mailer.ex`, `repo.ex`, `release.ex`, `application.ex` —
  support/infra.

## Web layer — `lib/least_cost_feed_web/`

- `router.ex` — public auth routes + authenticated routes (nutrients,
  ingredients, formulas, premix, transfer, print).
- `live/formula_live/` — formula CRUD (`form.ex`, `index.ex`), optimization,
  premix batches (`premix.ex`), printing (`formula_print.ex`,
  `premix_print.ex`), comparison (`compare.ex`), infeasibility relaxation
  (`nutrient_relax.ex`, `multi_nutrient_relax.ex`), version history
  (`version_history.ex`), nutrition guide (`nutrition_guide.ex`), EFC
  (`efc_form.ex`).
- `live/ingredient_live/` — ingredient CRUD with composition editor
  (`form.ex`), listing (`index.ex`), cross-formula usage (`usage.ex`),
  comparison (`compare.ex`), nutrient picker (`select_component.ex`).
- `live/nutrient_live/` — nutrient CRUD (`form.ex`, `index.ex`) + reusable
  `select_component.ex`.
- `live/transfer_live/form.ex` — CSV import.
- `live/helpers.ex`, `live/compare_helpers.ex` — shared LiveView utilities
  (add/delete line, sorting, float parse/format, compare-cell rendering).
- `components/my_components.ex` — custom UI (`search_form`, sortable streamed
  `table`, `infinite_scroll_footer`); `core_components.ex`, `layouts.ex`.
- `user_auth.ex`, `controllers/`, `endpoint.ex`, `telemetry.ex`, `gettext.ex`.

## Optimization flow

1. User edits a formula with ingredient bounds (min/max %) and nutrient
   constraints (min/max).
2. "Try Optimize" → `GlpsolFileGen.optimize/2` builds a MathProg model:
   minimize Σ(cost × proportion) subject to ingredient + nutrient constraints.
3. Model piped to `glpsol --math /dev/stdin`.
4. Output parsed; proportions / actual nutrients / shadow prices shown live via
   LiveView. If infeasible, `nutrient_relaxer.ex` diagnoses which constraints to
   relax.

## Drift-tracked content (keep current with code)

Update this skill and `CLAUDE.md` when these change in `lib/`:
- module/file responsibilities above,
- the optimization flow,
- Common Commands and Tech Stack (in `CLAUDE.md`).

Internal refactors that do not change documented behavior need no doc update.
````

- [ ] **Step 2: Verify the skill is valid**

Run: `head -5 .claude/skills/codebase-map/SKILL.md`
Expected: shows the YAML frontmatter with `name: codebase-map` and a `description:` line.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/codebase-map/SKILL.md
git commit -m "Add codebase-map project skill"
```

---

## Task 4: Document the drift workflow in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a subsection**

Append this subsection under the `## Architecture` section's end (before `## Tech Stack`) in `CLAUDE.md`:

```markdown
### Documentation Drift Detection

A `PostToolUse` hook (`.claude/hooks/check-doc-drift.sh`) runs after each
`git commit` made through Claude's Bash tool. If the commit changed
`lib/**/*.ex` or a migration but did not update `CLAUDE.md` or
`.claude/skills/codebase-map/SKILL.md`, the hook asks Claude to review for
drift and request permission before updating the docs. It only fires for
commits made via Claude Code (not the user's own terminal).
```

- [ ] **Step 2: Verify**

Run: `grep -n "Documentation Drift Detection" CLAUDE.md`
Expected: prints the heading line.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Document doc-drift detection workflow in CLAUDE.md"
```

---

## Task 5: End-to-end manual verification (no leftover artifacts)

**Files:** none created.

- [ ] **Step 1: Simulate a code-only commit and run the hook against it**

```bash
echo "# drift test $(date +%s)" >> lib/least_cost_feed.ex
git add lib/least_cost_feed.ex
git commit -m "TEMP: drift hook e2e test"
jq -n --arg c "git commit -m x" --arg d "$PWD" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
  | bash .claude/hooks/check-doc-drift.sh
```

Expected: a JSON object whose `.hookSpecificOutput.additionalContext` mentions
`lib/least_cost_feed.ex` and the short commit SHA.

- [ ] **Step 2: Undo the throwaway commit**

```bash
git reset --hard HEAD~1
```

Expected: `lib/least_cost_feed.ex` restored, the TEMP commit gone
(`git log --oneline -1` shows the Task 4 commit).

- [ ] **Step 3: Confirm the full suite still passes**

Run: `bash .claude/hooks/test_check_doc_drift.sh`
Expected: `ALL TESTS PASSED`.

---

## Notes for the implementer

- DRY/YAGNI: the script is a *detector only* — resist adding any file-editing
  logic; the review + permission step is Claude's job at runtime.
- The `additionalContext` field under `hookSpecificOutput` is the supported way
  a `PostToolUse` hook feeds text back into the conversation. If the running
  Claude Code version surfaces it differently, the JSON shape stays the same;
  do not switch to exit-code-2 (that path is for *blocking* errors, not advice).
- Keep the `CODE_RE` / `DOC_RE` patterns in `check-doc-drift.sh` and the paths
  referenced in the skill and `CLAUDE.md` in agreement.
