defmodule LeastCostFeed.HenModel.Energy do
  @moduledoc """
  Energy requirement of the laying hen (SPEC 4.2).

  Default (`:sakomura`, S6):

      MEm    = k_m * W^0.75 * (165.74 - 2.37 T)
      MEf    = W^0.75 * ΔF(T, F)                      (feather term, 4.2.1; ASSUMED for hens)
      ME_req = H * (MEm + MEf) + 6.68 WG + 2.40 E

  Alternatives: `:sakomura_alt` (S6 Table 2, 163.67 - 2.09 T) and
  `:emmans` (S5, brown: `W (140 - 2.0 T) + 2.0 E + 5.0 ΔW`, scales on W).

  `H` is the housing factor (cage 1.00, barn +9 %, free range +12 %; S4 3.10.2),
  applied to maintenance only. `k_m` is `me_maint_scalar` (1.0 = as
  published) or, in guide-anchored mode, solved by `guide_anchor_km/2`.
  """

  alias LeastCostFeed.HenModel.{Genotype, Params}

  @equations [:sakomura, :sakomura_alt, :emmans]
  def equations, do: @equations

  @doc "Housing factor H (multiplier on maintenance)."
  def housing_factor(housing, ov \\ %{})
  def housing_factor(:cage, ov), do: 1.0 + Params.value("housing_energy_cage", ov) / 100.0
  def housing_factor(:barn, ov), do: 1.0 + Params.value("housing_energy_barn_brown", ov) / 100.0

  def housing_factor(:free_range, ov),
    do: 1.0 + Params.value("housing_energy_free_range_brown", ov) / 100.0

  @doc "ME cost of egg output, BW gain and ME yield of BW loss (kcal/g) for an equation."
  def coefficients(equation, ov \\ %{})

  def coefficients(:emmans, ov),
    do: %{
      egg: Params.value("emmans_egg", ov),
      gain: Params.value("emmans_gain", ov),
      loss: Params.value("me_bwloss_yield", ov)
    }

  def coefficients(eq, ov) when eq in [:sakomura, :sakomura_alt],
    do: %{
      egg: Params.value("me_egg", ov),
      gain: Params.value("me_gain", ov),
      loss: Params.value("me_bwloss_yield", ov)
    }

  @doc """
  Unscaled maintenance ME (kcal/d) of a hen of `w` kg at `t` °C with feather
  score `f` (0-1), before `k_m` and `H`.
  """
  def maintenance_base(equation, w, t, f, ov \\ %{})

  def maintenance_base(:sakomura, w, t, f, ov) do
    :math.pow(w, 0.75) *
      (Params.value("me_maint_a", ov) + Params.value("me_maint_b", ov) * t +
         feather_increment(t, f, ov))
  end

  def maintenance_base(:sakomura_alt, w, t, f, ov) do
    :math.pow(w, 0.75) *
      (Params.value("me_maint_alt_a", ov) + Params.value("me_maint_alt_b", ov) * t +
         feather_increment(t, f, ov))
  end

  def maintenance_base(:emmans, w, t, _f, ov) do
    w * (Params.value("emmans_brown_a", ov) + Params.value("emmans_brown_b", ov) * t)
  end

  @doc "Maintenance ME including `k_m` and housing factor `h`: `k_m * H * (MEm + MEf)`."
  def maintenance(equation, w, t, f, km, h, ov \\ %{}),
    do: km * h * maintenance_base(equation, w, t, f, ov)

  @doc """
  Feather-cover increment ΔF(T, F) in kcal/kg^0.75/d (SPEC 4.2.1, pullet
  equations of S6 applied relative to a fully feathered bird; ASSUMED
  `feather_term_applies_to_hens`).
  """
  def feather_increment(t, f, ov \\ %{}) do
    if Params.get!("feather_term_applies_to_hens").raw == "true" do
      lct = fn ff ->
        Params.value("feather_lct_a", ov) + Params.value("feather_lct_b", ov) * ff
      end

      g(t, lct.(f), ov) - g(t, lct.(1.0), ov)
    else
      0.0
    end
  end

  defp g(t, l, ov) when t < l, do: Params.value("feather_cold_slope", ov) * (l - t)
  defp g(t, l, ov), do: Params.value("feather_warm_slope", ov) * (t - l)

  @doc """
  Daily ME requirement (kcal/d):
  `H * k_m * (MEm + MEf) + c_gain * max(WG, 0) + c_egg * E`.

  Options: `:equation` (default `:sakomura`), `:km` (1.0), `:housing_factor`
  (1.0), `:feather` (1.0), `:overrides`.
  """
  def me_req(w, t, wg, e, opts \\ []) do
    eq = Keyword.get(opts, :equation, :sakomura)
    ov = Keyword.get(opts, :overrides, %{})
    c = coefficients(eq, ov)

    maintenance(
      eq,
      w,
      t,
      Keyword.get(opts, :feather, 1.0),
      Keyword.get(opts, :km, 1.0),
      Keyword.get(opts, :housing_factor, 1.0),
      ov
    ) + c.gain * max(wg, 0.0) + c.egg * e
  end

  @doc """
  Guide-anchored `k_m` (SPEC 4.4): the maintenance multiplier for which the
  energy-driven intake of a cage, fully feathered hen eating a
  `guide_anchor_diet_me` diet at `ref_temp` equals the guide's intake, on
  average over the `guide_anchor_window` weeks (Hendrix Layer 2) using the
  guide's own BW, BW gain and egg mass.
  """
  def guide_anchor_km(edition, equation, ref_temp, ov \\ %{}) do
    me_diet = Params.value("guide_anchor_diet_me", ov) / 1000.0

    [from, to] =
      Params.get!("guide_anchor_window").raw
      |> String.split("-")
      |> Enum.map(&String.to_integer/1)

    c = coefficients(equation, ov)

    {need, maint} =
      Enum.reduce(from..to, {0.0, 0.0}, fn wk, {need, maint} ->
        row = Genotype.guide_week(edition, wk)
        next = Genotype.guide_week(edition, wk + 1) || row
        w = row["bw_g"] / 1000.0
        wg = max((next["bw_g"] - row["bw_g"]) / 7.0, 0.0)
        e = row["lay_pct_hd"] * row["egg_wt_g"] / 100.0

        {need + row["feed_g_d"] * me_diet - c.egg * e - c.gain * wg,
         maint + maintenance_base(equation, w, ref_temp, 1.0, ov)}
      end)

    need / maint
  end
end
