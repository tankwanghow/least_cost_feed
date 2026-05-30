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
