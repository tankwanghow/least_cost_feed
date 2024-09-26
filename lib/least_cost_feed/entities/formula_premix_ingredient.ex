defmodule LeastCostFeed.Entities.FormulaPremixIngredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "formula_premix_ingredients" do
    field :formula_quantity, :float
    field :premix_quantity, :float, default: 0.0
    belongs_to :ingredient, LeastCostFeed.Entities.Ingredient
    belongs_to :formula, LeastCostFeed.Entities.Formula

    field :ingredient_name, :string, virtual: true
    field :delete, :boolean, virtual: true, default: false
  end

  @doc false
  def changeset(fpi, attrs) do
    fpi
    |> cast(attrs, [
      :formula_quantity,
      :premix_quantity,
      :ingredient_id,
      :formula_id,
      :ingredient_name,
      :delete
    ])
    |> validate_required([:ingredient_id])
    |> validate_number(:premix_quantity, greater_than_or_equal_to: 0.0)
    |> validate_formula_premit_qty()
    |> maybe_mark_for_deletion()
  end

  defp validate_formula_premit_qty(cs) do
    if fetch_field!(cs, :premix_quantity) > fetch_field!(cs, :formula_quantity) do
      add_error(cs, :premix_quantity, "need to be smaller")
    else
      cs
    end
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
