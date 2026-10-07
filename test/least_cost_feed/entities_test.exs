defmodule LeastCostFeed.EntitiesTest do
  use LeastCostFeed.DataCase

  alias LeastCostFeed.Entities
  import LeastCostFeed.EntitiesFixtures
  import LeastCostFeed.UserAccountsFixtures, only: [user_fixture: 0]

  setup do
    %{user: user_fixture()}
  end

  describe "nutrients" do
    alias LeastCostFeed.Entities.Nutrient

    @invalid_attrs %{name: nil, unit: nil}

    test "get_nutrient!/1 returns the nutrient with given id", %{user: user} do
      nutrient = nutrient_fixture(user_id: user.id)
      assert Entities.get_nutrient!(nutrient.id) == nutrient
    end

    test "create_nutrient/1 with valid data creates a nutrient", %{user: user} do
      valid_attrs = %{name: "some name", unit: "some unit", user_id: user.id}

      assert {:ok, %Nutrient{} = nutrient} = Entities.create_nutrient(valid_attrs)
      assert nutrient.name == "some name"
      assert nutrient.unit == "some unit"
      assert nutrient.user_id == user.id
    end

    test "create_nutrient/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Entities.create_nutrient(@invalid_attrs)
    end

    test "create_nutrient/1 requires a user" do
      assert {:error, changeset} = Entities.create_nutrient(%{name: "N", unit: "%"})
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "update_nutrient/2 with valid data updates the nutrient", %{user: user} do
      nutrient = nutrient_fixture(user_id: user.id)
      update_attrs = %{name: "some updated name", unit: "some updated unit"}

      assert {:ok, %Nutrient{} = nutrient} = Entities.update_nutrient(nutrient, update_attrs)
      assert nutrient.name == "some updated name"
      assert nutrient.unit == "some updated unit"
    end

    test "update_nutrient/2 with invalid data returns error changeset", %{user: user} do
      nutrient = nutrient_fixture(user_id: user.id)
      assert {:error, %Ecto.Changeset{}} = Entities.update_nutrient(nutrient, @invalid_attrs)
      assert nutrient == Entities.get_nutrient!(nutrient.id)
    end

    test "delete_nutrient/1 deletes the nutrient", %{user: user} do
      nutrient = nutrient_fixture(user_id: user.id)
      assert {:ok, %Nutrient{}} = Entities.delete_nutrient(nutrient)
      assert_raise Ecto.NoResultsError, fn -> Entities.get_nutrient!(nutrient.id) end
    end

    test "change_nutrient/1 returns a nutrient changeset", %{user: user} do
      nutrient = nutrient_fixture(user_id: user.id)
      assert %Ecto.Changeset{} = Entities.change_nutrient(nutrient)
    end
  end

  describe "ingredients" do
    alias LeastCostFeed.Entities.Ingredient

    @invalid_attrs %{name: nil, dry_matter: nil, description: nil, category: nil, cost: nil}

    test "get_ingredient!/1 returns the ingredient with compositions preloaded", %{user: user} do
      ingredient = ingredient_fixture(user_id: user.id)
      fetched = Entities.get_ingredient!(ingredient.id)

      assert fetched.id == ingredient.id
      assert fetched.name == ingredient.name
      assert fetched.ingredient_compositions == []
    end

    test "create_ingredient/1 with valid data creates a ingredient", %{user: user} do
      valid_attrs = %{
        name: "some name",
        dry_matter: 90.0,
        description: "some description",
        category: "some category",
        cost: 120.5,
        user_id: user.id
      }

      assert {:ok, %Ingredient{} = ingredient} = Entities.create_ingredient(valid_attrs)
      assert ingredient.name == "some name"
      assert ingredient.dry_matter == 90.0
      assert ingredient.description == "some description"
      assert ingredient.category == "some category"
      assert ingredient.cost == 120.5
    end

    test "create_ingredient/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Entities.create_ingredient(@invalid_attrs)
    end

    test "update_ingredient/2 with valid data updates the ingredient", %{user: user} do
      ingredient = ingredient_fixture(user_id: user.id)

      update_attrs = %{
        name: "some updated name",
        description: "some updated description",
        category: "some updated category",
        cost: 456.7
      }

      assert {:ok, %Ingredient{} = ingredient} =
               Entities.update_ingredient(ingredient, update_attrs)

      assert ingredient.name == "some updated name"
      assert ingredient.description == "some updated description"
      assert ingredient.category == "some updated category"
      assert ingredient.cost == 456.7
    end

    test "update_ingredient/2 with invalid data returns error changeset", %{user: user} do
      ingredient = ingredient_fixture(user_id: user.id)
      assert {:error, %Ecto.Changeset{}} = Entities.update_ingredient(ingredient, @invalid_attrs)
      assert Entities.get_ingredient!(ingredient.id).name == ingredient.name
    end

    test "update_ingredient/2 returns error changeset for a duplicate name", %{user: user} do
      ingredient_fixture(user_id: user.id, name: "Maize")
      soy = ingredient_fixture(user_id: user.id, name: "Soy")

      assert {:error, changeset} = Entities.update_ingredient(soy, %{name: "Maize"})
      assert errors_on(changeset).name != []
      assert Entities.get_ingredient!(soy.id).name == "Soy"
    end

    test "update_ingredient/2 propagates a cost change to the user's formulas, and rolls back on error",
         %{user: user} do
      ingredient = ingredient_fixture(user_id: user.id, cost: 100.0)

      formula =
        formula_fixture(
          user_id: user.id,
          formula_ingredients: [%{ingredient_id: ingredient.id, cost: 100.0, actual: 0.5}]
        )

      fi_cost = fn ->
        [fi] = Entities.get_formula!(formula.id).formula_ingredients
        fi.cost
      end

      assert {:ok, ingredient} = Entities.update_ingredient(ingredient, %{cost: 200.0})
      assert fi_cost.() == 200.0

      assert {:error, _} = Entities.update_ingredient(ingredient, %{cost: 300.0, name: nil})
      assert fi_cost.() == 200.0
      assert Entities.get_ingredient!(ingredient.id).cost == 200.0
    end

    test "delete_ingredient/1 deletes the ingredient", %{user: user} do
      ingredient = ingredient_fixture(user_id: user.id)
      assert {:ok, %Ingredient{}} = Entities.delete_ingredient(ingredient)
      assert_raise Ecto.NoResultsError, fn -> Entities.get_ingredient!(ingredient.id) end
    end

    test "change_ingredient/1 returns a ingredient changeset", %{user: user} do
      ingredient = ingredient_fixture(user_id: user.id)
      assert %Ecto.Changeset{} = Entities.change_ingredient(ingredient)
    end
  end

  describe "formulas" do
    alias LeastCostFeed.Entities.Formula

    @invalid_attrs %{name: nil, batch_size: nil, note: nil}

    test "list_user_formulas/1 returns only that user's formulas", %{user: user} do
      formula = formula_fixture(user_id: user.id)
      formula_fixture(name: "someone else's")

      assert Entities.list_user_formulas(user.id) == [
               %{id: formula.id, name: formula.name, usage_per_day: formula.usage_per_day}
             ]
    end

    test "get_formula!/1 returns the formula with given id", %{user: user} do
      formula = formula_fixture(user_id: user.id)
      fetched = Entities.get_formula!(formula.id)

      assert fetched.id == formula.id
      assert fetched.name == formula.name
      assert fetched.formula_ingredients == []
      assert fetched.formula_nutrients == []
    end

    test "create_formula/1 with valid data creates a formula", %{user: user} do
      valid_attrs = %{
        name: "some name",
        batch_size: 120.5,
        note: "some note",
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id
      }

      assert {:ok, %Formula{} = formula} = Entities.create_formula(valid_attrs)
      assert formula.name == "some name"
      assert formula.batch_size == 120.5
      assert formula.note == "some note"
    end

    test "create_formula/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Entities.create_formula(@invalid_attrs)
    end

    test "update_formula/2 with valid data updates the formula", %{user: user} do
      formula = formula_fixture(user_id: user.id)
      update_attrs = %{name: "some updated name", batch_size: 456.7, note: "some updated note"}

      assert {:ok, %Formula{} = formula} = Entities.update_formula(formula, update_attrs)
      assert formula.name == "some updated name"
      assert formula.batch_size == 456.7
      assert formula.note == "some updated note"
    end

    test "update_formula/2 with invalid data returns error changeset", %{user: user} do
      formula = formula_fixture(user_id: user.id)
      assert {:error, %Ecto.Changeset{}} = Entities.update_formula(formula, @invalid_attrs)
      assert Entities.get_formula!(formula.id).name == formula.name
    end

    test "delete_formula/1 deletes the formula", %{user: user} do
      formula = formula_fixture(user_id: user.id)
      assert {:ok, %Formula{}} = Entities.delete_formula(formula)
      assert_raise Ecto.NoResultsError, fn -> Entities.get_formula!(formula.id) end
    end

    test "change_formula/1 returns a formula changeset", %{user: user} do
      formula = formula_fixture(user_id: user.id)
      assert %Ecto.Changeset{} = Entities.change_formula(formula)
    end
  end

  describe "list_formulas_for_compare/2" do
    alias LeastCostFeed.Entities

    test "returns only formulas matching ids and user, preloaded" do
      user = LeastCostFeed.UserAccountsFixtures.user_fixture()
      other = LeastCostFeed.UserAccountsFixtures.user_fixture()

      {:ok, f1} =
        Entities.create_formula(%{
          name: "F1",
          batch_size: 1000.0,
          weight_unit: "KG",
          usage_per_day: 0.0,
          user_id: user.id
        })

      {:ok, f2} =
        Entities.create_formula(%{
          name: "F2",
          batch_size: 1000.0,
          weight_unit: "KG",
          usage_per_day: 0.0,
          user_id: user.id
        })

      {:ok, fother} =
        Entities.create_formula(%{
          name: "X",
          batch_size: 1000.0,
          weight_unit: "KG",
          usage_per_day: 0.0,
          user_id: other.id
        })

      result = Entities.list_formulas_for_compare(user.id, [f1.id, f2.id, fother.id])

      ids = Enum.map(result, & &1.id) |> Enum.sort()
      assert ids == Enum.sort([f1.id, f2.id])

      assert Enum.all?(result, fn f ->
               Ecto.assoc_loaded?(f.formula_nutrients)
             end)
    end
  end

  describe "list_ingredients_for_compare/2" do
    alias LeastCostFeed.Entities

    test "returns only ingredients matching ids and user, with compositions preloaded" do
      user = LeastCostFeed.UserAccountsFixtures.user_fixture()

      {:ok, i1} =
        Entities.create_ingredient(%{
          name: "I1",
          cost: 1.0,
          dry_matter: 90.0,
          category: "x",
          description: "",
          user_id: user.id
        })

      result = Entities.list_ingredients_for_compare(user.id, [i1.id])
      assert length(result) == 1
      [i] = result
      assert Ecto.assoc_loaded?(i.ingredient_compositions)
    end
  end
end
