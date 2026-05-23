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

  @doc """
  Renders the displayed cell for an (entity, nutrient) pair.

  Returns a map: `%{text: String.t(), strike: boolean(), actual: String.t() | nil}`.
  """
  def cell_value(entity, nutrient, type, opts \\ [])

  def cell_value(%Formula{} = formula, nutrient, :formula, opts) do
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

  def cell_value(%Ingredient{} = ingredient, nutrient, :ingredient, _opts) do
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

  defp format_num(n) when is_float(n), do: Float.to_string(n)
  defp format_num(n), do: to_string(n)

  defp dedup_sort(nutrients) do
    nutrients
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end
end
