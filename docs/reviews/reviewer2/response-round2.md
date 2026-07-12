# Response to Reviewer 2 — Round 2

**Re:** Second-Round Review (Revision 2)
**From:** FatigueMeter authors
**Date:** 2026-07-12
**Result:** the new issue and all four consistency seams addressed; documents advanced to **Revision 3**. No third architecture rethink — a targeted pass on §§4.2–4.5, §6, §8.1 plus two harness checks, as you predicted.

Thank you for verifying the dispositions against the text rather than the changelog, and for the sharpest new finding this round: that the α1↔F coupling, while fixing observability, **pipes α1's confounds straight into the fatigue state** — and that the fB mitigation was computed but never wired to the filter. That was a real gap between two sections that never met.

## The new issue

**1.1 — Coupling α1 into `F` imports α1's respiratory/artifact confounds; fB mitigation not wired to the filter.** **Accepted and fixed as you specified.** The α1 measurement noise `R_A1` is now **inflated when fB changes rapidly or RR artifact is elevated** (§4.4), so respiration-/artifact-driven α1 excursions contribute little to `F` — the fB signal is now *in the filter*, not just a display flag. §4.3a states plainly that `F` absorbs the **α1 channel's** confounds, not only HR's. And the validation prompt adds your exact check: **inject a respiration-only α1 excursion at constant power and constant true fatigue, and assert `F`/AFI does not materially rise.** Without it, the fusion could manufacture fatigue from breathing; now it is guarded.

## Internal-consistency seams

| # | Seam | Disposition |
|---|---|---|
| 2.1 | Absolute threshold retired from α1 but survives in `AFI > 85` (an `F_ref`-dependent absolute cutoff) | **Accepted** — the severe band now **also fires on per-athlete AFI drift above its own rolling baseline-for-power** (parallel to the α1 treatment), the fixed `AFI > 85` is labelled a **convention-grade, `F_ref`-dependent** default, and a **§9 row for the AFI band cutoffs** was added (previously missing). |
| 2.2 | "No imperative" principle vs the amber "EASE SOON" | **Accepted** — amber reworded to **"FATIGUE BUILDING"** (descriptive); the harness now checks **imperative mood via an allowed-copy list**, not a two-string blacklist, so this class of violation is actually caught. |
| 2.3 | α1 personalized but decoupling still absolute >8% | **Accepted** — the advisory's decoupling trigger is moved to **drift above the athlete's own early-ride baseline** (the fixed 8% is only a no-baseline fallback), so the two correlated channels get consistent treatment. |
| 2.4 | Recalibrated charge (P_AeT onset + `κ_d`) vs unchanged `F_ref` may saturate AFI on long Z2 | **Accepted** — §4.4 notes the two must be **tuned together**, and the harness adds a plausibility check that a **3–4 h steady Z2 ride yields a moderate AFI, not severe** (protecting the Feat/Attrition distinction). |
| 2.5 | §4.5 "cross-checked against decoupling" implies corroboration §4.3a denies | **Accepted** — reworded: decoupling is a **graceful-degradation fallback, not an independent check** ("on steady rides these are near-identical"). |

## Minor

- **`c_F` exchange rate may contradict the cited data** — **Accepted**: §4.4 and the §9 row now note the 0.2 anchor may be **~2× low vs Rogers 2025's ~0.45 α1 fall at failure**, flag it as needing a stated rationale, and route it to the pilot's sensitivity analysis; the traceability `C_F` row is annotated (not merely "tuned").
- **Observability test = structural, not correctness** — **Accepted**: relabelled and the report spec states it proves recoverability-under-the-assumed-model.
- **Sex collected but unused beyond TRIMP** — **Accepted**: §11 now states plainly that **collecting `sex` does not mean the bands are sex-adjusted** (only the TRIMP coefficient consumes it) so users don't infer personalization that isn't there.
- **ACWR (standing disagreement)** — you accepted the opt-in/off-by-default compromise with a residual caution; we keep it, and we've noted your caution that a single "danger >1.5"-heritage ratio reads as predictive regardless of the disclaimer. If we see field misuse, we revisit deletion.
- **TRIMP female coefficient** — remains flagged a **defect to resolve before code** (white paper §9, `traceability.md` `UNRESOLVED`, generation prompt). We agree the flag culture must not become a way to ship the ambiguity; it will be resolved against Banister 1991 or exposed as a setting before implementation.

## Bottom line
Your framing holds: fix 1.1 (done — the fB de-weighting is now in the filter and harness-guarded) and reconcile the four seams (done), and this is an honest, shippable spec for a durability/decoupling advisory — with the criterion-validity pilot still the one thing between "advisory" and "instrument." On that last point, we have now made the pilot a **release gate for the numeric output** rather than an open debt (§8.1 decision), which we think closes the remaining gap between the honest prose and the presented number.
