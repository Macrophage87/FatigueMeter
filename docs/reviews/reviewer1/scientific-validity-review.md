# Reviewer 1 — Scientific-Validity Review of the FatigueMeter Documentation

**Reviewer:** Reviewer 1 (exercise physiology / physiological signal processing / estimation)
**Date:** 2026-07-12
**Materials reviewed:**
- `docs/literature-review.md`
- `docs/white-paper.md`
- `docs/references.md`
- `docs/prompts/scientific-validation-prompt.md`
- `docs/prompts/connectiq-app-generation-prompt.md`

**Overall recommendation:** *Accept with revisions.* The documentation is unusually
rigorous and self-critical for this genre, its reference base is real and accurately
summarized (I independently verified a sample — see below), and its honesty discipline
(provenance flags, calibration gating, "not a medical device") is a genuine strength.
However, several scientific-validity issues are under-weighted relative to how load-bearing
they are, and a few claims are overstated. None is fatal; all are addressable in the text
and in the design. Details below, graded by severity.

---

## 0. Independent verification I performed

Because a central risk in an AI-assembled literature base is fabricated or misattributed
citations — and because several references here are dated 2025–2026 — I did not take the
documents' own verification flags at face value. **According to PubMed**, I confirmed the
following load-bearing / most-suspicious citations are real and are summarized accurately:

