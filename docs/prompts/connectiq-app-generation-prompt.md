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
- Rolling **Efficiency Factor** and **decoupling %** vs a baseline established over minutes 5–15. Thresholds <5 / 5–8 / >8–10% as configurable settings.
- **Intensity-weighted kJ** with weight ramping from 1× below CP to ~2–3× above CP.
- **DFA-α1** on a **2-minute rolling RR window, recomputed every 5 s, box sizes 4–16 beats, per-box linear detrend**, with a **hard artifact gate at 5%** (configurable, prefer <3%) and a validity flag. Implement DFA correctly (integrate the mean-subtracted series, partition into boxes of size n, least-squares linear detrend per box, RMS across boxes → F(n); α1 = slope of log F(n) vs log n over n∈[4,16]). Profile it; if per-5 s recompute is too heavy, decimate further and document the tradeoff.
- **Cadence drift** and a simple **W′bal** (Skiba differential) from CP/W′.

**Layer 2 — Acute fatigue Kalman filter** (`AcuteFatigueFilter`):
- Implement the 4-state filter from white-paper §4 exactly: state `[HR_ss, HR, A1, F]`, the transition equations (including the power→DFA-α1 sigmoid `A1_target` and the **CP-gated fatigue drift F**), and the two linear observation equations. Use the seed/tuning table (§4.4) as defaults, all overridable in settings.
- Output the **Acute Fatigue Index (AFI, 0–100)** per §4.5, blended with model-free decoupling/α1 drift so it degrades gracefully when RR is poor.
- Implement the concerning-value band logic (fresh / accumulating / high / severe) with ordered, configurable cutoffs.

**Layer 3 — Residual fatigue ledger** (`TrainingLoadLedger`, persistent):
- Compute ride **TSS** (power) or fall back to **Banister/Edwards TRIMP** (HR).
- Maintain **CTL (42-day) and ATL (7-day) EWMAs** and **TSB = CTL − ATL** across rides via persistent storage. Implement **uncoupled/EWMA ACWR** as a descriptive ramp warning (>1.5), clearly labeled non-predictive.
- If resting RR is captured, track **RMSSD against a personal 7-day rolling baseline ± 1 SD** (not a universal cutoff).

**Coupling (Questions 4 & 3):**
- **Seed** the Layer-2 filter's `F(0)` from the Layer-3 residual state at ride start (white-paper §7) so the ride *starts* partly fatigued when the athlete is carrying load. Record **start-of-ride fatigue** on the same 0–100 scale as AFI.
- At ride end, record **end-of-ride fatigue** and the **fatigue-added delta**, and fold TSS into the ledger.
- **Productive-window signal** (§6): fire an amber "window closing — remaining work is mostly fatigue, not stimulus" state only when **≥2 of 3** independent signals agree (intensity-weighted kJ near durability anchor; decoupling >8% after ≥60–90 min; DFA-α1 drift/collapse). Never label it "damage."

### Effort characterizer — Feat of Strength vs Attrition (white-paper §8.2)
- Implement a `EffortCharacterizer` that continuously computes **FeatScore** and **AttritionScore** per white-paper §8.2, and classifies any red state as **Feat of Strength** (bought with output: P≫CP, severe-domain time, W′ matches, in-ride best efforts) or **Attrition** (drift at sub-threshold power past the durability anchor).
- Track **W′ "matches"** (W′bal dropping below a configurable ~20% then recovering) and **in-ride best efforts** (best 1/5/20-min mean-maximal power).
- The productive-window/turn-back verdict must be **conditioned on this classification**: fire "turn back / ease off" only for Attrition-dominant red, and render Feat-dominant red as **red-with-gold "🏅 Feat of Strength — this is the work"** (not a scold). This is a hard requirement — the user deliberately rides deep into the red and the app must not treat every red as a warning.

### Display — the single glance screen (white-paper §8.1)
Build a **large, full-screen** layout (target the Edge 1050 color display) designed to be flipped to a few times per ride for a decision, **not** watched constantly. Top→bottom:
1. **Verdict banner** (largest): KEEP GOING (green) · PRODUCTIVE — EASE SOON (amber) · EASE OFF / TURN BACK (red); when red, a second line "🏅 Feat of Strength" or "⚠ Attrition."
2. **AFI dial (0–100)** with green/amber/red arc and three ticks: start / now / projected end.
3. **Evidence row:** decoupling %, DFA-α1 + quality dot, kJ vs durability-anchor progress bar, W′ matches burned.
4. **Feats strip:** best 5-min power, biggest climb kJ, matches burned, TSB/start-fatigue context.
5. **Data-quality footer:** RR artifact %/α1 validity; decoupling-only fallback shown when RR is poor.
- **Color must always be reinforced with text/icon (never color alone).**

### Storage — markers through the ride + session results (white-paper §8.3)
- **In-ride time series:** use the Connect IQ **FitContributor** API to log `MESG_TYPE_RECORD` developer fields (AFI, F, decoupling %, DFA-α1, W′bal, intensity-weighted kJ, FeatScore, AttritionScore) so they appear in the .FIT and sync to Garmin Connect / intervals.icu.
- **Session summary:** write `MESG_TYPE_SESSION` developer fields **and** persist a compact **Session Result** object (date, duration, TSS, start/end fatigue, fatigue added, peak AFI, time-in-red split Feat vs Attrition, FeatScore + top feats, AttritionScore, durability kJ reached, CTL/ATL/TSB) to `Storage`.
- Maintain a **rolling history** of the last N Session Results and a **cross-ride comparison view** (post-ride screen or companion widget) so the rider can compare "feat-of-strength day vs attrition day" against prior rides.
- Persist transactionally so a mid-ride crash cannot corrupt the ledger or session history.

### Settings (Connect IQ properties)
Expose: FTP, CP, W′, HR_max, HR_rest, sex, current CTL/ATL seed; all filter τ/κ/gains and Q/R; decoupling and TSB band cutoffs; DFA artifact threshold; unit preferences. Ship documented defaults from the white paper.

### Calibration & honesty (hard requirements)
- Until the **threshold-calibration ride** and **durability-calibration** (white-paper §10) have run, label AFI, the productive-window signal, and start/end fatigue as **"uncalibrated — estimate only."**
- Provide a **calibration mode** that fits the personal power→DFA-α1 sigmoid (accept only R²>0.75), personal AeT/AnT power, and the durability kJ anchor + κ.
- Every displayed value that derives from a "convention" or "synthesis" (see white-paper §9 provenance table) must be traceable in code comments to its status, and must not be presented as clinically meaningful. Include the disclaimer that FatigueMeter is not a medical device.

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
