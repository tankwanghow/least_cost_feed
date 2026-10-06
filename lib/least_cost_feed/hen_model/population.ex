defmodule LeastCostFeed.HenModel.Population do
  @moduledoc """
  Reading-model population response (SPEC 4.5, S7/S9).

  N virtual hens (`pop_n_hens`) with `Emax_j = Emax + σ_E z_j` and
  `W_j = W (1 + CV_W u_j)` (deterministic quantile design, see
  `Stats.population_design/2`). All hens receive the flock intake FI
  (mean-field). Each hen's egg output is the Liebig minimum of her
  potential and each SID AA limit `(FI·[AA_i] − m_i W_j^0.75) / a_i`.

  Energy limit (`energy_limit` scenario option):

    * `:flock` (default) - the energy available for eggs,
      `(FI·[ME] − maintenance(W̄) − c_gain·WG⁺) / c_egg`, caps the flock
      mean; it is shared so that the hens with the highest AA/potential-
      limited output are the energy-limited ones ("water filling").
    * `:per_hen` - SPEC 4.5 as written: each hen's own
      `(FI·[ME] − maintenance(W_j) − c_gain·WG⁺) / c_egg`. With one mean-field
      intake this makes heavy hens energy-limited and light hens store the
      surplus as fat, so it biases egg mass down and BW up; kept for comparison.

  Returns `%{e_mean, emax_mean, r, limiting: %{nutrient => share of hens}}`.
  """

  @doc """
  `hens` is the list of `{z, u}`; `ctx` has `:sigma_e, :bw_cv, :aa_coefs,
  :egg_coef, :gain_coef, :energy_limit` and `:maint_scale` (fun W_j/W -> factor).
  """
  def respond(hens, emax, w, fi, diet, maint_mean, wg_pos, ctx) do
    aa_terms =
      for {aa, %{a: a, m: m}} <- ctx.aa_coefs,
          conc = diet.sid[aa],
          is_number(conc) and conc > 0.0,
          do: {aa, fi * conc, a, m}

    energy_for_eggs_mean = fi * diet.me - maint_mean - ctx.gain_coef * wg_pos

    individual =
      Enum.map(hens, fn {z, u} ->
        emax_j = max(0.0, emax + ctx.sigma_e * z)
        w_j = w * (1.0 + ctx.bw_cv * u)
        w75 = :math.pow(w_j, 0.75)

        {lim, who} =
          Enum.reduce(aa_terms, {emax_j, :potential}, fn {aa, supply, a, m}, {best, who} ->
            e = (supply - m * w75) / a
            if e < best, do: {e, aa}, else: {best, who}
          end)

        {lim, who} =
          if ctx.energy_limit == :per_hen do
            e_en =
              (fi * diet.me - maint_mean * ctx.maint_scale.(w_j / w) - ctx.gain_coef * wg_pos) /
                ctx.egg_coef

            if e_en < lim, do: {e_en, :energy}, else: {lim, who}
          else
            {lim, who}
          end

        {emax_j, max(lim, 0.0), who}
      end)

    n = length(individual)
    emax_mean = Enum.reduce(individual, 0.0, fn {em, _, _}, acc -> acc + em end) / n
    e_mean0 = Enum.reduce(individual, 0.0, fn {_, e, _}, acc -> acc + e end) / n

    individual =
      if ctx.energy_limit == :flock do
        e_en = max(energy_for_eggs_mean / ctx.egg_coef, 0.0)

        if e_mean0 > e_en do
          c = water_level(individual, e_en)

          Enum.map(individual, fn {em, e, who} ->
            if e > c, do: {em, c, :energy}, else: {em, e, who}
          end)
        else
          individual
        end
      else
        individual
      end

    e_mean = Enum.reduce(individual, 0.0, fn {_, e, _}, acc -> acc + e end) / n

    limiting =
      individual
      |> Enum.frequencies_by(&elem(&1, 2))
      |> Map.new(fn {k, v} -> {k, v / n} end)

    %{
      e_mean: e_mean,
      emax_mean: emax_mean,
      r: if(emax_mean > 0.0, do: min(e_mean / emax_mean, 1.0), else: 1.0),
      limiting: limiting
    }
  end

  # Level c such that mean(min(e_j, c)) = target (bisection).
  defp water_level(individual, target) do
    es = Enum.map(individual, &elem(&1, 1))
    n = length(es)
    f = fn c -> Enum.reduce(es, 0.0, fn e, acc -> acc + min(e, c) end) / n end

    Enum.reduce(1..50, {0.0, Enum.max(es)}, fn _, {lo, hi} ->
      mid = (lo + hi) / 2.0
      if f.(mid) < target, do: {mid, hi}, else: {lo, mid}
    end)
    |> then(fn {lo, hi} -> (lo + hi) / 2.0 end)
  end
end
