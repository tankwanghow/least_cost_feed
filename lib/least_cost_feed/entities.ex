defmodule LeastCostFeed.Entities do
  import Ecto.Query, warn: false
  alias LeastCostFeed.Repo

  alias LeastCostFeed.Entities.Nutrient

  def list_entities(query, page: page, per_page: per_page) do
    from(q in query,
      offset: ^((page - 1) * per_page),
      limit: ^per_page
    )
    |> Repo.all()
  end

  def get_nutrient!(id), do: Repo.get!(Nutrient, id)

  def create_nutrient(attrs \\ %{}) do
    %Nutrient{}
    |> Nutrient.changeset(attrs)
    |> Repo.insert()
  end

  def update_nutrient(%Nutrient{} = nutrient, attrs) do
    nutrient
    |> Nutrient.changeset(attrs)
    |> Repo.update()
  end

  def delete_nutrient(%Nutrient{} = nutrient) do
    Repo.delete(nutrient)
  end

  def change_nutrient(%Nutrient{} = nutrient, attrs \\ %{}) do
    Nutrient.changeset(nutrient, attrs)
  end
end
