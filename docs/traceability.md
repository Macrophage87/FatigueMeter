# Traceability Matrix (stub — to be completed during implementation)

**Status:** stub. This file maps every physiological constant / threshold used in the FatigueMeter **code** back to (a) its row in the white-paper §9 provenance table, (b) its `references.md` source, and (c) its **evidence-strength** note. The `scientific-validation-prompt.md` traceability check reads this file; the `connectiq-app-generation-prompt.md` requires the app-builder to **complete it as a deliverable**. It is seeded here so the file exists and the check does not fail on a missing file, and so the mapping's intent is unambiguous.

**Rule:** no physiological constant may appear in code without a row here. A constant with no provenance is a defect.

| Code symbol (planned) | Value / default | White-paper §9 row | Source (references.md) | Extraction | Evidence strength |
|---|---|---|---|---|---|
| `AET_ALPHA1` | 0.75 | DFA-α1 = 0.75 | Rogers/Olson/Gronwald 2020 | High | Group-level only; ±10 bpm individual LoA; n=15, male-dominated, lab |
| `ANT_ALPHA1` | 0.5 | DFA-α1 = 0.5 | Rogers/Gronwald | High | Weak (HR r≈0.71) — **display only, not a band boundary** |
| `ALPHA1_DRIFT_FLAG` | ≳0.3 below personal baseline-for-power | per-athlete α1 drift | Synthesis (Rogers 2025 pattern) | n/a | Synthesis; the **absolute <0.5 cutoff is retired** (running-derived) |
| `DECOUPLE_OK / CAUTION / HIGH` | 5 / 8 / 10 % | Decoupling bands | Friel/TrainingPeaks | High | Coaching convention; steady-effort validity only; low SNR sub-threshold |
| `KJ_ANCHOR_LOW / HIGH` | 1500 / 2500 kJ | kJ anchors | Spragg / durability review | High | Population-level; person-specific in practice |
| `CTL_TAU / ATL_TAU` | 42 / 7 d | CTL/ATL EWMA | TrainingPeaks PMC | High | Standard/established |
| `TSB_BANDS` | +25/+5/−10/−30 | Friel TSB bands | coaching convention | High | **Not peer-reviewed** — configurable default |
| `ACWR_*` | 0.8–1.3 / 1.5 | ACWR | Impellizzeri/Lolli | High | **Contested** — opt-in, off by default |
| `TAU_ST / TAU_FT` | 28 / 47 s | DALE constants | Gløersen 2022 | High | **Validated for VO₂ only (n=8) — does not transfer to `F`** |
| `TAU_HR / TAU_A / TAU_REC` | 30 / 90 / 900 s | Kalman seeds §4.4 | Synthesis | n/a | Synthesis / **τ_rec unsourced**; calibrate per athlete |
| `KAPPA_I / KAPPA_D` | tuned | Kalman seeds §4.4 | Synthesis | n/a | Hand-set; no on-bike ground truth; `KAPPA_D` charges only while active |
| `C_F` | tuned (~0.2 α1 @ F_ref) | Kalman seeds §4.4 | Synthesis | n/a | Unvalidatable cross-signal gain; **inherits weakness of `F_REF` and `A1_SIGMOID`**; 0.2 anchor possibly ~2× low vs Rogers 2025 |
| `F_REF` | ~12 bpm | AFI scaling §4.5 | Synthesis | n/a | **AFI linear in 1/F_ref** — sets whole scale; sensitivity must be surfaced |
| `AFI_SEVERE` / band cutoffs | 85 / … | AFI bands §4.5 | Convention | n/a | `F_ref`-dependent absolute-in-disguise; also fires on per-athlete AFI drift; calibrate |
| `PROJECTED_AFI` | forecast | dial §8.1 | Synthesis | n/a | Forecast on hand-set κ/τ_rec + constant-power assumption; **gated on pilot; render as range** |
| `F0_SEED f()` | ATL/TSB/RMSSD→bpm | seeding §7 | Synthesis | n/a | Cross-domain, uncited; presented as coarse bucket |
| `A1_SIGMOID (a0,a1,s)` | 1.1, 0.6, 0.02/W | A1_target map | PMC11280911 | High | Population map **not universal** (44% |r|>0.7); calibrate per athlete |
| `WPRIME_MATCH_THRESH` | <20% then recovery | W′ match | Skiba | High | Established; depends on good CP/W′ |
| `TRIMP_COEFF_F` | **UNRESOLVED (0.86 vs 0.64)** | Banister female coeff | references.md | 🟡 | **Defect — resolve vs Banister 1991 or expose as setting before shipping** |

**To do during implementation:** replace "planned" symbols with the actual code identifiers, add file:line anchors, and add any new constants introduced. Keep the evidence-strength column in sync with white-paper §9.
