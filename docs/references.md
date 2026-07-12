# References & Verification Status

Consolidated bibliography for the FatigueMeter literature review and white paper. Each entry lists what it supports and its verification status from the deep-read pass.

**Status key:** ✅ full text read & extracted · 🟡 partial (abstract-only, or paywalled full text) · ⛔ unverified / could not access · ⚠️ coaching convention, not peer-reviewed · 🧩 author's synthesis (not from a single source).

---

## VO₂ slow component — physiology

- ✅ Jones, Grassi, Christensen, Krustrup, Bangsbo, Poole. *Slow Component of V̇O₂ Kinetics: Mechanistic Bases and Practical Applications.* — https://www.researchgate.net/publication/51107457 — definition, efficiency loss, fiber recruitment, "mirror-image" slow component. *(Adversarially confirmed 3-0 on multiple claims.)*
- ✅ Krustrup et al. *The slow component of oxygen uptake … additional fibre recruitment.* — https://www.researchgate.net/publication/8890873 — type I/II recruitment temporally associated with slow component; onset ~2.6 min, amplitude ~0.24 L/min.
- 🟡 Cannon et al. (2021), *Pflügers Archiv.* — https://link.springer.com/article/10.1007/s00424-021-02573-8 — NIRS+EMG explain ~75% of slow-component dynamics; metabolic instability ~3× recruitment. *(2-1 vote on the 75% claim.)*
- ✅ Neuromuscular-blockade study (slow-twitch block raises VO₂/ATP turnover, slows kinetics). — https://www.researchgate.net/publication/23423164
- ✅ Henneman + superposition reconstruction, *J Physiol Sci* (2020). — https://link.springer.com/article/10.1186/s12576-020-00754-1 — ~96.4% reconstruction similarity.
- ✅ *V̇O₂ slow component: physiological and functional significance.* — https://www.researchgate.net/publication/15361181 — heavy-domain phenomenon. *(Note: the "primary mechanism = fiber recruitment" claim was refuted 0-3.)*

## VO₂ kinetics models

- ✅ Gløersen, Colosio, Boone, Dysthe, Malthe-Sørenssen, Capelli, Pogliaghi (2022). **DALE model**, *J Appl Physiol.* — https://journals.physiology.org/doi/full/10.1152/japplphysiol.00570.2021 (open AAM: https://air.unimi.it/bitstream/2434/1115029/3/) — τ_st≈28 s, τ_ft≈47 s, severe Ȧ≈88 mL·min⁻². *(Eq. 3 `min{0,…}` likely a typo for a gated increase.)*
- 🟡 Bell, Paterson, Kowalchuk, Padilla, Cunningham (2001), *Exp Physiol* **86(5):667–676**, PMID 11571496. — https://doi.org/10.1113/eph8602150 — mono/bi/tri-exponential comparison. **Conclusions now verified from publisher metadata:** moderate best fit = two-component or mono fitted 20 s–3 min; heavy best = three-component over full 6 min or two-component from 20 s; forcing equal time delays gives best statistical fit but an inappropriately low ΔVO₂/ΔWR and a shortened phase-2 τ (identifiability warning). Slow-component numbers: simple ΔVO₂(6−3 min)=259 mL/min; via exponential phase-3 amplitudes 409–833 mL/min (strong model dependence); phase-3 delay places onset ~2 min. *(Full-text equation typography and per-subject τ tables still paywalled; exponential forms taken from canonical open sources.)*
- ✅ whippr R package — VO₂ kinetics vignette. — https://fmmattioni.github.io/whippr/articles/vo2_kinetics.html — mono-exponential form, 63.2% τ, worked NLS example.
- ✅ Barstow et al. (1996), *J Appl Physiol* 81:1642–1650. — https://pubmed.ncbi.nlm.nih.gov/8904581/ — tri-exponential; G₁≈11.5 mL/min/W; slow onset TD₂≈140 s; relative slow ~20%; τ₂ unidentifiable; fiber/cadence scaling.
- ✅ mono-exponential critique / onset↔power r²≈0.62. — https://pmc.ncbi.nlm.nih.gov/articles/PMC5623047/

## DFA-α1 threshold & fatigue

