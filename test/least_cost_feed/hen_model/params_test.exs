defmodule LeastCostFeed.HenModel.ParamsTest do
  @moduledoc "T15: parameters file integrity and recomputation of DERIVED values (port of derive.py)."
  use ExUnit.Case, async: true

  alias LeastCostFeed.HenModel.{Genotype, Hendrix, Params, Stats}

  @aas [:lys, :met, :metcys, :thr, :trp, :val, :ile, :arg]

  test "every row has a valid status, and SOURCED/DERIVED rows cite a source" do
    for p <- Params.all() do
      assert p.status in [:sourced, :derived, :assumed, :placeholder], "#{p.id}: #{p.status}"

      if p.status in [:sourced, :derived] do
        assert p.source_id not in [nil, "", "-"], "#{p.id} has no source_id"
      end
    end
  end

  test "parameter ids are unique" do
    ids = Enum.map(Params.all(), & &1.id)
    assert length(ids) == length(Enum.uniq(ids))
  end

  test "flagged parameters are exactly the ASSUMED and PLACEHOLDER rows" do
    assert Enum.all?(Params.flagged(), &(&1.status in [:assumed, :placeholder]))
    assert Enum.any?(Params.flagged(), &(&1.id == "geno_sigma_emax"))
    assert Enum.any?(Params.flagged(), &(&1.id == "intake_aa_drive_lambda"))
  end

  test "overrides win and blank placeholders resolve to their neutral default" do
    assert Params.value("intake_cap_headroom") == 0.1
    assert Params.value("intake_cap_headroom", %{"intake_cap_headroom" => 0.2}) == 0.2
    assert Params.value("heat_lay_slope") == 0.0
    assert Params.value_or_nil("egg_price_per_kg") == nil
    assert_raise ArgumentError, fn -> Params.value("egg_grade_bands") end
  end

  test "fallback SID/total and SID/AFD ratios recompute from Hendrix Table 3" do
    phases = Hendrix.phases()

    for aa <- @aas do
      sid_total = Enum.sum(for p <- phases, do: p.sid[aa] / p.total[aa]) / 4
      sid_afd = Enum.sum(for p <- phases, do: p.sid[aa] / p.afd[aa]) / 4
      assert Float.round(sid_total, 3) == Params.value("fallback_sid_ratio_#{aa}")
      assert Float.round(sid_afd, 3) == Params.value("afd_to_sid_ratio_#{aa}")
    end
  end

  test "egg composition and shell fraction recompute" do
    shell_frac = Params.value("shell_caco3_g") / 0.95 / 60.0
    assert Float.round(shell_frac, 3) == Params.value("shell_fraction_60g")

    edible = fn id -> Params.value("egg_edible_#{id}") end

    for aa <- [:lys, :thr, :trp, :val, :ile, :arg] do
      assert Float.round(edible.(aa) * (1 - shell_frac), 2) == Params.value("egg_whole_#{aa}")
    end

    assert Float.round((edible.(:met) + edible.(:cys)) * (1 - shell_frac), 2) ==
             Params.value("egg_whole_metcys")
  end

  defp w_l2 do
    ws = for wk <- 40..65, do: Genotype.guide_week(:sea, wk)["bw_g"] / 1000.0
    Float.round(Enum.sum(ws) / length(ws), 3)
  end

  test "Trp maintenance and per-g-egg coefficients recompute from Hendrix L2" do
    w2 = w_l2()
    e2 = 59.0
    l2 = Hendrix.phase("L2")
    share = 10.25 * w2 / (2.25 * e2 + 10.25 * w2)
    assert Float.round(l2.sid.trp * share / :math.pow(w2, 0.75), 1) == Params.value("maint_trp")

    for aa <- @aas do
      m = Params.value("maint_#{aa}")
      a = (l2.sid[aa] - m * :math.pow(w2, 0.75)) / e2
      assert Float.round(a, 2) == Params.value("egg_coef_#{aa}"), "#{aa}"
    end

    for aa <- [:metcys, :thr] do
      m = Params.value("maint_#{aa}_setB")
      a = (l2.sid[aa] - m * :math.pow(w2, 0.75)) / e2
      assert Float.round(a, 2) == Params.value("egg_coef_#{aa}_setB")
    end
  end

  test "egg-weight SD recomputes from the SEA grading table (wk 30-90)" do
    sds =
      for wk <- 30..90,
          r = Genotype.guide_week(:sea, wk),
          ps = r["grade_S_lt53_pct"] / 100,
          pxl = r["grade_XL_gt73_pct"] / 100,
          ps > 0 and ps < 1 and pxl > 0 and pxl < 1 do
        mu = r["egg_wt_g"]
        ((53 - mu) / Stats.inv_norm(ps) + (73 - mu) / Stats.inv_norm(1 - pxl)) / 2
      end

    assert Float.round(Enum.sum(sds) / length(sds), 2) == Params.value("geno_egg_wt_sd")
  end

  test "BW CV recomputes from 85 % uniformity within ±10 %" do
    assert Float.round(0.10 / Stats.inv_norm(0.5 + 0.85 / 2), 3) == Params.value("geno_bw_cv")
  end
end
