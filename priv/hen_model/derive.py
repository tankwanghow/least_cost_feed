"""Derived parameters for the Hisex Brown model. Every input number is from a cited source
(see sources.md); this script only does arithmetic so the derivations are auditable."""
import csv, math, json
from statistics import NormalDist
N = NormalDist()
T = {}  # SEA guide targets by week
for r in csv.DictReader(open("hisex_brown_targets.csv")):
    if r["edition"] == "SEA": T[int(r["age_wk"])] = r
def bw(w): return float(T[w]["bw_g"]) / 1000
def mean_bw(a, b): ws=[w for w in range(a, b+1) if w in T]; return sum(bw(w) for w in ws)/len(ws)
def mean_em(a, b): ws=[w for w in range(a, b+1) if T[w].get("egg_mass_g_d")]; return sum(float(T[w]["egg_mass_g_d"]) for w in ws)/len(ws)

# --- S4 Hendrix Genetics Nutrition Guide 2025 vs2, Table 3: daily mg/hen/day (white & brown layers)
phases = {"L1": dict(age=(20, 40), E=59.5), "L2": dict(age=(40, 65), E=59.0),
          "L3": dict(age=(65, 90), E=57.5), "L4": dict(age=(90, 100), E=56.0)}
total = {"Lys":[945,930,915,890],"Met":[490,485,475,460],"MetCys":[850,840,825,795],"Thr":[685,675,660,650],
         "Trp":[225,220,220,210],"Val":[825,815,805,785],"Ile":[740,735,720,700],"Arg":[935,915,905,880]}
afd   = {"Lys":[805,790,775,760],"Met":[450,445,435,425],"MetCys":[740,730,720,695],"Thr":[555,545,540,530],
         "Trp":[195,195,195,185],"Val":[700,695,685,665],"Ile":[645,640,625,610],"Arg":[840,815,805,795]}
sid   = {"Lys":[835,825,810,790],"Met":[460,455,445,435],"MetCys":[755,740,730,710],"Thr":[555,545,540,535],
         "Trp":[195,195,195,185],"Val":[705,695,685,665],"Ile":[645,640,625,610],"Arg":[850,835,825,805]}
out = {}
# 1. guide-implied diet-level SID/total and AFD/total ratios (fallback digestibility)
out["sid_over_total"] = {aa: round(sum(s/t for s,t in zip(sid[aa], total[aa]))/4, 3) for aa in total}
out["afd_over_total"] = {aa: round(sum(s/t for s,t in zip(afd[aa], total[aa]))/4, 3) for aa in total}
# 2. reference BW for each phase from SEA guide
for k,p in phases.items():
    p["W"] = round(mean_bw(*p["age"]), 3); p["E_guide_table"] = round(mean_em(*p["age"]), 1)
