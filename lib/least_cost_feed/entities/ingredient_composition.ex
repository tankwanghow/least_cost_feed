defmodule LeastCostFeed.Entities.IngredientComposition do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredient_compositions" do
    field :quantity, :float
    belongs_to :nutrient, LeastCostFeed.Entities.Nutrient
    belongs_to :ingredient, LeastCostFeed.Entities.Ingredient

    field :nutrient_name, :string, virtual: true
    field :nutrient_unit, :string, virtual: true

    field :delete, :boolean, virtual: true, default: false
  end

  @doc false
  def changeset(ing_com, attrs) do
    ing_com
    |> cast(attrs, [
      :nutrient_name,
      :nutrient_id,
      :quantity,
      :ingredient_id,
      :nutrient_unit,
      :delete
    ])
    |> validate_required([:nutrient_id, :quantity])
    |> unsafe_validate_unique([:nutrient_id, :ingredient_id], LeastCostFeed.Repo)
    |> unique_constraint(:nutrient_id, name: :ingredient_unique_nutrient)
    |> maybe_mark_for_deletion()
  end

  defp maybe_mark_for_deletion(%{data: %{id: nil}} = changeset), do: changeset

  defp maybe_mark_for_deletion(changeset) do
    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
