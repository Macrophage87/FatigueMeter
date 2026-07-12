# Literature Review: Modeling Cyclist Fatigue from Power, Heart Rate, and HRV

**Scope.** This review surveys the exercise-physiology and modeling literature relevant to estimating fatigue in cyclists in real time, and over a training program, from mechanical power, heart rate (HR), and beat-to-beat heart-rate variability (HRV) — in particular the short-term detrended-fluctuation-analysis exponent **DFA-α1**. No gas-exchange (VO₂) measurement is assumed on-device. It covers seven threads: (1) the physiological basis of the aerobic VO₂ slow component; (2) classic and modern VO₂-kinetics models; (3) cardiovascular/HR drift and decoupling; (4) DFA-α1 as an aerobic-threshold and fatigue marker; (5) fusion models combining power + HR + HRV; (6) state-space / Kalman approaches suitable for a wearable; and (7) residual training-scale fatigue and the within-ride productive-to-damaging transition. Additional wearable-accessible fatigue markers are summarized at the end.

**How to read the citations (revised).** Each load-bearing claim is followed by a source. The flags below describe **extraction confidence** — how sure we are the claim was read correctly from its source — **not evidence strength**. These are orthogonal: a claim can be extracted with perfect fidelity (`[confirmed]`) from a study that is itself n=8, single-group, and lab-bound. Flags: **[confirmed]** = corroborated across sources or against full text (an *extraction* check, not independent scientific replication); **[partial]** = supported with a caveat; **[unverified]** = paywalled/not fully read; **[synthesis]** = engineering inference, not a result reproduced from a source. The earlier "N–M vote" notation (e.g. "2-1", "0-3") described an internal LLM extraction-agreement process and has been **retired from the physiological claims** to avoid implying it carries epistemic weight about the biology — where it appears it means *extraction agreement*, nothing more. **Evidence strength** (sample size, independent replication, sex/modality generalizability, individual-level error) is discussed inline and summarized in §9 of the [white paper](white-paper.md). A consolidated bibliography with URLs and per-source evidence notes is in [references.md](references.md).

> **Aggregate caveat (read first).** The within-ride engine leans on a body of DFA-α1 work that is **dominated by one overlapping author cluster** (Rogers, Gronwald, and collaborators) with **uniformly small samples** (n=7–15) and, for the *fatigue-quantification* use, **mostly running** (2 of 3 studies). "Consistent across ≥4 papers" therefore means *methodological consistency within one group*, **not** independent replication. The whole system rests on a stack of n<20, predominantly male studies. Every anchor below should be read against that fragility.

---

## 1. The physiological basis of the aerobic slow component

The **VO₂ slow component** is a slowly developing rise in oxygen uptake during constant-work-rate exercise performed **above the lactate threshold**, reflecting a progressive loss of skeletal-muscle contractile efficiency and tied to the fatigue process (Jones, Grassi, Poole et al., *Slow Component of VO₂ Kinetics: Mechanistic Bases and Practical Applications*) **[confirmed]**. It is specifically a **heavy/severe-domain phenomenon** — below the first threshold there is essentially nothing to model.

Its mechanism is **multifactorial**, and this matters for how we model it:

- **Progressive recruitment of additional (type II) fibers** that are less efficient. During intense sub-maximal cycling (~80% VO₂max), additional type I and type II fibers are recruited over time in temporal association with the slow component (Krustrup et al.) **[confirmed]**. Pharmacologically blocking slow-twitch fibers (forcing greater fast-twitch recruitment) raised muscle VO₂ (425 vs 332 mL/min), increased estimated ATP turnover by 19%, lowered true mechanical efficiency (26.2% vs 30.9%), and **slowed muscle VO₂ on-kinetics (τ 55 vs 33 s)** (Krustrup et al., neuromuscular-blockade study) **[confirmed]**.
- **Metabolic instability / efficiency loss** independent of new recruitment. A "mirror-image" slow component appears in high-intensity exercise where additional recruitment is impossible **[confirmed]**. A combined NIRS-plus-EMG regression explained ~75% of slow-component dynamics after the transient phase, with **metabolic instability weighted roughly 3× recruitment** (Cannon et al., *Pflügers Archiv* 2021) **[partial — 2-1 verification vote]**.

