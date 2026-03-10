# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LeastCostFeed is a Phoenix LiveView application for optimizing animal feed formulas using linear programming. Users define ingredients (with costs and nutrient compositions), set nutritional constraints, and the system finds the minimum-cost formula satisfying all constraints via the GLPK solver (`glpsol`).

## Common Commands

```bash
mix setup              # Install deps, create DB, run migrations, seed data
mix phx.server         # Start dev server at localhost:4000
mix test               # Run all tests (auto-creates/migrates test DB)
mix test test/path_test.exs          # Run a single test file
mix test test/path_test.exs:42       # Run a specific test by line number
mix credo              # Run linter
mix assets.deploy      # Build production assets (Tailwind + esbuild)
```

**Requirement:** `glpsol` (from `glpk-utils`) must be installed on the system for formula optimization.

## Architecture

### Domain Layer (`lib/least_cost_feed/`)

- **`entities.ex`** — Core context module with all CRUD operations, queries, and cost-sync logic. All data is **user-scoped** (isolated per user).
- **`entities/`** — Ecto schemas: `Formula`, `FormulaIngredient`, `FormulaNutrient`, `FormulaPremixIngredient`, `Ingredient`, `IngredientComposition`, `Nutrient`.
- **`glpsol_file_gen.ex`** — Generates MathProg `.mod` content and pipes it to `glpsol --math /dev/stdin`. Parses solver output to extract optimized ingredient proportions, actual nutrient values, and shadow prices. Returns `{:ok, ingredients, nutrients}` or `{:error, reason, output}`.
- **`user_accounts.ex` / `user_accounts/`** — Authentication context (bcrypt, session tokens, email confirmation).

### Web Layer (`lib/least_cost_feed_web/`)

- **`router.ex`** — Routes: public auth routes + authenticated routes for nutrients, ingredients, formulas, premix, transfer, and print views.
- **`live/formula_live/`** — Formula CRUD, optimization ("Try Optimize" calls `GlpsolFileGen.optimize/2`), premix batch calculations, and print views.
- **`live/ingredient_live/`** — Ingredient CRUD with nutrient composition editor and cross-formula usage tracking.
- **`live/nutrient_live/`** — Nutrient CRUD with a reusable `SelectComponent` for picking nutrients.
- **`live/transfer_live/`** — CSV data import functionality.
- **`live/helpers.ex`** — Shared LiveView utilities: `add_line`, `delete_line`, sorting, float parsing/formatting.
- **`components/my_components.ex`** — Custom UI components: `search_form`, sortable `table` with streams, `infinite_scroll_footer`.

### Optimization Flow

1. User edits formula with ingredient bounds (min/max %) and nutrient constraints (min/max)
2. "Try Optimize" generates a MathProg model: minimize Σ(cost × proportion) subject to ingredient and nutrient constraints
3. Model is piped to `glpsol --math /dev/stdin`
4. Results parsed and displayed in real-time via LiveView

### Key Patterns

- All entities use **Ecto changesets** with `cast_assoc` for nested associations (formula ingredients/nutrients).
- **Cost propagation:** When an ingredient's cost changes, a transaction updates all `formula_ingredients` referencing it.
- Formulas compute cost per 1000 weight units via SQL fragment in queries.
- LiveView forms use `inputs_for` for managing nested association lists.
- Pagination uses cursor-based infinite scroll with Phoenix streams.

## Tech Stack

- Elixir ~> 1.19, Phoenix 1.8, Phoenix LiveView 1.1, Ecto/PostgreSQL
- Tailwind CSS, esbuild, Heroicons
- Swoosh + Mailjet for email delivery
- Docker multi-stage build (includes `glpk-utils` for solver)