- **Barsumyan et al. (2026)**, *BMC Sports Sci Med Rehabil* 18(1), PMID 41923151 — verified.
  Title, cohort (17 trained cyclists, 60 min at 75% FTP, 5 months, 85 paired obs), and the
  key slopes (b = 0.61 drift, b = 0.58 decoupling; r = 0.40 / 0.38) match the abstract.
  [DOI](https://doi.org/10.1186/s13102-026-01678-w)
- **Rogers, Fleitas-Paniagua, Trpcic, Zagatto, Murias (2025)**, *Eur J Appl Physiol*
  125(6):1619–1631, PMID 39904800 — verified. Cycling TTF at 95% RCP, n=10, Control vs Reward,
  metabolic stability over Q2–Q4 while HR/DFA-α1/fB drift; the abstract confirms the design and
  the ICC 0.73–0.94 range. [DOI](https://doi.org/10.1007/s00421-025-05716-2)
- **Rothschild et al. (2025)**, *Eur J Appl Physiol* 125(10):2911–2920, PMID 40402269 —
  verified. 51 trained cyclists, ~2.5 h; HR decoupling r = −0.76; final GEE model
  (baseline VT₁, VO₂peak, F_R decoupling, HR-decoupling × duration) MAE ≈ 7.2 W, R² = 0.95.
  [DOI](https://doi.org/10.1007/s00421-025-05815-0)
- **Gronwald et al.** DFA-α1 exercise program — verified as a real, active line of work
  (e.g. constant-workload cadence study, *Hum Mov Sci* 2018, PMID 29966866,
  [DOI](https://doi.org/10.1016/j.humov.2018.06.013); normobaric-hypoxia constant-workload
  study, *Front Physiol* 2019, PMID 31427992,
  [DOI](https://doi.org/10.3389/fphys.2019.00999)).

I could not surface **Gløersen (DALE, 2022)** or **Rogers/Olson/Gronwald (2020)** through
PubMed text search (likely indexing/diacritic issues; both carry plausible DOIs in
`references.md`). Given that every checkable citation resolved and matched, I have no reason
to doubt them, but they remain unverified by me.

**Bottom line on sourcing:** the evidence base is genuine and faithfully transcribed. The
problems below are not "the citations are fake" — they are about *how strong the cited
evidence actually is*, *how far it generalizes to this app's operating conditions*, and *how
the documents grade their own confidence*.

---

## 1. Major concerns

### 1.1 The "adversarial fact-checking / vote" flags measure citation confidence, not scientific strength
`literature-review.md` uses flags such as `[confirmed] = adversarially fact-checked or
corroborated across ≥2 primary sources`, and reports outcomes like *"refuted in adversarial
fact-checking (0–3)"* and *"[partial — 2-1 verification vote]"*. These describe the
**confidence that a claim was correctly extracted from a source** — an LLM/agent
verification process. They do **not** measure the strength of the underlying physiological
evidence, and the "0–3" / "2-1" vote notation should not be read as if it carries
epistemic weight about the biology. A claim can be extracted with perfect fidelity (`[confirmed]`)
from a study that is itself n=8, single-group, and lab-bound.

**Why it matters:** a reader — or a downstream LLM consuming these docs as "the consensus"
(exactly what `scientific-validation-prompt.md` instructs) — will conflate *"we are sure the
paper says X"* with *"X is established science."* These are different axes.

**Recommendation:** split the flag into two orthogonal dimensions and state both:
(a) **extraction/citation confidence** (did we read it correctly), and (b) **evidence
strength** (sample size, replication, independence, effect size, generalizability). Retire
the "N–M vote" language from the physiological claims, or relabel it explicitly as
"extraction-agreement," not "verification."

### 1.2 The DFA-α1 core rests on a single research cluster and single-digit samples
The acute engine's central real-time signal is DFA-α1, and the review repeatedly cites
"corroboration across ≥2 (or ≥4) sources." In fact the DFA-α1-in-exercise literature is
**dominated by one overlapping author cluster** (Rogers, Gronwald, Hottenrott, Hoos, and
collaborators). "Confirmed across ≥4 sources" for the computation parameters is really
"≥4 papers from an overlapping group using the same method" — that is *methodological
consistency*, not *independent replication*. The samples are uniformly tiny: n=15 (2020
threshold paper), n=8, n=10 (2025 TTF), n=7 (ultra), n=11 (marathon), and **n=1** for the
"real-time on-device feasibility" field paper (`references.md` flags this honestly, but the
white paper's confidence framing does not carry it forward).

**Recommendation:** in both the review's §4 and the white paper's §9 provenance table, add
an explicit "**independent-replication / sample-size**" column and stop treating same-group
repetition as multi-source corroboration. Foreground that the entire acute layer is built on
teens-of-subjects evidence from a narrow group.

### 1.3 External-validity gap: lab steady-state validation → free-living variable-power cycling
This is, in my judgment, the **single largest threat to the acute engine**, and it is
under-weighted. Essentially all DFA-α1 validation was collected under controlled conditions:
constant-workload or incremental ramps, fixed or scheduled cadence, ergometer, chest strap,
low artifact. DFA-α1's short-term scaling estimate presumes a degree of local stationarity in
the RR series.

FatigueMeter is specified to run **outdoors, on a 2-minute rolling window recomputed every
5 s** (white paper §3.3), during real riding that includes coasting, surges, stops, cornering,
gear/cadence shifts, drafting, and road-buzz motion artifact. A moving 2-min window will
routinely **straddle large power transients**, violating the conditions under which α1 was
validated. None of the cited work establishes DFA-α1 behavior under free-living
variable-power cycling. The n=1 field paper is the closest and is exactly that — n=1.

**Recommendation:** state this gap prominently as a first-order limitation (currently
Limitation §11 mentions artifact but not the stationarity/variable-power problem). Add a
concrete mitigation to the design: gate α1 not only on artifact % but on **power/HR
stationarity within the window** (e.g. suppress α1 when within-window power CV or coasting
fraction exceeds a threshold), and validate α1 output on real outdoor rides before trusting
within-ride drift.

### 1.4 The "independent signals" in the productive-window logic are not independent
The productive-window verdict (white paper §6) fires when **≥2 of 3** signals agree:
(1) intensity-weighted kJ near the durability anchor, (2) rolling decoupling >8%, and
(3) DFA-α1 drift/collapse. This is framed as *"requiring agreement of independent Layer-1
signals rather than trusting any one."* They are **not independent**:

- **Decoupling and α1 drift both track the same underlying cardiac/autonomic drift** at fixed
  power — they are two windows onto one process, not two votes.
- **Cadence independently drives DFA-α1.** Verified from Gronwald et al. 2018 (*Hum Mov Sci*,
  PMID 29966866, [DOI](https://doi.org/10.1016/j.humov.2018.06.013)): at higher cadence α1
  falls significantly, independent of duration/fatigue. Since Barsumyan's central finding is
  that fatigued riders *drop cadence to hold power*, a rider's α1 will move partly as a
  **cadence artifact**, not a fatigue signal — and the app also uses cadence decline as a
  separate fatigue vote (white paper §3.4). The votes share drivers.
- **Respiratory frequency drives DFA-α1** (the Network Physiology framing the review itself
  invokes). The design also wants to use fR (derived from the *same* RR stream), so α1 and fR
  double-count a shared respiratory driver, and voluntary/involuntary breathing changes move
  α1 without any change in fatigue.
- **Shared confounds defeat the 2-of-3 gate.** Heat inflates decoupling, depresses α1, and —
  because it lengthens any effort — pushes the kJ clock. A hot day can therefore trip 2-of-3
  *simultaneously and falsely*. The heat suppression is applied to decoupling only (§3.1),
  but α1 is heat-sensitive too, so the gate is not protected.

**Recommendation:** stop describing the three signals as "independent." Either (a) build the
verdict from signals with genuinely distinct physiology (e.g. kJ clock + power-at-fixed-HR
drift + W′/severe-domain time), or (b) keep the current signals but model their shared
confounds explicitly (cadence-normalize α1; apply heat suppression to α1 as well as
decoupling) and describe the gate as "corroboration among correlated signals," which is
weaker but honest.

### 1.5 The fused acute state `F` is weakly observable and its physiological label is an interpretive leap
The Layer-2 Kalman state `F` is called *"the on-bike proxy for the VO₂ slow component /
efficiency loss"* (white paper §4.1, §4.2). Two problems:

1. **Observability.** With only HR and α1 as measurements and power known, `HR_ss` is pinned
   by the static power→HR gain, so `F` necessarily **absorbs whatever residual HR drift the
   power term cannot explain.** But that residual is not the VO₂ slow component — it is the
   sum of *everything* that lifts HR at fixed power: thermoregulatory/plasma-volume cardiac
   drift, dehydration, caffeine, altitude, glycogen state, emotional load. Labeling this
   catch-all residual as "the slow component / efficiency loss" is a physiological
   over-attribution. The literature review is careful to call HR drift a *proxy* for the slow
   component (§3), but the state vector then names `F` as if it *is* the slow component.
2. **The DALE analogy is loose, not a derivation.** DALE's efficiency drift is a **VO₂**
   phenomenon (~88 mL·min⁻² in the severe domain), gated at RCP/critical power. The app's `F`
   is an **HR-drift phenomenon in bpm**. Equating "`F` charges above CP at rate κ, recovers
   with τ_rec" to DALE's Ȧ is an *analogy*; the gate (CP), the recovery constant (τ_rec = 900 s,
   which is unsourced), and κ (tuned to hit a target bpm) are all free parameters. That is
   acceptable engineering, but the §9 provenance table lists "DALE τ_st/τ_ft/Ȧ — **Validated**"
   immediately adjacent to the `F`-drift design in a way that lends DALE's validation to a
   state it does not actually earn.

**Recommendation:** rename `F` to something honest ("residual HR drift at fixed power" or
"unexplained cardiovascular drift state") and describe it as *inspired by* DALE's gating
structure rather than *implementing* it. Keep DALE's "Validated" flag attached only to the
VO₂ constants, not to `F`.

### 1.6 "Validate against the user's own labeled rides" — there is no on-bike ground truth to label with
The abstract and §10/§12 state that the fused estimators "must be calibrated against the
user's own labeled rides before their outputs are trusted." This is the right instinct, but
**there is no gold-standard fatigue signal available on the bike** — that absence is the
entire premise of the project. So what are the "labels"? The calibration ride (§10) can fit
the power→α1 sigmoid and the personal AeT/AnT and kJ anchor — i.e. it can tune the model to
**internal self-consistency and to threshold crossings** — but it **cannot validate the
latent `F`/AFI against any measured fatigue truth**, because none exists on-device.

**Recommendation:** soften the language from "validate/labeled" to "**calibrate to
self-consistency**," and state plainly that AFI/`F` are never validated against a fatigue
gold standard, only tuned so that their *threshold crossings* line up with the athlete's
measured AeT/AnT/durability. This is a meaningful distinction the current text blurs, and it
directly affects §5 of `scientific-validation-prompt.md` (which likewise implies calibration
"moves values toward measured values" — true for threshold powers, not for the fatigue state).

### 1.7 The app's most prominent output rests on its least-validated logic
The single-glance screen (white paper §8.1) leads with a **verdict banner** (KEEP GOING /
EASE SOON / TURN BACK) and, when red, a Feat-of-Strength vs Attrition label. The
Feat/Attrition classifier (§8.2) is explicitly `[synthesis — not a validated classifier]`,
and the productive-window verdict it gates is itself probabilistic and confound-prone (§1.4).
So the **most visually dominant, most behaviorally consequential** output is driven by the
**least validated** component. That is an inverted risk-communication profile: evidence
strength and UI prominence run in opposite directions.

**Recommendation:** this is a design/ethics point, not just wording. Either demote the
verdict's visual authority relative to the raw evidence row, or attach a persistent
"heuristic — not validated" treatment to the verdict banner itself (not only in a footer),
so the rider cannot mistake a synthesis-grade guess for a measured judgment.

---

## 2. Moderate concerns

### 2.1 High correlation / ICC with wide limits of agreement is oversold as "Validated"
The α1 = 0.75 ↔ VT₁ anchor is listed in §9 as **"Validated (r=0.99 VO₂, ICC 0.99)"** with the
±10 bpm individual LoA relegated to a trailing clause. For an app that estimates an
*individual's* aerobic-threshold HR, **±10 bpm is the number that matters**, and it is large
(it spans most of a rider's Z2). High group-level r/ICC does not imply individual-level
interchangeability (standard Bland-Altman caution). The headline overstates individual
usability.

**Recommendation:** report the anchor as "strong group-level correlation but ±10 bpm
individual limits of agreement — not adequate for individual threshold setting without
per-athlete calibration," and move the LoA into the headline rather than the footnote.

### 2.2 Absolute α1 fatigue bands are near-useless in exactly the state the app targets
The 2025 TTF paper's own caution — *not all athletes reached anticorrelated α1 (<0.5) even at
task failure; α1 threshold validity degrades once fatigued* — is acknowledged (white paper
§4.5 caveat), but its implication is stronger than the text admits: the **absolute** α1
fatigue band is least trustworthy precisely in the **fatigued regime the app most wants to
alarm on**. The docs still ship the absolute <0.5 band as "corroborating."

**Recommendation:** demote the absolute α1 band further — from "corroborating" to "display
only, do not gate verdicts" — and rely on the per-athlete "drift below baseline-for-power"
signal, as the docs already prefer elsewhere. Ensure the two prompts reflect this
consistently.

### 2.3 Barsumyan is correlational and modest; the docs slightly over-read it
Verified: Barsumyan 2026 is an **association** study (repeated-measures r = 0.40 / 0.38 —
~15–16% of variance) at 75% FTP, with **mean decoupling ≈ 2.0 ± 2.4%** and **mean drift ≈
2.1 ± 2.3%** (SD ≈ mean, i.e. some riders coupled *negatively*). The paper hypothesizes
cadence decline is a *compensatory* response; it does **not** establish that cadence *leads*
or *predicts* fatigue, nor a usable threshold (the authors explicitly defer that). The review
(§3) calls cadence a signal that "lags neuromuscular fatigue" and "a useful second vote" —
mild over-reading of lead/lag and of signal quality. It also usefully illustrates how **noisy
sub-threshold decoupling is** (2% mean with huge scatter), which is relevant to the app's
reliance on a >8% decoupling gate.

**Recommendation:** describe cadence decline as an *associated, low-variance-explained,
direction-ambiguous* correlate, not a fatigue predictor, and cite the ~2% mean / high-SD
decoupling at 75% FTP as evidence that sub-threshold decoupling is a low-SNR channel.

### 2.4 Reliance on preprints and a paywalled state-space core
The Layer-2 filter architecture leans on two **non-peer-reviewed arXiv preprints**
("From Lab to Wrist" 2505.00101; "PM-EKF" 2604.26803), and `references.md` notes PM-EKF's
process/measurement **covariances and Jacobians are supplementary-only and unverified**.
Building an estimator's architecture on a preprint whose key matrices could not be read is a
stated but under-weighted risk.

**Recommendation:** flag preprint status explicitly wherever these are cited as design
authority (white paper §4, §6 of `references.md`), and treat the borrowed architecture as a
starting point requiring independent tuning/validation, not an established pattern.

### 2.5 The validation harness partly checks the model against itself
`scientific-validation-prompt.md` is a strong idea, but note a circularity: many of its
"consensus-plausibility" checks (α1 decreases with intensity; `F` stays ≈0 below CP; α1
drifts down over a long effort) are checking that **the model reproduces the equations it was
built from**, not that the model matches reality. Passing them demonstrates *internal
consistency*, not *external validity*. The prompt is honest about tiers (hard invariant /
plausibility / calibration), but should state that the plausibility tier is
**consistency-with-the-spec**, not **agreement-with-measurement**.

**Recommendation:** add a sentence to §2/§6 of the validation prompt clarifying that
direction/monotonicity checks validate the *implementation against the documented model*, and
that only real-file ingestion against measured VT/decoupling constitutes external validation
(which is inherently limited by §1.6's no-ground-truth problem).

---

## 3. Minor / editorial

- **3.1 Internal citation inconsistency.** Literature review §3 attributes the drift/decoupling
  equations to *"Barsumyan et al. 2026; frai.2025.1623384."* The `frai.2025.1623384` ID is the
  separate *Frontiers in AI* ML paper, not Barsumyan (BMC). Two different papers are conflated
  at that anchor. Separate them.
- **3.2 Missing `traceability.md`.** Both prompts (`scientific-validation-prompt.md` §4;
  `connectiq-app-generation-prompt.md`) treat `docs/traceability.md` as a source of truth /
  deliverable, but the file does not yet exist in the repo. The validation harness's
  traceability check would fail on a missing file. Either create the stub or mark it clearly as
  "to be generated."
- **3.3 Rogers 2025 ICC range.** `references.md` states DFA-α1 ICC "0.73–0.96"; the verified
  abstract gives the overall ICC band as 0.73–0.94. Minor, but reconcile the upper bound.
- **3.4 Banister female TRIMP coefficient** (0.86 vs 0.64) is flagged unresolved (§7.1). Resolve
  against Banister 1991 primary before shipping, or expose as a setting; a wrong exponent
  materially distorts female TRIMP/TSS-equivalents.
- **3.5 Normalized Power at short-window granularity.** Rolling EF = rolling-NP / rolling-HR over
  5–10 min windows (white paper §3.1) is a reasonable engineering adaptation, but NP was defined
  and validated over whole intervals/rides; it behaves erratically on short windows with
  coasting. Note the adaptation as unvalidated-at-that-granularity.
- **3.6 DALE Eq. 3 `min{0,…}` typo** is well handled (flagged to confirm against the published
  version) — good practice, keep it.

---

## 4. What the documents get right (credit where due)

- **Provenance discipline.** Every numeric threshold carries a status flag, and the §9 table is
  an exemplary artifact. Most projects in this space present coaching conventions as if they
  were validated cutoffs; this one does not.
- **Honest gap statements.** The "no validated marker exists for the productive-to-damaging
  transition," the "damage in cycling ≈ glycogen depletion, not muscle injury," and the
  "fused states are not directly validated" admissions are scientifically correct and rare.
- **Calibration gating.** Refusing to trust the personal power→α1 sigmoid unless R² > 0.75, and
  labeling everything "uncalibrated — estimate only" until calibration runs, is the right
  posture.
- **Correct, non-trivial physiology.** The DALE-vs-classical identifiability discussion, the
  τ₂-non-identifiability point, the intensity-gated (not volume-gated) durability finding, the
  cycling-concentric/low-EIMD distinction, and the ACWR critique (Lolli/Impellizzeri) are all
  accurate and show real command of the literature.
- **The reference base is genuine.** Every citation I could check resolved and matched — a
  meaningful result given the assembly method.

---

## 5. Priority-ordered recommendations

1. **(1.3)** Elevate the lab→field external-validity gap to a first-order limitation and add a
   power/HR **stationarity gate** on α1, not just an artifact gate.
2. **(1.4)** Stop calling the productive-window signals "independent"; model or acknowledge the
   shared cadence/respiratory/heat confounds; extend heat suppression to α1.
3. **(1.5 / 1.6)** Rename `F` honestly, attach DALE's "Validated" flag only to VO₂ constants, and
   change "validate against labeled rides" to "calibrate to self-consistency; no fatigue ground
   truth exists on-device."
4. **(1.1)** Re-label the "adversarial/vote" flags as extraction confidence and add a separate
   evidence-strength axis (sample size, independent replication).
5. **(1.2 / 2.1)** Add sample-size and independent-replication columns to §9; move the α1 ±10 bpm
   LoA into the headline.
6. **(1.7)** Reconcile UI prominence with evidence strength — the verdict banner needs a
   persistent heuristic treatment.
7. **(3.x)** Fix the Barsumyan/Frontiers-AI citation conflation, create or flag
   `traceability.md`, reconcile the ICC bound, resolve the Banister female coefficient.

---

## 6. Summary severity table

| # | Issue | Severity | Type |
|---|---|---|---|
| 1.1 | "Vote" flags conflate extraction confidence with evidence strength | Major | Framing |
| 1.2 | DFA-α1 core = single author cluster, single-digit N | Major | Evidence base |
| 1.3 | Lab steady-state validation ≠ free-living variable-power cycling | Major | External validity |
| 1.4 | Productive-window "independent signals" are not independent (shared confounds) | Major | Model logic |
| 1.5 | `F` weakly observable; "slow component" label is over-attribution | Major | Model / interpretation |
| 1.6 | No on-bike ground truth → cannot "validate," only self-calibrate | Major | Validation claim |
| 1.7 | Most prominent output = least validated logic | Major | Risk communication |
| 2.1 | High r/ICC with ±10 bpm LoA sold as "Validated" | Moderate | Statistics |
| 2.2 | Absolute α1 bands weakest in the fatigued regime the app targets | Moderate | Threshold validity |
| 2.3 | Barsumyan over-read (correlational, low variance explained) | Moderate | Over-interpretation |
| 2.4 | Filter architecture built on preprints / unverified matrices | Moderate | Source quality |
| 2.5 | Validation harness partly checks the model against itself | Moderate | Circularity |
| 3.1–3.6 | Citation conflation, missing file, ICC bound, TRIMP coeff, NP granularity | Minor | Editorial |

*Verification note: PubMed metadata retrieved 2026-07-12 for PMIDs 41923151, 39904800,
40402269, 29966866, 31427992. DOI links included above per source-attribution requirements.
Independent reproduction of paywalled per-subject tables and figure-read values was not
performed and is out of scope for this review.*
