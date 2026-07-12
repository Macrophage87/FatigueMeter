# FatigueMeter: A Multi-Timescale Model for Cyclist Fatigue from Power, Heart Rate, and HRV

**A design white paper**
Status: draft for implementation · Companion to [literature-review.md](literature-review.md)

---

## Abstract

FatigueMeter specifies a system that estimates cyclist fatigue on two timescales — **acute (within-ride)** and **residual (training-program)** — from three consumer signals: mechanical power, heart rate, and beat-to-beat RR intervals. It requires no gas-exchange hardware. The design rests on the observation that the aerobic **VO₂ slow component** and autonomic **complexity loss** are latent fatigue states that cannot be measured directly on a bike but can be *inferred* from how heart rate and HRV decouple from power over time. The system produces four families of output: (1) a within-ride **acute fatigue index** with a concerning-value scale; (2) live **on-ride metrics** for display; (3) a probabilistic **productive-window** signal flagging when continued riding is mostly fatigue rather than stimulus; and (4) **start-of-ride and end-of-ride** fatigue estimates that connect the residual and acute models. Every metric is tied to a specific piece of the literature, every numeric threshold carries a provenance flag, and the whole design foregrounds that the fused estimators are *new* and must be calibrated per athlete before being trusted.

---

## 1. Problem statement and design constraints

A cyclist wants to know, in the field and afterward: *How fatigued am I right now? Is this ride still doing me good, or am I just digging a hole? How much of today's fatigue did I bring with me, and how much did I add?*

**Constraints that shape every decision:**

- **Sensors:** power (1 Hz), HR (1 Hz), RR intervals (beat-to-beat). DFA-α1 **requires an RR-capable chest strap (Polar H10 class)**; wrist optical HR is not adequate (§4, literature review). No VO₂, no lactate, no NIRS assumed (but SmO₂ is an optional future input).
- **Platform:** Garmin Connect IQ (Monkey C). A small linear/extended Kalman filter is trivial to run at 1 Hz; the real compute budget is the **DFA-α1 sliding window** (recompute every 5 s, not every beat). This mirrors the known Connect IQ constraint from sibling projects that high-rate streaming work must be carefully budgeted.
- **Honesty:** the fused fatigue states are not directly validated by any single paper. Outputs must be presented as estimates with visible uncertainty, and the app must ship with a calibration path.

---

## 2. Model architecture: three coupled layers

```
                 ┌─────────────────────────────────────────────┐
   Ride history  │  LAYER 3 — Residual fatigue (days–weeks)     │
   (TSS/TRIMP)   │  CTL / ATL / TSB  +  ACWR  +  resting-HRV    │──► Start-of-ride fatigue state
                 └───────────────────────┬─────────────────────┘
                                         │ seeds
                 ┌───────────────────────▼─────────────────────┐
 power, HR, RR   │  LAYER 2 — Acute fatigue estimator (seconds) │
     (1 Hz)      │  4-state Kalman filter:                       │──► On-ride Acute Fatigue Index
                 │  HR_ss, HR, DFA-α1, F(slow/efficiency drift)  │──► End-of-ride fatigue state
                 └───────────────────────┬─────────────────────┘
                                         │ feeds
                 ┌───────────────────────▼─────────────────────┐
 power, HR, RR   │  LAYER 1 — Observable primitives             │
   + cadence     │  decoupling%, kJ (intensity-weighted),       │──► Productive-window signal
                 │  DFA-α1, cadence drift, W′bal                 │
                 └─────────────────────────────────────────────┘
```

Layer 1 computes cheap, directly-measured quantities. Layer 2 fuses them into a latent acute-fatigue state. Layer 3 accounts for the slow, residual fatigue that the athlete brings to the ride and carries away from it. The layers are coupled: Layer 3 **seeds** Layer 2's initial fatigue state (answering "start-of-ride fatigue"), and Layer 2's final state plus the ride's load **updates** Layer 3 (answering "end-of-ride fatigue" and next-day residual).

---

## 3. Layer 1 — Observable primitives (directly measured)

These require no model and are the trustworthy backbone.

