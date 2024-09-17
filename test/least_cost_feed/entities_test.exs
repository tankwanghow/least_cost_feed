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
end
