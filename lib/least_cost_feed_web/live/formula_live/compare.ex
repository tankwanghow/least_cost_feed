defmodule LeastCostFeedWeb.FormulaLive.Compare do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeedWeb.CompareHelpers

  @max 4

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Compare Formulas",
       only_differences?: false,
       show_actuals?: false
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
           "Compare needs 2–4 formulas (you gave #{length(formulas)} valid)."
         )
         |> push_navigate(to: ~p"/formulas")}

      length(formulas) > @max ->
        {:noreply,
         socket
         |> put_flash(:error, "Compare is limited to 4 formulas.")
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
        <span :for={f <- @formulas} class="px-3 py-1 rounded bg-primary text-primary-content text-sm">
          {f.name}
        </span>
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
                </td>
              <% end %>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
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
