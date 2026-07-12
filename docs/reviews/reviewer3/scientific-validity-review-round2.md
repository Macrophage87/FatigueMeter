# Reviewer 3 — Second-Round Scientific-Validity Review (Revision 2)

**Documents under review (Revision 2)**

- `docs/white-paper.md` (Rev 2)
- `docs/prompts/scientific-validation-prompt.md` (Rev 2)
- `docs/prompts/connectiq-app-generation-prompt.md` (Rev 2)
- `docs/traceability.md` (new stub)
- `docs/reviews/reviewer3/response.md` (authors' disposition of my first-round review)

**Scope & independence.** This is an independent second round on the **white paper and the two prompts**, as requested. I have not read the other reviewers' rounds or their responses, and I do not rely on them. Where I reference the literature review or references file it is only because the white paper depends on them.

**Method.** I did not take the response letter at face value. For each claimed fix I went to the actual spec text to confirm it landed and to judge whether it is *substantively* sound rather than merely worded to satisfy the objection. I then re-read the revised equations and prompts fresh, looking for new problems the revision introduced.

---

## 1. Summary judgment

The revision is **faithful and substantive** — unusually so. Every first-round point was accepted, and I confirmed the changes are present in the specs, not just asserted in the response. Several are genuinely well-executed: the honest reframing to a "durability/decoupling dashboard with an advisory," the descriptive-not-imperative status band, the demotion of the absolute α1 band to display-only, the separation of *extraction confidence* from *evidence strength* in §9, the retirement of the pseudo-quantitative "vote" grading, and — notably — the **new, more honest** self-critiques the authors added beyond what I asked (e.g., the Rothschild R²=0.95 row now correctly flagged **in-sample, not out-of-sample**; the DFA-α1 evidence base flagged as **one overlapping author cluster**, i.e. methodological consistency ≠ independent replication). That last point is exactly right and I had not made it.

Two accepted fixes are **correct in structure but limited in effect**, and the documents should say so more sharply (§2 below). The revision also **introduces or leaves standing** a handful of new issues (§3–§5). None is disqualifying; none reopens a first-round finding. But one **standing scientific-stance question** now dominates and deserves a decision rather than another caveat (§6).

**Verdict:** Accept the revision. The remaining items are refinements and one policy decision, not a re-litigation.

---

## 2. The two fixes that are structurally right but weaker in effect than the prose implies

### 2.1 The α1↔F coupling (my first-round §2.2) is now real — but it buys little information, and that matters

The fix is correct: adding `−c_F·F` to the `A1` transition (white paper §4.2) creates a genuine path from `F` to the measured `A1`, so α1 innovations now update `F`. The Rev 1 zero-coupling defect is closed, and the validation prompt now guards it with a regression test ("injecting a below-target α1 measurement moves `F`"). Good.

But the document should not let the reader infer that the filter now *extracts* a fatigue signal the sensors didn't contain. Trace the dynamics on the regime durability monitoring actually targets — **constant power**:

- In the predict step, `F` charges by `[κ_i·max(0,P−P_AeT) + κ_d]·Δt` every second. At constant power this is a **constant**, so `F` follows a near-deterministic charge-toward-equilibrium ramp set entirely by `κ_i, κ_d, τ_rec`.
- In the update step, `F` is corrected by HR and α1 innovations. HR's information about `F` is weak (the §4.3a confound with `g_P`/thermal drift), and α1's is high-`R` (slow, noisy) and, on a steady ride, is the *only* channel carrying `F` — precisely where α1 is also most exposed to the RSA/artifact/nonstationarity confounds of §3.3.

**Consequence, stated more sharply than §4.3a does:** on a steady ride, `F` (and therefore AFI) is dominated by the **process-model prior** — the assumed charge rate `κ` — lightly nudged by two weak, correlated measurement channels. The white paper's own framing, "AFI ≈ smoothed decoupling," is actually *generous*: on constant power AFI is closer to **a hand-tuned time-ramp weakly corrected by decoupling/α1**, i.e. it substantially reflects the *tuning of `κ`*, which is itself unobservable and hand-set (§4.4). This is not a reason to remove the coupling — it is a reason to state that the coupling makes the fusion *structurally* honest without making AFI *informationally* independent of its priors on the rides where it will most be read. Recommend adding one sentence to §4.3a to this effect.

### 2.2 The coupling introduces a new unidentifiable parameter, `c_F`, defined in terms of other synthesis constants

`c_F` is "tuned so F ≈ F_ref pulls α1 ~0.2 below its power-predicted value" (§4.4). But `F_ref` is an unvalidated ~12 bpm default, and "its power-predicted value" comes from the `A1_target` sigmoid that PMC11280911 shows is **not universal**. So the coupling gain is calibrated against two other hand-set constants — a stack of synthesis values defining each other, none identifiable from data until the criterion-validity pilot runs. This is disclosed piecewise across §4.4, but the *composition* (c_F depends on F_ref depends on the non-universal sigmoid) is not surfaced. The traceability stub should carry a note that `C_F` inherits the weakness of `F_REF` and `A1_SIGMOID`.

---

## 3. New issues in the revised Layer-2 equations

### 3.1 The AFI blend is under-specified — and now it is the headline number

§4.5 defines `AFI = 100·clamp(F/F_ref, 0, 1)` and, in the same paragraph, says AFI is "blended with the model-free decoupling%." These are two different definitions and no blend weight or switch-over rule is given. Because decoupling and `F` are correlated (they are two windows on the same drift), the blend weight materially changes AFI's behavior and its response to RR dropout. This was tolerable when AFI was one of several outputs; in Rev 2 AFI is *the* headline index on the dial (§8.1) and seeds/derives start- and end-of-ride fatigue. Specify the blend explicitly — weights, the RR-quality threshold at which it hands over to decoupling-only, and whether the hand-over is continuous or hard — or an implementer will invent it and the "advisory" will vary by implementation.

### 3.2 The "projected end-of-ride" AFI tick is the least-supported number on the screen and carries no caveat

§8.1 item 2 shows three ticks on the AFI dial: start, now, and **"projected end-of-ride at the current effort."** Projection means forward-integrating `F` under an assumed future power and the (unvalidated, hand-tuned, weakly-observable) `κ` dynamics — it compounds *every* uncertainty in Layer 2 and extrapolates it into the future, then renders it as a concrete tick beside two nominally-measured ones. It is not in the §9 provenance table and gets no persistent tag beyond the general banner. Either drop the projected tick pre-pilot, or render it visibly as a shaded *range* with an explicit "model projection" label — it should not sit on the dial with the same visual authority as "now."

### 3.3 Two intensity anchors, undocumented (minor, likely intentional)

The `F` charge now gates at `P_AeT` (§4.2), while the kJ weighting (§3.2), W′bal, and FeatScore's "severe domain" all gate at `CP`. Using AeT for drift-onset and CP for the severe/anaerobic constructs is physiologically defensible, but the document never says the split is deliberate, and a reader (or the app-builder) may treat it as an inconsistency. Add a one-line rationale.

### 3.4 The `κ_d` duration term charges unconditionally (minor; magnitude negligible)

`F`'s charge includes a constant `κ_d` applied every step regardless of power, so it also charges during stops/coasting (P=0). With the suggested `κ_d` (~3 bpm over 2 h) the stopped-state equilibrium is ~0.4 bpm and `τ_rec` still recovers `F` during a stop, so the practical effect is negligible — but conceptually the duration/thermal charge should gate on "active" rather than wall-clock. A one-line guard (charge `κ_d` only when riding) removes the conceptual wart.

---

## 4. New issue in the durability advisory (§6): the stationarity gate quietly undermines the advisory it feeds

The stationarity gate (§3.3) is the right call and I asked for it. But note its interaction with §6. The advisory draws on three markers: (1) intensity-weighted kJ, (2) decoupling >8% after the steadiness gate, (3) **per-athlete α1 drift**. On real outdoor rides, steady power is the exception, so the stationarity gate will **frequently suppress α1** exactly when the rider is doing variable-terrain work. When α1 is suppressed, the advisory reduces to kJ (a deterministic function of elapsed time) plus decoupling — i.e., **one drift channel past a time threshold.** So in field conditions the "corroboration among markers" the advisory advertises often collapses to a single informative signal. This is a direct and unacknowledged consequence of two correct Rev 2 changes acting together. The advisory copy and §6 should state that, on variable-power rides where α1 is gated out, the advisory rests on decoupling alone and should be weighted accordingly (it is closer to "decoupling is high and you've done a lot of work" than to multi-marker agreement).

---

## 5. Review of the two prompts

### 5.1 Scientific-validation prompt (Rev 2) — strong, with one methodological flaw in the pilot and minor residue

The rewrite is good. The epistemic-status header ("self-consistency ≠ external validity"), the ensemble-mean/wide-tolerance softening of the α1 monotonicity checks with an explicit **prohibition on per-run monotonicity**, the removal of the wrong "no sub-CP drift" invariant, the new **α1↔F wired** and **`F` observability** tests, the **stale-CP propagation** scenario, the **descriptive-not-imperative** assertion, and the **xfail criterion-validity stub** all map cleanly to the right concerns. This is a well-constructed harness spec.

Two issues:

- **The proposed criterion-validity pilot is mis-designed on one point (white paper §10 and prompt §5).** It calls for **Bland–Altman analysis per athlete** of AFI/`F` against "sustained-power decrement, lactate, RPE, next-day readiness." Bland–Altman assesses agreement between **two methods measuring the same quantity in the same units**; AFI is a 0–100 index and a 5-min-power decrement is watts — different constructs and units, so Bland–Altman is the wrong tool here. What you want is a **calibration/association analysis** (rank correlation, or a fitted calibration curve with cross-validated error), reserving Bland–Altman for the case where AFI is first expressed in the units of a chosen reference. Separately, **n=5 per athlete cannot establish criterion validity** — it is a proof-of-concept that can detect only very large associations and cannot pin agreement limits. Label the pilot honestly as *feasibility/proof-of-concept*, not validation, and size a real study before any "validated" claim.
- **Residual, correctly disclaimed:** the harness still cannot test the thing that matters (external validity) — the prompt says so plainly now, which is the right disposition. No change needed beyond the pilot-design fix above.

### 5.2 Connect IQ generation prompt (Rev 2) — faithful to the revised white paper; minor terminology drift

The prompt tracks Rev 2 accurately: EKF with the `−c_F·F` coupling called out as "the fusion mechanism — without it, α1 does not inform `F`"; the no-CP-hard-gate instruction; `F` renamed and the VO₂-slow-component label explicitly banned "in code or UI"; the stationarity + steadiness gates; ACWR opt-in/off-by-default; the Banister-coefficient defect; Feat/Attrition off the critical path; descriptive status band with a persistent "advisory · not validated" tag; α1 absolute value display-only. This is a good, buildable brief.

Minor: the scope note (line 5) still says the generator ships "the Acute Fatigue Index, on-ride display, **productive-window signal**, and start/end fatigue" — "productive-window signal" is the pre-Rev-2 name for what §6 now calls the **durability advisory**. The white paper likewise retains the word "verdict" in several places (§4.5, §6, §8.1's design rules) while insisting the output is not a directive. These are harmless internally but, in a project whose whole thesis is that *wording controls how confidently a rider reads the screen*, the residual "signal/verdict" vocabulary undercuts the point. Sweep the terminology so the specs say what the UI says.

### 5.3 Traceability stub — good, and it does its job

The stub is well-formed: it seeds the file so the harness's traceability check won't fail on a missing file, states the rule ("no physiological constant in code without a row here; a constant with no provenance is a defect"), and pre-populates the evidence-strength column with the honest notes (DALE "does not transfer to `F`"; `F_REF` "AFI linear in 1/F_ref — sets whole scale"; Banister coeff "UNRESOLVED — defect"). Add the `C_F` row (§2.2) and a `PROJECTED_AFI` row (§3.2) when those land in code.

---

## 6. The one decision that should replace the next caveat

Rev 2's discipline is now excellent — but it has reached the point where **almost every subsection carries a callout admitting the fused output is unvalidated, weakly observable, prior-dominated, or confounded.** The documents resolve this by *shipping AFI now, behind labels, with validation "owed."* I want to put the alternative squarely on the table, because it is the more defensible scientific stance and the documents do not currently weigh it:

> **Do not display AFI as a 0–100 number until the criterion-validity pilot returns a positive result.** Pre-pilot, show only the **validated backbone** — decoupling, kJ-vs-anchor, CTL/ATL/TSB, the population α1 anchor — plus, at most, a **coarse 3-state categorical** ("fresh / building / high") rather than a precise index and a projected-end tick. A number on a dial reads as a measurement no matter how many tags surround it; a large body of usability evidence says users anchor on the digit and discard the disclaimer. Honesty-by-labeling has a ceiling, and a weakly-observable, prior-dominated, externally-unvalidated fatigue *number* is above it.

This is not a demand to delete Layer 2 — it is a request to gate its **most measurement-like presentation** (the 0–100 index, the projected tick, the start/now/end deltas quoted to the point) on the one piece of evidence the project agrees is missing. The authors already wrote the pilot into §10 and left it visibly owed via an xfail stub; the logical next step is to make the pilot a **release gate for the numeric AFI**, not just a documented debt. If the team decides to ship the number pre-pilot anyway, that is a legitimate product call — but it should be recorded as a *decision taken against this recommendation*, not folded into the general "advisory" caveat.

---

## 7. Disposition of my first-round findings (verified against the Rev 2 specs)

| First-round finding | Status in Rev 2 (verified in spec) |
|---|---|
| 2.2 α1 does not inform `F` (no real fusion) | **Resolved structurally** (`−c_F·F` in §4.2 + wired-test in harness); effective-information caveat is the only residue (§2.1 here) |
| 2.1 `F` mislabeled as VO₂-slow-component proxy | **Resolved** — renamed "residual cardiovascular-drift state," label banned in code/UI |
| 2.5 flagship verdict on an admitted void; false "independence"; imperative verb | **Resolved** — "independent" dropped, confounds named in-UI, descriptive not imperative; new §4 practical-degradation note remains |
| 2.6 Feat/Attrition composite gating the verdict | **Resolved** — off the critical path, shown as raw evidence |
| 2.7 harness validates self-consistency, not validity; α1 monotonicity too strong | **Resolved** — renamed model-consistency, epistemic header added, checks softened to ensemble-mean, per-run monotonicity prohibited |
| 2.8 non-standard "vote" grading | **Resolved** — retired; extraction confidence separated from evidence strength |
| 2.4 group-level r used for individual decisions | **Resolved** — §9 leads with ±10 bpm LoA; absolute α1 band display-only |
| 2.3 α1 fatigue-use thin/field artifact | **Resolved** — n≈28/2-of-3-running stated; stationarity gate + uncharacterized-field-artifact admission added |
| §3 generalizability / aggregate n<20 | **Resolved** — now the first bullet of §11 |
| §4 NP short-window / stale-CP chain / confounders | **Resolved/partially** — steadiness gate added; stale-CP caveat + harness check added; confounders now "disclosed-not-modeled" as a stated limitation |
| §1 citation conflation / ICC drift | Reported fixed in the literature review (outside this round's scope; not re-verified here) |

Nothing from round one is reopened.

---

## 8. Required/recommended for this round

**Should address (substantive):**

1. Add the sharper observability statement to §4.3a — on steady rides AFI is prior-dominated (reflects `κ` tuning), not an independent measurement (§2.1).
2. Specify the AFI/decoupling blend explicitly (weights + hand-over rule); it is now the headline number (§3.1).
3. Fix the pilot's statistics: Bland–Altman is the wrong tool for AFI-vs-external-criterion (unit mismatch); relabel n=5 as proof-of-concept, not validation (§5.1).
4. State in §6 that when the stationarity gate suppresses α1 (the outdoor norm), the advisory rests on decoupling alone and must be weighted down accordingly (§4).
5. Decide, and record, whether the numeric AFI ships pre-pilot or is gated on it (§6).

**Nice to have:**

6. Down-caveat or range-render the "projected end-of-ride" tick (§3.2).
7. One-line rationale for the AeT-vs-CP anchor split (§3.3); gate `κ_d` on "active" (§3.4).
8. Note `c_F`'s dependence on `F_ref`/sigmoid in the traceability matrix (§2.2); add `C_F` and `PROJECTED_AFI` rows.
9. Terminology sweep: retire the leftover "productive-window signal" (generation prompt line 5) and "verdict" (white paper) so the spec vocabulary matches the deliberately-softened UI vocabulary (§5.2).

---

## 9. Closing

This is a model revision: faithful, verifiable, and in several places *more* self-critical than the review demanded. The two structural claims I flagged as unsupported in round one are now, respectively, made true by construction (the α1↔F coupling) and withdrawn (the slow-component label). What remains is not a set of errors so much as the honest residue of building an inferential product on top of markers validated only for threshold estimation, in the lab, in mostly-male samples — and the documents now say almost all of that out loud. The last mile is to stop *adding caveats* to the fused numeric output and instead *make a decision* about it: gate the AFI number on the external pilot the project already admits it owes, or ship it as an explicit exception to this recommendation. Either is defensible; drifting is not.

---

*Reviewer 3, second round. Rev 2 changes verified by reading the revised `white-paper.md` and both prompt files directly (not solely the response letter). Prior-round PubMed verifications (Barsumyan 2026, [DOI](https://doi.org/10.1186/s13102-026-01678-w); Rogers et al. 2025, [DOI](https://doi.org/10.1007/s00421-025-05716-2)) stand; no new external citations were introduced in Rev 2 requiring re-check.*
