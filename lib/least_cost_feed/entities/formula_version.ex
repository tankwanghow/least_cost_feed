defmodule LeastCostFeed.Entities.FormulaVersion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "formula_versions" do
    field :version, :integer
    field :note, :string
    field :snapshot, :map
    belongs_to :formula, LeastCostFeed.Entities.Formula

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(formula_version, attrs) do
    formula_version
    |> cast(attrs, [:formula_id, :version, :note, :snapshot])
    |> validate_required([:formula_id, :version, :snapshot])
  end
end
