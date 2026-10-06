# Digital Hisex Brown Laying Hen: science and design spec

> Copied into the repo on 2026-10-06 when v1 was implemented. The companion data files now live in
> `priv/hen_model/` (`derive.py` replaces `scripts/derive.py`); `scripts/parse_hisex.py`,
> `write_params.py` and the `ref/` source PDFs are not committed. Implementation notes, the
> parameters added during implementation and the validation status are in `priv/hen_model/README.md`.

*Target codebase:* LeastCostFeed (Phoenix 1.8 / LiveView 1.1, Elixir ~> 1.19), repo `tankwanghow/least_cost_feed`.
*Status:* design spec v0.1, 2026-10-06. Nothing is implemented yet.
*Companion files:*
- `parameters.csv`: every coefficient, with source and status
- `hisex_brown_targets.csv`: weekly genotype targets
- `hendrix_daily_nutrients.csv`: Hendrix phase requirements
- `sid_coefficients_cvb2017.csv`: per-ingredient SID
- `sources.md`: bibliography (S1…S35)
- `open_questions.md`
- `scripts/`: reproducible parsing and derivations (`parse_hisex.py`, `derive.py` → `derived.json`, `write_params.py`)
- `ref/`: downloaded source PDFs and text

**Parameter status legend (used in `parameters.csv`):**
- **SOURCED**: the value as printed in a cited source.
- **DERIVED**: arithmetic on SOURCED numbers only. The arithmetic is in `scripts/derive.py`, so anyone can reproduce it.
- **ASSUMED**: a design or biological assumption with no direct source. The reason is given.
- **PLACEHOLDER**: a value is needed but not yet known. The default is neutral (usually 0 or "off") until it is sourced or calibrated.

---

## 1. Purpose and scope

The model predicts **flock-average** weekly performance of Hisex Brown hens (cage, tropical South-East Asia by default) fed one or more LeastCostFeed formulas:
- hen-day lay %
- egg weight
- egg mass
- feed intake
- FCR
- body weight
- Ca/P shell-quality risk
- margin over feed cost

Formulas can be compared side by side.

**Out of scope (stated in the UI):**
- individual hens
- disease, vaccination reactions, mycotoxins
- social and handling stress
- lighting programme and photoperiod
- water quality and restriction
- moult
- rearing-phase nutrition (the model starts at onset of lay with guide body weight)
- feather pecking

The model is only as good as its genotype targets. These are the breeder's guide (S2/S3) until it is recalibrated on Tan's flocks.

## 2. Findings that shaped the design

1. **`efc_data/` is not on GitHub `main`.** All six raw URLs return 404 and the folder is absent from the tree. It is probably in the 9 local commits on pop-os that haven't been pushed. This design is based on `lib/least_cost_feed/efc_predict.ex` and `formula_live/efc_form.ex` as they are on GitHub (S1).
2. **On GitHub, the `/formulas/efc_optimizer` page (`FormulaLive.EfcForm`) is only an "EFC Nutrient Spec Generator".**
   - It calls `EfcPredict.compute_nutrient_specs/2`, then `save_as_formula`.
   - `EfcPredict.predict/2` (performance prediction) exists but is not wired to any UI on `main`.
   - The local version may differ. Reconcile after Tan pushes (see open_questions.md).
3. **Weaknesses in the existing `EfcPredict`:**
   - flat digestibility 0.85 for all AAs and diets
   - generic "brown" specs blended from Hy-Line/Lohmann/Novogen
   - several uncited constants (e.g. `me * (1 + 0.005 (T−25))`, penalty slopes)
   - a lay curve that isn't Hisex
   - no population variation, so responses are linear-plateau "broken stick" responses rather than the curvilinear flock response the Reading model predicts (S7)
4. **The real Hisex Brown guides were obtained.**
   - SE Asia cage edition L2240-1p (S2) and global cage edition L6240-1 (S3), with weekly tables to 100 wk.
   - The **Hendrix Genetics Nutrition Guide 2025** (S4) gives daily mg/hen/day total, AFD and SID amino acids, avP, retainable P and Ca for four laying phases, plus tropical-climate and shell guidance.
   - Calibrating to these makes the model Hisex-specific without inventing coefficients.

## 3. Architecture: "potential from the guide, response from Reading/EFG"

