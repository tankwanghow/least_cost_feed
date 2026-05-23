defmodule LeastCostFeedWeb.FormulaLive.CompareTest do
  use LeastCostFeedWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LeastCostFeed.Entities

  setup :register_and_log_in_user

  defp setup_two_formulas(user) do
    {:ok, n_cp} = Entities.create_nutrient(%{name: "Crude Protein", unit: "%", user_id: user.id})
    {:ok, n_lys} = Entities.create_nutrient(%{name: "Lysine", unit: "%", user_id: user.id})

    {:ok, f1} =
      Entities.create_formula(%{
        name: "F1",
        batch_size: 1000.0,
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id,
        formula_nutrients: [
          %{nutrient_id: n_cp.id, min: 17.5, max: 18.0, used: true},
          %{nutrient_id: n_lys.id, min: 0.90, used: true}
        ]
      })

    {:ok, f2} =
      Entities.create_formula(%{
        name: "F2",
        batch_size: 1000.0,
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id,
        formula_nutrients: [
          %{nutrient_id: n_cp.id, min: 17.5, max: 18.0, used: true},
          %{nutrient_id: n_lys.id, min: 0.92, used: true}
        ]
      })

    {f1, f2}
  end

  test "renders both formulas as columns with diff dot on Lysine", %{conn: conn, user: user} do
    {f1, f2} = setup_two_formulas(user)

    {:ok, _view, html} =
      live(conn, "/formulas/compare?ids=#{f1.id},#{f2.id}")

    assert html =~ "F1"
    assert html =~ "F2"
    assert html =~ "Lysine"
    assert html =~ "Crude Protein"
    assert html =~ "≥ 0.9"
    assert html =~ "≥ 0.92"
  end

  test "redirects with flash when fewer than 2 valid ids", %{conn: conn} do
    assert {:error, {:live_redirect, %{flash: flash, to: "/formulas"}}} =
             live(conn, "/formulas/compare?ids=999999")

    assert flash["error"] =~ "needs 2"
  end

  test "redirects with flash when more than 4 ids", %{conn: conn, user: user} do
    {f1, f2} = setup_two_formulas(user)

    {:ok, f3} =
      Entities.create_formula(%{
        name: "F3",
        batch_size: 1000.0,
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id
      })

    {:ok, f4} =
      Entities.create_formula(%{
        name: "F4",
        batch_size: 1000.0,
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id
      })

    {:ok, f5} =
      Entities.create_formula(%{
        name: "F5",
        batch_size: 1000.0,
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id
      })

    ids = [f1.id, f2.id, f3.id, f4.id, f5.id] |> Enum.join(",")

    assert {:error, {:live_redirect, %{flash: flash, to: "/formulas"}}} =
             live(conn, "/formulas/compare?ids=#{ids}")

    assert flash["error"] =~ "limited to 4"
  end

  test "clicking ✕ on a chip drops that formula and updates the URL", %{conn: conn, user: user} do
    {f1, f2} = setup_two_formulas(user)

    {:ok, f3} =
      Entities.create_formula(%{
        name: "F3",
        batch_size: 1000.0,
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id
      })

    {:ok, view, _html} = live(conn, "/formulas/compare?ids=#{f1.id},#{f2.id},#{f3.id}")
    view |> element("[phx-click=drop][phx-value-id='#{f3.id}']") |> render_click()

    assert_patch(view, "/formulas/compare?ids=#{f1.id},#{f2.id}")
    # F3 should no longer be a comparison column
    refute render(view) =~ ~r/<th[^>]*>\s*F3\s*<\/th>/
  end

  test "dropping below 2 redirects to /formulas with flash", %{conn: conn, user: user} do
    {f1, f2} = setup_two_formulas(user)
    {:ok, view, _html} = live(conn, "/formulas/compare?ids=#{f1.id},#{f2.id}")
    view |> element("[phx-click=drop][phx-value-id='#{f2.id}']") |> render_click()
    assert_redirected(view, "/formulas")
  end

  test "adding via the picker patches the URL with the new id", %{conn: conn, user: user} do
    {f1, f2} = setup_two_formulas(user)

    {:ok, f3} =
      Entities.create_formula(%{
        name: "F3",
        batch_size: 1000.0,
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id
      })

    {:ok, view, _html} = live(conn, "/formulas/compare?ids=#{f1.id},#{f2.id}")

    view
    |> form("form[phx-submit=add]", id: to_string(f3.id))
    |> render_submit()

    assert_patch(view, "/formulas/compare?ids=#{f1.id},#{f2.id},#{f3.id}")
  end

  test "Only differences hides rows where all non-anchor cells match anchor", %{conn: conn, user: user} do
    {f1, f2} = setup_two_formulas(user)
    # CP is the same on both (17.5–18.0), Lysine differs (0.90 vs 0.92)
    {:ok, view, html} = live(conn, "/formulas/compare?ids=#{f1.id},#{f2.id}")
    assert html =~ "Crude Protein"
    assert html =~ "Lysine"

    view |> element("input[phx-click=toggle_only_diff]") |> render_click()

    refute render(view) =~ "Crude Protein"
    assert render(view) =~ "Lysine"
  end
end
