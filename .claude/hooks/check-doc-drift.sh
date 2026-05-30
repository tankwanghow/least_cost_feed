#!/usr/bin/env bash
# Claude Code PostToolUse hook: after a `git commit`, detect when code changed
# but docs (CLAUDE.md / codebase-map skill) did not, and tell Claude to review.
# This script is a detector only — it never edits files.
set -uo pipefail

CODE_RE='^(lib/.*\.ex|priv/repo/migrations/.*\.exs)$'
DOC_RE='^(CLAUDE\.md|\.claude/skills/codebase-map/SKILL\.md)$'

input="$(cat)"

command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
# Match the `commit` subcommand for both `git commit ...` and
# `git -C <path> commit ...`; ignore everything else (e.g. `git log`).
if ! [[ "$command" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$) ]]; then
  exit 0
fi

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
