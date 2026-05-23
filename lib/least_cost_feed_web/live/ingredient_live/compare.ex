defmodule LeastCostFeedWeb.IngredientLive.Compare do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeedWeb.CompareHelpers

  @max 4

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Compare Ingredients", only_differences?: false)}
  end

  @impl true
  def handle_params(%{"ids" => ids_param}, _uri, socket) do
    requested_ids = parse_ids(ids_param)

    ingredients =
      Entities.list_ingredients_for_compare(socket.assigns.current_user.id, requested_ids)

    cond do
      length(ingredients) < 2 ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Compare needs 2–4 ingredients (you gave #{length(ingredients)} valid)."
         )
         |> push_navigate(to: ~p"/ingredients")}

      length(ingredients) > @max ->
        {:noreply,
         socket
         |> put_flash(:error, "Compare is limited to 4 ingredients.")
         |> push_navigate(to: ~p"/ingredients")}

      true ->
        ordered =
          Enum.sort_by(ingredients, fn i ->
            Enum.find_index(requested_ids, &(&1 == i.id))
          end)

        {:noreply, assign(socket, ingredients: ordered)}
    end
  end

  @impl true
  def render(assigns) do
    nutrients = CompareHelpers.union_nutrient_rows(assigns.ingredients, :ingredient)

    rows =
      Enum.map(nutrients, fn n ->
        cells = Enum.map(assigns.ingredients, &CompareHelpers.cell_value(&1, n, :ingredient, []))
        {n, cells}
      end)

    rows = if assigns.only_differences?, do: CompareHelpers.filter_differing_rows(rows), else: rows
    assigns = assign(assigns, rows_with_cells: rows)

    ~H"""
    <div class="w-11/12 mx-auto p-4">
      <.back navigate={~p"/ingredients"}>Back to Ingredients</.back>
      <div class="font-bold text-3xl mb-4">Compare Ingredients</div>

      <div class="flex flex-wrap gap-2 mb-4 items-center">
        <span
          :for={i <- @ingredients}
          class="px-3 py-1 rounded bg-primary text-primary-content text-sm flex items-center gap-1"
        >
          {i.name}
          <button
            phx-click="drop"
            phx-value-id={i.id}
            class="ml-1 text-primary-content/80 hover:text-primary-content"
            aria-label={"Remove " <> i.name}
          >✕</button>
        </span>
        <.live_component
          :if={length(@ingredients) < 4}
          module={LeastCostFeedWeb.IngredientLive.Compare.AddPicker}
          id="compare-add-picker"
          current_user={@current_user}
          current_ids={Enum.map(@ingredients, & &1.id)}
        />
      </div>

      <div class="mb-3 text-sm">
        <label class="flex items-center gap-1">
          <input type="checkbox" phx-click="toggle_only_diff" checked={@only_differences?} /> Only differences
        </label>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-sm border-collapse">
          <thead>
            <tr class="bg-primary text-primary-content">
              <th class="text-left p-2 w-[28%]">Nutrient</th>
              <th :for={i <- @ingredients} class="text-left p-2">{i.name}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{nutrient, cells} <- @rows_with_cells} class="border-b border-base-200">
              <td class="p-2 font-medium">{nutrient.name}</td>
              <%= for {cell, idx} <- Enum.with_index(cells) do %>
                <td class={[
                  "p-2",
                  idx > 0 &&
                    CompareHelpers.differs_from_anchor?(cell, List.first(cells)) && "bg-warning/20"
                ]}>
                  {cell.text}
                  <span
                    :if={idx > 0 && CompareHelpers.differs_from_anchor?(cell, List.first(cells))}
                    class="ml-1"
                  >
                    ●
                  </span>
                </td>
              <% end %>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("drop", %{"id" => id}, socket) do
    drop_id = String.to_integer(id)
    remaining = socket.assigns.ingredients |> Enum.map(& &1.id) |> Enum.reject(&(&1 == drop_id))

    if length(remaining) < 2 do
      {:noreply, push_navigate(socket, to: ~p"/ingredients")}
    else
      {:noreply,
       push_patch(socket, to: "/ingredients/compare?ids=" <> Enum.join(remaining, ","))}
    end
  end

  @impl true
  def handle_event("toggle_only_diff", _params, socket) do
    {:noreply, update(socket, :only_differences?, &(!&1))}
  end

  @impl true
  def handle_info({:patch_compare_ids, ids}, socket) do
    {:noreply,
     push_patch(socket, to: "/ingredients/compare?ids=" <> Enum.join(ids, ","))}
  end

  defp parse_ids(s) do
    s
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn part ->
      case Integer.parse(part) do
        {n, _} -> [n]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end
end

defmodule LeastCostFeedWeb.IngredientLive.Compare.AddPicker do
  use LeastCostFeedWeb, :live_component

  import Ecto.Query

  @impl true
  def update(assigns, socket) do
    candidates =
      from(i in LeastCostFeed.Entities.Ingredient,
        where: i.user_id == ^assigns.current_user.id and i.id not in ^assigns.current_ids,
        order_by: i.name,
        select: %{id: i.id, name: i.name}
      )
      |> LeastCostFeed.Repo.all()

    {:ok, socket |> assign(assigns) |> assign(candidates: candidates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form phx-submit="add" phx-target={@myself} class="flex items-center gap-1">
      <select name="id" class="select select-sm select-bordered">
        <option value="">+ Add ingredient…</option>
        <option :for={i <- @candidates} value={i.id}>{i.name}</option>
      </select>
      <button type="submit" class="btn btn-sm">Add</button>
    </form>
    """
  end

  @impl true
  def handle_event("add", %{"id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add", %{"id" => id}, socket) do
    new_id = String.to_integer(id)
    new_ids = socket.assigns.current_ids ++ [new_id]
    send(self(), {:patch_compare_ids, new_ids})
    {:noreply, socket}
  end
end
