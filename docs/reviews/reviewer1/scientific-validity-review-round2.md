# Reviewer 1 — Round 2 Review (Revision 2 of the White Paper and Prompts)

**Reviewer:** Reviewer 1 (exercise physiology / physiological signal processing / estimation)
**Date:** 2026-07-12
**Materials reviewed (Revision 2 only):**
- `docs/white-paper.md` (Rev 2)
- `docs/prompts/scientific-validation-prompt.md` (Rev 2)
- `docs/prompts/connectiq-app-generation-prompt.md` (Rev 2)
- `docs/reviews/reviewer1/response.md` (authors' disposition of my Round 1 review)

*Scope note: this round reviews the white paper and the two prompts, as requested. I did not
re-audit the literature review or references except where the prompts depend on them. Per the
brief, I ignored the other reviewers' files and treated this as an independent read.*

**Overall recommendation:** *Accept with minor revisions.* Revision 2 is a substantial,
good-faith response. The authors accepted every Round 1 point, and in two places went beyond
what I asked and **found a real defect I had missed** (see below). The document is now
honestly positioned as a *calibrated durability/decoupling dashboard with an advisory*, and
its UI-confidence-matches-evidence-confidence discipline is exemplary. However, the revision
**introduced one concrete technical error** (the EKF claim, R2-1), and several substantive
issues survive or are newly exposed by the changes. None blocks the project; all are fixable
in text and in the estimator spec.

---

## 0. Were the Round 1 changes actually made? (verification, not courtesy)

I checked the equations and UI spec directly rather than trusting the disposition table. The
claimed changes are genuinely present:

- **α1 now couples into `F`** — `A1(k+1)` gained the `− c_F·F(k)` term (§4.2). This is real
  fusion, and it fixes a **genuine defect the authors caught themselves**: in Rev 1 `F` entered
  only the HR equation, so DFA-α1 innovations contributed *zero* information to the fatigue
  state — the "fusion" was nominal. Good catch; credit to the authors.
- **The hard critical-power gate on `F` is removed** (§4.2, §4.4) — replaced by a graded
  `κ_i·max(0,P−P_AeT) + κ_d` charge. This is **physiologically correct**: cardiovascular drift
  is real sub-CP (thermoregulation, plasma-volume loss), and the supporting Barsumyan data were
  collected at 75% FTP. Removing the gate is the right call and I endorse it.
- **`F` renamed** "residual cardiovascular-drift state" and de-attributed from the VO₂ slow
  component (§4.1); **DALE's "Validated" flag now attaches only to the VO₂ constants** (§9).
- **Two-axis provenance table** (extraction vs evidence strength) with N/replication (§9);
  **absolute α1 band demoted to display-only** (§4.5); **descriptive-not-imperative UI** with a
  persistent "advisory" tag and equal-weight evidence row (§8.1); **calibrate ≠ validate**
  distinction and a criterion-validity pilot marked *owed* (§10); **ACWR opt-in/off by default**
  (§5).

These are the right moves and I will not re-litigate Round 1. The rest of this review is new.

---

## 1. New / remaining major concerns

### R2-1. The Rev 2 claim that the filter is nonlinear and "must use an EKF" is incorrect — the model as written is linear in the state
This is a concrete technical error introduced *by* the revision. §4.4 now states: *"The filter
is nonlinear (the `A1_target` sigmoid and the α1↔F coupling), so use an **EKF**."* Both cited
sources of nonlinearity are functions of the **exogenous input** `P`, not of the estimated
state:

- `A1_target(P) = a0 − a1/(1+exp(−s·(P−P_AeT)))` is nonlinear **in P**, but `P` is a measured
  input. It enters the `A1` transition as a known additive setpoint `u(k)` — it does **not**
  depend on any element of `x = [HR_ss, HR, A1, F]`.
- The coupling term `− c_F·F(k)` is **linear in `F`**.
- `HR_ss = HR_rest + g_P·P` is a known input term; the charge `κ_i·max(0,P−P_AeT) + κ_d` is a
  known input term (a hinge **in P**), minus `F/τ_rec` which is linear in `F`.
- Both observations (`HR_meas = HR + v`, `A1_meas = A1 + v`) are linear.

So the system is **linear time-varying with known input terms**, and a standard linear Kalman
filter is *exactly* optimal (under the Gaussian assumption). Nonlinearity in the *input* never
requires an EKF; only nonlinearity in the *state dynamics* or *measurement model* does. An EKF
would still run, but its Jacobian reduces to the constant state-transition matrix, so it buys
nothing and wastes Connect IQ compute budget on Jacobian evaluation the platform can ill afford.

Notably, **Rev 1 had this right** ("a plain KF suffices; keep the EKF only if `A1_target` is
made a state-dependent nonlinearity") and the condition it named — `A1_target` becoming
state-dependent — did **not** occur in Rev 2. The revision regressed on a point the prior draft
stated correctly. `P_AeT`, `a0/a1/s`, and `c_F` are fixed/calibrated parameters, not estimated
states, so nothing in the state path is nonlinear.

**Recommendation:** revert to "a linear (time-varying) Kalman filter is exact here; an EKF is
only needed if a sigmoid parameter or `P_AeT` is promoted to an estimated state." Fix the same
"use an EKF" instruction in the generation prompt (§Layer 2). *If* the authors intend future
online estimation of `P_AeT`/sigmoid, say so explicitly and keep the KF for now.

### R2-2. The α1→F coupling repairs the "fusion" but sharpens a double-counting problem the docs only address at Layer 1
Round 1's non-independence critique (my 1.4) was accepted at the **advisory** level (§6 now says
"correlated, not independent"). But the same non-independence now lives **inside the Kalman
filter and the AFI**, and this is not acknowledged:

- `F` is driven by HR-drift (`HR − HR_ss`) **and**, post-fix, by α1-drift (`A1 − A1_target`).
- AFI is then **further blended with model-free decoupling%** (§4.5).
- Decoupling, HR-drift-at-fixed-power, and α1-drift are three windows onto **one** underlying
  cardiac/autonomic drift (the docs say exactly this in §6).

So AFI is a weighted combination of three strongly correlated channels, presented as a single
0–100 index. Fusing correlated channels does **not** add independent information; it re-weights
one noisy signal. The Kalman gain will behave as if the α1 and HR innovations are conditionally
independent given the state (the standard KF assumption), which they are **not** here — a shared
physiological driver (heat, breathing) moves both measurements together, violating the diagonal-
`R` independence assumption in §4.4. Correlated measurement noise with a diagonal `R` makes the
filter **overconfident** (it double-counts agreeing-but-correlated evidence), tightening `P` and
AFI's implied precision beyond what the sensors support — the opposite of the honesty the
document is otherwise built on.

**Recommendation:** state in §4.3a/§4.4 that the HR and α1 innovations share physiological
drivers, so the diagonal-`R` assumption is optimistic and AFI's internal uncertainty is a lower
bound; consider a non-diagonal `R` (or inflating `R`) to avoid overconfidence. At minimum, stop
implying the fusion adds precision — §4.3a already says AFI is "a smoothed decoupling proxy with
a physiological prior" on steady rides; extend that candor to the correlated-noise point.

### R2-3. `c_F` is an unvalidatable cross-signal calibration constant
The fusion hinges on `c_F`, "tuned so `F ≈ F_ref` pulls α1 ~0.2 below its power-predicted value"
(§4.4). This single hand-set constant **defines the exchange rate between an α1 drop
(dimensionless) and a bpm of fatigue drift** — i.e. it asserts that "0.2 units of α1" equals
"`F_ref` bpm of HR drift" at the individual level. No cited source establishes any such
individual-level correspondence (PMC11280911 found the power↔α1 relationship itself is not even
universal). `c_F` therefore governs how much α1 moves the headline fatigue index, yet it cannot
be validated against anything on-device (§10's no-ground-truth problem applies doubly here,
since neither side of the exchange rate is measured against a fatigue criterion).

**Recommendation:** add `c_F` to the §9 "synthesis / hand-set — no on-bike ground truth" row
alongside `κ`, `τ_rec`, `Q`, `R`, and state that the α1 contribution to AFI is scaled by an
unvalidated cross-signal gain. The criterion-validity pilot (§10) should include a sensitivity
analysis on `c_F`.

### R2-4. Heat is simultaneously *signal for `F`* and *noise for the advisory* — an unresolved internal incoherence with a visible on-screen consequence
The authors deserve credit for disclosing this in the §4.4 Rev 2 note ("`F` is partly calibrated
against the very heat confound §6 tries to suppress… acknowledged, not resolved"). But
"acknowledged" understates the consequence for the **outputs**:

- `κ` is tuned against "typical cardiac drift, which is largely thermoregulatory," so on a hot
  day `F` (and thus AFI, and the AFI dial) **rises** — the app reads *more fatigued*.
- The durability advisory (§6) **suppresses** heat effects on decoupling and α1 and names heat as
  a confound to discount.

So on the same screen, in the same hot-weather scenario, the **AFI dial climbs** (heat treated
as fatigue) while the **advisory discounts** the drift (heat treated as artifact). These two
elements will visibly disagree, and a rider cannot tell which to believe. This is not merely a
provenance nuance; it is a coherence bug in the product's two most prominent fatigue readouts.

**Recommendation:** make the heat treatment **consistent across `F` and the advisory** — either
both attempt thermal decomposition (e.g. a core-temp-from-HR estimate, already listed as a
candidate marker) or both treat heat-driven drift as fatigue and say so. Do not tune `F` to
include thermal drift while the advisory excludes it.

### R2-5. "Fatigue added = end − start" and the `F(0)` seeding function `f()` remain unvalidated and partly ill-posed
§7's answer to Question 4 subtracts start-of-ride fatigue from end-of-ride fatigue. Two problems
survive Rev 2:

1. **The seeding map `f(ATL, TSB, RMSSD_deviation) → F(0)` in bpm is entirely unspecified and
   uncited.** It converts a days-scale residual-load state into "bpm of pre-existing
   cardiovascular drift" — a cross-domain mapping with no basis in any cited source. It then
   propagates into the headline "fatigue carried in" number and the AFI dial's start tick.
2. **The delta inherits every weakness of `F`.** Because `F` is weakly observable on steady
   rides (§4.3a) and scaled by hand-set `κ`/`F_ref`/`c_F`, "fatigue added" is a difference of two
   soft estimates and will often be dominated by parameter choice, not physiology. The
   arithmetic is at least dimensionally consistent (both endpoints are the same `F` state in
   bpm), so this is not apples-minus-oranges — but presenting a difference of two unvalidated
   indices as a concrete "fatigue you added today" number risks the same over-precision the rest
   of the document avoids.

**Recommendation:** specify `f()` and flag it synthesis-grade in §9; attach an uncertainty band
(or coarse buckets: "started fresh / moderately loaded / heavily loaded") to start-of-ride
fatigue and to "fatigue added," rather than a point value on the 0–100 scale.

### R2-6. The "projected end-of-ride" AFI tick is a forecast built entirely on hand-set constants
§8.1 item 2 shows a third dial tick: "projected end-of-ride at the current effort." Forecasting
`F` forward requires `τ_rec`, `κ_i`, `κ_d` (all hand-set, unsourced — §4.4) *and* an assumption
of constant future power. It is therefore the **most** speculative number on the screen — a
multi-parameter extrapolation — yet rendered as a concrete tick with the same visual authority
as "now."

**Recommendation:** either drop the projected tick until calibration exists, or render it as an
explicitly fuzzy band with a "projection" label, so a forecast on unvalidated constants is not
mistaken for a measurement.

---

## 2. Moderate concerns

### R2-7. The "simulated observability study" proves mathematical observability, not physiological identifiability
§4.3a (and the validation prompt §2 "`F` observability" test) require generating a ground-truth
`F(t)`, running the filter, and asserting `F` is recovered. For a linear time-varying system
this demonstrates **numerical observability/conditioning** — which could equally be checked
analytically via the observability Gramian — but because the ground truth is generated by the
**same model**, it cannot show that real HR drift decomposes into "fatigue `F`" versus unmodeled
thermal/dehydration drift the way the model assumes. That physiological identifiability is the
actual concern in §4.3a, and it is **not** testable by self-simulation. This is the very
self-consistency-≠-external-validity distinction the document elsewhere handles well; it slips
here.

**Recommendation:** relabel the simulated study "mathematical observability check (conditioning),
not physiological identifiability," and note that separating `F` from unmodeled drift requires
the external pilot (§10), not simulation.

### R2-8. The decoupling↔AFI blend is underspecified, so the 0–100 scale can shift meaning within a ride
§4.5 says AFI is "blended with model-free decoupling% … fall back to decoupling-only" when RR is
poor. The blend weighting and the decoupling→0–100 mapping are unspecified. If AFI is
`F`-dominated when RR is clean and decoupling-dominated when RR degrades, the **index means
different things at different times in the same ride**, and the start/now/projected ticks become
non-comparable across RR-quality transitions (common outdoors: sweat, strap slippage, terrain).

**Recommendation:** specify the blend as an explicit function of RR quality, guarantee the two
sources are scaled to a common reference (e.g. both normalized to `F_ref`-equivalent bpm), and
surface a marker when the AFI source switches so the dial's history stays interpretable.

### R2-9. The `κ_d` duration charge makes `F` accumulate on easy/recovery riding and its stop-behavior is unspecified
`F(k+1) = F + [κ_i·max(0,P−P_AeT) + κ_d]·Δt − (F/τ_rec)·Δt`. The constant `κ_d` charges every
second regardless of intensity, so `F` rises toward an equilibrium `≈ κ_d·τ_rec` (~2–3 bpm per
§4.4) even on a genuine **recovery spin or long descent**, reading as "accumulating fatigue" when
the athlete is actively recovering. It is also unstated whether `κ_d` charges while **stopped**
(traffic lights, café) — if `Δt` keeps advancing during auto-pause, `F` climbs while the rider
rests.

**Recommendation:** gate the `κ_d` charge on actual pedaling/moving (or on HR above resting), and
state that `F` should relax, not merely plateau, during genuine recovery; verify in the harness
that a recovery segment does not increase AFI.

---

## 3. Minor / prompt-specific

- **R2-10 (generation prompt, stale wording).** The scope note (line 5) still says *"…the
  **productive-window signal**, and start/end fatigue accounting"* — the Rev 2 rename to
  **"durability advisory"** did not propagate to that header note. Reconcile so the prompt's own
  framing matches the body it instructs.
- **R2-11 (validation prompt, hard-invariant too tight).** §1 lists DFA-α1 "within a sane range
  ≈[0.2, 1.6]" as a **hard** invariant. Resting/very-easy α1 can legitimately exceed ~1.5 and
  approach/exceed 1.6 (strongly correlated dynamics), so a **hard** upper bound risks failing the
  build on *correct* physiology at ride start. Make the upper bound a **soft/wide** check (or
  raise it well above 1.6).
- **R2-12 (validation prompt, EKF wording).** §2 and elsewhere assume the filter is an EKF;
  align with R2-1 (linear KF) once the white paper is corrected, so the harness does not bake in
  the same misclassification.
- **R2-13 (NP hard-check vs granularity caveat — note the tension, not a defect).** The harness
  hard-asserts `NP = 4th-root of 30 s rolling mean of power⁴` while the white paper (§3.1 Rev 2)
  flags rolling NP over short windows as unvalidated-at-granularity. This is *acceptable*
  (definitional identity ≠ validity claim), but add one line to the harness report noting the
  NP definition is checked for **coding correctness only**, not for validity at short-window
  granularity, so a reader does not infer the harness endorses the construct.
- **R2-14 (traceability dependency).** The validation prompt §4 traceability check is now backed
  by a real `docs/traceability.md` (good), but that file is a stub; the check is only as strong
  as the stub's completeness. Flag in the prompt that a passing traceability check on an
  incomplete stub is not meaningful coverage.

---

## 4. What Revision 2 gets right (credit)

- **Two self-caught defects fixed** — the α1-into-`F` coupling (the Rev 1 "fusion" was nominal)
  and the removal of the physiologically-wrong CP hard-gate. Both are real improvements beyond
  what Round 1 demanded.
- **The epistemic-status headers on both prompts** ("self-consistency ≠ external validity";
  "treat the docs as the *stated model*, not physiological ground truth") are model examples of
  honest tooling.
- **The `max`-hinge / graded intensity+duration charge** is a more faithful representation of
  real drift than the binary CP switch.
- **The provenance table's second axis** and the per-anchor N/replication notes directly answer
  Round 1's 1.1/1.2 and materially improve the document's scientific honesty.
- **Descriptive-not-imperative UI, persistent advisory tag, equal-weight evidence row, absolute
  α1 demotion, ACWR opt-in, criterion-validity pilot marked *owed*** — all correctly implemented.
- **The empirical base is unchanged from Round 1** (Rev 2 adds caveats, not new claims), and that
  base was independently PubMed-verified in Round 1; no new unverifiable citations were
  introduced.

---

## 5. Priority-ordered recommendations

1. **(R2-1)** Correct the EKF claim to a linear (time-varying) KF in both the white paper (§4.4)
   and the generation prompt (§Layer 2); the model is linear in the state as written.
2. **(R2-4)** Make heat handling consistent across `F` and the durability advisory — the two
   readouts currently disagree on hot days.
3. **(R2-2 / R2-3)** Acknowledge correlated measurement noise (HR & α1 share drivers) so AFI is
   not overconfident; add `c_F` to the hand-set/synthesis provenance row.
4. **(R2-5 / R2-6)** Specify and flag the `f()` seeding map and the projected-end tick; band or
   bucket them rather than showing point values.
5. **(R2-9)** Gate the `κ_d` charge on pedaling/movement; ensure recovery segments don't raise
   AFI; test it in the harness.
6. **(R2-7 / R2-8)** Relabel the observability study as a conditioning check; specify the
   AFI/decoupling blend and keep the 0–100 scale reference-consistent.
7. **(R2-10 → R2-14)** Fix the stale "productive-window" wording, loosen the α1 hard-bound to
   soft, align the harness's EKF/KF wording, and annotate the NP and traceability checks.

---

## 6. Summary severity table

| # | Issue | Severity | Type |
|---|---|---|---|
| R2-1 | "Nonlinear → EKF" is wrong; model is linear in the state (KF is exact) | Major | Technical correctness |
| R2-2 | Fusion double-counts correlated channels; diagonal-`R` → overconfident AFI | Major | Estimation / honesty |
| R2-3 | `c_F` is an unvalidatable cross-signal (α1↔bpm) calibration constant | Major | Model / provenance |
| R2-4 | Heat is signal for `F` but noise for the advisory — on-screen incoherence | Major | Internal coherence |
| R2-5 | `f()` seeding map unspecified/uncited; "fatigue added" is a soft-minus-soft point value | Major | Model / claim |
| R2-6 | Projected end-of-ride tick = forecast on hand-set constants, shown as a measurement | Major | Risk communication |
| R2-7 | Simulated observability proves math observability, not physiological identifiability | Moderate | Validation logic |
| R2-8 | AFI/decoupling blend underspecified → 0–100 scale drifts with RR quality | Moderate | Specification |
| R2-9 | `κ_d` accumulates `F` on recovery/coasting; stop-behavior unspecified | Moderate | Model behavior |
| R2-10 | Generation-prompt scope note still says "productive-window signal" | Minor | Consistency |
| R2-11 | α1 hard-bound [0.2,1.6] can false-fail on legitimate resting α1 | Minor | Harness bound |
| R2-12 | Validation prompt assumes EKF (align with R2-1) | Minor | Consistency |
| R2-13 | NP hard-check vs unvalidated-granularity caveat — annotate the report | Minor | Reporting |
| R2-14 | Traceability check only as strong as the stub it reads | Minor | Coverage |

*Verification note: I re-read the Rev 2 equations (§4.1–§4.5), the UI spec (§8), and both
prompts against the disposition table in `response.md` and confirmed the claimed edits are
present. The R2-1 linearity finding was derived by inspection of the transition/observation
equations in white-paper §4.2–§4.3. No new PubMed lookups were required this round, as Revision
2 adds caveats rather than new empirical claims; the underlying citations were verified in
Round 1.*
