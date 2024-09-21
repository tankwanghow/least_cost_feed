defmodule LeastCostFeedWeb.NutrientLive.SelectComponent do
  use LeastCostFeedWeb, :live_component

  alias LeastCostFeed.Entities.Nutrient
  alias LeastCostFeed.Entities
  import Ecto.Query, warn: false

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <span class="text-l font-semibold">Please Select nutrients</span>
      <span class="text-l text-emerald-700">(finished press ESC or click away)</span>
      <div class="h-[40rem] overflow-y-scroll border p-2">
        <div :for={nutrient <- @nutrients} id={"nutrient_#{nutrient.id}"} class="flex border-b">
          <div class="w-[4%]">
            <input
              :if={nutrient.checked}
              id={"chk_#{nutrient.id}"}
              type="checkbox"
              class="rounded"
              phx-click="nutrient_clicked"
              phx-value-object-id={nutrient.id}
              checked
            />
            <input
              :if={!nutrient.checked}
              id={"chk_#{nutrient.id}"}
              type="checkbox"
              class="rounded"
              phx-click="nutrient_clicked"
              phx-value-object-id={nutrient.id}
            />
          </div>
          <div class="w-[75%]"><%= nutrient.name %></div>
          <div class="w-[10%]"><%= nutrient.unit %></div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = socket |> assign(assigns)
    {:ok, socket |> nutrient_all()}
  end

  defp nutrient_all(socket) do
    query =
      Ecto.Query.from(nt in Nutrient,
        where: nt.user_id == ^socket.assigns.current_user.id,
        order_by: nt.name,
        select: %{id: nt.id, name: nt.name, unit: nt.unit, checked: false}
      )

    objects =
      Entities.list_entities(query, page: 1, per_page: 1000)
      |> Enum.map(fn x ->
        if Enum.any?(socket.assigns.selected_nutrient_ids, fn sn_id -> sn_id == x.id end) do
          Map.merge(x, %{checked: true})
        else
          x
        end
      end)

    socket
    |> assign(page: 1, per_page: 1000)
    |> assign(:nutrients, objects)
  end
end