### 3.1 Aerobic decoupling (rolling, real-time)
Convert the retrospective half-split into a live signal: establish a baseline **Efficiency Factor** over a stable early window (minutes 5–15), then report the running rise.
```
EF_window   = NormalizedPower_window / meanHR_window      (rolling, e.g. trailing 5–10 min)
EF_baseline = EF over minutes 5–15 at the ride's working intensity
Decoupling% = (EF_baseline − EF_window) / EF_baseline × 100
```
NormalizedPower = 4th-root of the 30 s rolling average of power⁴. **Thresholds (Friel/TrainingPeaks convention, configurable defaults, not validated damage cutoffs):** <5% healthy · 5–8% caution · >8–10% above-threshold/depleted. Suppress or annotate in high heat.

### 3.2 Intensity-weighted work (kJ clock)
```
kJ            = Σ power(W) · Δt / 1000
kJ_weighted   = Σ w(power) · power · Δt / 1000,   w(power) = 1 below CP, ramping to ~2–3× well above CP
```
Durability decline is driven by *intensity*, not raw volume (Spragg 2024). Person-specific warning anchors: ~1,500 kJ (developing/U23-like) to ~2,500 kJ (well-trained), defaulted by CTL and refined by calibration.

### 3.3 DFA-α1 (rolling)
2-min RR window, recomputed every 5 s, box sizes 4–16 beats, per-box linear detrend, **hard artifact gate at 5%** (prefer <3%). Emit both the value and a quality flag. See §4 of the literature review for the exact pipeline.

### 3.4 Cadence drift & W′bal
Second-half (or rolling) cadence decline as a corroborating fatigue vote (~0.6% expected decoupling per rpm, Barsumyan). W′bal depletion pattern from CP/W′ as an additional severe-domain fatigue input (Skiba differential form).

---

## 4. Layer 2 — Acute fatigue estimator (the core novelty)

A compact Kalman filter fuses power (a clean exogenous input) with HR and DFA-α1 (noisy, drifting observations of unobserved fatigue). This is the FatigueMeter engine, borrowing PM-EKF's filter architecture and the level+velocity HR sub-model from "From Lab to Wrist," and embedding a **DALE-style efficiency-drift state** as the on-bike analogue of the VO₂ slow component.

### 4.1 State vector
```
x = [ HR_ss , HR , A1 , F ]ᵀ
```
- `HR_ss` — quasi-steady HR the current power would elicit when fresh (bpm)
- `HR` — latent actual HR (bpm); lags HR_ss and is lifted by fatigue drift
- `A1` — latent DFA-α1 (dimensionless)
- `F` — slow cardiovascular/metabolic fatigue state = upward HR drift in bpm; 0 when fresh. **This is the on-bike proxy for the VO₂ slow component / efficiency loss.**

### 4.2 Transition equations (Δt = 1 s; discretize the first-order forms)
```
HR_ss(k)  = HR_rest + g_P · P(k)                                    # static power→HR gain
HR(k+1)   = HR(k) + (Δt/τ_HR)·(HR_ss(k) + F(k) − HR(k)) + w_HR
A1(k+1)   = A1(k) + (Δt/τ_A)·(A1_target(P(k)) − A1(k)) + w_A
F(k+1)    = F(k) + κ·max(0, P(k) − CP)·Δt − (F(k)/τ_rec)·Δt + w_F   # DALE-style gated drift
```
with the power→DFA-α1 map as a falling sigmoid crossing 0.75 at aerobic-threshold power:
```
A1_target(P) = a0 − a1 / (1 + exp(−s·(P − P_AeT)))
```
The fatigue accumulator `F` **charges only above critical power** (rate κ) and recovers with τ_rec — this is the intensity-gated efficiency drift, mirroring DALE's severe-domain Ȧ (≈88 mL·min⁻²) and its ~zero heavy-domain value.

### 4.3 Observation equations
```
HR_meas(k) = HR(k) + v_HR
A1_meas(k) = A1(k) + v_A          # large R: DFA-α1 is slow and noisy
```

