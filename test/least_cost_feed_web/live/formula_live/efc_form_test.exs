defmodule LeastCostFeedWeb.FormulaLive.EfcFormTest do
  @moduledoc "T16: simulator and compare tabs render for the user's formulas; other users' formulas are not accessible."
  use LeastCostFeedWeb.ConnCase

  import Phoenix.LiveViewTest
  import LeastCostFeed.UserAccountsFixtures

  alias LeastCostFeed.HenModelFixtures, as: F

  setup :register_and_log_in_user

  setup %{user: user} do
    a = F.lcf_layer_formula(user)

    b =
      F.lcf_layer_formula(user,
        name: "Layer Low Lys",
        scales: %{"L-Lysine HCl" => 0.0, "SS Soyabean Meal HP" => 0.7},
        nutrients: a.nutrients,
        ingredients: a.ingredients
      )

    %{a: a.formula, b: b.formula}
  end

  test "spec generator still works with the legacy basis (default)", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/formulas/efc_optimizer")
    assert html =~ "EFC Nutrient Spec Generator"
    html = view |> element("#generate-specs") |> render_click()
    assert html =~ "Lysine"
    assert html =~ "Generated"
  end

  test "spec generator with the Hisex Brown basis", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/formulas/efc_optimizer")
    view |> form("#spec-form", %{basis: "hisex"}) |> render_change()
    html = view |> element("#generate-specs") |> render_click()
    assert html =~ "Lysine"
    assert html =~ "Calcium"
    assert html =~ "Hisex Brown model"
  end

  test "simulator tab runs a cycle for the user's formula", %{conn: conn, a: a} do
    {:ok, view, html} = live(conn, ~p"/formulas/efc_optimizer?tab=simulator")
    assert html =~ "Hisex Brown Hen Simulator"
    assert html =~ "Layer Test"

    html =
      view
      |> form("#sim-form", %{
        sim: %{
          "prog" => %{"0" => %{"formula_id" => "#{a.id}"}},
          "start_week" => "20",
          "end_week" => "40",
          "egg_price" => "6.0"
        }
      })
      |> render_submit()

    assert html =~ "sim-results"
    assert html =~ "Eggs / hen housed"
    assert html =~ "First-limiting"
    assert html =~ "Assumptions &amp; limits"
    assert html =~ "geno_sigma_emax"
    assert html =~ "PLACEHOLDER"
    assert html =~ "digestibility C"
    assert html =~ "<svg"
    refute html =~ "sim-error"
  end

  test "simulator phase programme and snapshot", %{conn: conn, a: a, b: b} do
    {:ok, view, _} = live(conn, ~p"/formulas/efc_optimizer?tab=simulator")

    html =
      view
      |> form("#sim-form", %{
        sim: %{
          "prog" => %{
            "0" => %{"formula_id" => "#{a.id}"},
            "1" => %{"formula_id" => "#{b.id}", "from_week" => "30"}
          },
          "start_week" => "25",
          "end_week" => "35"
        }
      })
      |> render_submit()

    assert html =~ "Layer Low Lys"
    assert html =~ "Formula</th>"

    html =
      view
      |> form("#sim-form", %{sim: %{"mode" => "snapshot", "snapshot_week" => "45"}})
      |> render_submit()

    assert html =~ "sim-weeks"
  end

  test "simulator refuses another user's formula", %{conn: conn} do
    other = user_fixture()
    other_f = F.lcf_layer_formula(other, name: "Secret Formula").formula
    {:ok, view, html} = live(conn, ~p"/formulas/efc_optimizer?tab=simulator")
    refute html =~ "Secret Formula"

    html =
      render_submit(view, "sim_run", %{
        "sim" => %{"prog" => %{"0" => %{"formula_id" => "#{other_f.id}"}}, "end_week" => "30"}
      })

    assert html =~ "not found"
    refute html =~ "sim-results"
  end

  test "compare tab compares two formulas with deltas", %{conn: conn, a: a, b: b} do
    {:ok, view, html} = live(conn, ~p"/formulas/efc_optimizer?tab=compare")
    assert html =~ "Compare Formulas on Hisex Brown"

    html =
      render_submit(view, "compare_run", %{
        "compare_ids" => ["#{a.id}", "#{b.id}"],
        "sim" => %{"end_week" => "40", "egg_price" => "6"}
      })

    assert html =~ "compare-table"
    assert html =~ "Eggs / hen housed"
    assert html =~ "Layer Low Lys"
    assert html =~ "(Δ "
    assert html =~ "Assumptions &amp; limits"
  end

  test "compare needs two formulas and refuses other users' formulas", %{conn: conn, a: a} do
    other_f = F.lcf_layer_formula(user_fixture(), name: "Other").formula
    {:ok, view, _} = live(conn, ~p"/formulas/efc_optimizer?tab=compare")

    assert render_submit(view, "compare_run", %{"compare_ids" => ["#{a.id}"]}) =~ "needs 2"

    assert render_submit(view, "compare_run", %{"compare_ids" => ["#{a.id}", "#{other_f.id}"]}) =~
             "not found"
  end

  test "per-egg pricing needs bands", %{conn: conn, a: a} do
    {:ok, view, _} = live(conn, ~p"/formulas/efc_optimizer?tab=simulator")

    html =
      render_submit(view, "sim_run", %{
        "sim" => %{
          "prog" => %{"0" => %{"formula_id" => "#{a.id}"}},
          "end_week" => "25",
          "egg_pricing" => "per_egg"
        }
      })

    assert html =~ "grade band"

    html =
      render_submit(view, "sim_run", %{
        "sim" => %{"grade_bands" => "Small,,55,0.30\nLarge,55,,0.40"}
      })

    assert html =~ "sim-results"
  end
end
