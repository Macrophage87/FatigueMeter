# FatigueMeter

**A research-grounded model and Garmin Connect IQ concept for measuring cyclist fatigue in real time from power, heart rate, and heart-rate variability — and for tracking residual training-scale fatigue over days to weeks.**

---

## What this project is

FatigueMeter is an attempt to turn the exercise-physiology literature on the **aerobic "slow component," durability, and training load** into a set of concrete, computable fatigue metrics that can run on a wrist/bike computer from signals a cyclist already carries:

- **Mechanical power** (1 Hz, from a power meter)
- **Heart rate** (1 Hz)
- **Beat-to-beat RR intervals** (from an RR-capable chest strap, e.g. Polar H10 — required for DFA-α1)

No gas-exchange (VO₂) hardware is assumed on-device. The unifying idea is that the aerobic slow component and cardiovascular/autonomic drift are **latent fatigue states** that we cannot measure directly but can *infer* from the way HR and HRV decouple from power over time.

This repository currently holds the **research and design layer**. It is not yet an app — it is the literature review, the white paper that specifies the model, and the generation/validation prompts needed to build the app responsibly.

## The questions this project tries to answer

1. **Model fatigue on two timescales** — acute fatigue accumulated *during* a ride, and residual fatigue carried from a longer training program — with reasonable metrics for each, including both the raw numbers and the point at which those numbers become *concerning*.
2. **Provide on-ride fatigue metrics on a single large "decision" screen** — a full-screen glance layout the rider flips to a few times per ride for a "keep going" or "turn back / ease off" call, not a field watched constantly.
3. **Estimate the productive-to-damaging transition** — if the evidence supports it, flag when a ride shifts from being a productive training stimulus to mainly additional fatigue and damage.
4. **Model the fatigue metric at both the start and the end of a ride**, so residual (pre-ride) fatigue and end-of-ride fatigue are both represented.
5. **Store the markers through the ride and roll them into a session result** (via FIT developer fields + persistent storage) for easy comparison across rides.
6. **Characterize *why* the athlete is in the red** — distinguish a **Feat of Strength** (extreme fatigue bought with real output: big efforts, W′ "matches," power PRs) from **Attrition** (fatigue from drift/hole-digging), so a deliberately hard day is celebrated rather than scolded. Green/amber/red is retained, with a gold accent for feats of strength.

## Repository structure

```
FatigueMeter/
├── README.md                                   ← you are here
└── docs/
    ├── literature-review.md                    ← the full, cited literature review
    ├── white-paper.md                          ← the design white paper (model spec, metrics, thresholds)
    ├── references.md                           ← consolidated bibliography with verification status
    └── prompts/
        ├── connectiq-app-generation-prompt.md  ← LLM prompt to generate the Connect IQ app
        └── scientific-validation-prompt.md     ← LLM prompt for a scientific-consistency validation scheme
```

## Reading order

- Start with **[docs/literature-review.md](docs/literature-review.md)** for the evidence base (slow component, VO₂ kinetics, DFA-α1, decoupling/durability, training-load models, and the productive-vs-damaging question).
- Then **[docs/white-paper.md](docs/white-paper.md)** for how that evidence becomes a concrete multi-timescale model with equations, numeric thresholds, and a display design.
- The two files under **[docs/prompts/](docs/prompts)** are the executable next steps: one generates the app, one generates a validation harness that checks the app's numbers against the scientific consensus recorded here.

## Status & provenance

- **Stage:** research / design. No Monkey C application code exists yet.
- **Evidence base:** assembled from ~25 primary and secondary sources via deep full-text reads. Every load-bearing claim in the literature review carries a citation and, where relevant, a **verification flag** (confirmed / partially verified / unverified-paywalled / author's synthesis). Several agreement statistics for DFA-α1 thresholds and a handful of coaching-convention thresholds (e.g. Training Stress Balance bands) are explicitly marked as *not traceable to a peer-reviewed cutoff* — they are configurable defaults, not validated constants.
- **Honesty note:** the single most important caveat in the whole project is that **no published, validated model estimates the VO₂ slow component (or "damage") directly from power + HR + HRV.** FatigueMeter composes validated *pieces* (DFA-α1 thresholds, aerobic decoupling, DALE-style efficiency-loss kinetics, Banister/CTL-ATL-TSB load accounting) into a *new* estimator. The fused estimator itself must be calibrated against the user's own labeled rides before its fatigue state is trusted.

## Important disclaimer

FatigueMeter is a training-analysis concept, **not a medical device**. Its outputs are estimates of physiological state derived from consumer sensors and are subject to sensor error (especially RR/HRV quality), individual variability, and model assumptions. It does not diagnose overtraining syndrome or any medical condition, and it must not be used as a substitute for medical advice, coaching judgment, or subjective self-assessment.

## License

TBD.