### 4.4 Seed/tuning starting values (from the literature; calibrate per athlete)
| Parameter | Start value | Basis |
|---|---|---|
| τ_HR | 30 s | HR kinetics |
| τ_A | 90 s | DFA-α1 responds slowly |
| τ_rec | 900 s | within-ride partial recovery |
| g_P | ≈(HR_max−HR_rest)/P_max ≈ 0.15 bpm/W | static gain |
| CP, P_AeT | from athlete (P_AeT ≈ 0.75·FTP) | pull FTP/CP from intervals.icu (may be stale) |
| a0, a1, s | 1.1, 0.6, 0.02/W | sigmoid through α1=0.75 at P_AeT |
| κ | tuned so 30 min at CP+50 W lifts F ≈ 8–10 bpm | typical cardiac drift |
| Q | diag(0.5, 0.5, 0.002, 0.05) | process noise (tune) |
| R | diag(σ_HR², σ_A1²), σ_HR=2 bpm, σ_A1=0.15 | measurement noise |
| P₀ | diag(25, 25, 0.09, 4) | wide init; first ~60 s pulls states in |

Seed HR(0), A1(0) from the first valid measurements; F(0) from Layer 3 (see §7). Because the observation equations are linear, a plain KF suffices; keep the EKF only if `A1_target` is made a state-dependent nonlinearity.

### 4.5 The Acute Fatigue Index (what the rider sees)
Define a single 0–100 index from the filter's fatigue state, normalized to the athlete:
```
AFI = 100 · clamp( F / F_ref , 0, 1 )   # F_ref = athlete's typical end-of-hard-ride drift, default ~12 bpm
```
Cross-checked against, and blended with, the model-free decoupling% and DFA-α1 drift so the index degrades gracefully when RR quality is poor (fall back to decoupling-only).

**Concerning-value scale (defaults; §"provenance" below):**
| AFI / signal | State | Basis |
|---|---|---|
| AFI < 30, decoupling <5%, α1 > 0.75 | Fresh / productive aerobic | decoupling convention; α1 anchor |
| AFI 30–60, decoupling 5–8% | Accumulating, still productive | decoupling convention |
| AFI 60–85, decoupling >8%, α1 drifting toward 0.5 | High fatigue; durability fading | durability drift; α1 fatigue drift |
| AFI > 85, or α1 < 0.5 at sub-threshold power, or α1 ≳0.3 below baseline-for-power | Severe; window closing | α1 collapse empirical anchor (0.32–0.37 when fatigued) |

> **Caveat on the severe band:** Rogers et al. (2025) found that in a cycling time-to-task-failure, **not all athletes reached anticorrelated α1 (<0.5) even at the moment of failure** — failure occurred across a *range* of personal α1 values, and α1 threshold validity degrades once fatigued. Therefore the **per-athlete "≳0.3 below baseline-for-power" drift is the more reliable severe trigger than the absolute α1 < 0.5**, and the absolute cutoff should be treated as corroborating, not decisive.

---

## 5. Layer 3 — Residual training-scale fatigue

Standard, well-behaved bookkeeping (implement exactly as in §7.1 of the literature review):
```
TSS_today = (sec·NP·IF)/(FTP·3600)·100            # or Banister/Edwards TRIMP if no power
CTL = CTL_y + (TSS − CTL_y)/42                     # Fitness
ATL = ATL_y + (TSS − ATL_y)/7                      # Fatigue
TSB = CTL_y − ATL_y                                # Form
ACWR = EWMA_7 / EWMA_28   (uncoupled/EWMA form; descriptive only)
```
**Residual Fatigue readout** = ATL and TSB, with configurable Friel bands (>+10 fresh · −10→−30 productive overload · **<−30 high overreaching risk**) and an ACWR ramp warning at >1.5, **labeled descriptive, not predictive**. If resting RR is captured (e.g. morning or pre-ride), track **RMSSD against a personal 7-day rolling baseline ±1 SD** rather than any universal cutoff, and surface a sustained decline as an overreaching flag with the honest caveat that direction alone can mislead (some overreached athletes show transient HRV elevation).