Following Emmans/Fisher/Gous:
- A **genotype** defines the *potential* (what the hen would do if not limited by nutrients or the environment).
- **Intake** is what the hen tries to eat to meet her most-limiting need, constrained by capacity.
- **Partitioning** turns realised nutrient intake into maintenance, growth and egg output.
- A **population** of hens with varying potential converts individual linear-plateau responses into the curvilinear flock response (S7, S9, S19).

```
          ┌────────────── Genotype (Hisex SEA guide, daily-interpolated) ───────────────┐
          │ P_lay(t), P_EW(t), BW_target(t), FI_guide(t), livability(t)                  │
          │ + calibration offsets (onset shift, persistency, EW offset)                  │
          └───────────────┬─────────────────────────────────────────────────────────────┘
                          ▼   Emax(t) = P_lay·P_EW/100   (potential egg mass, g/d)
 Diet (LCF formula) ──►  Requirements (ME, 7 SID AAs, Ca, avP)  ◄── House T, feather F, housing
   ME, SID AAs, Ca, avP   │
                          ▼
                     Intake rule (EFG first-limiting, capped)
                          ▼
                     Population response (N virtual hens, Reading model, Liebig minimum)
                          ▼
                     Split egg-mass shortfall → lay % (2/3) and egg weight (1/3)
                          ▼
                     Energy balance → BW change;  Ca/P balance → shell-risk index
                          ▼
                     Economics (feed cost, egg revenue by grade, margin)
```

Simulation runs on a **daily time step**, with outputs aggregated **weekly**.

There are two modes:
- **Snapshot:** one age, steady state. This replaces the old `predict/2`.
- **Cycle:** from `start_week` (default 18) to `end_week` (default 100, max 100 because guide tables end there), with a **phase-feeding programme** `[%{from_week: 18, formula_id: a}, %{from_week: 40, formula_id: b}, …]`.

## 4. Equations

Notation:
- t = age (days); wk = t/7
- W = body weight (kg)
- T = house temperature (°C, daily mean; optional max for risk flags)
- F = feather cover score 0–1 (1 = full)
- FI = feed intake (g/d)
- E = egg output (g egg/hen/d)
- [x] = diet concentration (per g feed)

Parameter IDs in `monospace` refer to `parameters.csv`.

### 4.1 Genotype potential

From `hisex_brown_targets.csv` (edition `SEA` by default; `GLOBAL` optional), linearly interpolate weekly values to day t:

- **P_lay(t):** hen-day lay %
- **P_EW(t):** egg weight (g)
- **BW_tgt(t):** body weight (g)
- **FI_guide(t):** feed intake (g/d)
- **Liv(t):** livability (%)

**Calibration offsets (defaults neutral):**
- onset shift `δ_on` (days): P_lay(t) := P_lay(t − δ_on)
- persistency scale `ρ`: for wk > peak week, P_lay := P_peak − ρ·(P_peak − P_lay)
- egg-weight offset `δ_EW` (g)

**Potential egg mass:** Emax(t) = P_lay(t)·P_EW(t)/100 (g/d). At wk 30 (SEA) this gives 96.9 × 60.7/100 = 58.8 g/d, matching the guide's egg-mass column.

Rearing (wk 1–18) is in the targets file for reference only. v1 starts the hen at BW_tgt(start_week).

### 4.2 Energy requirement (default: Sakomura 2004, S6)

```
MEm  = k_m · W^0.75 · (165.74 − 2.37·T)                       [me_maint_a, me_maint_b, me_maint_scalar]
MEf  = W^0.75 · ΔF(T, F)                                       feather/cold increment (4.2.1)
ME_req = H · (MEm + MEf) + 6.68·WG + 2.40·E                     [me_gain, me_egg]; WG g/d, E g/d
```

- **H** = housing factor. Cage 1.00; barn/aviary 1.09; free-range/organic 1.12 (brown) [`housing_energy_*`, S4 §3.10.2]. It is applied to maintenance only, because the guide's extra energy is for activity.
- **Alternative (switchable):** Emmans 1974 brown, ME = W(140 − 2.0T) + 2E + 5ΔW (S5, verified via secondary source S5b). Note that it scales on W, not W^0.75.
- **Worked check:** W 1.804, T 25, WG 1.0, E 58.8 → 1.556 × 106.49 + 6.68 + 141.1 = **313.5 kcal/d** (unit test T1).
- **Known gap.** At 2800 kcal/kg the default equation implies FI = 112 g at wk 30 and 105 g at wk 100 (25 °C), against the guide's flat 115 g (derive.py `energy_check`). The Sakomura model therefore under-predicts guide intake by 3–9%, rising with age. Emmans brown sits about 10 g lower still. The handle for this is `me_maint_scalar` k_m (see 4.3 and §7).