out["phases"] = phases
# 3. egg AA content per g of whole (shell-on) egg: USDA FDC 171287 (S10) edible portion x (1 - shell fraction)
usda = {"Lys":9.12,"Met":3.80,"Cys":2.72,"Thr":5.56,"Trp":1.67,"Val":8.58,"Ile":6.71,"Arg":8.20,"CP":125.6}  # mg/g edible (CP in mg/g)
usda["MetCys"] = usda["Met"] + usda["Cys"]
shell_g = 5.5/0.95  # S11: ~5.5 g CaCO3 = ~95% of dry shell
shell_frac_60g = shell_g/60.0
out["shell_g"] = round(shell_g, 2); out["shell_frac_at_60g_egg"] = round(shell_frac_60g, 3)
egg_aa = {aa: round(v*(1-shell_frac_60g), 2) for aa,v in usda.items()}
out["egg_aa_mg_per_g_whole_egg"] = egg_aa
# 4. maintenance (digestible, mg/kg BW^0.75/d): set A = Sakomura et al. 2015 (S14) + Ekmay et al. 2016 TSAA (S15)
mA = {"Lys":81,"Met":60,"MetCys":71.48,"Thr":133,"Val":155,"Ile":94,"Arg":174}
mB = {"MetCys":26,"Thr":22}  # Bonato et al. 2011 (S13)
# Trp: no maintenance study found; split Hendrix L2 SID Trp using the maintenance share implied by
# the Reading-model Trp coefficients 2.25E + 10.25W (Wethli & Morris via Gous 1981, S8)
W2, E2 = phases["L2"]["W"], phases["L2"]["E"]
share = 10.25*W2/(2.25*E2 + 10.25*W2)
mTrp_perkgW = sid["Trp"][1]*share/W2
mTrp_perW075 = sid["Trp"][1]*share/(W2**0.75)
out["trp_maint_share"] = round(share,3); out["trp_maint_mg_per_kgW075"] = round(mTrp_perW075,1)
mA["Trp"] = round(mTrp_perW075,1)
# 5. derive egg coefficient a (mg SID AA per g egg output) so that a*E + m*W^0.75 = Hendrix L2 SID requirement
def derive(mset):
    res = {}
    for aa in sid:
        if aa not in mset: continue
        m = mset[aa]; R = sid[aa][1]
        a = (R - m*W2**0.75)/E2
        # validation: predict L1, L3, L4 with same a, m (L1 also contains growth, so expect under-prediction)
        pred = {k: round(a*p["E"] + m*p["W"]**0.75) for k,p in phases.items()}
        guide = dict(zip(phases.keys(), sid[aa]))
        k_impl = egg_aa.get(aa, float("nan"))/a if a>0 else float("nan")
        res[aa] = dict(m=m, a=round(a,2), implied_efficiency_vs_egg_content=round(k_impl,2),
                       pred=pred, guide=guide, maint_share_L2=round(m*W2**0.75/R,2))
    return res
out["deriv_setA"] = derive(mA); out["deriv_setB"] = derive(mB)
# 6. within-flock egg-weight SD from SEA grading table (normal assumption), weeks 30-90
sds=[]
for w in range(30, 91):
    r=T[w]; mu=float(r["egg_wt_g"]); pS=float(r["grade_S_lt53_pct"])/100; pXL=float(r["grade_XL_gt73_pct"])/100
    if 0<pS<1 and 0<pXL<1:
        sds.append(((53-mu)/N.inv_cdf(pS) + (73-mu)/N.inv_cdf(1-pXL))/2)
out["egg_wt_sd_g"] = dict(mean=round(sum(sds)/len(sds),2), min=round(min(sds),2), max=round(max(sds),2))
# 7. BW CV implied by uniformity >=85% within +/-10% of mean (S4 target; +/-10% definition ASSUMED)
out["bw_cv_from_uniformity85"] = round(0.10/N.inv_cdf(0.5+0.85/2),3)
# 8. Hendrix internal quintile data (S4 Table 4): spread of individual egg mass 44-66 wk
q=[59.4,58.0,58.0,58.3,56.5]
out["quintile_em_range"] = (min(q), max(q))
# 9. energy check: Sakomura 2004 (S6) laying-hen ME equation vs guide feed intake at 25 and 30 C on 2800 kcal/kg feed
def me_sak(W, T, WG, EM): return W**0.75*(165.74-2.37*T) + 6.68*WG + 2.40*EM
def me_emm_brown(W, T, WG, EM): return W*(140-2.0*T) + 2.0*EM + 5.0*WG
chk=[]
for w in [22,26,30,40,50,60,70,80,90,100]:
    W=bw(w); WG=(bw(w+1)-bw(w))*1000/7 if w+1 in T else 0.0; EM=float(T[w]["egg_mass_g_d"])
    for temp in (25,30):
        chk.append(dict(wk=w,T=temp,W=round(W,3),WG=round(WG,2),EM=EM,
            ME_sak=round(me_sak(W,temp,WG,EM)),FI_sak_2800=round(me_sak(W,temp,WG,EM)/2.8,1),
            ME_emm=round(me_emm_brown(W,temp,WG,EM)),FI_emm_2800=round(me_emm_brown(W,temp,WG,EM)/2.8,1),
            FI_guide=float(T[w]["feed_g_d"])))
out["energy_check"]=chk
json.dump(out, open("derived.json","w"), indent=1)
print(json.dumps({k:v for k,v in out.items() if k!="energy_check"}, indent=1))
for c in chk: print(c)
