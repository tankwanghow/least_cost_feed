# Compare Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compare view for formulas and ingredients (2–4 at a time) with leftmost-anchored diff highlighting and a "show only differences" filter.

**Architecture:** Two new LiveView routes (`/formulas/compare`, `/ingredients/compare`), a shared pure-function helper module, and a small selection-state addition to each index page. The existing `<.table>` component is reused as-is (the checkbox column is added by each index page as a normal `:col` slot — no component change needed).

**Tech Stack:** Phoenix LiveView 1.1, Ecto/PostgreSQL, ExUnit + Phoenix.LiveViewTest, Tailwind.

---

## Spec reference

`docs/superpowers/specs/2026-05-23-compare-feature-design.md`

## File map

| File | Action |
|---|---|
| `lib/least_cost_feed_web/live/compare_helpers.ex` | **Create** — pure functions: union nutrient rows, cell value, diff detection, row filter |
| `lib/least_cost_feed/entities.ex` | **Modify** — add `list_formulas_for_compare/2` and `list_ingredients_for_compare/2` |
| `lib/least_cost_feed_web/router.ex` | **Modify** — add 2 routes in `:require_authenticated_user` |
| `lib/least_cost_feed_web/live/formula_live/compare.ex` | **Create** — the formula compare LiveView |
| `lib/least_cost_feed_web/live/ingredient_live/compare.ex` | **Create** — the ingredient compare LiveView |
| `lib/least_cost_feed_web/live/formula_live/index.ex` | **Modify** — selection state + checkbox col + "Compare (N)" button |
| `lib/least_cost_feed_web/live/ingredient_live/index.ex` | **Modify** — same as above |
| `test/least_cost_feed_web/live/compare_helpers_test.exs` | **Create** — unit tests for helpers |
| `test/least_cost_feed_web/live/formula_live/compare_test.exs` | **Create** — LiveView smoke tests |
| `test/least_cost_feed_web/live/ingredient_live/compare_test.exs` | **Create** — LiveView smoke tests |

---

## Task 1: `compare_helpers` — `union_nutrient_rows/2`

**Files:**
- Create: `lib/least_cost_feed_web/live/compare_helpers.ex`
- Test: `test/least_cost_feed_web/live/compare_helpers_test.exs`

Pure function that takes a list of entities (formulas or ingredients with the relevant assoc preloaded) and returns a deduplicated, alphabetically sorted list of `%Nutrient{}` rows.

For `:formula` type: every nutrient that appears on any selected formula's `formula_nutrients`.
For `:ingredient` type: only nutrients where at least one selected ingredient has a populated `quantity` (i.e., `ingredient_compositions` entry exists).

- [ ] **Step 1: Write the failing test**

Create `test/least_cost_feed_web/live/compare_helpers_test.exs`:

```elixir
defmodule LeastCostFeedWeb.CompareHelpersTest do
  use ExUnit.Case, async: true
  alias LeastCostFeedWeb.CompareHelpers
  alias LeastCostFeed.Entities.{Formula, FormulaNutrient, Ingredient, IngredientComposition, Nutrient}

  defp nut(id, name), do: %Nutrient{id: id, name: name, unit: "%"}

  describe "union_nutrient_rows/2 for :formula" do
    test "returns union of nutrients across formulas, sorted alphabetically, deduped by id" do
      lys = nut(1, "Lysine")
      cp = nut(2, "Crude Protein")
      me = nut(3, "Metab. Energy Poultry")

      f1 = %Formula{formula_nutrients: [
        %FormulaNutrient{nutrient_id: 1, nutrient: lys},
        %FormulaNutrient{nutrient_id: 2, nutrient: cp}
      ]}

      f2 = %Formula{formula_nutrients: [
        %FormulaNutrient{nutrient_id: 2, nutrient: cp},
        %FormulaNutrient{nutrient_id: 3, nutrient: me}
      ]}

      rows = CompareHelpers.union_nutrient_rows([f1, f2], :formula)
      assert Enum.map(rows, & &1.name) == ["Crude Protein", "Lysine", "Metab. Energy Poultry"]
    end
  end

  describe "union_nutrient_rows/2 for :ingredient" do
    test "skips nutrients where no ingredient has a populated quantity" do
      lys = nut(1, "Lysine")
      cp = nut(2, "Crude Protein")
      gly = nut(3, "Glycine")

      i1 = %Ingredient{ingredient_compositions: [
        %IngredientComposition{nutrient_id: 1, nutrient: lys, quantity: 0.3},
        %IngredientComposition{nutrient_id: 3, nutrient: gly, quantity: nil}
      ]}

      i2 = %Ingredient{ingredient_compositions: [
        %IngredientComposition{nutrient_id: 2, nutrient: cp, quantity: 44.0}
      ]}

      rows = CompareHelpers.union_nutrient_rows([i1, i2], :ingredient)
      assert Enum.map(rows, & &1.name) == ["Crude Protein", "Lysine"]
      refute Enum.any?(rows, &(&1.name == "Glycine"))
    end
  end
end
```

- [ ] **Step 2: Run test, expect fail**

```
mix test test/least_cost_feed_web/live/compare_helpers_test.exs
```

Expected: failure — `CompareHelpers` undefined.

- [ ] **Step 3: Implement `compare_helpers.ex`**

Create `lib/least_cost_feed_web/live/compare_helpers.ex`:

```elixir
defmodule LeastCostFeedWeb.CompareHelpers do
  @moduledoc "Pure helpers shared by the formula and ingredient compare LiveViews."

  alias LeastCostFeed.Entities.{Formula, Ingredient}

  @doc """
  Returns the deduplicated, alphabetically sorted union of nutrient structs
  across the given entities. For `:ingredient`, only includes nutrients where
  at least one ingredient has a non-nil composition quantity.
  """
  def union_nutrient_rows(entities, :formula) do
    entities
    |> Enum.flat_map(fn %Formula{formula_nutrients: fns} ->
      Enum.map(fns, & &1.nutrient)
    end)
    |> dedup_sort()
  end

  def union_nutrient_rows(entities, :ingredient) do
    entities
    |> Enum.flat_map(fn %Ingredient{ingredient_compositions: ics} ->
      ics
      |> Enum.filter(&(&1.quantity != nil))
      |> Enum.map(& &1.nutrient)
    end)
    |> dedup_sort()
  end

  defp dedup_sort(nutrients) do
    nutrients
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end
end
```

