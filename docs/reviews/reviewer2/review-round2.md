# Reviewer 2 — Second-Round Review (Revision 2)

**Documents reviewed (this round):** `docs/white-paper.md` (Rev 2),
`docs/prompts/scientific-validation-prompt.md` (Rev 2),
`docs/prompts/connectiq-app-generation-prompt.md` (Rev 2), plus the authors'
`docs/reviews/reviewer2/response.md` and the `docs/traceability.md` seed. Scope
is the **white paper and the two prompts**, per the review request.

**Reviewer stance:** unchanged — adversarial, and independent of the other
reviews in this folder (not read for this round).

**Recommendation:** *Minor revision → accept.* This is a serious, good-faith
revision. Every major concern from round 1 is either resolved or honestly
demoted with the disagreement flagged, and two of the fixes (the α1↔F coupling
and the observability caveat) required real structural work rather than wording.
The remaining items below are one genuinely **new** issue created by a Rev-2 fix,
a handful of **internal-consistency seams** where an old absolute-threshold or
imperative-verb problem survived the refactor in a different location, and minor
notes. None is fatal; none should block the criterion-validity pilot the
document now correctly owes. I would not require a third full round — a targeted
pass on §§4.2–4.5 and §8.1 would close these.

---

## 0. Verification of the response (did the revision actually land?)

I checked the response letter's dispositions against the document text rather
than taking them on trust. They hold up:

- **1.1 (no criterion validation)** — §10 now cleanly separates *calibration to
  self-consistency* from *criterion validation*, adds a concrete pilot
  (AFI/`F` vs power decrement / lactate / RPE, Bland–Altman per athlete), and the
  harness carries a skipped/`xfail` stub so the owed pilot is visible every run
  (`scientific-validation-prompt.md:60`). Abstract and §12 are re-scoped to
  "dashboard + advisory." **Resolved as far as documents can resolve it.**
