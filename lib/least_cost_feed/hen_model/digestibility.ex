defmodule LeastCostFeed.HenModel.Digestibility do
  @moduledoc """
  Digestible (SID) amino acids of a diet (SPEC 5.3). LCF stores AAs on a
  total basis; routes, selectable per run:

    * `:auto` (default) - A if the account has SID nutrients for that AA,
      otherwise C with D fallback.
    * `:sid_nutrients` (A) - use "SID Lysine"... directly.
    * `:dig_as_sid` (B) - treat "Dig." nutrients as SID.
    * `:dig_afd` (B) - "Dig." nutrients are AFD; converted with the Hendrix
      SID/AFD ratios `afd_to_sid_ratio_*` (DERIVED, S4 Table 3).
    * `:cvb` (C) - per ingredient: `Σ actual_k × totalAA_k × SIDC_k` with
      CVB 2017 coefficients (S16) via `priv/hen_model/ingredient_cvb_map.csv`;
      crystalline AAs at `sid_crystalline_aa` (100 %). Ingredients with AA
      content but no mapping fall back to D for their contribution and are
      listed as unmapped.
    * `:hendrix_ratio` (D) - total × `fallback_sid_ratio_*` (DERIVED, S4).

  Whenever a requested route lacks data for an AA, that AA falls back to D
  and a warning is added.
  """

  alias LeastCostFeed.HenModel.{AminoAcids, CSV, Params}

  @routes [:auto, :sid_nutrients, :dig_as_sid, :dig_afd, :cvb, :hendrix_ratio]
  def routes, do: @routes

  @route_labels %{
    auto: "Auto (A if SID nutrients exist, else C with D fallback)",
    sid_nutrients: "A: SID nutrients in account",
    dig_as_sid: "B: 'Dig.' nutrients treated as SID",
    dig_afd: "B: 'Dig.' nutrients are AFD (Hendrix SID/AFD ratio)",
    cvb: "C: per-ingredient CVB 2017 SID",
    hendrix_ratio: "D: Hendrix diet-level SID/total ratios (approximate)"
  }
  def route_label(r), do: Map.fetch!(@route_labels, r)

  @cvb_file "sid_coefficients_cvb2017.csv"
  @map_file "ingredient_cvb_map.csv"
  @external_resource CSV.path(@cvb_file)
  @external_resource CSV.path(@map_file)

  @cvb CSV.read!(@cvb_file)
       |> Map.new(fn r ->
         {r["feedstuff"],
          %{
            estimated: r["estimated_flag"] == "yes",
            sidc:
              Map.new(~w(LYS MET CYS THR TRP ILE ARG VAL), fn k ->
                {k |> String.downcase() |> String.to_atom(), CSV.to_float(r[k]) / 100.0}
              end)
          }}
       end)

  @map CSV.read!(@map_file)
       |> Enum.map(fn r ->
         %{
           pattern: String.downcase(r["pattern"]),
           kind: String.to_atom(r["kind"]),
           feedstuff: r["cvb_feedstuff"],
           note: r["note"]
         }
       end)

  # Fail compilation if the map points at a feedstuff that is not in the CVB table.
  for %{kind: :feedstuff, feedstuff: f} <- @map, not Map.has_key?(@cvb, f) do
    raise "ingredient_cvb_map.csv refers to unknown CVB feedstuff #{inspect(f)}"
  end

  def cvb_table, do: @cvb
  def cvb_map, do: @map

  @doc "CVB mapping entry for an ingredient name, or nil."
  def match_ingredient(name) do
    n = String.downcase(name || "")
    Enum.find(@map, fn m -> String.contains?(n, m.pattern) end)
  end

  @doc """
  SIDC (fraction) of `aa` for a mapping entry. `metcys` combines MET and CYS
  weighted by the ingredient's own Met and Cys (= Met+Cys − Met) contents.
  """
  def sidc(%{kind: :synthetic}, _aa, _totals, ov),
    do: Params.value("sid_crystalline_aa", ov) / 100.0

  def sidc(%{kind: :feedstuff, feedstuff: f}, :metcys, totals, _ov) do
    c = Map.fetch!(@cvb, f).sidc
    mc = Map.get(totals, :metcys) || 0.0
    met = Map.get(totals, :met) || 0.0

    if mc > 0.0 and met > 0.0 and met <= mc,
      do: (met * c.met + (mc - met) * c.cys) / mc,
      else: (c.met + c.cys) / 2.0
  end

  def sidc(%{kind: :feedstuff, feedstuff: f}, aa, _totals, _ov),
    do: Map.fetch!(Map.fetch!(@cvb, f).sidc, aa)

  def fallback_ratio(aa, ov \\ %{}), do: Params.value("fallback_sid_ratio_#{aa}", ov)

  @doc """
  Computes SID AA concentrations (mg/g) for a diet.

  `input` keys: `:total`, `:sid`, `:dig` (maps aa => mg/g diet, missing = nil)
  and `:ingredients` (list of `%{name, actual (fraction), total: %{aa => mg/g ingredient}}`).

  Returns `%{sid: %{aa => mg/g}, aa_routes: %{aa => :a | :b | :c | :d | :none}, unmapped: [name], warnings: [..]}`.
  """
  def compute(route, input, ov \\ %{}) when route in @routes do
    total = Map.get(input, :total, %{})
    sid_n = Map.get(input, :sid, %{})
    dig = Map.get(input, :dig, %{})
    ings = Map.get(input, :ingredients, [])

    c_result = if route in [:auto, :cvb] and ings != [], do: per_ingredient(ings, ov)

    {sid, routes, warnings} =
      Enum.reduce(AminoAcids.aas(), {%{}, %{}, []}, fn aa, {s, r, w} ->
        d_value = fn -> total[aa] && total[aa] * fallback_ratio(aa, ov) end

        {val, rt, warn} =
          case route do
            :auto ->
              cond do
                present?(sid_n[aa]) -> {sid_n[aa], :a, nil}
                c_result && present?(total[aa]) -> {c_result.sid[aa], :c, nil}
                true -> {d_value.(), :d, nil}
              end

            :sid_nutrients ->
              if present?(sid_n[aa]),
                do: {sid_n[aa], :a, nil},
                else:
                  {d_value.(), :d,
                   "No SID #{AminoAcids.label(aa)} nutrient; used Hendrix ratio (D)"}

            :dig_as_sid ->
              if present?(dig[aa]),
                do: {dig[aa], :b, nil},
                else:
                  {d_value.(), :d,
                   "No Dig. #{AminoAcids.label(aa)} nutrient; used Hendrix ratio (D)"}

            :dig_afd ->
              if present?(dig[aa]),
                do: {dig[aa] * Params.value("afd_to_sid_ratio_#{aa}", ov), :b, nil},
                else:
                  {d_value.(), :d,
                   "No Dig. #{AminoAcids.label(aa)} nutrient; used Hendrix ratio (D)"}

            :cvb ->
              if c_result && present?(total[aa]),
                do: {c_result.sid[aa], :c, nil},
                else:
                  {d_value.(), :d,
                   "No ingredient data for #{AminoAcids.label(aa)}; used Hendrix ratio (D)"}

            :hendrix_ratio ->
              {d_value.(), :d, nil}
          end

        rt = if is_nil(val), do: :none, else: rt
        {Map.put(s, aa, val), Map.put(r, aa, rt), if(warn, do: [warn | w], else: w)}
      end)

    unmapped =
      if c_result && Enum.any?(Map.values(routes), &(&1 == :c)), do: c_result.unmapped, else: []

    warnings =
      Enum.reverse(warnings) ++
        if(unmapped != [],
          do: ["No CVB mapping for: #{Enum.join(unmapped, ", ")} (their AA used Hendrix ratio D)"],
          else: []
        ) ++
        if(Enum.any?(Map.values(routes), &(&1 == :none)),
          do: [
            "No value for: " <>
              (routes
               |> Enum.filter(&(elem(&1, 1) == :none))
               |> Enum.map(&AminoAcids.label(elem(&1, 0)))
               |> Enum.join(", ")) <>
              " (treated as not limiting)"
          ],
          else: []
        )

    %{sid: sid, aa_routes: routes, unmapped: unmapped, warnings: warnings}
  end

  defp present?(v), do: is_number(v) and v > 0.0

  defp per_ingredient(ings, ov) do
    {sid, unmapped} =
      Enum.reduce(ings, {Map.new(AminoAcids.aas(), &{&1, 0.0}), []}, fn ing, {acc, um} ->
        entry = match_ingredient(ing.name)
        has_aa = Enum.any?(AminoAcids.aas(), &((ing.total[&1] || 0.0) > 0.0))

        acc =
          Enum.reduce(AminoAcids.aas(), acc, fn aa, a ->
            t = ing.total[aa] || 0.0
            k = if entry, do: sidc(entry, aa, ing.total, ov), else: fallback_ratio(aa, ov)
            Map.update!(a, aa, &(&1 + ing.actual * t * k))
          end)

        {acc, if(is_nil(entry) and has_aa, do: [ing.name | um], else: um)}
      end)

    %{sid: sid, unmapped: Enum.reverse(unmapped)}
  end
end