#### 4.2.1 Feather cover and cold (S6, from Neme 2004 pullets)

```
LCT(F) = 24.54 − 5.65·F
ΔF(T,F) = g(T, LCT(F)) − g(T, LCT(1))
g(T,L)  = 6.73·(L − T)  if T < L ;  0.88·(T − L) if T ≥ L
```

The pullet equations are applied as an *increment relative to a fully feathered bird* on top of the hen equation. This is **ASSUMED** (`feather_term_applies_to_hens`). The hen-specific study to obtain is Peguri & Coon 1993 (S26).

In the tropics (T ≈ 26–32 °C) with F ≥ 0.5 the cold branch is inactive, and the term contributes at most about 0.88 × 5.65 × (1 − F) kcal/kg^0.75/d.

### 4.3 Amino-acid requirement of the mean hen (Reading form, SID basis)

For each AA *i* ∈ {Lys, Met, Met+Cys, Thr, Trp, Val, Ile, Arg}:

```
R_i = a_i · E + m_i · W^0.75            (mg SID/d)
```

- **m_i (maintenance):** set A (default) is Sakomura et al. 2015 (S14) for Lys, Met, Thr, Val, Ile, Arg, and Ekmay et al. 2016 (S15) for TSAA. These are **SOURCED** values, but they were measured in broiler-breeder pullets. Set B is Bonato et al. 2011 (S13) for M+C and Thr only. The Trp value is **DERIVED** (see `maint_trp`).
- **a_i (per g egg):** **DERIVED** so that R_i at the Hendrix Layer-2 reference (E = 59.0 g/d; W = 1.896 kg, the SEA guide mean for 40–65 wk) equals the Hendrix SID daily requirement (S4 Table 3).
  - Values: Lys 11.76, Met 6.07, M+C 10.58, Thr 5.59, Trp 2.88, Val 7.53, Ile 8.27, Arg 9.39 mg/g.
  - Validation: they reproduce the L3 and L4 guide figures within 0–12 mg/d (e.g. Lys 809/792 predicted vs 810/790 in the guide).
  - The implied net efficiency vs egg AA content (S10) is 0.5–1.0. Values near or above 1 (Val, Thr) show that Hendrix's figures embed safety margins and that maintenance set A is high for some AAs. The model inherits this. It is listed in Limits and should be recalibrated.

**Why not textbook efficiencies?** The verified efficiency set for layers on a digestible basis (Sakomura et al. 2015, S9, Table 10) could not be opened, and the brief forbids using unverifiable numbers. Anchoring a_i to the breeder's own Hisex/Hendrix requirement keeps the model consistent with the guide. A single per-AA `a_scalar` calibration handle lets flock data move it.

**Ca and P requirements (for the risk index, §4.8):**
- Ca output = lay% / 100 × 2.2 g (S11), with 70% supplied from feed (S4 §7).
- avP adequacy uses the Hendrix phase band (S4 Table 3) and the 250–300 mg/d floor (S8).

### 4.4 Intake rule (EFG first-limiting nutrient)

Diet concentrations: [ME] (kcal/g) and [AA_i] (mg SID/g), from §5.

```
FI_E  = ME_req / [ME]
FI_i  = R_i(Ē, W̄) / [AA_i]
FI_d  = FI_E + λ · max(0, max_i FI_i − FI_E)                    desired intake  [intake_aa_drive_lambda]
FI_cap = (1 + h) · FI_guide(t) · c_heat(T)                     [intake_cap_headroom, intake_cap_heat]
FI    = min(FI_d, FI_cap)
```

- **Theory.** Emmans & Fisher (S18) and Emmans (S17) hold that the bird eats to meet its first-limiting resource. Gous et al. 1987 (S12) showed experimentally that energy affects egg output only through intake (and hence AA intake), and that AA concentration also changes intake.
- **λ** (default 1.0 = full EFG): its magnitude was not extracted from any source, so it is **PLACEHOLDER**.
- **h = 0.10** is **ASSUMED**. The guide notes that intake capacity is limiting at onset of lay (S4 §3.10.1).
- **c_heat** = 1 by default (**PLACEHOLDER**; candidate source Marsden & Morris 1987, S32).
- `intake_energy_elasticity` (default 0) allows energy intake to rise with diet ME. S12 sourced the direction but not the magnitude.
- **Guide-anchored mode (option):** k_m is solved so that a Hendrix-spec Layer-2 diet at 2800 kcal/kg and a user-stated reference temperature T_ref reproduces FI_guide. The guide doesn't state its temperature, so T_ref is a user input. When this mode is off, k_m = 1 (pure Sakomura) or a calibrated value.