- [ ] **Step 4: Run test, expect pass**

```
mix test test/least_cost_feed_web/live/compare_helpers_test.exs
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/least_cost_feed_web/live/compare_helpers.ex test/least_cost_feed_web/live/compare_helpers_test.exs
git commit -m "Add CompareHelpers.union_nutrient_rows for formula/ingredient compare"
```

---

## Task 2: `compare_helpers` — `cell_value/3`

Renders the displayed string for one (entity, nutrient) cell. Knows about formula min/max ranges, ingredient quantity, disabled constraints, and the optional actuals overlay.

**Files:**
- Modify: `lib/least_cost_feed_web/live/compare_helpers.ex`
- Modify: `test/least_cost_feed_web/live/compare_helpers_test.exs`

Return shape: `%{text: String.t(), strike: boolean(), actual: String.t() | nil}`. The LiveView template wraps this in markup.

- [ ] **Step 1: Add failing tests**

Append to the existing test file:

```elixir
describe "cell_value/3 for formulas" do
  alias LeastCostFeed.Entities.{Formula, FormulaNutrient, Nutrient}

  test "min and max set renders as a range" do
    f = %Formula{formula_nutrients: [
      %FormulaNutrient{nutrient_id: 1, min: 17.5, max: 18.0, actual: nil, used: true}
    ]}
    n = %Nutrient{id: 1, name: "Crude Protein", unit: "%"}
    assert %{text: "17.5 – 18.0", strike: false} = CompareHelpers.cell_value(f, n, :formula, [])
  end

  test "min only renders with ≥ prefix" do
    f = %Formula{formula_nutrients: [
      %FormulaNutrient{nutrient_id: 1, min: 0.92, max: nil, actual: nil, used: true}
    ]}
    n = %Nutrient{id: 1, name: "Lysine", unit: "%"}
    assert %{text: "≥ 0.92"} = CompareHelpers.cell_value(f, n, :formula, [])
  end

  test "max only renders with ≤ prefix" do
    f = %Formula{formula_nutrients: [
      %FormulaNutrient{nutrient_id: 1, min: nil, max: 6.0, actual: nil, used: true}
    ]}
    n = %Nutrient{id: 1, name: "Crude Fiber", unit: "%"}
    assert %{text: "≤ 6.0"} = CompareHelpers.cell_value(f, n, :formula, [])
  end

  test "missing on this formula renders as dash" do
    f = %Formula{formula_nutrients: []}
    n = %Nutrient{id: 99, name: "X", unit: "%"}
    assert %{text: "—"} = CompareHelpers.cell_value(f, n, :formula, [])
  end

  test "disabled constraint sets strike true" do
    f = %Formula{formula_nutrients: [
      %FormulaNutrient{nutrient_id: 1, min: 0.3, max: nil, actual: nil, used: false}
    ]}
    n = %Nutrient{id: 1, name: "Phytate Phos.", unit: "%"}
    assert %{text: "≥ 0.3", strike: true} = CompareHelpers.cell_value(f, n, :formula, [])
  end

  test "show_actuals: true adds actual when present" do
    f = %Formula{formula_nutrients: [
      %FormulaNutrient{nutrient_id: 1, min: 0.92, max: nil, actual: 1.05, used: true}
    ]}
    n = %Nutrient{id: 1, name: "Lysine", unit: "%"}
    assert %{actual: "1.05"} = CompareHelpers.cell_value(f, n, :formula, show_actuals: true)
  end
end

describe "cell_value/3 for ingredients" do
  alias LeastCostFeed.Entities.{Ingredient, IngredientComposition, Nutrient}

  test "renders quantity with unit" do
    i = %Ingredient{ingredient_compositions: [
      %IngredientComposition{nutrient_id: 1, quantity: 44.0}
    ]}
    n = %Nutrient{id: 1, name: "Crude Protein", unit: "%"}
    assert %{text: "44.0 %"} = CompareHelpers.cell_value(i, n, :ingredient, [])
  end

  test "missing composition renders as dash" do
    i = %Ingredient{ingredient_compositions: []}
    n = %Nutrient{id: 99, name: "X", unit: "%"}
    assert %{text: "—"} = CompareHelpers.cell_value(i, n, :ingredient, [])
  end
end
```

- [ ] **Step 2: Run test, expect fail**

```
mix test test/least_cost_feed_web/live/compare_helpers_test.exs
```

Expected: 8 new failures (`cell_value/3 undefined` etc).

- [ ] **Step 3: Implement `cell_value/4`**

Append to `lib/least_cost_feed_web/live/compare_helpers.ex` (inside `defmodule`):

```elixir
@doc """
Renders the displayed cell for an (entity, nutrient) pair.

Returns a map: `%{text: String.t(), strike: boolean(), actual: String.t() | nil}`.
"""
def cell_value(entity, nutrient, type, opts \\ [])

def cell_value(%LeastCostFeed.Entities.Formula{} = formula, nutrient, :formula, opts) do
  case Enum.find(formula.formula_nutrients, &(&1.nutrient_id == nutrient.id)) do
    nil ->
      %{text: "—", strike: false, actual: nil}

    fn_row ->
      %{
        text: format_range(fn_row.min, fn_row.max),
        strike: fn_row.used == false,
        actual:
          if(Keyword.get(opts, :show_actuals, false) and fn_row.actual,
            do: format_num(fn_row.actual),
            else: nil
          )
      }
  end
end

def cell_value(%LeastCostFeed.Entities.Ingredient{} = ingredient, nutrient, :ingredient, _opts) do
  case Enum.find(ingredient.ingredient_compositions, &(&1.nutrient_id == nutrient.id)) do
    nil ->
      %{text: "—", strike: false, actual: nil}

    %{quantity: nil} ->
      %{text: "—", strike: false, actual: nil}

    ic ->
      %{text: "#{format_num(ic.quantity)} #{nutrient.unit}", strike: false, actual: nil}
  end
end

defp format_range(nil, nil), do: "—"
defp format_range(min, nil), do: "≥ #{format_num(min)}"
defp format_range(nil, max), do: "≤ #{format_num(max)}"
defp format_range(min, max), do: "#{format_num(min)} – #{format_num(max)}"

defp format_num(n) when is_float(n) do
  # Trim trailing zeros but keep at least one decimal (e.g. 17.5 not 17.500000, 18.0 stays 18.0).
  case Float.to_string(n) do
    s -> s
  end
end

defp format_num(n), do: to_string(n)
```

