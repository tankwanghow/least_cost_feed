defmodule LeastCostFeedWeb.IngredientLive.Index do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.Ingredient
  import Ecto.Query, warn: false

  @per_page 25
  @empty_sort_directions %{
    "name" => nil,
    "category" => nil,
    "dry_matter" => nil,
    "cost" => nil,
    "updated_at" => nil
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-8/12 mx-auto">
      <p class="w-full text-3xl text-center font-medium"><%= @page_title %></p>
      <LeastCostFeedWeb.MyComponents.search_form
        search_val={@search.terms}
        placeholder="Name, Category..."
      />
      <div class="text-center mb-2">
        <.link navigate={~p"/ingredients/new"} id="new_ingredient">
          <.button>New Ingredient</.button>
        </.link>
      </div>

      <LeastCostFeedWeb.MyComponents.table
        id="ingredients"
        rows={@streams.ingredients}
        end_of_data?={@end_of_timeline?}
        row_click={fn {_id, ingredient} -> JS.navigate(~p"/ingredients/#{ingredient}/edit") end}
        sort_directions={@sort_directions}
      >
        <:col :let={{_id, ingredient}} label="Name" class="w-[35%]" sort="name">
          <%= ingredient.name %>
        </:col>
        <:col :let={{_id, ingredient}} label="Category" class="w-[25%]" sort="category">
          <%= ingredient.category %>
        </:col>
        <:col :let={{_id, ingredient}} label="Cost" class="w-[10%]" sort="cost">
          <%= ingredient.cost %>
        </:col>
        <:col :let={{_id, ingredient}} label="Dry Matter%" class="w-[10%]" sort="dry_matter">
          <%= ingredient.dry_matter %>
        </:col>
        <:col :let={{_id, ingredient}} label="Updated" class="w-[15%]" sort="updated_at">
          <%= Timex.from_now(ingredient.updated_at) %>
        </:col>

        <:action :let={{id, ingredient}} class="w-[5%] text-rose-500">
          <.link
            phx-click={JS.push("delete", value: %{id: ingredient.id}) |> hide("##{id}")}
            data-confirm={"Are you sure? DELETE (#{ingredient.name})"}
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
     |> assign(page_title: "Ingredient Listing")
     |> LeastCostFeedWeb.Helpers.sort("updated_at", &query/1, @empty_sort_directions)
     |> filter(true, 1)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    ingredient = Entities.get_ingredient!(id)
    {:ok, _} = Entities.delete_ingredient(ingredient)

    {:noreply, stream_delete(socket, :ingredients, ingredient)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"terms" => terms}}, socket) do
    socket = socket |> assign(search: %{terms: terms})
    {:noreply, socket |> assign(query: query(socket))|> filter(true, 1)}
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
    {:noreply, socket |> filter(false, socket.assigns.page + 1)}
  end

  defp filter(socket, reset, page) do
    objects =
      Entities.list_entities(socket.assigns.query, page: page, per_page: @per_page)

    obj_count = Enum.count(objects)

    socket
    |> assign(page: page, per_page: @per_page)
    |> stream(:ingredients, objects, reset: reset)
    |> assign(end_of_timeline?: obj_count < @per_page)
  end

  defp query(socket) do
    Ecto.Query.from(ing in Ingredient,
      where: ilike(ing.name, ^"%#{socket.assigns.search.terms}%"),
      or_where: ilike(ing.category, ^"%#{socket.assigns.search.terms}%"),
      where: ing.user_id == ^socket.assigns.current_user.id
    )
  end
end
