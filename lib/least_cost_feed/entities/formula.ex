defmodule LeastCostFeed.Entities.Formula do
  use Ecto.Schema
  import Ecto.Changeset

  alias LeastCostFeed.Helpers

  schema "formulas" do
    field :name, :string
    field :batch_size, :float, default: 0.0
    field :weight_unit, :string
    field :note, :string
    field :usage_per_day, :float, default: 0.0
    field :premix_bag_weight, :float, default: 0.0
    field :premix_bag_usage_qty, :integer, default: 0
    field :premix_bags_qty, :integer, default: 0
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
    dtls = Helpers.get_list(changeset, :formula_ingredients)

    sum =
      Enum.reduce(dtls, 0.0, fn x, acc ->
        acc +
          if(!Helpers.my_fetch_field!(x, :delete),
            do:
              (Helpers.my_fetch_field!(x, :cost) |> LeastCostFeedWeb.Helpers.float_parse()) *
                (Helpers.my_fetch_field!(x, :actual) |> LeastCostFeedWeb.Helpers.float_parse()) *
                (Helpers.my_fetch_field!(changeset, :batch_size)
                 |> LeastCostFeedWeb.Helpers.float_parse()),
            else: 0.0
          )
      end)

    bz = Helpers.my_fetch_field!(changeset, :batch_size) |> LeastCostFeedWeb.Helpers.float_parse()

    if bz > 0.0 do
      changeset |> force_change(:cost, sum / bz * 1000.0)
    else
      changeset
    end
  end
end
