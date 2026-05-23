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
