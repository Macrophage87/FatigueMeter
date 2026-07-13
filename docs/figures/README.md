# Fatigue-variable behaviour figures

Each figure models how **one fatigue variable behaves as fatigue increases**,
drawn directly from the model equations in [`../white-paper.md`](../white-paper.md)
(§3–§5, corrected Rev-3 seed values) and the evidence in
[`../literature-review.md`](../literature-review.md). Every figure is provided in
**vector (`.svg`, `.pdf`)** and **raster (`.png`)** form — the `.pdf` is what the
LaTeX paper (`../paper/fatiguemeter.tex`) includes.

> **Honesty caveat (white paper §10):** these curves are **illustrative of the
> modelled behaviour** — shapes and directions, not calibrated magnitudes. The
> fused **AFI** and the durability advisory are synthesis-grade and have **not**
> been validated against any external fatigue criterion; the axes use the
> documented default constants, which are per-athlete-calibratable.

## Regenerating

```sh
python docs/figures/generate_figures.py
```

The script is self-contained (matplotlib + numpy) and keeps its constants in sync
with `source/Constants.mc` / `resources/properties.xml`. Colours follow the
validated data-viz palette (CVD-checked); every multi-series plot also carries
distinct line styles + direct labels, and status bands are always text-labelled,
so identity is never colour-alone.

## Index

| File | Variable | Behaviour with increasing fatigue |
|---|---|---|
| `00_overview` | all | small-multiples summary grid |
| `01_F_drift_state` | `F` residual cardiovascular drift | rises toward `F_ss = charge·τ_rec`, relaxes on recovery |
| `02_AFI_index` | Acute Fatigue Index | rises 0→100 through green/amber/red bands |
| `03_DFA_alpha1` | DFA-α1 | (a) falls with intensity through 0.75/0.50; (b) drifts below baseline-for-power |
| `04_decoupling` | aerobic decoupling % | rises as HR drift lifts, crossing 5 / 8 % |
| `05_efficiency_factor` | Efficiency Factor | declines (EF = NP/HR) |
| `06_hr_drift` | HR at fixed power | rises (HR = HR_ss + F) |
| `07_cadence_drift` | cadence drift | rises modestly (low-weight corroborator) |
| `08_wprime_bal` | W′bal & matches | sawtooth depletion; dips <20% count as "matches" |
| `09_kj_durability_clock` | intensity-weighted kJ | accumulates toward the durability anchor |
| `10_ctl_atl_tsb` | CTL / ATL / TSB | TSB falls negative under load, recovers on taper |
| `11_rmssd_baseline` | resting RMSSD | sustained decline below the personal −1 SD band |
| `12_feat_vs_attrition` | FeatScore vs AttritionScore | both rise — output-bought vs drift-bought red |
