# Hisex Brown hen model: data files

Data and provenance for `LeastCostFeed.HenModel` (mechanistic EFG / Reading-model
laying-hen model, v1). Design spec: `docs/superpowers/specs/2026-10-06-hisex-brown-hen-model-design.md`
(open questions for Tan: `...-open-questions.md` next to it). Bibliography: [`sources.md`](sources.md) (S1…S35).

| File | Content |
|---|---|
| `parameters.csv` | **Every** coefficient the code uses, with `source_id`, location and status (SOURCED / DERIVED / ASSUMED / PLACEHOLDER). Loaded at compile time by `HenModel.Params`; code never hard-codes a coefficient. |
| `hisex_brown_targets.csv` | Weekly Hisex Brown guide tables wk 1–100 (`SEA` = S.E. Asia cage L2240-1p, default; `GLOBAL` = L6240-1). |
| `hendrix_daily_nutrients.csv` | Hendrix Nutrition Guide 2025 Table 3 (Layer 1–4, mg/hen/d). |
| `sid_coefficients_cvb2017.csv` | CVB 2017 SID coefficients for 25 feedstuffs (route C). |
| `ingredient_cvb_map.csv` | LCF ingredient name pattern → CVB feedstuff / synthetic AA. **Suggestions only** (ASSUMED) until Tan confirms (open question 4). |
| `nutrient_aliases.csv` | LCF nutrient names → model inputs (ME, total / SID / "Dig." AAs, Ca, avP, …). Add account-specific names here. |
| `derive.py` | Reproduces the DERIVED values (run from this directory). The same arithmetic is re-checked in `test/least_cost_feed/hen_model/params_test.exs` (T15). |

## Parameters added during implementation (v1)

All added rows are in `parameters.csv` with their status:

- `intake_aa_drive_lambda` value changed **1.0 → 0.0** (PLACEHOLDER): v1 default is energy-only intake (an AA shortfall does not drive extra intake), pending open question 15.
- `housing_energy_cage` 0 % (DERIVED baseline), `afd_to_sid_ratio_*` (DERIVED from S4 Table 3, route B for AFD "Dig." values).
- `guide_anchor_ref_temp` 25 °C (PLACEHOLDER), `guide_anchor_window` 40–65 wk and `guide_anchor_diet_me` 2800 kcal/kg (ASSUMED) for guide-anchored energy mode.
- `heat_egg_wt_ref_temp` 23 °C (ASSUMED) for the optional explicit EW heat multiplier.
- `cal_onset_shift_d`, `cal_persistency_scale`, `cal_egg_wt_offset_g`, `cal_aa_a_scalar` (PLACEHOLDER, neutral) calibration handles.
- `scenario_temp_mean_c` 25 °C (PLACEHOLDER), `scenario_feather_score` 1.0 (ASSUMED), `egg_price_per_kg` blank (PLACEHOLDER) UI defaults.
- `ingredient_cvb_map` (ASSUMED) pointer to the mapping file.

## Configurable model choices (defaults = pending-decision defaults)

| Option (`Scenario` field / UI) | Default | Alternatives |
|---|---|---|
| `edition` | `:sea` | `:global` |
| `energy_equation` | `:sakomura` (S6) | `:sakomura_alt`, `:emmans` (S5) |
| `energy_scaling` | `:guide_anchored` (k_m solved so mean energy-driven intake = guide intake over wk 40–65 at `guide_anchor_ref_temp`, cage, F = 1, 2800 kcal/kg) | `:published` (k_m = `me_maint_scalar` = 1.0) |
| `intake_aa_drive_lambda` (override) | 0.0 (AA shortfall does not raise intake) | 0–1 (1 = full EFG) |
| `aa_maint_set` | `:a` (S14/S15) | `:b` (S13, M+C and Thr) |
| digestibility route | `:auto` (A if SID nutrients exist, else C with D fallback per unmapped ingredient) | `:sid_nutrients` (A), `:dig_as_sid` / `:dig_afd` (B), `:cvb` (C), `:hendrix_ratio` (D) |
| `heat_egg_weight` | `:intake` (heat acts through intake only) | `:explicit` (S4 slopes −0.4 %/°C 23–27 °C, −0.8 %/°C > 27 °C on potential EW) |
| `energy_limit` | `:flock` | `:per_hen` (SPEC 4.5 literal) |
| egg pricing | per kg (no default price) | per egg with user grade bands (`egg_grade_bands` PLACEHOLDER, none shipped) |
| `EfcPredict` | kept, marked deprecated; legacy spec generator unchanged and still the default | spec generator can use `HenModel.spec_for/3` ("Hisex Brown model" basis) |

