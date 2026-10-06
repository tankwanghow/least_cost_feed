defmodule LeastCostFeed.HenModel.Intake do
  @moduledoc """
  EFG first-limiting intake rule (SPEC 4.4):

      FI_E   = ME_req / [ME]
      FI_i   = R_i / [AA_i]
      FI_d   = FI_E + λ · max(0, max_i FI_i − FI_E)        λ = intake_aa_drive_lambda
      FI_cap = (1 + h) · FI_guide − c_heat · (T − heat_lay_threshold)⁺
      FI     = min(FI_d, FI_cap)

  `h` = `intake_cap_headroom` (ASSUMED 0.10); `c_heat` = `intake_cap_heat`
  (PLACEHOLDER, 0 = off). `intake_energy_elasticity` is carried in
  parameters.csv but not applied in v1 (functional form not sourced).

  Returns `%{fi, fi_energy, fi_aa, driver}` where `driver` is `:energy`,
  the AA that drove intake, or `:cap`.
  """

  def desired(me_req, me, req_aa, sid, lambda, fi_guide, headroom, cap_heat, temp, heat_threshold) do
    fi_e = me_req / me

    {fi_aa, aa} =
      Enum.reduce(req_aa, {0.0, nil}, fn {aa, r}, {best, best_aa} ->
        conc = sid[aa]

        if is_number(conc) and conc > 0.0 and r / conc > best,
          do: {r / conc, aa},
          else: {best, best_aa}
      end)

    fi_d = fi_e + lambda * max(0.0, fi_aa - fi_e)
    cap = (1.0 + headroom) * fi_guide - cap_heat * max(0.0, temp - heat_threshold)

    {fi, driver} =
      cond do
        fi_d > cap -> {cap, :cap}
        fi_aa > fi_e and lambda > 0.0 -> {fi_d, aa}
        true -> {fi_d, :energy}
      end

    %{fi: max(fi, 0.0), fi_energy: fi_e, fi_aa: fi_aa, driver: driver}
  end
end