- [ ] **Step 4: Run tests, expect pass**

```
mix test test/least_cost_feed_web/live/compare_helpers_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/least_cost_feed_web/live/compare_helpers.ex test/least_cost_feed_web/live/compare_helpers_test.exs
git commit -m "Add CompareHelpers.cell_value rendering for formula/ingredient cells"
```

---

## Task 3: `compare_helpers` — diff detection + row filter

**Files:**
- Modify: `lib/least_cost_feed_web/live/compare_helpers.ex`
- Modify: `test/least_cost_feed_web/live/compare_helpers_test.exs`

Two functions:

- `differs_from_anchor?(cell, anchor_cell)` — compares the `:text` field of two cell maps.
- `filter_differing_rows(row_cells_list)` — takes a list of `{nutrient, [cell1, cell2, cell3, cell4]}` tuples and keeps only those where any non-anchor cell's `:text` differs from cell1's `:text`.

- [ ] **Step 1: Add failing tests**

```elixir
describe "differs_from_anchor?/2" do
  test "true when text differs" do
    a = %{text: "0.90", strike: false, actual: nil}
    b = %{text: "0.92", strike: false, actual: nil}
    assert CompareHelpers.differs_from_anchor?(b, a)
  end

  test "false when text equal" do
    a = %{text: "0.90", strike: false, actual: nil}
    b = %{text: "0.90", strike: false, actual: nil}
    refute CompareHelpers.differs_from_anchor?(b, a)
  end
end

describe "filter_differing_rows/1" do
  test "drops rows where every non-anchor cell equals anchor" do
    n1 = %{id: 1, name: "A"}
    n2 = %{id: 2, name: "B"}

    same_row = {n1, [
      %{text: "x", strike: false, actual: nil},
      %{text: "x", strike: false, actual: nil},
      %{text: "x", strike: false, actual: nil}
    ]}

    diff_row = {n2, [
      %{text: "x", strike: false, actual: nil},
      %{text: "y", strike: false, actual: nil},
      %{text: "x", strike: false, actual: nil}
    ]}

    kept = CompareHelpers.filter_differing_rows([same_row, diff_row])
    assert kept == [diff_row]
  end
end
```

- [ ] **Step 2: Run test, expect fail**

```
mix test test/least_cost_feed_web/live/compare_helpers_test.exs
```

Expected: failures for the new tests.

- [ ] **Step 3: Implement**

Append to `lib/least_cost_feed_web/live/compare_helpers.ex`:

```elixir
@doc "True when `cell.text` is not equal to `anchor.text`."
def differs_from_anchor?(%{text: ct}, %{text: at}), do: ct != at

@doc """
Given a list of `{nutrient, [cell1, cell2, ...]}` tuples (anchor is cell1),
keep only the rows where at least one non-anchor cell differs from the anchor.
"""
def filter_differing_rows(rows) do
  Enum.filter(rows, fn {_n, [anchor | rest]} ->
    Enum.any?(rest, &differs_from_anchor?(&1, anchor))
  end)
end
```

- [ ] **Step 4: Run tests, expect pass**

```
mix test test/least_cost_feed_web/live/compare_helpers_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/least_cost_feed_web/live/compare_helpers.ex test/least_cost_feed_web/live/compare_helpers_test.exs
git commit -m "Add CompareHelpers diff detection and row filter"
```

---

## Task 4: `entities.ex` — `list_formulas_for_compare/2` + `list_ingredients_for_compare/2`

**Files:**
- Modify: `lib/least_cost_feed/entities.ex`
- Modify: `test/least_cost_feed/entities_test.exs`

Two functions that load entities for the compare page with the right preloads, scoped to user.

- [ ] **Step 1: Locate insertion point**

Open `lib/least_cost_feed/entities.ex`, find a logical location near the existing `list_formulas` and `list_ingredients` functions. Insert the new functions after them.

- [ ] **Step 2: Write failing tests**

Append to `test/least_cost_feed/entities_test.exs` (inside its outermost `defmodule`, before final `end`):

```elixir
describe "list_formulas_for_compare/2" do
  alias LeastCostFeed.Entities

  test "returns only formulas matching ids and user, preloaded" do
    user = LeastCostFeed.UserAccountsFixtures.user_fixture()
    other = LeastCostFeed.UserAccountsFixtures.user_fixture()

    {:ok, f1} = Entities.create_formula(%{
      name: "F1", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id
    })
    {:ok, f2} = Entities.create_formula(%{
      name: "F2", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id
    })
    {:ok, fother} = Entities.create_formula(%{
      name: "X", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: other.id
    })

    result = Entities.list_formulas_for_compare(user.id, [f1.id, f2.id, fother.id])

    ids = Enum.map(result, & &1.id) |> Enum.sort()
    assert ids == Enum.sort([f1.id, f2.id])

    assert Enum.all?(result, fn f ->
      Ecto.assoc_loaded?(f.formula_nutrients)
    end)
  end
end

describe "list_ingredients_for_compare/2" do
  alias LeastCostFeed.Entities

  test "returns only ingredients matching ids and user, with compositions preloaded" do
    user = LeastCostFeed.UserAccountsFixtures.user_fixture()

    {:ok, i1} = Entities.create_ingredient(%{
      name: "I1", cost: 1.0, unit: "KG", category: "x", description: "", user_id: user.id
    })

    result = Entities.list_ingredients_for_compare(user.id, [i1.id])
    assert length(result) == 1
    [i] = result
    assert Ecto.assoc_loaded?(i.ingredient_compositions)
  end
end
```

NOTE: If the existing `entities_test.exs` uses different fixture helpers or `create_*` signatures (e.g. requires more fields), adjust the test data accordingly. Verify required fields by reading the `changeset/2` of `Formula` and `Ingredient` and amending the test attribute maps.

- [ ] **Step 3: Run test, expect fail**

```
mix test test/least_cost_feed/entities_test.exs
```

Expected: failures because `list_formulas_for_compare/2` and `list_ingredients_for_compare/2` are undefined.

- [ ] **Step 4: Implement the functions**

Add to `lib/least_cost_feed/entities.ex` (the `alias`es and `import Ecto.Query` already exist in this module):

