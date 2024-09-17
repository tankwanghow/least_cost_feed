defmodule LeastCostFeed.Entities.Nutrient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nutrients" do
    field :name, :string
    field :unit, :string
    belongs_to :user, LeastCostFeed.UserAccounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(nutrient, attrs) do
    nutrient
    |> cast(attrs, [:name, :unit, :user_id])
    |> validate_required([:name, :unit, :user_id])
    |> unsafe_validate_unique([:name, :user_id], LeastCostFeed.Repo)
    |> unique_constraint(:name, name: :nutrients_unique_name_in_user)
  end
end