- **1.3 (identifiability / observability)** — new §4.3a is exactly the honest
  statement I asked for ("on a steady ride, AFI is effectively a smoothed
  decoupling proxy"), and the harness now *requires a simulated observability
  study* (`scientific-validation-prompt.md:35`). **Resolved.**
- **1.4 (CP-gate)** — the hard gate is gone; charge is graded intensity+duration
  (`white-paper.md:105`); the wrong harness invariant is deleted and replaced
  (`scientific-validation-prompt.md:33`). **Resolved.**
- **1.2, 1.5, 1.6, 1.7, 1.8** — absolute α1 collapse retired to display-only;
  "independent" dropped and confounds named in-UI; DALE downgraded to "inspired
  by / functional form only"; power→α1 non-universality stated with a
  decoupling-only fallback; aggregate-fragility limitation added. All present in
  the text. The §9 note that the DFA-α1 base is **one overlapping author cluster**
  (Rogers/Gronwald) is a sharper point than I made — credit for volunteering it.
- **`traceability.md`** is a real seed with the evidence-strength column, a row
  for the new `C_F`, and the TRIMP coefficient flagged `UNRESOLVED` — not a hollow
  file. Good; the harness's traceability gate won't be vacuous.

The revision is faithful to its own changelog. What follows is what the changelog
did *not* catch.

---

## 1. New issue introduced by the Rev-2 fix (the one that matters this round)

### 1.1 Coupling α1 into `F` fixes observability but pipes α1's confounds straight into the fatigue state — and the fB mitigation is not wired to the filter

The Rev-1→Rev-2 fusion fix adds `−c_F·F` to the α1 transition
(`white-paper.md:104`) so that α1 innovations now update `F`. This correctly
addresses round-1 §1.3 (α1 was previously inert). But it has a side effect the
revision does not confront: **`F` now absorbs whatever moves α1, not only
fatigue.** The document itself establishes, in the *same revision*, that α1 in
the 4–16-beat band is "strongly shaped by respiratory sinus arrhythmia"
(`white-paper.md:78`) and is contaminated by artifact and by the non-universal
power→α1 map. Before the coupling, that contamination stayed in the (discarded)
α1 channel; after it, a breathing change on a climb, or a burst of RR artifact,
drives α1 below `A1_target(P)`, and the filter has no way to distinguish that
from fatigue — so it loads onto `F` and inflates AFI. The fusion improved
observability of `F` by giving it a second sensor, but that sensor's dominant
error modes are now fatigue-state errors.

The revision *gestures* at the fix — §3.3 says to derive **fB from the RR stream
and use it to flag ventilation-driven α1 movement** — but that mitigation is not
connected to the filter. In §4.2 the α1 transition has **no fB term** and no
mechanism to de-weight the α1→`F` innovation when fB indicates the α1 drop is
respiratory. fB is computed for a display flag; `F` still eats the
respiration-driven α1 drift. So the mitigation and the vulnerability live in
different sections and never meet.

**Recommended fix (small, concrete):** make the α1 measurement-noise `R_A1` (or
the coupling gain's effective weight) a function of fB — inflate α1's `R` when fB
is changing rapidly, so respiratory-driven α1 excursions contribute little to
`F`. State in §4.3a that `F` absorbs α1-channel confounds (respiration, artifact,
map error), not only HR-channel confounds. And add a harness check
(§2/§3): inject a **respiration-only α1 excursion at constant power and constant
true fatigue** and assert `F`/AFI does **not** materially rise. Without that, the
"fusion" can manufacture fatigue out of breathing.

---

## 2. Internal-consistency seams (old problems that survived the refactor elsewhere)

### 2.1 The absolute threshold was retired from α1 but survives in AFI>85

§4.5 retires the absolute α1 cutoff and states "verdict gating uses only the
per-athlete drift-below-baseline signal" (`white-paper.md:158`). Good — but the
**severe-band row still fires on `AFI > 85`** (`white-paper.md:156`), and
`AFI = 100·clamp(F/F_ref)` with `F_ref` the admittedly-arbitrary ~12 bpm
(`white-paper.md:146`). So `AFI > 85` is just `F > ~10.2 bpm of drift` — an
**absolute HR-drift threshold set by an unvalidated constant**, i.e. exactly the
kind of population-absolute cutoff the α1 retirement was meant to eliminate. The
absolute threshold was not removed; it was moved from the α1 channel to the AFI
channel. Since §4.5 already concedes AFI is linear in 1/`F_ref` and that `F_ref`
sets the whole scale, the severe verdict inherits that arbitrariness. Recommend
either (a) gate severe on AFI **drift relative to the athlete's own rolling
AFI-for-power** (parallel to the α1 treatment), or (b) state explicitly that
`AFI > 85` is a convention-grade band whose position is `F_ref`-dependent and
must be calibrated — and add it to the §9 provenance table, which currently has
no row for the AFI band cutoffs themselves.

### 2.2 "No imperative verdict" is stated as a principle but the amber band keeps an imperative

Rev 2's stated rule is descriptive-not-imperative, and the harness asserts the
app "never emits a directive 'TURN BACK'/'STOP' string"
(`scientific-validation-prompt.md:37`). But the amber status band is
**"FATIGUE BUILDING — EASE SOON"** (`white-paper.md:210`,
`connectiq-app-generation-prompt.md:51`). "EASE SOON" is a directive verb phrase
— it tells the rider to do something — and it passes the harness only because the
harness blacklists the two specific strings "TURN BACK"/"STOP" rather than
checking for imperative mood. So either the principle ("no directive verb on
unvalidated logic") is overstated, or the amber copy violates it. Pick one:
reword amber to descriptive ("fatigue markers building") to match the principle,
**or** relax the principle to "no *strong* directive on the red/durability
advisory, mild guidance permitted" and say so. As written, the document asserts a
rule its own UI copy breaks, and the harness can't catch it.

### 2.3 Asymmetric treatment of the two correlated channels: α1 is now per-athlete, decoupling is still absolute

The revision's central α1 move is "prefer per-athlete drift-below-baseline over a
population absolute." Sound. But the durability advisory's decoupling trigger is
still the **absolute** ">8% at steady power" (`white-paper.md:185`) — a
Friel/TrainingPeaks convention — even though §3.1's new caveat establishes that
sub-threshold decoupling is low-SNR (mean ≈2%, SD ≈ mean;
`white-paper.md:66`). The same argument that moved α1 to a personal baseline
applies to decoupling: an absolute 8% cutoff on a noisy, individually-variable
channel is exactly what you rejected for α1. For consistency, either move the
decoupling trigger to a per-athlete baseline-drift as well, or justify why the
two correlated channels get different treatment. Right now the choice looks
incidental rather than principled.

### 2.4 The recalibrated charge and the unchanged `F_ref` may not be jointly consistent

Two Rev-2 changes interact and were not checked against each other. (a) The
intensity charge now starts at **P_AeT** (≈0.75·FTP), not CP
(`white-paper.md:105,131`), and (b) a duration term `κ_d` now charges `F`
continuously even at Z2. Yet (c) `F_ref` is unchanged at "end-of-**hard**-ride
drift, ~12 bpm" (`white-paper.md:146`). With charge now accruing across most of
the tempo range *plus* a standing duration term, `F` will climb on long moderate
rides far more than in Rev 1 — but it is still normalized by an
end-of-*hard*-ride reference. The plausible failure mode is **AFI saturating (or
reading "high") on long endurance rides**, which would undercut the whole
Feat/Attrition distinction (a 4 h Z2 ride should read as productive attrition-low,
not near-max AFI). This may be fine after tuning, but the two changes need to be
tuned *together*, and §4.4 should note the coupling. A harness plausibility check
would help: assert a long steady Z2 ride yields AFI in a moderate band, not the
severe band.

### 2.5 §4.5 still implies AFI is corroborated by decoupling, which §4.3a denies

§4.5 says AFI is "cross-checked against, and blended with, the model-free
decoupling%" (`white-paper.md:148`), phrasing that implies independent
corroboration. But §4.3a now states that on steady rides "AFI is effectively a
smoothed decoupling proxy." You cannot cross-*check* a quantity against something
it approximately equals. Minor, but reword §4.5 to "blended with decoupling as a
graceful-degradation fallback (note: on steady rides these are near-identical, so
this is a fallback, not an independent check)" to stay consistent with §4.3a.

---

## 3. Minor notes

- **`c_F`'s exchange rate is an invented constant that may contradict the cited
  data.** `c_F` is tuned so `F ≈ F_ref` depresses α1 by "~0.2"
  (`white-paper.md:133`). That number couples two independently-unvalidated
  constants by an assumed physiological exchange rate (12 bpm of drift ⇔ 0.2 of
  α1), and it sits uneasily next to the one cycling datapoint the docs lean on:
  Rogers 2025's α1 fell ~1.2→~0.75 (≈0.45) at task failure. If end-of-hard-ride
  `F_ref` corresponds to task-failure-adjacent fatigue, 0.2 looks low by ~2×; if
  it doesn't, the mapping needs a stated rationale. Either way `c_F`'s 0.2 anchor
  deserves its own line in §4.4's honesty note rather than being folded silently
  into "hand-set." The traceability row for `C_F` exists — good — but lists it as
  "tuned," not as encoding a specific (and possibly off) physiological claim.

- **The observability harness test verifies structural observability, not
  correctness — label it so.** The required test generates ground-truth `F(t)`
  from the model, then asserts recovery (`scientific-validation-prompt.md:35`).
  Because the generator and the filter share the generative model, a passing
  result demonstrates the observability Gramian is non-degenerate under
  variable power — real and worth having — but it is not evidence the *real*
  `F(t)` follows that model. The prompt mostly scopes this correctly; add one
  sentence to the report spec stating the test proves recoverability-under-the-
  assumed-model, so no reader mistakes a green observability check for external
  validity.

- **Sex is collected but unused beyond TRIMP.** The generation prompt exposes
  `sex` as a setting (`connectiq-app-generation-prompt.md:65`) and §11 now flags
  sex generalizability as an output limitation (good), but nothing in the model
  consumes `sex` except the (still-ambiguous) Banister female coefficient. That's
  the honest floor given the male-dominated evidence base, but worth a one-line
  acknowledgement that collecting sex does not mean the bands are sex-adjusted —
  otherwise a user may reasonably infer personalization that isn't there.

- **ACWR (standing disagreement).** I recommended deletion; you demoted to
  opt-in/off-by-default with the Lolli/Impellizzeri critique linked in-UI and
  flagged the disagreement honestly (`white-paper.md:174`). I accept the
  compromise — the honest in-UI critique plus off-by-default is defensible
  engineering — with one residual caution: a user who opts in still sees a number
  that *looks* like a risk score regardless of the disclaimer, because a single
  ratio with a "danger >1.5" heritage reads as predictive. If you ever see it
  misused in the field, revisit deletion. Not a blocker.

- **TRIMP female coefficient** is now correctly flagged as a defect to resolve
  before shipping, in both the white paper's provenance table and
  `traceability.md` (`UNRESOLVED (0.86 vs 0.64)`). Good — just don't let the
  `xfail`/flag culture become a way to ship the ambiguity; it must be resolved or
  exposed as a setting before code, as the generation prompt now says
  (`connectiq-app-generation-prompt.md:36`).

---

## 4. Summary verdict

**What round 2 got right:** the reframing from "meter" to
"calibrated dashboard + advisory" is now load-bearing, not cosmetic; the
observability caveat and the α1↔F coupling are real structural fixes; the
provenance table's split of *extraction confidence* vs *evidence strength*
(plus the single-author-cluster note) is better epistemic hygiene than most
published models manage; and the harness is now honestly labeled a
*consistency* engine with the owed criterion-validity pilot kept visible as a
skipped test. The response engaged the *reasoning*, not just the wording.

**What remains:** one substantive new issue — (1.1) coupling α1 into `F` pipes
α1's respiratory/artifact confounds into the fatigue state, and the fB
mitigation is computed but never wired into the filter; and a cluster of
internal-consistency seams where a retired problem reappeared in a new location
(2.1 absolute threshold now lives in AFI>85; 2.2 the "no imperative" rule vs the
amber "EASE SOON" copy; 2.3 α1 personalized but decoupling still absolute; 2.4
recalibrated charge vs unchanged `F_ref`). These are edits to §§4.2–4.5 and §8.1
and two added harness checks — not another architecture rethink.

**Bottom line:** the documents now claim only what the evidence supports and
label the gap between the two persistently and in the UI. Fix 1.1 (or explicitly
accept and disclose it), reconcile the four consistency seams, and this is an
honest, shippable specification for a durability/decoupling advisory — with the
criterion-validity pilot still the one thing standing between "advisory" and
"instrument."

---

*Note: this round relied on document inspection only; no new external citations
were checked, as the evidence base was audited in the first-round review.*
