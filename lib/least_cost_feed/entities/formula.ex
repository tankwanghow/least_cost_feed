defmodule LeastCostFeed.Entities.Formula do
  use Ecto.Schema
  import Ecto.Changeset

  alias LeastCostFeed.Helpers

  schema "formulas" do
    field :name, :string
    field :batch_size, :float
    field :weight_unit, :string
    field :note, :string
    field :usage_per_day, :float
    field :target_premix_weight, :float
    field :premix_bag_usage_qty, :integer
    field :premix_bag_make_qty, :integer
    field :premix_batch_weight, :float

    belongs_to :user, LeastCostFeed.UserAccounts.User

    has_many :formula_ingredients, LeastCostFeed.Entities.FormulaIngredient,
      on_delete: :delete_all

    has_many :formula_nutrients, LeastCostFeed.Entities.FormulaNutrient, on_delete: :delete_all

    has_many :formula_premix_ingredients, LeastCostFeed.Entities.FormulaPremixIngredient,
      on_delete: :delete_all

    field :left_premix_bag_weight, :float, virtual: true
    field :true_premix_bag_weight, :float, virtual: true
    field :cost, :float, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(formula, attrs) do
    formula
    |> cast(attrs, [:name, :batch_size, :note, :weight_unit, :cost, :usage_per_day, :user_id])
    |> validate_required([:name, :weight_unit, :batch_size, :user_id, :usage_per_day])
    |> validate_number(:batch_size, greater_than_or_equal_to: 0)
    |> cast_assoc(:formula_ingredients)
    |> cast_assoc(:formula_nutrients)
  end

  def premix_changeset(formula, attrs) do
    formula
    |> cast(attrs, [
      :target_premix_weight,
      :premix_bag_usage_qty,
      :premix_bag_make_qty,
      :user_id,
      :premix_batch_weight,
      :name,
      :weight_unit
    ])
    |> validate_required([
      :target_premix_weight,
      :premix_bag_usage_qty,
      :premix_bag_make_qty,
      :premix_batch_weight,
      :user_id
    ])
    |> validate_number(:premix_bag_make_qty, greater_than: 0)
    |> validate_number(:premix_bag_usage_qty, greater_than_or_equal_to: 1)
    |> validate_number(:target_premix_weight, greater_than_or_equal_to: 0)
    |> cast_assoc(:formula_premix_ingredients)
  end

  def refresh_cost(changeset) do
    dtls = Helpers.get_list(changeset, :formula_ingredients)

    sum =
      Enum.reduce(dtls, 0.0, fn x, acc ->
        acc +
          if(Helpers.my_fetch_field!(x, :delete),
            do: 0.0,
            else:
              (Helpers.my_fetch_field!(x, :cost) |> LeastCostFeedWeb.Helpers.float_parse()) *
                (Helpers.my_fetch_field!(x, :actual) |> LeastCostFeedWeb.Helpers.float_parse()) *
                (Helpers.my_fetch_field!(changeset, :batch_size)
                 |> LeastCostFeedWeb.Helpers.float_parse())
          )
      end)

    bz = Helpers.my_fetch_field!(changeset, :batch_size) |> LeastCostFeedWeb.Helpers.float_parse()

    if bz > 0.0 do
      changeset
      |> force_change(:cost, (sum / bz * 1000.0) |> LeastCostFeedWeb.Helpers.float_decimal())
    else
      changeset
    end
  end

  def refresh_premix_calculations(changeset) do
    dtls = Helpers.get_list(changeset, :formula_premix_ingredients)

    current_bag_weight =
      Enum.reduce(dtls, 0.0, fn x, acc ->
        acc +
          if(Helpers.my_fetch_field!(x, :delete),
            do: 0.0,
            else:
              Helpers.my_fetch_field!(x, :premix_quantity)
              |> LeastCostFeedWeb.Helpers.float_parse()
          )
      end)

    make_bag_qty =
      Helpers.my_fetch_field!(changeset, :premix_bag_make_qty)
      |> LeastCostFeedWeb.Helpers.float_parse()

    target_premix_weight =
      Helpers.my_fetch_field!(changeset, :target_premix_weight)
      |> LeastCostFeedWeb.Helpers.float_parse()

    bag_use =
      Helpers.my_fetch_field!(changeset, :premix_bag_usage_qty)
      |> LeastCostFeedWeb.Helpers.float_parse()

    left = (target_premix_weight - current_bag_weight) |> LeastCostFeedWeb.Helpers.float_decimal()

    batch =
      (current_bag_weight * make_bag_qty / bag_use) |> LeastCostFeedWeb.Helpers.float_decimal()

    tbagwei = (current_bag_weight / bag_use) |> LeastCostFeedWeb.Helpers.float_decimal()

    if bag_use > 0 do
      changeset
      |> force_change(:left_premix_bag_weight, left)
      |> force_change(:premix_batch_weight, batch)
      |> force_change(:true_premix_bag_weight, tbagwei)
    else
      changeset
    end
  end
end
