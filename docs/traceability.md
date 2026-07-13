# Traceability Matrix

**Status:** completed for the initial FatigueMeter Connect IQ implementation.
This file maps every physiological constant / threshold used in the code back to
(a) its row in the white-paper §9 provenance table, (b) its `references.md`
source, and (c) its **evidence-strength** note. The
`scientific-validation-prompt.md` traceability check reads this file.

**Rule:** no physiological constant may appear in code without a row here. A
constant with no provenance is a defect. All defaults live in
`source/Constants.mc`; every convention/synthesis value is *also* a live setting
(`resources/properties/properties.xml` + `Config.mc`) so it is not hard-coded.

| Code symbol | File:anchor | Value / default | White-paper §9 row | Source (references.md) | Extraction | Evidence strength |
|---|---|---|---|---|---|---|
| `AET_ALPHA1` | Constants.mc `AET_ALPHA1` | 0.75 | DFA-α1 = 0.75 | Rogers/Olson/Gronwald 2020 | High | Group-level only; ±10 bpm individual LoA; n=15, male-dominated, lab — **fallback/display, not sole gate** |
| `ANT_ALPHA1` | Constants.mc `ANT_ALPHA1` | 0.5 | DFA-α1 = 0.5 | Rogers/Gronwald | High | Weak (HR r≈0.71) — **display only** |
| `ALPHA1_DRIFT_HIGH/SEVERE` | Constants.mc | 0.2 / 0.3 below baseline | per-athlete α1 drift | Synthesis (Rogers 2025 pattern) | n/a | Synthesis; absolute <0.5 cutoff **retired** (running-derived) |
| `DECOUP_OK/CAUTION/HIGH` | Constants.mc + `decoupOk/…` prop | 5 / 8 / 10 % | Decoupling bands | Friel/TrainingPeaks | High | Coaching convention; steady-effort validity only; low SNR sub-threshold |
| `DECOUP_REF` | Constants.mc `DECOUP_REF` | 8 % | AFI/decoupling blend §4.5 | Friel (derived) | n/a | Synthesis — common-scale ref so AFI_decoup≈AFI at F_ref |
| `KJ_ANCHOR_LOW/HIGH` + `kjAnchor` | Constants.mc / prop | 1500 / 2500; default 2000 | kJ anchors | Spragg / durability review | High | Population-level; person-specific in practice |
| `CTL_TAU / ATL_TAU` | Constants.mc | 42 / 7 d | CTL/ATL EWMA | TrainingPeaks | High | Standard/established |
| `TSB_FRESH / TSB_OVERREACH` | Constants.mc + props | +10 / −30 | Friel TSB bands | coaching convention | High | **Not peer-reviewed** — configurable |
| `acwrEnabled` (+ `acwr()`) | props / TrainingLoadLedger.mc | false (opt-in) | ACWR | Impellizzeri/Lolli | High | **Contested** — off by default, descriptive-only |
| `TAU_HR / TAU_A / TAU_REC` | Constants.mc + props | 30 / 90 / 900 s | Kalman seeds §4.4 | Synthesis | n/a | Synthesis; **τ_rec unsourced**; calibrate |
| `KAPPA_I / KAPPA_D` | Constants.mc + props | 1.45e-4 / 2.8e-3 | Kalman seeds §4.4 | Synthesis | n/a | Hand-set; re-derived for τ_rec-drained dynamics; `κ_d` active-gated |
| `C_F` | Constants.mc + prop `cF` | 0.0167 | Kalman seeds §4.4 (`c_F`) | Synthesis | n/a | Unvalidatable cross-signal gain (bpm⇔α1); inherits F_ref/sigmoid weakness; 0.2 anchor possibly ~2× low vs Rogers 2025 |
| `F_REF` | Constants.mc + prop `fRef` | 12 bpm | AFI scaling §4.5 | Synthesis | n/a | **AFI linear in 1/F_ref** — sets whole scale; sensitivity surfaced |
| `G_P` | Constants.mc + prop `gP` | 0.45 bpm/W | Kalman seeds §4.4 | Synthesis | n/a | Static-gain estimate ≈(HRmax−HRrest)/P_at_HRmax; white paper's ≈0.15 (P_max as sprint peak) saturated AFI — harness-flagged, corrected to ~0.45 (denominator = power at HR_max ≈ threshold) |
| `Q_* / R_HR / R_A1 / P0_*` | Constants.mc + props | see file | Kalman Q/R §4.4 | Synthesis | n/a | Hand-set; no on-bike ground truth; R inflated (correlated noise) |
| `AFI_FRESH/BUILDING/HIGH_MAX` | Constants.mc | 30 / 60 / 85 | AFI bands §4.5 | Convention | n/a | `F_ref`-dependent absolute-in-disguise; also fires on per-athlete AFI drift; calibrate |
| `SIG_A0 / SIG_A1 / SIG_S` | Constants.mc + props `a0/a1/sigmoidS` | 1.0 / 0.5 / 0.02 | A1_target map | PMC11280911 | High | Population map **not universal** (44% |r|>0.7); a0/a1 set so the midpoint crosses the **α1=0.75 AeT anchor** at P_AeT (white paper's 1.1/0.6 gave 0.80 — harness-flagged); decoupling-only fallback on fit failure |
| `DFA_R2_GATE` | Constants.mc / CalibrationFit.mc | 0.75 | calibration §10 | white-paper §10 | n/a | Fit-acceptance gate; below → decoupling-only, α1 display-only |
| `WPRIME_MATCH_FRAC` | Constants.mc / EffortCharacterizer.mc | 0.20 | W′ match §8.2 | Skiba | High | Established; depends on good CP/W′ (stale-CP caveat surfaced) |
| `TRIMP_MALE_COEFF/EXP` | Constants.mc / TrainingLoadLedger.mc | 0.64 / 1.92 | Banister TRIMP | references.md (Banister) | High | Male form unambiguous |
| `trimpFemaleCoeff` (+`TRIMP_FEMALE_EXP`) | prop / Constants.mc | **0.86** / 1.67 | Banister female coeff | references.md 🟡 | 🟡 | **UNRESOLVED (0.86 vs 0.64)** — exposed as SETTING per prompt; default 0.86 (Banister 1991) |
| `TAU_ST / TAU_FT` (context) | — (not used for `F`) | 28 / 47 s | DALE constants | Gløersen 2022 | High | **Validated for VO₂ only (n=8) — does NOT transfer to `F`**; intentionally not applied to the HR-drift state |
| `EF_BASELINE_START/END_S` | Constants.mc | 300 / 900 s | decoupling baseline §3.1 | Friel/TrainingPeaks | High | Baseline window minutes 5–15 (convention) |
| `DURABILITY_MIN_S` | Constants.mc | 3600 s | durability advisory §6 | Maunder/Stevens (timing) | High | Advisory needs ≥60–90 min work |
| `DFA_WINDOW_S / RECOMPUTE_S / BOX_MIN/MAX` | Constants.mc | 120 / 5 / 4 / 16 | DFA pipeline §3.3 | Rogers/Gronwald | High | Pipeline convention (2-min window, 5-s recompute, boxes 4–16) |
| `ARTIFACT_GOOD` (+ `artifactGate`) | Constants.mc / props | 1 % / 5 % | RR-quality weight §4.5 / artifact gate §3.3 | Rogers/Gronwald | High | w_rr breakpoints; hard artifact gate default 5% (prefer <3%) |
| `RR_STALE_S` | Constants.mc / PrimitivesCalculator.mc | 10 s | graceful degradation §8.4 (staleness timer) | white-paper §8.4 | n/a | Engineering timeout: no fresh RR for this long → α1 marked unavailable (don't emit a stale α1 off an aged buffer), reacquire cleanly |
| `F0_SEED f()` | TrainingLoadLedger.seedFatigueBpm | ATL/TSB/RMSSD→bpm | seeding §7 | Synthesis | n/a | Cross-domain, uncited; presented as **coarse bucket**, not a point |
| `PROJECTED_AFI` (range) | FatigueMeterView.drawDial | now ± AFI uncertainty | dial §8.1 | Synthesis | n/a | Forecast; **gated on pilot; rendered as a shaded range**, not a hard tick |
| Feat/Attrition weights | EffortCharacterizer.mc | arbitrary | §8.2 red-typing | Synthesis | n/a | No labeled data, no error rate; **off the advisory critical path** |

**Now live settings (review round 1):** the convention/synthesis values that gate
live output — `afiFresh`/`afiBuilding` (AFI band), `decoupRef` (blend scale),
`seedA`/`seedB`/`seedTsbScale` (seeding map), and the Feat/Attrition weights
(`featWSev`/`featMatchW`/`featBestW`/`attrDriftW`) — are now read from
`Application.Properties` via `Config`, not hard-coded, so changing the setting
changes behaviour (honesty rule). The AFI band also fires on a **per-athlete AFI
drift** above the athlete's own rolling baseline (`afiDriftAboveBaseline`,
margin `afiDriftMargin`), so the absolute cutoff is not the sole gate.

**Coverage note (for the harness):** every physiological constant referenced in
`source/` has a row above. The DALE `TAU_ST/TAU_FT` row is included to record that
those "Validated (VO₂)" constants are **deliberately not** applied to the HR-based
`F` state. `c_F`, the projected-AFI range, and the `f()` seeding map — flagged as
gaps in the earlier stub — now have rows.
