defmodule LeastCostFeed.Repo.Migrations.AddShadowToFormulaNutrients do
  use Ecto.Migration

  def change do
    alter table(:formula_nutrients) do
      add :shadow, :float
    end
  end
end
