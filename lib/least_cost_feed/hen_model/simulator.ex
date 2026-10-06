defmodule LeastCostFeed.HenModel.Simulator do
  @moduledoc """
  Daily time-step simulation with weekly aggregation (SPEC 3).

    * `:cycle` - weeks `start_week..end_week` (18..100 max); week `w`
      covers days `7w-3 .. 7w+3` (guide knots sit at `t = 7w`); BW evolves
      from `BW_tgt(start)` by energy balance; phase-feeding programme.
    * `:snapshot` - one age at steady state: BW = guide BW, one day at `t = 7w`.

  Daily chain: potential (Genotype) → requirements (Energy, AminoAcids) →
  intake (Intake) → population response (Population) → lay/EW split and BW
  (Partition) → shell risk (Minerals, on weekly means) → economics.
  """

  alias LeastCostFeed.HenModel.{
    AminoAcids,
    Diet,
    Economics,
    Energy,
    Genotype,
    Intake,
    Minerals,
    Params,
    Partition,
    Population,
    Scenario,
    Stats
  }

  @doc "Runs a scenario. Returns `{:ok, result}` or `{:error, message}`."
  def run(%Scenario{} = scenario) do
    s = Scenario.resolve(scenario)

    cond do
      s.programme == [] ->
        {:error, "No formula selected"}

      Enum.any?(s.programme, &(not match?(%Diet{}, &1.diet))) ->
        {:error, "Programme contains an invalid diet"}

      s.mode == :cycle and s.end_week < s.start_week ->
        {:error, "End week must be after start week"}

      true ->
        ctx = context(s)
        {:ok, if(s.mode == :snapshot, do: snapshot(s, ctx), else: cycle(s, ctx))}
    end
  end

  @doc "Builds the resolved constants for a run (exposed for tests and the UI)."
  def context(%Scenario{} = s) do
    ov = s.overrides
    eq = s.energy_equation

    km =
      case s.energy_scaling do
        :guide_anchored -> Energy.guide_anchor_km(s.edition, eq, s.anchor_ref_temp, ov)
        :published -> Params.value("me_maint_scalar", ov)
      end

    ecoef = Energy.coefficients(eq, ov)

    %{
      ov: ov,
      km: km,
      h: Energy.housing_factor(s.housing, ov),
      eq: eq,
      ecoef: ecoef,
      cal: Genotype.default_calibration(ov),
      aa_coefs: AminoAcids.coefficients(s.aa_maint_set, ov),
      lambda: Params.value("intake_aa_drive_lambda", ov),
      headroom: Params.value("intake_cap_headroom", ov),
      cap_heat: Params.value("intake_cap_heat", ov),
      heat_threshold: Params.value("heat_lay_threshold", ov),
      heat_lay_slope: Params.value("heat_lay_slope", ov),
      split: Params.value("aa_deficit_split_lay", ov),
      ew_heat: %{
        ref: Params.value("heat_egg_wt_ref_temp", ov),
        s1: Params.value("heat_egg_wt_23_27", ov),
        s2: Params.value("heat_egg_wt_above_27", ov)
      },
      hens: Stats.population_design(s.n_hens, Params.value("geno_corr_emax_bw", ov)),
      pop: %{
        sigma_e: Params.value("geno_sigma_emax", ov),
        bw_cv: Params.value("geno_bw_cv", ov),
        aa_coefs: AminoAcids.coefficients(s.aa_maint_set, ov),
        egg_coef: ecoef.egg,
        gain_coef: ecoef.gain,
        energy_limit: s.energy_limit,
        maint_scale:
          if(eq == :emmans,
            do: fn ratio -> ratio end,
            else: fn ratio -> :math.pow(ratio, 0.75) end
          )
      }
    }
  end

  @doc "One simulated day. Returns a map of daily outputs including `:bw_next` (kg)."
  def day(s, ctx, t, w, diet) do
    pot = Genotype.potential(s.edition, t, ctx.cal)
    temp = s.temp_c

    lay_pot =
      pot.lay * max(0.0, 1.0 - ctx.heat_lay_slope / 100.0 * max(0.0, temp - ctx.heat_threshold))

    ew_pot = pot.ew * ew_heat_factor(s, ctx, temp)
    emax = lay_pot * ew_pot / 100.0
    wg_pos = max(pot.wg_tgt, 0.0)

    maint = Energy.maintenance(ctx.eq, w, temp, s.feather, ctx.km, ctx.h, ctx.ov)
    me_req = maint + ctx.ecoef.gain * wg_pos + ctx.ecoef.egg * emax
    req = AminoAcids.requirement(ctx.aa_coefs, emax, w)

    intake =
      Intake.desired(
        me_req,
        diet.me,
        req,
        diet.sid,
        ctx.lambda,
        pot.fi_guide,
        ctx.headroom,
        ctx.cap_heat,
        temp,
        ctx.heat_threshold
      )

    fi = intake.fi
    pop = Population.respond(ctx.hens, emax, w, fi, diet, maint, wg_pos, ctx.pop)
    {lay, ew} = Partition.split(pop.r, lay_pot, ew_pot, ctx.split)
    egg_mass = lay * ew / 100.0

    surplus = fi * diet.me - maint - ctx.ecoef.egg * egg_mass
    dw = Partition.bw_change(surplus, ctx.ecoef)

    %{
      t: t,
      lay: lay,
      ew: ew,
      egg_mass: egg_mass,
      emax: emax,
      fi: fi,
      fi_energy: intake.fi_energy,
      fi_aa: intake.fi_aa,
      intake_driver: intake.driver,
      me_intake: fi * diet.me,
      bw_g: w * 1000.0,
      bw_next: w + dw / 1000.0,
      liv: pot.liv,
      limiting: pop.limiting,
      ca_mg: diet.ca && fi * diet.ca,
      avp_mg: diet.avp && fi * diet.avp,
      sid_intake: Map.new(diet.sid, fn {aa, c} -> {aa, c && fi * c} end),
      sid_req: req
    }
  end

  defp ew_heat_factor(%{heat_egg_weight: :explicit}, ctx, temp) do
    %{ref: ref, s1: s1, s2: s2} = ctx.ew_heat
    band = min(max(temp - ref, 0.0), 27.0 - ref)
    above = max(temp - 27.0, 0.0)
    1.0 - s1 / 100.0 * band - s2 / 100.0 * above
  end

  defp ew_heat_factor(_, _ctx, _temp), do: 1.0

  defp diet_for_week(programme, wk) do
    sorted = Enum.sort_by(programme, & &1.from_week)
    (Enum.filter(sorted, &(&1.from_week <= wk)) |> List.last() || hd(sorted)).diet
  end

  defp feed_price(s, diet), do: s.feed_price_per_kg || diet.cost_per_kg

  defp cycle(s, ctx) do
    t0 = 7 * s.start_week - 3
    w0 = Genotype.potential(s.edition, t0, ctx.cal).bw_g / 1000.0

    {weeks, _w, _cum} =
      Enum.reduce(
        s.start_week..s.end_week,
        {[], w0, %{eggs: 0.0, mass: 0.0, feed: 0.0, margin: 0.0, cost: 0.0, rev: 0.0}},
        fn wk, {acc, w, cum} ->
          diet = diet_for_week(s.programme, wk)

          {days, w_end} =
            Enum.map_reduce((7 * wk - 3)..(7 * wk + 3), w, fn t, w_t ->
              d = day(s, ctx, t * 1.0, w_t, diet)
              {d, d.bw_next}
            end)

          row = aggregate(s, ctx, wk, days, diet)

          cum = %{
            eggs: cum.eggs + row.hh.eggs,
            mass: cum.mass + row.hh.mass_kg,
            feed: cum.feed + row.hh.feed_kg,
            margin: cum.margin + (row.hh.margin || 0.0),
            cost: cum.cost + (row.hh.cost || 0.0),
            rev: cum.rev + (row.hh.revenue || 0.0)
          }

          row =
            Map.merge(row, %{
              eggs_hh_cum: cum.eggs,
              egg_mass_hh_cum_kg: cum.mass,
              feed_hh_cum_kg: cum.feed,
              margin_hh_cum: cum.margin
            })

          {[row | acc], w_end, cum}
        end
      )

    weeks = Enum.reverse(weeks)
    result(s, ctx, weeks)
  end

  defp snapshot(s, ctx) do
    wk = s.snapshot_week
    t = 7.0 * wk
    w = Genotype.potential(s.edition, t, ctx.cal).bw_g / 1000.0
    diet = diet_for_week(s.programme, wk)
    row = aggregate(s, ctx, wk, [day(s, ctx, t, w, diet)], diet)
    result(s, ctx, [row])
  end

  defp aggregate(s, ctx, wk, days, diet) do
    n = length(days)
    mean = fn key -> Enum.reduce(days, 0.0, &(Map.fetch!(&1, key) + &2)) / n end
    mean_opt = fn key -> if Enum.all?(days, &is_number(Map.fetch!(&1, key))), do: mean.(key) end

    lay = mean.(:lay)

    ew =
      if lay > 0, do: Enum.reduce(days, 0.0, &(&1.lay * &1.ew + &2)) / (lay * n), else: mean.(:ew)

    egg_mass = mean.(:egg_mass)
    fi = mean.(:fi)
    liv = mean.(:liv)

    limiting =
      days
      |> Enum.flat_map(&Map.to_list(&1.limiting))
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {k, v} -> {k, Enum.sum(v) / n} end)

    {top, top_share} = Enum.max_by(limiting, &elem(&1, 1), fn -> {:potential, 1.0} end)

    price = feed_price(s, diet)
    feed_cost = Economics.feed_cost_hd(fi, price)

    revenue =
      case Enum.map(days, &Economics.revenue_hd(&1.lay, &1.ew, s.egg_pricing, ctx.ov)) do
        list -> if Enum.all?(list, &is_number/1), do: Enum.sum(list) / n
      end

    margin = if is_number(feed_cost) and is_number(revenue), do: revenue - feed_cost

    shell =
      Minerals.shell_risk(
        %{
          ca_mg: mean_opt.(:ca_mg),
          avp_mg: mean_opt.(:avp_mg),
          lay: lay,
          wk: wk,
          t_max: s.temp_max_c,
          coarse_share: s.coarse_limestone_share
        },
        ctx.ov
      )

    guide_t = 7.0 * wk
    hh = fn v -> v && v * n * liv / 100.0 end

    %{
      week: wk,
      formula: diet.name,
      formula_id: diet.formula_id,
      lay: lay,
      ew: ew,
      egg_mass: egg_mass,
      emax: mean.(:emax),
      fi: fi,
      fi_energy: mean.(:fi_energy),
      fcr: if(egg_mass > 0, do: fi / egg_mass),
      feed_per_dozen_kg: if(lay > 0, do: fi / 1000.0 / (lay / 100.0) * 12.0),
      bw_g: mean.(:bw_g),
      me_intake: mean.(:me_intake),
      liv: liv,
      intake_driver:
        days |> Enum.frequencies_by(& &1.intake_driver) |> Enum.max_by(&elem(&1, 1)) |> elem(0),
      limiting: limiting,
      top_limiting: top,
      top_limiting_share: top_share,
      ca_mg: mean_opt.(:ca_mg),
      avp_mg: mean_opt.(:avp_mg),
      sid_intake:
        Map.new(diet.sid, fn {aa, _} ->
          {aa, if(diet.sid[aa], do: Enum.reduce(days, 0.0, &(&1.sid_intake[aa] + &2)) / n)}
        end),
      sid_req:
        Map.new(ctx.aa_coefs, fn {aa, _} ->
          {aa, Enum.reduce(days, 0.0, &(&1.sid_req[aa] + &2)) / n}
        end),
      shell: shell,
      feed_price_per_kg: price,
      feed_cost_hd: feed_cost,
      revenue_hd: revenue,
      margin_hd: margin,
      margin_per_1000_week: margin && margin * 1000.0 * 7.0,
      guide: %{
        lay: Genotype.guide_curve(s.edition, "lay_pct_hd", guide_t),
        ew: Genotype.guide_curve(s.edition, "egg_wt_g", guide_t),
        fi: Genotype.guide_curve(s.edition, "feed_g_d", guide_t),
        bw_g: Genotype.guide_curve(s.edition, "bw_g", guide_t),
        egg_mass:
          Genotype.guide_curve(s.edition, "lay_pct_hd", guide_t) *
            Genotype.guide_curve(s.edition, "egg_wt_g", guide_t) /
            100.0
      },
      hh: %{
        eggs: n * lay / 100.0 * liv / 100.0,
        mass_kg: n * egg_mass / 1000.0 * liv / 100.0,
        feed_kg: n * fi / 1000.0 * liv / 100.0,
        margin: hh.(margin),
        cost: hh.(feed_cost),
        revenue: hh.(revenue)
      }
    }
  end

  defp result(s, ctx, weeks) do
    n = length(weeks)
    avg = fn key -> Enum.reduce(weeks, 0.0, &(Map.fetch!(&1, key) + &2)) / n end
    last = List.last(weeks)
    eggs_hh = Enum.reduce(weeks, 0.0, &(&1.hh.eggs + &2))
    mass_hh = Enum.reduce(weeks, 0.0, &(&1.hh.mass_kg + &2))
    feed_hh = Enum.reduce(weeks, 0.0, &(&1.hh.feed_kg + &2))
    margins = Enum.map(weeks, & &1.hh.margin)
    m1000 = Enum.map(weeks, & &1.margin_per_1000_week)

    %{
      scenario: s,
      weeks: weeks,
      km: ctx.km,
      summary: %{
        weeks: n,
        eggs_hh: eggs_hh,
        egg_mass_hh_kg: mass_hh,
        feed_hh_kg: feed_hh,
        avg_lay: avg.(:lay),
        avg_ew: avg.(:ew),
        avg_egg_mass: avg.(:egg_mass),
        avg_fi: avg.(:fi),
        fcr: if(mass_hh > 0, do: feed_hh / mass_hh),
        bw_end_g: last.bw_g,
        margin_hh: if(Enum.all?(margins, &is_number/1), do: Enum.sum(margins)),
        margin_per_1000_week: if(Enum.all?(m1000, &is_number/1), do: Enum.sum(m1000) / n),
        weeks_moderate: Enum.count(weeks, &(&1.shell.class == :moderate)),
        weeks_high: Enum.count(weeks, &(&1.shell.class == :high))
      },
      diets: s.programme |> Enum.map(& &1.diet) |> Enum.uniq_by(&{&1.formula_id, &1.name}),
      flagged_params: Params.flagged()
    }
  end
end
