defmodule LeastCostFeed.Repo.Migrations.CreateFormulaVersions do
  use Ecto.Migration

  def change do
    create table(:formula_versions) do
      add :formula_id, references(:formulas, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :note, :string
      add :snapshot, :map, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:formula_versions, [:formula_id])
    create unique_index(:formula_versions, [:formula_id, :version])
  end
end
