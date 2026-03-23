defmodule LeastCostFeedWeb.FormulaLive.MultiNutrientRelax do
  use LeastCostFeedWeb, :live_view
  alias Phoenix.PubSub

  alias LeastCostFeedWeb.Helpers
  alias LeastCostFeed.{Entities, NutrientRelaxer}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-3/4 min-w-[1000px] mx-auto p-5">
      <.back navigate={~p"/formulas"}>Back to Formulas</.back>
      <div class="font-bold text-3xl mb-4">Multi-Formula Nutrient Relax</div>

      <div :if={@status == :selecting}>
        <div class="mb-4 text-gray-600">
          Select formulas to optimize together. Suggestions are ranked by total daily cost impact.
        </div>
        <table class="w-full text-sm mb-4">
          <thead>
            <tr class="border-b-2 border-gray-300 text-left">
              <th class="py-1 px-2 w-[5%]">
                <input type="checkbox" phx-click="toggle_all" checked={@all_selected?} />
              </th>
              <th class="py-1 px-2">Formula</th>
              <th class="py-1 px-2 text-right">Usage/Day</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={f <- @formulas} class="border-b border-gray-200 hover:bg-gray-50">
              <td class="py-1 px-2">
                <input
                  type="checkbox"
                  phx-click="toggle_formula"
                  phx-value-id={f.id}
                  checked={f.id in @selected_ids}
                />
              </td>
              <td class="py-1 px-2">
                <.link class="text-blue-600 hover:font-bold" navigate={~p"/formulas/#{f.id}/edit"}>
                  {f.name}
                </.link>
              </td>
              <td class="py-1 px-2 text-right">{Helpers.float_decimal(f.usage_per_day)}</td>
            </tr>
          </tbody>
        </table>
        <button
          phx-click="run_optimize"
          disabled={@selected_ids == []}
          class="blue button font-bold w-[20%]"
        >
          Optimize Selected ({length(@selected_ids)})
        </button>
      </div>

      <div :if={@status == :running} class="text-center py-20">
        <div class="text-xl font-bold text-blue-600 animate-pulse">
          Analyzing {length(@selected_ids)} formulas...
        </div>
        <div class="text-gray-500 mt-2">
          This may take a while with multiple formulas.
        </div>
      </div>

      <div :if={@status == :done}>
        <div class="flex gap-4 mb-4 text-lg">
          <div>
            Total Baseline Daily Cost:
            <span class="font-bold">{Helpers.float_decimal(@results.total_baseline_daily_cost, 2)}</span>
          </div>
        </div>

        <div :for={fr <- @results.formula_results} class="mb-4 p-3 border rounded bg-gray-50">
          <.link class="font-bold text-lg mb-1 text-blue-600 hover:underline" navigate={~p"/formulas/#{fr.formula_id}/edit"}>
            {fr.formula_name}
          </.link>
          <div class="text-sm text-gray-600">Usage/Day: {Helpers.float_decimal(fr.usage_per_day)}</div>
          <%= case fr.result do %>
            <% {:ok, baseline_cost, _suggestions, combined} -> %>
              <div class="text-sm">
                Cost/1000: <span class="font-bold">{Helpers.float_decimal(baseline_cost * 1000, 2)}</span>
                <span :if={combined} class="ml-4 text-green-700">
                  Combined Savings: {Helpers.float_decimal(combined.combined_savings, 2)}/1000
                </span>
              </div>
            <% {:error, reason} -> %>
              <div class="text-sm text-red-600">{reason}</div>
          <% end %>
        </div>

        <div :if={@sorted_suggestions != []}>
          <div class="font-bold text-xl mb-2">
            Cross-Formula Suggestions
          </div>
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b-2 border-gray-300 text-left">
                <th class="py-1 px-2 w-[3%]">
                  <input
                    type="checkbox"
                    phx-click="toggle_all_suggestions"
                    checked={@all_suggestions_selected?}
                  />
                </th>
                <.sort_th click="sort" col="formula_name" current={@sort_col} dir={@sort_dir}>
                  Formula
                </.sort_th>
                <.sort_th click="sort" col="nutrient_name" current={@sort_col} dir={@sort_dir}>
                  Nutrient
                </.sort_th>
                <.sort_th click="sort" col="field" current={@sort_col} dir={@sort_dir}>
                  Bound
                </.sort_th>
                <.sort_th click="sort" col="current" current={@sort_col} dir={@sort_dir} class="text-right">
                  Current
                </.sort_th>
                <.sort_th click="sort" col="suggested" current={@sort_col} dir={@sort_dir} class="text-right">
                  Suggested
                </.sort_th>
                <th class="py-1 px-2 text-right">Change</th>
                <.sort_th click="sort" col="individual_savings" current={@sort_col} dir={@sort_dir} class="text-right">
                  Savings/1000
                </.sort_th>
                <.sort_th click="sort" col="daily_savings" current={@sort_col} dir={@sort_dir} class="text-right">
                  Daily Savings
                </.sort_th>
              </tr>
            </thead>
            <tbody>
              <tr :for={s <- @sorted_suggestions} class="border-b border-gray-200 hover:bg-gray-50">
                <td class="py-1 px-2">
                  <input
                    type="checkbox"
                    phx-click="toggle_suggestion"
                    phx-value-fid={s.formula_id}
                    phx-value-nid={s.nutrient_id}
                    checked={MapSet.member?(@checked_suggestions, {s.formula_id, s.nutrient_id})}
                  />
                </td>
                <td class="py-1 px-2">
                  <.link class="text-blue-600 hover:font-bold" navigate={~p"/formulas/#{s.formula_id}/edit"}>
                    {s.formula_name}
                  </.link>
                </td>
                <td class="py-1 px-2">{s.nutrient_name} ({s.nutrient_unit})</td>
                <td class="py-1 px-2">{s.field}</td>
                <td class="py-1 px-2 text-right">{Helpers.float_decimal(s.current)}</td>
                <td class="py-1 px-2 text-right font-bold text-blue-700">
                  {Helpers.float_decimal(s.suggested)}
                </td>
                <td class="py-1 px-2 text-right text-gray-500">
                  {format_pct_change(s.current, s.suggested)}
                </td>
                <td class="py-1 px-2 text-right text-green-700">
                  {Helpers.float_decimal(s.individual_savings, 2)}
                </td>
                <td class="py-1 px-2 text-right font-bold text-green-700">
                  {Helpers.float_decimal(s.daily_savings, 2)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@sorted_suggestions == []} class="text-center py-10 text-gray-500 text-lg">
          No binding constraints found across selected formulas.
        </div>

        <div :if={@sorted_suggestions != []} class="flex gap-2 mt-6">
          <button
            phx-click="apply_selected"
            disabled={MapSet.size(@checked_suggestions) == 0}
            class="green button font-bold w-[20%]"
          >
            Apply Selected ({MapSet.size(@checked_suggestions)})
          </button>
          <button phx-click="apply_all" class="blue button font-bold w-[20%]">
            Apply All
          </button>
          <button phx-click="reset" class="gray button w-[15%]">
            Back to Selection
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :click, :string, required: true
  attr :col, :string, required: true
  attr :current, :string, required: true
  attr :dir, :atom, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  defp sort_th(assigns) do
    ~H"""
    <th
      class={"py-1 px-2 cursor-pointer select-none hover:bg-gray-100 #{@class}"}
      phx-click={@click}
      phx-value-col={@col}
    >
      {render_slot(@inner_block)}
      <span :if={@col == @current} class="ml-1 text-xs">
        {if @dir == :asc, do: "\u25B2", else: "\u25BC"}
      </span>
    </th>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    formulas = Entities.list_user_formulas(socket.assigns.current_user.id)

    {:ok,
     socket
     |> assign(
       page_title: "Multi-Formula Nutrient Relax",
       formulas: formulas,
       selected_ids: [],
       all_selected?: false,
       status: :selecting,
       results: nil,
       sorted_suggestions: [],
       checked_suggestions: MapSet.new(),
       all_suggestions_selected?: false,
       sort_col: "daily_savings",
       sort_dir: :desc
     )}
  end

  @impl true
  def handle_event("toggle_formula", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected_ids

    selected =
      if id in selected,
        do: List.delete(selected, id),
        else: [id | selected]

    {:noreply,
     assign(socket,
       selected_ids: selected,
       all_selected?: length(selected) == length(socket.assigns.formulas)
     )}
  end

  @impl true
  def handle_event("toggle_all", _, socket) do
    selected =
      if socket.assigns.all_selected?,
        do: [],
        else: Enum.map(socket.assigns.formulas, & &1.id)

    {:noreply, assign(socket, selected_ids: selected, all_selected?: !socket.assigns.all_selected?)}
  end

  @impl true
  def handle_event("toggle_suggestion", %{"fid" => fid, "nid" => nid}, socket) do
    key = {String.to_integer(fid), String.to_integer(nid)}
    checked = socket.assigns.checked_suggestions

    checked =
      if MapSet.member?(checked, key),
        do: MapSet.delete(checked, key),
        else: MapSet.put(checked, key)

    all? = MapSet.size(checked) == length(socket.assigns.sorted_suggestions)
    {:noreply, assign(socket, checked_suggestions: checked, all_suggestions_selected?: all?)}
  end

  @impl true
  def handle_event("toggle_all_suggestions", _, socket) do
    checked =
      if socket.assigns.all_suggestions_selected? do
        MapSet.new()
      else
        socket.assigns.sorted_suggestions
        |> Enum.map(fn s -> {s.formula_id, s.nutrient_id} end)
        |> MapSet.new()
      end

    {:noreply,
     assign(socket,
       checked_suggestions: checked,
       all_suggestions_selected?: !socket.assigns.all_suggestions_selected?
     )}
  end

  @impl true
  def handle_event("sort", %{"col" => col}, socket) do
    {col, dir} =
      if col == socket.assigns.sort_col do
        {col, if(socket.assigns.sort_dir == :asc, do: :desc, else: :asc)}
      else
        {col, :asc}
      end

    sorted = sort_suggestions(socket.assigns.results.ranked_suggestions, col, dir)
    {:noreply, assign(socket, sort_col: col, sort_dir: dir, sorted_suggestions: sorted)}
  end

  @impl true
  def handle_event("run_optimize", _, socket) do
    selected_ids = socket.assigns.selected_ids

    if selected_ids != [] do
      PubSub.subscribe(
        LeastCostFeed.PubSub,
        "#{socket.assigns.current_user.id}_multi_nutrient_relax_job"
      )

      Task.start(fn ->
        result = NutrientRelaxer.optimize_multi(selected_ids)

        PubSub.broadcast(
          LeastCostFeed.PubSub,
          "#{socket.assigns.current_user.id}_multi_nutrient_relax_job",
          {"multi_nutrient_relax_done", result}
        )
      end)

      {:noreply, assign(socket, status: :running)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset", _, socket) do
    {:noreply,
     assign(socket,
       status: :selecting,
       results: nil,
       sorted_suggestions: [],
       checked_suggestions: MapSet.new(),
       all_suggestions_selected?: false
     )}
  end

  @impl true
  def handle_event("apply_selected", _, socket) do
    apply_suggestions(socket, socket.assigns.checked_suggestions)
  end

  @impl true
  def handle_event("apply_all", _, socket) do
    all_keys =
      socket.assigns.sorted_suggestions
      |> Enum.map(fn s -> {s.formula_id, s.nutrient_id} end)
      |> MapSet.new()

    apply_suggestions(socket, all_keys)
  end

  @impl true
  def handle_info({"multi_nutrient_relax_done", {:ok, results}}, socket) do
    sorted = sort_suggestions(results.ranked_suggestions, socket.assigns.sort_col, socket.assigns.sort_dir)

    all_checked =
      sorted
      |> Enum.map(fn s -> {s.formula_id, s.nutrient_id} end)
      |> MapSet.new()

    {:noreply,
     assign(socket,
       status: :done,
       results: results,
       sorted_suggestions: sorted,
       checked_suggestions: all_checked,
       all_suggestions_selected?: true
     )}
  end

  @impl true
  def handle_info({"multi_nutrient_relax_done", {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(status: :selecting)
     |> put_flash(:error, "Optimization failed: #{reason}")}
  end

  defp apply_suggestions(socket, keys) do
    if MapSet.size(keys) == 0 do
      {:noreply, socket}
    else
      import Ecto.Query

      suggestions = socket.assigns.sorted_suggestions

      suggestions
      |> Enum.filter(fn s -> MapSet.member?(keys, {s.formula_id, s.nutrient_id}) end)
      |> Enum.each(fn s ->
        from(fn_ in LeastCostFeed.Entities.FormulaNutrient,
          where: fn_.formula_id == ^s.formula_id and fn_.nutrient_id == ^s.nutrient_id
        )
        |> LeastCostFeed.Repo.update_all(set: [{s.field, s.suggested}])
      end)

      count = MapSet.size(keys)

      {:noreply,
       socket
       |> put_flash(:info, "Applied #{count} relaxation suggestion#{if count > 1, do: "s", else: ""}")
       |> push_navigate(to: ~p"/formulas")}
    end
  end

  defp sort_suggestions(suggestions, col, dir) do
    key = String.to_existing_atom(col)

    Enum.sort_by(suggestions, &Map.get(&1, key), fn a, b ->
      case dir do
        :asc -> a <= b
        :desc -> a >= b
      end
    end)
  end

  defp format_pct_change(current, suggested) do
    pct = (suggested - current) / current * 100
    sign = if pct >= 0, do: "+", else: ""
    "#{sign}#{Helpers.float_decimal(pct, 1)}%"
  end
end