**Real numbers to expect (trained cyclist):** CTL 70–150; hard 3-h ride 200–300 TSS; TSB in a build block routinely −10 to −30; ramping CTL >5–8/week is the practical over-reach warning.

---

## 6. The productive-to-damaging transition (Question 3)

**The honest position (must be reflected in UI copy):** no validated marker exists for the exact moment a ride turns net-negative, and in cycling "damage" is mostly **glycogen depletion**, not muscle injury. FatigueMeter therefore emits a **probabilistic "productive window closing" signal**, not a "damage now" alarm, by requiring **agreement of independent Layer-1 signals** rather than trusting any one:

1. **Intensity-weighted kJ** approaching the athlete's durability anchor (~1,500–2,500 kJ, default from CTL).
2. **Rolling decoupling** >8% at steady power, after ≥60–90 min, suppressed in high heat.
3. **DFA-α1 drift** — sustained inability to hold early-ride power at early-ride HR, or α1 collapsing below ~0.5 at sub-threshold power.

When ≥2 of 3 agree, display: *"Durability fading — remaining work is now mostly fatigue, not stimulus."* This is defensible because the aerobic boundary demonstrably drifts down ~6–10% after ~1,400–1,680 kJ, that drift is measurable via decoupling and power-at-HR, and it correlates with high-end performance loss (rs=0.719). The glycogen-flip and any "damage point" are flagged **speculative** in-app.

**Crucial refinement — not all red is a "turn back."** High fatigue produced by a deliberate hard effort (a max climb, a breakaway, a threshold block) is the *intended* stimulus, not a warning. The productive-window verdict is therefore **conditioned on how the fatigue was earned** — see §8.2 (Feat of Strength vs Attrition). The turn-back signal fires only for *attrition* red (drift at sub-threshold power past the durability anchor), not for *feat-of-strength* red (high output, W′ depletion, best efforts). This prevents the app from scolding a legitimately great hard day.

---

## 7. Start-of-ride and end-of-ride fatigue (Question 4)

- **Start-of-ride** fatigue = Layer 3 state at ride start, mapped to the same 0–100 scale as AFI so the two are comparable. Concretely, seed the Layer-2 filter's `F(0)` from residual fatigue: `F(0) = f(ATL, TSB, RMSSD_deviation)`, e.g. a rider deep in negative TSB with suppressed RMSSD starts with a non-zero drift offset (lower effective durability anchor, faster κ). This makes the model *begin* the ride already partly fatigued — matching the lived experience of riding on tired legs.
- **End-of-ride** fatigue = Layer-2 final `F`/AFI plus the ride's TSS folded into ATL/CTL. The delta (end minus start) is the **fatigue added by this ride**; the start value is the **fatigue carried in**. Reporting both directly answers Question 4.

---

## 8. Display, effort characterization, and storage

### 8.1 The single glance screen (Question 2)

**Design premise:** this is *not* a constantly-watched field. It is a large, full-screen layout the rider flips to a handful of times per ride to get a decision — a **"keep going"** or **"turn back / ease off"** call. So it leads with a **verdict**, backed by evidence, readable in a ~2-second glance on the Edge 1050's large color display.

**Layout (top → bottom):**
1. **Verdict banner (largest element).** One of: **KEEP GOING** (green) · **PRODUCTIVE — EASE SOON** (amber) · **EASE OFF / TURN BACK** (red). When red, a second line names the *kind* of red (§8.2): **"🏅 Feat of Strength"** or **"⚠ Attrition."** This is the headline the rider came for.
2. **Acute Fatigue Index dial (0–100)** with a green/amber/red arc and three ticks: **start-of-ride** fatigue (carried in), **now**, and **projected end-of-ride** at the current effort. The start→now gap is the fatigue added so far.
3. **Evidence row (the "why"):** rolling decoupling %, DFA-α1 with a data-quality dot, intensity-weighted kJ vs the personal **durability anchor** (progress bar), and **W′ matches burned**.
4. **Feats-of-strength strip:** the ride's best efforts so far (e.g., peak 5-min power, biggest climb kJ), matches burned, and residual context (TSB / start fatigue).
5. **Data-quality footer:** RR artifact %/DFA-α1 validity; when RR is poor, the screen shows the decoupling-only fallback and says so.

