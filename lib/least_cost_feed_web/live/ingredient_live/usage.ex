defmodule LeastCostFeedWeb.IngredientLive.Usage do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities.{Ingredient, Formula, FormulaIngredient}
  alias Number.Delimit
  import Ecto.Query, warn: false

  @empty_sort_directions %{
    "ingredient_name" => nil,
    "use_perc" => nil,
    "cost_perc" => nil
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-8/12 mx-auto">
      <p class="w-full text-3xl text-center font-medium"><%= @page_title %></p>
      <div class="flex font-bold text-right border-y border-gray-600 p-2 bg-blue-200">
        <div
          class="w-[24%] text-left hover:cursor-pointer hover:text-white"
          phx-click="sort"
          phx-value-sort-by="ingredient_name"
        >
          Ingredient<%= direction_icon(@sort_directions["ingredient_name"], assigns) %>
        </div>
        <div class="w-[25%] text-center">Used In Formula</div>
        <div class="w-[6%]">Cost</div>
        <div
          class="w-[5%] hover:cursor-pointer hover:text-white"
          phx-click="sort"
          phx-value-sort-by="use_perc"
        >
          Use%<%= direction_icon(@sort_directions["use_perc"], assigns) %>
        </div>
        <div class="w-[8%]">7days Use</div>
        <div class="w-[8%]">7days Cost</div>
        <div class="w-[9%]">30days Use</div>
        <div class="w-[9%]">30days Cost</div>
        <div
          class="w-[6%] hover:cursor-pointer hover:text-white"
          phx-click="sort"
          phx-value-sort-by="cost_perc"
        >
          Cost%<%= direction_icon(@sort_directions["cost_perc"], assigns) %>
        </div>
      </div>
      <%= for i <- @ingredients do %>
        <div class="flex text-right border-b border-gray-400 px-2 bg-orange-200 hover:bg-orange-300">
          <div class="w-[24%] text-left text-nowrap overflow-hidden"><%= i.ingredient_name %></div>
          <div class="w-[25%] text-center">
            <%= for f <- formula_links(i.formula_list) do %>
              <%= formula_link(f, assigns) %>
            <% end %>
          </div>
          <div class="w-[6%]">
            <%= Delimit.number_to_delimited(i.ingredient_cost, precision: 4) %>
          </div>
          <div class="w-[5%]">
            <%= Delimit.number_to_delimited(i.use_perc) %>%
          </div>
          <div class="w-[8%]">
            <%= Delimit.number_to_delimited(i.day_use_7) %>
          </div>
          <div class="w-[8%]">
            <%= Delimit.number_to_delimited(i.day_cost_7) %>
          </div>
          <div class="w-[9%]">
            <%= Delimit.number_to_delimited(i.day_use_30) %>
          </div>
          <div class="w-[9%]">
            <%= Delimit.number_to_delimited(i.day_cost_30) %>
          </div>
          <div class="w-[6%]">
            <%= Delimit.number_to_delimited(i.cost_perc) %>%
          </div>
        </div>
      <% end %>
      <div class="flex font-bold text-right border-y border-gray-600 p-2 bg-blue-200 mb-5">
        <div class="w-[24%]"></div>
        <div class="w-[25%]"></div>
        <div class="w-[6%]"></div>
        <div class="w-[5%]"></div>
        <div class="w-[8%]"><%= Delimit.number_to_delimited(@total_usage_7 * 7) %></div>
        <div class="w-[8%]"><%= Delimit.number_to_delimited(@total_cost_7) %></div>
        <div class="w-[9%]"><%= Delimit.number_to_delimited(@total_usage_30 * 30) %></div>
        <div class="w-[9%]"><%= Delimit.number_to_delimited(@total_cost_30) %></div>
        <div class="w-[6%]"></div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Ingredient Usages Listing")
     |> assign(sort_directions: @empty_sort_directions)
     |> filter()}
  end

  @impl true
  def handle_event("sort", %{"sort-by" => by}, socket) do
    dir = if(Map.fetch!(socket.assigns.sort_directions, by) == "asc", do: "desc", else: "asc")

    {:noreply,
     socket
     |> assign(
       ingredients:
         socket.assigns.ingredients
         |> Enum.sort_by(
           &Map.fetch!(&1, String.to_atom(by)),
           String.to_atom(dir)
         )
     )
     |> assign(sort_directions: Map.merge(@empty_sort_directions, %{by => dir}))}
  end

  defp direction_icon(dir, assigns) do
    assigns = assign(assigns, :dir, dir)

    ~H"""
    <span :if={@dir == "asc"}>&uarr;</span>
    <span :if={@dir == "desc"}>&darr;</span>
    """
  end

  defp filter(socket) do
    objects = query(socket) |> LeastCostFeed.Repo.all()

    total_use = objects |> Enum.reduce(0.0, fn x, acc -> acc + x.ingredient_usage_weight end)

    total_cost =
      objects
      |> Enum.reduce(0.0, fn x, acc -> acc + x.ingredient_usage_weight * x.ingredient_cost end)

    total_use_7 = objects |> Enum.reduce(0.0, fn x, acc -> acc + x.ingredient_usage_weight end)

    total_cost_7 =
      objects
      |> Enum.reduce(0.0, fn x, acc -> acc + x.ingredient_usage_weight * x.ingredient_cost * 7 end)

    total_use_30 = objects |> Enum.reduce(0.0, fn x, acc -> acc + x.ingredient_usage_weight end)

    total_cost_30 =
      objects
      |> Enum.reduce(0.0, fn x, acc ->
        acc + x.ingredient_usage_weight * x.ingredient_cost * 30
      end)

    objects =
      objects
      |> Enum.map(fn i ->
        i
        |> Map.merge(%{
          formula_list: i.formula_list,
          use_perc: i.ingredient_usage_weight / total_use * 100,
          day_use_7: i.ingredient_usage_weight * 7,
          day_cost_7: i.ingredient_usage_weight * 7 * i.ingredient_cost,
          day_use_30: i.ingredient_usage_weight * 30,
          day_cost_30: i.ingredient_usage_weight * 30 * i.ingredient_cost,
          cost_perc: i.ingredient_usage_weight * i.ingredient_cost / total_cost * 100
        })
      end)

    socket
    |> assign(ingredients: objects)
    |> assign(total_usage_7: total_use_7)
    |> assign(total_cost_7: total_cost_7)
    |> assign(total_usage_30: total_use_30)
    |> assign(total_cost_30: total_cost_30)
  end

  defp formula_links(fl) do
    String.split(fl, "|")
    |> Enum.map(fn sf ->
      [_all, code, id] = Regex.scan(~r/.+(\(.+\)).+\~(\d+)$/, sf) |> List.flatten()

      [String.slice(code, 1..(String.length(code) - 2)), id]
    end)
    |> Enum.sort()
  end

  defp formula_link([code, id], assigns) do
    assigns = assign(assigns, :code, code) |> assign(:id, id)

    ~H"""
    <.link class="text-blue-600 hover:underline" navigate={~p"/formulas/#{@id}/edit"}>
      <%= @code %>
    </.link>
    """
  end

  defp query(socket) do
    Ecto.Query.from(f in Formula,
      join: fi in FormulaIngredient,
      on: f.id == fi.formula_id,
      join: i in Ingredient,
      on: i.id == fi.ingredient_id,
      where: f.user_id == ^socket.assigns.current_user.id,
      where: fi.actual > 0.0,
      where: f.usage_per_day > 0.0,
      group_by: i.id,
      select: %{
        ingredient_id: i.id,
        ingredient_name: i.name,
        ingredient_cost: avg(fi.cost),
        ingredient_usage_weight: sum(fi.actual * f.usage_per_day),
        formula_list: fragment("string_agg(? || ' ~' || ?::varchar(15), '|')", f.name, f.id)
      }
    )
  end
end
