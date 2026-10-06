defmodule LeastCostFeed.HenModel.EnergyTest do
  use ExUnit.Case, async: true

  alias LeastCostFeed.HenModel.Energy

  # T1 (SPEC 8): Sakomura worked value
  test "T1 Sakomura ME requirement worked example" do
    assert_in_delta Energy.me_req(1.804, 25.0, 1.0, 58.8), 313.5, 0.5
  end

  # T2: Emmans brown switch: 1.804*90 + 2*58.8 + 5*1 = 285
  test "T2 Emmans 1974 brown alternative" do
    assert_in_delta Energy.me_req(1.804, 25.0, 1.0, 58.8, equation: :emmans), 285.0, 1.0
  end

  test "maintenance falls with temperature (Sakomura slope -2.37)" do
    w75 = :math.pow(1.8, 0.75)
    m25 = Energy.maintenance_base(:sakomura, 1.8, 25.0, 1.0)
    m30 = Energy.maintenance_base(:sakomura, 1.8, 30.0, 1.0)
    assert_in_delta m25 - m30, 5 * 2.37 * w75, 1.0e-9
  end

  test "housing factor applies to maintenance only" do
    base = Energy.me_req(1.8, 25.0, 0.0, 0.0)
    barn = Energy.me_req(1.8, 25.0, 0.0, 0.0, housing_factor: Energy.housing_factor(:barn))
    assert_in_delta barn / base, 1.09, 1.0e-9
    assert Energy.housing_factor(:cage) == 1.0
    assert_in_delta Energy.housing_factor(:free_range), 1.12, 1.0e-9

    with_egg = Energy.me_req(1.8, 25.0, 0.0, 50.0, housing_factor: 1.09) - barn
    assert_in_delta with_egg, 2.4 * 50.0, 1.0e-9
  end

  test "feather term is zero for a fully feathered hen and follows S6 equations" do
    assert Energy.feather_increment(25.0, 1.0) == 0.0
    # warm branch for both F=0.5 and F=1 at 30 C: 0.88*((30-LCT(0.5)) - (30-LCT(1)))
    lct = fn f -> 24.54 - 5.65 * f end
    assert_in_delta Energy.feather_increment(30.0, 0.5), 0.88 * (lct.(1.0) - lct.(0.5)), 1.0e-9
    # cold branch below LCT(0.5)=21.715 but above LCT(1)=18.89
    t = 20.0
    expected = 6.73 * (lct.(0.5) - t) - 0.88 * (t - lct.(1.0))
    assert_in_delta Energy.feather_increment(t, 0.5), expected, 1.0e-9
  end

  test "guide-anchored k_m reproduces mean guide intake over Layer-2 weeks" do
    km = Energy.guide_anchor_km(:sea, :sakomura, 25.0)
    assert km > 1.0 and km < 1.2

    rows = for wk <- 40..65, do: LeastCostFeed.HenModel.Genotype.guide_week(:sea, wk)

    fis =
      for {r, i} <- Enum.with_index(rows) do
        next = Enum.at(rows, i + 1) || LeastCostFeed.HenModel.Genotype.guide_week(:sea, 66)
        wg = max((next["bw_g"] - r["bw_g"]) / 7.0, 0.0)
        e = r["lay_pct_hd"] * r["egg_wt_g"] / 100.0
        Energy.me_req(r["bw_g"] / 1000.0, 25.0, wg, e, km: km) / 2.8
      end

    guide = Enum.map(rows, & &1["feed_g_d"])
    assert_in_delta Enum.sum(fis) / length(fis), Enum.sum(guide) / length(guide), 1.0e-6
  end
end