**Design rules:** verdict legible at arm's length; numbers secondary; **color is always reinforced by text/icon (never color alone)** — for red-green-colorblind riders and for glance speed.

### 8.2 Characterizing "red": Feat of Strength vs Attrition

Red is not automatically bad — going deep into the red is frequently the *point*. FatigueMeter classifies the **driver** of high fatigue along one physiologically-grounded axis: **is the fatigue being bought with output?**

- **Feat of Strength (productive red).** High fatigue *with* high intensity/output: power ≫ CP, time in the severe domain, **W′ depletions ("matches")**, and in-ride best efforts (power PRs for standard durations). This is intended stimulus. Rendered **red-with-gold** and explicitly *not* a turn-back: the verdict reads *"This is the work — continue if intended."*
- **Attrition (hole-digging red).** High fatigue with *declining or merely-maintained* output: rising decoupling and α1 drift at **sub-threshold** power, deep past the durability/kJ anchor. The fatigue is drift, not performance — this is the genuine **"ease off / turn back"** red.

**Currency (both computed continuously and stored):**
```
FeatScore      ∝ kJ_above_CP + w_sev·(time in severe domain) + Σ(depth of W′ matches) + best-effort bonuses
AttritionScore ∝ (decoupling above baseline)·(time at sub-threshold power past durability anchor)
                 + (α1 drift below personal baseline-for-power)
```
The verdict blends them: red with **Feat ≫ Attrition** → celebrate/continue; red with **Attrition ≫ Feat** → turn back. A **W′ "match"** = a W′bal depletion below a low threshold (e.g., <20%) followed by partial recovery; matches burned is an intuitive, cyclist-familiar count of hard efforts. **[synthesis — grounded in severe-domain/W′ physiology (Skiba, Schäfer) and durability-drift (Maunder/Stevens), but not a validated classifier; label in-app.]**

### 8.3 Data storage and session results

Two tiers, so markers persist through the ride *and* roll up for cross-ride comparison:

**(a) In-ride time series → FIT developer fields (record messages).** Log continuously (1 Hz, or 5 s for α1) via the Connect IQ **FitContributor** API as `MESG_TYPE_RECORD` developer fields: AFI, F (efficiency/slow drift), decoupling %, DFA-α1, W′bal, intensity-weighted kJ, FeatScore, AttritionScore. Written into the .FIT file, they **flow to Garmin Connect / intervals.icu** for post-ride charting and remain inspectable later.

**(b) Session summary → FIT session fields + persistent app storage.** At ride end, write `MESG_TYPE_SESSION` developer fields **and** persist a compact **Session Result** for cross-ride comparison: date, duration, TSS, **start-of-ride fatigue, end-of-ride fatigue, fatigue added**, peak AFI, **time-in-red split into Feat minutes vs Attrition minutes**, FeatScore + top feats (best 1/5/20-min power, biggest climb, matches burned), AttritionScore, durability anchor reached (kJ), and updated CTL/ATL/TSB. Keep a **rolling history** (e.g., last N sessions) in `Storage`.

**Cross-ride comparison view (post-ride screen / widget):** a compact trend/table of recent Session Results, so the rider can see **"was today a feat-of-strength day or an attrition day?"** relative to previous rides, and watch whether hard days are being bought with performance or paid for with drift. This is the "easy comparing across rides" deliverable.

---

## 9. Provenance of every numeric threshold

