defmodule LeastCostFeed.HenModel.Hendrix do
  @moduledoc """
  Hendrix Genetics Nutrition Guide 2025 (S4) Table 3: daily nutrient
  requirements (mg/hen/d) for Layer 1-4, from
  `priv/hen_model/hendrix_daily_nutrients.csv`.

  Phase boundaries: L1 from onset to < 40 wk, L2 40 to < 65, L3 65 to < 90,
  L4 90+ (the table's `to_age_wk` is treated as exclusive).
  """

  alias LeastCostFeed.HenModel.CSV

  @file_name "hendrix_daily_nutrients.csv"
  @external_resource CSV.path(@file_name)

  @aa_cols %{
    lys: "Lys",
    met: "Met",
    metcys: "MetCys",
    thr: "Thr",
    trp: "Trp",
    val: "Val",
    ile: "Ile",
    arg: "Arg"
  }

  @phases CSV.read!(@file_name)
          |> Enum.map(fn r ->
            num = fn k -> CSV.to_float(r[k]) end

            aa = fn basis ->
              Map.new(@aa_cols, fn {key, col} -> {key, num.("#{basis}_#{col}_mg_d")} end)
            end

            [me_lo, me_hi] =
              r["energy_cage_kcal_kg"] |> String.split("-") |> Enum.map(&CSV.to_float/1)

            %{
              phase: r["phase"],
              to_wk: num.("to_age_wk"),
              egg_mass: num.("expected_egg_mass_g_d"),
              me_kcal_kg: {me_lo, me_hi},
              total: aa.("total"),
              afd: aa.("afd"),
              sid: aa.("sid"),
              avp: {num.("avp_mg_d_min"), num.("avp_mg_d_max")},
              ca: {num.("ca_mg_d_min"), num.("ca_mg_d_max")},
              na_min: num.("na_mg_d_min"),
              cl: {num.("cl_mg_d_min"), num.("cl_mg_d_max")}
            }
          end)

  def phases, do: @phases

  def phase(name), do: Enum.find(@phases, &(&1.phase == name))

  @doc "Hendrix phase for an age in weeks."
  def phase_for_week(wk) do
    Enum.find(@phases, List.last(@phases), fn p -> wk < p.to_wk end)
  end
end
