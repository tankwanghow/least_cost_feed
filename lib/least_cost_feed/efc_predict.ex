defmodule LeastCostFeed.EfcPredict do
  @moduledoc """
  EFC Prediction Model — predicts laying hen egg output from dietary nutrient profiles.

  All amino acid values are on a TOTAL basis (matching the ingredient database).
  Internally, a 0.85 digestibility factor is applied when feeding into dose-response
  equations that were published using digestible amino acid intakes.

  Nutrient specs are derived from breed supplier guides (Hy-Line, Lohmann, Novogen)
  with digestible AA requirements converted to total basis.

  Sources: NRC 1994, Peguri & Coon 1991, Harms & Russell 1993,
           Azzam et al. 2011, Liu et al. 2005, breed guide data.
  """

  # Assumed digestibility coefficient for converting total → digestible AA
  @digestibility 0.85

  # Breed supplier nutrient specs by phase (from breed_nutrients.csv, economic targets)
  # Each entry: {age_max, %{digestible mg/day requirements + other specs}}
  @breed_specs %{
    "brown" => [
      {32, %{me: 2800, cp: 17.80, lys: 830, met: 415, mc: 747, thr: 581, trp: 178,
             ile: 664, val: 730, arg: 863, ca: 4.00, ap: 0.43, na: 0.18, cl: 0.18, la: 1.60}},
      {50, %{me: 2750, cp: 16.00, lys: 810, met: 405, mc: 729, thr: 567, trp: 174,
             ile: 648, val: 713, arg: 842, ca: 4.20, ap: 0.37, na: 0.15, cl: 0.15, la: 1.36}},
      {65, %{me: 2750, cp: 15.18, lys: 780, met: 390, mc: 702, thr: 546, trp: 168,
             ile: 624, val: 686, arg: 811, ca: 4.40, ap: 0.34, na: 0.15, cl: 0.15, la: 1.27}},
      {80, %{me: 2750, cp: 14.82, lys: 745, met: 373, mc: 671, thr: 522, trp: 160,
             ile: 596, val: 656, arg: 775, ca: 4.60, ap: 0.32, na: 0.15, cl: 0.15, la: 1.27}},
      {999, %{me: 2750, cp: 14.09, lys: 700, met: 350, mc: 630, thr: 490, trp: 151,
              ile: 560, val: 616, arg: 728, ca: 4.70, ap: 0.29, na: 0.15, cl: 0.15, la: 1.27}}
    ],
    "white" => [
      {50, %{me: 2725, cp: 18.00, lys: 800, met: 400, mc: 720, thr: 560, trp: 180,
             ile: 640, val: 700, arg: 830, ca: 4.10, ap: 0.42, na: 0.18, cl: 0.18, la: 2.00}},
      {70, %{me: 2725, cp: 17.50, lys: 780, met: 390, mc: 700, thr: 550, trp: 170,
             ile: 620, val: 680, arg: 810, ca: 4.40, ap: 0.40, na: 0.18, cl: 0.18, la: 1.60}},
      {999, %{me: 2725, cp: 16.80, lys: 740, met: 370, mc: 670, thr: 520, trp: 160,
              ile: 590, val: 650, arg: 770, ca: 4.50, ap: 0.38, na: 0.18, cl: 0.18, la: 1.30}}
    ]
  }

  defstruct diet: %{},
            bird: %{},
            feed_intake_g_day: 0.0,
            egg_weight_g: 0.0,
            egg_production_pct: 0.0,
            egg_mass_g_day: 0.0,
            fcr: 0.0,
            me_intake_kcal_day: 0.0,
            lysine_intake_mg: 0.0,
            methionine_intake_mg: 0.0,
            met_cys_intake_mg: 0.0,
            threonine_intake_mg: 0.0,
            tryptophan_intake_mg: 0.0

  @default_bird %{
    age_weeks: 30,
    body_weight_kg: 1.90,
    body_weight_change_g_day: 1.0,
    temperature_c: 24.0,
    breed: "brown",
    housing: "cage"
  }

  @doc """
  Predict egg output from a formula's nutrient actuals (all on TOTAL basis).

  `nutrient_map` is a map of %{nutrient_name => actual_value} extracted
  from the formula's formula_nutrients after optimization.

  `bird_params` overrides default bird state (optional).

  Returns an `%EfcPredict{}` struct with all predictions.
  """
  def predict(nutrient_map, bird_params \\ %{}) do
    bird = Map.merge(@default_bird, bird_params)
    diet = extract_diet(nutrient_map)

    # Iterative solve: feed intake depends on egg mass, egg mass depends on feed intake
    egg_mass_est = iterate(diet, bird, 55.0, 10)

    fi = predict_feed_intake(bird, diet, egg_mass_est)
    ew = predict_egg_weight(bird, diet, fi)
    ep = predict_egg_production(bird, diet, fi)
    em = ew * ep / 100.0

    %__MODULE__{
      diet: diet,
      bird: bird,
      feed_intake_g_day: Float.round(fi, 1),
      egg_weight_g: Float.round(ew, 1),
      egg_production_pct: Float.round(ep, 1),
      egg_mass_g_day: Float.round(em, 1),
      fcr: if(em > 0, do: Float.round(fi / em, 3), else: 0.0),
      me_intake_kcal_day: Float.round(fi * diet.me_kcal_kg / 1000.0, 1),
      lysine_intake_mg: Float.round(diet.lysine_pct / 100.0 * fi * 1000.0, 0),
      methionine_intake_mg: Float.round(diet.methionine_pct / 100.0 * fi * 1000.0, 0),
      met_cys_intake_mg: Float.round(diet.met_cys_pct / 100.0 * fi * 1000.0, 0),
      threonine_intake_mg: Float.round(diet.threonine_pct / 100.0 * fi * 1000.0, 0),
      tryptophan_intake_mg: Float.round(diet.tryptophan_pct / 100.0 * fi * 1000.0, 0)
    }
  end

  @doc """
  Extract a nutrient map from a formula changeset's formula_nutrients.
  Returns %{nutrient_name => actual_value}.
  """
  def nutrient_map_from_changeset(changeset) do
    changeset
    |> Ecto.Changeset.get_assoc(:formula_nutrients)
    |> Enum.reject(fn cs -> Ecto.Changeset.get_field(cs, :delete) end)
    |> Enum.map(fn cs ->
      {Ecto.Changeset.get_field(cs, :nutrient_name), Ecto.Changeset.get_field(cs, :actual)}
    end)
    |> Map.new()
  end

  @doc """
  Compute nutrient specs (min/max) needed to achieve target egg output.
  All amino acid specs are on TOTAL basis (matching the ingredient database).
  Values are derived from breed supplier guides.
  """
  def compute_nutrient_specs(targets, user_nutrients) do
    age = div(targets.age_weeks_min + targets.age_weeks_max, 2)
    target_fi = (targets.consumption_min + targets.consumption_max) / 2.0
    temp = (targets.temp_min + targets.temp_max) / 2.0
    breed = targets.breed

    # Look up breed-specific requirements for this age
    phase = get_breed_phase(breed, age)

    # ME: from breed guide (kcal/kg), convert to kcal/g for DB unit
    me_kcal_g = phase.me / 1000.0

    # Adjust ME for temperature stress
    me_adj = if temp > 25.0, do: me_kcal_g * (1.0 + 0.005 * (temp - 25.0)), else: me_kcal_g

    # CP from breed guide
    cp_pct = phase.cp

    # Convert digestible AA mg/day → total % of diet
    # total_pct = dig_mg / digestibility / (feed_intake_g * 10)
    lys_total_pct = phase.lys / @digestibility / (target_fi * 10.0)
    met_total_pct = phase.met / @digestibility / (target_fi * 10.0)
    mc_total_pct = phase.mc / @digestibility / (target_fi * 10.0)
    thr_total_pct = phase.thr / @digestibility / (target_fi * 10.0)
    trp_total_pct = phase.trp / @digestibility / (target_fi * 10.0)
    ile_total_pct = phase.ile / @digestibility / (target_fi * 10.0)
    val_total_pct = phase.val / @digestibility / (target_fi * 10.0)
    arg_total_pct = phase.arg / @digestibility / (target_fi * 10.0)

    # Minerals/other from breed guide (already in % or direct units)
    ca_pct = phase.ca
    ap_pct = phase.ap
    na_pct = phase.na
    cl_pct = phase.cl
    la_pct = phase.la

    # Potassium: NRC 0.15% min, typically 0.5-0.7% in practical diets
    # Daily ~650 mg, scale with feed intake
    k_pct = 650.0 / (target_fi * 10.0)

    # Choline: NRC 1300 mg/day for layers, DB unit is mg/g
    choline_mg_g = 1300.0 / target_fi

    # Crude fiber max (gut fill limit)
    cf_max_pct = if target_fi < 100.0, do: 4.0, else: 5.0

    # Ether extract / crude fat
    ee_min_pct = 2.5
    ee_max_pct = 7.0

    # Phytate phosphorus max: ~250 mg/day
    phytate_p_max_pct = 250.0 / (target_fi * 10.0)

    # Build nutrient spec list with 5% safety margin on minimums
    spec_definitions = [
      {["Metab. Energy Poultry", "Metab. Energy"],
       Float.round(me_adj * 0.98, 4), Float.round(me_adj * 1.05, 4)},
      {["Crude Protein"], Float.round(cp_pct * 0.95, 2), nil},
      {["Lysine"], Float.round(lys_total_pct * 0.95, 4), nil},
      {["Methionine"], Float.round(met_total_pct * 0.95, 4), nil},
      {["Met + Cys"], Float.round(mc_total_pct * 0.95, 4), nil},
      {["Threonine"], Float.round(thr_total_pct * 0.95, 4), nil},
      {["Tryptophan"], Float.round(trp_total_pct * 0.95, 4), nil},
      {["Arginine"], Float.round(arg_total_pct * 0.95, 4), nil},
      {["Isoleucine"], Float.round(ile_total_pct * 0.95, 4), nil},
      {["Valine"], Float.round(val_total_pct * 0.95, 4), nil},
      {["Calcium"], Float.round(ca_pct * 0.95, 2), Float.round(ca_pct * 1.10, 2)},
      {["Avail. Phos"], Float.round(ap_pct * 0.90, 2), Float.round(ap_pct * 1.20, 2)},
      {["Phytate Phos"], nil, Float.round(phytate_p_max_pct, 4)},
      {["Linoleic Acid"], Float.round(la_pct, 2), nil},
      {["Crude Fiber"], nil, Float.round(cf_max_pct, 2)},
      {["Ether extract", "Ether Extract"], Float.round(ee_min_pct, 2), Float.round(ee_max_pct, 2)},
      {["Sodium"], Float.round(na_pct * 0.90, 2), Float.round(na_pct * 1.30, 2)},
      {["Chlorine"], Float.round(cl_pct * 0.90, 2), Float.round(cl_pct * 1.30, 2)},
      {["Potassium"], Float.round(k_pct * 0.90, 2), Float.round(k_pct * 1.30, 2)},
      {["Choline"], Float.round(choline_mg_g * 0.90, 2), nil}
    ]

    Enum.flat_map(spec_definitions, fn {patterns, min_val, max_val} ->
      case find_total_nutrient(user_nutrients, patterns) do
        nil -> []
        nutrient ->
          [%{
            nutrient_id: nutrient.id,
            nutrient_name: nutrient.name,
            nutrient_unit: nutrient.unit,
            min: min_val,
            max: max_val,
            actual: 0.0,
            shadow: 0.0,
            used: true
          }]
      end
    end)
  end

  @doc """
  Predict daily ME requirement (kcal/day).
  Composite equation from NRC 1994 / Sakomura 2005.
  """
  def predict_me_requirement(bird, egg_mass_g_day) do
    w_m = if bird.housing == "cage", do: 110.0, else: 120.0
    metabolic_bw = :math.pow(bird.body_weight_kg, 0.75)
    me_maint = w_m * metabolic_bw
    me_egg = 2.07 * egg_mass_g_day
    me_gain = 5.24 * max(bird.body_weight_change_g_day, 0)

    me_temp =
      cond do
        bird.temperature_c < 21.0 ->
          4.69 * (21.0 - bird.temperature_c) * metabolic_bw

        bird.temperature_c > 25.0 ->
          heat_reduction = 0.015 * (bird.temperature_c - 25.0)
          -(me_maint + me_egg + me_gain) * heat_reduction

        true ->
          0.0
      end

    me_maint + me_egg + me_gain + me_temp
  end

  # --- Private ---

  defp iterate(_diet, _bird, est, 0), do: est

  defp iterate(diet, bird, est, remaining) do
    fi = predict_feed_intake(bird, diet, est)
    ew = predict_egg_weight(bird, diet, fi)
    ep = predict_egg_production(bird, diet, fi)
    em = ew * ep / 100.0

    if abs(em - est) < 0.01 do
      em
    else
      iterate(diet, bird, em, remaining - 1)
    end
  end

  # Extract total-basis nutrients from nutrient_map (DB names).
  # Excludes "Dig." prefixed nutrients to avoid matching digestible variants.
  defp extract_diet(nutrient_map) do
    get = fn patterns, default ->
      Enum.find_value(patterns, default, fn pattern ->
        Enum.find_value(nutrient_map, nil, fn {name, val} ->
          name_lower = String.downcase(name)
          pat_lower = String.downcase(pattern)

          if String.contains?(name_lower, pat_lower) and
               not String.contains?(name_lower, "dig.") and
               is_number(val) and val > 0,
             do: val
        end)
      end)
    end

    # ME is in kcal/g in the DB, convert to kcal/kg
    me_raw = get.(["Metab. Energy Poultry", "Metab. Energy"], 2.80)
    me_kcal_kg = if me_raw < 10, do: me_raw * 1000, else: me_raw

    %{
      me_kcal_kg: me_kcal_kg,
      cp_pct: get.(["Crude Protein"], 16.5),
      lysine_pct: get.(["Lysine"], 0.85),
      methionine_pct: get.(["Methionine"], 0.38),
      met_cys_pct: get.(["Met + Cys"], 0.68),
      threonine_pct: get.(["Threonine"], 0.62),
      tryptophan_pct: get.(["Tryptophan"], 0.19),
      calcium_pct: get.(["Calcium"], 4.10),
      linoleic_acid_pct: get.(["Linoleic Acid"], 1.50),
      choline_mg_g: get.(["Choline"], 1.1)
    }
  end

  # Look up the breed phase spec for a given age
  defp get_breed_phase(breed, age) do
    phases = Map.get(@breed_specs, breed, @breed_specs["brown"])

    Enum.find_value(phases, elem(List.last(phases), 1), fn {age_max, spec} ->
      if age <= age_max, do: spec
    end)
  end

  defp predict_feed_intake(bird, diet, egg_mass_g_day) do
    me_req = predict_me_requirement(bird, egg_mass_g_day)
    me_density = diet.me_kcal_kg / 1000.0
    fi = me_req / me_density

    {lo, hi} = if bird.breed == "white", do: {85.0, 120.0}, else: {95.0, 135.0}
    max(lo, min(fi, hi))
  end

  defp predict_egg_weight(bird, diet, feed_intake_g) do
    # Total intakes in mg/day
    met_total_mg = diet.methionine_pct / 100.0 * feed_intake_g * 1000.0
    mc_total_mg = diet.met_cys_pct / 100.0 * feed_intake_g * 1000.0
    lys_total_mg = diet.lysine_pct / 100.0 * feed_intake_g * 1000.0

    # Convert to digestible for dose-response equations
    met_dig_mg = met_total_mg * @digestibility
    mc_dig_mg = mc_total_mg * @digestibility
    lys_dig_mg = lys_total_mg * @digestibility

    # Age-based egg weight curve
    age_ew =
      if bird.breed == "white" do
        44.0 + 22.0 * (1.0 - :math.exp(-0.08 * (bird.age_weeks - 18)))
      else
        45.0 + 23.0 * (1.0 - :math.exp(-0.07 * (bird.age_weeks - 18)))
      end

    # Methionine response: Harms & Russell 1993 (digestible basis)
    met_potential = 64.2 - 38.7 * :math.exp(-0.0078 * met_dig_mg)
    met_ref = 64.2 - 38.7 * :math.exp(-0.0078 * 400.0)
    met_effect = met_potential - met_ref

    # M+C response: Liu et al. 2005 (digestible basis)
    mc_potential = 47.8 + 0.0394 * mc_dig_mg - 0.0000285 * mc_dig_mg * mc_dig_mg
    mc_ref = 47.8 + 0.0394 * 700.0 - 0.0000285 * 700.0 * 700.0
    mc_effect = mc_potential - mc_ref

    # Lysine effect (digestible basis)
    lys_effect = 0.01 * max(lys_dig_mg - 700.0, -200.0)

    # ME effect: +1g per +100 kcal/kg above 2750
    me_effect = (diet.me_kcal_kg - 2750.0) / 100.0 * 1.0

    # Linoleic acid effect
    la_effect =
      cond do
        diet.linoleic_acid_pct < 0.8 -> -2.0
        diet.linoleic_acid_pct < 1.15 -> -1.0 * (1.15 - diet.linoleic_acid_pct) / 0.35
        true -> 0.0
      end

    nutrient_delta = (met_effect + mc_effect) / 2.0 + lys_effect + me_effect * 0.5 + la_effect
    max(40.0, min(age_ew + nutrient_delta, 72.0))
  end

  defp predict_egg_production(bird, diet, feed_intake_g) do
    age = bird.age_weeks

    base_prod =
      cond do
        age < 20 -> max(0.0, (age - 18) * 25.0)
        age < 24 -> 50.0 + (age - 20) * 12.0
        age < 30 -> if(bird.breed == "white", do: 96.0, else: 95.5)
        true ->
          decline = if(bird.breed == "white", do: 0.22, else: 0.20)
          if(bird.breed == "white", do: 96.0, else: 95.5) - decline * (age - 30)
      end
      |> max(0.0)
      |> min(98.0)

    # Total AA intakes in mg/day, convert to digestible for penalty thresholds
    lys_dig_mg = diet.lysine_pct / 100.0 * feed_intake_g * 1000.0 * @digestibility
    thr_dig_mg = diet.threonine_pct / 100.0 * feed_intake_g * 1000.0 * @digestibility
    trp_dig_mg = diet.tryptophan_pct / 100.0 * feed_intake_g * 1000.0 * @digestibility

    lys_penalty =
      cond do
        lys_dig_mg < 600 -> (600 - lys_dig_mg) / 100.0 * 3.0
        lys_dig_mg < 700 -> (700 - lys_dig_mg) / 100.0 * 1.0
        true -> 0.0
      end

    thr_penalty =
      cond do
        thr_dig_mg < 400 -> (400 - thr_dig_mg) / 100.0 * 4.0
        thr_dig_mg < 500 -> (500 - thr_dig_mg) / 100.0 * 1.5
        true -> 0.0
      end

    trp_penalty =
      cond do
        trp_dig_mg < 120 -> (120 - trp_dig_mg) / 30.0 * 5.0
        trp_dig_mg < 150 -> (150 - trp_dig_mg) / 30.0 * 2.0
        true -> 0.0
      end

    ca_penalty = if diet.calcium_pct < 3.0, do: (3.0 - diet.calcium_pct) / 0.5 * 3.0, else: 0.0
    cp_penalty = if diet.cp_pct < 13.0, do: (13.0 - diet.cp_pct) / 2.0 * 5.0, else: 0.0

    # Choline: daily intake in mg = mg/g * g_feed. NRC recommends ~1300 mg/day.
    choline_mg_day = diet.choline_mg_g * feed_intake_g

    choline_penalty =
      cond do
        choline_mg_day < 800 -> (800 - choline_mg_day) / 200.0 * 5.0
        choline_mg_day < 1000 -> (1000 - choline_mg_day) / 200.0 * 2.0
        true -> 0.0
      end

    total_penalty = lys_penalty + thr_penalty + trp_penalty + ca_penalty + cp_penalty + choline_penalty
    max(0.0, min(base_prod - total_penalty, 98.5))
  end

  # Find a TOTAL nutrient (excludes "Dig." prefixed names)
  defp find_total_nutrient(user_nutrients, patterns) do
    Enum.find(user_nutrients, fn n ->
      name_lower = String.downcase(n.name)
      not String.contains?(name_lower, "dig.") and
        Enum.any?(patterns, fn pat ->
          String.contains?(name_lower, String.downcase(pat))
        end)
    end)
  end
end