### 4.5 Population response (Reading model, S7/S9)

N virtual hens j = 1…N (default 200, numerical setting). Each hen has:
- Emax_j = Emax(t) + σ_E·z_j
- W_j = W̄·(1 + CV_W·u_j)
- z and u are standard normal (deterministic quantiles, so results are reproducible). The correlation between them is `geno_corr_emax_bw` (default 0).
- σ_E default 1.0 g/d (`geno_sigma_emax`, **ASSUMED**, back-calculated from the S4 Table 4 quintiles; probably an underestimate; sensitivity range 1–4).
- CV_W 0.069 (`geno_bw_cv`, **ASSUMED** definition of uniformity).

All hens receive the flock intake FI. This is a mean-field simplification: hens with higher Emax also eat more, which a later version can add. Each hen's egg output is the Liebig minimum:

```
E_j = max(0, min( Emax_j ,  min_i ( FI·[AA_i] − m_i·W_j^0.75 ) / a_i ,  E_energy ))
E_energy = ( FI·[ME] − H(MEm+MEf)(W_j) − 6.68·WG⁺ ) / 2.40      (energy-limited egg output)
Ē = mean_j E_j ;   r = Ē / mean_j Emax_j
```

The limiting nutrient for each hen is recorded, giving the share of the flock limited by each nutrient. It is shown in the UI as "first-limiting nutrient (% of hens)". Averaging over hens produces the diminishing-returns curve and the population optimum A_opt = a·Emax + b·BW + x·√(a²σ²E + b²σ²BW) (S9) without extra coefficients.

### 4.6 Splitting the shortfall into lay % and egg weight

The Hendrix guide (S4 §3.1) states that a reduction in egg mass from AA imbalance is about 2/3 lower rate of lay and 1/3 lower egg weight. This is implemented multiplicatively, which keeps lay × EW = Ē:

```
lay% = P_lay · r^(2/3)        EW = P_EW · r^(1/3)        egg mass = lay%·EW/100 = Ē
```

The log-share reading of "2/3 : 1/3" is an interpretation, and that is stated. Morris & Gous 1988 (S33) is the primary work on this partition (exists; figures not extracted).

### 4.7 Body weight

- Energy surplus S = FI·[ME] − H(MEm+MEf) − 2.40·Ē.
- If S > 0: WG = min(S/6.68, WG_tgt⁺ + S_excess/6.68). Growth is fat (S8), and excess energy is stored.
- If S < 0: ΔW = S / 4.34 (`me_bwloss_yield`, **ASSUMED**).
- No AA requirement for gain after onset of lay (S8: change is fat).
- **Validation only, not used as multipliers** to avoid double counting with intake (S4 §4): growth at point of lay is reduced above 24 °C and severely above 28 °C.

### 4.8 Temperature effects (S4 §4)

These enter through (i) the MEm temperature slope and (ii) the intake cap. On top of that:
- **Lay:** P_lay is reduced by `heat_lay_slope`·(T − 30)⁺. This is **PLACEHOLDER**, default 0. S4 gives only the threshold: "rate of lay generally affected above 30 °C".
- **Egg weight:** −0.4 %/°C (23–27 °C) and −0.8 %/°C (>27 °C) are **validation targets**. Test T7 checks that the intake-mediated response is about that size. If calibration shows the model misses it, an explicit EW multiplier can be switched on using those exact sourced slopes, with the intake effect then removed for EW.

### 4.9 Ca/P shell-quality risk index

The index is computed daily and reported weekly as **Low / Moderate / High**, with reasons listed. Points:

