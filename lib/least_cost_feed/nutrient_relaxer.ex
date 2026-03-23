defmodule LeastCostFeed.NutrientRelaxer do
  @moduledoc """
  Shadow-price-based constraint relaxation optimizer.

  Uses GLPK sensitivity analysis (--ranges) to find optimal relaxation points
  for binding nutrient constraints in a single solve, instead of binary search.
  """

  alias LeastCostFeed.{Entities, GlpsolFileGen, Helpers}

  @max_relax 0.05
  @shadow_threshold 0.001

  def optimize_multi(formula_ids) do
    formulas = Enum.map(formula_ids, fn id -> Entities.get_formula!(id) end)

    formula_results =
      Enum.map(formulas, fn formula ->
        changeset = Entities.change_formula(formula)
        result = optimize(changeset)

        %{
          formula_id: formula.id,
          formula_name: formula.name,
          usage_per_day: formula.usage_per_day || 0.0,
          result: result
        }
      end)

    total_baseline =
      Enum.reduce(formula_results, 0.0, fn fr, acc ->
        case fr.result do
          {:ok, baseline_cost, _suggestions, _combined} ->
            acc + baseline_cost * fr.usage_per_day

          _ ->
            acc
        end
      end)

    ranked =
      formula_results
      |> Enum.flat_map(fn fr ->
        case fr.result do
          {:ok, _baseline_cost, suggestions, _combined} ->
            Enum.map(suggestions, fn s ->
              daily_savings = Float.round(s.individual_savings * fr.usage_per_day / 1000, 2)

              Map.merge(s, %{
                formula_id: fr.formula_id,
                formula_name: fr.formula_name,
                usage_per_day: fr.usage_per_day,
                daily_savings: daily_savings
              })
            end)

          _ ->
            []
        end
      end)
      |> Enum.sort_by(& &1.daily_savings, :desc)

    {:ok,
     %{
       total_baseline_daily_cost: Float.round(total_baseline, 2),
       formula_results: formula_results,
       ranked_suggestions: ranked
     }}
  end

  def optimize(formula_changeset) do
    case GlpsolFileGen.optimize_with_ranges(formula_changeset, nil) do
      {:ok, ingredients, nutrients} ->
        baseline_cost = compute_cost(formula_changeset, ingredients)
        suggestions = compute_suggestions(formula_changeset, nutrients, baseline_cost)
        combined = try_combined(formula_changeset, suggestions, baseline_cost)
        {:ok, baseline_cost, suggestions, combined}

      {:error, msg, _output} ->
        {:error, msg}
    end
  end

  defp compute_cost(changeset, opt_ingredients) do
    formula_ingredients =
      Helpers.get_list(changeset, :formula_ingredients)
      |> Enum.filter(fn x ->
        !Helpers.my_fetch_field!(x, :delete) and Helpers.my_fetch_field!(x, :used)
      end)

    Enum.reduce(opt_ingredients, 0.0, fn i, acc ->
      fi =
        Enum.find(formula_ingredients, fn fi ->
          "#{Helpers.my_fetch_field!(fi, :ingredient_id)}" == i.id
        end)

      if fi do
        actual = String.to_float(i.actual)
        cost = Helpers.my_fetch_field!(fi, :cost) || 0.0
        acc + actual * cost
      else
        acc
      end
    end)
  end

  defp compute_suggestions(changeset, nutrients, _baseline_cost) do
    formula_nutrients =
      Helpers.get_list(changeset, :formula_nutrients)
      |> Enum.filter(fn x ->
        !Helpers.my_fetch_field!(x, :delete) and Helpers.my_fetch_field!(x, :used)
      end)

    nutrients
    |> Enum.flat_map(fn n ->
      fn_ =
        Enum.find(formula_nutrients, fn fn_ ->
          "#{Helpers.my_fetch_field!(fn_, :nutrient_id)}" == n.id
        end)

      if fn_ do
        shadow = String.to_float(n.shadow)
        actual = String.to_float(n.actual)
        min_val = Helpers.my_fetch_field!(fn_, :min)
        max_val = Helpers.my_fetch_field!(fn_, :max)
        nutrient_id = Helpers.my_fetch_field!(fn_, :nutrient_id)
        nutrient_name = Helpers.my_fetch_field!(fn_, :nutrient_name) || ""
        nutrient_unit = Helpers.my_fetch_field!(fn_, :nutrient_unit) || ""

        cond do
          # Min constraint binding (NL): shadow > 0, actual ≈ min
          shadow > @shadow_threshold and min_val != nil and abs(actual - min_val) < 0.0001 ->
            suggested = compute_min_relaxation(min_val, n.range_low)
            savings = Float.round(shadow * (min_val - suggested) * 1000, 2)

            if savings > 0 do
              [
                %{
                  nutrient_id: nutrient_id,
                  nutrient_name: nutrient_name,
                  nutrient_unit: nutrient_unit,
                  field: :min,
                  current: min_val,
                  suggested: suggested,
                  individual_savings: savings
                }
              ]
            else
              []
            end

          # Max constraint binding (NU): shadow < 0, actual ≈ max
          shadow < -@shadow_threshold and max_val != nil and abs(actual - max_val) < 0.0001 ->
            suggested = compute_max_relaxation(max_val, n.range_high)
            savings = Float.round(abs(shadow) * (suggested - max_val) * 1000, 2)

            if savings > 0 do
              [
                %{
                  nutrient_id: nutrient_id,
                  nutrient_name: nutrient_name,
                  nutrient_unit: nutrient_unit,
                  field: :max,
                  current: max_val,
                  suggested: suggested,
                  individual_savings: savings
                }
              ]
            else
              []
            end

          true ->
            []
        end
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.individual_savings, :desc)
  end

  # For min binding: relax down to max(range_low, current * (1 - max_relax))
  defp compute_min_relaxation(current, range_low) do
    max_relax_point = Float.round(current * (1 - @max_relax), 4)

    limit =
      case range_low do
        :neg_infinity -> max_relax_point
        f when is_float(f) -> max(f, max_relax_point)
        _ -> max_relax_point
      end

    Float.round(limit, 4)
  end

  # For max binding: relax up to min(range_high, current * (1 + max_relax))
  defp compute_max_relaxation(current, range_high) do
    max_relax_point = Float.round(current * (1 + @max_relax), 4)

    limit =
      case range_high do
        :infinity -> max_relax_point
        f when is_float(f) -> min(f, max_relax_point)
        _ -> max_relax_point
      end

    Float.round(limit, 4)
  end

  defp try_combined(changeset, suggestions, baseline_cost) do
    if length(suggestions) < 2 do
      nil
    else
      changes = Enum.map(suggestions, fn s -> {s.nutrient_id, s.field, s.suggested} end)
      modified = apply_nutrient_changes(changeset, changes)

      case GlpsolFileGen.optimize(modified, nil) do
        {:ok, ingredients, _nutrients} ->
          cost = compute_cost(modified, ingredients)
          savings = Float.round((baseline_cost - cost) * 1000, 2)

          %{
            suggestions: suggestions,
            combined_cost: cost,
            combined_savings: savings
          }

        _ ->
          nil
      end
    end
  end

  defp apply_nutrient_changes(changeset, changes) do
    formula_nutrients = Ecto.Changeset.get_assoc(changeset, :formula_nutrients)

    new_nutrients =
      Enum.map(formula_nutrients, fn fn_ ->
        nutrient_id = Ecto.Changeset.get_field(fn_, :nutrient_id)

        case Enum.find(changes, fn {id, _, _} -> id == nutrient_id end) do
          {_, field, value} -> Ecto.Changeset.change(fn_, %{field => value})
          nil -> fn_
        end
      end)

    Ecto.Changeset.put_assoc(changeset, :formula_nutrients, new_nutrients)
  end
end
