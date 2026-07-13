# Implementation Notes — engineering choices & exposed-as-setting values

This file lists (1) every place the implementation made an engineering choice not
fully specified by the white paper, and (2) every value exposed as a **setting**
because the science flagged it as *convention* or *synthesis* (white-paper §9).
It is a required deliverable of `docs/prompts/connectiq-app-generation-prompt.md`.

## A. Architecture / module map

| Module (source/) | White-paper layer / role |
|---|---|
| `PrimitivesCalculator.mc` | Layer 1 — NP, EF/decoupling (steadiness-gated), kJ-weighted, DFA-α1 (via `DfaAlpha1`), cadence drift, W′bal |
| `DfaAlpha1.mc` | DFA-α1 pipeline + artifact % + fB estimate (pure) |
| `AcuteFatigueFilter.mc` + `KalmanMath.mc` | Layer 2 — 4-state **linear** Kalman filter with the α1↔F coupling and R_A1 inflation |
| `EffortCharacterizer.mc` | §8.2 Feat vs Attrition (off the critical path) |
| `TrainingLoadLedger.mc` | Layer 3 — TSS/TRIMP, CTL/ATL/TSB, ACWR (opt-in), RMSSD baseline, persistent |
| `FitLogger.mc` | §8.3 FitContributor record + session developer fields |
| `SessionStore.mc` | §8.3 persistent Session Results + rolling history |
| `StatusEvaluator.mc` / `DescriptiveStrings.mc` | §4.5/§6/§8.1 descriptive band logic + allowed-copy list |
| `CalibrationFit.mc` | §10 personal power→α1 fit with the R²>0.75 gate |
| `FatigueMeterView.mc` / `FatigueMeterApp.mc` | §8.1 single glance screen + 1 Hz compute loop + finalize |
| `Config.mc` / `Constants.mc` / `Metric.mc` / `MathUtil.mc` / `RingBuffer.mc` | settings, provenance-tagged constants, fault-isolation envelope, math |

## B. Engineering choices NOT fully specified by the white paper

1. **4-state filter with `HR_ss` as a deterministic input row.** §4.1 lists
   `x = [HR_ss, HR, A1, F]`, but §4.2 defines `HR_ss = HR_rest + g_P·P`
   algebraically from the measured input. We keep the 4-state vector but make the
   `HR_ss` transition row depend on the input only (`A[HR_ss][*]=0`, input term
   `HR_rest+g_P·P`), which is the faithful **linear-KF** reading (all
   nonlinearities are functions of the measured `P` and enter as `u(k)`). No
   Jacobians. `KalmanMath.predict/scalarUpdate` are the exact linear operations.

2. **Scalar (per-channel) measurement updates.** HR and α1 are updated as two
   independent scalar updates rather than a stacked 2-vector update. This makes
   **missing-observation handling native** (skip the absent channel → predict-only
   or HR-only) and avoids a 2×2 inverse. Equivalent to the joint update under a
   diagonal `R`; with the deliberate `R` inflation it is conservative.

3. **`R_A1` inflation law (fB/artifact).** The white paper mandates inflating
   `R_A1` on rapid-fB / high-artifact windows but does not give a formula. We use
   `R_A1_eff = R_A1 · (1 + 4·min(artifact/gate,2)) · (1 + 6·min(|ΔfB|/0.1,3)) · 1.5`.
   The trailing ×1.5 is a **lower-bound floor** for the shared-driver correlated-
   noise overconfidence (§4.4). All coefficients are hand-set engineering values.

4. **κ_i / κ_d recomputed for the τ_rec-drained dynamics.** Because
   `dF/dt = charge − F/τ_rec`, steady state is `F_ss = charge·τ_rec`. We solved the
   white-paper targets ("30 min at P_AeT+80 W ⇒ ~9 bpm"; "~2–3 bpm over 2 h at Z2")
   through that relation: `κ_i ≈ 1.45e-4`, `κ_d ≈ 2.8e-3`. Both are settings;
   both are synthesis-grade and must be calibrated (white-paper §10).

5. **Decoupling common-scale reference `DECOUP_REF = 8%`.** §4.5 requires
   `AFI_decoup` scaled so it ≈ `AFI_kalman` at `F_ref`, but leaves the constant to
   the implementer. We map ~8% decoupling → full scale (100), consistent with the
   Friel "above-threshold" band. Exposed via `Constants.DECOUP_REF`.

6. **Per-athlete α1 drift-below-baseline** is computed as
   `A1_target(P) − α1_measured` (expected-for-power minus measured), using the
   population (or, once calibrated, personal) sigmoid as the per-power baseline.
   The white paper specifies "drift below the athlete's own baseline-for-power"
   without an on-device baseline-tracking scheme; this is a faithful, cheap proxy.

7. **Calibration fit is a linearised sigmoid fit.** `CalibrationFit.fitSigmoid`
   fits α1 = m·P + b across the transition, takes the fit **R²** for the >0.75
   gate, locates the personal AeT as the 0.75 crossing, and maps the linear slope
   onto the sigmoid slope `s ≈ −4·m/a1`. A full nonlinear least-squares sigmoid fit
   was judged unnecessary on-device for locating the crossing + gating.

