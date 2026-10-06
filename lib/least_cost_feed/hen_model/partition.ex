defmodule LeastCostFeed.HenModel.Partition do
  @moduledoc """
  Splitting egg output and energy (SPEC 4.6, 4.7).

  * An egg-mass shortfall `r = Ē / Emax` is split multiplicatively,
    `lay = P_lay · r^s`, `EW = P_EW · r^(1-s)` with `s = aa_deficit_split_lay`
    (2/3, S4 3.1), so `lay × EW / 100 = Emax · r`.
  * Body weight: energy surplus `S = FI·[ME] − maintenance − c_egg·E`;
    `S > 0` → gain `S / c_gain` (fat, S8); `S < 0` → loss `S / me_bwloss_yield`.
  """

  def split(r, p_lay, p_ew, share) do
    r = r |> max(0.0) |> min(1.0)
    {p_lay * :math.pow(r, share), p_ew * :math.pow(r, 1.0 - share)}
  end

  @doc "BW change (g/d) from energy surplus `s` (kcal/d) and energy coefficients."
  def bw_change(s, %{gain: gain}) when s >= 0, do: s / gain
  def bw_change(s, %{loss: loss}), do: s / loss
end
