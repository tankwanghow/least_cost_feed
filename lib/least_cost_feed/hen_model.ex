defmodule LeastCostFeed.HenModel do
  @moduledoc """
  Mechanistic (EFG / Reading-model) Hisex Brown laying-hen model, v1.

  Public API (user-scoped; all model maths is pure, no DB writes):

    * `load_diet/3`  - an LCF formula of the user → `%Diet{}`
    * `simulate/3`   - full cycle (or snapshot) for a phase programme
    * `compare/4`    - 2-4 formulas under one shared scenario
    * `spec_for/3`   - nutrient specs (min/max) for the spec generator

  Science and parameter provenance: `priv/hen_model/README.md`,
  `priv/hen_model/parameters.csv`, `priv/hen_model/sources.md`.
  """

  import Ecto.Query, warn: false

  alias LeastCostFeed.{Entities, Repo}
  alias LeastCostFeed.Entities.{Formula, Nutrient}

  alias LeastCostFeed.HenModel.{
    AminoAcids,
    Diet,
    Digestibility,
    Energy,
    Genotype,
    Hendrix,
    Params,
    Scenario,
    Simulator
  }

  @max_compare 4

  @doc "Map `nutrient_id => %{name, unit}` of the user's nutrients."
  def nutrients_by_id(user_id) do
    from(n in Nutrient,
      where: n.user_id == ^user_id,
      select: {n.id, %{id: n.id, name: n.name, unit: n.unit}}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Loads a formula owned by `user_id` as a model diet. Other users' formulas
  are reported as not found. Options: `:route` (digestibility), `:overrides`.
  """
  def load_diet(user_id, formula_id, opts \\ []) do
    id = to_int(formula_id)

    owned? =
      id && Repo.exists?(from(f in Formula, where: f.id == ^id and f.user_id == ^user_id))

    if owned? do
      Diet.from_formula(Entities.get_formula!(id), nutrients_by_id(user_id), opts)
    else
      {:error, "Formula #{formula_id} not found"}
    end
  end

  @doc """
  Runs a scenario for the user. `programme` is `[%{from_week, formula_id}]`
  (or a single formula id); `attrs` are `Scenario` fields.
  """
  def simulate(user_id, programme, attrs \\ %{}) do
    route = Map.get(attrs, :digestibility, :auto)
    ov = Map.get(attrs, :overrides, %{})
    start = Map.get(attrs, :start_week, 18)

    programme =
      if is_list(programme), do: programme, else: [%{from_week: start, formula_id: programme}]

    with {:ok, prog} <- load_programme(user_id, programme, route, ov) do
      Scenario
      |> struct(Map.drop(attrs, [:digestibility]))
      |> Map.put(:programme, prog)
      |> Simulator.run()
    end
  end

  @doc """
  Compares 2-#{@max_compare} formulas, each fed for the whole run, under one
  scenario. Returns `{:ok, [%{formula_id, name, result}]}` in input order.
  """
  def compare(user_id, formula_ids, attrs \\ %{}) do
    ids = formula_ids |> Enum.map(&to_int/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    cond do
      length(ids) < 2 ->
        {:error, "Compare needs 2-#{@max_compare} formulas"}

      length(ids) > @max_compare ->
        {:error, "Compare is limited to #{@max_compare} formulas"}

      true ->
        ids
        |> Task.async_stream(fn id -> {id, simulate(user_id, id, attrs)} end, timeout: 60_000)
        |> Enum.reduce_while({:ok, []}, fn
          {:ok, {id, {:ok, res}}}, {:ok, acc} ->
            {:cont, {:ok, [%{formula_id: id, name: hd(res.diets).name, result: res} | acc]}}

          {:ok, {_id, {:error, msg}}}, _ ->
            {:halt, {:error, msg}}

          {:exit, reason}, _ ->
            {:halt, {:error, "Simulation failed: #{inspect(reason)}"}}
        end)
        |> case do
          {:ok, list} -> {:ok, Enum.reverse(list)}
          err -> err
        end
    end
  end

  @compare_metrics [
    {:eggs_hh, "Eggs / hen housed", 1},
    {:egg_mass_hh_kg, "Egg mass / hen housed (kg)", 2},
    {:avg_lay, "Average lay (%)", 1},
    {:avg_ew, "Average egg weight (g)", 1},
    {:avg_fi, "Average feed intake (g/d)", 1},
    {:fcr, "FCR (kg feed / kg egg)", 3},
    {:bw_end_g, "BW at end (g)", 0},
    {:margin_hh, "Margin / hen housed", 2},
    {:margin_per_1000_week, "Margin / 1000 hens / week", 0},
    {:weeks_moderate, "Weeks at Moderate shell risk", 0},
    {:weeks_high, "Weeks at High shell risk", 0}
  ]

  @doc "Rows `%{key, label, decimals, values, deltas}` (Δ vs the first column) for compare results."
  def compare_rows(results) do
    Enum.map(@compare_metrics, fn {key, label, dec} ->
      values = Enum.map(results, &Map.get(&1.result.summary, key))
      first = hd(values)

      deltas =
        Enum.map(values, fn v -> if is_number(v) and is_number(first), do: v - first end)

      %{key: key, label: label, decimals: dec, values: values, deltas: deltas}
    end)
  end

  @doc """
  Nutrient specs for the spec generator from the hen model (SPEC 6.2):
  SID AA mg/d from `a·E + m·W^0.75` (+ `x`·SD population margin, S9),
  Ca/avP from the Hendrix band of the phase, ME from SPEC 4.2 at the target
  intake. AAs are written to SID nutrients if the account has them,
  otherwise to total nutrients via the Hendrix SID/total ratios (route D).

  `targets`: `%{age_weeks, temp_c, intake_g, housing (:cage), edition (:sea), x (0.0)}`.
  Returns the same list shape as the legacy `EfcPredict.compute_nutrient_specs/2`.
  """
  def spec_for(targets, user_nutrients, ov \\ %{}) do
    edition = Map.get(targets, :edition, :sea)
    wk = targets.age_weeks
    t = 7.0 * wk
    pot = Genotype.potential(edition, t)
    w = pot.bw_g / 1000.0
    fi = targets.intake_g * 1.0
    temp = targets.temp_c * 1.0
    x = Map.get(targets, :x, 0.0)
    eq = :sakomura
    km = Energy.guide_anchor_km(edition, eq, Params.value("guide_anchor_ref_temp", ov), ov)

    me_req =
      Energy.me_req(w, temp, max(pot.wg_tgt, 0.0), pot.emax,
        km: km,
        housing_factor: Energy.housing_factor(Map.get(targets, :housing, :cage), ov),
        feather: Params.value("scenario_feather_score", ov),
        overrides: ov
      )

    req =
      AminoAcids.population_requirement(
        AminoAcids.coefficients(:a, ov),
        pot.emax,
        w,
        x,
        Params.value("geno_sigma_emax", ov),
        Params.value("geno_bw_cv", ov)
      )

    phase = Hendrix.phase_for_week(wk)
    {ca_lo, ca_hi} = phase.ca
    {avp_lo, avp_hi} = phase.avp
    pct = fn mg -> mg / (fi * 10.0) end

    find = fn key, basis ->
      Enum.find(user_nutrients, fn n -> Diet.classify(n.name) == {key, basis} end)
    end

    me_spec =
      case find.(:me, :energy) do
        nil ->
          []

        n ->
          kcal_g = me_req / fi

          v =
            if String.contains?(String.downcase(n.unit || ""), "kg"),
              do: kcal_g * 1000.0,
              else: kcal_g

          [spec(n, Float.round(v, 4), nil)]
      end

    aa_specs =
      Enum.flat_map(AminoAcids.aas(), fn aa ->
        case {find.(aa, :sid), find.(aa, :total)} do
          {%{} = n, _} ->
            [spec(n, Float.round(pct.(req[aa]), 4), nil)]

          {nil, %{} = n} ->
            [spec(n, Float.round(pct.(req[aa] / Digestibility.fallback_ratio(aa, ov)), 4), nil)]

          _ ->
            []
        end
      end)

    mineral_specs =
      [{:ca, ca_lo, ca_hi}, {:avp, avp_lo, avp_hi}]
      |> Enum.flat_map(fn {key, lo, hi} ->
        case find.(key, :total) do
          nil -> []
          n -> [spec(n, Float.round(pct.(lo), 3), Float.round(pct.(hi), 3))]
        end
      end)

    me_spec ++ aa_specs ++ mineral_specs
  end

  defp spec(n, min, max),
    do: %{
      nutrient_id: n.id,
      nutrient_name: n.name,
      nutrient_unit: n.unit,
      min: min,
      max: max,
      actual: 0.0,
      shadow: 0.0,
      used: true
    }

  defp load_programme(user_id, programme, route, ov) do
    programme
    |> Enum.reduce_while({:ok, []}, fn %{from_week: fw, formula_id: fid}, {:ok, acc} ->
      case load_diet(user_id, fid, route: route, overrides: ov) do
        {:ok, diet} -> {:cont, {:ok, [%{from_week: to_int(fw) || 18, diet: diet} | acc]}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, []} -> {:error, "No formula selected"}
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp to_int(_), do: nil
end
