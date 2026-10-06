defmodule LeastCostFeed.HenModel.Diet do
  @moduledoc """
  A LeastCostFeed formula translated into model inputs (SPEC 5).

  Concentrations are per g of feed: `me` kcal/g, `sid`/`total` AAs mg/g,
  `ca`/`avp` mg/g; `cp`, `na`, `cl`, `linoleic` in %. Nutrient names are
  matched case-insensitively (exact, whitespace-normalised) against
  `priv/hen_model/nutrient_aliases.csv`, so account-specific names can be
  added without code changes.

  Nutrient values come from Σ ingredient `actual` × composition when the
  formula has ingredient proportions, otherwise from the formula nutrients'
  `actual`. Without either the diet is rejected.
  """

  alias LeastCostFeed.HenModel.{AminoAcids, CSV, Digestibility, Params}

  defstruct formula_id: nil,
            name: nil,
            me: nil,
            cp: nil,
            sid: %{},
            total: %{},
            ca: nil,
            avp: nil,
            na: nil,
            cl: nil,
            linoleic: nil,
            cost_per_kg: nil,
            route: :auto,
            aa_routes: %{},
            unmapped: [],
            source: nil,
            warnings: []

  @alias_file "nutrient_aliases.csv"
  @external_resource CSV.path(@alias_file)

  @aliases CSV.read!(@alias_file)
           |> Map.new(fn r ->
             {r["alias"] |> String.downcase() |> String.split() |> Enum.join(" "),
              {String.to_atom(r["key"]), String.to_atom(r["basis"])}}
           end)

  @doc "`{key, basis}` for a nutrient name (e.g. `{:lys, :sid}`), or nil."
  def classify(name) when is_binary(name),
    do: Map.get(@aliases, name |> String.downcase() |> String.split() |> Enum.join(" "))

  def classify(_), do: nil

  @doc """
  ME in kcal/g from a stored value: kcal/kg is detected from the unit or a
  value above 100.
  """
  def me_kcal_per_g(v, unit \\ nil)
  def me_kcal_per_g(nil, _), do: nil

  def me_kcal_per_g(v, unit) do
    u = String.downcase(unit || "")

    cond do
      String.contains?(u, "kcal/kg") -> v / 1000.0
      v > 100.0 -> v / 1000.0
      true -> v * 1.0
    end
  end

  @doc """
  Builds a diet from a formula preloaded by `Entities.get_formula!/1` and a
  map `nutrient_id => %{name, unit}` of the owner's nutrients.

  Options: `:route` (digestibility route, default `:auto`), `:overrides`.
  Returns `{:ok, %Diet{}}` or `{:error, message}`.
  """
  def from_formula(formula, nutrients_by_id, opts \\ []) do
    ings =
      (formula.formula_ingredients || [])
      |> Enum.filter(&((&1.actual || 0.0) > 0.0))
      |> Enum.map(fn fi ->
        comps =
          case fi.ingredient do
            %{ingredient_compositions: list} when is_list(list) ->
              Map.new(list, &{&1.nutrient_id, &1.quantity || 0.0})

            _ ->
              %{}
          end

        %{
          name: fi.ingredient_name || (fi.ingredient && fi.ingredient.name),
          actual: fi.actual,
          comps: comps
        }
      end)

    ing_sum = Enum.reduce(ings, 0.0, &(&1.actual + &2))

    fn_actuals =
      (formula.formula_nutrients || [])
      |> Enum.filter(&is_number(&1.actual))
      |> Map.new(&{&1.nutrient_id, &1.actual})

    comp_ids = ings |> Enum.flat_map(&Map.keys(&1.comps)) |> MapSet.new()

    {values, source} =
      if ing_sum > 0.0 do
        ids = MapSet.union(comp_ids, MapSet.new(Map.keys(fn_actuals)))

        {Map.new(ids, fn id ->
           if MapSet.member?(comp_ids, id),
             do:
               {id,
                Enum.reduce(ings, 0.0, fn i, acc -> acc + i.actual * Map.get(i.comps, id, 0.0) end)},
             else: {id, fn_actuals[id]}
         end), :ingredients}
      else
        {fn_actuals, :formula_nutrients}
      end

    if values == %{} or Enum.all?(Map.values(values), &(&1 == 0.0)) do
      {:error,
       "Formula \"#{formula.name}\" has no ingredient proportions or nutrient actuals. Optimise it first."}
    else
      named =
        Enum.flat_map(values, fn {id, v} ->
          case nutrients_by_id[id] do
            %{name: name, unit: unit} -> [{classify(name), v, unit}]
            _ -> []
          end
        end)

      ingredient_aa =
        Enum.map(ings, fn i ->
          total =
            Enum.reduce(i.comps, %{}, fn {id, q}, acc ->
              case nutrients_by_id[id] && classify(nutrients_by_id[id].name) do
                {aa, :total} ->
                  if aa in AminoAcids.aas(), do: Map.put(acc, aa, q * 10.0), else: acc

                _ ->
                  acc
              end
            end)

          %{name: i.name, actual: i.actual, total: total}
        end)

      cost = Map.get(formula, :cost)

      diet =
        build(named, ingredient_aa, opts)
        |> Map.merge(%{
          formula_id: formula.id,
          name: formula.name,
          cost_per_kg: if(is_number(cost) and cost > 0, do: cost / 1000.0),
          source: source
        })

      validate(diet)
    end
  end

  @doc """
  Builds a diet from plain values (tests, spec checks):
  `%{name, me (kcal/g), sid: %{aa => mg/g}, total: ..., ca, avp (mg/g), cost_per_kg}`.
  """
  def new(attrs) do
    struct(
      __MODULE__,
      Map.merge(%{route: :given, aa_routes: Map.new(AminoAcids.aas(), &{&1, :given})}, attrs)
    )
  end

  defp build(named, ingredient_aa, opts) do
    route = Keyword.get(opts, :route, :auto)
    ov = Keyword.get(opts, :overrides, %{})

    pick = fn key, basis ->
      Enum.find_value(named, fn
        {{^key, ^basis}, v, unit} -> {v, unit}
        _ -> nil
      end)
    end

    val = fn key, basis ->
      case pick.(key, basis) do
        {v, _} -> v
        nil -> nil
      end
    end

    aa_map = fn basis ->
      Map.new(AminoAcids.aas(), fn aa ->
        case val.(aa, basis) do
          nil -> {aa, nil}
          v -> {aa, v * 10.0}
        end
      end)
    end

    total = aa_map.(:total)

    dig =
      Digestibility.compute(
        route,
        %{total: total, sid: aa_map.(:sid), dig: aa_map.(:dig), ingredients: ingredient_aa},
        ov
      )

    me =
      case pick.(:me, :energy) do
        {v, unit} -> me_kcal_per_g(v, unit)
        nil -> nil
      end

    pct_to_mg = fn v -> v && v * 10.0 end

    warnings =
      dig.warnings ++
        case val.(:linoleic, :total) do
          nil ->
            []

          la ->
            min = Params.value("linoleic_min", ov)

            if la < min,
              do: ["Linoleic acid #{Float.round(la * 1.0, 2)}% is below #{min}% (S4 3.11)"],
              else: []
        end

    %__MODULE__{
      me: me,
      cp: val.(:cp, :total),
      total: total,
      sid: dig.sid,
      ca: pct_to_mg.(val.(:ca, :total)),
      avp: pct_to_mg.(val.(:avp, :total)),
      na: val.(:na, :total),
      cl: val.(:cl, :total),
      linoleic: val.(:linoleic, :total),
      route: route,
      aa_routes: dig.aa_routes,
      unmapped: dig.unmapped,
      warnings: warnings
    }
  end

  defp validate(%__MODULE__{me: me} = d) when not is_number(me) or me <= 0,
    do:
      {:error,
       "Formula \"#{d.name}\" has no ME value (expected a nutrient named e.g. \"Metab. Energy Poultry\")."}

  defp validate(%__MODULE__{} = d) do
    w =
      d.warnings ++
        if(is_nil(d.ca), do: ["No Calcium value: shell-risk Ca checks skipped"], else: []) ++
        if(is_nil(d.avp), do: ["No Avail. Phos value: shell-risk P checks skipped"], else: [])

    {:ok, %{d | warnings: w}}
  end

  @doc "Short label of the digestibility basis actually used, e.g. \"C\" or \"C+D\"."
  def basis_badge(%__MODULE__{aa_routes: routes}) do
    routes
    |> Map.values()
    |> Enum.reject(&(&1 in [:none]))
    |> Enum.uniq()
    |> Enum.map(fn
      :given -> "given"
      r -> r |> to_string() |> String.upcase()
    end)
    |> Enum.sort()
    |> Enum.join("+")
  end
end
