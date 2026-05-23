defmodule LeastCostFeedWeb.FormulaLive.Compare do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeedWeb.CompareHelpers

  @max 6

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Compare Formulas",
       only_differences?: false,
       show_actuals?: false,
       max: @max
     )}
  end

  @impl true
  def handle_params(%{"ids" => ids_param}, _uri, socket) do
    requested_ids = parse_ids(ids_param)
    formulas = Entities.list_formulas_for_compare(socket.assigns.current_user.id, requested_ids)

    cond do
      length(formulas) < 2 ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Compare needs 2–#{@max} formulas (you gave #{length(formulas)} valid)."
         )
         |> push_navigate(to: ~p"/formulas")}

      length(formulas) > @max ->
        {:noreply,
         socket
         |> put_flash(:error, "Compare is limited to #{@max} formulas.")
         |> push_navigate(to: ~p"/formulas")}

      true ->
        ordered =
          Enum.sort_by(formulas, fn f ->
            Enum.find_index(requested_ids, &(&1 == f.id))
          end)

        {:noreply, assign(socket, formulas: ordered)}
    end
  end

  @impl true
  def render(assigns) do
    rows_with_cells =
      build_rows(assigns.formulas, assigns.only_differences?, assigns.show_actuals?)

    assigns = assign(assigns, rows_with_cells: rows_with_cells)

    ~H"""
    <div class="w-11/12 mx-auto p-4">
      <.back navigate={~p"/formulas"}>Back to Formulas</.back>
      <div class="font-bold text-3xl mb-4">Compare Formulas</div>

      <div class="flex flex-wrap gap-2 mb-4 items-center">
        <span
          :for={f <- @formulas}
          class="px-3 py-1 rounded bg-primary text-primary-content text-sm flex items-center gap-1"
        >
          {f.name}
          <button
            phx-click="drop"
            phx-value-id={f.id}
            class="ml-1 text-primary-content/80 hover:text-primary-content"
            aria-label={"Remove " <> f.name}
          >✕</button>
        </span>
        <.live_component
          :if={length(@formulas) < @max}
          module={LeastCostFeedWeb.FormulaLive.Compare.AddPicker}
          id="compare-add-picker"
          current_user={@current_user}
          current_ids={Enum.map(@formulas, & &1.id)}
        />
      </div>

      <div class="flex items-center gap-4 mb-3 text-sm">
        <label class="flex items-center gap-1">
          <input type="checkbox" phx-click="toggle_only_diff" checked={@only_differences?} /> Only differences
        </label>
        <label class="flex items-center gap-1">
          <input type="checkbox" phx-click="toggle_show_actuals" checked={@show_actuals?} /> Show actuals
        </label>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-sm border-collapse">
          <thead>
            <tr class="bg-primary text-primary-content">
              <th class="text-left p-2 w-[28%]">Nutrient</th>
              <th :for={f <- @formulas} class="text-left p-2">{f.name}</th>
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
                  <span class={[cell.strike && "line-through opacity-60"]}>
                    {cell.text}
                  </span>
                  <span
                    :if={idx > 0 && CompareHelpers.differs_from_anchor?(cell, List.first(cells))}
                    class="ml-1"
                  >
                    ●
                  </span>
                  <div :if={cell.actual} class="text-xs text-base-content/60">
                    actual: {cell.actual}
                  </div>
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
    remaining = socket.assigns.formulas |> Enum.map(& &1.id) |> Enum.reject(&(&1 == drop_id))

    if length(remaining) < 2 do
      {:noreply,
       socket
       |> put_flash(:info, "Compare closed — fewer than 2 formulas remained.")
       |> push_navigate(to: ~p"/formulas")}
    else
      {:noreply,
       push_patch(socket, to: "/formulas/compare?ids=" <> Enum.join(remaining, ","))}
    end
  end

  @impl true
  def handle_event("toggle_only_diff", _params, socket) do
    {:noreply, update(socket, :only_differences?, &(!&1))}
  end

  @impl true
  def handle_event("toggle_show_actuals", _params, socket) do
    {:noreply, update(socket, :show_actuals?, &(!&1))}
  end

  @impl true
  def handle_info({:patch_compare_ids, ids}, socket) do
    {:noreply, push_patch(socket, to: "/formulas/compare?ids=" <> Enum.join(ids, ","))}
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

  defp build_rows(formulas, only_diff?, show_actuals?) do
    nutrients = CompareHelpers.union_nutrient_rows(formulas, :formula)

    rows =
      Enum.map(nutrients, fn n ->
        cells =
          Enum.map(formulas, &CompareHelpers.cell_value(&1, n, :formula, show_actuals: show_actuals?))

        {n, cells}
      end)

    if only_diff?, do: CompareHelpers.filter_differing_rows(rows), else: rows
  end
end

defmodule LeastCostFeedWeb.FormulaLive.Compare.AddPicker do
  use LeastCostFeedWeb, :live_component

  alias LeastCostFeed.Entities
  import Ecto.Query

  @impl true
  def update(assigns, socket) do
    all_ids = list_all_ids(assigns.current_user.id)

    candidates =
      Entities.list_formulas_for_compare(assigns.current_user.id, all_ids)
      |> Enum.reject(&(&1.id in assigns.current_ids))
      |> Enum.sort_by(& &1.name)

    {:ok, socket |> assign(assigns) |> assign(candidates: candidates)}
  end

  defp list_all_ids(user_id) do
    from(f in LeastCostFeed.Entities.Formula, where: f.user_id == ^user_id, select: f.id)
    |> LeastCostFeed.Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form phx-submit="add" phx-target={@myself} class="flex items-center gap-1">
      <select name="id" class="select select-sm select-bordered">
        <option value="">+ Add formula…</option>
        <option :for={f <- @candidates} value={f.id}>{f.name}</option>
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
