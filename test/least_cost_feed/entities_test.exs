defmodule LeastCostFeed.EntitiesTest do
  use LeastCostFeed.DataCase

  alias LeastCostFeed.Entities

  describe "nutrients" do
    alias LeastCostFeed.Entities.Nutrient

    import LeastCostFeed.EntitiesFixtures

    @invalid_attrs %{name: nil, unit: nil}

    test "list_nutrients/0 returns all nutrients" do
      nutrient = nutrient_fixture()
      assert Entities.list_nutrients() == [nutrient]
    end

    test "get_nutrient!/1 returns the nutrient with given id" do
      nutrient = nutrient_fixture()
      assert Entities.get_nutrient!(nutrient.id) == nutrient
    end

    test "create_nutrient/1 with valid data creates a nutrient" do
      valid_attrs = %{name: "some name", unit: "some unit"}

      assert {:ok, %Nutrient{} = nutrient} = Entities.create_nutrient(valid_attrs)
      assert nutrient.name == "some name"
      assert nutrient.unit == "some unit"
    end

    test "create_nutrient/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Entities.create_nutrient(@invalid_attrs)
    end

    test "update_nutrient/2 with valid data updates the nutrient" do
      nutrient = nutrient_fixture()
      update_attrs = %{name: "some updated name", unit: "some updated unit"}

      assert {:ok, %Nutrient{} = nutrient} = Entities.update_nutrient(nutrient, update_attrs)
      assert nutrient.name == "some updated name"
      assert nutrient.unit == "some updated unit"
    end

    test "update_nutrient/2 with invalid data returns error changeset" do
      nutrient = nutrient_fixture()
      assert {:error, %Ecto.Changeset{}} = Entities.update_nutrient(nutrient, @invalid_attrs)
      assert nutrient == Entities.get_nutrient!(nutrient.id)
    end

    test "delete_nutrient/1 deletes the nutrient" do
      nutrient = nutrient_fixture()
      assert {:ok, %Nutrient{}} = Entities.delete_nutrient(nutrient)
      assert_raise Ecto.NoResultsError, fn -> Entities.get_nutrient!(nutrient.id) end
    end

    test "change_nutrient/1 returns a nutrient changeset" do
      nutrient = nutrient_fixture()
      assert %Ecto.Changeset{} = Entities.change_nutrient(nutrient)
    end
  end

  describe "ingredients" do
    alias LeastCostFeed.Entities.Ingredient

    import LeastCostFeed.EntitiesFixtures

    @invalid_attrs %{name: nil, unit: nil, description: nil, category: nil, cost: nil}

    test "list_ingredients/0 returns all ingredients" do
      ingredient = ingredient_fixture()
      assert Entities.list_ingredients() == [ingredient]
    end

    test "get_ingredient!/1 returns the ingredient with given id" do
      ingredient = ingredient_fixture()
      assert Entities.get_ingredient!(ingredient.id) == ingredient
    end

    test "create_ingredient/1 with valid data creates a ingredient" do
      valid_attrs = %{
        name: "some name",
        unit: "some unit",
        description: "some description",
        category: "some category",
        cost: 120.5
      }

      assert {:ok, %Ingredient{} = ingredient} = Entities.create_ingredient(valid_attrs)
      assert ingredient.name == "some name"
      assert ingredient.unit == "some unit"
      assert ingredient.description == "some description"
      assert ingredient.category == "some category"
      assert ingredient.cost == 120.5
    end

    test "create_ingredient/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Entities.create_ingredient(@invalid_attrs)
    end

    test "update_ingredient/2 with valid data updates the ingredient" do
      ingredient = ingredient_fixture()

      update_attrs = %{
        name: "some updated name",
        unit: "some updated unit",
        description: "some updated description",
        category: "some updated category",
        cost: 456.7
      }

      assert {:ok, %Ingredient{} = ingredient} =
               Entities.update_ingredient(ingredient, update_attrs)

      assert ingredient.name == "some updated name"
      assert ingredient.unit == "some updated unit"
      assert ingredient.description == "some updated description"
      assert ingredient.category == "some updated category"
      assert ingredient.cost == 456.7
    end

    test "update_ingredient/2 with invalid data returns error changeset" do
      ingredient = ingredient_fixture()
      assert {:error, %Ecto.Changeset{}} = Entities.update_ingredient(ingredient, @invalid_attrs)
      assert ingredient == Entities.get_ingredient!(ingredient.id)
    end

    test "delete_ingredient/1 deletes the ingredient" do
      ingredient = ingredient_fixture()
      assert {:ok, %Ingredient{}} = Entities.delete_ingredient(ingredient)
      assert_raise Ecto.NoResultsError, fn -> Entities.get_ingredient!(ingredient.id) end
    end

    test "change_ingredient/1 returns a ingredient changeset" do
      ingredient = ingredient_fixture()
      assert %Ecto.Changeset{} = Entities.change_ingredient(ingredient)
    end
  end

  describe "formulas" do
    alias LeastCostFeed.Entities.Formula

    import LeastCostFeed.EntitiesFixtures

    @invalid_attrs %{name: nil, batch_size: nil, note: nil}

    test "list_formulas/0 returns all formulas" do
      formula = formula_fixture()
      assert Entities.list_formulas() == [formula]
    end

    test "get_formula!/1 returns the formula with given id" do
      formula = formula_fixture()
      assert Entities.get_formula!(formula.id) == formula
    end

    test "create_formula/1 with valid data creates a formula" do
      valid_attrs = %{name: "some name", batch_size: 120.5, note: "some note"}

      assert {:ok, %Formula{} = formula} = Entities.create_formula(valid_attrs)
      assert formula.name == "some name"
      assert formula.batch_size == 120.5
      assert formula.note == "some note"
    end

    test "create_formula/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Entities.create_formula(@invalid_attrs)
    end

    test "update_formula/2 with valid data updates the formula" do
      formula = formula_fixture()
      update_attrs = %{name: "some updated name", batch_size: 456.7, note: "some updated note"}

      assert {:ok, %Formula{} = formula} = Entities.update_formula(formula, update_attrs)
      assert formula.name == "some updated name"
      assert formula.batch_size == 456.7
      assert formula.note == "some updated note"
    end

    test "update_formula/2 with invalid data returns error changeset" do
      formula = formula_fixture()
      assert {:error, %Ecto.Changeset{}} = Entities.update_formula(formula, @invalid_attrs)
      assert formula == Entities.get_formula!(formula.id)
    end

    test "delete_formula/1 deletes the formula" do
      formula = formula_fixture()
      assert {:ok, %Formula{}} = Entities.delete_formula(formula)
      assert_raise Ecto.NoResultsError, fn -> Entities.get_formula!(formula.id) end
    end

    test "change_formula/1 returns a formula changeset" do
      formula = formula_fixture()
      assert %Ecto.Changeset{} = Entities.change_formula(formula)
    end
  end
end
