defmodule LeastCostFeedWeb.NutrientLive.Index do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.Nutrient
  import Ecto.Query, warn: false

  @per_page 25
  @empty_sort_directions %{"name" => nil, "unit" => nil, "updated_at" => nil}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-6/12 mx-auto">
      <p class="w-full text-3xl text-center font-medium"><%= @page_title %></p>
      <LeastCostFeedWeb.MyComponents.search_form search_val={@search.terms} placeholder="Name..." />
      <div class="text-center mb-2">
        <.link navigate={~p"/nutrients/new"} id="new_nutrient">
          <.button>New Nutrient</.button>
        </.link>
      </div>

      <LeastCostFeedWeb.MyComponents.table
        id="nutrients"
        rows={@streams.nutrients}
        end_of_data?={@end_of_timeline?}
        row_click={fn {_id, nutrient} -> JS.navigate(~p"/nutrients/#{nutrient}/edit") end}
        sort_directions={@sort_directions}
      >
        <:col :let={{_id, nutrient}} label="Name" class="w-[40%]" sort="name">
          <%= nutrient.name %>
        </:col>
        <:col :let={{_id, nutrient}} label="Unit" class="w-[20%]" sort="unit">
          <%= nutrient.unit %>
        </:col>
        <:col :let={{_id, nutrient}} label="Updated" class="w-[30%]" sort="updated_at">
          <%= Timex.from_now(nutrient.updated_at) %>
        </:col>

        <:action :let={{id, nutrient}} class="w-[10%] text-rose-500">
          <.link
            phx-click={JS.push("delete", value: %{id: nutrient.id}) |> hide("##{id}")}
            data-confirm={"Are you sure? DELETE (#{nutrient.name})"}
          >
            <.icon name="hero-trash-solid" class="h-5 w-5" />
          </.link>
        </:action>
      </LeastCostFeedWeb.MyComponents.table>
      <LeastCostFeedWeb.MyComponents.infinite_scroll_footer ended={@end_of_timeline?} />
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(search: %{terms: ""})
      |> assign(sort_directions: @empty_sort_directions |> Map.merge(%{"updated_at" => :asc}))

    {:ok,
     socket
     |> assign(page_title: "Nutrient Listing")
     |> LeastCostFeedWeb.Helpers.sort("updated_at", &query/1, @empty_sort_directions)
     |> filter(true, 1)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    nutrient = Entities.get_nutrient!(id)
    {:ok, _} = Entities.delete_nutrient(nutrient)

    {:noreply, stream_delete(socket, :nutrients, nutrient)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"terms" => terms}}, socket) do
    socket = socket |> assign(search: %{terms: terms})
    {:noreply, socket |> assign(query: query(socket)) |> filter(true, 1)}
  end

  @impl true
  def handle_event("sort", %{"sort-by" => sort_by}, socket) do
    {:noreply,
     socket
     |> LeastCostFeedWeb.Helpers.sort(sort_by, &query/1, @empty_sort_directions)
     |> filter(true, 1)}
  end

  @impl true
  def handle_event("next-page", _, socket) do
    socket = socket |> assign(query: query(socket))
    {:noreply, socket |> filter(false, socket.assigns.page + 1)}
  end

  defp filter(socket, reset, page) do
    objects =
      Entities.list_entities(socket.assigns.query, page: page, per_page: @per_page)

    obj_count = Enum.count(objects)

    socket
    |> assign(page: page, per_page: @per_page)
    |> stream(:nutrients, objects, reset: reset)
    |> assign(end_of_timeline?: obj_count < @per_page)
  end

  defp query(socket) do
    Ecto.Query.from(nt in Nutrient,
      where: nt.user_id == ^socket.assigns.current_user.id,
      where: ilike(nt.name, ^"%#{socket.assigns.search.terms}%")
    )
  end
end