- ✅ Rogers, Olson, Gronwald (2020), *Front Physiol.* — https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2020.596567/full — DFA-α1=0.75 ≈ VT1 (VO₂ r=0.99; HR r=0.97, ±10 bpm LoA); compute params.
- 🟡 Rogers, Gronwald (2021), *Front Sports Act Living* (field, **n=1**). — https://www.frontiersin.org/journals/sports-and-active-living/articles/10.3389/fspor.2021.668812/full — real-time on-device feasibility; 0.75/0.5 anchors.
- ✅ Rogers, Mourot, Doucende, Gronwald (2021), ultramarathon. — https://pmc.ncbi.nlm.nih.gov/articles/PMC8295593/ — α1 0.71→0.32 post-6h at same pace while HR unchanged (d=0.02).
- ✅ Gronwald/Rogers, marathon. — https://pmc.ncbi.nlm.nih.gov/articles/PMC8488837/ — α1 0.54→0.37 across race.
- ✅/🟡 Rogers, Fleitas-Paniagua, Trpcic, Zagatto, Murias (2025), durability/TTF, *EJAP* 125(6):1619–1631, PMID 39904800. — https://doi.org/10.1007/s00421-025-05716-2 — **verified via the lead author's full-text reproduction** at http://www.muscleoxygentraining.com/2025/02/dfa-a1-respiratory-rate-as-measures-of.html. Cycling TTF at 95% RCP/MMSS, n=10 (5M/5F), TTF ~46 min (Control 46.6±18.9 vs Reward 45.3±21.3, p=0.54). HR, DFA-α1, fB all drift Rest→Q4 while VO₂/lactate/glucose stay flat over Q2–Q4. **RM-ANOVA:** DFA-α1 F=29.06, η²=0.63; HR F=369, η²=0.95; fB F=58, η²=0.76 (all p<0.001). Repeatability (Table 2, Q1–Q4): DFA-α1 ICC 0.73–0.96 / r 0.83–0.97; HR ICC 0.93–0.97; fB ICC 0.93–0.96. Per-quarter DFA-α1 pattern ~1.2 (Q1) → ~0.75 (Q4) is **figure-read** (exact supplementary-table means still paywalled). **Key nuance:** not all participants reached anticorrelated (<0.5) values even at failure — failure occurred across a range of personal α1/fB values; α1 intensity thresholds lose validity once fatigued.
- ✅ Rogers & Gronwald (2022), "Update" review, *Front Physiol.* — https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2022.879071/full — artifact tolerance, H10 device note, sub-0.5 "unsustainability" framing.
- ⛔ Mobile-app DFA-α1 validity paper (10.1007/s00421-025-06037-0) — agreement stats **unverified (paywalled)**.

## Fusion: power + HR + HRV

- ✅ *Relationship of Cycling Power and Non-Linear HRV from Everyday Workout Data* (PMC11280911). — https://pmc.ncbi.nlm.nih.gov/articles/PMC11280911/ — per-individual P=m·α1+q; **not universal** (44–66% of fits usable); calibration pending.
- ✅ *Quantifying training response in cycling based on cardiovascular drift using ML*, *Front AI* (2025). — https://www.frontiersin.org/journals/artificial-intelligence/articles/10.3389/frai.2025.1623384/full — verbatim drift & decoupling equations.
- ✅ Rothschild et al. (2025), durability prediction, *EJAP.* — https://pmc.ncbi.nlm.nih.gov/articles/PMC12479576/ — GEE model R²=0.95, MAE 7.2 W; HR decoupling r_rm=−0.76. *(Needs ΔFR + VO₂peak — not fully on-device.)*
- ✅ Barsumyan, Soost, Graw, Burchard (2026), *BMC Sports Sci Med Rehabil* **18(1)**, PMID 41923151, PMCID PMC13063868, DOI 10.1186/s13102-026-01678-w. — https://pmc.ncbi.nlm.nih.gov/articles/PMC13063868/ — **full open-access text verified.** 17 male cyclists, 60 min at 75% FTP monthly ×5 mo, 85 paired obs. Drift/decoupling formulas confirmed **verbatim** (first-half − second-half ordering, matching our docs). Cadence decline 86.6→84.8 rpm (Δ−1.75 rpm, d=1.49). Regressions: drift ~ cadence b=0.61 (CI 0.10–1.13, p=0.024); decoupling ~ cadence b=0.58 (CI 0.19–0.97, p=0.007); rmcorr r=0.40 / 0.38; ≈0.61%/rpm and 0.58%/rpm. Mean drift 2.09±2.29%, mean decoupling 2.00±2.38%. **No practical numeric fatigue threshold established — authors defer to future work.**
- ⚠️ TrainingPeaks decoupling thresholds & Efficiency Factor. — https://help.trainingpeaks.com/hc/en-us/articles/204071724 · https://www.trainingpeaks.com/coach-blog/aerobic-endurance-and-decoupling/ — *(EF=NP/avgHR is standard Coggan but not stated verbatim in primary sources.)*

## State-space / Kalman for wearables

