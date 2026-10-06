# Open questions for Tan Kwang How

Ordered by how much each blocks the build. Section references point to SPEC.md.

## A. Blocking for v1

1. **Push your local `main`, or share `efc_data/`.**
   - GitHub `main` has no `efc_data/` folder (README, sources, equations, breed CSVs, predict.py all return 404).
   - The EFC Optimizer page on GitHub is only the spec generator; `EfcPredict.predict/2` isn't wired to it.
   - Your 9 unpushed commits probably change this. I need them to:
     - reconcile the design
     - avoid duplicating work
     - base the pull request on current code
2. **Your layer formulas in LCF.**
   - Which formulas do you feed Hisex Brown hens?
   - What is the phase programme (age ranges per formula)?
   - Is each formula optimised, so it has `actual` values?
   - Two or three real formulas are needed as test fixtures and as the first comparison.
3. **Nutrient names and units in your LCF account (tankwanghow).** Exact names for:
   - ME (and whether it's kcal/g)
   - CP
   - the 8 AAs (total? any "Dig." or "SID" versions?)
   - Ca, available P, Na, Cl, linoleic acid

   **If you have "Dig." nutrients, are they SID (standardized ileal) or AFD (apparent faecal)?** This decides digestibility route A, B or D (SPEC §5.3).
4. **Digestibility approach.** Do you agree to replace the flat 0.85 with per-ingredient SID (route C)? That needs:
   - a mapping of each LCF ingredient to a CVB feedstuff, or your own SID % per ingredient (e.g. from your premix supplier, Evonik AMINODat or Rostagno tables)
   - which ingredients are synthetic AAs (counted as 100% digestible)

   Optionally: should I add SID AA nutrients to your ingredient compositions, so the optimiser can formulate on SID directly? This is the best long-term option.
5. **House temperatures.** Typical daily mean and maximum by month for your layer houses, and whether they're open-sided or closed (tunnel-ventilated). The model is sensitive to temperature through intake and maintenance energy.
6. **Egg pricing.**
   - Sold per egg by grade, per tray, or per kg?
   - Your grade bands (g) and current prices per grade.
   - The Malaysian AA–F bands I found (AA >70, A 65–70, B 60–65, C 55–60, D 50–55, E 45–50, F <45 g) come only from secondary web sources. Please confirm.
7. **Feed price.** Use the LCF formula cost (cost per 1000 kg from ingredient costs, soon linked to FullCircle purchase prices), or a separate delivered price that includes milling and transport?

## B. Needed for calibration (v2)

8. **Flock records.** Weekly per flock, for as many past flocks as you have. Spreadsheet or CSV is fine; the format is in SPEC §7.
   - Columns: flock id/house, hatch date or age (wk), hens alive, mortality, total eggs (or hen-day %), egg kg or average egg weight, feed used (kg), formula fed.
   - Optional: body weight and uniformity, house temperature, grade counts.
   - Where do these live today? FullCircle, a spreadsheet, or peggy.asia? If peggy.asia already holds farm KPST data, I could read it from there.
9. **Strain and housing.** Are all flocks Hisex Brown, in cages? Any barn or free-range flocks (the model adds +9% / +12% maintenance energy for those)?
10. **Feather condition.** Do you score feather cover in older flocks? The model takes a 0–1 score; the default is fully feathered.
11. **Limestone.** What share of the limestone is coarse (2–4 mm)? It feeds the shell-risk index (Hendrix recommends 70% coarse for brown layers in production).

## C. Design choices for you

12. **Guide edition.** Use the Hisex Brown **S.E. Asia** cage guide (peak 97.0%, 480 eggs to 100 wk, BW 1948 g), as I propose, or the **global** edition (peak 97.5%, 484 eggs, BW 1900 g)?
13. **Energy model.**
    - The published Sakomura equation predicts 3–9% less feed than the Hisex guide's 115 g/d.
    - Options:
      - (a) keep it as published and let calibration on your records correct it
      - (b) "guide-anchored": scale maintenance so a guide-spec diet reproduces 115 g/d at a reference temperature you state
    - Which do you prefer, and what is the reference temperature?
14. **AA maintenance set.** Use set A (broiler-breeder pullets, all AAs; default) or set B (Bonato 2011 roosters, M+C and Thr only, about 3–6× lower)? This changes how much egg output responds to AA changes.
15. **Intake behaviour.**
    - Should hens eat more to make up an AA shortfall (full EFG theory, λ = 1), or only to meet energy (λ = 0)?
    - How much above the guide's intake can a flock eat (default +10%)?
    - Leave heat-stress intake and lay penalties off until your data calibrate them?
16. **EfcPredict.** OK to deprecate it and rebuild the EFC spec generator on the new model? That means Hisex-only and SID-based, replacing the generic brown/white specs.
17. **UI scope for the first PR.** Full cycle (18–100 wk) with phase feeding plus a single-age snapshot, or snapshot only first?
18. **Population safety margin.** For the spec generator, formulate for the average hen, or add a population margin (Reading model x × SD term)? If a margin, how much (e.g. covering 1 SD of hens)?

## D. Sources I couldn't open (would improve the model if you have access)

- Sakomura et al. 2015, *J Appl Poult Res* 24:267, Table 10 (digestible AA efficiencies for layers)
- Peguri & Coon 1993, *Poult Sci* 72:1318 (hen feather cover × temperature energy equation)
- Marsden & Morris 1987, *Br Poult Sci* 28:693 (temperature effects on intake and egg output)
- Nonis & Gous 2008, *SAJAS* 38:75 (AA maintenance)
- Evonik AMINODat or Rostagno 2024 SID tables (tropical ingredients missing from CVB, e.g. local palm kernel and copra grades)
