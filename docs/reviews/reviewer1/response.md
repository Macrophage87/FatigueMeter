# Response to Reviewer 1

**Re:** Scientific-Validity Review of the FatigueMeter Documentation
**From:** FatigueMeter authors
**Date:** 2026-07-12
**Revision produced:** white paper, literature review, references, and both prompts updated to **Revision 2**; a `docs/traceability.md` stub added.

Thank you — this review materially improved the documents. We independently verifying our own citations before critiquing our inferences is exactly the right order of attack, and your central framing (the problems are not fake citations but *how strong the evidence is, how far it generalizes, and how we graded our own confidence*) is the through-line we adopted for the whole revision. **We accepted every point.** Where we chose one of your suggested options over another, or went further, we say so below.

## Disposition of major concerns

| # | Your concern | Disposition | What changed |
|---|---|---|---|
| 1.1 | "Vote" flags conflate extraction confidence with evidence strength | **Accepted** | Lit-review "How to read the citations" now states the flags measure **extraction confidence only**, explicitly orthogonal to evidence strength; the "N–M vote" notation is **retired** from physiological claims and relabelled "extraction agreement." White-paper §9 is now a **two-axis table** (Extraction | Evidence strength). |
| 1.2 | DFA-α1 core = single author cluster, single-digit N | **Accepted** | New **aggregate caveat** at the top of lit-review §4-context ("dominated by one overlapping author cluster… methodological consistency, not independent replication"). White-paper §9 carries an **N/replication/generalizability** column; §11 opens with **"Aggregate fragility"** naming every n. |
| 1.3 | Lab steady-state ≠ free-living variable-power cycling | **Accepted — elevated to first-order** | White-paper §3.3 adds a mandatory **stationarity gate** on α1 (suppress when within-window power CV/coasting exceeds a threshold), and §11 lists the **external-validity gap** as a first-order limitation ("validate on the athlete's own outdoor rides before trusting within-ride drift"). The generation prompt now requires the gate; the validation prompt tests it. |
| 1.4 | "Independent signals" are not independent | **Accepted (your option b, plus part of a)** | §6 **drops "independent,"** reframes as "corroboration among **correlated** signals," extends **thermal suppression to α1** (not just decoupling), **names the shared confounds in-UI**, and moves the α1 gate to the **per-athlete drift** signal (reducing the cadence/absolute-value artifacts you flagged). We kept the kJ+decoupling+α1 set rather than fully rebuilding from orthogonal signals, but describe its evidential weight honestly. |
| 1.5 | `F` weakly observable; "slow component" label is over-attribution | **Accepted** | `F` is **renamed** "residual cardiovascular-drift state" and explicitly de-attributed from the VO₂ slow component (§4.1). New **§4.3a observability caveat** states `F` is weakly observable at constant power and AFI is "a smoothed decoupling proxy with a physiological prior" there. DALE's "Validated" flag now attaches **only to the VO₂ constants** (§9). |
| 1.6 | No on-bike ground truth → cannot "validate," only self-calibrate | **Accepted** | §10 rewritten: "validate against labeled rides" → **"calibrate to self-consistency,"** with an explicit statement that calibration tunes **threshold crossings**, not the latent fatigue magnitude. A **criterion-validity pilot** (regress AFI/`F` vs power-decrement/lactate/RPE, Bland–Altman per athlete) is added as *owed and not yet done*. The validation prompt §5 no longer implies calibration moves `F` "toward measured values." |
| 1.7 | Most prominent output = least-validated logic | **Accepted (both wording and design)** | §8.1 status band is now **descriptive** (no "TURN BACK"), carries a **persistent "advisory · not a validated measurement" tag on the banner itself**, and the **evidence row is given ≥ equal visual weight**. The Feat/Attrition classifier is taken **off the verdict critical path** (§8.2) — shown as context, never a gate. |

## Disposition of moderate concerns

| # | Your concern | Disposition |
|---|---|---|
| 2.1 | High r/ICC with ±10 bpm LoA sold as "Validated" | **Accepted** — §9 headline for α1=0.75 is now "**group-level agreement good, but ±10 bpm individual LoA — not adequate for individual threshold setting without per-athlete calibration**." |
| 2.2 | Absolute α1 band weakest in the fatigued regime it targets | **Accepted** — the absolute <0.5 band is **demoted to display-only** and gates nothing; verdict gating uses the per-athlete drift-below-baseline signal only (§4.5). |
| 2.3 | Barsumyan over-read | **Accepted** — lit-review §3 and §9 now describe it as *correlational, ~15–16% variance explained, direction-ambiguous, no threshold established*, and cite its ~2%-mean/high-SD decoupling as evidence that **sub-threshold decoupling is a low-SNR channel**. |
| 2.4 | Preprint-based, unverified-matrix state-space core | **Accepted** — references.md flags both arXiv items **⚠ non-peer-reviewed preprint**; §4 and §11 state the architecture is a starting point requiring independent tuning, and that PM-EKF's HR contributed no significant accuracy in its own setup. |
| 2.5 | Harness partly checks the model against itself | **Accepted** — the harness is renamed a **model-consistency** harness; its header now states **self-consistency ≠ external validity**, and the plausibility tier is labelled *implementation-against-spec, not agreement-with-measurement*. |

## Disposition of minor / editorial

- **3.1 Citation conflation** (Barsumyan vs `frai.2025.1623384`) — **Fixed**; the two are now kept distinct in lit-review §3.
- **3.2 Missing `traceability.md`** — **Fixed**; a seeded stub now exists so the harness's traceability check has a real file; the generation prompt still requires the app-builder to complete it.
- **3.3 Rogers ICC 0.73–0.96 vs 0.73–0.94** — **Fixed** to the abstract's **0.73–0.94 / r 0.83–0.98** in both lit review and references, with a note that the earlier ceiling was a mis-transcription in the tightening direction.
- **3.4 Banister female coefficient** — **Accepted and escalated**: references.md now calls the 0.86-vs-0.64 ambiguity a **defect**; the generation prompt requires resolving it against Banister 1991 or exposing it as a setting before shipping.
- **3.5 NP at short-window granularity** — **Accepted**: §3.1 flags rolling NP/EF as **unvalidated at that granularity** and adds a **steadiness gate**.
- **3.6 DALE Eq. 3 `min{0,…}` typo** — retained the existing flag as you recommended.

## On what we did *not* change

Your critique did not ask us to abandon the project, and we did not — but we adopted your implied reframing throughout: FatigueMeter is now presented as a **calibrated durability/decoupling dashboard with an advisory**, whose *validated backbone* is the observable primitives and whose *fused AFI/advisory* is honestly synthesis-grade and awaiting criterion validation. The one thing we could not do in this revision is *perform* the criterion-validity pilot; we have instead made its absence visible in the docs and wired a skipped test stub into the harness so it cannot be quietly forgotten.

We would welcome a re-read of Revision 2, particularly §4.3a (observability) and §10 (calibration vs validation), which are the two places your review most changed our thinking.
