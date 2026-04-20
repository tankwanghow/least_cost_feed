defmodule LeastCostFeedWeb.FormulaLive.EfcForm do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeedWeb.Helpers
  alias LeastCostFeed.Entities
  alias LeastCostFeed.EfcPredict
  import Ecto.Query, warn: false

  @default_targets %{
    age_weeks_min: 25,
    age_weeks_max: 45,
    temp_min: 24.0,
    temp_max: 30.0,
    egg_weight_min: 58.0,
    egg_weight_max: 64.0,
    consumption_min: 105.0,
    consumption_max: 120.0,
    breed: "brown",
    housing: "cage",
    body_weight_kg: 1.90
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-1/2 min-w-[700px] mx-auto p-5">
      <.back navigate={~p"/formulas"}>Back Formula Listing</.back>
      <div class="font-bold text-3xl">EFC Nutrient Spec Generator</div>
      <p class="text-sm opacity-60 mb-3">
        Set production targets, generate nutrient specs, then save as a formula to add ingredients and optimize.
      </p>

      <%!-- Target Parameters --%>
      <div class="border border-base-300 bg-base-200 rounded-xl p-4 mb-4">
        <div class="font-bold text-lg mb-2">Production Targets</div>
        <form phx-change="update_targets">
          <div class="grid grid-cols-3 gap-3">
            <div>
              <label class="label text-xs font-semibold">Breed</label>
              <select name="breed" class="select select-bordered select-sm w-full">
                <option value="brown" selected={@targets.breed == "brown"}>Brown</option>
                <option value="white" selected={@targets.breed == "white"}>White</option>
              </select>
            </div>
            <div>
              <label class="label text-xs font-semibold">Housing</label>
              <select name="housing" class="select select-bordered select-sm w-full">
                <option value="cage" selected={@targets.housing == "cage"}>Cage</option>
                <option value="floor" selected={@targets.housing == "floor"}>Floor</option>
              </select>
            </div>
            <div>
              <label class="label text-xs font-semibold">Body Weight (kg)</label>
              <input type="number" name="body_weight_kg" value={@targets.body_weight_kg}
                step="any" class="input input-bordered input-sm w-full" />
            </div>
          </div>
          <div class="grid grid-cols-4 gap-3 mt-2">
            <div class="flex gap-1">
              <div class="w-1/2">
                <label class="label text-xs font-semibold">Age Min (wk)</label>
                <input type="number" name="age_weeks_min" value={@targets.age_weeks_min}
                  class="input input-bordered input-sm w-full" />
              </div>
              <div class="w-1/2">
                <label class="label text-xs font-semibold">Age Max (wk)</label>
                <input type="number" name="age_weeks_max" value={@targets.age_weeks_max}
                  class="input input-bordered input-sm w-full" />
              </div>
            </div>
            <div class="flex gap-1">
              <div class="w-1/2">
                <label class="label text-xs font-semibold">Temp Min (°C)</label>
                <input type="number" name="temp_min" value={@targets.temp_min}
                  step="any" class="input input-bordered input-sm w-full" />
              </div>
              <div class="w-1/2">
                <label class="label text-xs font-semibold">Temp Max (°C)</label>
                <input type="number" name="temp_max" value={@targets.temp_max}
                  step="any" class="input input-bordered input-sm w-full" />
              </div>
            </div>
            <div class="flex gap-1">
              <div class="w-1/2">
                <label class="label text-xs font-semibold">Egg Wt Min (g)</label>
                <input type="number" name="egg_weight_min" value={@targets.egg_weight_min}
                  step="any" class="input input-bordered input-sm w-full" />
              </div>
              <div class="w-1/2">
                <label class="label text-xs font-semibold">Egg Wt Max (g)</label>
                <input type="number" name="egg_weight_max" value={@targets.egg_weight_max}
                  step="any" class="input input-bordered input-sm w-full" />
              </div>
            </div>
            <div class="flex gap-1">
              <div class="w-1/2">
                <label class="label text-xs font-semibold">Feed Min (g/d)</label>
                <input type="number" name="consumption_min" value={@targets.consumption_min}
                  step="any" class="input input-bordered input-sm w-full" />
              </div>
              <div class="w-1/2">
                <label class="label text-xs font-semibold">Feed Max (g/d)</label>
                <input type="number" name="consumption_max" value={@targets.consumption_max}
                  step="any" class="input input-bordered input-sm w-full" />
              </div>
            </div>
          </div>
        </form>
      </div>

      <%!-- Action buttons --%>
      <div class="flex my-2 gap-2">
        <div class="btn btn-secondary font-bold" phx-click="generate_specs">
          Generate Nutrient Specs
        </div>
        <div
          :if={@nutrient_specs != []}
          class="btn btn-success font-bold"
          phx-click="save_as_formula"
        >
          Save as Formula
        </div>
      </div>

      <%!-- Nutrient Specs --%>
      <div>
        <div class="font-bold flex text-center">
          <div class="w-[3%]" />
          <div class="w-[37%]">Nutrient</div>
          <div class="w-[15%]">Min</div>
          <div class="w-[15%]">Max</div>
        </div>
        <%= for spec <- @nutrient_specs do %>
          <div class="flex text-sm">
            <div class="w-[3%] mt-1">
              <input type="checkbox" class="rounded" checked={spec.used}
                phx-click="toggle_nutrient_used" phx-value-id={spec.nutrient_id} />
            </div>
            <div class="w-[37%] truncate py-1"><%= spec.nutrient_name %>(<%= spec.nutrient_unit %>)</div>
            <div class="w-[15%]">
              <input type="number" step="any" class="input input-bordered input-xs w-full"
                value={Helpers.float_decimal(spec.min, decimals_for(spec.nutrient_unit, spec.min))}
                phx-blur="update_nutrient_spec" phx-value-id={spec.nutrient_id} phx-value-field="min" />
            </div>
            <div class="w-[15%]">
              <input type="number" step="any" class="input input-bordered input-xs w-full"
                value={Helpers.float_decimal(spec.max, decimals_for(spec.nutrient_unit, spec.max))}
                phx-blur="update_nutrient_spec" phx-value-id={spec.nutrient_id} phx-value-field="max" />
            </div>
          </div>
        <% end %>
        <div :if={@nutrient_specs == []} class="opacity-50 italic text-sm p-4">
          Click "Generate Nutrient Specs" to compute nutrient requirements from your targets.
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "EFC Nutrient Spec Generator")
     |> assign(targets: @default_targets)
     |> assign(nutrient_specs: [])}
  end

  @impl true
  def handle_event("update_targets", params, socket) do
    targets = socket.assigns.targets

    targets =
      targets
      |> update_target(params, "breed", :breed, &(&1))
      |> update_target(params, "housing", :housing, &(&1))
      |> update_target(params, "age_weeks_min", :age_weeks_min, &parse_int/1)
      |> update_target(params, "age_weeks_max", :age_weeks_max, &parse_int/1)
      |> update_target(params, "temp_min", :temp_min, &parse_float_val/1)
      |> update_target(params, "temp_max", :temp_max, &parse_float_val/1)
      |> update_target(params, "egg_weight_min", :egg_weight_min, &parse_float_val/1)
      |> update_target(params, "egg_weight_max", :egg_weight_max, &parse_float_val/1)
      |> update_target(params, "consumption_min", :consumption_min, &parse_float_val/1)
      |> update_target(params, "consumption_max", :consumption_max, &parse_float_val/1)
      |> update_target(params, "body_weight_kg", :body_weight_kg, &parse_float_val/1)

    {:noreply, assign(socket, targets: targets)}
  end

  @impl true
  def handle_event("generate_specs", _, socket) do
    user_nutrients = load_user_nutrients(socket.assigns.current_user.id)
    specs = EfcPredict.compute_nutrient_specs(socket.assigns.targets, user_nutrients)

    {:noreply,
     socket
     |> assign(nutrient_specs: specs)
     |> put_flash(:info, "Generated #{length(specs)} nutrient specs")}
  end

  @impl true
  def handle_event("toggle_nutrient_used", %{"id" => id}, socket) do
    int_id = String.to_integer(id)

    specs =
      Enum.map(socket.assigns.nutrient_specs, fn s ->
        if s.nutrient_id == int_id, do: %{s | used: !s.used}, else: s
      end)

    {:noreply, assign(socket, nutrient_specs: specs)}
  end

  @impl true
  def handle_event("update_nutrient_spec", %{"id" => id, "value" => value, "field" => field}, socket) do
    int_id = String.to_integer(id)
    parsed = parse_float_val(value)

    specs =
      Enum.map(socket.assigns.nutrient_specs, fn s ->
        if s.nutrient_id == int_id do
          Map.put(s, String.to_existing_atom(field), parsed)
        else
          s
        end
      end)

    {:noreply, assign(socket, nutrient_specs: specs)}
  end

  @impl true
  def handle_event("save_as_formula", _, socket) do
    targets = socket.assigns.targets
    age_mid = div(targets.age_weeks_min + targets.age_weeks_max, 2)

    formula_attrs = %{
      "name" => "EFC #{targets.breed} #{age_mid}wk #{targets.egg_weight_min}-#{targets.egg_weight_max}g",
      "batch_size" => "1000",
      "weight_unit" => "kg",
      "usage_per_day" => "0",
      "note" => "EFC generated: age #{targets.age_weeks_min}-#{targets.age_weeks_max}wk, #{targets.temp_min}-#{targets.temp_max}°C, egg #{targets.egg_weight_min}-#{targets.egg_weight_max}g",
      "user_id" => "#{socket.assigns.current_user.id}",
      "formula_ingredients" => %{},
      "formula_nutrients" =>
        socket.assigns.nutrient_specs
        |> Enum.with_index()
        |> Enum.map(fn {spec, i} ->
          {"#{i}",
           %{
             "nutrient_id" => "#{spec.nutrient_id}",
             "min" => if(spec.min, do: "#{spec.min}", else: ""),
             "max" => if(spec.max, do: "#{spec.max}", else: ""),
             "actual" => "0",
             "shadow" => "0",
             "used" => "#{spec.used}"
           }}
        end)
        |> Map.new()
    }

    case Entities.create_formula(formula_attrs) do
      {:ok, formula} ->
        {:noreply,
         socket
         |> put_flash(:info, "Formula saved! Add ingredients and optimize here.")
         |> push_navigate(to: ~p"/formulas/#{formula.id}/edit")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save formula")}
    end
  end

  # --- Private ---

  defp load_user_nutrients(user_id) do
    from(n in LeastCostFeed.Entities.Nutrient,
      where: n.user_id == ^user_id,
      select: %{id: n.id, name: n.name, unit: n.unit},
      order_by: n.name
    )
    |> LeastCostFeed.Repo.all()
  end

  defp update_target(targets, params, key, field, parser) do
    case Map.get(params, key) do
      nil -> targets
      "" -> targets
      val ->
        parsed = parser.(val)
        if parsed, do: Map.put(targets, field, parsed), else: targets
    end
  end

  defp parse_int(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_float_val(val) when is_number(val), do: val
  defp parse_float_val(nil), do: nil

  defp parse_float_val(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp decimals_for(_unit, nil), do: 4
  defp decimals_for("kcal/g", _val), do: 4
  defp decimals_for("mg/kg", _val), do: 1
  defp decimals_for("kIU/kg", _val), do: 1
  defp decimals_for("mg/g", _val), do: 2

  defp decimals_for("%" = _unit, val) when is_number(val) do
    cond do
      abs(val) >= 1.0 -> 2
      abs(val) >= 0.01 -> 4
      true -> 6
    end
  end

  defp decimals_for(_unit, _val), do: 4
end