8. **Ride "end" hook.** A data field has no explicit "activity saved" callback, so
   the Session Result fold + FitContributor session fields are written from
   `App.onStop()` (the reliable app-teardown hook), guarded to run **once**.

9. **RR acquisition.** Beat-to-beat RR is read via
   `Sensor.registerSensorDataListener({:heartBeatIntervals=>{:enabled=>true}})`
   and buffered for the next `compute()`. The SensorData member name is accessed
   defensively (`heartBeatIntervals` or `heartBeatIntervalData`) across SDK
   revisions. If the listener is unavailable the app runs decoupling-only.

10. **Cross-ride comparison** data (§8.3) is persisted in `SessionStore` (last 20
    Session Results) and the footer/strip surface start-fatigue + TSB context;
    a dedicated multi-ride comparison **screen** is left to a companion widget /
    Garmin Connect (a data field cannot host a separate browsing screen). The
    stored records carry every field §8.3 lists.

11. **DFA artifact detector.** A local-median deviation detector (simplified
    Lipponen–Tarvainen; ±3-beat window, 25% tolerance) produces the artifact %
    that drives the hard gate. The exact ectopic-correction algorithm is not
    specified by the white paper; this is a standard, cheap proxy.

12. **`κ_d` "active" definition.** The white paper says κ_d charges "while active
    (pedaling / HR above rest)" but its stated *goal* is that `F` **relaxes on
    recovery/coasting/stops**. An HR-based trigger would keep charging during a
    coast with still-elevated HR, defeating that goal, so we define active as
    **doing work** — `cadence>0` **or** `power > 5%·FTP`. Easy Z1 pedaling still
    charges κ_d (thermal drift), while a true coast/stop switches it off and `F`
    decays via τ_rec. This resolves the spec's internal tension toward the stated
    goal (harness "recovery relaxes F" check).

