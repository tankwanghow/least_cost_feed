defmodule LeastCostFeed.Entities.Formula do
  use Ecto.Schema
  import Ecto.Changeset

  schema "formulas" do
    field :name, :string
    field :batch_size, :float, default: 0.0
    field :weight_unit, :string
    field :note, :string
    field :usage_per_day, :float, default: 0.0
    field :cost, :float, virtual: true
    belongs_to :user, LeastCostFeed.UserAccounts.User
    has_many :formula_ingredients, LeastCostFeed.Entities.FormulaIngredient
    has_many :formula_nutrients, LeastCostFeed.Entities.FormulaNutrient

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(formula, attrs) do
    formula
    |> cast(attrs, [:name, :batch_size, :note, :weight_unit, :cost, :usage_per_day, :user_id])
    |> validate_required([:name, :weight_unit, :batch_size, :user_id])
    |> cast_assoc(:formula_ingredients)
    |> cast_assoc(:formula_nutrients)
  end

  def refresh_cost(changeset) do
    dtls = get_change_or_data(changeset, :formula_ingredients)

    sum =
      Enum.reduce(dtls, 0.0, fn x, acc ->
        func =
          if is_struct(x, Ecto.Changeset) do
            &fetch_field!/2
          else
            &Map.fetch!/2
          end

        acc +
          if(!func.(x, :delete),
            do: func.(x, :cost) * func.(x, :actual) * fetch_field!(changeset, :batch_size),
            else: 0.0
          )
      end)

    changeset |> put_change(:cost, :erlang.float_to_binary(sum, [:compact, decimals: 4]))
  end

  def get_change_or_data(changeset, detail_name) do
    list =
      if is_nil(get_change(changeset, detail_name)) do
        Map.fetch!(changeset.data, detail_name)
      else
        get_change(changeset, detail_name)
      end

    if is_struct(list, Ecto.Association.NotLoaded), do: [], else: list
  end
end
