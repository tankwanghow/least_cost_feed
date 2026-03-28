defmodule LeastCostFeedWeb.FormulaLive.NutritionGuide do
  use LeastCostFeedWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Layer Nutrition Guide")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="print-me" class="print-here">
      <style>
        .guide-page { width: 210mm; padding: 10mm 12mm; font-size: 11px; line-height: 1.4; }
        .guide-page h1 { font-size: 18px; font-weight: 800; margin-bottom: 2px; }
        .guide-page h2 { font-size: 14px; font-weight: 700; margin-top: 12px; margin-bottom: 4px; border-bottom: 2px solid #333; padding-bottom: 2px; }
        .guide-page h3 { font-size: 12px; font-weight: 600; margin-top: 8px; margin-bottom: 2px; }
        .guide-page table { width: 100%; border-collapse: collapse; margin: 4px 0; }
        .guide-page th, .guide-page td { border: 1px solid #ccc; padding: 3px 5px; text-align: left; }
        .guide-page th { background: #f0f0f0; font-weight: 600; }
        .guide-page .critical { background: #fee2e2; }
        .guide-page .recommended { background: #fef9c3; }
        .guide-page .conditional { background: #e0f2fe; }
        .guide-page .skip { background: #f0fdf4; }
        .guide-page .tag { display: inline-block; padding: 1px 6px; border-radius: 3px; font-weight: 700; font-size: 10px; }
        .guide-page .tag-critical { background: #dc2626; color: white; }
        .guide-page .tag-rec { background: #ca8a04; color: white; }
        .guide-page .tag-cond { background: #0284c7; color: white; }
        .guide-page .tag-skip { background: #16a34a; color: white; }
        .guide-page .note { font-size: 10px; color: #555; font-style: italic; }
        .guide-page .section-note { background: #f8fafc; border-left: 3px solid #0284c7; padding: 4px 8px; margin: 4px 0; font-size: 10px; }

        @media print {
          .guide-page { padding: 5mm 8mm; }
          .page { page-break-after: always; }
        }
        .chrome-page .page, .firefox-page .page { page-break-after: always; }
      </style>

      <%!-- PAGE 1 --%>
      <div class="page guide-page">
        <h1>Layer Feed Nutrient Constraint Guide</h1>
        <p class="note">For egg-laying hens (Hy-Line Brown type) in tropical conditions (95-110g intake/day). Values in % unless noted.</p>

        <div style="display: flex; gap: 12px; margin: 6px 0;">
          <span><span class="tag tag-critical">CRITICAL</span> Always set</span>
          <span><span class="tag tag-rec">RECOMMENDED</span> Set for most formulas</span>
          <span><span class="tag tag-cond">CONDITIONAL</span> Depends on other constraints</span>
          <span><span class="tag tag-skip">SKIP</span> Redundant / unnecessary</span>
        </div>

        <h2>Energy</h2>
        <table>
          <tr>
            <th style="width:22%">Nutrient</th>
            <th style="width:10%">Min</th>
            <th style="width:10%">Max</th>
            <th style="width:14%">Importance</th>
            <th>Notes</th>
          </tr>
          <tr class="critical">
            <td><b>ME Energy</b> (kcal/kg)</td>
            <td>2,750-2,850</td>
            <td>2,850-2,950</td>
            <td><span class="tag tag-critical">CRITICAL</span> both</td>
            <td>Without both, optimizer dumps cheap fillers (no min) or expensive fats (no max)</td>
          </tr>
        </table>

        <h2>Macro Minerals</h2>
        <table>
          <tr>
            <th style="width:22%">Nutrient</th>
            <th style="width:10%">Min</th>
            <th style="width:10%">Max</th>
            <th style="width:14%">Importance</th>
            <th>Notes</th>
          </tr>
          <tr class="critical">
            <td><b>Calcium</b> (%)</td>
            <td>4.0-4.5</td>
            <td>4.2-4.5</td>
            <td><span class="tag tag-critical">CRITICAL</span> both</td>
            <td>Eggshell quality. Too low = thin shells, too high = impairs P absorption</td>
          </tr>
          <tr class="critical">
            <td><b>Available P</b> (%)</td>
            <td>0.32-0.45</td>
            <td>0.38-0.45</td>
            <td><span class="tag tag-critical">CRITICAL</span> both</td>
            <td>Too low = weak bones/shells, too high = Ca interference, pollution</td>
          </tr>
          <tr class="recommended">
            <td><b>Sodium</b> (%)</td>
            <td>0.16</td>
            <td>0.22</td>
            <td><span class="tag tag-rec">RECOMMENDED</span> both</td>
            <td>Too low = production drop, too high = wet droppings</td>
          </tr>
          <tr class="recommended">
            <td><b>Chloride</b> (%)</td>
            <td>0.15</td>
            <td>0.22</td>
            <td><span class="tag tag-rec">RECOMMENDED</span> both</td>
            <td>Acid-base balance; excess causes wet litter</td>
          </tr>
          <tr class="conditional">
            <td><b>Potassium</b> (%)</td>
            <td>&mdash;</td>
            <td>0.80</td>
            <td><span class="tag tag-cond">CONDITIONAL</span> max only</td>
            <td>Skip min &mdash; plants supply enough. Max only if soybean meal heavy diet</td>
          </tr>
        </table>

        <h2>Amino Acids</h2>
        <div class="section-note">
          <b>General rule:</b> Skip ALL amino acid max constraints. The cost-minimizing optimizer won't over-include expensive protein. Toxicity only at levels far beyond practical ingredients.
        </div>
        <table>
          <tr>
            <th style="width:22%">Nutrient</th>
            <th style="width:10%">Min</th>
            <th style="width:10%">Max</th>
            <th style="width:14%">Importance</th>
            <th>Notes</th>
          </tr>
          <tr class="critical">
            <td><b>Methionine</b> (%)</td>
            <td>0.34-0.45</td>
            <td>&mdash;</td>
            <td><span class="tag tag-critical">CRITICAL</span> min</td>
            <td>1st limiting AA. Skip max &mdash; synthetic DL-Met is cheap, cost self-limits</td>
          </tr>
          <tr class="critical">
            <td><b>Met + Cys</b> (%)</td>
            <td>0.60-0.78</td>
            <td>&mdash;</td>
            <td><span class="tag tag-critical">CRITICAL</span> min</td>
            <td>Skip max &mdash; redundant if Met min is set</td>
          </tr>
          <tr class="critical">
            <td><b>Lysine</b> (%)</td>
            <td>0.70-0.91</td>
            <td>&mdash;</td>
            <td><span class="tag tag-critical">CRITICAL</span> min</td>
            <td>2nd limiting AA. Skip max &mdash; no toxicity at practical levels</td>
          </tr>
          <tr class="recommended">
            <td><b>Threonine</b> (%)</td>
            <td>0.48-0.66</td>
            <td>&mdash;</td>
            <td><span class="tag tag-rec">RECOMMENDED</span> min</td>
            <td>3rd limiting AA. Skip max</td>
          </tr>
          <tr class="recommended">
            <td><b>Tryptophan</b> (%)</td>
            <td>0.16-0.21</td>
            <td>&mdash;</td>
            <td><span class="tag tag-rec">RECOMMENDED</span> min</td>
            <td>Always low in practical ingredients, won't overshoot</td>
          </tr>
          <tr class="conditional">
            <td><b>Isoleucine</b> (%)</td>
            <td>0.56-0.80</td>
            <td>&mdash;</td>
            <td><span class="tag tag-cond">CONDITIONAL</span> min</td>
            <td>Skip if CP min &ge; 15% &mdash; soybean meal supplies adequate Ile</td>
          </tr>
          <tr class="conditional">
            <td><b>Valine</b> (%)</td>
            <td>0.61-0.86</td>
            <td>&mdash;</td>
            <td><span class="tag tag-cond">CONDITIONAL</span> min</td>
            <td>Skip if CP min &ge; 15% &mdash; usually adequate from intact protein</td>
          </tr>
          <tr class="conditional">
            <td><b>Arginine</b> (%)</td>
            <td>0.75-1.08</td>
            <td>&mdash;</td>
            <td><span class="tag tag-cond">CONDITIONAL</span> min</td>
            <td>Skip if CP min &ge; 15%. Skip max &mdash; no Lys-Arg antagonism in layers</td>
          </tr>
          <tr class="skip">
            <td><b>Leucine, Histidine, Phenylalanine</b></td>
            <td>&mdash;</td>
            <td>&mdash;</td>
            <td><span class="tag tag-skip">SKIP</span> both</td>
            <td>Always in excess from corn/soy. Never limiting in practice</td>
          </tr>
        </table>
      </div>

      <%!-- PAGE 2 --%>
      <div class="page guide-page">
        <h2>Crude Protein</h2>
        <table>
          <tr>
            <th style="width:40%">Condition</th>
            <th style="width:10%">Min</th>
            <th style="width:10%">Max</th>
            <th>Importance & Notes</th>
          </tr>
          <tr class="skip">
            <td>All 5 key AAs constrained (Met, M+C, Lys, Thr, Trp)</td>
            <td><span class="tag tag-skip">SKIP</span> or 13.5% floor</td>
            <td>16.5-18.0</td>
            <td><span class="tag tag-rec">REC</span> max only &mdash; prevents excess N, heat stress, cost</td>
          </tr>
          <tr class="recommended">
            <td>Only Met + Lys constrained</td>
            <td>15.0-16.0</td>
            <td>16.5-18.0</td>
            <td><span class="tag tag-rec">REC</span> both &mdash; min ensures other AAs are adequate</td>
          </tr>
          <tr class="critical">
            <td>No AA constraints at all</td>
            <td>15.0-17.0</td>
            <td>17.0-18.5</td>
            <td><span class="tag tag-critical">CRITICAL</span> both &mdash; only way to ensure protein adequacy</td>
          </tr>
        </table>

        <div class="section-note">
          <b>Why skip CP min when all AAs are set?</b> The AA minimums force the optimizer to include enough protein sources.
          A CP min on top is redundant and may increase cost. A CP <b>max</b> still prevents excess nitrogen &rarr; heat stress, wet litter, kidney load.
        </div>

        <h2>Lipids & Fiber</h2>
        <table>
          <tr>
            <th style="width:22%">Nutrient</th>
            <th style="width:10%">Min</th>
            <th style="width:10%">Max</th>
            <th style="width:14%">Importance</th>
            <th>Notes</th>
          </tr>
          <tr class="recommended">
            <td><b>Linoleic Acid</b> (%)</td>
            <td>1.0-1.5</td>
            <td>&mdash;</td>
            <td><span class="tag tag-rec">RECOMMENDED</span> min</td>
            <td>Egg size & mass. Skip max &mdash; oil inclusion is cost-limited</td>
          </tr>
          <tr class="recommended">
            <td><b>Crude Fiber</b> (%)</td>
            <td>&mdash;</td>
            <td>5.0-6.0</td>
            <td><span class="tag tag-rec">RECOMMENDED</span> max only</td>
            <td>Skip min. Max prevents gut passage issues, reduced digestibility</td>
          </tr>
          <tr class="conditional">
            <td><b>Ether Extract / Fat</b> (%)</td>
            <td>&mdash;</td>
            <td>5.0-6.0</td>
            <td><span class="tag tag-cond">CONDITIONAL</span> max only</td>
            <td>Only if oil is cheap and optimizer over-includes. Skip min</td>
          </tr>
        </table>

        <h2>Phytate Phosphorus (Phytase-Dependent)</h2>
        <table>
          <tr>
            <th style="width:40%">Condition</th>
            <th style="width:10%">Min</th>
            <th style="width:10%">Max</th>
            <th>Importance & Notes</th>
          </tr>
          <tr class="critical">
            <td>Using <b>superdosing phytase</b> (1000+ FTU)</td>
            <td>0.25-0.35</td>
            <td>&mdash;</td>
            <td><span class="tag tag-critical">CRITICAL</span> min &mdash; ensures substrate for phytase to release credited P, Ca, ME, AAs</td>
          </tr>
          <tr class="recommended">
            <td>Using <b>standard phytase</b> (500 FTU)</td>
            <td>0.20-0.25</td>
            <td>&mdash;</td>
            <td><span class="tag tag-rec">REC</span> min &mdash; lower requirement but still needed</td>
          </tr>
          <tr class="skip">
            <td><b>No phytase</b> in formula</td>
            <td>&mdash;</td>
            <td>&mdash;</td>
            <td><span class="tag tag-skip">SKIP</span> &mdash; phytate P is anti-nutritional without phytase</td>
          </tr>
        </table>

        <div class="section-note">
          <b>Why?</b> The LP optimizer treats phytase nutrient credits as fixed constants. It has no concept that phytase needs phytate substrate to work.
          Without this constraint, the optimizer may drop all phytate-rich ingredients while still crediting the phytase's P/Ca/ME release.
        </div>

        <h2>Phase-Specific Values (Hy-Line Brown, Tropical)</h2>
        <p class="note">Peak @95-100g/day, Mid @100-105g/day, Late @105-110g/day</p>
        <table>
          <tr>
            <th style="width:22%">Nutrient</th>
            <th style="width:26%">Peak (20-48 wk)</th>
            <th style="width:26%">Mid (48-70 wk)</th>
            <th style="width:26%">Late (70+ wk)</th>
          </tr>
          <tr><td>ME Energy (kcal/kg)</td><td>2,850</td><td>2,800-2,900</td><td>2,750-2,850</td></tr>
          <tr><td>Calcium (%)</td><td>4.0-4.2</td><td>4.1-4.4</td><td>4.2-4.5</td></tr>
          <tr><td>Available P (%)</td><td>0.38-0.45</td><td>0.35-0.42</td><td>0.32-0.38</td></tr>
          <tr><td>Methionine (%)</td><td>0.38-0.45</td><td>0.36-0.42</td><td>0.34-0.40</td></tr>
          <tr><td>Met + Cys (%)</td><td>0.65-0.78</td><td>0.63-0.72</td><td>0.60-0.68</td></tr>
          <tr><td>Lysine (%)</td><td>0.80-0.91</td><td>0.73-0.86</td><td>0.70-0.80</td></tr>
          <tr><td>Crude Protein (%)</td><td>16.5-18.0</td><td>15.5-16.5</td><td>14.5-15.5</td></tr>
          <tr><td>Threonine (%)</td><td>0.55-0.66</td><td>0.50-0.62</td><td>0.48-0.58</td></tr>
          <tr><td>Tryptophan (%)</td><td>0.18-0.21</td><td>0.17-0.20</td><td>0.16-0.19</td></tr>
          <tr><td>Sodium (%)</td><td>0.16-0.22</td><td>0.16-0.20</td><td>0.16-0.20</td></tr>
          <tr><td>Chloride (%)</td><td>0.15-0.22</td><td>0.15-0.21</td><td>0.15-0.21</td></tr>
          <tr><td>Linoleic Acid (%)</td><td>1.0-1.5</td><td>1.0-1.25</td><td>1.0</td></tr>
          <tr><td>Crude Fiber (%)</td><td>max 5.5</td><td>max 5.5</td><td>max 6.0</td></tr>
          <tr><td>Phytate P (%, w/ phytase)</td><td>0.25-0.35</td><td>0.25-0.30</td><td>0.20-0.25</td></tr>
        </table>

        <h2>Minimum Viable Constraint Set (14 Nutrients)</h2>
        <div style="display: flex; gap: 20px;">
          <div style="width: 50%;">
            <table>
              <tr><th>#</th><th>Nutrient</th><th>Constraint</th></tr>
              <tr><td>1</td><td>ME Energy</td><td>min + max</td></tr>
              <tr><td>2</td><td>Calcium</td><td>min + max</td></tr>
              <tr><td>3</td><td>Available P</td><td>min + max</td></tr>
              <tr><td>4</td><td>Methionine</td><td>min</td></tr>
              <tr><td>5</td><td>Met + Cys</td><td>min</td></tr>
              <tr><td>6</td><td>Lysine</td><td>min</td></tr>
              <tr><td>7</td><td>Threonine</td><td>min</td></tr>
            </table>
          </div>
          <div style="width: 50%;">
            <table>
              <tr><th>#</th><th>Nutrient</th><th>Constraint</th></tr>
              <tr><td>8</td><td>Tryptophan</td><td>min</td></tr>
              <tr><td>9</td><td>Sodium</td><td>min + max</td></tr>
              <tr><td>10</td><td>Chloride</td><td>min + max</td></tr>
              <tr><td>11</td><td>Linoleic Acid</td><td>min</td></tr>
              <tr><td>12</td><td>Crude Protein</td><td>max only</td></tr>
              <tr><td>13</td><td>Crude Fiber</td><td>max only</td></tr>
              <tr><td>14</td><td>Phytate P *</td><td>min (if phytase)</td></tr>
            </table>
          </div>
        </div>
        <p class="note" style="margin-top: 6px;">
          Sources: NRC 1994, Hy-Line Brown Management Guide, Lohmann Brown Guide, ISA Brown/Hendrix Genetics, DSM OVN Guidelines 2022.
          &nbsp; * Phytate P only required when phytase is included in the formula.
        </p>
      </div>
    </div>
    """
  end
end
