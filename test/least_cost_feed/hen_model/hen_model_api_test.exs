defmodule LeastCostFeed.HenModelTest do
  use LeastCostFeed.DataCase, async: true

  import LeastCostFeed.UserAccountsFixtures

  alias LeastCostFeed.HenModel
  alias LeastCostFeed.HenModelFixtures, as: F

  setup do
    user = user_fixture()
    a = F.lcf_layer_formula(user)

    b =
      F.lcf_layer_formula(user,
        name: "Layer Low Lys",
        scales: %{"L-Lysine HCl" => 0.0, "SS Soyabean Meal HP" => 0.7},
        nutrients: a.nutrients,
        ingredients: a.ingredients
      )

    %{user: user, a: a.formula, b: b.formula}
  end

  test "simulate a user's formula over a short cycle", %{user: user, a: a} do
    assert {:ok, r} =
             HenModel.simulate(user.id, a.id, %{start_week: 25, end_week: 35, temp_c: 28.0})

    assert length(r.weeks) == 11
    assert hd(r.diets).name == "Layer Test"
    assert is_number(r.summary.avg_lay)
  end

  test "phase programme and snapshot", %{user: user, a: a, b: b} do
    prog = [%{from_week: 18, formula_id: a.id}, %{from_week: 30, formula_id: "#{b.id}"}]
    {:ok, r} = HenModel.simulate(user.id, prog, %{end_week: 32})
    assert Enum.find(r.weeks, &(&1.week == 29)).formula == "Layer Test"
    assert Enum.find(r.weeks, &(&1.week == 30)).formula == "Layer Low Lys"

    {:ok, s} = HenModel.simulate(user.id, a.id, %{mode: :snapshot, snapshot_week: 40})
    assert length(s.weeks) == 1
  end

  test "compare 2 formulas, deltas vs first column", %{user: user, a: a, b: b} do
    {:ok, results} =
      HenModel.compare(user.id, [a.id, b.id], %{end_week: 40, egg_pricing: {:per_kg, 6.0}})

    assert Enum.map(results, & &1.name) == ["Layer Test", "Layer Low Lys"]
    rows = HenModel.compare_rows(results)
    eggs = Enum.find(rows, &(&1.key == :eggs_hh))
    assert hd(eggs.deltas) == 0.0
    assert Enum.at(eggs.deltas, 1) < 0, "a lower-Lys formula should reduce eggs"
    assert Enum.find(rows, &(&1.key == :margin_hh)).values |> Enum.all?(&is_number/1)
  end

  test "compare limits and scoping", %{user: user, a: a} do
    assert {:error, _} = HenModel.compare(user.id, [a.id])
    assert {:error, _} = HenModel.compare(user.id, [1, 2, 3, 4, 5])
    other = user_fixture()
    other_f = F.lcf_layer_formula(other, name: "Other").formula
    assert {:error, msg} = HenModel.compare(user.id, [a.id, other_f.id])
    assert msg =~ "not found"
  end

  test "spec_for writes model specs to the user's nutrients", %{user: user} do
    nutrients = HenModel.nutrients_by_id(user.id) |> Map.values()
    specs = HenModel.spec_for(%{age_weeks: 40, temp_c: 25.0, intake_g: 115.0}, nutrients)
    by_name = Map.new(specs, &{&1.nutrient_name, &1})

    # total Lys via route D: requirement / 0.886 / (115 g * 10)
    assert by_name["Lysine"].min > 0.7 and by_name["Lysine"].min < 0.9
    assert by_name["Calcium"].min == Float.round(3700 / 1150, 3)
    assert by_name["Calcium"].max == Float.round(4200 / 1150, 3)
    assert_in_delta by_name["Metab. Energy Poultry"].min, 2.8, 0.15
    assert Enum.all?(specs, &(&1.used and &1.actual == 0.0))
  end
end