13. **Per-athlete AFI drift baseline (§4.5).** The band must *also* fire on "AFI
    drifting above its own rolling baseline-for-power" so the absolute
    `afiBuilding` cutoff is not the sole gate. Full power-conditioning is heavy
    on-device, so the baseline is a **slow EWMA of AFI updated only on steady
    (prior-dominated) segments** (surges don't pollute it), established after a
    warmup; `afiDriftAboveBaseline()` feeds a `STATUS_DRIFTING` trigger parallel
    to the α1 drift signal. Margin is the `afiDriftMargin` setting.

14. **Observability/conditioning check (§4.3a).** `KalmanMath.observabilityCheck`
    builds the discrete observability matrix `O = [H; HA; HA²; HA³]` (both
    measurement rows), forms the Gramian `OᵀO`, and returns `det(OᵀO)` (>0 ⇔
    non-degenerate) and the F-diagonal energy. Run once at filter init with the
    live gains. This proves **numerical recoverability under the assumed model
    only** — not physiological identifiability (that needs the pilot, §10), and
    the code/report say so.

15. **End-of-ride & fatigue-added are bucketed (§7).** `fatigueBucket` /
    `deltaBucket` coarsen the end-of-ride drift and the added delta into
    fresh/moderate/heavy and small/moderate/large, stored in the Session Result
    with the AFI uncertainty band. The raw bpm still go to the FIT session field
    for export, but the in-app/cross-ride presentation is bucketed, matching the
    start-of-ride treatment.

16. **`g_P` corrected from 0.15 → 0.45 (found by the validation harness).** The
    white paper gives `g_P ≈ (HR_max−HR_rest)/P_max ≈ 0.15 bpm/W`, but 0.15
    implies `P_max ≈ 930 W` (a sprint peak). With it, `HR_ss = HR_rest + g_P·P`
    underestimates fresh HR by ~50 bpm at endurance power, so `F` absorbs the
    static-gain error and **AFI saturates to ~100 on every ride** — violating the
    white paper's own §4.4 requirement that a long steady Z2 ride yields a
    *moderate*, not severe, AFI (the model-consistency harness's `P9` check caught
    this). The correct denominator is the **power at HR_max** (~threshold):
    `(190−50)/~310 ≈ 0.45`. `g_P` is synthesis/hand-set (§9) and a live setting, so
    this is a defaults correction, not a new physiological claim; calibration fits
    it per athlete.

17. **`A1_target` sigmoid retuned to cross 0.75 at P_AeT (harness-found).** The
    white paper's `a0/a1 = 1.1/0.6` give a sigmoid midpoint of `a0 − a1/2 = 0.80`,
    not the 0.75 AeT anchor it claims to pass through — so the population prior and
    the calibrated 0.75 crossing disagreed by ~0.05. Set `a0=1.0, a1=0.5` →
    midpoint 0.75 at P_AeT, asymptotes 1.0 (rest) / 0.5 (the AnT anchor). Synthesis
    shape params + settings (§9); check `S1` guards it.

18. **RR staleness timer (§8.4, harness-found).** The RR buffer ages out only by
    summed RR-duration, not wall-clock, so when the strap drops, DFA kept emitting
    a **stale α1** off the frozen buffer instead of marking it unavailable. Added a
    `RR_STALE_S` (10 s) timer: once RR has been silent that long, α1 is marked
    unavailable so the filter drops the α1 update and the tile greys — matching
    §8.4's "hold last-valid then mark unavailable, reacquire cleanly." Mirrored in
    the harness engine; A7's marker/reacquire rows exercise it.

## C. Values exposed as SETTINGS because the science flags them convention/synthesis

All are in `resources/properties/properties.xml` (defaults) and
`resources/settings/settings.xml` (UI), read live via `Config.mc`. Changing the
setting changes behaviour (the honesty requirement — nothing convention/synthesis
is hard-coded as if validated).

| Setting | Default | §9 status |
|---|---|---|
| `afiFresh / afiBuilding` | 30 / 60 | convention, F_ref-dependent (§4.5) — now gate the band via `cfg`, not hard-coded |
| `afiDriftMargin` | 15 | per-athlete AFI drift trigger margin (§4.5) |
| `decoupRef` | 8 % | synthesis — AFI-decoupling common-scale ref (§4.5) |
| `seedA / seedB / seedTsbScale` | 0.6 / 0.4 / 30 | synthesis — start-of-ride seeding map (§7) |
| `featWSev / featMatchW / featBestW / attrDriftW` | 0.02 / 40 / 30 / 100 | synthesis — Feat/Attrition weights (§8.2, off critical path) |
| `gP / a0 / a1 / sigmoidS` | 0.15 / 1.1 / 0.6 / 0.02 | synthesis — now in the settings UI |
| `qHr / qHrLat / qA1 / qF / rHr / rA1` | see file | hand-set Q/R — now in the settings UI |
| `powerCvGate / coastFracGate` | 0.10 / 0.10 | steadiness/stationarity gate — now in the settings UI |
| `decoupOk / decoupCaution / decoupHigh` | 5 / 8 / 10 % | convention (Friel) |
| `artifactGate` | 5 % | pipeline convention |
| `powerCvGate / coastFracGate` | 0.10 / 0.10 | steadiness/stationarity gate (engineering) |
| `kjAnchor` | 2000 kJ | population-level, person-specific in practice |
| `tsbFresh / tsbOverreach` | +10 / −30 | Friel bands, not peer-reviewed |
| `trimpFemaleCoeff` | **0.86** | **UNRESOLVED** 0.86 vs 0.64 — see §D |
| `acwrEnabled` | **false** | contested (Lolli/Impellizzeri) — opt-in only |
| `tauHr / tauA / tauRec` | 30 / 90 / 900 s | synthesis; τ_rec unsourced |
| `kappaI / kappaD` | 1.45e-4 / 2.8e-3 | synthesis; hand-set |
| `cF` | 0.0167 | synthesis; unvalidatable cross-signal gain |
| `fRef` | 12 bpm | synthesis; **AFI linear in 1/F_ref** — sets the whole scale |
| `a0 / a1 / sigmoidS` | 1.1 / 0.6 / 0.02 | population map, **not universal** |
| `gP` | 0.15 bpm/W | static gain estimate |
| `qHr / qHrLat / qA1 / qF / rHr / rA1` | see file | hand-set; no on-bike ground truth |
| `positivePilot` | false | **release gate** for the numeric AFI (§8.1) |
| `shipNumberOverride` | false | explicit pre-pilot numeric-AFI exception (§8.1) |

## D. The one unresolved constant (flagged, not invented)

**Banister female TRIMP coefficient (0.86 vs 0.64).** `references.md` records a
~34% ambiguity across secondary sources and marks it a **defect** to be resolved
against Banister 1991 or exposed as a setting. Per the generation prompt's
instruction ("do not ship an ambiguous hard-coded constant"), we **exposed it as
a setting** (`trimpFemaleCoeff`, default **0.86** with exponent 1.67 for the
female form `0.86·e^(1.67x)`, vs the male `0.64·e^(1.92x)`). The male form is the
unambiguous one. This is the only value the white paper did not pin down; we did
not invent a value — we surfaced the ambiguity to the user with the documented
default.

## E. Honesty / release-gate behaviour implemented

- Pre-pilot (default): the dial shows the **3-state green/amber/red categorical**
  + coarse start/now only — **no precise AFI digit, no point start/now/end, no
  projected tick** (gated on `positivePilot` OR `shipNumberOverride`; §8.1).
- The status band always carries the **"advisory · not a validated measurement"**
  tag (or **"uncalibrated — estimate only"** until a personal calibration is
  stored). Colour is always reinforced with text/icon.
- Status copy is **descriptive** (FRESH/PRODUCTIVE · FATIGUE BUILDING · DURABILITY
  MARKERS DRIFTING) — no imperative mood; all strings come from the allowed-copy
  list in `resources/strings/strings.xml`.
- Feat/Attrition **never gates** the band — it only labels the *kind* of red.
- Durability advisory names **heat as a co-driver** (not discounted) and, when the
  stationarity gate suppresses α1, says the advisory rests on decoupling + kJ
  alone and is weighted down.
- The word **"damage"** is never emitted as a certainty; the glycogen flip /
  absolute-α1 alarm are not presented as measurements.
