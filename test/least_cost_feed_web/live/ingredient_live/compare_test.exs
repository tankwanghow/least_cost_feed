defmodule LeastCostFeedWeb.IngredientLive.CompareTest do
  use LeastCostFeedWeb.ConnCase
  import Phoenix.LiveViewTest
  alias LeastCostFeed.Entities

  setup :register_and_log_in_user

  test "renders two ingredients side-by-side with diff highlight", %{conn: conn, user: user} do
    {:ok, n} = Entities.create_nutrient(%{name: "Crude Protein", unit: "%", user_id: user.id})

    {:ok, i1} =
      Entities.create_ingredient(%{
        name: "Corn",
        cost: 1.2,
        dry_matter: 90.0,
        category: "x",
        description: "",
        user_id: user.id,
        ingredient_compositions: [%{nutrient_id: n.id, quantity: 7.5}]
      })

    {:ok, i2} =
      Entities.create_ingredient(%{
        name: "SBM",
        cost: 1.85,
        dry_matter: 90.0,
        category: "x",
        description: "",
        user_id: user.id,
        ingredient_compositions: [%{nutrient_id: n.id, quantity: 44.0}]
      })

    {:ok, _view, html} = live(conn, "/ingredients/compare?ids=#{i1.id},#{i2.id}")
    assert html =~ "Corn"
    assert html =~ "SBM"
    assert html =~ "Crude Protein"
    assert html =~ "7.5"
    assert html =~ "44.0"
  end

  test "redirects when fewer than 2 valid ids", %{conn: conn} do
    assert {:error, {:live_redirect, %{flash: flash, to: "/ingredients"}}} =
             live(conn, "/ingredients/compare?ids=999999")

    assert flash["error"] =~ "needs 2"
  end
end
