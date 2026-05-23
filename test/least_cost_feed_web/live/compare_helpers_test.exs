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

  describe "cell_value/3 for formulas" do
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
end
