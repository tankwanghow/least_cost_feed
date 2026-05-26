defmodule LeastCostFeed.GlpsolFileGen do
  alias LeastCostFeed.Helpers

  def optimize(formula, _user_id) do
    content = build_mod_content(formula)
    {result, _} = System.shell("glpsol --math /dev/stdin <<'GLPEOF'\n#{content}\nGLPEOF")
    interpret_optimize_result(result)
  end

  @doc """
  Diagnose an infeasible formula by re-solving with elastic slacks on every
  used nutrient and bounded ingredient constraint, minimizing weighted total
  violation. Ingredient slacks carry a much heavier penalty so the solver
  prefers to blame nutrients first; ingredients only show up when no amount
  of nutrient relaxation can restore feasibility.

  Returns `{:ok, %{nutrients: [..], ingredients: [..]}}` — each entry is
  `%{id, actual, shortfall, excess}`. `shortfall > 0` means below `min`;
  `excess > 0` means above `max`. Each list is sorted worst-first.
  """
  def diagnose_infeasibility(formula, _user_id) do
    content = build_diagnostic_mod_content(formula)
    {result, _} = System.shell("glpsol --math /dev/stdin <<'GLPEOF'\n#{content}\nGLPEOF")
    interpret_diagnostic_result(result)
  end

  def optimize_with_ranges(formula, _user_id) do
    content = build_mod_content(formula)
    ranges_file = "/tmp/glpk_ranges_#{System.unique_integer([:positive])}.txt"

    {result, _} =
      System.shell(
        "glpsol --math /dev/stdin --ranges '#{ranges_file}' <<'GLPEOF'\n#{content}\nGLPEOF"
      )

    ranges_text =
      case File.read(ranges_file) do
        {:ok, data} ->
          File.rm(ranges_file)
          data

        _ ->
          ""
      end

    case interpret_optimize_result(result) do
      {:ok, ingredients, nutrients} ->
        ranges = parse_ranges(ranges_text)

        nutrients_with_ranges =
          Enum.map(nutrients, fn n ->
            case Enum.find(ranges, fn r -> r.id == n.id end) do
              nil -> Map.merge(n, %{status: nil, range_low: nil, range_high: nil})
              r -> Map.merge(n, %{status: r.status, range_low: r.range_low, range_high: r.range_high})
            end
          end)

        {:ok, ingredients, nutrients_with_ranges}

      error ->
        error
    end
  end

  defp parse_ranges(ranges_text) do
    lines = String.split(ranges_text, "\n")

    lines
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, idx}, acc ->
      if Regex.match?(~r/^\s+\d+\s+n_\d+/, line) do
        line2 = Enum.at(lines, idx + 1, "")
        parts1 = String.split(String.trim(line))
        parts2 = String.split(String.trim(line2))

        id = Enum.at(parts1, 1) |> String.replace_prefix("n_", "")
        status = Enum.at(parts1, 2)
        range_low = parse_glpk_number(Enum.at(parts1, 6))
        range_high = parse_glpk_number(Enum.at(parts2, 2))

        [%{id: id, status: status, range_low: range_low, range_high: range_high} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp parse_glpk_number(nil), do: nil
  defp parse_glpk_number("."), do: 0.0
  defp parse_glpk_number("+Inf"), do: :infinity
  defp parse_glpk_number("-Inf"), do: :neg_infinity

  defp parse_glpk_number(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp interpret_optimize_result(result) do
    cond do
      String.match?(result, ~r/OPTIMAL(.+?)SOLUTION FOUND/) ->
        formula =
          Regex.scan(~r/FORMULA_START(.+?)FORMULA_END/, result)
          |> List.flatten()
          |> Enum.at(1)

        optimize_ingredients =
          (formula || "")
          |> String.split("|")
          |> Enum.filter(fn x -> x != "" end)
          |> Enum.map(fn x -> String.split(x, ",") end)
          |> Enum.map(fn x ->
            %{
              id: Enum.at(x, 0) |> String.split("_") |> Enum.at(1),
              actual: Enum.at(x, 1),
              shadow: Enum.at(x, 2)
            }
          end)

        specs =
          Regex.scan(~r/SPECS_START(.+?)SPECS_END/, result)
          |> List.flatten()
          |> Enum.at(1)

        optimize_nutrients =
          (specs ||
             "")
          |> String.split("|")
          |> Enum.filter(fn x -> x != "" end)
          |> Enum.map(fn x -> String.split(x, ",") end)
          |> Enum.map(fn x ->
            %{
              id: Enum.at(x, 0) |> String.split("_") |> Enum.at(1),
              actual: Enum.at(x, 1),
              shadow: Enum.at(x, 2)
            }
          end)

        {:ok, optimize_ingredients, optimize_nutrients}

      String.match?(result, ~r/HAS NO PRIMAL FEASIBLE SOLUTION/) ->
        {:error, "!!Not Feasible!!", result}

      true ->
        {:error, "!!mod file error!!", result}
    end
  end


  defp build_mod_content(formula) do
    formula_ingredients = filter_formula_ingredients(formula)
    formula_nutrients = filter_formula_nutrients(formula)

    varibles(formula_ingredients) <>
      objective_function(formula_ingredients) <>
      nutrient_expressions_constraints(formula_nutrients, formula_ingredients) <>
      constraint_100(formula_ingredients) <>
      ingredients_constraints(formula_ingredients) <>
      "solve;" <>
      "printf 'FORMULA_START';\n" <>
      printf_statement_for_ingredients(formula_ingredients) <>
      "printf 'FORMULA_END';\n" <>
      "printf 'SPECS_START';\n" <>
      printf_statement_for_nutrients(formula_nutrients) <>
      "printf 'SPECS_END';\n" <>
      "end;"
  end

  defp filter_formula_ingredients(formula) do
    Helpers.get_list(formula, :formula_ingredients)
    |> Enum.filter(fn x -> !Helpers.my_fetch_field!(x, :delete) and Helpers.my_fetch_field!(x, :used) end)
  end

  defp filter_formula_nutrients(formula) do
    Helpers.get_list(formula, :formula_nutrients)
    |> Enum.filter(fn x -> !Helpers.my_fetch_field!(x, :delete) end)
  end

  defp printf_statement_for_ingredient(formula_ingredient) do
    id = Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)
    "printf 'p_#{id},%.6f,%.6f|', p_#{id}.val, p_#{id}.dual;"
  end

  defp printf_statement_for_ingredients(formula_ingredients) do
    (formula_ingredients
     |> Enum.map_join("\n", fn i -> printf_statement_for_ingredient(i) end)) <> "\n"
  end

  defp printf_statement_for_nutrient(formula_nutrient) do
    "printf 'n_#{Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)},%.6f,%.6f|', n_#{Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)}.val, n_#{Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)}.dual;"
  end

  defp printf_statement_for_nutrients(formula_nutrients) do
    (formula_nutrients
     |> Enum.map_join("\n", fn n -> printf_statement_for_nutrient(n) end)) <> "\n"
  end

  defp constraint_100(formula_ingredients) do
    ("PERC: " <>
       (formula_ingredients
        |> Enum.map_join(" ", fn i -> "+p_#{Helpers.my_fetch_field!(i, :ingredient_id)}" end))) <>
      " = 1;\n"
  end

  defp nutrient_expressions_constraints(formula_nutrients, formula_ingredients) do
    formula_nutrients
    |> Enum.map(fn n -> nutrient_expressions_constraint(n, formula_ingredients) end)
    |> Enum.filter(fn n -> !is_nil(n) end)
    |> Enum.join("\n")
  end

  defp nutrient_expressions_constraint(formula_nutrient, formula_ingredients) do
    ingredients_selected_has_this_nutrient? = nutrient_expressions(formula_nutrient, formula_ingredients) |> String.trim() != ""

    if ingredients_selected_has_this_nutrient? do
      if Helpers.my_fetch_field!(formula_nutrient, :used) do
        "n_#{Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)}: " <>
          constraint(
            formula_nutrient,
            nutrient_expressions(formula_nutrient, formula_ingredients)
          )
      else
        "n_#{Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)}: " <>
          gt_zero_constraint(
            nutrient_expressions(formula_nutrient, formula_ingredients)
          )
      end
    else
      id = Enum.at(formula_ingredients, 0) |> Helpers.my_fetch_field!(:ingredient_id)
      "n_#{Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)}: " <> constraint(formula_nutrient, "+0*p_#{id}")
    end
  end

  defp nutrient_expressions(formula_nutrient, formula_ingredients) do
    formula_ingredients
    |> Enum.map(fn i -> nutrient_expression(formula_nutrient, i) end)
    |> Enum.filter(fn n -> !is_nil(n) end)
    |> Enum.join("")
  end

  defp nutrient_expression(formula_nutrient, formula_ingredient) do
    ingredient = Helpers.my_fetch_field!(formula_ingredient, :ingredient)

    ingredient_compositions =
      if is_nil(ingredient) do
        id = Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)
        LeastCostFeed.Entities.get_ingredient!(id).ingredient_compositions
      else
        Helpers.my_fetch_field!(ingredient, :ingredient_compositions)
      end

    innu =
      ingredient_compositions
      |> Enum.find(fn t ->
        Helpers.my_fetch_field!(t, :nutrient_id) ==
          Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)
      end)

    if is_nil(innu) do
      ""
    else
      if(innu.quantity > 0,
        do: "+#{innu.quantity}*p_#{Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)}",
        else: ""
      )
    end
  end

  defp ingredients_constraints(formula_ingredients) do
    (formula_ingredients
     |> Enum.map(fn i -> ingredient_constraint(i) end)
     |> Enum.filter(fn i -> !is_nil(i) end)
     |> Enum.join("\n")) <> "\n"
  end

  defp ingredient_constraint(formula_ingredient) do
    "s.t.pc_#{Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)}: " <>
      constraint(
        formula_ingredient,
        "p_#{Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)}"
      )
  end

  defp varibles(formula_ingredients) do
    (formula_ingredients |> Enum.map_join("\n", fn i -> varible(i) end)) <> "\n"
  end

  defp varible(formula_ingredient) do
    "var p_#{Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)} >= 0;"
  end

  def objective_function(formula_ingredients) do
    "minimize cost: " <>
      (formula_ingredients |> Enum.map_join(" ", fn i -> ingredient_expression(i) end)) <> ";\n"
  end

  defp ingredient_expression(formula_ingredient) do
    "+#{Helpers.my_fetch_field!(formula_ingredient, :cost)}*p_#{Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)}"
  end

  defp constraint(object, expression) do
    max = Helpers.my_fetch_field!(object, :max)
    min = Helpers.my_fetch_field!(object, :min)

    cond do
      !is_nil(max) and !is_nil(min) -> gt_lt_constraint(min, max, expression)
      !is_nil(max) and is_nil(min) -> lt_constraint(max, expression)
      is_nil(max) and !is_nil(min) -> gt_constraint(min, expression)
      true -> gt_zero_constraint(expression)
    end
  end

  defp gt_lt_constraint(min, max, expression) do
    "#{min} <= #{expression} <= #{max};"
  end

  defp gt_constraint(min, expression) do
    "#{expression} >= #{min};"
  end

  defp lt_constraint(max, expression) do
    "#{expression} <= #{max};"
  end

  defp gt_zero_constraint(expression) do
    "#{expression} >= 0;"
  end

  # ---- Infeasibility diagnostics (elastic-slack relaxation) -------------------

  defp build_diagnostic_mod_content(formula) do
    formula_ingredients = filter_formula_ingredients(formula)

    formula_nutrients =
      filter_formula_nutrients(formula)
      |> Enum.filter(&Helpers.my_fetch_field!(&1, :used))

    # Only ingredients with a real bound (non-nil min OR max) are worth slacking;
    # otherwise `pc_X: p_X >= 0` is implied by the variable declaration anyway.
    bound_ingredients =
      Enum.filter(formula_ingredients, fn fi ->
        not is_nil(Helpers.my_fetch_field!(fi, :min)) or
          not is_nil(Helpers.my_fetch_field!(fi, :max))
      end)

    varibles(formula_ingredients) <>
      slack_variables(formula_nutrients) <>
      ingredient_slack_variables(bound_ingredients) <>
      diagnostic_objective(formula_nutrients, bound_ingredients) <>
      elastic_nutrient_constraints(formula_nutrients, formula_ingredients) <>
      constraint_100(formula_ingredients) <>
      elastic_ingredients_constraints(formula_ingredients, bound_ingredients) <>
      "solve;\n" <>
      "printf 'DIAG_START';\n" <>
      diagnostic_printfs(formula_nutrients) <>
      "printf 'DIAG_END';\n" <>
      "printf 'IDIAG_START';\n" <>
      ingredient_diagnostic_printfs(bound_ingredients) <>
      "printf 'IDIAG_END';\n" <>
      "end;"
  end

  defp slack_variables(nutrients) do
    nutrients
    |> Enum.map_join("\n", fn n ->
      id = Helpers.my_fetch_field!(n, :nutrient_id)
      "var s_minus_#{id} >= 0;\nvar s_plus_#{id} >= 0;"
    end)
    |> Kernel.<>("\n")
  end

  defp ingredient_slack_variables(bound_ingredients) do
    bound_ingredients
    |> Enum.map_join("\n", fn fi ->
      id = Helpers.my_fetch_field!(fi, :ingredient_id)
      "var s_minus_i_#{id} >= 0;\nvar s_plus_i_#{id} >= 0;"
    end)
    |> Kernel.<>("\n")
  end

  # Weight = 1 / typical magnitude so a 50-kcal ME violation does not dwarf a
  # 0.05% methionine violation. Ingredient slacks get a much larger weight so
  # the solver only blames ingredient bounds when no nutrient relaxation works.
  defp diagnostic_objective(nutrients, bound_ingredients) do
    nutrient_terms =
      nutrients
      |> Enum.map_join(" ", fn n ->
        id = Helpers.my_fetch_field!(n, :nutrient_id)
        w = slack_weight(n)
        "+#{w}*s_minus_#{id} +#{w}*s_plus_#{id}"
      end)

    w_i = ingredient_slack_weight(nutrients)

    ingredient_terms =
      bound_ingredients
      |> Enum.map_join(" ", fn fi ->
        id = Helpers.my_fetch_field!(fi, :ingredient_id)
        "+#{w_i}*s_minus_i_#{id} +#{w_i}*s_plus_i_#{id}"
      end)

    terms = String.trim("#{nutrient_terms} #{ingredient_terms}")
    "minimize violation: #{terms};\n"
  end

  defp slack_weight(formula_nutrient) do
    min = Helpers.my_fetch_field!(formula_nutrient, :min)
    max = Helpers.my_fetch_field!(formula_nutrient, :max)

    scale =
      [min, max]
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> 1.0 end)

    if scale in [0, 0.0], do: 1.0, else: 1.0 / scale
  end

  # Lexicographic-ish: pick W >> any nutrient weight so the solver only spends
  # ingredient slack when no nutrient relaxation can restore feasibility.
  defp ingredient_slack_weight(nutrients) do
    max_n =
      nutrients
      |> Enum.map(&slack_weight/1)
      |> Enum.max(fn -> 1.0 end)

    max_n * 1000.0
  end

  defp elastic_nutrient_constraints(formula_nutrients, formula_ingredients) do
    formula_nutrients
    |> Enum.map_join("\n", fn n -> elastic_nutrient_constraint(n, formula_ingredients) end)
    |> Kernel.<>("\n")
  end

  defp elastic_nutrient_constraint(formula_nutrient, formula_ingredients) do
    id = Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)
    expr = nutrient_expressions(formula_nutrient, formula_ingredients)

    expr =
      if String.trim(expr) == "" do
        first_id = Enum.at(formula_ingredients, 0) |> Helpers.my_fetch_field!(:ingredient_id)
        "+0*p_#{first_id}"
      else
        expr
      end

    # s_minus lifts LHS up (covers shortfall vs. `min`);
    # s_plus pushes LHS down (covers excess vs. `max`).
    elastic = "#{expr} + s_minus_#{id} - s_plus_#{id}"
    "n_#{id}: " <> constraint(formula_nutrient, elastic)
  end

  defp diagnostic_printfs(nutrients) do
    nutrients
    |> Enum.map_join("\n", fn n ->
      id = Helpers.my_fetch_field!(n, :nutrient_id)
      "printf 'd_#{id},%.6f,%.6f,%.6f|', n_#{id}.val, s_minus_#{id}.val, s_plus_#{id}.val;"
    end)
    |> Kernel.<>("\n")
  end

  defp elastic_ingredients_constraints(formula_ingredients, bound_ingredients) do
    bound_ids =
      MapSet.new(bound_ingredients, fn fi -> Helpers.my_fetch_field!(fi, :ingredient_id) end)

    formula_ingredients
    |> Enum.map_join("\n", fn fi ->
      id = Helpers.my_fetch_field!(fi, :ingredient_id)

      if MapSet.member?(bound_ids, id) do
        elastic = "p_#{id} + s_minus_i_#{id} - s_plus_i_#{id}"
        "s.t.pc_#{id}: " <> constraint(fi, elastic)
      else
        ingredient_constraint(fi)
      end
    end)
    |> Kernel.<>("\n")
  end

  defp ingredient_diagnostic_printfs(bound_ingredients) do
    bound_ingredients
    |> Enum.map_join("\n", fn fi ->
      id = Helpers.my_fetch_field!(fi, :ingredient_id)

      "printf 'i_#{id},%.6f,%.6f,%.6f|'," <>
        " p_#{id}.val, s_minus_i_#{id}.val, s_plus_i_#{id}.val;"
    end)
    |> Kernel.<>("\n")
  end

  defp interpret_diagnostic_result(result) do
    if String.match?(result, ~r/OPTIMAL(.+?)SOLUTION FOUND/) do
      nutrient_violations =
        result
        |> extract_section(~r/DIAG_START(.+?)DIAG_END/)
        |> parse_violation_entries(&parse_nutrient_entry/1)

      ingredient_violations =
        result
        |> extract_section(~r/IDIAG_START(.+?)IDIAG_END/)
        |> parse_violation_entries(&parse_ingredient_entry/1)

      {:ok, %{nutrients: nutrient_violations, ingredients: ingredient_violations}}
    else
      {:error, "Diagnostic solve failed", result}
    end
  end

  defp extract_section(result, regex) do
    Regex.scan(regex, result)
    |> List.flatten()
    |> Enum.at(1)
    |> Kernel.||("")
  end

  defp parse_violation_entries(section, entry_parser) do
    section
    |> String.split("|")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(entry_parser)
    |> Enum.filter(&(&1.shortfall > 1.0e-6 or &1.excess > 1.0e-6))
    |> Enum.sort_by(&(-max(&1.shortfall, &1.excess)))
  end

  defp parse_nutrient_entry(entry) do
    [id_str, lhs, s_minus, s_plus] = String.split(entry, ",")
    # n_X.val is the slacked LHS: expr + s_minus - s_plus.
    # Real nutrient value = lhs - s_minus + s_plus.
    lhs_f = parse_diag_float(lhs)
    shortfall = parse_diag_float(s_minus)
    excess = parse_diag_float(s_plus)

    %{
      id: String.replace_prefix(id_str, "d_", ""),
      actual: lhs_f - shortfall + excess,
      shortfall: shortfall,
      excess: excess
    }
  end

  defp parse_ingredient_entry(entry) do
    [id_str, actual, s_minus, s_plus] = String.split(entry, ",")
    # p_X.val IS the real proportion — slacks are external to the variable.
    %{
      id: String.replace_prefix(id_str, "i_", ""),
      actual: parse_diag_float(actual),
      shortfall: parse_diag_float(s_minus),
      excess: parse_diag_float(s_plus)
    }
  end

  defp parse_diag_float(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
