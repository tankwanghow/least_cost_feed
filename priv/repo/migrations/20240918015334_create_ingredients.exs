defmodule LeastCostFeed.Repo.Migrations.CreateIngredients do
  use Ecto.Migration

  def change do
    create table(:ingredients) do
      add :name, :string
      add :dry_matter, :float
      add :cost, :float
      add :description, :text
      add :category, :string
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create table(:ingredient_compositions) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all)
      add :nutrient_id, references(:nutrients, on_delete: :delete_all)
      add :quantity, :float
    end

    create index(:ingredients, [:user_id])
    create unique_index(:ingredients, [:name, :user_id], name: :ingredients_unique_name_in_user)
    create unique_index(:ingredient_compositions, [:ingredient_id, :nutrient_id], name: :ingredient_unique_nutrient)
  end
end
