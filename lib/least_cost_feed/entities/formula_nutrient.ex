defmodule LeastCostFeed.Entities.FormulaNutrient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "formula_nutrients" do
    field :min, :float
    field :max, :float
    field :actual, :float
    field :used, :boolean, default: true
    belongs_to :nutrient, LeastCostFeed.Entities.Nutrient
    belongs_to :formula, LeastCostFeed.Entities.Formula

    field :nutrient_name, :string, virtual: true
    field :nutrient_unit, :string, virtual: true
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
      :nutrient_id,
      :formula_id,
      :delete,
      :nutrient_name,
      :nutrient_unit
    ])
    |> validate_required([:nutrient_id])
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