- ✅ *From Lab to Wrist* (arXiv 2505.00101). — https://arxiv.org/html/2505.00101 — neural Kalman HR/VO₂; level+velocity HR sub-model; HR MAE 2.81 bpm.
- 🟡 *PM-EKF* (arXiv 2604.26803). — https://arxiv.org/html/2604.26803 — 5-state EKF gas exchange; median R²=0.72. *(Q/R covariances & Jacobians supplementary-only — unverified.)*
- ✅ *Enhancing instantaneous oxygen uptake estimation …*, *Front Physiol* (2022). — https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2022.897412/full — XGBoost R²=0.94; cannot model transitions.

## Residual training-scale fatigue

- ✅ TrainingPeaks — *Science of the Performance Manager* (TSS/CTL/ATL/TSB). — https://www.trainingpeaks.com/learn/articles/the-science-of-the-performance-manager/ · https://help.trainingpeaks.com/hc/en-us/articles/204071884
- 🟡 Banister TRIMP. — https://www.trainingimpulse.com/banisters-trimp-0 · https://www.veohtu.com/trimp.html — *(female coefficient 0.86 vs 0.64 discrepancy across sources.)*
- 🟡 Banister/Busso fitness-fatigue (τ1≈45 d, τ2≈15 d, k1=1, k2≈2). — https://arxiv.org/pdf/2505.20859 · https://journals.humankinetics.com/view/journals/ijspp/17/5/article-p810.xml — *(illustrative, ill-conditioned in practice.)*
- ✅ ACWR + critiques (Lolli 2019; Impellizzeri 2020/2021). — https://cran.r-project.org/web/packages/ACWR/ · https://www.globalperformanceinsights.com/post/has-the-acute-chronic-workload-ratio-been-debunked
- ✅ Meeusen et al. (2013) overreaching/OTS consensus, *Eur J Sport Sci.* — https://onlinelibrary.wiley.com/doi/10.1080/17461391.2012.730061
- 🟡 HRV/RMSSD overreaching thresholds. — https://pubmed.ncbi.nlm.nih.gov/28480859/ — *(small samples; use personal baseline.)*

## Productive-to-damaging transition / durability

- ✅ Maunder et al. (2021), *Sports Medicine* — durability definition. — https://link.springer.com/article/10.1007/s40279-021-01459-0
- ✅ Stevens et al. — VT1 217→196 W after ~2 h/1,400 kJ. — https://pmc.ncbi.nlm.nih.gov/articles/PMC9488873/
- ✅ VT1 & 5-min TT drift after 150 min (rs=0.719). — https://pmc.ncbi.nlm.nih.gov/articles/PMC11322397/
- ✅ Non-linear durability decline. — https://link.springer.com/article/10.1007/s00421-024-05440-3
- ✅ Spragg et al. (2024) — intensity-driven power-profile deterioration. — https://pmc.ncbi.nlm.nih.gov/articles/PMC11235642/
- ✅ Durability systematic review (kJ anchors 1,500/2,500). — https://link.springer.com/article/10.1007/s00421-025-05885-0
- ✅ EIMD concentric vs eccentric (cycling ≈ low damage). — https://pmc.ncbi.nlm.nih.gov/articles/PMC1159298/
- 🧩 Glycogen adaptive-to-catabolic flip. — https://link.springer.com/chapter/10.1007/978-3-319-72790-5_4 · https://pmc.ncbi.nlm.nih.gov/articles/PMC11934587/ — *(no validated glycogen % threshold; speculative.)*

## Other wearable fatigue markers (supporting sweep, via Consensus)

- Rothschild 2025 durability (decoupling) · Rogers 2025 (DFA-α1 + fR durability) · Nicolò 2017/2020 (respiratory frequency) · Kao 2025 (HRV & fatigue) · Yogev 2023 / Feldmann 2022 (SmO₂ NIRS) · Dolson 2022 / Kalman CBT-from-HR 2025–2026 (core temp) · Flockhart 2023 / Coates 2023 (CGM) · Daanen 2012 / Bellenger 2016 (HR recovery) · McConnochie 2024 (IMU running dynamics). Full URLs in the earlier session sweep.

---

### Overall confidence

- **Strongest / directly usable:** DFA-α1=0.75 aerobic-threshold anchor; DALE kinetics constants; CTL/ATL/TSB accounting; durability-drift magnitudes; decoupling formulas.
- **Use with per-athlete calibration:** power→DFA-α1 mapping; Kalman seed values; kJ durability anchors.
- **Ship as configurable conventions, not validated cutoffs:** decoupling %, Friel TSB bands, ACWR zones, RMSSD absolute thresholds.
- **Explicitly speculative (label in-app):** the intra-ride "damage point"; the glycogen adaptive-flip; DFA-α1 collapse as a hard fatigue alarm.
