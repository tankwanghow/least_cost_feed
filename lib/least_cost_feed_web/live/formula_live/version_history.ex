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

      <div :if={@versions == []} class="text-center py-10 text-base-content/50 text-lg">
        No saved versions yet.
      </div>

      <table :if={@versions != []} class="table table-zebra w-full text-sm">
        <thead>
          <tr>
            <th class="w-[8%]">Version</th>
            <th class="w-[20%]">Date</th>
            <th>Note</th>
            <th class="w-[15%] text-right">Cost/1000</th>
            <th class="w-[10%] text-right">Ingredients</th>
            <th class="w-[10%] text-right">Nutrients</th>
            <th class="w-[15%] text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={v <- @versions}>
            <td class="font-bold">v{v.version}</td>
            <td class="text-base-content/60">
              {Calendar.strftime(v.inserted_at, "%Y-%m-%d %H:%M")}
            </td>
            <td>{v.note || "—"}</td>
            <td class="text-right">
              {snapshot_cost(v.snapshot)}
            </td>
            <td class="text-right">
              {length(v.snapshot["formula_ingredients"] || [])}
            </td>
            <td class="text-right">
              {length(v.snapshot["formula_nutrients"] || [])}
            </td>
            <td class="text-right flex gap-1 justify-end">
              <button
                phx-click="restore"
                phx-value-id={v.id}
                data-confirm={"Restore version #{v.version}? This will overwrite the current formula."}
                class="btn btn-info btn-xs"
              >
                Restore
              </button>
              <button
                phx-click="delete"
                phx-value-id={v.id}
                data-confirm={"Delete version #{v.version}?"}
                class="btn btn-error btn-xs"
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
