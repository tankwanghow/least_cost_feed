defmodule LeastCostFeed.Entities do
  import Ecto.Query, warn: false
  alias LeastCostFeed.Repo
  alias LeastCostFeed.Entities.{Formula, Nutrient, FormulaIngredient, FormulaNutrient}
  alias LeastCostFeed.Entities.{Ingredient, IngredientComposition, FormulaPremixIngredient}

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
        order_by: nt.name,
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

  def get_print_formulas!(ids) do
    frm_nut =
      from(fnt in FormulaNutrient,
        join: nt in Nutrient,
        on: nt.id == fnt.nutrient_id,
        preload: :nutrient,
        select: fnt,
        select_merge: %{nutrient_name: nt.name, nutrient_unit: nt.unit},
        order_by: nt.name
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
      preload: :user,
      where: frm.id in ^ids,
      group_by: frm.id,
      select: frm,
      select_merge: %{
        cost:
          fragment("?/?*1000", sum(frm.batch_size * frming.actual * frming.cost), frm.batch_size)
      }
    )
    |> Repo.all()
  end

  def get_print_premix!(ids) do
    premix_ing =
      from(fping in FormulaPremixIngredient,
        join: ing in Ingredient,
        on: ing.id == fping.ingredient_id,
        preload: [ingredient: :ingredient_compositions],
        order_by: [desc: fping.formula_quantity],
        select: fping,
        select_merge: %{ingredient_name: ing.name}
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
      preload: [formula_premix_ingredients: ^premix_ing],
      preload: [formula_ingredients: ^frm_ing],
      preload: :user,
      where: frm.id in ^ids,
      group_by: frm.id,
      select: frm
    )
    |> Repo.all()
  end

  def get_formula_premix_ingredients!(id) do
    fpi =
      from(fping in FormulaPremixIngredient,
        join: i in Ingredient,
        on: i.id == fping.ingredient_id,
        where: fping.formula_id == ^id,
        order_by: [desc: fping.formula_quantity],
        select: %FormulaPremixIngredient{
          id: fping.id,
          ingredient_id: i.id,
          formula_id: fping.formula_id,
          ingredient_name: i.name,
          formula_quantity: fping.formula_quantity,
          premix_quantity: fping.premix_quantity,
          delete: false
        }
      )

    from(frm in Formula,
      where: frm.id == ^id,
      preload: [formula_premix_ingredients: ^fpi],
      select: frm,
      select_merge: %{
        left_premix_bag_weight:
          fragment(
            "(? / (case ? when 0 then 1 else ? end) * (case ? when 0 then 1 else ? end)) - ?",
            frm.premix_batch_weight,
            frm.premix_bag_make_qty,
            frm.premix_bag_make_qty,
            frm.premix_bag_usage_qty,
            frm.premix_bag_usage_qty,
            frm.target_premix_weight
          ),
        true_premix_bag_weight:
          fragment("? / (case ? when 0 then 1 else ? end)", frm.premix_batch_weight, frm.premix_bag_make_qty, frm.premix_bag_make_qty)
      }
    )
    |> Repo.one!()
  end

  def get_formula_ingredients!(id) do
    from(fing in FormulaIngredient,
      join: f in Formula,
      on: f.id == fing.formula_id,
      join: i in Ingredient,
      on: i.id == fing.ingredient_id,
      where: f.id == ^id,
      where: fing.actual > 0.0,
      select: %FormulaPremixIngredient{
        id: nil,
        ingredient_id: i.id,
        formula_id: f.id,
        ingredient_name: i.name,
        formula_quantity: fing.actual * f.batch_size,
        premix_quantity: 0.0,
        delete: false
      }
    )
    |> Repo.all()
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

  def update_formula_premix(%Formula{} = formula, attrs) do
    formula
    |> Formula.premix_changeset(attrs)
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

  def change_formula_premix(%Formula{} = formula, attrs \\ %{}) do
    Formula.premix_changeset(formula, attrs)
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
    |> Enum.sort_by(&LeastCostFeed.Helpers.my_fetch_field!(&1, :actual), :desc)
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
    |> Enum.sort_by(&LeastCostFeed.Helpers.my_fetch_field!(&1, :nutrient_name))
  end
end
