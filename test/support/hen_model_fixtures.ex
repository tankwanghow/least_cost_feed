defmodule LeastCostFeed.HenModelFixtures do
  @moduledoc """
  Hen-model test diets built only from the Hendrix Table 3 daily
  requirements (S4) and the Hisex guide intake (S2): concentration =
  Hendrix mg/d ÷ mean guide intake over the phase, ME 2800 kcal/kg
  (`guide_anchor_diet_me`), Ca and avP at the band midpoint.
  """

  alias LeastCostFeed.HenModel.{Diet, Genotype, Hendrix, Params, Scenario}

  @phase_weeks %{"L1" => {18, 39}, "L2" => {40, 64}, "L3" => {65, 89}, "L4" => {90, 100}}

  def mean_guide_fi(edition, {from, to}) do
    fis = for wk <- from..to, do: Genotype.guide_week(edition, wk)["feed_g_d"]
    Enum.sum(fis) / length(fis)
  end

  @doc "Hendrix-spec SID diet for a phase (mg/g). `scale` multiplies all SID AAs."
  def hendrix_diet(phase_name, opts \\ []) do
    edition = Keyword.get(opts, :edition, :sea)
    scale = Keyword.get(opts, :aa_scale, 1.0)
    p = Hendrix.phase(phase_name)
    fi = Keyword.get(opts, :formulation_fi, mean_guide_fi(edition, @phase_weeks[phase_name]))
    {ca_lo, ca_hi} = p.ca
    {avp_lo, avp_hi} = p.avp
    ca_factor = Keyword.get(opts, :ca_factor)

    Diet.new(%{
      name: Keyword.get(opts, :name, "Hendrix #{phase_name}"),
      formula_id: Keyword.get(opts, :formula_id, phase_name),
      me: Keyword.get(opts, :me, Params.value("guide_anchor_diet_me") / 1000.0),
      sid: Map.new(p.sid, fn {aa, mg} -> {aa, scale * mg / fi} end),
      total: Map.new(p.total, fn {aa, mg} -> {aa, mg / fi} end),
      ca: if(ca_factor, do: ca_factor * ca_lo / fi, else: (ca_lo + ca_hi) / 2.0 / fi),
      avp: (avp_lo + avp_hi) / 2.0 / fi,
      cost_per_kg: Keyword.get(opts, :cost_per_kg, 2.0)
    })
  end

  @doc "Phase programme L1 18-39, L2 40-64, L3 65-89, L4 90-100."
  def hendrix_programme(opts \\ []) do
    for {name, {from, _}} <- Enum.sort_by(@phase_weeks, fn {_, {f, _}} -> f end),
        do: %{from_week: from, diet: hendrix_diet(name, opts)}
  end

  def scenario(attrs \\ %{}) do
    struct(Scenario, Map.merge(%{programme: hendrix_programme(), temp_c: 25.0}, attrs))
  end

  @doc """
  Creates a user-owned layer formula in the DB (test data only, not model
  coefficients): maize + soybean meal + wheat bran + synthetic Lys/Met +
  limestone/MDCP/oil, with ingredient proportions set (as after "Optimize").
  Returns `%{formula, nutrients, ingredients}`.
  """
  def lcf_layer_formula(user, opts \\ []) do
    alias LeastCostFeed.Entities

    nutrient_specs = [
      {:me, "Metab. Energy Poultry", "kcal/g"},
      {:lys, "Lysine", "%"},
      {:met, "Methionine", "%"},
      {:metcys, "Met + Cys", "%"},
      {:thr, "Threonine", "%"},
      {:trp, "Tryptophan", "%"},
      {:val, "Valine", "%"},
      {:ile, "Isoleucine", "%"},
      {:arg, "Arginine", "%"},
      {:ca, "Calcium", "%"},
      {:avp, "Avail. Phos", "%"}
    ]

    nutrients =
      Keyword.get_lazy(opts, :nutrients, fn ->
        Map.new(nutrient_specs, fn {k, name, unit} ->
          {:ok, n} = Entities.create_nutrient(%{name: name, unit: unit, user_id: user.id})
          {k, n}
        end)
      end)

    # name, cost/kg, proportion, composition
    ingredient_specs = [
      {"Corn Grain", 1.2, 0.60,
       %{
         me: 3.35,
         lys: 0.25,
         met: 0.18,
         metcys: 0.38,
         thr: 0.29,
         trp: 0.06,
         val: 0.40,
         ile: 0.28,
         arg: 0.38,
         avp: 0.08
       }},
      {"SS Soyabean Meal HP", 2.2, 0.25,
       %{
         me: 2.45,
         lys: 2.85,
         met: 0.64,
         metcys: 1.35,
         thr: 1.80,
         trp: 0.62,
         val: 2.20,
         ile: 2.10,
         arg: 3.40,
         ca: 0.3,
         avp: 0.2
       }},
      {"Wheat Bran", 0.9, 0.04,
       %{
         me: 1.30,
         lys: 0.60,
         met: 0.20,
         metcys: 0.50,
         thr: 0.50,
         trp: 0.25,
         val: 0.70,
         ile: 0.45,
         arg: 1.00,
         avp: 0.3
       }},
      {"Limestone", 0.15, 0.085, %{ca: 38.0}},
      {"MDCP21", 3.5, 0.01, %{ca: 16.0, avp: 21.0}},
      {"L-Lysine HCl", 8.0, 0.002, %{lys: 78.8}},
      {"DL-Methionine 99", 12.0, 0.0025, %{met: 99.0, metcys: 99.0}},
      {"Palm Oil", 4.0, 0.0105, %{me: 8.5}}
    ]

    suffix = Keyword.get(opts, :suffix, "")
    scales = Keyword.get(opts, :scales, %{})

    ingredients =
      Keyword.get_lazy(opts, :ingredients, fn ->
        Map.new(ingredient_specs, fn {name, cost, _p, comp} ->
          {:ok, ing} =
            Entities.create_ingredient(%{
              name: name,
              cost: cost,
              dry_matter: 88.0,
              category: "test",
              user_id: user.id,
              ingredient_compositions:
                Enum.map(comp, fn {k, q} -> %{nutrient_id: nutrients[k].id, quantity: q} end)
            })

          {name, ing}
        end)
      end)

    {:ok, formula} =
      Entities.create_formula(%{
        name: Keyword.get(opts, :name, "Layer Test#{suffix}"),
        batch_size: 1000.0,
        weight_unit: "KG",
        usage_per_day: 0.0,
        user_id: user.id,
        formula_ingredients:
          Enum.map(ingredient_specs, fn {name, cost, p, _} ->
            p = p * Map.get(scales, name, 1.0)
            %{ingredient_id: ingredients[name].id, actual: p, cost: cost, used: true}
          end),
        formula_nutrients: [%{nutrient_id: nutrients.lys.id, min: 0.8, used: true}]
      })

    %{formula: formula, nutrients: nutrients, ingredients: ingredients}
  end
end
