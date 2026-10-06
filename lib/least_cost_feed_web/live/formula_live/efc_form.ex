defmodule LeastCostFeedWeb.FormulaLive.EfcForm do
  @moduledoc """
  `/formulas/efc_optimizer` — three tabs (`?tab=`):

    * `spec` (default) — EFC Nutrient Spec Generator. Basis "Legacy EFC"
      (deprecated `EfcPredict`, unchanged default) or "Hisex Brown model"
      (`HenModel.spec_for/3`).
    * `simulator` — Hisex Brown hen simulator (`HenModel.simulate/3`):
      one formula or a phase programme, cycle or snapshot.
    * `compare` — 2-4 formulas under one shared scenario (`HenModel.compare/3`).

  Every result panel shows the digestibility basis, diet warnings, the
  ASSUMED/PLACEHOLDER parameters and the model limits.
  """
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeedWeb.Helpers
  alias LeastCostFeed.{Entities, EfcPredict, HenModel}
  alias LeastCostFeed.HenModel.{AminoAcids, Diet, Digestibility, Economics, Params}
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
    body_weight_kg: 1.90,
    basis: "legacy"
  }

  @tabs ~w(spec simulator compare)
  @max_programme 4
  @max_compare 4

  # Option values accepted from the form (anything else falls back to the default).
  @choices %{
    "mode" => ~w(cycle snapshot),
    "housing" => ~w(cage barn free_range),
    "edition" => ~w(sea global),
    "energy_scaling" => ~w(guide_anchored published),
    "energy_equation" => ~w(sakomura sakomura_alt emmans),
    "route" => Enum.map(Digestibility.routes(), &Atom.to_string/1),
    "heat_egg_weight" => ~w(intake explicit),
    "aa_maint_set" => ~w(a b),
    "energy_limit" => ~w(flock per_hen),
    "egg_pricing" => ~w(per_kg per_egg)
  }

  # Compile-time string -> atom table for the choices above (no runtime atom creation).
  @choice_atoms Map.new(@choices, fn {k, vs} -> {k, Map.new(vs, &{&1, String.to_atom(&1)})} end)

  # Form fields that override a parameters.csv value.
  @override_fields %{
    "lambda" => "intake_aa_drive_lambda",
    "headroom" => "intake_cap_headroom",
    "sigma_e" => "geno_sigma_emax"
  }

  @limits [
    "Predicts flock averages, not individual hens; variation between hens is statistical (200 virtual hens).",
    "Disease, stress, lighting, moult, mycotoxins, water and management errors are outside the model.",
    "Genetic potential is the breeder's guide (Hisex SEA/global) until calibrated on your flocks.",
    "AA maintenance values come from broiler-breeder pullets (S14/S15) or roosters (S13); the pullet feather/LCT term is applied to hens.",
    "Per-g-egg AA coefficients are back-calculated from Hendrix's own requirements (with safety margins); AA excess is not penalised.",
    "Energy: published Sakomura under-predicts guide intake; guide-anchored mode scales maintenance at a reference temperature you choose. Onset intake (wk 20-21) and late-cycle intake are under-predicted.",
    "Heat-stress intake cap and direct heat lay penalty are placeholders (off). The default intake-mediated mode does not reproduce the guide's egg-weight heat response; use the explicit option for that.",
    "The shell-risk index is a rule-based screen, not a shell-strength prediction.",
    "Egg composition is fixed; age-related changes are not modelled.",
    "Digestibility routes B and D are approximations; prefer A (SID nutrients) or C (CVB per ingredient, mapping still to be confirmed)."
  ]

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id

    {:ok,
     socket
     |> assign(page_title: "EFC Optimizer & Hisex Brown Simulator")
     |> assign(tab: "spec")
     |> assign(targets: @default_targets)
     |> assign(nutrient_specs: [])
     |> assign(formulas: Entities.list_user_formulas(user_id))
     |> assign(sim: default_sim_params())
     |> assign(compare_ids: [], max_compare: @max_compare)
     |> assign(sim_result: nil, sim_error: nil)
     |> assign(compare_results: nil, compare_error: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "spec"
    {:noreply, assign(socket, tab: tab)}
  end

  # ---------------------------------------------------------------- render

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["mx-auto p-5", if(@tab == "spec", do: "w-1/2 min-w-[700px]", else: "w-11/12")]}>
      <.back navigate={~p"/formulas"}>Back Formula Listing</.back>
      <div role="tablist" class="tabs tabs-boxed mb-3 w-fit">
        <.link
          :for={
            {t, label} <- [
              {"spec", "Spec Generator"},
              {"simulator", "Hen Simulator"},
              {"compare", "Compare"}
            ]
          }
          patch={~p"/formulas/efc_optimizer?tab=#{t}"}
          role="tab"
          id={"tab-#{t}"}
          class={["tab", @tab == t && "tab-active"]}
        >
          {label}
        </.link>
      </div>

      <.spec_tab :if={@tab == "spec"} targets={@targets} nutrient_specs={@nutrient_specs} />

      <div :if={@tab == "simulator"}>
        <div class="font-bold text-3xl">Hisex Brown Hen Simulator</div>
        <p class="text-sm opacity-60 mb-3">
          Mechanistic model (Hisex Brown guide potential, Sakomura energy, Reading-model SID amino acids, 200 virtual hens).
          Pick a formula or a phase programme and a house scenario.
        </p>
        <form id="sim-form" phx-change="sim_change" phx-submit="sim_run">
          <.programme_inputs sim={@sim} formulas={@formulas} />
          <.scenario_inputs sim={@sim} />
          <button type="submit" class="btn btn-secondary font-bold mt-3" id="sim-run">Run simulation</button>
        </form>
        <div :if={@sim_error} class="alert alert-error mt-3" id="sim-error">{@sim_error}</div>
        <.sim_results :if={@sim_result} result={@sim_result} />
      </div>

      <div :if={@tab == "compare"}>
        <div class="font-bold text-3xl">Compare Formulas on Hisex Brown</div>
        <p class="text-sm opacity-60 mb-3">
          Choose 2-{@max_compare} formulas; each is fed for the whole run under the same scenario.
        </p>
        <form id="compare-form" phx-change="compare_change" phx-submit="compare_run">
          <div class="border border-base-300 bg-base-200 rounded-xl p-3 mb-3">
            <div class="font-bold mb-1">Formulas</div>
            <div class="grid grid-cols-3 gap-1 max-h-48 overflow-y-auto text-sm">
              <label :for={f <- @formulas} class="flex items-center gap-1">
                <input
                  type="checkbox"
                  name="compare_ids[]"
                  value={f.id}
                  checked={f.id in @compare_ids}
                  disabled={length(@compare_ids) >= @max_compare and f.id not in @compare_ids}
                />
                {f.name}
              </label>
            </div>
            <div :if={@formulas == []} class="italic opacity-60 text-sm">
              You have no formulas yet.
            </div>
          </div>
          <.scenario_inputs sim={@sim} />
          <button type="submit" class="btn btn-secondary font-bold mt-3" id="compare-run">Compare</button>
        </form>
        <div :if={@compare_error} class="alert alert-error mt-3" id="compare-error">
          {@compare_error}
        </div>
        <.compare_results :if={@compare_results} results={@compare_results} />
      </div>
    </div>
    """
  end

  # --- spec generator (existing behaviour, plus basis selector)

  attr :targets, :map, required: true
  attr :nutrient_specs, :list, required: true

  defp spec_tab(assigns) do
    ~H"""
    <div class="font-bold text-3xl">EFC Nutrient Spec Generator</div>
    <p class="text-sm opacity-60 mb-3">
      Set production targets, generate nutrient specs, then save as a formula to add ingredients and optimize.
    </p>

    <div class="border border-base-300 bg-base-200 rounded-xl p-4 mb-4">
      <div class="font-bold text-lg mb-2">Production Targets</div>
      <form phx-change="update_targets" id="spec-form">
        <div class="grid grid-cols-4 gap-3">
          <div>
            <label class="label text-xs font-semibold">Basis</label>
            <select name="basis" class="select select-bordered select-sm w-full">
              <option value="legacy" selected={@targets.basis == "legacy"}>
                Legacy EFC (deprecated)
              </option>
              <option value="hisex" selected={@targets.basis == "hisex"}>Hisex Brown model</option>
            </select>
          </div>
          <div>
            <label class="label text-xs font-semibold">Breed</label>
            <select
              name="breed"
              class="select select-bordered select-sm w-full"
              disabled={@targets.basis == "hisex"}
            >
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
            <input
              type="number"
              name="body_weight_kg"
              value={@targets.body_weight_kg}
              step="any"
              class="input input-bordered input-sm w-full"
              disabled={@targets.basis == "hisex"}
            />
          </div>
        </div>
        <div class="grid grid-cols-4 gap-3 mt-2">
          <div :for={
            {lbl_min, k_min, lbl_max, k_max} <- [
              {"Age Min (wk)", :age_weeks_min, "Age Max (wk)", :age_weeks_max},
              {"Temp Min (°C)", :temp_min, "Temp Max (°C)", :temp_max},
              {"Egg Wt Min (g)", :egg_weight_min, "Egg Wt Max (g)", :egg_weight_max},
              {"Feed Min (g/d)", :consumption_min, "Feed Max (g/d)", :consumption_max}
            ]
          }>
            <div class="flex gap-1">
              <div class="w-1/2">
                <label class="label text-xs font-semibold">{lbl_min}</label>
                <input
                  type="number"
                  name={k_min}
                  value={Map.get(@targets, k_min)}
                  step="any"
                  class="input input-bordered input-sm w-full"
                />
              </div>
              <div class="w-1/2">
                <label class="label text-xs font-semibold">{lbl_max}</label>
                <input
                  type="number"
                  name={k_max}
                  value={Map.get(@targets, k_max)}
                  step="any"
                  class="input input-bordered input-sm w-full"
                />
              </div>
            </div>
          </div>
        </div>
        <p :if={@targets.basis == "hisex"} class="text-xs mt-2 opacity-70">
          Hisex Brown model: SID amino acids from a·E + m·W^0.75 at the mid age (Hisex SEA guide egg mass and BW),
          Ca/avP from the Hendrix phase band, ME from Sakomura (guide-anchored) at the mid feed intake and temperature.
          Written to SID nutrients if your account has them, otherwise to total via Hendrix SID/total ratios (approximate).
          Egg-weight targets are not used. Floor housing is treated as barn (+9 % maintenance energy).
        </p>
      </form>
    </div>

    <div class="flex my-2 gap-2">
      <div class="btn btn-secondary font-bold" phx-click="generate_specs" id="generate-specs">
        Generate Nutrient Specs
      </div>
      <div :if={@nutrient_specs != []} class="btn btn-success font-bold" phx-click="save_as_formula">
        Save as Formula
      </div>
    </div>

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
            <input
              type="checkbox"
              class="rounded"
              checked={spec.used}
              phx-click="toggle_nutrient_used"
              phx-value-id={spec.nutrient_id}
            />
          </div>
          <div class="w-[37%] truncate py-1">{spec.nutrient_name}({spec.nutrient_unit})</div>
          <div class="w-[15%]">
            <input
              type="number"
              step="any"
              class="input input-bordered input-xs w-full"
              value={Helpers.float_decimal(spec.min, decimals_for(spec.nutrient_unit, spec.min))}
              phx-blur="update_nutrient_spec"
              phx-value-id={spec.nutrient_id}
              phx-value-field="min"
            />
          </div>
          <div class="w-[15%]">
            <input
              type="number"
              step="any"
              class="input input-bordered input-xs w-full"
              value={Helpers.float_decimal(spec.max, decimals_for(spec.nutrient_unit, spec.max))}
              phx-blur="update_nutrient_spec"
              phx-value-id={spec.nutrient_id}
              phx-value-field="max"
            />
          </div>
        </div>
      <% end %>
      <div :if={@nutrient_specs == []} class="opacity-50 italic text-sm p-4">
        Click "Generate Nutrient Specs" to compute nutrient requirements from your targets.
      </div>
    </div>
    """
  end

  # --- simulator inputs

  attr :sim, :map, required: true
  attr :formulas, :list, required: true

  defp programme_inputs(assigns) do
    assigns = assign(assigns, rows: 0..(@max_programme - 1))

    ~H"""
    <div class="border border-base-300 bg-base-200 rounded-xl p-3 mb-3">
      <div class="font-bold mb-1">Formula / phase programme</div>
      <div class="grid grid-cols-4 gap-2">
        <div :for={i <- @rows}>
          <label class="label text-xs font-semibold">
            {if i == 0, do: "Formula (from start)", else: "then from week"}
          </label>
          <div class="flex gap-1">
            <input
              :if={i > 0}
              type="number"
              name={"sim[prog][#{i}][from_week]"}
              value={get_in(@sim, ["prog", "#{i}", "from_week"])}
              class="input input-bordered input-sm w-20"
              placeholder="wk"
            />
            <select
              name={"sim[prog][#{i}][formula_id]"}
              class="select select-bordered select-sm w-full"
              id={"prog-#{i}"}
            >
              <option value="">{if i == 0, do: "— choose —", else: "— none —"}</option>
              <option
                :for={f <- @formulas}
                value={f.id}
                selected={get_in(@sim, ["prog", "#{i}", "formula_id"]) == "#{f.id}"}
              >
                {f.name}
              </option>
            </select>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :sim, :map, required: true

  defp scenario_inputs(assigns) do
    ~H"""
    <div class="border border-base-300 bg-base-200 rounded-xl p-3">
      <div class="font-bold mb-1">Scenario</div>
      <div class="grid grid-cols-6 gap-2">
        <.sel
          name="mode"
          label="Mode"
          sim={@sim}
          options={[{"cycle", "Cycle (weekly)"}, {"snapshot", "Snapshot (one age)"}]}
        />
        <.num name="start_week" label="Start week" sim={@sim} />
        <.num name="end_week" label="End week (≤100)" sim={@sim} />
        <.num name="snapshot_week" label="Snapshot age (wk)" sim={@sim} />
        <.num name="temp_c" label="House mean T (°C)" sim={@sim} />
        <.num name="temp_max_c" label="House max T (°C)" sim={@sim} placeholder="= mean" />
        <.sel
          name="housing"
          label="Housing"
          sim={@sim}
          options={[
            {"cage", "Cage"},
            {"barn", "Barn/aviary (+9%)"},
            {"free_range", "Free range (+12%)"}
          ]}
        />
        <.num name="feather" label="Feather score 0-1" sim={@sim} />
        <.num name="hens_housed" label="Hens housed" sim={@sim} />
        <.num name="feed_price" label="Feed price /kg" sim={@sim} placeholder="formula cost" />
        <.sel
          name="egg_pricing"
          label="Egg price basis"
          sim={@sim}
          options={[{"per_kg", "Per kg"}, {"per_egg", "Per egg by grade"}]}
        />
        <.num name="egg_price" label="Egg price /kg" sim={@sim} placeholder="required for margin" />
      </div>
      <div :if={@sim["egg_pricing"] == "per_egg"} class="mt-2">
        <label class="label text-xs font-semibold">
          Grade bands: one per line "name,min_g,max_g,price_per_egg" (blank min/max = open). No default bands (PLACEHOLDER).
        </label>
        <textarea name="sim[grade_bands]" rows="3" class="textarea textarea-bordered w-full text-sm">{@sim["grade_bands"]}</textarea>
      </div>
      <details class="mt-2">
        <summary class="cursor-pointer text-sm font-semibold">Model options</summary>
        <div class="grid grid-cols-6 gap-2 mt-2">
          <.sel
            name="edition"
            label="Guide"
            sim={@sim}
            options={[{"sea", "Hisex SE Asia"}, {"global", "Hisex global"}]}
          />
          <.sel
            name="energy_scaling"
            label="Energy scaling"
            sim={@sim}
            options={[{"guide_anchored", "Guide-anchored"}, {"published", "As published (k_m=1)"}]}
          />
          <.num name="anchor_ref_temp" label="Anchor ref T (°C)" sim={@sim} />
          <.sel
            name="energy_equation"
            label="Energy equation"
            sim={@sim}
            options={[
              {"sakomura", "Sakomura 2004"},
              {"sakomura_alt", "Sakomura alt."},
              {"emmans", "Emmans 1974"}
            ]}
          />
          <.num name="lambda" label="AA intake drive λ (0-1)" sim={@sim} />
          <.num name="headroom" label="Intake cap headroom" sim={@sim} />
          <.sel
            name="route"
            label="Digestibility"
            sim={@sim}
            options={
              Enum.map(Digestibility.routes(), &{Atom.to_string(&1), Digestibility.route_label(&1)})
            }
          />
          <.sel
            name="heat_egg_weight"
            label="Heat on egg weight"
            sim={@sim}
            options={[{"intake", "Via intake only"}, {"explicit", "Explicit S4 slopes"}]}
          />
          <.sel
            name="aa_maint_set"
            label="AA maintenance"
            sim={@sim}
            options={[{"a", "Set A (S14/S15)"}, {"b", "Set B (S13)"}]}
          />
          <.sel
            name="energy_limit"
            label="Energy limit"
            sim={@sim}
            options={[{"flock", "Flock (default)"}, {"per_hen", "Per hen (SPEC literal)"}]}
          />
          <.num name="sigma_e" label="σ Emax (g/d)" sim={@sim} />
          <.num
            name="coarse_share"
            label="Coarse limestone share"
            sim={@sim}
            placeholder="optional 0-1"
          />
        </div>
      </details>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :sim, :map, required: true
  attr :placeholder, :string, default: nil

  defp num(assigns) do
    ~H"""
    <div>
      <label class="label text-xs font-semibold">{@label}</label>
      <input
        type="number"
        step="any"
        name={"sim[#{@name}]"}
        value={@sim[@name]}
        placeholder={@placeholder}
        class="input input-bordered input-sm w-full"
      />
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :sim, :map, required: true
  attr :options, :list, required: true

  defp sel(assigns) do
    ~H"""
    <div>
      <label class="label text-xs font-semibold">{@label}</label>
      <select name={"sim[#{@name}]"} class="select select-bordered select-sm w-full">
        <option :for={{v, l} <- @options} value={v} selected={@sim[@name] == v}>{l}</option>
      </select>
    </div>
    """
  end

  # --- simulator results

  attr :result, :map, required: true

  defp sim_results(assigns) do
    assigns =
      assign(assigns,
        s: assigns.result.summary,
        weeks: assigns.result.weeks,
        multi: length(assigns.result.diets) > 1,
        hens: assigns.result.scenario.hens_housed
      )

    ~H"""
    <div id="sim-results" class="mt-4">
      <div class="grid grid-cols-6 gap-2 mb-3">
        <.stat label="Eggs / hen housed" value={fmt(@s.eggs_hh, 1)} />
        <.stat label="Egg mass / HH (kg)" value={fmt(@s.egg_mass_hh_kg, 2)} />
        <.stat label="Avg lay %" value={fmt(@s.avg_lay, 1)} />
        <.stat label="Avg egg wt (g)" value={fmt(@s.avg_ew, 1)} />
        <.stat label="Avg feed (g/d)" value={fmt(@s.avg_fi, 1)} />
        <.stat label="FCR (kg/kg)" value={fmt(@s.fcr, 3)} />
        <.stat label="BW at end (g)" value={fmt(@s.bw_end_g, 0)} />
        <.stat label="Margin / hen housed" value={fmt(@s.margin_hh, 2)} />
        <.stat label={"Margin, #{@hens} hens"} value={@s.margin_hh && fmt(@s.margin_hh * @hens, 0)} />
        <.stat label="Margin /1000 hens /wk" value={fmt(@s.margin_per_1000_week, 0)} />
        <.stat
          label="Weeks Moderate / High shell risk"
          value={"#{@s.weeks_moderate} / #{@s.weeks_high}"}
        />
        <.stat label="k_m used" value={fmt(@result.km, 3)} />
      </div>

      <.diet_panel diets={@result.diets} />

      <div :if={length(@weeks) > 1} class="grid grid-cols-3 gap-3 my-3">
        <.chart title="Lay % (hen-day)" weeks={@weeks} key={:lay} />
        <.chart title="Egg weight (g)" weeks={@weeks} key={:ew} />
        <.chart title="Egg mass (g/d)" weeks={@weeks} key={:egg_mass} />
        <.chart title="Feed intake (g/d)" weeks={@weeks} key={:fi} />
        <.chart title="Body weight (g)" weeks={@weeks} key={:bw_g} />
        <.chart
          title="Margin / 1000 hens / wk"
          weeks={@weeks}
          key={:margin_per_1000_week}
          guide={false}
        />
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-xs border-collapse" id="sim-weeks">
          <thead>
            <tr class="bg-primary text-primary-content">
              <th class="p-1">Wk</th>
              <th :if={@multi} class="p-1 text-left">Formula</th>
              <th class="p-1">Lay % (guide)</th>
              <th class="p-1">Egg wt g (guide)</th>
              <th class="p-1">Egg mass g/d</th>
              <th class="p-1">Feed g/d (guide)</th>
              <th class="p-1">FCR</th>
              <th class="p-1">BW g (guide)</th>
              <th class="p-1 text-left">First-limiting (% hens)</th>
              <th class="p-1">Shell risk</th>
              <th class="p-1">Margin /1000 hens /wk</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={w <- @weeks} class="border-b border-base-200 text-center">
              <td class="p-1">{w.week}</td>
              <td :if={@multi} class="p-1 text-left">{w.formula}</td>
              <td class="p-1">
                {fmt(w.lay, 1)} <span class="opacity-50">({fmt(w.guide.lay, 1)})</span>
              </td>
              <td class="p-1">
                {fmt(w.ew, 1)} <span class="opacity-50">({fmt(w.guide.ew, 1)})</span>
              </td>
              <td class="p-1">{fmt(w.egg_mass, 1)}</td>
              <td class="p-1">
                {fmt(w.fi, 1)} <span class="opacity-50">({fmt(w.guide.fi, 0)})</span>
              </td>
              <td class="p-1">{fmt(w.fcr, 2)}</td>
              <td class="p-1">
                {fmt(w.bw_g, 0)} <span class="opacity-50">({fmt(w.guide.bw_g, 0)})</span>
              </td>
              <td class="p-1 text-left">{limiting_text(w)}</td>
              <td class="p-1"><.risk shell={w.shell} /></td>
              <td class="p-1">{fmt(w.margin_per_1000_week, 0)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <.assumptions_panel scenario={@result.scenario} km={@result.km} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-lg p-2 text-center">
      <div class="text-xs opacity-60">{@label}</div>
      <div class="font-bold">{@value || "—"}</div>
    </div>
    """
  end

  attr :shell, :map, required: true

  defp risk(assigns) do
    ~H"""
    <span
      class={[
        "badge badge-sm",
        @shell.class == :low && "badge-success",
        @shell.class == :moderate && "badge-warning",
        @shell.class == :high && "badge-error"
      ]}
      title={Enum.join(@shell.reasons, "; ")}
    >
      {@shell.class |> Atom.to_string() |> String.capitalize()}
    </span>
    """
  end

  attr :diets, :list, required: true

  defp diet_panel(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-xl p-3 text-sm" id="diet-panel">
      <div :for={d <- @diets} class="mb-2">
        <span class="font-bold">{d.name}</span>
        <span
          class={["badge badge-sm ml-1", approximate?(d) && "badge-warning"]}
          title="digestibility basis"
        >
          digestibility {Diet.basis_badge(d)}{if d.unmapped != [],
            do: " (#{length(d.unmapped)} unmapped → D)"}
        </span>
        <span :if={approximate?(d)} class="text-xs ml-1 opacity-70">approximate digestibility</span>
        <span class="ml-2 opacity-70">
          ME {fmt(d.me && d.me * 1000, 0)} kcal/kg · cost/kg {fmt(d.cost_per_kg, 3)} ·
          SID mg/g: {Enum.map_join(AminoAcids.aas(), ", ", fn aa ->
            "#{AminoAcids.label(aa)} #{fmt(d.sid[aa], 2)}"
          end)}
        </span>
        <ul :if={d.warnings != []} class="list-disc ml-6 text-warning-content/80 text-xs">
          <li :for={w <- d.warnings}>{w}</li>
        </ul>
      </div>
    </div>
    """
  end

  attr :scenario, :map, required: true
  attr :km, :float, required: true

  defp assumptions_panel(assigns) do
    assigns = assign(assigns, flagged: Params.flagged(), limits: @limits)

    ~H"""
    <details class="border border-base-300 rounded-xl p-3 mt-4 text-sm" id="assumptions-panel" open>
      <summary class="font-bold cursor-pointer">Assumptions & limits</summary>
      <div class="mt-2">
        <div class="mb-1">
          Scenario: {@scenario.temp_c} °C mean / {@scenario.temp_max_c} °C max, {@scenario.housing}, feather {@scenario.feather},
          guide {@scenario.edition |> Atom.to_string() |> String.upcase()}, energy {@scenario.energy_equation} ({@scenario.energy_scaling}{if @scenario.energy_scaling ==
                                                                                                                                                :guide_anchored,
                                                                                                                                              do:
                                                                                                                                                " at #{@scenario.anchor_ref_temp} °C"}, k_m {fmt(
            @km,
            3
          )}),
          AA maintenance set {@scenario.aa_maint_set |> Atom.to_string() |> String.upcase()}, energy limit {@scenario.energy_limit}, heat on EW {@scenario.heat_egg_weight}.
        </div>
        <div :if={@scenario.overrides != %{}} class="mb-1">
          Your overrides:
          <span :for={{k, v} <- @scenario.overrides} class="badge badge-info badge-sm mr-1">{k} = {v}</span>
        </div>
        <table class="w-full text-xs border-collapse my-2">
          <thead>
            <tr class="bg-base-200">
              <th class="p-1 text-left">Parameter</th>
              <th class="p-1 text-left">Value</th>
              <th class="p-1 text-left">Status</th>
              <th class="p-1 text-left">Why / what is missing</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={p <- @flagged} class="border-b border-base-200">
              <td class="p-1">
                <span class="font-mono">{p.id}</span><br /><span class="opacity-60">{p.description}</span>
              </td>
              <td class="p-1">
                {flagged_value(p, @scenario.overrides)} {p.unit}
              </td>
              <td class="p-1">
                <span class={[
                  "badge badge-sm",
                  if(p.status == :placeholder, do: "badge-error", else: "badge-warning")
                ]}>
                  {p.status |> Atom.to_string() |> String.upcase()}
                </span>
              </td>
              <td class="p-1 opacity-80">{p.notes}</td>
            </tr>
          </tbody>
        </table>
        <div class="font-semibold">Model limits</div>
        <ol class="list-decimal ml-6">
          <li :for={l <- @limits}>{l}</li>
        </ol>
      </div>
    </details>
    """
  end

  attr :title, :string, required: true
  attr :weeks, :list, required: true
  attr :key, :atom, required: true
  attr :guide, :boolean, default: true
  attr :series, :list, default: nil

  @doc false
  def chart(assigns) do
    series =
      assigns.series ||
        [
          %{
            name: "Model",
            class: "stroke-primary",
            dashed: false,
            points: points(assigns.weeks, &Map.get(&1, assigns.key))
          }
        ] ++
          if(assigns.guide,
            do: [
              %{
                name: "Hisex guide",
                class: "stroke-base-content",
                dashed: true,
                points: points(assigns.weeks, &Map.get(&1.guide, assigns.key))
              }
            ],
            else: []
          )

    assigns = assign(assigns, svg: svg_paths(series), series: series)

    ~H"""
    <div class="border border-base-300 rounded-lg p-2">
      <div class="text-xs font-semibold flex justify-between">
        <span>{@title}</span>
        <span class="opacity-60">{fmt(@svg.y_min, 1)} – {fmt(@svg.y_max, 1)}</span>
      </div>
      <svg viewBox="0 0 300 120" class="w-full h-32">
        <path
          :for={p <- @svg.paths}
          d={p.d}
          fill="none"
          class={p.class}
          stroke-width="1.5"
          stroke-dasharray={if p.dashed, do: "4 3"}
          opacity={if p.dashed, do: "0.5"}
        />
      </svg>
      <div class="text-[10px] opacity-60 flex justify-between">
        <span>wk {@svg.x_min}</span>
        <span :for={s <- @series}>{if s.dashed, do: "- - ", else: "— "}{s.name}</span>
        <span>wk {@svg.x_max}</span>
      </div>
    </div>
    """
  end

  defp points(weeks, f),
    do: weeks |> Enum.map(&{&1.week, f.(&1)}) |> Enum.filter(&is_number(elem(&1, 1)))

  defp svg_paths(series) do
    all = Enum.flat_map(series, & &1.points)

    if all == [] do
      %{paths: [], y_min: nil, y_max: nil, x_min: nil, x_max: nil}
    else
      {x_min, x_max} = all |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
      {y_min, y_max} = all |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
      pad = max((y_max - y_min) * 0.05, 1.0e-6)
      {lo, hi} = {y_min - pad, y_max + pad}
      sx = fn x -> if x_max == x_min, do: 150.0, else: (x - x_min) / (x_max - x_min) * 296 + 2 end
      sy = fn y -> 118 - (y - lo) / (hi - lo) * 116 end

      paths =
        Enum.map(series, fn s ->
          d =
            s.points
            |> Enum.with_index()
            |> Enum.map_join(" ", fn {{x, y}, i} ->
              "#{if i == 0, do: "M", else: "L"}#{Float.round(sx.(x) * 1.0, 1)},#{Float.round(sy.(y) * 1.0, 1)}"
            end)

          %{d: d, class: s.class, dashed: s.dashed}
        end)

      %{paths: paths, y_min: y_min, y_max: y_max, x_min: x_min, x_max: x_max}
    end
  end

  # --- compare results

  attr :results, :list, required: true

  defp compare_results(assigns) do
    colors = ["stroke-primary", "stroke-secondary", "stroke-accent", "stroke-error"]

    series_for = fn key ->
      assigns.results
      |> Enum.with_index()
      |> Enum.map(fn {r, i} ->
        %{
          name: r.name,
          class: Enum.at(colors, i),
          dashed: false,
          points: points(r.result.weeks, &Map.get(&1, key))
        }
      end)
    end

    assigns =
      assign(assigns,
        rows: HenModel.compare_rows(assigns.results),
        lay_series: series_for.(:lay),
        mass_series: series_for.(:egg_mass),
        margin_series: series_for.(:margin_per_1000_week),
        first: hd(assigns.results).result
      )

    ~H"""
    <div id="compare-results" class="mt-4">
      <div class="overflow-x-auto">
        <table class="w-full text-sm border-collapse" id="compare-table">
          <thead>
            <tr class="bg-primary text-primary-content">
              <th class="text-left p-2 w-[28%]">Metric</th>
              <th :for={r <- @results} class="text-left p-2">{r.name}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="border-b border-base-200">
              <td class="p-2 font-medium">{row.label}</td>
              <%= for {{v, d}, idx} <- Enum.with_index(Enum.zip(row.values, row.deltas)) do %>
                <td class={["p-2", idx > 0 && is_number(d) && abs(d) > 1.0e-9 && "bg-warning/20"]}>
                  {fmt(v, row.decimals) || "—"}
                  <span :if={idx > 0 && is_number(d)} class="text-xs opacity-70">
                    (Δ {signed(d, row.decimals)})
                  </span>
                </td>
              <% end %>
            </tr>
          </tbody>
        </table>
      </div>
      <div :if={length(hd(@results).result.weeks) > 1} class="grid grid-cols-3 gap-3 my-3">
        <.chart title="Lay %" weeks={[]} key={:lay} series={@lay_series} />
        <.chart title="Egg mass (g/d)" weeks={[]} key={:egg_mass} series={@mass_series} />
        <.chart title="Margin / 1000 hens / wk" weeks={[]} key={:margin} series={@margin_series} />
      </div>
      <.diet_panel diets={Enum.flat_map(@results, & &1.result.diets)} />
      <.assumptions_panel scenario={@first.scenario} km={@first.km} />
    </div>
    """
  end

  # ---------------------------------------------------------------- events

  @impl true
  def handle_event("update_targets", params, socket) do
    targets =
      socket.assigns.targets
      |> update_target(params, "basis", :basis, &if(&1 in ["legacy", "hisex"], do: &1))
      |> update_target(params, "breed", :breed, & &1)
      |> update_target(params, "housing", :housing, & &1)
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

  def handle_event("generate_specs", _, socket) do
    user_nutrients = load_user_nutrients(socket.assigns.current_user.id)
    t = socket.assigns.targets

    specs =
      case t.basis do
        "hisex" ->
          HenModel.spec_for(
            %{
              age_weeks: min(max(div(t.age_weeks_min + t.age_weeks_max, 2), 18), 100),
              temp_c: (t.temp_min + t.temp_max) / 2.0,
              intake_g: (t.consumption_min + t.consumption_max) / 2.0,
              housing: if(t.housing == "floor", do: :barn, else: :cage)
            },
            user_nutrients
          )

        _ ->
          EfcPredict.compute_nutrient_specs(t, user_nutrients)
      end

    {:noreply,
     socket
     |> assign(nutrient_specs: specs)
     |> put_flash(:info, "Generated #{length(specs)} nutrient specs")}
  end

  def handle_event("toggle_nutrient_used", %{"id" => id}, socket) do
    int_id = String.to_integer(id)

    specs =
      Enum.map(socket.assigns.nutrient_specs, fn s ->
        if s.nutrient_id == int_id, do: %{s | used: !s.used}, else: s
      end)

    {:noreply, assign(socket, nutrient_specs: specs)}
  end

  def handle_event(
        "update_nutrient_spec",
        %{"id" => id, "value" => value, "field" => field},
        socket
      )
      when field in ["min", "max"] do
    int_id = String.to_integer(id)
    parsed = parse_float_val(value)

    specs =
      Enum.map(socket.assigns.nutrient_specs, fn s ->
        if s.nutrient_id == int_id,
          do: Map.put(s, String.to_existing_atom(field), parsed),
          else: s
      end)

    {:noreply, assign(socket, nutrient_specs: specs)}
  end

  def handle_event("save_as_formula", _, socket) do
    targets = socket.assigns.targets
    age_mid = div(targets.age_weeks_min + targets.age_weeks_max, 2)
    prefix = if targets.basis == "hisex", do: "Hisex Brown", else: "EFC #{targets.breed}"

    formula_attrs = %{
      "name" => "#{prefix} #{age_mid}wk #{targets.egg_weight_min}-#{targets.egg_weight_max}g",
      "batch_size" => "1000",
      "weight_unit" => "kg",
      "usage_per_day" => "0",
      "note" =>
        "#{if targets.basis == "hisex", do: "Hisex Brown model", else: "EFC"} generated: age #{targets.age_weeks_min}-#{targets.age_weeks_max}wk, #{targets.temp_min}-#{targets.temp_max}°C, egg #{targets.egg_weight_min}-#{targets.egg_weight_max}g",
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

  def handle_event("sim_change", %{"sim" => sim}, socket) do
    {:noreply, assign(socket, sim: merge_sim(socket.assigns.sim, sim))}
  end

  def handle_event("sim_change", _params, socket), do: {:noreply, socket}

  def handle_event("sim_run", params, socket) do
    sim = merge_sim(socket.assigns.sim, Map.get(params, "sim", %{}))
    socket = assign(socket, sim: sim)

    with {:ok, attrs} <- scenario_attrs(sim),
         {:ok, programme} <- programme(sim),
         {:ok, result} <- HenModel.simulate(socket.assigns.current_user.id, programme, attrs) do
      {:noreply, assign(socket, sim_result: result, sim_error: nil)}
    else
      {:error, msg} -> {:noreply, assign(socket, sim_result: nil, sim_error: msg)}
    end
  end

  def handle_event("compare_change", params, socket) do
    ids =
      params
      |> Map.get("compare_ids", [])
      |> Enum.map(&parse_int/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(@max_compare)

    sim = merge_sim(socket.assigns.sim, Map.get(params, "sim", %{}))
    {:noreply, assign(socket, compare_ids: ids, sim: sim)}
  end

  def handle_event("compare_run", params, socket) do
    ids =
      params
      |> Map.get("compare_ids", Enum.map(socket.assigns.compare_ids, &to_string/1))
      |> Enum.map(&parse_int/1)
      |> Enum.reject(&is_nil/1)

    sim = merge_sim(socket.assigns.sim, Map.get(params, "sim", %{}))
    socket = assign(socket, sim: sim, compare_ids: Enum.take(ids, @max_compare))

    with {:ok, attrs} <- scenario_attrs(sim),
         {:ok, results} <- HenModel.compare(socket.assigns.current_user.id, ids, attrs) do
      {:noreply, assign(socket, compare_results: results, compare_error: nil)}
    else
      {:error, msg} -> {:noreply, assign(socket, compare_results: nil, compare_error: msg)}
    end
  end

  # ---------------------------------------------------------------- scenario parsing

  defp default_sim_params do
    %{
      "mode" => "cycle",
      "start_week" => "18",
      "end_week" => "100",
      "snapshot_week" => "30",
      "temp_c" => fmt(Params.value("scenario_temp_mean_c"), 1),
      "temp_max_c" => "",
      "feather" => fmt(Params.value("scenario_feather_score"), 2),
      "housing" => "cage",
      "hens_housed" => "1000",
      "feed_price" => "",
      "egg_pricing" => "per_kg",
      "egg_price" => "",
      "grade_bands" => "",
      "edition" => "sea",
      "energy_scaling" => "guide_anchored",
      "anchor_ref_temp" => fmt(Params.value("guide_anchor_ref_temp"), 1),
      "energy_equation" => "sakomura",
      "lambda" => fmt(Params.value("intake_aa_drive_lambda"), 2),
      "headroom" => fmt(Params.value("intake_cap_headroom"), 2),
      "route" => "auto",
      "heat_egg_weight" => "intake",
      "aa_maint_set" => "a",
      "energy_limit" => "flock",
      "sigma_e" => fmt(Params.value("geno_sigma_emax"), 2),
      "coarse_share" => "",
      "prog" =>
        Map.new(0..(@max_programme - 1), fn i ->
          {"#{i}", %{"formula_id" => "", "from_week" => ""}}
        end)
    }
  end

  defp merge_sim(old, new) do
    prog =
      Map.merge(old["prog"], Map.get(new, "prog", %{}), fn _k, a, b -> Map.merge(a, b) end)
      |> Map.take(Enum.map(0..(@max_programme - 1), &"#{&1}"))

    old |> Map.merge(Map.take(new, Map.keys(old))) |> Map.put("prog", prog)
  end

  defp choice(sim, key) do
    atoms = Map.fetch!(@choice_atoms, key)
    Map.get(atoms, sim[key], Map.fetch!(atoms, hd(@choices[key])))
  end

  @doc false
  def scenario_attrs(sim) do
    num = fn key -> parse_float_val(sim[key]) end

    overrides =
      for {field, pid} <- @override_fields,
          v = num.(field),
          is_number(v),
          v != Params.value(pid),
          into: %{},
          do: {pid, v}

    pricing =
      case choice(sim, "egg_pricing") do
        :per_kg ->
          {:ok, {:per_kg, num.("egg_price")}}

        :per_egg ->
          case Economics.parse_bands(sim["grade_bands"] || "") do
            {:ok, []} -> {:error, "Enter at least one grade band for per-egg pricing"}
            {:ok, bands} -> {:ok, {:per_egg, bands}}
            err -> err
          end
      end

    with {:ok, egg_pricing} <- pricing do
      {:ok,
       %{
         mode: choice(sim, "mode"),
         start_week: int(sim["start_week"], 18),
         end_week: int(sim["end_week"], 100),
         snapshot_week: sim["snapshot_week"] |> int(30) |> max(18) |> min(100),
         temp_c: num.("temp_c"),
         temp_max_c: num.("temp_max_c"),
         feather: num.("feather"),
         housing: choice(sim, "housing"),
         hens_housed: int(sim["hens_housed"], 1000),
         edition: choice(sim, "edition"),
         feed_price_per_kg: num.("feed_price"),
         egg_pricing: egg_pricing,
         coarse_limestone_share: num.("coarse_share"),
         energy_equation: choice(sim, "energy_equation"),
         energy_scaling: choice(sim, "energy_scaling"),
         anchor_ref_temp: num.("anchor_ref_temp"),
         aa_maint_set: choice(sim, "aa_maint_set"),
         heat_egg_weight: choice(sim, "heat_egg_weight"),
         energy_limit: choice(sim, "energy_limit"),
         digestibility: choice(sim, "route"),
         overrides: overrides
       }}
    end
  end

  defp programme(sim) do
    start = int(sim["start_week"], 18)

    rows =
      for i <- 0..(@max_programme - 1),
          row = sim["prog"]["#{i}"],
          row["formula_id"] not in [nil, ""] do
        %{
          from_week: if(i == 0, do: start, else: int(row["from_week"], nil)),
          formula_id: row["formula_id"]
        }
      end

    cond do
      rows == [] or (sim["prog"]["0"]["formula_id"] || "") == "" ->
        {:error, "Choose a formula"}

      Enum.any?(rows, &is_nil(&1.from_week)) ->
        {:error, "Each extra programme row needs a from-week"}

      true ->
        {:ok, rows}
    end
  end

  # ---------------------------------------------------------------- helpers

  defp approximate?(d),
    do: Enum.any?(Map.values(d.aa_routes), &(&1 in [:b, :d])) or d.unmapped != []

  defp flagged_value(p, overrides) do
    case Map.fetch(overrides, p.id) do
      {:ok, v} -> "#{v} (yours; file: #{p.raw})"
      :error -> if p.raw in [nil, ""], do: "(blank → off)", else: p.raw
    end
  end

  defp limiting_text(w) do
    w.limiting
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.take(2)
    |> Enum.map_join(", ", fn {k, share} -> "#{limiting_label(k)} #{round(share * 100)}%" end)
  end

  defp limiting_label(:potential), do: "none (at potential)"
  defp limiting_label(:energy), do: "energy"
  defp limiting_label(aa), do: AminoAcids.label(aa)

  defp fmt(nil, _), do: nil
  defp fmt(v, 0) when is_number(v), do: v |> round() |> Integer.to_string()
  defp fmt(v, d) when is_number(v), do: :erlang.float_to_binary(v * 1.0, decimals: d)

  defp signed(v, d), do: if(v >= 0, do: "+", else: "") <> fmt(v, d)

  defp int(nil, default), do: default

  defp int(v, default) do
    case Integer.parse(to_string(v)) do
      {i, _} -> i
      :error -> default
    end
  end

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
      nil ->
        targets

      "" ->
        targets

      val ->
        parsed = parser.(val)
        if parsed, do: Map.put(targets, field, parsed), else: targets
    end
  end

  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(val) do
    case Integer.parse(to_string(val)) do
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
