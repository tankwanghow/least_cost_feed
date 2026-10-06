defmodule LeastCostFeed.HenModel.Genotype do
  @moduledoc """
  Genetic potential of the Hisex Brown hen (SPEC 4.1), from the breeder's
  weekly tables in `priv/hen_model/hisex_brown_targets.csv`
  (`:sea` = S.E. Asia cage guide L2240-1p (S2, default); `:global` = L6240-1 (S3)).

  Weekly values are knots at age `t = 7*wk` days and are linearly
  interpolated to any day. Calibration offsets (SPEC 7; all PLACEHOLDER,
  neutral by default) are applied to lay % and egg weight:

    * onset shift `δ_on` (d): `P_lay(t) := P_lay(t - δ_on)`
    * persistency `ρ`: after peak, `P_lay := P_peak - ρ (P_peak - P_lay)`
    * egg-weight offset `δ_EW` (g)
  """

  alias LeastCostFeed.HenModel.{CSV, Params}

  @file_name "hisex_brown_targets.csv"
  @external_resource CSV.path(@file_name)

  @numeric ~w(bw_g feed_g_d lay_pct_hd egg_wt_g egg_mass_g_d livability_pct eggs_hh_cum
              egg_mass_hh_cum_kg feed_cum_kg grade_S_lt53_pct grade_M_53_63_pct
              grade_L_63_73_pct grade_XL_gt73_pct)

  @rows CSV.read!(@file_name)

  @tables (for edition <- ["SEA", "GLOBAL"], into: %{} do
             rows =
               @rows
               |> Enum.filter(&(&1["edition"] == edition))
               |> Enum.map(fn r ->
                 Map.new(@numeric, fn k -> {k, CSV.to_float(r[k])} end)
                 |> Map.put("age_wk", String.to_integer(r["age_wk"]))
               end)
               |> Enum.sort_by(& &1["age_wk"])

             first_ew = Enum.find_value(rows, & &1["egg_wt_g"])

             # Before the first production week lay is 0, egg weight is the first
             # recorded value (no eggs are laid, so it only avoids a nil), and
             # livability is 100 %.
             filled =
               Enum.map(rows, fn r ->
                 r
                 |> Map.update!("lay_pct_hd", &(&1 || 0.0))
                 |> Map.update!("egg_wt_g", &(&1 || first_ew))
                 |> Map.update!("livability_pct", &(&1 || 100.0))
               end)

             {peak_wk, peak_lay} =
               filled
               |> Enum.map(&{&1["age_wk"], &1["lay_pct_hd"]})
               |> Enum.reduce(fn {w, l}, {bw, bl} -> if l > bl, do: {w, l}, else: {bw, bl} end)

             key = edition |> String.downcase() |> String.to_atom()

             {key,
              %{
                rows: filled,
                first_wk: hd(filled)["age_wk"],
                last_wk: List.last(filled)["age_wk"],
                peak_wk: peak_wk,
                peak_lay: peak_lay,
                curves:
                  Map.new(
                    ["lay_pct_hd", "egg_wt_g", "bw_g", "feed_g_d", "livability_pct"],
                    fn k ->
                      {k, filled |> Enum.map(& &1[k]) |> List.to_tuple()}
                    end
                  )
              }}
           end)

  @editions Map.keys(@tables)

  def editions, do: @editions

  @doc "Raw guide rows for an edition (weekly, as in the CSV)."
  def rows(edition \\ :sea), do: table(edition).rows

  @doc "Guide row for a given week, or nil."
  def guide_week(edition, wk), do: Enum.find(rows(edition), &(&1["age_wk"] == wk))

  def peak_week(edition \\ :sea), do: table(edition).peak_wk
  def last_week(edition \\ :sea), do: table(edition).last_wk

  @doc "Default calibration offsets from parameters.csv (neutral)."
  def default_calibration(overrides \\ %{}) do
    %{
      onset_shift_d: Params.value("cal_onset_shift_d", overrides),
      persistency: Params.value("cal_persistency_scale", overrides),
      ew_offset_g: Params.value("cal_egg_wt_offset_g", overrides)
    }
  end

  @doc """
  Potential at age `t` (days): `%{lay, ew, emax, bw_g, fi_guide, liv, wg_tgt}`.
  `emax = lay * ew / 100` (g egg/hen/d); `wg_tgt` is the guide's BW gain (g/d).
  """
  def potential(edition, t, cal \\ nil) do
    cal = cal || default_calibration()
    tab = table(edition)
    shifted_t = t - cal.onset_shift_d
    lay0 = curve(tab, "lay_pct_hd", shifted_t)

    lay =
      if shifted_t / 7.0 > tab.peak_wk do
        max(0.0, tab.peak_lay - cal.persistency * (tab.peak_lay - lay0))
      else
        lay0
      end

    ew = curve(tab, "egg_wt_g", t) + cal.ew_offset_g
    bw = curve(tab, "bw_g", t)

    %{
      lay: lay,
      ew: ew,
      emax: lay * ew / 100.0,
      bw_g: bw,
      fi_guide: curve(tab, "feed_g_d", t),
      liv: curve(tab, "livability_pct", t),
      wg_tgt: curve(tab, "bw_g", t + 1) - bw
    }
  end

  @doc "Interpolated guide curve value (no calibration) at day `t`."
  def guide_curve(edition, key, t), do: curve(table(edition), key, t)

  defp table(edition) when edition in @editions, do: Map.fetch!(@tables, edition)
  defp table(edition), do: raise(ArgumentError, "unknown guide edition #{inspect(edition)}")

  defp curve(tab, key, t) do
    values = Map.fetch!(tab.curves, key)
    wk = t / 7.0
    n = tuple_size(values)

    cond do
      wk <= tab.first_wk ->
        elem(values, 0)

      wk >= tab.last_wk ->
        elem(values, n - 1)

      true ->
        i = trunc(Float.floor(wk)) - tab.first_wk
        f = wk - Float.floor(wk)
        y0 = elem(values, i)
        y1 = elem(values, i + 1)
        y0 + (y1 - y0) * f
    end
  end
end
