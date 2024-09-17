defmodule LeastCostFeed.Repo.Migrations.CreateNutrients do
  use Ecto.Migration

  def change do
    create table(:nutrients) do
      add :name, :string
      add :unit, :string
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:nutrients, [:user_id])
    create unique_index(:nutrients, [:name, :user_id], name: :nutrients_unique_name_in_user)
  end
end