A key correction to the older narrative: the claim that the slow component **is primarily** a change in fiber-type recruitment pattern was **refuted** in adversarial fact-checking (0–3). The modern consensus is that recruitment and efficiency loss act together, with efficiency loss dominant. **Modeling implication:** an *efficiency-decay term* is a better functional form than a *recruitment-counting* term. A reconstruction study combining Henneman's size principle with the superposition principle reproduced severe-domain kinetics to ~96.4% similarity, suggesting the slow component emerges largely from fiber-type metabolic profiles rather than fatigue per se — but this remains one model among several (Keir-adjacent work, *J Physiol Sci* 2020) **[confirmed]**.

---

## 2. Classic and modern VO₂-kinetics models

### 2.1 The canonical exponential family

All standard models are built from the delayed first-order rise:

```
ΔVO₂(t) = ΔVO₂_ss · { 1 − e^[ −(t − TD)/τ ] }
```

where **τ** is the time to reach **63.2%** of the final increment and **TD** is a transport/onset delay (whippr R-package documentation; note the package rounds to "63%") **[confirmed]**.

- **Mono-exponential** (one term): fits moderate exercise below the gas-exchange threshold. It is widely criticized for **collapsing several distinct physiological processes into one parameter**, masking the underlying physiology **[confirmed]**.
- **Bi-exponential**: adds a second delayed term (the slow component; TD₂ ≈ 2 min, large τ₂) for heavy exercise.
- **Tri-exponential** (Barstow's Eq. 1): prepends a cardiodynamic term (A₀, τ₀) truncated at TD₁:

```
VO₂(t) = VO₂_baseline
       + A₀·(1 − e^[−t/τ₀])                 (Phase 1, cardiodynamic)
       + A₁·(1 − e^[−(t−TD₁)/τ₁])           (Phase 2, primary)
       + A₂·(1 − e^[−(t−TD₂)/τ₂])           (Phase 3, slow component)
```

### 2.2 Parameter values and the identifiability trap

Barstow et al. (1996, *J Appl Physiol* 81:1642–1650) give concrete heavy-exercise values at 60 rpm: TD₁ 25 s, primary amplitude A₁′ 1.54 L/min, **primary gain G₁ ≈ 11.5 mL/min/W**, τ₁ 27.7 s, **slow-component onset TD₂ ≈ 140 s (119–147 s across cadences)**, end-exercise slow amplitude A₂′ 0.37 L/min, and **relative slow component ≈ 20% (16–22%)** of the total response **[confirmed, full text read]**. Slow-component size scaled with fiber type (relative slow vs %type-I r = −0.64 to −0.83; more type II → bigger slow component) and with blood lactate (A₂′ vs Δlactate r = 0.64–0.84). Pedal rate 45→90 rpm changed only the primary gain (G₁ fell to ~9.4 mL/min/W); the slow-component parameters were largely **cadence-independent** **[confirmed]**.

The decisive implementation lesson across all sources: **the slow exponential's time constant τ₂ is not identifiable.** Barstow's τ₂ point estimates ranged from ~180 s to 6.7×10⁵ s; Bell et al. (2001, *Exp Physiol* 86(5):667–676) found τ and slow-amplitude estimates **differed significantly (P<0.05) with model/window choice** — the estimated end-exercise slow component ranged from a simple ΔVO₂(6−3 min) of **259 mL/min up to 409–833 mL/min** across exponential fits, a striking demonstration of model dependence — and forcing equal time delays on the two-/three-component models gave the best statistical fit but an **inappropriately low ΔVO₂/ΔWR and an artificially shortened phase-2 τ** (the identifiability trap) **[Bell: partial — conclusions and numbers verified from publisher metadata; per-subject τ tables still paywalled]**. Over a finite bout the slow rise is effectively **linear**. Bell's practical guidance: for heavy exercise, a three-component model over the full 6 min, or a two-component model fitted from 20 s onward, fits best; onset of the slow component estimated via a phase-3 delay is **~2 min, earlier than the arbitrary 3 min** often assumed **[confirmed]**.

### 2.3 The DALE model — the most implementable modern form

Gløersen, Colosio, Boone, Pogliaghi et al. (2022, *J Appl Physiol*; "DALE" = Delayed Adjustment and Loss of Efficiency, `10.1152/japplphysiol.00570.2021`) reparameterize kinetics as **two fiber populations** each with a fixed first-order lag, plus a **gated linear efficiency drift** replacing the ill-conditioned slow exponential **[confirmed, full text incl. open AAM]**:

```
VO₂_st(t) = A_st · (1 − e^[−(t−td_p)/τ_st])
VO₂_ft(t) = A0_ft·(1 − e^[−(t−td_p)/τ_ft])
            + { 0                                              if t < td_sc
                Ȧ·( (t−td_sc) − τ_ft·(e^[−(t−td_sc)/τ_ft] − 1) )  if t ≥ td_sc }
VO₂(t)    = VO₂_baseline + VO₂_st(t) + VO₂_ft(t)
```

Fitted values (n=8): **τ_st ≈ 28 s and τ_ft ≈ 47 s, held constant across all intensity domains**; primary delay td_p ≈ 12 s. The efficiency-drift slope **Ȧ was 16 mL·min⁻² in the heavy domain (not different from zero, p=0.17) but 88 mL·min⁻² in the severe domain (p<0.001)** — i.e. the true slow component is severe-domain-specific and switches on above critical power/RCP; drift onset td_sc ≈ 72 s (heavy) / 118 s (severe) **[confirmed]**. Model selection was statistically a wash against the conventional 3-phase model (BIC favored DALE by 9.3; AICc favored conventional by 1.8) but DALE uses fewer free parameters (12 vs 15) and is far better conditioned **[confirmed]**.

**Why DALE is the right on-device form:** it fixes the kinetics to two global constants (no per-domain τ re-estimation), replaces three correlated slow-component parameters with a single slope + onset, and — crucially — makes the mechanisms **intensity-gated by power**: below CP a delayed steady state; above CP a linear efficiency drift at ~90 mL·min⁻². Each first-order state reduces to a one-pole IIR filter (`y[k] = y[k−1] + (Δt/τ)(A[k] − y[k−1])`), O(1) per sample, no runtime curve-fitting **[synthesis, grounded in DALE]**.

*(Minor source flag: DALE's printed Eq. 3 uses `min{0, …}`, which as typeset would force a decrease; the surrounding equations, prose, and the +150 bound on Ȧ indicate this is a typo for a gated linear increase. Confirm against the published version before hardcoding.)*

---

## 3. Cardiovascular drift and aerobic decoupling

Because no gas exchange is available on-device, **HR drift is the practical window onto the slow component.** Two computations dominate:

**Cardiovascular drift (%)** — split a steady effort in half:
```
CardiacDrift(%) = (HR_secondHalf − HR_firstHalf) / HR_firstHalf × 100
```
**Aerobic decoupling (%)** — the power-to-HR ratio degradation:
```
Pw:HR_Decoupling(%) = (Pw:HR_firstHalf − Pw:HR_secondHalf) / Pw:HR_firstHalf × 100,   where Pw:HR = mean power / mean HR
```
The **verbatim equations above are from Barsumyan et al. 2026** (BMC; full open-access text) **[confirmed]**. (A *separate* paper — the *Frontiers in AI* ML study, `frai.2025.1623384` — also works on cardiovascular drift but is a different source; the two were conflated at this anchor in an earlier draft and are now kept distinct.) The industry-standard TrainingPeaks/Coggan variant substitutes **Efficiency Factor EF = Normalized Power / average HR** per half; note that the exact `EF = NP/avgHR` definition is standard Coggan doctrine but was **not** stated verbatim in the fetched primary sources **[partial]**. **Validity note:** these formulas were validated on *controlled steady* efforts and over whole intervals; applied to short rolling windows on variable outdoor rides they are a low-SNR, unvalidated-at-that-granularity adaptation (see white paper §3.1).

**Numeric thresholds (TrainingPeaks/Friel convention):** **< 5% decoupling** = well-developed aerobic endurance at that intensity; **5–8/10%** = moderate limitation or onset of fatigue; **> 8–10%** = effort was above aerobic threshold or the athlete is depleted/heat-stressed **[confirmed as coaching convention; not a validated damage threshold]**.

**Corroborating channel — cadence decline.** Barsumyan et al. (2026, *BMC Sports Sci Med Rehabil* 18(1); 17 male cyclists, 60 min at 75% FTP monthly ×5 mo, 85 paired observations) found second-half cadence decline (mean Δ −1.75 rpm, 86.6→84.8) is significantly associated with both drift metrics (mixed-model b = 0.61, p = 0.024 for drift; b = 0.58, p = 0.007 for decoupling; rmcorr r = 0.40 / 0.38): **each 1 rpm of cadence decline ≈ +0.61% cardiovascular drift and ≈ +0.58% aerobic decoupling** **[confirmed — full open-access text verified; the two drift/decoupling formulas above match this paper verbatim]**. Cadence is free in the FIT stream and lags neuromuscular fatigue, so it is a useful second vote — though the authors established **no practical cadence-drop threshold** and defer that to future work.

Machine-learning work on power+HR quantifies cardiovascular drift as a training-response/fatigue signal in cycling (frai.2025.1623384) **[confirmed the equations; model coefficients per-dataset]**.

---

## 4. DFA-α1 as a threshold and fatigue state variable

**What it is.** DFA-α1 is the short-term scaling exponent of detrended fluctuation analysis applied to the RR-interval series (box sizes 4–16 beats). It summarizes the fractal correlation structure of heart rhythm: ~1.0+ at rest (correlated), falling through ~0.75, past 0.5 (uncorrelated/white-noise-like), to <0.5 (anticorrelated) at severe intensity (Rogers, Olson, Gronwald 2020) **[confirmed]**.

**Canonical computation parameters** (identical across Rogers/Gronwald 2020, the 2021 field paper, the ultramarathon and marathon papers, and the 2022 review) **[confirmed across ≥4 sources]**:
- **Rolling 2-minute RR window**, recomputed **every 5 s** (the reference "time-varying" method).
- **DFA box/scale range 4 ≤ n ≤ 16 beats** — do not widen it.
- Per-box linear detrend; Kubios adds "Smoothn priors" (λ=500).
- **Artifact correction mandatory; reject/flag windows > 5% artifact** (validated recordings ran 0.6–3%). At 6% artifact, proportional bias becomes large.
- **RR source: a true RR-capable chest strap (Polar H10 class).** Optical/wrist HR is inadequate — DFA-α1 is exquisitely sensitive to R-peak timing resolution.

**Threshold anchors:**
- **Aerobic threshold (VT1/LT1): DFA-α1 = 0.75.** In Rogers/Olson/Gronwald 2020 (n=15) the 0.75 crossing agreed with gas-exchange VT1 extremely well: **VO₂ r=0.99, ICC=0.99, bias −0.33 mL/kg/min; HR r=0.97, bias −1.9 bpm but limits of agreement ~±10 bpm** **[confirmed for r; the ~±10 bpm individual LoA is the honest caveat]**.
- **Anaerobic threshold (VT2/RCP): DFA-α1 = 0.5.** Weaker validation; in elite cyclists r≈0.93 (power), 0.71 (HR) **[partial]**.
- **Individual variability is real:** one cohort reported VT1 at DFA-α1 = 0.68 ± 0.28 (Naranjo-Orellana), so 0.75 is a population anchor, not a universal constant. Per-athlete calibration is recommended **[confirmed]**.

**DFA-α1 as a within-ride fatigue (durability) signal — the higher-value use**, supported by three independent datasets **[confirmed as a pattern; exact TTF quarter values partly unverified/paywalled]**:
- **Ultramarathon** (n=7): after a 6-h run, treadmill DFA-α1 at the same aerobic-threshold pace fell from **0.71 → 0.32 (d=1.38)** while **HR barely moved (d=0.02)** — DFA-α1 revealed fatigue that HR concealed.
- **Marathon** (n=11): DFA-α1 fell from **0.54 (10% of race) → 0.37 (100%)**, p=.003, and kept falling in the final third even as runners slowed and HR drift was smaller.
- **Cycling time-to-task-failure** (Rogers, Fleitas-Paniagua, Trpcic, Zagatto, Murias 2025, at 95% RCP/MMSS, n=10, TTF ~46 min): metabolic responses (VO₂, lactate, glucose) were stable over Q2–Q4 while HR, DFA-α1, and respiratory frequency all drifted to task failure. **DFA-α1 fell ~1.2 (Q1) → ~0.75 (Q4)** (RM-ANOVA F=29.06, η²=0.63, p<0.001), with session-to-session repeatability (DFA-α1 ICC **0.73–0.94**, r 0.83–0.98 — matching the abstract exactly; an earlier draft mis-transcribed the ICC ceiling as 0.96) **[verified via the lead author's full-text reproduction; ANOVA and repeatability tables confirmed, the per-quarter α1 means are figure-read as the supplementary table remains paywalled]**. Note the ICC lower bound of 0.73 is only "moderate," and η²=0.63 at n=10 is in the regime where point estimates are upward-biased. **Important nuance:** not all participants reached anticorrelated (<0.5) α1 values even at task failure — failure occurred across a *range* of personal α1/fB values, and the authors caution that α1 intensity-threshold validity degrades once fatigued. This tempers any hard "α1 < 0.5 = failure" rule.

**Theoretical framing.** In the Balagué/Gronwald **Network Physiology of Exercise** view, the RR series integrates neuromuscular, metabolic, hormonal, and central inputs; progressive fatigue is theorized as the network disengaging/segregating subsystems, manifesting as loss of fractal correlation and falling α1 (a "subsystems fail before the whole system fails" dynamic) **[confirmed as the authors' framing]**.

**Concerning-state heuristics (not formally validated):** 0.75 = leaving the purely aerobic domain; ~0.5 = at/near the highest sustainable intensity. **The per-athlete signal — a drop of ≳0.3 below one's own baseline for a given power — is the defensible fatigue flag; the *absolute* <0.5 cutoff is not.** The 0.32–0.37 values sometimes cited come from **running** (ultra/marathon); the only **cycling** study found drift only to ~0.75 at task failure with **not all athletes reaching <0.5 even at failure**, so importing a running collapse magnitude into a cycling app contradicts the "cycling ≠ running" rule. The white paper accordingly uses only the per-athlete drift for gating and treats the absolute value as display-only **[synthesis]**.

---

## 5. Fusion models: power + HR + HRV

The closest existing work to the FatigueMeter target:

- **"Universal" power-to-DFA-α1 mapping** (PMC11280911; 21 male cyclists, 554 everyday workouts). Per-individual fits of `P = m·α1 + q` (linear) or `P = s/α1 + t` (hyperbolic); power at α1=0.75 and 0.5 read off the individual fit. **Crucially it is NOT universal:** representative single-workout Spearman r = −0.44 (±0.55); grouped r = −0.75 (±0.27); only **44% of single workouts / 66% of workout groups reached |r|>0.7.** The authors trust only fits with R²>0.75 and note performance validation is "pending" **[confirmed — the headline is that DFA-α1→power must be calibrated per athlete]**.
- **Rothschild et al. 2025 durability prediction** (51 cyclists, EJAP). Predicts power at VT1 *after* ~2–2.5 h of riding from pre/post decoupling: best GEE model `Post-VT1 ≈ 21.7 + 1.0·(Baseline VT1) − 0.58·ΔFR − 0.003·(ΔHR·Time) − 0.53·VO₂peak`, **R²=0.95 (0.93 bootstrap), MAE=7.2 W**; strongest single predictor is **HR decoupling (r_rm = −0.76)** **[confirmed]**. **Caveats:** (1) this is an **in-sample GEE with 5 predictors including an interaction term on n=51** — an R²=0.95 for a noisy physiological prediction should trigger *overfitting* suspicion, not be paraded as out-of-sample accuracy; the durable takeaway is the *ranking* (HR decoupling is the dominant, cheapest marker), not the R². (2) The full model needs respiratory frequency (ΔFR) and VO₂peak, so it is not directly implementable on a power+HR+RR device, and it is a pre/post test-battery model rather than a within-ride estimator.

No source provides a single fused real-time fatigue algorithm; combining these into an on-ride signal is an engineering synthesis (see the white paper).

---

## 6. State-space / Kalman approaches for a wearable

Three sources bracket the design space **[all three URLs live and correctly extracted]**:

- **"From Lab to Wrist"** (arXiv 2505.00101) — a *neural* Kalman filter for running HR/VO₂. Its two-state HR model `z = (level, velocity)` with a rate-clamped observation update is directly reusable. HR MAE 2.81 bpm, RMSE 4.60, R²=0.73 (831 sessions); VO₂ MAE 251 mL/min, MAPE 11.4%. **No power, no HRV, no on-device claim** **[confirmed]**.
- **PM-EKF** (arXiv 2604.26803) — the one true Extended Kalman Filter, a 5-state mechanistic gas-exchange model with HR as an *input* (via cardiac output Q = HR·SV) and IMU kinetic energy as the *measurement*. Median R²=0.72 (n=9–10, leave-one-subject-out). **Its process/measurement noise covariances and Jacobians are in supplementary material not present in the HTML — unverified and must be tuned by the implementer.** HR contributed no significant accuracy in their setup, and it assumes rapid tissue-venous equilibrium (so it does not model VO₂ on/off kinetics well) **[partial]**.
- **Non-linear instantaneous VO₂ estimation** (fphys.2022.897412) — an XGBoost model (HR% + respiratory difference + accelerometer jerk feature MADs + demographics), R²=0.94, MAE 1.83 mL/kg/min (n=29). It explicitly **cannot model transitions** and gives no fatigue state or uncertainty — the opposite of what a fatigue tracker needs **[confirmed]**.

**Takeaway:** none uses power or DFA-α1 and none has on-device VO₂, so a FatigueMeter estimator is new work, borrowing PM-EKF's *filter architecture* and 2505.00101's *level+velocity HR sub-model*. A small (≈4-state) linear Kalman filter fusing power (input) with HR and DFA-α1 (observations) is trivially real-time on a Connect IQ watch; the real compute cost is the DFA-α1 sliding-window analysis, not the filter **[synthesis]**.

---

## 7. Residual training-scale fatigue and the productive-to-damaging transition

### 7.1 Residual fatigue: Banister → CTL/ATL/TSB → ACWR

All impulse-response models share one idea: each workout deposits a training impulse that decays; current state is the running sum.

**Daily load primitives.**
- **Banister TRIMP (HR):** `TRIMP = duration(min) · ΔHR_ratio · Y`, `ΔHR_ratio = (HR_ex − HR_rest)/(HR_max − HR_rest)`, `Y = 0.64·e^(1.92·x)` (men) / `0.86·e^(1.67·x)` (women) **[partial — the female coefficient appears as both 0.86 and 0.64 in secondary sources; verify against Banister 1991]**.
- **TSS (power):** `TSS = (sec·NP·IF)/(FTP·3600)·100 = duration(h)·IF²·100`, with `IF = NP/FTP`; 1 h at FTP = 100 TSS **[confirmed]**.

**Banister fitness-fatigue model:**
```
P(t) = p0 + k1·Fitness(t) − k2·Fatigue(t)
Fitness(t) = Σ w(i)·e^[−(t−i)/τ1],   Fatigue(t) = Σ w(i)·e^[−(t−i)/τ2]
```
Canonical (illustrative, athlete-specific in practice): **τ1 ≈ 45 days (fitness), τ2 ≈ 15 days (fatigue), k1 = 1, k2 ≈ 2**. Because τ2 < τ1, fatigue decays faster than fitness — the basis of tapering **[partial — canonical starting values, not universal constants; model is known to be ill-conditioned]**.

**Performance Manager Chart (implement this):**
```
CTL_today = CTL_yesterday + (TSS_today − CTL_yesterday)·(1/42)      "Fitness"
ATL_today = ATL_yesterday + (TSS_today − ATL_yesterday)·(1/7)       "Fatigue"
TSB_today = CTL_yesterday − ATL_yesterday                           "Form"
```
CTL is the 42-day, ATL the 7-day EWMA of daily TSS; TSB = Form **[confirmed]**. Real numbers for a trained cyclist: CTL 70–90 = solid, 100–150 = high-performance band; ramping CTL faster than ~5–8 points/week courts trouble; a hard 3-h ride ≈ 200–300 TSS. **TSB bands** — TrainingPeaks' own published range is only ±10 (>+10 fresh, <−10 fatigued); the widely-taught Friel bands (+25→+5 tapered/race-ready; +5→−10 grey; −10→−30 productive overload; **<−30 high overreaching risk**) are **coaching convention, not peer-reviewed cutoffs** **[partial — ship as configurable defaults]**.

**Acute:Chronic Workload Ratio (ACWR):** `ACWR = 7-day acute / 28-day chronic`; "sweet spot" **0.8–1.3**, ">1.5" danger zone. Use the **uncoupled** or EWMA form (λ=2/(N+1)). **Heavily critiqued:** mathematical coupling produces spurious associations (Lolli 2019); Impellizzeri (2020/2021) document ecological fallacy, arbitrary discretization, and regression-to-the-mean, and argue against ACWR for injury prediction. **Recommendation: ship as a descriptive load-ramp monitor, not a predictive alarm** **[confirmed]**.

**Overreaching continuum (Meeusen et al. 2013 consensus):** Functional overreaching recovers in **days–2 weeks** (then supercompensates); non-functional overreaching in **weeks–months**; overtraining syndrome in **>2 months**. HRV markers: resting vagal HRV (**RMSSD**) trends down toward NFOR/OTS; reported figures include RMSSD ~25 ms distinguishing OTS (AUC 0.91) and NFOR vs control 74.6 ± 23.8 vs 107.6 ± 20.2 ms — **but absolute values are highly individual; a personal 7-day rolling RMSSD baseline with ±1 SD bands is far more actionable than any universal cutoff**, and some functionally-overreached endurance athletes show transient HRV *elevation* (direction alone can mislead) **[partial — small-sample studies]**.

### 7.2 The productive-to-damaging transition within a ride

**Honest framing:** there is **no published, validated marker** for the exact moment further riding stops building fitness and starts only accumulating damage. What exists is a set of quantified adjacent phenomena that can proxy "the productive window is closing" — to be messaged probabilistically, never as "damage now" **[confirmed as an honest gap statement]**.

**Durability drift — the most quantifiable piece.** Maunder et al. (2021, *Sports Medicine*) define **durability** as "the time of onset and magnitude of deterioration in physiological-profiling characteristics over time during prolonged exercise." Concrete numbers:
- After ~2 h at 90% VT1 (~1,400 kJ): power at VT1 fell **217 → 196 W (−21 ± 12 W, ~10%)**; HR at that boundary rose 142 → 151 bpm; individual range 9–44 W **[confirmed]**.
- After 150 min at 90% VT1 (~1,680 kJ): VT1 power **211 → 198 W (−6%)** and 5-min TT power **333 → 302 W (−9%)**, the two correlated (rs=0.719) **[confirmed]**.
- The decline is **non-linear** — it accelerates late **[confirmed]**.
- **Intensity, not volume, drives it** (Spragg et al. 2024): ~2,000 kJ of low-intensity work produced no significant power-profile change, but the same kJ with 5×8 min at 105–110% CP cut 1 s power −9.1%, 15 s −10.3%, and W′ −2.98 kJ **[confirmed]**. Population kJ anchors: U23 decline after ~1,500 kJ, elite after ~2,500 kJ **[confirmed]**.

**Damage in cycling ≈ substrate depletion, not muscle injury.** Cycling is overwhelmingly concentric, so it produces far less exercise-induced muscle damage than running (CK/IL-6 rise after eccentric but not concentric exercise; matched bouts show higher IL-6 after running). For a single road ride the driver is **glycogen depletion**: trained cyclists hold ~400–500 g muscle + ~80–100 g liver glycogen (~90–120 min hard unfuelled); a hard 3-h ride can deplete muscle stores 70–80%; "bonk" appears ~75 min (poorly fuelled, hard) to ~180 min (well fuelled) **[confirmed]**. Mechanistically, low-glycogen "train-low" work amplifies adaptive signaling (AMPK/PGC-1α), but *very* low glycogen attenuates PGC-1α and drives net protein degradation — a plausible adaptive-to-catabolic flip, but **no published glycogen percentage marks it, and glycogen is not measurable on-device** **[synthesis/speculation, flagged]**.

**No intra-session "marginal fatigue > marginal fitness" framework exists** in the literature; TSS/CTL/ATL/TSB and ACWR are multi-day tools, not within-ride transition detectors **[confirmed gap]**.

---

## 8. Other wearable-accessible fatigue markers (supporting sweep)

From a parallel search of the wearable-fatigue literature (Consensus), ranked by cost to add to a power+HR+RR device:

**Free now (from existing signals):**
- **Aerobic decoupling / HR drift** — best-validated durability signal (Rothschild R²=0.95, MAE 7.2 W).
- **Respiratory frequency (fR)** — a strong effort marker that tracks RPE and responds faster than HR (Nicolò et al.), and is **derivable from the RR stream itself** via respiratory sinus arrhythmia; Rogers 2025 combined DFA-α1 + fR to track durability loss.
- **Time-domain & nonlinear HRV** (RMSSD, SDNN, SD1/SD2, sample entropy) — move systematically with fatigue.
- **Cadence decline** — cheap corroborating fatigue signal (Barsumyan).

**One cheap sensor:**
- **Muscle oxygen saturation (SmO₂, NIRS)** — the most physiologically direct proxy; reliability rivals VO₂/HR (ICC 0.81–0.90); breakpoints match ventilatory thresholds.
- **Core-temperature estimation from HR** (Kalman/particle filter, RMSE ≈ 0.36–0.41 °C) — models the thermal driver of drift.

**Slow / between-session:**
- **HR recovery & HR acceleration** (HR acceleration decreases with overreaching), **CGM glucose** (substrate/overreaching, days-scale), **running dynamics** (running-only, heterogeneous).

---

## 9. Synthesis and the gap FatigueMeter fills

The literature supplies every *piece* but no assembled whole:
- A **physiologically current, identifiable slow-component form** (DALE: two fixed lags + a power-gated linear efficiency drift).
- A **validated real-time autonomic state variable** with threshold anchors (DFA-α1 = 0.75/0.5) and a demonstrated within-ride fatigue drift.
- A **cheap observable of the slow component** (aerobic decoupling; HR drift; cadence decline).
- A **filter architecture** (small EKF/KF) proven feasible on wearable-grade data.
- A **mature residual-load accounting system** (TSS → CTL/ATL/TSB) with honest caveats and an overreaching continuum.
- **Durability-drift numbers** (~6–10% VT1 decline after ~1,400–1,680 kJ; intensity-driven) that quantify the closing of the productive window.

The **gap** is the fusion: no published model estimates the slow component (or fatigue, or "damage") directly from power + HR + HRV, and no framework marks the intra-ride productive-to-damaging transition. FatigueMeter composes the validated pieces into that estimator; the [white paper](white-paper.md) specifies how, and both fused estimators must be calibrated against the user's own labeled rides before their outputs are trusted.
