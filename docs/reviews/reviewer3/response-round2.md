# Response to Reviewer 3 — Round 2

**Re:** Second-Round Scientific-Validity Review (Revision 2)
**From:** FatigueMeter authors
**Date:** 2026-07-12
**Result:** all refinements accepted; **the policy decision you asked for is made and recorded**; documents advanced to **Revision 3**.

Thank you — this round's most valuable contribution is §6: telling us to **stop adding caveats to the fused numeric output and instead make a decision about it.** We agree, and we made it. Your point that the α1↔F coupling is "structurally right but buys little information" is also now stated in the spec more sharply than before.

## The decision (your §6)

**Made and recorded:** the precise **0–100 AFI digit, the point-value start/now/end, and the projected-end tick are GATED on a positive criterion-validity pilot.** Pre-pilot, the app ships the **validated backbone** (decoupling, kJ-vs-anchor, CTL/ATL/TSB, the population α1 anchor) plus a **coarse 3-state categorical** (green/amber/red — which also satisfies the required colour scheme) and the Feat/Attrition characterization. Shipping the number earlier is now an **explicit, recorded exception**, not a caveat folded into "advisory." This is written into white-paper §8.1, enforced by a validation-prompt release-gate check, and reflected in the generation prompt (default 3-state; numeric AFI behind a `positivePilot` flag).

## The two "structurally right but weaker in effect" fixes

- **2.1 — the coupling buys little information; on steady rides AFI is prior-dominated.** **Accepted** — §4.3a now states this more sharply than "smoothed decoupling": on constant power `F`/AFI is **a prior-dominated time-ramp set by hand-tuned `κ`, lightly corrected by two weak correlated channels**, so it substantially reflects the *tuning of `κ`*. The coupling makes the fusion *structurally* honest without making AFI *informationally* independent of its priors on the rides where it is most read.
- **2.2 — `c_F` is defined in terms of other synthesis constants.** **Accepted** — the §9 `c_F` row and the `traceability.md` `C_F` row now record that it **inherits the weakness of `F_ref` and the non-universal sigmoid**; the pilot includes a `c_F` sensitivity analysis.

## New issues in the Layer-2 equations

| # | Issue | Disposition |
|---|---|---|
| 3.1 | AFI blend under-specified — and it is now the headline number | **Accepted** — §4.5 specifies weights (`w_rr`), a common `F_ref`-equivalent reference, continuous hand-over, and a source-switch marker. |
| 3.2 | Projected end-of-ride tick least-supported, no caveat | **Accepted** — gated on the pilot; rendered as a shaded "projection" range; §9 + traceability rows added. |
| 3.3 | AeT-vs-CP anchor split undocumented | **Accepted** — §4.2 now states the split is **deliberate** (AeT for drift onset; CP for the severe-domain constructs), with a one-line rationale. |
| 3.4 | `κ_d` charges unconditionally | **Accepted** — `κ_d` charges **only while active**; the harness asserts recovery segments don't raise AFI. |

## The durability advisory (your §4)

**Accepted — this was a sharp observation.** §6 now states that because the stationarity gate (§3.3) **frequently suppresses α1 on variable outdoor rides**, the advisory routinely **collapses to decoupling + the kJ clock — effectively one drift channel past a time threshold**, not multi-marker agreement; the copy must say so and weight down accordingly. The generation prompt carries the same instruction.

## The two prompts (your §5)

- **5.1 — the pilot's statistics are mis-designed (Bland–Altman wrong for mismatched units; n=5 is not validation).** **Accepted** — §10 and the validation prompt now specify a **calibration/association analysis** (rank correlation + cross-validated calibration curve), reserve Bland–Altman for a later same-units stage, and label any n≈5 run **proof-of-concept/feasibility**, with a powered study as the release gate.
- **5.2 — terminology drift ("productive-window signal", "verdict").** **Accepted** — swept: the generation-prompt scope note now says "durability advisory," and the residual UI/design "verdict" vocabulary in the white paper was changed to "status/advisory/characterization."
- **5.3 — traceability: add `C_F` and `PROJECTED_AFI` rows.** **Accepted** — both added (plus a seeding-map row), with the `C_F` dependency note.

## Closing
Your one-line close — "make a decision about the number, or ship it as an explicit exception; drifting is not defensible" — is the single most useful sentence across both rounds. We stopped drifting: the numeric AFI is gated on the pilot, and the pre-pilot product is the validated backbone plus a 3-state categorical. What remains between "advisory" and "instrument" is now a single, scoped, correctly-designed study rather than a stack of caveats.
