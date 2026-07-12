# LLM Prompt — Generate the FatigueMeter Connect IQ Application

Paste the prompt below into a capable coding LLM (with this repository available as context — at minimum `docs/white-paper.md`, `docs/literature-review.md`, and `docs/references.md`). It is written to produce a Garmin Connect IQ **data field + companion background logic** in Monkey C, faithful to the model spec, with the honesty and calibration requirements built in.

> **Note on scope:** this generates a first working implementation of Layers 1–3 with the Acute Fatigue Index, on-ride display, productive-window signal, and start/end fatigue accounting. It deliberately ships the fused states behind a "uncalibrated — estimate only" label until the calibration flow has run.

---

## PROMPT

You are an expert Garmin **Connect IQ / Monkey C** developer and exercise-physiology-aware software engineer. Build an application called **FatigueMeter** that estimates a cyclist's fatigue in real time from power, heart rate, and beat-to-beat RR intervals, and tracks residual training-scale fatigue. Follow the specification in `docs/white-paper.md` exactly; use `docs/literature-review.md` and `docs/references.md` as the authority for every equation, constant, and threshold. **Do not invent physiological constants — take them from the white paper's tables, and where the white paper marks a value as a "synthesis" or "convention," expose it as a user-configurable setting with the documented default.**

### Target & tech
- **Platform:** Connect IQ, Monkey C. Target primarily the **Edge 1050** (and be portable to other power-capable Edge/Forerunner devices). Use the current Connect IQ SDK conventions.
- **App type:** a **Data Field** for on-ride display, plus the persistent-storage/background logic needed for the residual-fatigue ledger (Layer 3) across activities. If a single data field cannot hold all state, structure it so a companion (watch-app or widget) or `Storage`/`Application.Properties` persistence carries CTL/ATL/TSB and per-athlete calibration between rides.
- **Sensors:** subscribe to power, heart rate, cadence, and **RR/HRV intervals** (`Sensor` / `ANT+` HRV; require an RR-capable strap). Gracefully detect when RR is unavailable or artifact-heavy and fall back per §8 of the white paper.

### What to implement (map to the white paper's three layers)

