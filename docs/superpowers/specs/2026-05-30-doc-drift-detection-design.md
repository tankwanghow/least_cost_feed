# Doc-Drift Detection on Commit — Design

**Date:** 2026-05-30
**Status:** Approved (pending spec review)

## Goal

Keep the project's documentation following the code. When a commit changes
code but leaves the docs untouched, surface the *candidate* drift to Claude,
which then confirms whether the docs are genuinely stale and **asks the user's
permission before updating** them.

Two artifacts are kept in sync with the code:

1. `CLAUDE.md` (root project doc)
2. A new project skill: `.claude/skills/codebase-map/SKILL.md`

## Mechanism

A git commit can be observed two ways; only one can drive the
review-and-ask-permission flow:

- **Claude Code `PostToolUse` hook** matching `Bash` calls whose command
  contains `git commit`. After the commit lands, a script runs and can inject a
  message back into the conversation. **This is the chosen mechanism.**
- A native `.git/hooks/post-commit` script fires on *any* commit but runs in
  the shell and cannot reach Claude, so it cannot drive the flow. Not used in
  the core build.

**Known limitation:** the hook only fires for commits made through Claude's
Bash tool. Commits made in the user's own terminal will not trigger it. An
optional native `post-commit` that drops a flag file (surfaced at next session
start) is a possible future add-on, explicitly out of scope here.

## Components

### 1. `.claude/hooks/check-doc-drift.sh` (tracked in repo)

Deterministic *candidate* detector. It never edits anything. On a commit it:

- Reads the just-made commit's changed files: `git diff --name-only HEAD~1 HEAD`.
  (Handles the root-commit case where `HEAD~1` does not exist — exit silently.)
- `CODE_CHANGED` = any changed path matching `lib/**/*.ex`,
  `priv/repo/migrations/**`, or `lib/least_cost_feed_web/router.ex`.
- `DOCS_CHANGED` = whether `CLAUDE.md` or
  `.claude/skills/codebase-map/SKILL.md` appear in the same changed-file list.
- If `CODE_CHANGED` is true and `DOCS_CHANGED` is false: print an
  `additionalContext` payload naming the commit SHA and the changed code files,
  instructing Claude to review for drift.
- Otherwise: exit 0 silently (no output).

The script reads the `PostToolUse` JSON on stdin to confirm the triggering
command was a `git commit` (defense in depth beyond the matcher).

### 2. `.claude/settings.json` — hook wiring

Add a `PostToolUse` hook entry with matcher `Bash` that runs the script. This is
added alongside the existing `permissions` block; the permissions block is not
modified or removed.

### 3. `.claude/skills/codebase-map/SKILL.md` — new project skill

An architecture / codebase-map skill: module layout, the optimization flow, and
key-file responsibilities — a deeper companion to `CLAUDE.md`. It is also the
second artifact the drift check watches. The skill self-documents the
drift-tracking rule (what content is considered code-derived) so the rule lives
with the code.

## Flow When Drift Is Suspected

1. Claude commits a change touching `lib/`.
2. Hook fires and injects: *"Commit `<sha>` changed `lib/...` but not CLAUDE.md /
   codebase-map. Review for drift."*
3. Claude runs `git show <sha>` and compares the real change against the docs'
   claims.
4. If docs are genuinely stale: Claude states exactly what is out of date and
   **asks permission** to update, then edits (the edit-permission prompt is a
   second backstop). The doc fix lands as a follow-up commit.
5. If no real drift (e.g. an internal refactor with no documented-behavior
   change): Claude says so and does nothing.

## Drift-Tracked Content

- **`CLAUDE.md`:** the Architecture file-responsibility list, Common Commands,
  Optimization Flow, and Tech Stack sections. Free-form prose (e.g. Project
  Overview) is not force-synced.
- **Skill:** module map + optimization flow.

## Out of Scope (YAGNI)

- No auto-rewrite of docs without asking.
- No syncing of memory files.
- No coverage of commits made outside Claude Code (optional add-on only).

## Acceptance Criteria

- Committing a change to a `lib/**/*.ex` file without touching the docs causes
  Claude to receive a drift-candidate message naming the commit and files.
- Committing a change that also updates `CLAUDE.md` (or the skill) produces no
  drift message.
- Committing changes only to non-code paths (e.g. `docs/`, `assets/`) produces
  no drift message.
- The root-commit / missing-`HEAD~1` case does not error.
- The existing `permissions` block in `.claude/settings.json` is preserved.
- The `codebase-map` skill exists and accurately reflects the current `lib/`
  layout and optimization flow at creation time.
