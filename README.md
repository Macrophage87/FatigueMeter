# FatigueMeter

**A research-grounded model and Garmin Connect IQ data field for measuring cyclist fatigue in real time from power, heart rate, and heart-rate variability — and for tracking residual training-scale fatigue over days to weeks.**

---

## What this project is

FatigueMeter is an attempt to turn the exercise-physiology literature on the **aerobic "slow component," durability, and training load** into a set of concrete, computable fatigue metrics that can run on a wrist/bike computer from signals a cyclist already carries:

- **Mechanical power** (1 Hz, from a power meter)
- **Heart rate** (1 Hz)
- **Beat-to-beat RR intervals** (from an RR-capable chest strap, e.g. Polar H10 — required for DFA-α1)

No gas-exchange (VO₂) hardware is assumed on-device. The unifying idea is that the aerobic slow component and cardiovascular/autonomic drift are **latent fatigue states** that we cannot measure directly but can *infer* from the way HR and HRV decouple from power over time.

This repository holds both the **research/design layer** (literature review, white paper, generation/validation prompts) **and the resulting Connect IQ data field** — a Monkey C implementation targeting 8 Garmin Edge / Forerunner / fenix products (Edge 1050 lead), in `source/` + `manifest.xml`, with a packaged store build in `store/FatigueMeter.iq`. The docs remain the spec; the code is the app the spec generated.

## The questions this project tries to answer

1. **Model fatigue on two timescales** — acute fatigue accumulated *during* a ride, and residual fatigue carried from a longer training program — with reasonable metrics for each, including both the raw numbers and the point at which those numbers become *concerning*.
2. **Provide on-ride fatigue metrics on a single large "decision" screen** — a full-screen glance layout the rider flips to a few times per ride for a "keep going" or "turn back / ease off" call, not a field watched constantly.
3. **Estimate the productive-to-damaging transition** — if the evidence supports it, flag when a ride shifts from being a productive training stimulus to mainly additional fatigue and damage.
4. **Model the fatigue metric at both the start and the end of a ride**, so residual (pre-ride) fatigue and end-of-ride fatigue are both represented.
5. **Store the markers through the ride and roll them into a session result** (via FIT developer fields + persistent storage) for easy comparison across rides.
6. **Characterize *why* the athlete is in the red** — distinguish a **Feat of Strength** (extreme fatigue bought with real output: big efforts, W′ "matches," power PRs) from **Attrition** (fatigue from drift/hole-digging), so a deliberately hard day is celebrated rather than scolded. Green/amber/red is retained, with a gold accent for feats of strength.

## Modeled behavior of each fatigue variable

How each fatigue variable is modeled to behave **as fatigue increases** — the
acute drift state and index, the Layer-1 primitives, the residual-load
accounting, and the effort characterization. Curves are computed from the
white-paper model equations (see [`docs/figures/`](docs/figures/), regenerate with
`python docs/figures/generate_figures.py`), and are provided in both **vector
(SVG)** and **raster (PNG)** form.

![Modeled behavior of each fatigue variable with increasing fatigue](docs/figures/00_overview.png)

Full-size, per-variable figures with equations and evidence notes are in
[white paper Appendix A](docs/white-paper.md#appendix-a--figures-modeled-behavior-of-each-fatigue-variable)
and the [literature-review appendix](docs/literature-review.md#appendix--figures-how-each-reviewed-marker-behaves-with-increasing-fatigue).

> These are **illustrative shapes, not calibrated measurements** — the fused AFI
> and durability advisory are synthesis-grade and unvalidated against any external
> fatigue criterion (white paper §10).

## Repository structure

```
FatigueMeter/
├── README.md                                   ← you are here
├── BUILD.md                                    ← build / simulate / sideload
├── IMPLEMENTATION_NOTES.md                     ← engineering choices & exposed settings
├── manifest.xml  monkey.jungle                 ← Connect IQ data-field manifest + build config
├── source/                                     ← Monkey C implementation (19 modules + 2 test)
├── resources/                                  ← strings, settings UI, property defaults, drawables
├── scripts/                                    ← CI helpers (traceability + (:test)-count lints)
├── store/                                      ← packaged FatigueMeter.iq + Garmin store assets
└── docs/
    ├── literature-review.md                    ← the full, cited literature review
    ├── white-paper.md                          ← the design white paper (model spec, metrics, thresholds)
    ├── references.md                           ← consolidated bibliography with verification status
    ├── traceability.md                         ← constant→provenance matrix (every Constants.mc symbol)
    ├── connectiq-ci-setup.md                   ← CI / toolchain setup notes
    ├── figures/                                ← fatigue-variable behavior figures (SVG + PNG) + generator
    ├── paper/                                  ← typeset paper sources
    ├── reviews/                                ← design & review notes
    └── prompts/
        ├── connectiq-app-generation-prompt.md          ← LLM prompt to generate the Connect IQ app
        ├── connectiq-settings-parameters-prompt.md     ← LLM prompt for the settings / parameters schema
        └── scientific-validation-prompt.md             ← LLM prompt for a scientific-consistency validation scheme
```

## Reading order

- Start with **[docs/literature-review.md](docs/literature-review.md)** for the evidence base (slow component, VO₂ kinetics, DFA-α1, decoupling/durability, training-load models, and the productive-vs-damaging question).
- Then **[docs/white-paper.md](docs/white-paper.md)** for how that evidence becomes a concrete multi-timescale model with equations, numeric thresholds, and a display design.
- The two files under **[docs/prompts/](docs/prompts)** are the executable next steps: one generates the app, one generates a validation harness that checks the app's numbers against the scientific consensus recorded here.

## Status & provenance

- **Stage:** implemented (pre-pilot). The Connect IQ data field is built (`source/`, 19 modules) and packaged (`store/FatigueMeter.iq`); it has been through Garmin store submission. The precise numeric AFI stays gated off (`positivePilot` / `shipNumberOverride`) until calibrated against labeled rides, so shipped output is the 3-state advisory only (§8.1). See `BUILD.md` to build/sideload and `IMPLEMENTATION_NOTES.md` for engineering choices.
- **Evidence base:** assembled from ~25 primary and secondary sources via deep full-text reads. Every load-bearing claim in the literature review carries a citation and, where relevant, a **verification flag** (confirmed / partially verified / unverified-paywalled / author's synthesis). Several agreement statistics for DFA-α1 thresholds and a handful of coaching-convention thresholds (e.g. Training Stress Balance bands) are explicitly marked as *not traceable to a peer-reviewed cutoff* — they are configurable defaults, not validated constants.
- **Honesty note:** the single most important caveat in the whole project is that **no published, validated model estimates the VO₂ slow component (or "damage") directly from power + HR + HRV.** FatigueMeter composes validated *pieces* (DFA-α1 thresholds, aerobic decoupling, DALE-style efficiency-loss kinetics, Banister/CTL-ATL-TSB load accounting) into a *new* estimator. The fused estimator itself must be calibrated against the user's own labeled rides before its fatigue state is trusted.

## Important disclaimer

FatigueMeter is a training-analysis concept, **not a medical device**. Its outputs are estimates of physiological state derived from consumer sensors and are subject to sensor error (especially RR/HRV quality), individual variability, and model assumptions. It does not diagnose overtraining syndrome or any medical condition, and it must not be used as a substitute for medical advice, coaching judgment, or subjective self-assessment.

## License

TBD.
