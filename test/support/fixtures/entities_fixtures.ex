defmodule LeastCostFeed.EntitiesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `LeastCostFeed.Entities` context.

  Entities are user-scoped; pass `user_id` in attrs or a new user is created.
  """

  import LeastCostFeed.UserAccountsFixtures, only: [user_fixture: 0]

  defp with_user(attrs) do
    attrs |> Map.new() |> Map.put_new_lazy(:user_id, fn -> user_fixture().id end)
  end

  @doc """
  Generate a nutrient.
  """
  def nutrient_fixture(attrs \\ %{}) do
    {:ok, nutrient} =
      attrs
      |> with_user()
      |> Enum.into(%{
        name: "some name",
        unit: "some unit"
      })
      |> LeastCostFeed.Entities.create_nutrient()

    nutrient
  end

  @doc """
  Generate a ingredient.
  """
  def ingredient_fixture(attrs \\ %{}) do
    {:ok, ingredient} =
      attrs
      |> with_user()
      |> Enum.into(%{
        category: "some category",
        cost: 120.5,
        dry_matter: 90.0,
        description: "some description",
        name: "some name"
      })
      |> LeastCostFeed.Entities.create_ingredient()

    ingredient
  end

  @doc """
  Generate a formula.
  """
  def formula_fixture(attrs \\ %{}) do
    {:ok, formula} =
      attrs
      |> with_user()
      |> Enum.into(%{
        batch_size: 120.5,
        name: "some name",
        note: "some note",
        weight_unit: "KG",
        usage_per_day: 0.0
      })
      |> LeastCostFeed.Entities.create_formula()

    formula
  end
end
