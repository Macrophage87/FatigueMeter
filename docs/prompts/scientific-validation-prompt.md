# LLM Prompt — Scientific-Consistency Validation Scheme for FatigueMeter

Paste the prompt below into a capable coding LLM with this repository as context. Its job is to produce an **automated validation harness** that continuously checks the FatigueMeter app's computed values against the **established scientific consensus** recorded in `docs/literature-review.md`, `docs/white-paper.md`, and `docs/references.md` — so the app can never present a number that contradicts the science it is built on.

This is deliberately separate from ordinary unit tests. Unit tests check that a formula is coded correctly; this harness checks that the *system's behavior and outputs stay physiologically plausible and internally consistent* across realistic and adversarial ride scenarios.

---

## PROMPT

You are a verification engineer with a strong background in exercise physiology and signal processing. Build a **scientific-consistency validation harness** for the FatigueMeter application (a cyclist-fatigue estimator; see `docs/white-paper.md` for the model and `docs/literature-review.md` + `docs/references.md` for the evidence base). The harness must assert that FatigueMeter's outputs never contradict the recorded scientific consensus, and must clearly separate **hard invariants** (violation = bug) from **soft/plausibility checks** (violation = warning to review) from **calibration-dependent** behavior.

### Deliverable
A runnable test suite (choose Python for off-device testing of the extracted pure functions; the app's formulas should be provided as pure functions per the generation prompt, or reimplemented faithfully and cross-checked). Include: synthetic signal generators, real-file ingestion (FIT/CSV with power, HR, RR, cadence), a property-based testing layer, an assertion catalog, and a human-readable report that cites which consensus statement each check enforces (link back to `docs/references.md` entries).

### 1. Hard invariants (must always hold; violation = fail)
Encode these as assertions over any run:
- **Definitional identities:** `TSB == CTL − ATL` exactly (using yesterday's values); `IF == NP/FTP`; `TSS == duration_h · IF² · 100` within float tolerance; NP = 4th-root of 30 s rolling mean of power⁴.
- **Bounds:** AFI ∈ [0,100]; DFA-α1 finite and within a sane range (≈[0.2, 1.6]) whenever the artifact gate passes; decoupling % real-valued; EWMA states non-negative for non-negative TSS.
- **Ordering of concerning bands:** the AFI/decoupling/α1 cutoffs are strictly ordered (fresh < accumulating < high < severe); no overlapping or inverted bands.
- **Artifact gate:** DFA-α1 is emitted only when window artifact ≤ the configured threshold (default 5%); otherwise the value is withheld and the fallback path is active.
- **Kalman sanity:** covariance stays positive-definite; state estimates do not diverge (no NaN/Inf) under sensor dropouts, RR gaps, power=0, HR=0.
- **Ledger integrity:** CTL/ATL update is idempotent per day and survives a simulated mid-ride crash without corruption.

### 2. Consensus-plausibility checks (monotonicity & direction; violation = warning)
Drive the model with synthetic and real rides and assert the *directions* the literature establishes:
- **α1 vs intensity:** in the ensemble/mean, DFA-α1 **decreases** as intensity rises, crossing ~0.75 near the athlete's aerobic-threshold power and ~0.5 near anaerobic threshold (Rogers/Gronwald). Check the crossing powers are within a tolerance of the athlete's configured AeT/AnT.
- **Decoupling under drift:** for a long steady sub-threshold effort with imposed cardiac drift, decoupling % is **non-negative and increases** over time; for a fresh short effort it stays <5%.
- **α1 within-ride fatigue drift:** for a prolonged effort at fixed power, DFA-α1 **drifts downward** over time even when power is constant (durability signal); its end-of-ride value at a fixed aerobic power is lower than its start value.
- **Durability magnitude:** the modeled VT1/decoupling drift after ~1,400–1,680 kJ is in the ballpark of **~6–10%** (Maunder/Stevens); flag if the model predicts implausibly small (<1%) or large (>25%) drift for a typical trained profile.
- **DALE gating:** the fatigue state `F` stays ≈0 below CP and accumulates only above CP (severe-domain gating; Gløersen). Assert `F` does not grow during sustained sub-CP riding.
- **Training-load realism:** 1 h at FTP ⇒ ~100 TSS; a hard 3 h ride ⇒ 200–300 TSS; CTL ramp warnings fire when weekly CTL rise >5–8 points; ACWR >1.5 raises a *descriptive* (not predictive) warning.
- **TSB tapering behavior:** after a load reduction, ATL falls faster than CTL, so TSB rises (Banister τ2<τ1) — assert this on a simulated taper.

### 3. Adversarial / robustness scenarios
Generate and run these, asserting no hard-invariant violations and sensible fallback:
- Corrupt/ectopic RR streams at 3%, 6%, 12% artifact → α1 withheld above gate; fallback to decoupling-only engages and is surfaced in output.
- Wrist-optical-quality RR (jittered) → the harness confirms the app flags low confidence rather than emitting a confident α1.
- Power spikes/dropouts, HR sensor loss, pauses/stops, very short rides (<15 min, no baseline window) → no divide-by-zero, no NaN, graceful "insufficient data."
- Heat scenario (imposed extra drift) → decoupling rises but the productive-window signal requires ≥2/3 agreement before firing (no false "damage" claim).
- Extreme profiles (very high/low FTP, HR_max) → outputs stay bounded and ordered.

### 4. Provenance & honesty enforcement (unique to this project)
- **Convention/synthesis guard:** for every threshold the white-paper §9 provenance table marks as "convention" or "synthesis," assert the app treats it as a *configurable setting with the documented default*, and that changing the setting changes behavior (i.e. it is not hard-coded). Fail if a convention value is hard-coded as if validated.
- **Label enforcement:** assert that when calibration has not run, AFI / productive-window / start-end fatigue are tagged "uncalibrated — estimate only," and that no output is labeled clinically meaningful. Assert the non-medical-device disclaimer is present.
- **No-overclaim check:** assert the app never emits the word "damage" as a certainty for the productive-window signal, and that speculative items (glycogen flip, α1 hard alarm) are labeled speculative.
- **Traceability:** cross-check `docs/traceability.md` — every physiological constant used in code maps to a white-paper table row and a reference; fail if a constant has no provenance.

### 5. Calibration-dependence checks
- Assert that with **no** athlete calibration, the model uses literature defaults and says so; with a **calibration ride** applied, the personal power→DFA-α1 sigmoid is used only if its fit R² > 0.75, else it refuses and keeps defaults.
- Regression check: after calibration, α1-crossing powers and durability anchor move toward the athlete's measured values, not away.

### 6. Reporting
Produce a report that, per check: states the assertion, the consensus statement it enforces (quoted/linked from `docs/references.md`), pass/fail/warn, and — for warnings — the observed vs expected direction/magnitude. Summarize hard-invariant failures at the top. The report must be readable by a coach or sports scientist, not just an engineer.

### Ground rules
- Treat `docs/literature-review.md`/`references.md` as the source of truth for *what the consensus is*; do not introduce thresholds not present there. Where the literature is explicitly uncertain (durability magnitude ranges, individual α1 variability ±0.28, contested ACWR), encode **tolerant** checks (ranges/directions), not brittle equalities.
- Distinguish clearly, in both code and report, the three tiers: **hard invariant**, **plausibility (direction/range)**, **calibration-dependent**. A soft-check warning must never fail the build; a hard-invariant violation must.
- Where a check cannot be grounded in a cited consensus statement, mark it **heuristic** and keep it non-blocking.

Begin by enumerating the assertion catalog grouped by the six sections above, mapping each assertion to its `references.md` source and its tier, then implement the harness. Flag any assertion you cannot ground in the recorded literature.