| Check | Rule | Source of anchor |
|---|---|---|
| Ca intake vs requirement | FI·[Ca] < 1.00 × Hendrix lower band → +1; < 0.95 × → +2 | S4 Table 3 bands; cut-points ASSUMED |
| Ca balance | FI·[Ca] < (lay/100 × 2.2 g × 0.70) / absorption 0.50 → +1 (absorption midpoint of S4's 30–70 % range) | S11, S4 §7; midpoint ASSUMED |
| avP low | FI·[avP] < max(250 mg, Hendrix lower band) → +1 | S8, S4 |
| avP high | FI·[avP] > 1.15 × Hendrix upper band → +1 | direction S11/S8; cut-point ASSUMED |
| Heat | T_max > 27 °C → +1 | S4 §4; threshold ASSUMED |
| Age | wk > 65 → +1 (Ca absorption falls with age) | S4 §7.6; threshold ASSUMED |
| Limestone particle (optional input) | coarse share < 0.70 → +1 | S4 Table 10 |

Score 0–1 → Low, 2–3 → Moderate, ≥4 → High. This is a **transparent rule-based index, not a predicted shell-strength value.** The guide's shell-strength target (4200 g/cm², S2) is shown as context only.

### 4.10 Flock and economics

```
hens_alive(t)        = hens_housed · Liv(t)/100                       (guide livability; override with records)
feed price (per kg)  = formula.cost / 1000                            (LCF Formula.refresh_cost = Σ cost·actual ·1000)
feed cost / hen-day  = FI/1000 · price_feed
egg revenue / hen-day:
   mode :per_kg  → lay/100 · EW/1000 · price_per_kg
   mode :per_egg → lay/100 · Σ_g p_g · P(EW_ind ∈ band_g)            EW_ind ~ N(EW, 5.0 g)   [geno_egg_wt_sd]
margin / hen-day     = revenue − feed cost
weekly: per 1000 hens alive;  cumulative: per hen housed (× Liv)
FCR = FI / egg mass  (kg feed / kg egg); also feed per 10 eggs and per dozen
```

Grade bands and prices are user inputs (`egg_grade_bands` **PLACEHOLDER**). The suggested default is the Malaysian AA…F scheme, pending Tan's confirmation. The SD of 5.0 g is **DERIVED** from the Hisex SEA grading table and validated against S2's %S/M/L/XL by week (test T9).

## 5. Reading a LeastCostFeed formula

### 5.1 What LCF stores (S1)

- `Formula`: name, batch_size, weight_unit, usage_per_day, note, virtual `cost` (per 1000 weight units).
  - `formula_nutrients`: nutrient_id, min, max, **actual**, shadow, used.
  - `formula_ingredients`: ingredient_id, cost, min, max, **actual** (fraction), shadow, used.
- `Ingredient` has many `ingredient_compositions` (nutrient_id, quantity).
- `Nutrient`: name, unit; user-scoped.
- `Entities.get_formula!/1` preloads nutrients (with name/unit) and ingredients (with compositions).

### 5.2 Nutrient name map (`HenModel.Diet`)

Names are matched case-insensitively against an alias list. The alias list is configurable and stored in `priv/hen_model/nutrient_aliases.csv`, so Tan's exact names can be added without code changes.

| Model input | Default LCF aliases (from EfcPredict, S1) | Unit handling |
|---|---|---|
| ME | "Metab. Energy Poultry", "Metab. Energy", "ME" | kcal/g (LCF stores e.g. 2.80); kcal/kg auto-detected if value > 100 |
| CP | "Crude Protein" | % |
| Lys, Met, M+C, Thr, Trp, Val, Ile, Arg | "Lysine", "Methionine", "Met + Cys", "Threonine", "Tryptophan", "Valine", "Isoleucine", "Arginine" | % total |
| SID AAs | "SID Lysine"… or "Dig. Lysine"… (see 5.3) | % |
| Ca, avP | "Calcium", "Avail. Phos" | % |
| Na, Cl, linoleic | "Sodium", "Chlorine", "Linoleic Acid" | % (warnings only) |

Concentration per g feed is `actual` / 100 × 1000 mg (for %), or kcal/g directly. If a formula has no `actual` (not optimised yet), the model computes Σ ingredient actual × composition. If neither is available it refuses, with a message.

### 5.3 Digestibility: replacing the flat 0.85

LCF holds AAs on a **total** basis. Four routes, in priority order:

- **A. SID nutrients exist in the account** (e.g. "SID Lysine"). Use them directly. Best, and the LP can also constrain on SID.
- **B. "Dig." nutrients exist.** Ask Tan whether they are SID or AFD (open question). AFD is converted using the Hendrix AFD vs SID mg/d ratios (S4 Table 3), or treated as SID with a warning.
- **C. Per-ingredient SID (recommended).** SID_i(diet) = Σ_k actual_k × totalAA_{k,i} × SIDC_{k,i}, with:
  - SIDC from **CVB 2017** (S16; 25 feedstuffs extracted to `sid_coefficients_cvb2017.csv`)
  - crystalline AAs at 100% (S16 §7.2)
  - laying hens may digest soybean meal about 2% better than broilers (S16 §6.1, not applied by default)

  Data needed:
  - a mapping **LCF ingredient → CVB feedstuff** (or an explicit SIDC per ingredient)
  - flags for synthetic AA ingredients

  v1 stores the mapping in a CSV under `priv/` or a JSON column (no migration). v2 can add `ingredient_digestibilities` (ingredient_id, nutrient_id, sidc) and, better, materialise **SID nutrients into ingredient compositions**, so routes A and C converge and the optimiser can formulate on SID.
- **D. Fallback.** Total × diet-level SID/total ratios implied by the Hendrix guide (S4 Table 3; Lys 0.886, Met 0.94, M+C 0.887, Thr 0.815, Trp 0.88, Val 0.851, Ile 0.87, Arg 0.912). These are AA-specific, unlike 0.85, but still approximate. The UI shows an "approximate digestibility" badge.

Tropical ingredients missing from CVB (e.g. some palm kernel or copra grades, local by-products) are flagged as unmapped. Rostagno 2024 (S30) is the suggested second table.

## 6. Integration into LeastCostFeed

### 6.1 Module layout

```
lib/least_cost_feed/hen_model.ex                 # public API: simulate/2, snapshot/2, compare/2, spec_for/2
lib/least_cost_feed/hen_model/params.ex          # loads priv/hen_model/parameters.csv at compile time (@external_resource); status kept for UI
lib/least_cost_feed/hen_model/genotype.ex        # loads hisex_brown_targets.csv; daily interpolation; calibration offsets
lib/least_cost_feed/hen_model/diet.ex            # LCF formula -> %Diet{me, sid: %{lys: ..}, ca, avp, cost_per_kg, warnings}
lib/least_cost_feed/hen_model/digestibility.ex   # routes A-D; loads sid_coefficients_cvb2017.csv
lib/least_cost_feed/hen_model/energy.ex          # MEm (Sakomura/Emmans), feather term, housing, ME_req
lib/least_cost_feed/hen_model/amino_acids.ex     # requirement a·E + m·W^0.75; inverse (spec generator)
lib/least_cost_feed/hen_model/intake.ex          # EFG intake rule + caps
lib/least_cost_feed/hen_model/population.ex      # virtual hens, Liebig minimum, limiting-nutrient shares
lib/least_cost_feed/hen_model/partition.ex       # 2/3-1/3 split, BW energy balance
lib/least_cost_feed/hen_model/minerals.ex        # Ca/P shell-risk index
lib/least_cost_feed/hen_model/economics.ex       # feed cost, egg revenue (per kg / per grade), margin
lib/least_cost_feed/hen_model/simulator.ex       # daily loop, weekly aggregation, phase programme
lib/least_cost_feed/hen_model/calibration.ex     # record import, fitting, stored calibrations (v2)
priv/hen_model/{parameters.csv, hisex_brown_targets.csv, hendrix_daily_nutrients.csv,
                sid_coefficients_cvb2017.csv, nutrient_aliases.csv}
```

- **Pure functions, no DB writes** in v1. Inputs are plain structs: `%HenModel.Scenario{formula_programme, start_week, end_week, temp_c, temp_max_c, feather, housing, hens_housed, edition, prices, options}`.
- **Performance:** a 82-week cycle is 574 days × 200 hens × 8 AAs ≈ 1M cheap float operations, a few ms in Elixir. Comparing 4 formulas runs in a `Task.async_stream`.
- Everything takes `user_id` and uses the existing per-user `Entities` getters for formulas, nutrients and ingredients, preserving user scoping.

### 6.2 Fate of `EfcPredict`

- **Keep it compiling in v1 and mark it `@deprecated`.** It has no other callers on `main` apart from EfcForm's spec generator. Check the local branch.
- **Re-base the spec generator on the new model.** `HenModel.spec_for(%{age_weeks, egg_mass or targets, temp, housing, intake}, user_nutrients)` computes:
  - SID AA mg/d from a·E + m·W^0.75 (population-adjusted with the S9 x·SD term; x a user choice, default 0 = mean hen)
  - Ca/avP from the Hendrix band for the phase
  - ME from §4.2 at the target intake

  It then converts to % of diet. It writes SID nutrients if the account has them, otherwise total via route D ratios. This removes `@breed_specs` and the flat 0.85. The old breed dropdown (brown/white) becomes Hisex Brown (SEA/global). Other strains can be added as more targets files later.
- **Remove `EfcPredict`** in v2, once Tan has confirmed the new outputs.

### 6.3 UI (`/formulas/efc_optimizer`)

The existing route `live "/formulas/efc_optimizer", FormulaLive.EfcForm, :efc` stays. It gains tabs (live_action or assigns):

1. **Spec generator** (existing, re-based as in 6.2).
2. **Hen simulator.**
   - Pick 1 formula, or a phase programme of formulas.
   - Inputs: start/end week, house temperature (mean/max, or a weekly table), feather score, housing, hens housed, feed price override, egg price mode (per kg or per grade with bands and prices).
   - Outputs: weekly table and charts (lay %, EW, egg mass, FI, FCR, BW against the Hisex guide lines), first-limiting nutrient by week, shell-risk badge per week, economics summary.
3. **Compare.** Choose 2–4 formulas (or programmes) with a shared scenario. Side-by-side columns and Δ vs the first column for cumulative eggs/hen housed, egg mass, average FI, FCR, BW at end, margin per hen housed and per 1000 hens per week, and weeks at Moderate/High shell risk.
   - Reuse `LeastCostFeedWeb.CompareHelpers` (exists, S1) for the table styling.
4. **Calibrate** (v2). Upload flock CSV, view fit and residuals, save calibration.

Every output panel shows a **"Model limits"** note (§9) and a **"digestibility basis"** badge (A/B/C/D). Each parameter shown in the UI carries its status (SOURCED/DERIVED/ASSUMED/PLACEHOLDER), so ASSUMED inputs are visible.

**Charts:** use the existing JS/hooks approach in the app. No new heavy dependency. A small SVG line component is enough.

### 6.4 Docs and repo hygiene

- Update `CLAUDE.md` and `.claude/skills/codebase-map/SKILL.md`. The repo's doc-drift hook expects both to change when `lib/` changes (S1).
- Add `priv/hen_model/README.md` pointing to `sources.md`.
- Ship `sources.md` and the derivation script in the repo, e.g. `priv/hen_model/derive.py`, or port it to an ExUnit test that recomputes the DERIVED values.

### 6.5 Database (v2 only)

User-scoped tables, following the existing migrations' style:
- `flocks` (user_id, name, strain, edition, hatch_date, hens_housed, housing)
- `flock_weekly_records` (flock_id, week_ending, age_wk, hens_alive, mortality, eggs_total, hen_day_pct, egg_kg, avg_egg_wt_g, feed_kg, bw_avg_g, bw_uniformity_pct, temp_mean_c, temp_max_c, formula_id, grade counts as jsonb)
- `flock_calibrations` (flock_id, params jsonb, fit_stats jsonb, fitted_at)

## 7. Calibration hook

**Input format** (CSV or the v2 table): one row per flock-week with the fields listed in 6.5. Minimum fields:
- age_wk
- hens_alive
- eggs_total (or hen_day_pct)
- egg_kg (or avg_egg_wt_g)
- feed_kg
- formula (LCF formula name or id)

Body weight and temperature are strongly recommended.

**Fitted parameters** (bounded; all others fixed):

| Parameter | Default | Bounds | Mainly identified by |
|---|---|---|---|
| δ_on onset shift (d) | 0 | −21…+21 | early lay % |
| ρ persistency scale | 1 | 0.5…2 | lay % after peak |
| δ_EW egg-weight offset (g) | 0 | −4…+4 | egg weight |
| k_m maintenance-energy scalar | 1 | 0.85…1.20 | feed intake |
| σ_E (g/d) | 1.0 | 0.5…5 | curvature when diets change |
| a_scalar (all AAs) | 1 | 0.8…1.2 | response to formula changes (only identifiable if formulas varied) |

**Method:**
1. Simulate with recorded temperatures, formula programme and hens alive.
2. Minimise weighted SSE on weekly lay %, EW, FI and BW (weights = 1/variance of each series), using Nelder–Mead with box constraints in pure Elixir. This is a ~100-line function; no new dependency.
3. **Validation:** hold out the last 20% of weeks, or one flock of several. Report RMSE and bias per series against the uncalibrated guide model.
4. Store parameters per flock. The simulator can then use "Calibrated: Flock X" instead of "Hisex guide".
5. Guard rails: refuse to fit a_scalar or σ_E unless records include at least 2 different formulas. Show parameter correlations.

## 8. Test plan (ExUnit, `test/least_cost_feed/hen_model/`)

| # | Test | Expectation |
|---|---|---|
| T1 | `Energy.me_req` Sakomura worked value | W 1.804, T 25, WG 1, E 58.8 → 313.5 ± 0.5 kcal |
| T2 | Emmans brown switch | W 1.804, T 25, ΔW 1, E 58.8 → 1.804·90 + 117.6 + 5 = 285 kcal (±1) |
| T3 | `AminoAcids.requirement` vs Hendrix | L2 exact; L3 and L4 SID within ±2% for all 8 AAs (S4 Table 3) |
| T4 | Guide reproduction | Hendrix-spec SID diet at 2800 kcal/kg, 25 °C, SEA: lay % and EW within ±3% of guide every week 20–100; BW within ±5%; FI within ±10% with k_m = 1 and ±3% in guide-anchored mode |
| T5 | Monotone, diminishing Lys response | egg mass non-decreasing and concave in dietary SID Lys; plateau at Emax |
| T6 | Gous 1987 property (S12) | two diets with equal AA:ME ratio but different ME give similar egg output when AA-limited, via intake compensation |
| T7 | Temperature | 23 → 27 °C reduces EW by about 1.6% (±1 point) with no lay change below 30 °C (S4 §4) |
| T8 | 2/3 : 1/3 split | for r < 1, log(lay/P_lay) / log(r) = 2/3 |
| T9 | Grade split | with SD 5.0 g, predicted %<53 g and %>73 g at wk 30, 50, 70, 90 within ±3 points of S2 grading |
| T10 | Identities | egg mass = lay·EW/100; FCR = FI/egg mass; cumulative eggs/hen housed at 100 wk ≈ 480 (S2) on guide diet ±3% |
| T11 | Diet mapping | kcal/g vs kcal/kg detection; alias matching; "Dig." vs "SID" routing; route C on a fixture formula (maize + SBM + synthetic Lys/Met) gives the hand-computed SID |
| T12 | Shell risk | Hendrix-midband diet at 25 °C, 40 wk → Low; Ca at 90% lower band, 70 wk, 32 °C → High |
| T13 | Economics | per-kg vs per-grade revenue on hand-checked example; feed price = formula.cost/1000 |
| T14 | Calibration recovery | synthetic records generated with δ_on = +7 d, k_m = 1.08, σ_E = 2 recovered within 10% |
| T15 | Parameters file integrity | every row has status ∈ {SOURCED, DERIVED, ASSUMED, PLACEHOLDER}; SOURCED/DERIVED rows have source_id; the DERIVED values are recomputed in a test and match the CSV |
| T16 | LiveView | simulator and compare tabs render for a user's formulas; other users' formulas are not accessible |
| T17 | Population stability | outputs change < 0.5% between N = 100 and 400 |

## 9. Limits (shown to the user)

1. Predicts **flock averages**, not individual hens. Variation between hens is represented statistically.
2. **Disease, stress, lighting**, moult, mycotoxins, water and management errors are outside the model.
3. Genetic potential is the **breeder's guide** (Hisex SEA/global, S2/S3) until calibrated. Real flocks commonly differ.
4. AA maintenance values come from **broiler-breeder pullets** (S14/S15) or roosters (S13). The pullet feather/LCT term is applied to hens. Both are assumptions.
5. The per-g-egg AA coefficients are **back-calculated from Hendrix's own requirements** (S4), which include safety margins. Responses to AA *excess* are not modelled (no imbalance or toxicity penalties).
6. The energy equation (S6) under-predicts guide intake by 3–9% without calibration.
7. The heat-stress intake cap and the direct heat lay penalty are placeholders (default off).
8. The shell-risk index is a rule-based screen, not a shell-strength prediction.
9. Egg composition is fixed (S10, S11). Age-related changes (S20) are not yet modelled.
10. Digestibility routes B and D are approximations. Use route A or C for decisions.

## 10. Delivery plan

- **PR 1 (model core, no UI change):**
  - `hen_model/*` modules and `priv/hen_model/*` data
  - tests T1–T15 and T17
  - `CLAUDE.md` and codebase-map updates
- **PR 2 (UI):** simulator and compare tabs on `/formulas/efc_optimizer`; spec generator re-based; `EfcPredict` deprecated; T16.
- **PR 3 (data, after Tan's answers):**
  - nutrient alias file for his account
  - ingredient → CVB mapping (route C)
  - optional migration adding SID nutrients to his ingredients
- **PR 4 (calibration):** v2 tables, CSV import, fitting UI, T14 with real data.
