# Response to Reviewer 1 — Round 2

**Re:** Round 2 Review (Revision 2 of the white paper and prompts)
**From:** FatigueMeter authors
**Date:** 2026-07-12
**Result:** all Round 2 points accepted; documents advanced to **Revision 3**.

Thank you — and in particular for **catching a defect I introduced**, the EKF claim. You were right that Rev 1 had the linearity call correct and Rev 2 regressed on it. That is exactly the kind of error a verification-minded read exists to catch. Every Round 2 point is now fixed.

## Major

| # | Concern | Disposition | Change |
|---|---|---|---|
| R2-1 | "Nonlinear → EKF" is wrong; model is linear in the state | **Accepted — reverted** | §4.4 now states this is a **linear (time-varying) KF**; nonlinearities are functions of the measured input `P` and enter as known input terms; an EKF is needed only if a sigmoid param/`P_AeT` becomes an estimated state. Fixed identically in the generation prompt (Layer 2, "not an EKF, do not implement Jacobians") and the validation prompt (filter-type invariant). |
| R2-2 | Correlated measurement noise → diagonal-`R` overconfidence | **Accepted** | §4.4 now states the HR and α1 innovations **share drivers**, so diagonal-`R` is optimistic and AFI's implied precision is a **lower bound**; inflate `R` (or non-diagonal `R`). §4.3a extended to the correlated-noise point. |
| R2-3 | `c_F` is an unvalidatable cross-signal calibration constant | **Accepted** | `c_F` added to the §9 "synthesis / hand-set — no ground truth" set with its own row noting it is a bpm⇔α1 exchange rate inheriting `F_ref`/sigmoid weakness; the criterion-validity study now includes a **`c_F` sensitivity analysis** (§10). |
| R2-4 | Heat is signal for `F` but noise for the advisory — on-screen incoherence | **Accepted — resolved, not just disclosed** | Made consistent: because `F` is *cardiovascular* drift it **legitimately includes thermal drift**, so a hot-day AFI rise is correct; the §6 advisory now **names heat as a co-driver of the drift rather than discounting it**. The dial and advisory no longer disagree on hot days. |
| R2-5 | `f()` seeding unspecified/uncited; "fatigue added" is soft-minus-soft | **Accepted** | §7 now gives an explicit default `f()` and flags it synthesis-grade (§9 row); **start-of-ride fatigue and "fatigue added" are presented as coarse buckets / ranges**, not point values. |
| R2-6 | Projected end-of-ride tick = forecast on hand-set constants, shown as a measurement | **Accepted** | The projected tick is **gated on the pilot** and, when shown, rendered as a **shaded "projection" range**, never a hard tick equal to "now" (§8.1); §9/traceability rows added. |

## Moderate

| # | Concern | Disposition |
|---|---|---|
| R2-7 | Simulated observability proves math observability, not physiological identifiability | **Accepted** — relabelled a **mathematical observability/conditioning check** in §4.3a and the validation prompt, with an explicit "proves recoverability under the assumed model only; separating `F` from unmodeled drift needs the external pilot" note. |
| R2-8 | AFI/decoupling blend underspecified → 0–100 scale drifts with RR quality | **Accepted** — §4.5 now specifies the blend (RR-quality weight `w_rr`, both sources scaled to a common `F_ref`-equivalent reference, continuous hand-over, and a display marker when the dominant source switches). |
| R2-9 | `κ_d` accumulates `F` on recovery/coasting; stop-behavior unspecified | **Accepted** — `κ_d` now charges **only while active** (pedaling / HR > rest) so `F` relaxes on recovery/coasting/stops; the harness asserts a recovery segment does not raise AFI. |

## Minor / prompt-specific

- **R2-10** stale "productive-window signal" wording — **Fixed** (swept to "durability advisory" across prompt and body; the leftover "verdict" UI/design vocabulary was also swept).
- **R2-11** α1 hard-bound [0.2, 1.6] false-fails resting α1 — **Fixed**: the upper bound is now a **soft/wide** check; only the lower bound (>~0.2) is hard.
- **R2-12** validation prompt assumed EKF — **Fixed**: aligned to linear KF.
- **R2-13** NP hard-check vs granularity caveat — **Fixed**: the harness report now states the NP identity is checked for **coding correctness only**, not validity at short-window granularity.
- **R2-14** traceability check only as strong as the stub — **Fixed**: the prompt now requires the report to state the fraction of code constants actually present and treat missing rows as gaps.

## Note
The one place I went beyond the fixes: your R2-4 and R2-2, taken together, pushed me to make the **heat/`F` relationship coherent by construction** (F owns thermal drift; the advisory attributes rather than discounts) rather than patching the symptom — I think that is the more honest resolution, and it removes the two-readouts-disagree bug you identified rather than merely labelling it.
