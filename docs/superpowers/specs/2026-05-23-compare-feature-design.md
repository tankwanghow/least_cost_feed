# Compare Feature — Design

**Date:** 2026-05-23
**Status:** Approved (design phase)

## Goal

Let users place 2–4 formulas (or 2–4 ingredients) side-by-side and see a single
nutrient-by-nutrient table that highlights where the entities differ. The
recurring need is to compare phase variants (e.g. A05 vs A05L, or
A05/A05L/A06L) quickly without exporting CSVs or asking an assistant.

## Scope

**In scope**
- Compare 2–4 formulas, or 2–4 ingredients (separate routes).
- Diff highlighting anchored to the leftmost column.
- Optional "show only differing rows" filter.
- Optional "show actuals" overlay for formulas (default off).
- ✕ to drop a column on the compare page.
- "+ Add" typeahead picker to add a column up to the cap of 4.
- Selection on the existing index pages via a checkbox column + a
  "Compare (N)" header button.

**Out of scope (deferred)**
- Editing values inside the compare view (e.g. copy A's Lysine to B).
- Comparing against an external reference target (e.g. the Hendrix CSV).
- More than 4 entities in one view.
- Saved/named comparisons (the URL with `?ids=` is already shareable).

## Routes

| Route | LiveView | Notes |
|---|---|---|
| `GET /formulas/compare?ids=44,46,47` | `FormulaLive.Compare` | 2–4 ids; otherwise redirect to `/formulas` with flash |
| `GET /ingredients/compare?ids=663,665` | `IngredientLive.Compare` | 2–4 ids; otherwise redirect to `/ingredients` with flash |

All entities are user-scoped (existing pattern). Ids not belonging to the
current user are silently dropped; if fewer than 2 valid ids remain, redirect
with a flash explaining the cap.

## Selection (from index pages)

The existing `<.table>` in `my_components.ex` gains an optional `selectable`
attribute. When set, it renders a leading checkbox column. Selection lives
in the LiveView socket assign `:selected_ids` (`MapSet.t/0`), toggled by a
`"toggle_select"` event.

A header button reads `"Compare (N)"`. Disabled when `N < 2` or `N > 4`.
When enabled it is a `<.link navigate>` to the compare route with `?ids=`.

This mirrors the existing `multi_nutrient_relax.ex` multi-select pattern
already in the app.

## Compare page

### Layout

A header strip with one chip per selected entity (✕ to remove); a
`"+ Add"` typeahead picker (search the user's remaining formulas /
ingredients; disabled when 4 already selected); the toggles
*Only differences* and *Show actuals* (formulas only); and a Print
button.

Below the strip: a table with entities as columns and nutrients as
rows.

```
[A05] ✕   [A05L] ✕   [A06L] ✕   [+ Add ▾]    ☐ Only differences   ☐ Show actuals   [Print]
─────────────────────────────────────────────────────────────────────────────────────────
                       A05            A05L           A06L
ME (kcal/g)            2.80–2.90      2.85–2.90 ●    2.85–2.90 ●
Crude Protein %        17.0–18.0      17.5–18.0 ●    17.5–18.0 ●
Lysine min %           0.90           0.92 ●         0.92 ●
Met+Cys min %          0.81           0.88 ●         0.88 ●
Calcium %              4.0–4.2        4.1–4.3 ●      4.3–4.6 ●
Linoleic Acid min %    1.3            2.0 ●          2.0 ●
─ Phytate Phos. %      0.285          0.285          0.25 ●       ← strikethrough = used:false
```

### Row population

Rows are the union of nutrients across the selected entities, in a stable
nutrient sort order (alphabetical by name, with ME first as a convention
the app already follows).

- **Formula compare:** every nutrient that appears on at least one selected
  formula's `formula_nutrients`.
- **Ingredient compare:** only nutrients where at least one selected
  ingredient has a populated composition value. (Keeps the table short.)

Missing values render as `—`.

### Cell rendering

**Formula compare**
- `"min – max"` when both bounds are set
- `"≥ min"` when only `min` is set; `"≤ max"` when only `max` is set
- `"—"` when neither bound exists
- Disabled constraints (`used == false`) are rendered with strikethrough
- When *Show actuals* is on, the optimized `actual` is shown as a smaller
  grey subscript under the spec (no overlay when `actual` is nil)

**Ingredient compare**
- The composition `quantity` followed by the nutrient's `unit`
- `"—"` when the nutrient is not in the ingredient's compositions

### Diff highlight

Anchor = leftmost column. For each non-anchor cell, the rendered string is
compared to the anchor's rendered string. If different, the cell gets a
background tint plus a leading `●` dot. The *Only differences* toggle
filters out rows where every non-anchor cell matches the anchor.

## Data access

Two new functions in `lib/least_cost_feed/entities.ex`:

```elixir
def list_formulas_for_compare(user_id, ids) when is_list(ids) do
  Formula
  |> where(user_id: ^user_id)
  |> where([f], f.id in ^ids)
  |> preload(formula_nutrients: :nutrient)
  |> Repo.all()
end

def list_ingredients_for_compare(user_id, ids) when is_list(ids) do
  Ingredient
  |> where(user_id: ^user_id)
  |> where([i], i.id in ^ids)
  |> preload(ingredient_compositions: :nutrient)
  |> Repo.all()
end
```

## File layout

```
lib/least_cost_feed_web/live/
├── formula_live/compare.ex             + compare.html.heex
├── ingredient_live/compare.ex          + compare.html.heex
└── compare_helpers.ex                  # shared

lib/least_cost_feed/entities.ex                            # + list_*_for_compare/2
lib/least_cost_feed_web/components/my_components.ex        # ~ optional selectable column on <.table>
lib/least_cost_feed_web/live/formula_live/index.ex         # + selection state + Compare button
lib/least_cost_feed_web/live/ingredient_live/index.ex      # + selection state + Compare button
lib/least_cost_feed_web/router.ex                          # + 2 routes
```

`compare_helpers.ex` exports:

- `union_nutrient_rows(entities, type)` — returns the sorted list of
  `%Nutrient{}` rows to display, applying the per-type "skip empty rows"
  rule for ingredients.
- `cell_value(entity, nutrient, opts)` — rendered string for the cell
  (handles min/max ranges, ingredient quantity, used:false strikethrough,
  optional actual overlay).
- `differs_from_anchor?(cell, anchor_cell)` — boolean comparison of
  rendered strings.
- `filter_differing_rows(rows_with_cells)` — keeps only rows where any
  non-anchor cell differs from the anchor.

## Testing

- LiveView tests in `formula_live/compare_test.exs` and
  `ingredient_live/compare_test.exs`:
  - Renders the requested 2–4 columns.
  - Redirects with flash when fewer than 2 valid ids are given.
  - Dropping a column updates the URL and re-renders.
  - Adding a column via the picker updates the URL and re-renders.
  - Diff highlight applies to non-anchor cells that differ.
  - *Only differences* filter removes all-equal rows.
- Integration test: from the formulas index, select 3 formulas, click
  Compare, land on the compare page with the correct ids in the URL and
  data rendered.
- Unit tests for `compare_helpers`: `union_nutrient_rows`,
  `differs_from_anchor?`, `filter_differing_rows`.

## Open follow-ups (not blockers for v1)

- Compare against a reference target (Hendrix CSV) — future feature.
- Inline editing within compare — future feature.
- Persist a named comparison — future feature.
