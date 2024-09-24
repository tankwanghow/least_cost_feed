defmodule LeastCostFeed.Entities do
  import Ecto.Query, warn: false
  alias LeastCostFeed.Repo
  alias LeastCostFeed.Entities.{Formula, Nutrient, FormulaIngredient, FormulaNutrient}
  alias LeastCostFeed.Entities.{Ingredient, IngredientComposition}

  def list_entities(query, page: page, per_page: per_page) do
    from(q in query,
      offset: ^((page - 1) * per_page),
      limit: ^per_page
    )
    |> Repo.all()
  end

  def get_nutrient!(id), do: Repo.get!(Nutrient, id)

  def create_nutrient(attrs \\ %{}) do
    %Nutrient{}
    |> Nutrient.changeset(attrs)
    |> Repo.insert()
  end

  def update_nutrient(%Nutrient{} = nutrient, attrs) do
    nutrient
    |> Nutrient.changeset(attrs)
    |> Repo.update()
  end

  def delete_nutrient(%Nutrient{} = nutrient) do
    Repo.delete(nutrient)
  end

  def change_nutrient(%Nutrient{} = nutrient, attrs \\ %{}) do
    Nutrient.changeset(nutrient, attrs)
  end

  def get_ingredient!(id) do
    ing_coms =
      from(ic in IngredientComposition,
        join: nt in Nutrient,
        on: nt.id == ic.nutrient_id,
        select: ic,
        select_merge: %{nutrient_name: nt.name, nutrient_unit: nt.unit}
      )

    from(ing in Ingredient, preload: [ingredient_compositions: ^ing_coms], where: ing.id == ^id)
    |> Repo.one!()
  end

  def create_ingredient(attrs \\ %{}) do
    %Ingredient{}
    |> Ingredient.changeset(attrs)
    |> Repo.insert()
  end

  def update_ingredient(%Ingredient{} = ingredient, attrs) do
    Repo.transaction(fn r ->
      cs = ingredient |> Ingredient.changeset(attrs)
      r.update(cs)

      if Ecto.Changeset.changed?(cs, :cost) do
        from(fi in FormulaIngredient,
          join: f in Formula,
          on: f.id == fi.formula_id,
          where: f.user_id == ^ingredient.user_id,
          where: fi.ingredient_id == ^ingredient.id,
          select: fi
        )
        |> r.update_all(set: [cost: Ecto.Changeset.fetch_field!(cs, :cost)])
      end
    end)
  end

  def delete_ingredient(%Ingredient{} = ingredient) do
    Repo.delete(ingredient)
  end

  def change_ingredient(%Ingredient{} = ingredient, attrs \\ %{}) do
    Ingredient.changeset(ingredient, attrs)
  end

  def get_formula!(id) do
    frm_nut =
      from(fnt in FormulaNutrient,
        join: nt in Nutrient,
        on: nt.id == fnt.nutrient_id,
        preload: :nutrient,
        select: fnt,
        select_merge: %{nutrient_name: nt.name, nutrient_unit: nt.unit}
      )

    frm_ing =
      from(fing in FormulaIngredient,
        join: ing in Ingredient,
        on: ing.id == fing.ingredient_id,
        preload: [ingredient: :ingredient_compositions],
        order_by: [desc: fing.actual],
        select: fing,
        select_merge: %{ingredient_name: ing.name, cost: fing.cost, amount: 0.0}
      )

    from(frm in Formula,
      join: frming in FormulaIngredient,
      on: frm.id == frming.formula_id,
      preload: [formula_ingredients: ^frm_ing],
      preload: [formula_nutrients: ^frm_nut],
      where: frm.id == ^id,
      group_by: frm.id,
      select: frm,
      select_merge: %{
        cost:
          fragment("?/?*1000", sum(frm.batch_size * frming.actual * frming.cost), frm.batch_size)
      }
    )
    |> Repo.one!()
  end

  def create_formula(attrs \\ %{}) do
    %Formula{}
    |> Formula.changeset(attrs)
    |> Repo.insert()
  end

  def update_formula(%Formula{} = formula, attrs) do
    formula
    |> Formula.changeset(attrs)
    |> Repo.update()
  end

  def update_formula_usage(id, value) do
    from(f in Formula, where: f.id == ^id, update: [set: [usage_per_day: ^value]])
    |> Repo.update_all([])
  end

  def delete_formula(%Formula{} = formula) do
    Repo.delete(formula)
  end

  def change_formula(%Formula{} = formula, attrs \\ %{}) do
    Formula.changeset(formula, attrs)
  end

  def replace_formula_with_optimize(formula, ingredient_attrs, nutrient_attrs) do
    formula_ingredients = Ecto.Changeset.get_assoc(formula, :formula_ingredients)
    formula_nutrients = Ecto.Changeset.get_assoc(formula, :formula_nutrients)

    formula
    |> Ecto.Changeset.put_assoc(
      :formula_ingredients,
      replace_formula_ingredient_with_optimize(formula_ingredients, ingredient_attrs)
    )
    |> Ecto.Changeset.put_assoc(
      :formula_nutrients,
      replace_formula_nutrient_with_optimize(formula_nutrients, nutrient_attrs)
    )
  end

  defp replace_formula_ingredient_with_optimize(formula_ingredients, attrs) do
    Enum.map(formula_ingredients, fn to_update ->
      update_source =
        Enum.find(attrs, fn attr ->
          String.to_integer(attr.id) == Ecto.Changeset.get_field(to_update, :ingredient_id)
        end)

      if update_source do
        Ecto.Changeset.change(to_update, %{
          actual: LeastCostFeedWeb.Helpers.float_decimal(update_source.actual, 6),
          shadow: LeastCostFeedWeb.Helpers.float_decimal(update_source.shadow)
        })
      else
        Ecto.Changeset.change(to_update, %{
          actual: "0.0",
          shadow: "0.0"
        })
      end
    end)
  end

  defp replace_formula_nutrient_with_optimize(formula_nutrients, attrs) do
    Enum.map(formula_nutrients, fn to_update ->
      update_source =
        Enum.find(attrs, fn attr ->
          String.to_integer(attr.id) == Ecto.Changeset.get_field(to_update, :nutrient_id)
        end)

      if update_source do
        Ecto.Changeset.change(to_update, %{
          actual: LeastCostFeedWeb.Helpers.float_decimal(update_source.actual)
        })
      else
        Ecto.Changeset.change(to_update, %{
          actual: "0.0"
        })
      end
    end)
  end
end
