defmodule LeastCostFeed.HenModel.EconomicsMineralsTest do
  use ExUnit.Case, async: true

  alias LeastCostFeed.HenModel.{Economics, Genotype, Minerals, Hendrix}

  # T9: grade split with SD 5.02 g vs SEA grading table
  test "T9 predicted %<53 g and %>73 g within 3 points of the guide" do
    bands = [%{min: nil, max: 53.0}, %{min: 73.0, max: nil}]

    for wk <- [30, 50, 70, 90] do
      r = Genotype.guide_week(:sea, wk)
      [s, xl] = Economics.grade_shares(r["egg_wt_g"], 5.02, bands)
      assert_in_delta s * 100, r["grade_S_lt53_pct"], 3.0, "wk #{wk} S"
      assert_in_delta xl * 100, r["grade_XL_gt73_pct"], 3.0, "wk #{wk} XL"
    end
  end

  # T13: economics hand-checked
  test "T13 per-kg and per-egg revenue, feed cost" do
    # 90 % lay, 62 g egg, 6.0 per kg -> 0.9 * 0.062 * 6 = 0.3348 per hen-day
    assert_in_delta Economics.revenue_hd(90.0, 62.0, {:per_kg, 6.0}), 0.3348, 1.0e-9
    # one open band covering everything at 0.40/egg -> 0.9 * 0.40
    assert_in_delta Economics.revenue_hd(
                      90.0,
                      62.0,
                      {:per_egg, [%{min: nil, max: nil, price: 0.40}]}
                    ),
                    0.36,
                    1.0e-9

    # two bands split at the mean -> 50/50
    bands = [%{min: nil, max: 62.0, price: 0.30}, %{min: 62.0, max: nil, price: 0.50}]
    assert_in_delta Economics.revenue_hd(90.0, 62.0, {:per_egg, bands}), 0.9 * 0.40, 1.0e-9
    # 115 g at 2.10/kg
    assert_in_delta Economics.feed_cost_hd(115.0, 2.1), 0.2415, 1.0e-9
    assert Economics.revenue_hd(90.0, 62.0, {:per_kg, nil}) == nil
  end

  test "grade bands parse" do
    assert {:ok,
            [
              %{name: "A", min: nil, max: 60.0, price: 0.3},
              %{name: "B", min: 60.0, max: nil, price: 0.4}
            ]} =
             Economics.parse_bands("A,,60,0.3\nB,60,,0.4")

    assert {:error, _} = Economics.parse_bands("A,x,60,0.3")
  end

  # T12: shell risk
  test "T12 Hendrix mid-band diet at 25 C, 40 wk is Low" do
    p = Hendrix.phase_for_week(40)
    {ca_lo, ca_hi} = p.ca
    {avp_lo, avp_hi} = p.avp

    risk =
      Minerals.shell_risk(%{
        ca_mg: (ca_lo + ca_hi) / 2,
        avp_mg: (avp_lo + avp_hi) / 2,
        lay: 95.0,
        wk: 40,
        t_max: 25.0
      })

    assert risk.class == :low
    assert risk.points <= 1
  end

  test "T12 Ca at 90 % of the lower band, 70 wk, 32 C is High" do
    p = Hendrix.phase_for_week(70)
    {ca_lo, _} = p.ca
    {avp_lo, avp_hi} = p.avp

    risk =
      Minerals.shell_risk(%{
        ca_mg: 0.9 * ca_lo,
        avp_mg: (avp_lo + avp_hi) / 2,
        lay: 86.0,
        wk: 70,
        t_max: 32.0
      })

    assert risk.class == :high
    assert risk.points >= 4
    assert length(risk.reasons) >= 3
  end

  test "limestone and avP checks" do
    base = %{ca_mg: 4200.0, avp_mg: 380.0, lay: 90.0, wk: 50, t_max: 25.0}
    assert Minerals.shell_risk(base).points == 0
    assert Minerals.shell_risk(Map.put(base, :coarse_share, 0.5)).points == 1
    assert Minerals.shell_risk(%{base | avp_mg: 200.0}).points == 1
    assert Minerals.shell_risk(%{base | avp_mg: 500.0}).points == 1
    assert Minerals.shell_risk(%{base | ca_mg: nil, avp_mg: nil}).points == 0
  end
end
