defmodule LeastCostFeed.HenModel.DietTest do
  @moduledoc "T11: diet mapping (units, aliases, digestibility routes)."
  use LeastCostFeed.DataCase, async: true

  import LeastCostFeed.UserAccountsFixtures

  alias LeastCostFeed.{Entities, HenModel}
  alias LeastCostFeed.HenModel.{Diet, Digestibility}
  alias LeastCostFeed.HenModelFixtures, as: F

  test "alias matching is case/whitespace-insensitive and basis-aware" do
    assert Diet.classify("Lysine") == {:lys, :total}
    assert Diet.classify("  lysine ") == {:lys, :total}
    assert Diet.classify("Dig. Lysine") == {:lys, :dig}
    assert Diet.classify("SID  Lysine") == {:lys, :sid}
    assert Diet.classify("Metab. Energy Poultry") == {:me, :energy}
    assert Diet.classify("Met + Cys") == {:metcys, :total}
    assert Diet.classify("Something else") == nil
  end

  test "ME kcal/g vs kcal/kg detection" do
    assert Diet.me_kcal_per_g(2.8, "kcal/g") == 2.8
    assert Diet.me_kcal_per_g(2800.0, "kcal/g") == 2.8
    assert Diet.me_kcal_per_g(2750.0, "kcal/kg") == 2.75
    assert Diet.me_kcal_per_g(2.75, "Kcal/Kg") == 0.00275
  end

  test "CVB mapping: specific patterns win, synthetic AAs at 100 %" do
    assert Digestibility.match_ingredient("Corn Grain").feedstuff == "Maize"
    assert Digestibility.match_ingredient("Corn Gluten Meal 60").feedstuff == "Maize gluten meal"

    assert Digestibility.match_ingredient("SS Soyabean Meal HP").feedstuff ==
             "Soybean meal, solvent extracted"

    assert Digestibility.match_ingredient("Wheat Bran").feedstuff == "Wheat bran"
    assert Digestibility.match_ingredient("L-Lysine HCl").kind == :synthetic
    assert Digestibility.match_ingredient("Limestone") == nil
  end

  describe "route C on a maize + SBM + synthetic Lys/Met formula" do
    setup do
      user = user_fixture()
      %{formula: f} = F.lcf_layer_formula(user)
      %{user: user, formula: f}
    end

    test "SID equals the hand-computed CVB sum", %{user: user, formula: f} do
      {:ok, d} = HenModel.load_diet(user.id, f.id, route: :cvb)

      # Lys: 0.60*0.25*0.90 + 0.25*2.85*0.88 + 0.04*0.60*0.75 + 0.002*78.8*1.00 = 0.9376 % -> 9.376 mg/g
      assert_in_delta d.sid.lys, 9.376, 1.0e-6
      # Met: 0.6*.18*.94 + .25*.64*.90 + .04*.2*.78 + .0025*99 = 0.49926 %
      assert_in_delta d.sid.met, 4.9926, 1.0e-6
      # Met+Cys weighted by each ingredient's Met and Cys (= M+C - Met)
      assert_in_delta d.sid.metcys, 7.44345, 1.0e-6
      assert d.aa_routes.lys == :c
      assert d.unmapped == []
      assert_in_delta d.me, 0.6 * 3.35 + 0.25 * 2.45 + 0.04 * 1.3 + 0.0105 * 8.5, 1.0e-9
      assert_in_delta d.ca, 10 * (0.25 * 0.3 + 0.085 * 38 + 0.01 * 16), 1.0e-9
      assert d.source == :ingredients

      assert_in_delta d.cost_per_kg,
                      f
                      |> then(&Entities.get_formula!(&1.id))
                      |> Map.get(:cost)
                      |> Kernel./(1000),
                      1.0e-9
    end

    test "route D uses the Hendrix ratios on total AA", %{user: user, formula: f} do
      {:ok, d} = HenModel.load_diet(user.id, f.id, route: :hendrix_ratio)
      assert_in_delta d.sid.lys, 10 * 1.0441 * 0.886, 1.0e-6
      assert Diet.basis_badge(d) == "D"
    end

    test "auto uses SID nutrients (A) when the account has them, Dig. only on request", %{
      user: user,
      formula: f
    } do
      {:ok, sid_lys} =
        Entities.create_nutrient(%{name: "SID Lysine", unit: "%", user_id: user.id})

      {:ok, dig_met} =
        Entities.create_nutrient(%{name: "Dig. Methionine", unit: "%", user_id: user.id})

      formula = Entities.get_formula!(f.id)

      {:ok, _} =
        Entities.update_formula(formula, %{
          "formula_nutrients" =>
            formula.formula_nutrients
            |> Enum.map(&%{"id" => &1.id, "nutrient_id" => &1.nutrient_id})
            |> Kernel.++([
              %{"nutrient_id" => sid_lys.id, "actual" => 0.80},
              %{"nutrient_id" => dig_met.id, "actual" => 0.45}
            ])
            |> Enum.with_index()
            |> Map.new(fn {m, i} -> {"#{i}", m} end)
        })

      {:ok, auto} = HenModel.load_diet(user.id, f.id)
      assert auto.aa_routes.lys == :a
      assert_in_delta auto.sid.lys, 8.0, 1.0e-9
      assert auto.aa_routes.met == :c

      {:ok, b} = HenModel.load_diet(user.id, f.id, route: :dig_as_sid)
      assert b.aa_routes.met == :b
      assert_in_delta b.sid.met, 4.5, 1.0e-9
      assert b.aa_routes.lys == :d
      assert Enum.any?(b.warnings, &(&1 =~ "No Dig. Lys"))

      {:ok, afd} = HenModel.load_diet(user.id, f.id, route: :dig_afd)
      assert_in_delta afd.sid.met, 4.5 * 1.023, 1.0e-9
    end

    test "other users' formulas are not accessible", %{formula: f} do
      other = user_fixture()
      assert {:error, msg} = HenModel.load_diet(other.id, f.id)
      assert msg =~ "not found"
    end
  end

  test "unmapped ingredients with AA content fall back to D and are listed" do
    formula = %{
      id: 1,
      name: "X",
      cost: 2000.0,
      formula_nutrients: [],
      formula_ingredients: [
        %{
          actual: 0.5,
          ingredient_name: "Corn Grain",
          ingredient: %{
            ingredient_compositions: [
              %{nutrient_id: 1, quantity: 0.25},
              %{nutrient_id: 2, quantity: 3.3}
            ]
          }
        },
        %{
          actual: 0.5,
          ingredient_name: "Local Byproduct",
          ingredient: %{
            ingredient_compositions: [
              %{nutrient_id: 1, quantity: 1.0},
              %{nutrient_id: 2, quantity: 2.0}
            ]
          }
        }
      ]
    }

    nutrients = %{1 => %{name: "Lysine", unit: "%"}, 2 => %{name: "ME", unit: "kcal/g"}}
    {:ok, d} = Diet.from_formula(formula, nutrients, route: :cvb)
    assert d.unmapped == ["Local Byproduct"]
    assert_in_delta d.sid.lys, 10 * (0.5 * 0.25 * 0.90 + 0.5 * 1.0 * 0.886), 1.0e-9
    assert d.aa_routes.met == :none
    assert Enum.any?(d.warnings, &(&1 =~ "No CVB mapping for: Local Byproduct"))
    assert Enum.any?(d.warnings, &(&1 =~ "treated as not limiting"))
    assert_in_delta d.cost_per_kg, 2.0, 1.0e-9
  end

  test "a formula without proportions or actuals is rejected" do
    formula = %{id: 1, name: "Empty", cost: 0.0, formula_nutrients: [], formula_ingredients: []}
    assert {:error, msg} = Diet.from_formula(formula, %{})
    assert msg =~ "Optimise it first"
  end

  test "falls back to formula nutrient actuals when there are no ingredient proportions" do
    formula = %{
      id: 1,
      name: "Spec only",
      cost: 0.0,
      formula_ingredients: [],
      formula_nutrients: [%{nutrient_id: 1, actual: 1.0}, %{nutrient_id: 2, actual: 2800.0}]
    }

    {:ok, d} =
      Diet.from_formula(formula, %{
        1 => %{name: "Lysine", unit: "%"},
        2 => %{name: "ME", unit: "kcal/kg"}
      })

    assert d.source == :formula_nutrients
    assert d.me == 2.8
    assert_in_delta d.sid.lys, 8.86, 1.0e-9
    assert d.cost_per_kg == nil
  end
end
