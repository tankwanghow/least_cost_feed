defmodule LeastCostFeed.EntitiesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `LeastCostFeed.Entities` context.
  """

  @doc """
  Generate a nutrient.
  """
  def nutrient_fixture(attrs \\ %{}) do
    {:ok, nutrient} =
      attrs
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
      |> Enum.into(%{
        category: "some category",
        cost: 120.5,
        description: "some description",
        name: "some name",
        unit: "some unit"
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
      |> Enum.into(%{
        batch_size: 120.5,
        name: "some name",
        note: "some note"
      })
      |> LeastCostFeed.Entities.create_formula()

    formula
  end
end
