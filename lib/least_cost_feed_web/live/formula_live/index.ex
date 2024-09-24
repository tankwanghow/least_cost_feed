defmodule LeastCostFeedWeb.FormulaLive.Index do
  alias LeastCostFeed.Entities.FormulaIngredient
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.Formula
  alias LeastCostFeedWeb.Helpers
  import Ecto.Query, warn: false

  @per_page 25
  @empty_sort_directions %{
    "name" => nil,
    "batch_size" => nil,
    "usage_per_day" => nil,
    "cost" => nil,
    "updated_at" => nil
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-8/12 mx-auto">
      <p class="w-full text-3xl text-center font-medium"><%= @page_title %></p>
      <LeastCostFeedWeb.MyComponents.search_form search_val={@search.terms} placeholder="Name..." />
      <div class="text-center mb-2">
        <.link navigate={~p"/formulas/new"} id="new_formula">
          <.button>New Formula</.button>
        </.link>
      </div>
      <%!-- row_click={fn {_id, formula} -> JS.navigate(~p"/formulas/#{formula}/edit") end} --%>
      <LeastCostFeedWeb.MyComponents.table
        id="formulas"
        rows={@streams.formulas}
        end_of_data?={@end_of_timeline?}
        sort_directions={@sort_directions}
      >
        <:col :let={{_id, formula}} label="Name" class="w-[30%]" sort="name">
          <.link class="text-blue-600 hover:font-bold" navigate={~p"/formulas/#{formula}/edit"}>
            <%= formula.name %>
          </.link>
        </:col>
        <:col :let={{_id, formula}} label="Batch Size" class="w-[20%]" sort="batch_size">
          <%= Helpers.float_decimal(formula.batch_size) %><%= formula.weight_unit %>
        </:col>
        <:col :let={{_id, formula}} label="Cost" class="w-[10%]" sort="cost">
          <%= Helpers.float_decimal(formula.cost * 1000, 2) %>/1000<%= formula.weight_unit %>
        </:col>
        <:col :let={{_id, formula}} label="Usage/Day" class="w-[10%]" sort="usage_per_day">
          <input
            type="number"
            step="any"
            class="py-0 px-2 w-[80%] border rounded border-gray-600"
            id={"formula_#{formula.id}"}
            phx-value-id={formula.id}
            phx-blur="update_usage"
            value={Helpers.float_decimal(formula.usage_per_day)}
          /><%= formula.weight_unit %>
        </:col>
        <:col :let={{_id, formula}} label="Updated" class="w-[15%]" sort="updated_at">
          <%= Timex.from_now(formula.updated_at) %>
        </:col>

        <:action :let={{id, formula}} class="w-[5%] text-rose-500">
          <.link
            phx-click={JS.push("delete", value: %{id: formula.id}) |> hide("##{id}")}
            data-confirm={"Are you sure? DELETE (#{formula.name})"}
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
     |> assign(page_title: "Formula Listing")
     |> LeastCostFeedWeb.Helpers.sort("updated_at", &query/1, @empty_sort_directions)
     |> filter(true, 1)}
  end

  @impl true
  def handle_event("update_usage", %{"id" => id, "value" => value}, socket) do
    Entities.update_formula_usage(id, value)
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    formula = Entities.get_formula!(id)
    {:ok, _} = Entities.delete_formula(formula)

    {:noreply, stream_delete(socket, :formulas, formula)}
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
    |> stream(:formulas, objects, reset: reset)
    |> assign(end_of_timeline?: obj_count < @per_page)
  end

  defp query(socket) do
    Ecto.Query.from(frm in Formula,
      join: frming in FormulaIngredient,
      on: frm.id == frming.formula_id,
      where: ilike(frm.name, ^"%#{socket.assigns.search.terms}%"),
      where: frm.user_id == ^socket.assigns.current_user.id,
      group_by: frm.id,
      select: frm,
      select_merge: %{
        cost: fragment("?/?", sum(frm.batch_size * frming.actual * frming.cost), frm.batch_size)
      }
    )
  end
end
