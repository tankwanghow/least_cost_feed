defmodule LeastCostFeed.Entities.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :name, :string
    field :dry_matter, :float
    field :description, :string
    field :category, :string
    field :cost, :float
    belongs_to :user, LeastCostFeed.UserAccounts.User
    has_many :ingredient_compositions, LeastCostFeed.Entities.IngredientComposition, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name, :dry_matter, :cost, :description, :category, :user_id])
    |> validate_required([:name, :dry_matter, :cost, :category, :user_id])
    |> validate_number(:cost, greater_than_or_equal_to: 0.0)
    |> validate_number(:dry_matter, greater_than_or_equal_to: 0.0)
    |> unsafe_validate_unique([:name, :user_id], LeastCostFeed.Repo)
    |> unique_constraint(:name, name: :ingredients_unique_name_in_user)
    |> cast_assoc(:ingredient_compositions)
  end
end
