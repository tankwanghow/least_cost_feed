defmodule LeastCostFeedWeb.FormulaLive.VersionHistory do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeedWeb.Helpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-3/4 min-w-[1000px] mx-auto p-5">
      <.back navigate={~p"/formulas/#{@formula_id}/edit"}>Back to Formula</.back>
      <div class="font-bold text-3xl mb-4">
        Version History — {@formula_name}
      </div>

      <div :if={@versions == []} class="text-center py-10 text-gray-500 text-lg">
        No saved versions yet.
      </div>

      <table :if={@versions != []} class="w-full text-sm">
        <thead>
          <tr class="border-b-2 border-gray-300 text-left">
            <th class="py-1 px-2 w-[8%]">Version</th>
            <th class="py-1 px-2 w-[20%]">Date</th>
            <th class="py-1 px-2">Note</th>
            <th class="py-1 px-2 w-[15%] text-right">Cost/1000</th>
            <th class="py-1 px-2 w-[10%] text-right">Ingredients</th>
            <th class="py-1 px-2 w-[10%] text-right">Nutrients</th>
            <th class="py-1 px-2 w-[15%] text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={v <- @versions} class="border-b border-gray-200 hover:bg-gray-50">
            <td class="py-1 px-2 font-bold">v{v.version}</td>
            <td class="py-1 px-2 text-gray-600">
              {Calendar.strftime(v.inserted_at, "%Y-%m-%d %H:%M")}
            </td>
            <td class="py-1 px-2">{v.note || "—"}</td>
            <td class="py-1 px-2 text-right">
              {snapshot_cost(v.snapshot)}
            </td>
            <td class="py-1 px-2 text-right">
              {length(v.snapshot["formula_ingredients"] || [])}
            </td>
            <td class="py-1 px-2 text-right">
              {length(v.snapshot["formula_nutrients"] || [])}
            </td>
            <td class="py-1 px-2 text-right flex gap-1 justify-end">
              <button
                phx-click="restore"
                phx-value-id={v.id}
                data-confirm={"Restore version #{v.version}? This will overwrite the current formula."}
                class="text-blue-600 hover:font-bold"
              >
                Restore
              </button>
              <button
                phx-click="delete"
                phx-value-id={v.id}
                data-confirm={"Delete version #{v.version}?"}
                class="text-red-600 hover:font-bold"
              >
                Delete
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    formula = Entities.get_formula!(id)
    versions = Entities.list_formula_versions(formula.id)

    {:ok,
     socket
     |> assign(
       page_title: "Version History — #{formula.name}",
       formula_id: formula.id,
       formula_name: formula.name,
       versions: versions
     )}
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    version = Entities.get_formula_version!(id)

    {:ok, _formula} = Entities.restore_formula_version(version)

    {:noreply,
     socket
     |> put_flash(:info, "Restored version #{version.version}")
     |> push_navigate(to: ~p"/formulas/#{socket.assigns.formula_id}/edit")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    version = Entities.get_formula_version!(id)
    {:ok, _} = Entities.delete_formula_version(version)
    versions = Entities.list_formula_versions(socket.assigns.formula_id)

    {:noreply,
     socket
     |> assign(versions: versions)
     |> put_flash(:info, "Deleted version #{version.version}")}
  end

  defp snapshot_cost(snapshot) do
    ingredients = snapshot["formula_ingredients"] || []

    total =
      Enum.reduce(ingredients, 0.0, fn fi, acc ->
        actual = to_float(fi["actual"])
        cost = to_float(fi["cost"])
        acc + actual * cost
      end)

    Helpers.float_decimal(total * 1000, 2)
  end

  defp to_float(nil), do: 0.0
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1
  defp to_float(v) when is_binary(v), do: String.to_float(v)
  defp to_float(%Decimal{} = v), do: Decimal.to_float(v)
end