```elixir
def list_formulas_for_compare(user_id, ids) when is_list(ids) do
  from(f in LeastCostFeed.Entities.Formula,
    where: f.user_id == ^user_id and f.id in ^ids,
    preload: [formula_nutrients: :nutrient]
  )
  |> LeastCostFeed.Repo.all()
end

def list_ingredients_for_compare(user_id, ids) when is_list(ids) do
  from(i in LeastCostFeed.Entities.Ingredient,
    where: i.user_id == ^user_id and i.id in ^ids,
    preload: [ingredient_compositions: :nutrient]
  )
  |> LeastCostFeed.Repo.all()
end
```

- [ ] **Step 5: Run tests, expect pass**

```
mix test test/least_cost_feed/entities_test.exs
```

Expected: new tests pass; existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/least_cost_feed/entities.ex test/least_cost_feed/entities_test.exs
git commit -m "Add Entities.list_formulas_for_compare and list_ingredients_for_compare"
```

---

## Task 5: Router — add the two compare routes

**Files:**
- Modify: `lib/least_cost_feed_web/router.ex`

- [ ] **Step 1: Add the routes**

Inside the `:require_authenticated_user` block in `lib/least_cost_feed_web/router.ex`, immediately after the existing `live "/formulas/efc_optimizer", ...` line, add:

```elixir
live "/formulas/compare", FormulaLive.Compare, :compare
```

And immediately after the existing `live "/ingredients/:id/edit", ...` line, add:

```elixir
live "/ingredients/compare", IngredientLive.Compare, :compare
```

- [ ] **Step 2: Confirm routes are registered**

```
mix phx.routes | grep compare
```

Expected output includes:
```
GET   /formulas/compare      LeastCostFeedWeb.FormulaLive.Compare :compare
GET   /ingredients/compare   LeastCostFeedWeb.IngredientLive.Compare :compare
```

(Will fail to start until the LiveView modules exist — that's fine; the routes file itself just needs to compile, which it will because module references in router are compile-time symbols, not loaded.)

- [ ] **Step 3: Commit**

```bash
git add lib/least_cost_feed_web/router.ex
git commit -m "Add /formulas/compare and /ingredients/compare routes"
```

---

## Task 6: Formula compare LiveView — mount + render columns/rows + diff highlight

**Files:**
- Create: `lib/least_cost_feed_web/live/formula_live/compare.ex`
- Create: `test/least_cost_feed_web/live/formula_live/compare_test.exs`

Renders the basic compare page: header chips per formula + table with anchored diff highlighting. No drop/add controls or toggles yet (Tasks 7–8 add them).

- [ ] **Step 1: Write a failing LiveView smoke test**

Create `test/least_cost_feed_web/live/formula_live/compare_test.exs`:

```elixir
defmodule LeastCostFeedWeb.FormulaLive.CompareTest do
  use LeastCostFeedWeb.ConnCase

  import Phoenix.LiveViewTest
  import LeastCostFeed.UserAccountsFixtures

  alias LeastCostFeed.{Entities, Repo}

  setup :register_and_log_in_user

  defp setup_two_formulas(user) do
    {:ok, n_cp} = Entities.create_nutrient(%{name: "Crude Protein", unit: "%", user_id: user.id})
    {:ok, n_lys} = Entities.create_nutrient(%{name: "Lysine", unit: "%", user_id: user.id})

    {:ok, f1} = Entities.create_formula(%{
      name: "F1", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id,
      formula_nutrients: [
        %{nutrient_id: n_cp.id, min: 17.5, max: 18.0, used: true},
        %{nutrient_id: n_lys.id, min: 0.90, used: true}
      ]
    })

    {:ok, f2} = Entities.create_formula(%{
      name: "F2", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id,
      formula_nutrients: [
        %{nutrient_id: n_cp.id, min: 17.5, max: 18.0, used: true},
        %{nutrient_id: n_lys.id, min: 0.92, used: true}
      ]
    })

    {f1, f2}
  end

  test "renders both formulas as columns with diff dot on Lysine", %{conn: conn, user: user} do
    {f1, f2} = setup_two_formulas(user)

    {:ok, _view, html} =
      live(conn, ~p"/formulas/compare?ids=#{f1.id},#{f2.id}")

    assert html =~ "F1"
    assert html =~ "F2"
    assert html =~ "Lysine"
    assert html =~ "Crude Protein"
    # Anchor cell shows raw, non-anchor that differs gets a dot
    assert html =~ "≥ 0.90"
    assert html =~ "≥ 0.92"
  end

  test "redirects with flash when fewer than 2 valid ids", %{conn: conn} do
    {:error, {:live_redirect, %{flash: flash}}} = live(conn, ~p"/formulas/compare?ids=999999")
    assert flash["error"] =~ "needs 2"
  end

  test "redirects with flash when more than 4 ids", %{conn: conn, user: user} do
    {f1, f2} = setup_two_formulas(user)
    {:ok, f3} = Entities.create_formula(%{
      name: "F3", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id
    })
    {:ok, f4} = Entities.create_formula(%{
      name: "F4", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id
    })
    {:ok, f5} = Entities.create_formula(%{
      name: "F5", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id
    })

    ids = [f1.id, f2.id, f3.id, f4.id, f5.id] |> Enum.join(",")
    {:error, {:live_redirect, %{flash: flash}}} = live(conn, ~p"/formulas/compare?ids=#{ids}")
    assert flash["error"] =~ "limited to 4"
  end
