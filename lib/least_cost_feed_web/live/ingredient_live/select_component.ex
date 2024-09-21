defmodule LeastCostFeedWeb.IngredientLive.SelectComponent do
  use LeastCostFeedWeb, :live_component

  alias LeastCostFeed.Entities.Ingredient
  alias LeastCostFeed.Entities
  import Ecto.Query, warn: false

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <span class="text-l font-semibold">Please Select Ingredients</span>
      <span class="text-l text-emerald-700">(finished press ESC or click away)</span>
      <div class="h-[40rem] overflow-y-scroll border p-2">
        <div
          :for={ingredient <- @ingredients}
          id={"ingredient_#{ingredient.id}"}
          class="flex border-b"
        >
          <div class="w-[4%]">
            <input
              :if={ingredient.checked}
              id={"chk_#{ingredient.id}"}
              type="checkbox"
              class="rounded"
              phx-click="ingredient_clicked"
              phx-value-object-id={ingredient.id}
              checked
            />
            <input
              :if={!ingredient.checked}
              id={"chk_#{ingredient.id}"}
              type="checkbox"
              class="rounded"
              phx-click="ingredient_clicked"
              phx-value-object-id={ingredient.id}
            />
          </div>
          <div class="w-[40%]"><%= ingredient.name %></div>
          <div class="w-[36%]"><%= ingredient.category %></div>
          <div class="w-[10%]"><%= ingredient.cost %></div>
          <div class="w-[10%]"><%= ingredient.dry_matter %></div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = socket |> assign(assigns)
    {:ok, socket |> ingredient_all()}
  end

  defp ingredient_all(socket) do
    query =
      Ecto.Query.from(ing in Ingredient,
        where: ing.user_id == ^socket.assigns.current_user.id,
        order_by: ing.name,
        select: %{
          id: ing.id,
          name: ing.name,
          cost: ing.cost,
          category: ing.category,
          dry_matter: ing.dry_matter,
          checked: false
        }
      )

    objects =
      Entities.list_entities(query, page: 1, per_page: 1000)
      |> Enum.map(fn x ->
        if Enum.any?(socket.assigns.selected_ingredient_ids, fn sn_id -> sn_id == x.id end) do
          Map.merge(x, %{checked: true})
        else
          x
        end
      end)

    socket
    |> assign(page: 1, per_page: 1000)
    |> assign(:ingredients, objects)
  end
end
