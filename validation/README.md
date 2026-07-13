# FatigueMeter — Model-Consistency Validation Harness

A runnable harness that checks the FatigueMeter app's computed values stay
**internally consistent with the project's stated model** (`docs/white-paper.md`,
`docs/literature-review.md`, `docs/references.md`). Built from
`docs/prompts/scientific-validation-prompt.md`.

## Epistemic status — read this first

This harness verifies **"the app does not contradict the project's stated model."**
That is valuable **regression protection**. It is **NOT** a proof that the app
agrees with physiological reality. **Self-consistency ≠ external validity:** the
documents it checks against are authored by this same project and contain
synthesis and speculation, so a wrong assumption will be "certified" here. Only
the criterion-validity pilot (white-paper §10) — an **association analysis**
against a *measured* external fatigue readout (sustained-power decrement, lactate,
RPE, next-day readiness), **not** this harness — can establish external validity,
and even that is limited by the absence of an on-bike fatigue ground truth. The
report prints this caveat in its header.

## What it checks (tiered)

Every assertion is labelled with a **tier** and the consensus statement it
enforces (see `fatiguemeter/catalog.py`):

| Tier | Meaning | Build effect |
|---|---|---|
| **HARD** | definitional identity / bound (TSB=CTL−ATL, AFI∈[0,100], NP definition, linear-KF, band ordering, artifact gate, covariance PSD, ledger idempotency) | violation FAILS |
| **ADVERSARIAL** | robustness / no-crash under corrupt RR, dropouts, extremes, and the full §8.4 degradation matrix | violation FAILS |
| **HONESTY** | convention/synthesis values are live settings; defaults match; advisory/uncalibrated/disclaimer present; descriptive mood (no imperative); no "damage"; traceability coverage | violation FAILS |
| **CALIBRATION** | no-calibration defaults; R²>0.75 fit gate; threshold-crossing regression; criterion-validity **stub** (skipped, owed) | violation FAILS (stub SKIPs) |
| **PLAUSIBILITY** | ensemble-level directions the literature establishes (α1↓ with intensity, decoupling↑ under drift, durability magnitude, coupling wired, respiration≠fatigue, long-Z2→moderate, recovery relaxes F, Feat vs Attrition, TSB taper, load realism) | violation **WARNS only** |

The plausibility checks are deliberately **tolerant and ensemble-level** (ranges
and directions, never per-run equalities or per-run monotonicity), because the
science is explicitly uncertain (individual α1 variability ±0.28, running-vs-
cycling α1 collapse, low-SNR sub-threshold decoupling, contested ACWR).

## How the app's formulas are exercised

The app is Monkey C (can't run off-device), so `fatiguemeter/model.py` is a
**faithful Python port** of the pure functions in `source/*.mc` (the
"reimplemented faithfully and cross-checked" path the prompt allows). Each port
names its `source/*.mc` origin. `fatiguemeter/engine.py` mirrors
`PrimitivesCalculator` + `FatigueMeterView.compute` so whole rides can be driven
through the model. The honesty checks parse the **actual repo files**
(`resources/*.xml`, `docs/traceability.md`) so they validate what ships, not the
port.

> **Keep the port in sync.** If you change a formula in `source/*.mc`, update the
> matching function in `model.py`. `HN2` cross-checks the ported defaults against
> `resources/properties/properties.xml` to catch drift in the constants.

## Running

```sh
cd validation
pip install -r requirements.txt

# human-readable report (coach/scientist readable), + optional markdown
python run_report.py
python run_report.py --md report.md

# the pytest suite (catalog tier contract + property-based layer)
python -m pytest -q
```

`run_report.py` exits non-zero if any hard-invariant/requirement fails. The full
ride simulations make the suite take a few minutes; the pure-function property
tests (`tests/test_properties.py`, hypothesis) are fast.

Real files: `fatiguemeter/signals.py` ingests **CSV** (`time,power,hr,cadence,rr`;
RR values `|`-separated) out of the box, and **FIT** via the optional `fitparse`
package (`pip install fitparse`). A tiny CSV fixture is in `tests/data/`.

## CI

`.github/workflows/validation-harness.yml` runs the harness on every PR and on
pushes to `main`: it installs `requirements.txt`, runs `run_report.py` (which
**exits non-zero on any HARD/STRUCTURAL/ADVERSARIAL/HONESTY/CALIBRATION failure**,
so a structural regression blocks the merge), then the pytest suite, and uploads
the human-readable report as a build artifact. PLAUSIBILITY checks only warn and
never fail the build.

## A real bug this harness caught

The default static HR–power gain `gP` shipped as `0.15` (the white paper's `≈`
value, which implies P_max≈930 W — a sprint peak). That made `HR_ss` underestimate
fresh HR by ~50 bpm, so `F` absorbed the gap and **AFI saturated to ~100 on every
ride** — violating the white paper's own §4.4 requirement that a long steady Z2
ride yields a *moderate*, not severe, AFI. The check `P9` failed until `gP` was
corrected to `0.45` (P_max = power at HR_max ≈ threshold). See the app's
`IMPLEMENTATION_NOTES.md`.

## Layout

```
validation/
├── README.md
├── requirements.txt
├── run_report.py                 # human-readable report entry point
├── conftest.py
├── fatiguemeter/
│   ├── model.py                  # faithful Python port of source/*.mc pure functions
│   ├── engine.py                 # rolling 1 Hz ride engine (compute-loop mirror)
│   ├── signals.py                # synthetic generators + CSV/FIT ingestion
│   ├── provenance.py             # parses traceability.md + resources/*.xml (honesty)
│   └── catalog.py                # the tiered assertion catalog (single source of truth)
└── tests/
    ├── test_catalog.py           # runs the catalog through pytest with the tier contract
    ├── test_properties.py        # hypothesis property-based layer over pure functions
    ├── test_ingestion.py         # CSV ingestion smoke test
    └── data/sample_ride.csv
```