end
```

- [ ] **Step 2: Run test, expect fail**

```
mix test test/least_cost_feed_web/live/formula_live/compare_test.exs
```

Expected: compile error or 500 — `FormulaLive.Compare` undefined.

- [ ] **Step 3: Implement the LiveView**

Create `lib/least_cost_feed_web/live/formula_live/compare.ex`:

```elixir
defmodule LeastCostFeedWeb.FormulaLive.Compare do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeedWeb.CompareHelpers

  @max 4

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Compare Formulas", only_differences?: false, show_actuals?: false)}
  end

  @impl true
  def handle_params(%{"ids" => ids_param}, _uri, socket) do
    requested_ids = parse_ids(ids_param)
    formulas = Entities.list_formulas_for_compare(socket.assigns.current_user.id, requested_ids)

    cond do
      length(formulas) < 2 ->
        {:noreply,
         socket
         |> put_flash(:error, "Compare needs 2–4 formulas (you gave #{length(formulas)} valid).")
         |> push_navigate(to: ~p"/formulas")}

      length(formulas) > @max ->
        {:noreply,
         socket
         |> put_flash(:error, "Compare is limited to 4 formulas.")
         |> push_navigate(to: ~p"/formulas")}

      true ->
        ordered =
          Enum.sort_by(formulas, fn f -> Enum.find_index(requested_ids, &(&1 == f.id)) end)

        {:noreply, assign(socket, formulas: ordered)}
    end
  end

  @impl true
  def render(assigns) do
    rows_with_cells = build_rows(assigns.formulas, assigns.only_differences?, assigns.show_actuals?)
    assigns = assign(assigns, rows_with_cells: rows_with_cells)

    ~H"""
    <div class="w-11/12 mx-auto p-4">
      <.back navigate={~p"/formulas"}>Back to Formulas</.back>
      <div class="font-bold text-3xl mb-4">Compare Formulas</div>

      <div class="flex flex-wrap gap-2 mb-4 items-center">
        <span :for={f <- @formulas} class="px-3 py-1 rounded bg-primary text-primary-content text-sm">
          {f.name}
        </span>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-sm border-collapse">
          <thead>
            <tr class="bg-primary text-primary-content">
              <th class="text-left p-2 w-[28%]">Nutrient</th>
              <th :for={f <- @formulas} class="text-left p-2">{f.name}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{nutrient, cells} <- @rows_with_cells} class="border-b border-base-200">
              <td class="p-2 font-medium">{nutrient.name}</td>
              <%= for {cell, idx} <- Enum.with_index(cells) do %>
                <td class={[
                  "p-2",
                  idx > 0 && CompareHelpers.differs_from_anchor?(cell, List.first(cells)) && "bg-warning/20"
                ]}>
                  <span class={[cell.strike && "line-through opacity-60"]}>
                    {cell.text}
                  </span>
                  <span :if={idx > 0 && CompareHelpers.differs_from_anchor?(cell, List.first(cells))} class="ml-1">●</span>
                </td>
              <% end %>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp parse_ids(s) do
    s
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn part ->
      case Integer.parse(part) do
        {n, _} -> [n]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  defp build_rows(formulas, only_diff?, show_actuals?) do
    nutrients = CompareHelpers.union_nutrient_rows(formulas, :formula)

    rows =
      Enum.map(nutrients, fn n ->
        cells = Enum.map(formulas, &CompareHelpers.cell_value(&1, n, :formula, show_actuals: show_actuals?))
        {n, cells}
      end)

    if only_diff?, do: CompareHelpers.filter_differing_rows(rows), else: rows
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

```
mix test test/least_cost_feed_web/live/formula_live/compare_test.exs
```

Expected: all 3 tests pass. If `create_formula` does not accept nested `formula_nutrients` in the test seed, adjust the seed to call `Entities.create_formula_nutrient/1` (or equivalent) directly per the actual context API.

- [ ] **Step 5: Manual smoke check**

```
mix phx.server
```

Visit `/formulas/compare?ids=<two-real-ids>` while logged in. Confirm the table renders with both columns and diff highlighting on differing cells.

- [ ] **Step 6: Commit**

```bash
git add lib/least_cost_feed_web/live/formula_live/compare.ex test/least_cost_feed_web/live/formula_live/compare_test.exs
git commit -m "Add FormulaLive.Compare with diff-highlighted side-by-side view"
```

---

## Task 7: Formula compare — drop + add column controls

**Files:**
- Modify: `lib/least_cost_feed_web/live/formula_live/compare.ex`
- Modify: `test/least_cost_feed_web/live/formula_live/compare_test.exs`

Add ✕ buttons on each chip (drop) and a small `<select>` of the user's other formulas with an "Add" button (capped at 4 total).

- [ ] **Step 1: Add failing test for drop**

Append to `compare_test.exs`:

```elixir
test "clicking ✕ on a chip drops that formula and updates the URL", %{conn: conn, user: user} do
  {f1, f2} = setup_two_formulas(user)
  {:ok, f3} = Entities.create_formula(%{
    name: "F3", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id
  })

  {:ok, view, _html} = live(conn, ~p"/formulas/compare?ids=#{f1.id},#{f2.id},#{f3.id}")
  view |> element("[phx-click=drop][phx-value-id='#{f3.id}']") |> render_click()

  assert_patch(view, ~p"/formulas/compare?ids=#{f1.id},#{f2.id}")
  refute render(view) =~ "F3"
end

test "dropping below 2 redirects to /formulas with flash", %{conn: conn, user: user} do
  {f1, f2} = setup_two_formulas(user)
  {:ok, view, _html} = live(conn, ~p"/formulas/compare?ids=#{f1.id},#{f2.id}")
  view |> element("[phx-click=drop][phx-value-id='#{f2.id}']") |> render_click()
  assert_redirected(view, ~p"/formulas")
end
```

- [ ] **Step 2: Run tests, expect fail**

```
mix test test/least_cost_feed_web/live/formula_live/compare_test.exs
```

Expected: 2 new failures.

- [ ] **Step 3: Add drop button to the chip rendering and the handle_event**

In `compare.ex`, replace the chip block in `render/1`:

```elixir
<div class="flex flex-wrap gap-2 mb-4 items-center">
  <span :for={f <- @formulas} class="px-3 py-1 rounded bg-primary text-primary-content text-sm flex items-center gap-1">
    {f.name}
    <button
      :if={length(@formulas) > 2}
      phx-click="drop"
      phx-value-id={f.id}
      class="ml-1 text-primary-content/80 hover:text-primary-content"
      aria-label={"Remove " <> f.name}
    >✕</button>
  </span>
  <.live_component
    :if={length(@formulas) < 4}
    module={LeastCostFeedWeb.FormulaLive.Compare.AddPicker}
    id="compare-add-picker"
    current_user={@current_user}
    current_ids={Enum.map(@formulas, & &1.id)}
  />
</div>
```

Append the event handler to `compare.ex`:

```elixir
@impl true
def handle_event("drop", %{"id" => id}, socket) do
  drop_id = String.to_integer(id)
  remaining = socket.assigns.formulas |> Enum.map(& &1.id) |> Enum.reject(&(&1 == drop_id))

  if length(remaining) < 2 do
    {:noreply,
     socket
     |> put_flash(:info, "Compare closed — fewer than 2 formulas remained.")
     |> push_navigate(to: ~p"/formulas")}
  else
    {:noreply, push_patch(socket, to: ~p"/formulas/compare?ids=#{Enum.join(remaining, ",")}")}
  end
end
```

- [ ] **Step 4: Implement the Add picker as a LiveComponent**

Create the picker inline at the bottom of `lib/least_cost_feed_web/live/formula_live/compare.ex` (still inside same file, after the main module's `end`):

```elixir
defmodule LeastCostFeedWeb.FormulaLive.Compare.AddPicker do
  use LeastCostFeedWeb, :live_component

  alias LeastCostFeed.Entities

  @impl true
  def update(assigns, socket) do
    candidates =
      Entities.list_formulas_for_compare(assigns.current_user.id, list_all_ids(assigns.current_user.id))
      |> Enum.reject(&(&1.id in assigns.current_ids))
      |> Enum.sort_by(& &1.name)

    {:ok, socket |> assign(assigns) |> assign(candidates: candidates)}
  end

  defp list_all_ids(user_id) do
    import Ecto.Query
    from(f in LeastCostFeed.Entities.Formula, where: f.user_id == ^user_id, select: f.id)
    |> LeastCostFeed.Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form phx-submit="add" phx-target={@myself} class="flex items-center gap-1">
      <select name="id" class="select select-sm select-bordered">
        <option value="">+ Add formula…</option>
        <option :for={f <- @candidates} value={f.id}>{f.name}</option>
      </select>
      <button type="submit" class="btn btn-sm">Add</button>
    </form>
    """
  end

  @impl true
  def handle_event("add", %{"id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add", %{"id" => id}, socket) do
    new_id = String.to_integer(id)
    new_ids = socket.assigns.current_ids ++ [new_id]
    send(self(), {:patch_compare_ids, new_ids})
    {:noreply, socket}
  end
end
```

Add a `handle_info/2` to the parent `Compare` LiveView for the message:

```elixir
@impl true
def handle_info({:patch_compare_ids, ids}, socket) do
  {:noreply, push_patch(socket, to: ~p"/formulas/compare?ids=#{Enum.join(ids, ",")}")}
end
```

- [ ] **Step 5: Add test for add picker**

Append to `compare_test.exs`:

```elixir
test "adding via the picker patches the URL with the new id", %{conn: conn, user: user} do
  {f1, f2} = setup_two_formulas(user)
  {:ok, f3} = Entities.create_formula(%{
    name: "F3", batch_size: 1000.0, weight_unit: "KG", usage_per_day: 0.0, user_id: user.id
  })

  {:ok, view, _html} = live(conn, ~p"/formulas/compare?ids=#{f1.id},#{f2.id}")

  view
  |> form("form[phx-submit=add]", id: to_string(f3.id))
  |> render_submit()

  assert_patch(view, ~p"/formulas/compare?ids=#{f1.id},#{f2.id},#{f3.id}")
end
```

- [ ] **Step 6: Run tests, expect pass**

```
mix test test/least_cost_feed_web/live/formula_live/compare_test.exs
```

- [ ] **Step 7: Commit**

```bash
git add lib/least_cost_feed_web/live/formula_live/compare.ex test/least_cost_feed_web/live/formula_live/compare_test.exs
git commit -m "Add drop/add column controls to FormulaLive.Compare"
```

---

## Task 8: Formula compare — toggles (only differences, show actuals)

**Files:**
- Modify: `lib/least_cost_feed_web/live/formula_live/compare.ex`
- Modify: `test/least_cost_feed_web/live/formula_live/compare_test.exs`

- [ ] **Step 1: Add failing test for "Only differences"**

```elixir
test "Only differences hides rows where all non-anchor cells match anchor", %{conn: conn, user: user} do
  {f1, f2} = setup_two_formulas(user)
  # CP is the same on both (17.5–18.0), Lysine differs (0.90 vs 0.92)
  {:ok, view, html} = live(conn, ~p"/formulas/compare?ids=#{f1.id},#{f2.id}")
  assert html =~ "Crude Protein"
  assert html =~ "Lysine"

  view |> element("input[phx-click=toggle_only_diff]") |> render_click()

  refute render(view) =~ "Crude Protein"
  assert render(view) =~ "Lysine"
end
```

- [ ] **Step 2: Run test, expect fail**

```
mix test test/least_cost_feed_web/live/formula_live/compare_test.exs
```

- [ ] **Step 3: Add the toggles to the render and handle_event**

Add a controls strip below the chip block in `render/1`:

```elixir
<div class="flex items-center gap-4 mb-3 text-sm">
  <label class="flex items-center gap-1">
    <input type="checkbox" phx-click="toggle_only_diff" checked={@only_differences?} /> Only differences
  </label>
  <label class="flex items-center gap-1">
    <input type="checkbox" phx-click="toggle_show_actuals" checked={@show_actuals?} /> Show actuals
  </label>
</div>
```

Append handlers:

```elixir
@impl true
def handle_event("toggle_only_diff", _params, socket) do
  {:noreply, update(socket, :only_differences?, &(!&1))}
end

@impl true
def handle_event("toggle_show_actuals", _params, socket) do
  {:noreply, update(socket, :show_actuals?, &(!&1))}
end
```

- [ ] **Step 4: Run tests, expect pass**

```
mix test test/least_cost_feed_web/live/formula_live/compare_test.exs
```

- [ ] **Step 5: Commit**

```bash
git add lib/least_cost_feed_web/live/formula_live/compare.ex test/least_cost_feed_web/live/formula_live/compare_test.exs
git commit -m "Add Only-differences and Show-actuals toggles to FormulaLive.Compare"
```

---

## Task 9: Ingredient compare LiveView — full

**Files:**
- Create: `lib/least_cost_feed_web/live/ingredient_live/compare.ex`
- Create: `test/least_cost_feed_web/live/ingredient_live/compare_test.exs`

Same structure as the formula compare, but renders single-value cells (no min/max range, no actuals overlay, no `Show actuals` toggle). Reuses `CompareHelpers`.

- [ ] **Step 1: Write failing smoke test**

Create `test/least_cost_feed_web/live/ingredient_live/compare_test.exs`:

```elixir
defmodule LeastCostFeedWeb.IngredientLive.CompareTest do
  use LeastCostFeedWeb.ConnCase
  import Phoenix.LiveViewTest
  import LeastCostFeed.UserAccountsFixtures
  alias LeastCostFeed.Entities

  setup :register_and_log_in_user

  test "renders two ingredients side-by-side with diff highlight", %{conn: conn, user: user} do
    {:ok, n} = Entities.create_nutrient(%{name: "Crude Protein", unit: "%", user_id: user.id})

    {:ok, i1} = Entities.create_ingredient(%{
      name: "Corn", cost: 1.2, unit: "KG", category: "x", description: "", user_id: user.id,
      ingredient_compositions: [%{nutrient_id: n.id, quantity: 7.5}]
    })
    {:ok, i2} = Entities.create_ingredient(%{
      name: "SBM", cost: 1.85, unit: "KG", category: "x", description: "", user_id: user.id,
      ingredient_compositions: [%{nutrient_id: n.id, quantity: 44.0}]
    })

    {:ok, _view, html} = live(conn, ~p"/ingredients/compare?ids=#{i1.id},#{i2.id}")
    assert html =~ "Corn"
    assert html =~ "SBM"
    assert html =~ "Crude Protein"
    assert html =~ "7.5"
    assert html =~ "44.0"
  end

  test "redirects when fewer than 2 valid ids", %{conn: conn} do
    {:error, {:live_redirect, %{flash: flash}}} = live(conn, ~p"/ingredients/compare?ids=999999")
    assert flash["error"] =~ "needs 2"
  end
end
```

- [ ] **Step 2: Run test, expect fail**

```
mix test test/least_cost_feed_web/live/ingredient_live/compare_test.exs
```

- [ ] **Step 3: Implement**

Create `lib/least_cost_feed_web/live/ingredient_live/compare.ex` (same structure as `FormulaLive.Compare`, with these substitutions):

- Replace `formulas` ↔ `ingredients`, `Entities.list_formulas_for_compare` ↔ `Entities.list_ingredients_for_compare`, `:formula` ↔ `:ingredient` everywhere.
- Remove the `show_actuals?` assign and toggle and its handler.
- Update redirect targets: `~p"/ingredients"` instead of `~p"/formulas"`.
- Replace the AddPicker query to load ingredient ids.
- Update the URL pattern: `~p"/ingredients/compare?ids=..."` everywhere.

Full file:

```elixir
defmodule LeastCostFeedWeb.IngredientLive.Compare do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeedWeb.CompareHelpers

  @max 4

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Compare Ingredients", only_differences?: false)}
  end

  @impl true
  def handle_params(%{"ids" => ids_param}, _uri, socket) do
    requested_ids = parse_ids(ids_param)
    ingredients =
      Entities.list_ingredients_for_compare(socket.assigns.current_user.id, requested_ids)

    cond do
      length(ingredients) < 2 ->
        {:noreply,
         socket
         |> put_flash(:error, "Compare needs 2–4 ingredients (you gave #{length(ingredients)} valid).")
         |> push_navigate(to: ~p"/ingredients")}

      length(ingredients) > @max ->
        {:noreply,
         socket
         |> put_flash(:error, "Compare is limited to 4 ingredients.")
         |> push_navigate(to: ~p"/ingredients")}

      true ->
        ordered =
          Enum.sort_by(ingredients, fn i -> Enum.find_index(requested_ids, &(&1 == i.id)) end)

        {:noreply, assign(socket, ingredients: ordered)}
    end
  end

  @impl true
  def render(assigns) do
    nutrients = CompareHelpers.union_nutrient_rows(assigns.ingredients, :ingredient)

    rows =
      Enum.map(nutrients, fn n ->
        cells = Enum.map(assigns.ingredients, &CompareHelpers.cell_value(&1, n, :ingredient, []))
        {n, cells}
      end)

    rows = if assigns.only_differences?, do: CompareHelpers.filter_differing_rows(rows), else: rows
    assigns = assign(assigns, rows_with_cells: rows)

    ~H"""
    <div class="w-11/12 mx-auto p-4">
      <.back navigate={~p"/ingredients"}>Back to Ingredients</.back>
      <div class="font-bold text-3xl mb-4">Compare Ingredients</div>

      <div class="flex flex-wrap gap-2 mb-4 items-center">
        <span :for={i <- @ingredients} class="px-3 py-1 rounded bg-primary text-primary-content text-sm flex items-center gap-1">
          {i.name}
          <button
            :if={length(@ingredients) > 2}
            phx-click="drop"
            phx-value-id={i.id}
            class="ml-1"
            aria-label={"Remove " <> i.name}
          >✕</button>
        </span>
        <.live_component
          :if={length(@ingredients) < 4}
          module={LeastCostFeedWeb.IngredientLive.Compare.AddPicker}
          id="compare-add-picker"
          current_user={@current_user}
          current_ids={Enum.map(@ingredients, & &1.id)}
        />
      </div>

      <div class="mb-3 text-sm">
        <label class="flex items-center gap-1">
          <input type="checkbox" phx-click="toggle_only_diff" checked={@only_differences?} /> Only differences
        </label>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-sm border-collapse">
          <thead>
            <tr class="bg-primary text-primary-content">
              <th class="text-left p-2 w-[28%]">Nutrient</th>
              <th :for={i <- @ingredients} class="text-left p-2">{i.name}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{nutrient, cells} <- @rows_with_cells} class="border-b border-base-200">
              <td class="p-2 font-medium">{nutrient.name}</td>
              <%= for {cell, idx} <- Enum.with_index(cells) do %>
                <td class={[
                  "p-2",
                  idx > 0 && CompareHelpers.differs_from_anchor?(cell, List.first(cells)) && "bg-warning/20"
                ]}>
                  {cell.text}
                  <span :if={idx > 0 && CompareHelpers.differs_from_anchor?(cell, List.first(cells))} class="ml-1">●</span>
                </td>
              <% end %>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("drop", %{"id" => id}, socket) do
    drop_id = String.to_integer(id)
    remaining = socket.assigns.ingredients |> Enum.map(& &1.id) |> Enum.reject(&(&1 == drop_id))

    if length(remaining) < 2 do
      {:noreply, push_navigate(socket, to: ~p"/ingredients")}
    else
      {:noreply, push_patch(socket, to: ~p"/ingredients/compare?ids=#{Enum.join(remaining, ",")}")}
    end
  end

  @impl true
  def handle_event("toggle_only_diff", _params, socket) do
    {:noreply, update(socket, :only_differences?, &(!&1))}
  end

  @impl true
  def handle_info({:patch_compare_ids, ids}, socket) do
    {:noreply, push_patch(socket, to: ~p"/ingredients/compare?ids=#{Enum.join(ids, ",")}")}
  end

  defp parse_ids(s) do
    s
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn p ->
      case Integer.parse(p) do
        {n, _} -> [n]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end
end

defmodule LeastCostFeedWeb.IngredientLive.Compare.AddPicker do
  use LeastCostFeedWeb, :live_component

  @impl true
  def update(assigns, socket) do
    import Ecto.Query

    candidates =
      from(i in LeastCostFeed.Entities.Ingredient,
        where: i.user_id == ^assigns.current_user.id and i.id not in ^assigns.current_ids,
        order_by: i.name,
        select: %{id: i.id, name: i.name}
      )
      |> LeastCostFeed.Repo.all()

    {:ok, socket |> assign(assigns) |> assign(candidates: candidates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form phx-submit="add" phx-target={@myself} class="flex items-center gap-1">
      <select name="id" class="select select-sm select-bordered">
        <option value="">+ Add ingredient…</option>
        <option :for={i <- @candidates} value={i.id}>{i.name}</option>
      </select>
      <button type="submit" class="btn btn-sm">Add</button>
    </form>
    """
  end

  @impl true
  def handle_event("add", %{"id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add", %{"id" => id}, socket) do
    send(self(), {:patch_compare_ids, socket.assigns.current_ids ++ [String.to_integer(id)]})
    {:noreply, socket}
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

```
mix test test/least_cost_feed_web/live/ingredient_live/compare_test.exs
```

- [ ] **Step 5: Commit**

```bash
git add lib/least_cost_feed_web/live/ingredient_live/compare.ex test/least_cost_feed_web/live/ingredient_live/compare_test.exs
git commit -m "Add IngredientLive.Compare with full controls"
```

---

## Task 10: Formula index — selection state + checkbox column + Compare button

**Files:**
- Modify: `lib/least_cost_feed_web/live/formula_live/index.ex`

Uses the existing `<.table>` component as-is by adding a new leading `:col` slot whose body is a checkbox bound to `@selected_ids`. No changes to `my_components.ex`.

- [ ] **Step 1: Add `:selected_ids` socket assign**

In `mount/3` of `formula_live/index.ex`, add to the socket setup:

```elixir
|> assign(selected_ids: MapSet.new())
```

So the mount becomes:

```elixir
def mount(_params, _session, socket) do
  socket =
    socket
    |> assign(search: %{terms: ""})
    |> assign(sort_directions: @empty_sort_directions |> Map.merge(%{"updated_at" => :asc}))
    |> assign(selected_ids: MapSet.new())

  {:ok,
   socket
   |> assign(page_title: "Formula Listing")
   |> LeastCostFeedWeb.Helpers.sort("updated_at", &query/1, @empty_sort_directions)
   |> filter(true, 1)}
end
```

- [ ] **Step 2: Add the toggle handler**

```elixir
@impl true
def handle_event("toggle_select", %{"id" => id}, socket) do
  id = String.to_integer(id)
  selected = socket.assigns.selected_ids

  selected =
    if MapSet.member?(selected, id),
      do: MapSet.delete(selected, id),
      else: MapSet.put(selected, id)

  {:noreply, assign(socket, selected_ids: selected)}
end
```

- [ ] **Step 3: Add the checkbox column to the table**

Insert this as the FIRST `:col` slot inside the `<LeastCostFeedWeb.MyComponents.table>` block:

```elixir
<:col :let={{_id, formula}} class="w-[3%]">
  <input
    type="checkbox"
    phx-click="toggle_select"
    phx-value-id={formula.id}
    checked={formula.id in @selected_ids}
  />
</:col>
```

- [ ] **Step 4: Add the "Compare (N)" button**

In the header button group (the div containing the existing "New Formula", "Multi-Formula Nutrient Relax", "EFC Optimizer" links), insert after the existing buttons:

```elixir
<.link
  :if={MapSet.size(@selected_ids) in 2..4}
  navigate={~p"/formulas/compare?ids=#{Enum.join(@selected_ids, ",")}"}
  id="compare_formulas"
  class="ml-2"
>
  <.button>Compare ({MapSet.size(@selected_ids)})</.button>
</.link>
```

- [ ] **Step 5: Manual verification**

```
mix phx.server
```

Visit `/formulas`. Check 2 formulas via the new checkbox column. The "Compare (2)" button should appear; clicking it navigates to `/formulas/compare?ids=...`. Check a 3rd and 4th; verify the link updates. Check a 5th and verify the button hides (out of range).

- [ ] **Step 6: Commit**

```bash
git add lib/least_cost_feed_web/live/formula_live/index.ex
git commit -m "Add selection + Compare button to Formula index"
```

---

## Task 11: Ingredient index — selection state + checkbox column + Compare button

**Files:**
- Modify: `lib/least_cost_feed_web/live/ingredient_live/index.ex`

Mirror of Task 10.

- [ ] **Step 1: Add `:selected_ids` to the socket in `mount/3`**

Same as Task 10 — `|> assign(selected_ids: MapSet.new())`.

- [ ] **Step 2: Add `handle_event("toggle_select", …)`**

Identical to Task 10's handler.

- [ ] **Step 3: Add checkbox `:col` slot inside the existing `<.table>` block**

Identical to Task 10's snippet, replacing `formula` with `ingredient` (and matching the let pattern actually used in this file).

- [ ] **Step 4: Add "Compare (N)" button in the header**

Identical structure, but targets `~p"/ingredients/compare?ids=#{...}"` and ids the link `id="compare_ingredients"`.

- [ ] **Step 5: Manual verification**

```
mix phx.server
```

Visit `/ingredients`. Check 2 ingredients; confirm Compare button appears and navigates correctly.

- [ ] **Step 6: Commit**

```bash
git add lib/least_cost_feed_web/live/ingredient_live/index.ex
git commit -m "Add selection + Compare button to Ingredient index"
```

---

## Final verification

After all tasks pass:

```
mix test
mix credo
mix phx.server
```

Manual walkthrough:
1. Log in.
2. From `/formulas`, select 3 formulas (e.g. A05, A05L, A06L). Click "Compare (3)".
3. Confirm the table renders with diff highlights on differing cells.
4. Toggle "Only differences" — irrelevant rows hide.
5. Toggle "Show actuals" — small grey actuals appear under bound specs.
6. Click ✕ on one chip — column drops, URL updates.
7. Use "+ Add" to re-add a formula.
8. Repeat from `/ingredients`.

Total commits expected: **11** (one per task).
