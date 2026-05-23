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
