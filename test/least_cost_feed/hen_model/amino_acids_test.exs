defmodule LeastCostFeed.HenModel.AminoAcidsTest do
  use ExUnit.Case, async: true

  alias LeastCostFeed.HenModel.{AminoAcids, Genotype, Hendrix}

  defp mean_bw(from, to) do
    ws = for wk <- from..to, do: Genotype.guide_week(:sea, wk)["bw_g"] / 1000.0
    Float.round(Enum.sum(ws) / length(ws), 3)
  end

  # T3: L2 reproduced exactly (to coefficient rounding); L3/L4 within ±2 %, or within the
  # table's 5 mg/d resolution (Hendrix values are printed rounded to 5 mg; Trp is a flat
  # 195 mg/d for L1-L3, so L3 Trp misses ±2 % by 0.1 point: 190.9 vs 195).
  test "T3 requirement reproduces Hendrix SID requirements" do
    coefs = AminoAcids.coefficients(:a)

    for {phase, {from, to}, tol} <- [
          {"L2", {40, 65}, 0.003},
          {"L3", {65, 90}, 0.02},
          {"L4", {90, 100}, 0.02}
        ] do
      p = Hendrix.phase(phase)
      req = AminoAcids.requirement(coefs, p.egg_mass, mean_bw(from, to))

      for aa <- AminoAcids.aas() do
        guide = p.sid[aa]
        dev = abs(req[aa] / guide - 1.0)

        assert dev <= tol or (phase != "L2" and abs(req[aa] - guide) <= 5.0),
               "#{phase} #{aa}: predicted #{Float.round(req[aa], 1)} vs Hendrix #{guide} (#{Float.round(dev * 100, 2)}%)"
      end
    end
  end

  test "maintenance set B changes only Met+Cys and Thr" do
    a = AminoAcids.coefficients(:a)
    b = AminoAcids.coefficients(:b)
    assert a.lys == b.lys
    assert b.metcys == %{a: 11.83, m: 26.0}
    assert b.thr == %{a: 8.63, m: 22.0}
  end

  test "population requirement with x = 0 equals mean-hen requirement and grows with x" do
    c = AminoAcids.coefficients(:a)
    base = AminoAcids.requirement(c, 58.0, 1.85)
    p0 = AminoAcids.population_requirement(c, 58.0, 1.85, 0.0, 1.0, 0.069)
    p1 = AminoAcids.population_requirement(c, 58.0, 1.85, 1.0, 1.0, 0.069)

    for aa <- AminoAcids.aas() do
      assert_in_delta p0[aa], base[aa], 1.0e-9
      assert p1[aa] > base[aa]
    end
  end
end
