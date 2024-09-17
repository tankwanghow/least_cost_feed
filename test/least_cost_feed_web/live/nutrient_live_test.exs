defmodule LeastCostFeedWeb.NutrientLiveTest do
  use LeastCostFeedWeb.ConnCase

  import Phoenix.LiveViewTest
  import LeastCostFeed.EntitiesFixtures

  @create_attrs %{name: "some name", unit: "some unit"}
  @update_attrs %{name: "some updated name", unit: "some updated unit"}
  @invalid_attrs %{name: nil, unit: nil}

  defp create_nutrient(_) do
    nutrient = nutrient_fixture()
    %{nutrient: nutrient}
  end

  describe "Index" do
    setup [:create_nutrient]

    test "lists all nutrients", %{conn: conn, nutrient: nutrient} do
      {:ok, _index_live, html} = live(conn, ~p"/nutrients")

      assert html =~ "Listing Nutrients"
      assert html =~ nutrient.name
    end

    test "saves new nutrient", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/nutrients")

      assert index_live |> element("a", "New Nutrient") |> render_click() =~
               "New Nutrient"

      assert_patch(index_live, ~p"/nutrients/new")

      assert index_live
             |> form("#nutrient-form", nutrient: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#nutrient-form", nutrient: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/nutrients")

      html = render(index_live)
      assert html =~ "Nutrient created successfully"
      assert html =~ "some name"
    end

    test "updates nutrient in listing", %{conn: conn, nutrient: nutrient} do
      {:ok, index_live, _html} = live(conn, ~p"/nutrients")

      assert index_live |> element("#nutrients-#{nutrient.id} a", "Edit") |> render_click() =~
               "Edit Nutrient"

      assert_patch(index_live, ~p"/nutrients/#{nutrient}/edit")

      assert index_live
             |> form("#nutrient-form", nutrient: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#nutrient-form", nutrient: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/nutrients")

      html = render(index_live)
      assert html =~ "Nutrient updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes nutrient in listing", %{conn: conn, nutrient: nutrient} do
      {:ok, index_live, _html} = live(conn, ~p"/nutrients")

      assert index_live |> element("#nutrients-#{nutrient.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#nutrients-#{nutrient.id}")
    end
  end

  describe "Show" do
    setup [:create_nutrient]

    test "displays nutrient", %{conn: conn, nutrient: nutrient} do
      {:ok, _show_live, html} = live(conn, ~p"/nutrients/#{nutrient}")

      assert html =~ "Show Nutrient"
      assert html =~ nutrient.name
    end

    test "updates nutrient within modal", %{conn: conn, nutrient: nutrient} do
      {:ok, show_live, _html} = live(conn, ~p"/nutrients/#{nutrient}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Nutrient"

      assert_patch(show_live, ~p"/nutrients/#{nutrient}/show/edit")

      assert show_live
             |> form("#nutrient-form", nutrient: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#nutrient-form", nutrient: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/nutrients/#{nutrient}")

      html = render(show_live)
      assert html =~ "Nutrient updated successfully"
      assert html =~ "some updated name"
    end
  end
end