| Threshold | Status |
|---|---|
| DFA-α1 = 0.75 (aerobic threshold) | **Validated** (r=0.99 VO₂, ICC 0.99); ±10 bpm individual LoA |
| DFA-α1 = 0.5 (anaerobic threshold) | Moderately validated (cyclists r≈0.93 power) |
| DFA-α1 < 0.5 / ≳0.3-below-baseline as fatigue flag | **Synthesis** — anchored on empirical Q1→Q4 ~1.2→~0.75 drift (Rogers 2025); absolute <0.5 not universal (many fail above it), so per-athlete baseline drift preferred |
| Decoupling <5 / 5–8 / >8–10% | Coaching convention (Friel/TrainingPeaks); not a validated damage cutoff |
| ~0.6% decoupling per rpm cadence decline | **Verified** (Barsumyan 2026 full text: b=0.61 drift / 0.58 decoupling); no threshold established |
| Durability −6 to −10% VT1 after ~1,400–1,680 kJ | **Validated** (Maunder/Stevens) |
| kJ anchors 1,500 / 2,500 | Population-level (Spragg / review); person-specific in practice |
| CTL/ATL/TSB (42/7-day EWMA), TSS formula | **Standard/established** |
| Friel TSB bands (+25/+5/−10/−30) | Coaching convention, **not peer-reviewed** — configurable default |
| ACWR sweet spot 0.8–1.3, danger >1.5 | Contested (Impellizzeri/Lolli) — descriptive only |
| RMSSD 25 ms / NFOR 74.6 vs 107.6 ms | Small-sample; use personal baseline instead |
| DALE τ_st≈28 s, τ_ft≈47 s, severe Ȧ≈88 mL·min⁻² | **Validated** (Gløersen 2022, n=8) |
| Kalman seed values (§4.4) | **Synthesis** — physiologically motivated, calibrate per athlete |
| Feat-of-Strength vs Attrition red-typing (§8.2) | **Synthesis** — grounded in severe-domain/W′ physiology + durability drift; not a validated classifier |
| W′ "match" = W′bal <20% then recovery; matches-burned count | Established concept (Skiba W′bal); threshold is a configurable convention |
| Best-effort / power-PR bonuses (1/5/20-min) | Established practice (mean-maximal-power / best-effort curves) |

---

## 10. Calibration & validation plan

1. **Cold start** from athlete profile (FTP/CP, HR_max/HR_rest, sex, CTL) → literature defaults.
2. **Threshold calibration ride** — a ramp or step protocol to fit the personal power→DFA-α1 sigmoid (accept only fits with R²>0.75) and personal AeT/AnT power.
3. **Durability calibration** — one or two long rides to fit the personal kJ anchor and κ (fatigue charge rate) against observed VT1/decoupling drift.
4. **Ongoing** — nightly RMSSD baseline; periodic re-fit as CTL changes.
5. **Scientific-consistency validation** — an automated harness (see [prompts/scientific-validation-prompt.md](prompts/scientific-validation-prompt.md)) that asserts the app's outputs never contradict the recorded consensus (e.g. α1 monotonic-decreasing with intensity in the mean; decoupling non-negative under drift; TSB = CTL − ATL exactly; AFI bounded; concerning bands ordered).

---

## 11. Limitations (state plainly, in-app where relevant)

- **RR/HRV quality is the dominant failure mode.** Requires a chest strap; artifact >5% invalidates DFA-α1.
- **The fused fatigue states are not directly validated** by any single study; they compose validated pieces and require per-athlete calibration.
- **Individual variability** in α1 thresholds (±0.28 SD around 0.75) and in all coaching-convention bands.
- **Confounders:** heat, dehydration, altitude, deliberate breathing, nutrition/glycogen, illness, menstrual cycle (largely unstudied for α1).
- **Cycling ≠ running:** the durability and low-EIMD findings are cycling-appropriate; do not import running muscle-damage numbers.
- **Not a medical device;** does not diagnose overtraining syndrome.

---

## 12. Summary

FatigueMeter turns a decade of slow-component, DFA-α1, decoupling, and training-load research into a single coherent, on-device-feasible system: a DALE-grounded Kalman estimator of acute fatigue, sitting on model-free decoupling primitives, seeded and updated by a standard CTL/ATL/TSB residual-fatigue ledger, with a probabilistic productive-window signal and explicit start/end fatigue accounting. Its distinctive discipline is provenance: every number is traceable, every synthesis is labeled, and the app cannot present a value that contradicts the science it is built on — enforced by the validation harness specified in the companion prompt.