**Layer 1 — Observable primitives** (`PrimitivesCalculator`):
- Rolling **Normalized Power** (30 s rolling avg of power⁴, then 4th root).
- Rolling **Efficiency Factor** and **decoupling %** vs a baseline established over minutes 5–15, **behind a steadiness gate** (emit only when the window's power CV and coasting fraction are below configurable limits; mark low-confidence otherwise — NP/EF over short windows is unvalidated and noisy on variable terrain). Thresholds <5 / 5–8 / >8–10% as configurable settings.
- **Intensity-weighted kJ** with weight ramping from 1× below CP to ~2–3× above CP.
- **DFA-α1** on a **2-minute rolling RR window, recomputed every 5 s, box sizes 4–16 beats, per-box linear detrend**, with a **hard artifact gate at 5%** (configurable, prefer <3%) **AND a stationarity gate** (suppress/down-weight α1 when within-window power CV or coasting fraction exceeds a configurable threshold — a moving window straddling transients violates α1's stationarity assumption) and a validity flag. Implement DFA correctly (integrate the mean-subtracted series, partition into boxes of size n, least-squares linear detrend per box, RMS across boxes → F(n); α1 = slope of log F(n) vs log n over n∈[4,16]). Where feasible derive respiratory frequency (fB) from the RR stream to flag ventilation-driven α1 movement. Profile it; if per-5 s recompute is too heavy, decimate further and document the tradeoff.
- **Cadence drift** and a simple **W′bal** (Skiba differential) from CP/W′ (**guard: a stale CP/W′ propagates to matches/FeatScore — surface a data-quality caveat**).

**Layer 2 — Acute fatigue EKF** (`AcuteFatigueFilter`):
- Implement the **4-state Extended Kalman filter** from white-paper §4 **as revised (Rev 2)**: state `[HR_ss, HR, A1, F]` where `F` is the **residual cardiovascular-drift state** (NOT "the VO₂ slow component" — do not use that label in code or UI). Implement the transition equations **including the α1↔F coupling term `−c_F·F` in the `A1` update** (this is the fusion mechanism — without it, α1 does not inform `F`) and the **graded intensity+duration charge** for `F` (`κ_i·max(0,P−P_AeT) + κ_d`). **Do NOT hard-gate `F` at critical power** — sub-CP drift is real. Use the seed/tuning table (§4.4) as defaults, all overridable in settings.
- Output the **Acute Fatigue Index (AFI, 0–100)** per §4.5 as an **index/estimate** (never a "measured fatigue" value), blended with model-free decoupling so it degrades gracefully to decoupling-only when RR is poor or α1 calibration fails the R²>0.75 gate.
- Implement the band logic (fresh / accumulating / high / severe) with ordered, configurable cutoffs. **Verdict gating uses only the per-athlete α1 drift-below-baseline signal; the absolute α1 value is display-only and must not gate any verdict.**
- Include the **observability guard**: expose `F` and AFI with an uncertainty/confidence indicator, and document in code that on constant-power segments `F` is weakly observable (AFI ≈ smoothed decoupling there).

**Layer 3 — Residual fatigue ledger** (`TrainingLoadLedger`, persistent):
- Compute ride **TSS** (power) or fall back to **Banister/Edwards TRIMP** (HR).
- Maintain **CTL (42-day) and ATL (7-day) EWMAs** and **TSB = CTL − ATL** across rides via persistent storage. **ACWR is OPT-IN and OFF by default** (mathematically criticized — Lolli/Impellizzeri); when enabled, show it only as a plain weekly load-ramp display with the critique linked in-UI, never as a predictive risk score. Prefer a CTL ramp (>5–8 pts/week) as the over-reach cue.
- **Resolve the Banister female TRIMP coefficient (0.86 vs 0.64) against the 1991 primary, or expose it as a setting** — do not ship an ambiguous hard-coded constant.
- If resting RR is captured, track **RMSSD against a personal 7-day rolling baseline ± 1 SD** (not a universal cutoff).

**Coupling (Questions 4 & 3):**
- **Seed** the Layer-2 filter's `F(0)` from the Layer-3 residual state at ride start (white-paper §7) so the ride *starts* partly fatigued when the athlete is carrying load. Record **start-of-ride fatigue** on the same 0–100 scale as AFI.
- At ride end, record **end-of-ride fatigue** and the **fatigue-added delta**, and fold TSS into the ledger.
- **Durability advisory** (§6, Rev 2): surface a **descriptive** "durability markers are drifting — remaining work may be mostly fatigue" state drawing on **correlated** markers (intensity-weighted kJ near anchor; decoupling >8% after the steadiness gate and ≥60–90 min; per-athlete α1 drift-below-baseline). **Do NOT call these "independent," do NOT emit an imperative "TURN BACK," and never label it "damage."** Apply thermal suppression to **both** decoupling and α1, and **name the shared confounds in-UI** (heat/dehydration/fuel/altitude) when the advisory fires.

### Effort characterizer — Feat of Strength vs Attrition (white-paper §8.2)
- Implement an `EffortCharacterizer` that continuously computes **FeatScore** and **AttritionScore** per white-paper §8.2, characterizing high-fatigue states as **Feat of Strength** (bought with output: P≫CP, severe-domain time, W′ matches, in-ride best efforts) or **Attrition** (drift at sub-threshold power past the durability anchor).
- Track **W′ "matches"** (W′bal dropping below a configurable ~20% then recovering) and **in-ride best efforts** (best 1/5/20-min mean-maximal power).
- **This classifier is OFF the verdict critical path (Rev 2).** It has arbitrary weights and no validation, so it must **not gate or suppress** the status band. Show FeatScore/AttritionScore as **raw evidence** that *contextualizes* a red state ("this red is dominated by hard output 🏅" vs "…by drift ⚠"), so a deliberately hard effort is celebrated rather than scolded — but the app must never convert this synthesis-grade guess into an authoritative directive.

### Display — the single glance screen (white-paper §8.1)
Build a **large, full-screen** layout (target the Edge 1050 color display) designed to be flipped to a few times per ride for a read, **not** watched constantly. Top→bottom:
1. **Status band** (largest), **carrying a persistent "advisory · not a validated measurement" tag**: descriptive states **FRESH / PRODUCTIVE** (green) · **FATIGUE BUILDING — EASE SOON** (amber) · **DURABILITY MARKERS DRIFTING** (red); when red, a second line "🏅 Feat of Strength" or "⚠ Attrition" as characterization, **not a command**. No imperative "TURN BACK" text.
2. **AFI dial (0–100)** with green/amber/red arc and three ticks: start / now / projected end — labeled an *index*.
3. **Evidence row (at least equal visual weight to the status band — it is the validated part):** decoupling %, DFA-α1 + quality dot, kJ vs durability-anchor progress bar, W′ matches burned.
4. **Feats strip:** best 5-min power, biggest climb kJ, matches burned, TSB/start-fatigue context.
5. **Data-quality footer:** RR artifact %/α1 validity + stationarity/steadiness status; decoupling-only fallback shown when RR is poor or α1 uncalibrated.
- **Color must always be reinforced with text/icon (never color alone).**

### Storage — markers through the ride + session results (white-paper §8.3)
- **In-ride time series:** use the Connect IQ **FitContributor** API to log `MESG_TYPE_RECORD` developer fields (AFI, F, decoupling %, DFA-α1, W′bal, intensity-weighted kJ, FeatScore, AttritionScore) so they appear in the .FIT and sync to Garmin Connect / intervals.icu.
- **Session summary:** write `MESG_TYPE_SESSION` developer fields **and** persist a compact **Session Result** object (date, duration, TSS, start/end fatigue, fatigue added, peak AFI, time-in-red split Feat vs Attrition, FeatScore + top feats, AttritionScore, durability kJ reached, CTL/ATL/TSB) to `Storage`.
- Maintain a **rolling history** of the last N Session Results and a **cross-ride comparison view** (post-ride screen or companion widget) so the rider can compare "feat-of-strength day vs attrition day" against prior rides.
- Persist transactionally so a mid-ride crash cannot corrupt the ledger or session history.

### Settings (Connect IQ properties)
Expose: FTP, CP, W′, HR_max, HR_rest, sex, current CTL/ATL seed; all filter τ/κ/gains and Q/R; decoupling and TSB band cutoffs; DFA artifact threshold; unit preferences. Ship documented defaults from the white paper.

### Calibration & honesty (hard requirements)
- Until the **threshold-calibration ride** and **durability-calibration** (white-paper §10) have run, label AFI, the durability advisory, and start/end fatigue as **"uncalibrated — estimate only."** The fused AFI/advisory must **always** carry a persistent "advisory · not a validated measurement" tag (calibration tunes threshold-crossings and self-consistency; it does **not** validate the fatigue magnitude — there is no on-bike fatigue ground truth, white-paper §10).
- Provide a **calibration mode** that fits the personal power→DFA-α1 sigmoid (accept only R²>0.75, else decoupling-only + α1 display-only), personal AeT/AnT power, and the durability kJ anchor + κ terms.
- Every displayed value that derives from a "convention" or "synthesis" (see white-paper §9 provenance table) must be traceable in code comments to its status, and must not be presented as clinically meaningful. Reflect the **evidence-strength** column, not just extraction confidence. Include the disclaimer that FatigueMeter is not a medical device, and that the within-ride α1/fatigue use is unvalidated on outdoor variable-power rides.

### Engineering requirements
- Clean, commented Monkey C; clear module boundaries (`PrimitivesCalculator`, `AcuteFatigueFilter`, `EffortCharacterizer`, `TrainingLoadLedger`, `FitLogger` (FitContributor record/session fields), `SessionStore` (persistent Session Results + rolling history), `FatigueMeterView`, `FatigueMeterApp`, settings). No blocking work in `compute()`; keep the 1 Hz path light and budget the DFA-α1 recompute.
- Numerically guard against divide-by-zero (HR=0, power=0), sensor dropouts, and RR gaps. Persist ledger state transactionally so a crash mid-ride cannot corrupt CTL/ATL.
- Provide unit-testable pure functions for every formula (DFA-α1, NP, decoupling, TSS, CTL/ATL/TSB, Kalman predict/update, W′bal, FeatScore/AttritionScore, match detection) so the validation harness (`docs/prompts/scientific-validation-prompt.md`) can exercise them off-device.
- Include a `manifest.xml`, `monkey.jungle`, resource/layout files, and a short `BUILD.md` with build/sideload steps for the Edge 1050. Add a `docs/traceability.md` mapping each implemented constant/threshold back to its white-paper table row and reference.

### Deliverables
1. Complete, buildable Monkey C source for the data field + persistence.
2. Settings definitions with documented defaults.
3. Pure-function modules with signatures suited to off-device unit testing.
4. `BUILD.md` and `docs/traceability.md`.
5. A short `IMPLEMENTATION_NOTES.md` listing every place you had to make an engineering choice not fully specified by the white paper, and every value you exposed as a setting because the science flagged it as convention/synthesis.

Begin by restating your understanding of the three-layer architecture and the coupling, list the modules and files you will create, then produce the code. If any constant is missing from the white paper, stop and flag it rather than inventing a value.
