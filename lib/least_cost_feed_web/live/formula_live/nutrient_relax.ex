defmodule LeastCostFeedWeb.FormulaLive.NutrientRelax do
  use LeastCostFeedWeb, :live_view
  alias Phoenix.PubSub

  alias LeastCostFeedWeb.Helpers
  alias LeastCostFeed.{Entities, NutrientRelaxer}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-3/4 min-w-[1000px] mx-auto p-5">
      <.back navigate={~p"/formulas/#{@formula.id}/edit"}>Back to Formula</.back>
      <div class="font-bold text-3xl mb-2">
        Nutrient Relax — {@formula.name}
      </div>

      <div :if={@status == :running} class="text-center py-20">
        <div class="text-xl font-bold text-blue-600 animate-pulse">
          Analyzing shadow prices and testing relaxations...
        </div>
        <div class="text-gray-500 mt-2">
          This may take a few seconds.
        </div>
      </div>

      <div :if={@status == :error} class="text-center py-20">
        <div class="text-xl font-bold text-red-600">{@error_msg}</div>
        <.link navigate={~p"/formulas/#{@formula.id}/edit"} class="blue button mt-4 inline-block">
          Back to Formula
        </.link>
      </div>

      <div :if={@status == :done}>
        <div class="flex gap-4 mb-4 text-lg">
          <div>
            Current Cost/1000: <span class="font-bold">{Helpers.float_decimal(@baseline_cost * 1000, 2)}</span>
          </div>
          <div :if={@combined}>
            Suggested Cost/1000:
            <span class="font-bold text-green-700">
              {Helpers.float_decimal(@combined.combined_cost * 1000, 2)}
            </span>
          </div>
          <div :if={@combined}>
            Total Savings:
            <span class="font-bold text-green-700">
              {Helpers.float_decimal(@combined.combined_savings, 2)}
            </span>
          </div>
        </div>

        <div :if={@suggestions == []} class="text-center py-10 text-gray-500 text-lg">
          No binding nutrient constraints found. The formula is already at its cheapest
          given the current ingredient set.
        </div>

        <div :if={@suggestions != []}>
          <div class="font-bold text-xl mb-2">Individual Relaxation Impact</div>
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b-2 border-gray-300 text-left">
                <th class="py-1 px-2">Nutrient</th>
                <th class="py-1 px-2">Constraint</th>
                <th class="py-1 px-2 text-right">Current</th>
                <th class="py-1 px-2 text-right">Suggested</th>
                <th class="py-1 px-2 text-right">Change</th>
                <th class="py-1 px-2 text-right">Savings/1000</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={s <- @suggestions} class="border-b border-gray-200 hover:bg-gray-50">
                <td class="py-1 px-2">{s.nutrient_name} ({s.nutrient_unit})</td>
                <td class="py-1 px-2">{s.field}</td>
                <td class="py-1 px-2 text-right">{Helpers.float_decimal(s.current)}</td>
                <td class="py-1 px-2 text-right font-bold text-blue-700">
                  {Helpers.float_decimal(s.suggested)}
                </td>
                <td class="py-1 px-2 text-right text-gray-500">
                  {format_pct_change(s.current, s.suggested)}
                </td>
                <td class="py-1 px-2 text-right font-bold text-green-700">
                  {Helpers.float_decimal(s.individual_savings, 2)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@combined} class="mt-6">
          <div class="font-bold text-xl mb-2">Combined Suggestion</div>
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b-2 border-gray-300 text-left">
                <th class="py-1 px-2">Nutrient</th>
                <th class="py-1 px-2">Constraint</th>
                <th class="py-1 px-2 text-right">Current</th>
                <th class="py-1 px-2 text-right">Suggested</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={s <- @combined.suggestions} class="border-b border-gray-200">
                <td class="py-1 px-2">{s.nutrient_name} ({s.nutrient_unit})</td>
                <td class="py-1 px-2">{s.field}</td>
                <td class="py-1 px-2 text-right">{Helpers.float_decimal(s.current)}</td>
                <td class="py-1 px-2 text-right font-bold text-blue-700">
                  {Helpers.float_decimal(s.suggested)}
                </td>
              </tr>
            </tbody>
          </table>
          <div class="mt-2 text-lg">
            Combined Savings:
            <span class="font-bold text-green-700">
              {Helpers.float_decimal(@combined.combined_savings, 2)} /1000
            </span>
          </div>
        </div>

        <div class="flex gap-2 mt-6">
          <button
            :if={@combined}
            phx-click="apply_combined"
            class="green button font-bold w-[20%]"
          >
            Apply Combined
          </button>
          <.link navigate={~p"/formulas/#{@formula.id}/edit"} class="gray button w-[15%]">
            Cancel
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    formula = Entities.get_formula!(id)

    if connected?(socket) do
      PubSub.subscribe(
        LeastCostFeed.PubSub,
        "#{socket.assigns.current_user.id}_nutrient_relax_job"
      )

      send(self(), :run_analysis)
    end

    {:ok,
     socket
     |> assign(
       formula: formula,
       page_title: "Nutrient Relax — #{formula.name}",
       status: :running,
       error_msg: nil,
       baseline_cost: nil,
       suggestions: [],
       combined: nil
     )}
  end

  @impl true
  def handle_info(:run_analysis, socket) do
    formula = socket.assigns.formula
    changeset = Entities.change_formula(formula)

    Task.start(fn ->
      result = NutrientRelaxer.optimize(changeset)

      PubSub.broadcast(
        LeastCostFeed.PubSub,
        "#{formula.user_id}_nutrient_relax_job",
        {"nutrient_relax_done", result}
      )
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({"nutrient_relax_done", result}, socket) do
    socket =
      case result do
        {:ok, baseline_cost, suggestions, combined} ->
          socket
          |> assign(
            status: :done,
            baseline_cost: baseline_cost,
            suggestions: suggestions,
            combined: combined
          )

        {:error, reason} ->
          socket
          |> assign(status: :error, error_msg: "Optimization failed: #{reason}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_combined", _, socket) do
    formula = socket.assigns.formula
    combined = socket.assigns.combined

    if combined do
      import Ecto.Query

      Enum.each(combined.suggestions, fn s ->
        from(fn_ in LeastCostFeed.Entities.FormulaNutrient,
          where: fn_.formula_id == ^formula.id and fn_.nutrient_id == ^s.nutrient_id
        )
        |> LeastCostFeed.Repo.update_all(set: [{s.field, s.suggested}])
      end)

      {:noreply,
       socket
       |> put_flash(:info, "Relaxation suggestions applied — saved #{Helpers.float_decimal(combined.combined_savings, 2)}/1000")
       |> push_navigate(to: ~p"/formulas/#{formula.id}/edit")}
    else
      {:noreply, socket}
    end
  end

  defp format_pct_change(current, suggested) do
    pct = (suggested - current) / current * 100
    sign = if pct >= 0, do: "+", else: ""
    "#{sign}#{Helpers.float_decimal(pct, 1)}%"
  end
end
