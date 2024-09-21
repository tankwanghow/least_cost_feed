defmodule LeastCostFeed.Entities.FormulaIngredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "formula_ingredients" do
    field :min, :float
    field :max, :float
    field :actual, :float
    field :cost, :float, default: 0.0
    field :shadow, :float
    field :used, :boolean, default: true
    belongs_to :ingredient, LeastCostFeed.Entities.Ingredient
    belongs_to :formula, LeastCostFeed.Entities.Formula

    field :ingredient_name, :string, virtual: true
    field :weight, :float, virtual: true
    field :amount, :float, virtual: true
    field :delete, :boolean, virtual: true, default: false
  end

  @doc false
  def changeset(formula_nutrient, attrs) do
    formula_nutrient
    |> cast(attrs, [
      :min,
      :max,
      :actual,
      :used,
      :cost,
      :shadow,
      :ingredient_id,
      :formula_id,
      :weight,
      :amount,
      :ingredient_name,
      :delete
    ])
    |> validate_required([:ingredient_id])
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
