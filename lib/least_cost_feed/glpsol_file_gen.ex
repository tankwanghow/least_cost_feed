defmodule LeastCostFeed.GlpsolFileGen do
  alias LeastCostFeed.Helpers

  def optimize(formula, _user_id) do
    content = build_mod_content(formula)
    {result, _} = System.shell("glpsol --math /dev/stdin <<'GLPEOF'\n#{content}\nGLPEOF")
    interpret_optimize_result(result)
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
            %{id: Enum.at(x, 0) |> String.split("_") |> Enum.at(1), actual: Enum.at(x, 1)}
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
    "printf 'p_#{Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)},%.6f,%.6f|', p_#{Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)}.val, p_#{Helpers.my_fetch_field!(formula_ingredient, :ingredient_id)}.dual;"
  end

  defp printf_statement_for_ingredients(formula_ingredients) do
    (formula_ingredients
     |> Enum.map_join("\n", fn i -> printf_statement_for_ingredient(i) end)) <> "\n"
  end

  defp printf_statement_for_nutrient(formula_nutrient) do
    "printf 'n_#{Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)},%.6f|', n_#{Helpers.my_fetch_field!(formula_nutrient, :nutrient_id)}.val;"
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
end