## Implementation decisions to review

1. **Energy limit at flock level** (`energy_limit: :flock`). SPEC 4.5 caps each hen with her own
   `W_j`. With one mean-field intake for all hens, that makes heavy hens energy-limited and lets light
   hens store the surplus as fat: on the Hendrix test diet it lowered lay 1.8–2.4 % and pushed BW
   +18 % by 100 wk. v1 caps the flock mean instead and makes the highest-output hens the
   energy-limited ones. The literal version stays selectable.
2. **Guide knots at `t = 7·wk` days**; simulated week `w` = days `7w−3 … 7w+3`. (The guide's 50 %
   lay at 143 d fits this better than mid-week knots.)
3. **Weeks before the first production week** have lay 0 and egg weight = first recorded value.
4. **BW** starts at guide BW for `start_week`; desired intake uses potential egg output (`Emax`).
5. **Shell risk** is evaluated on weekly means; `T_max` defaults to the mean temperature.
6. **`intake_energy_elasticity`** is carried in the CSV but not applied (form and magnitude unsourced).

## Validation status (see tests)

- T1–T3, T5, T6, T8–T13, T15, T16 (LiveView: `test/least_cost_feed_web/live/formula_live/efc_form_test.exs`), T17 pass as specified (T3: L3 Trp is 190.9 vs 195 mg/d, i.e. 2.1 %;
  accepted under the table's 5 mg/d rounding).
- **T4**: lay and EW within ±3 % and BW within ±5 % for weeks 20–100 (default mode, 25 °C).
  Feed intake: guide-anchored within ±3 % for weeks 22–85 but only ±5 % to week 100 (late
  intake 3–4 % under the guide's flat 115 g); weeks 20–21 excluded (onset intake is not
  energy-driven; model is 5–13 % below the guide). Published Sakomura: within ±10 % for weeks 22–100.
- **T7 gap**: the default intake-mediated mode does **not** reproduce the S4 egg-weight heat
  response: on a non-limiting diet EW does not change; on a tight diet lay falls too. The
  `:explicit` option reproduces −1.6 % (23→27 °C) with no lay change.
- **T14** (calibration recovery) deferred with the calibration module (v2).

## UI (`/formulas/efc_optimizer`)

- `?tab=spec`: existing spec generator; new "Basis" select (legacy `EfcPredict`, default; or "Hisex Brown model" via `HenModel.spec_for/3`; floor housing maps to barn).
- `?tab=simulator`: pick one of your formulas or a phase programme (formula + from-week rows), week range or snapshot week, house mean/max temperature, feather score, egg price (per kg, or per egg with grade bands), feed price override, and the model options above. Shows summary stats, the diet panel with the digestibility-route badge, SVG charts, the weekly table (lay %, EW, egg mass, intake, FCR, BW, shell risk, margin, limiting nutrient) and an **Assumptions & limits** panel listing every ASSUMED/PLACEHOLDER parameter, any overrides and the known limits.
- `?tab=compare`: tick 2–4 formulas; same scenario; comparison table with Δ vs the first formula and overlaid charts.
- Formulas are always loaded scoped to the signed-in user.
