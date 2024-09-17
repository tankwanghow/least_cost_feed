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
end
