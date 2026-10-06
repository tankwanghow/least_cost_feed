defmodule LeastCostFeed.HenModel.Minerals do
  @moduledoc """
  Rule-based Ca/P shell-quality risk index (SPEC 4.9). Transparent screen,
  NOT a predicted shell strength. Points (all thresholds from parameters.csv):

  | Check | Rule |
  |---|---|
  | Ca vs Hendrix lower band | `< shell_risk_ca_low` × band → +2, `< shell_risk_ca_moderate` × → +1 |
  | Ca balance | `< lay/100 × shell_ca_per_egg × ca_feed_share / shell_risk_ca_absorption` → +1 |
  | avP low | `< max(avp_adequate_min, Hendrix lower band)` → +1 |
  | avP high | `> shell_risk_avp_high × Hendrix upper band` → +1 |
  | Heat | `T_max > shell_risk_heat` → +1 |
  | Age | `wk > shell_risk_age` → +1 |
  | Limestone (optional) | coarse share `< coarse_limestone_share_brown` → +1 |

  Classes from `shell_risk_score_bins` (0-1 Low, 2-3 Moderate, 4+ High).
  """

  alias LeastCostFeed.HenModel.{Hendrix, Params}

  @doc """
  `input`: `%{ca_mg, avp_mg (mg/d or nil), lay (%), wk, t_max, coarse_share (nil)}`.
  Returns `%{points, class (:low | :moderate | :high), reasons: [String]}`.
  """
  def shell_risk(input, ov \\ %{}) do
    phase = Hendrix.phase_for_week(input.wk)
    {ca_lo, _ca_hi} = phase.ca
    {avp_lo, avp_hi} = phase.avp

    checks = [
      fn ->
        case input.ca_mg do
          nil ->
            nil

          ca ->
            cond do
              ca < Params.value("shell_risk_ca_low", ov) * ca_lo ->
                {2,
                 "Ca #{round(ca)} mg/d < #{pct(Params.value("shell_risk_ca_low", ov))} of Hendrix #{phase.phase} min #{round(ca_lo)}"}

              ca < Params.value("shell_risk_ca_moderate", ov) * ca_lo ->
                {1, "Ca #{round(ca)} mg/d below Hendrix #{phase.phase} min #{round(ca_lo)}"}

              true ->
                nil
            end
        end
      end,
      fn ->
        if input.ca_mg do
          need =
            input.lay / 100.0 * Params.value("shell_ca_per_egg", ov) * 1000.0 *
              Params.value("ca_feed_share", ov) / Params.value("shell_risk_ca_absorption", ov)

          if input.ca_mg < need,
            do: {1, "Ca #{round(input.ca_mg)} mg/d < shell Ca balance need #{round(need)}"}
        end
      end,
      fn ->
        if input.avp_mg do
          floor = max(Params.value("avp_adequate_min", ov), avp_lo)
          if input.avp_mg < floor, do: {1, "avP #{round(input.avp_mg)} mg/d < #{round(floor)}"}
        end
      end,
      fn ->
        if input.avp_mg do
          cap = Params.value("shell_risk_avp_high", ov) * avp_hi

          if input.avp_mg > cap,
            do: {1, "avP #{round(input.avp_mg)} mg/d > #{round(cap)} (P excess)"}
        end
      end,
      fn ->
        lim = Params.value("shell_risk_heat", ov)
        if input.t_max > lim, do: {1, "House T max #{input.t_max} °C > #{lim} °C"}
      end,
      fn ->
        lim = Params.value("shell_risk_age", ov)
        if input.wk > lim, do: {1, "Age #{input.wk} wk > #{round(lim)} wk (Ca absorption falls)"}
      end,
      fn ->
        case Map.get(input, :coarse_share) do
          nil ->
            nil

          share ->
            lim = Params.value("coarse_limestone_share_brown", ov)
            if share < lim, do: {1, "Coarse limestone #{pct(share)} < #{pct(lim)}"}
        end
      end
    ]

    hits = checks |> Enum.map(& &1.()) |> Enum.reject(&is_nil/1)
    points = hits |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    %{points: points, class: classify(points), reasons: Enum.map(hits, &elem(&1, 1))}
  end

  @doc "Class for a point score using `shell_risk_score_bins` (\"0-1/2-3/4+\")."
  def classify(points) do
    [_low, moderate, high] =
      Params.get!("shell_risk_score_bins").raw
      |> String.split("/")
      |> Enum.map(fn s -> s |> String.split(["-", "+"]) |> hd() |> String.to_integer() end)

    cond do
      points >= high -> :high
      points >= moderate -> :moderate
      true -> :low
    end
  end

  defp pct(f), do: "#{round(f * 100)}%"
end
