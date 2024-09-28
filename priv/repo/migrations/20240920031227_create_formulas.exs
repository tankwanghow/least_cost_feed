defmodule LeastCostFeed.Repo.Migrations.CreateFormulas do
  use Ecto.Migration

  def change do
    create table(:formulas) do
      add :name, :string
      add :batch_size, :float, default: 0.0
      add :note, :text
      add :weight_unit, :string, default: "Kg"
      add :usage_per_day, :float, default: 0.0
      add :user_id, references(:users, on_delete: :delete_all)
      add :target_premix_weight, :float
      add :premix_bag_usage_qty, :integer
      add :premix_bag_make_qty, :integer
      add :premix_batch_weight, :float

      timestamps(type: :utc_datetime)
    end

    create table(:formula_ingredients) do
      add :formula_id, references(:formulas, on_delete: :delete_all)
      add :ingredient_id, references(:ingredients, on_delete: :restrict)
      add :cost, :float, default: 0.0
      add :min, :float
      add :max, :float
      add :actual, :float
      add :shadow, :float
      add :used, :boolean, default: true
    end

    create table(:formula_nutrients) do
      add :formula_id, references(:formulas, on_delete: :delete_all)
      add :nutrient_id, references(:nutrients, on_delete: :restrict)
      add :min, :float
      add :max, :float
      add :actual, :float
      add :used, :boolean, default: true
    end

    create table(:formula_premix_ingredients) do
      add :formula_id, references(:formulas, on_delete: :delete_all)
      add :ingredient_id, references(:ingredients, on_delete: :restrict)
      add :formula_quantity, :float
      add :premix_quantity, :float
    end

    create index(:formulas, [:user_id])
    create unique_index(:formulas, [:name, :user_id], name: :formulas_unique_name_in_user)

    create unique_index(:formula_ingredients, [:ingredient_id, :formula_id],
             name: :formula_unique_ingredient
           )

    create unique_index(:formula_nutrients, [:formula_id, :nutrient_id],
             name: :formula_unique_nutrient
           )

    create unique_index(:formula_premix_ingredients, [:ingredient_id, :formula_id],
             name: :formula_premix_unique_ingredient
           )
  end
end
