# LLM Prompt — Reproduce the FatigueMeter Connect IQ Settings Parameters

Paste the prompt below into a capable coding LLM to generate the Garmin
Connect IQ **settings / properties** for FatigueMeter. It enumerates **every**
user-configurable parameter exposed in the Garmin Connect / Connect IQ settings
menu, using the **exact display name** the athlete sees and in the **exact order**
the settings appear on screen.

The prompt has **two jobs**, in order:

1. **Reproduce the settings scaffold exactly** — the 43 titles, ids, ranges, and
   defaults (§ "Parameter list"). This is a pure transcription: names and order are exact.
2. **Generate a value for each parameter** from an athlete's training record
   (§ "How to generate each value"). This is the semantic layer: it says, per
   parameter, whether to personalize it, how to derive the number from the record,
   or to leave the documented default untouched. Without this layer the scaffold
   only clones an empty menu — it does not tell you *how the parameters are produced*.

The authoritative sources in this repository are:

- `resources/settings/settings.xml` — the settings menu (order, `propertyKey`, ranges).
- `resources/properties/properties.xml` — the persistent `Application.Properties` and defaults.
- `resources/strings/strings.xml` — the display titles referenced by each setting.

If any instruction below disagrees with those files, **the files win** — they are the
source of truth. This prompt is a faithful, self-contained transcription of them.

---

## PROMPT

You are an expert Garmin **Connect IQ / Monkey C** developer. Generate the settings
and properties resources for an app called **FatigueMeter**. You must reproduce the
settings **exactly** — every setting must use the **precise display title** given below,
appear in the **precise order** given below, use the stated control type, honor the
stated numeric min/max, and read from / write to the stated `Application.Properties`
key with the stated default.

### Hard requirements
1. **Names are exact.** Use the display title verbatim, including units, symbols
   (`τ`, `κ`, `α1`, `′`, `↔`, `%`), parentheses, and casing. Do not rename, abbreviate,
   expand, or "clean up" any title.
2. **Order is exact.** Emit the settings in the order listed (top to bottom, group by
   group). Garmin renders settings in document order; do not reorder or sort.
3. **One property per setting.** Each setting's `propertyKey` binds to the matching
   `Application.Properties` id. Boolean settings use a `boolean` control; all numeric
   settings use a `numeric` control with the given `min`/`max`.
4. **Defaults come from properties.** Seed each property with the default value and
   type shown. `type` is one of `number` (integer), `float`, or `boolean`.
5. Localize titles through `resources/strings/strings.xml` (title = `@Strings.<id>`);
   bind settings through `@Properties.<id>`. Do not hard-code literals in `settings.xml`.

### Parameter list — exact display name, in exact order

Format: `# | Display title (exact) | property id | control | min | max | default`

**Group 1 — Athlete profile**

| # | Display title (exact) | property id | control | min | max | default |
|---|---|---|---|---|---|---|
| 1 | `FTP (W)` | `ftp` | numeric | 80 | 600 | 250 (number) |
| 2 | `Critical Power (W)` | `cp` | numeric | 80 | 600 | 240 (number) |
| 3 | `W′ (J)` | `wPrime` | numeric | 3000 | 45000 | 20000 (number) |
| 4 | `HR max (bpm)` | `hrMax` | numeric | 120 | 230 | 190 (number) |
| 5 | `HR rest (bpm)` | `hrRest` | numeric | 30 | 90 | 50 (number) |
| 6 | `Sex` | `sexFemale` | boolean | — | — | false (boolean) |
| 7 | `CTL seed` | `ctlSeed` | numeric | 0 | 200 | 70.0 (float) |
| 8 | `ATL seed` | `atlSeed` | numeric | 0 | 200 | 70.0 (float) |

**Group 2 — Acute filter (advanced)**

| # | Display title (exact) | property id | control | min | max | default |
|---|---|---|---|---|---|---|
| 9 | `τ_HR (s)` | `tauHr` | numeric | 5 | 120 | 30.0 (float) |
| 10 | `τ_α1 (s)` | `tauA` | numeric | 20 | 240 | 90.0 (float) |
| 11 | `τ_rec (s)` | `tauRec` | numeric | 120 | 3600 | 900.0 (float) |
| 12 | `κ_i intensity charge` | `kappaI` | numeric | 0 | 0.02 | 0.000145 (float) |
| 13 | `κ_d duration charge` | `kappaD` | numeric | 0 | 0.01 | 0.0028 (float) |
| 14 | `c_F (α1↔F gain)` | `cF` | numeric | 0 | 0.1 | 0.0167 (float) |
| 15 | `F_ref (bpm)` | `fRef` | numeric | 4 | 30 | 12.0 (float) |

**Group 3 — Bands & thresholds**

| # | Display title (exact) | property id | control | min | max | default |
|---|---|---|---|---|---|---|
| 16 | `Decoupling OK %` | `decoupOk` | numeric | 1 | 15 | 5.0 (float) |
| 17 | `Decoupling caution %` | `decoupCaution` | numeric | 2 | 20 | 8.0 (float) |
| 18 | `Decoupling high %` | `decoupHigh` | numeric | 3 | 25 | 10.0 (float) |
| 19 | `DFA artifact gate %` | `artifactGate` | numeric | 1 | 20 | 5.0 (float) |
| 20 | `Durability kJ anchor` | `kjAnchor` | numeric | 800 | 4000 | 2000.0 (float) |
| 21 | `TRIMP female coeff (0.86/0.64)` | `trimpFemaleCoeff` | numeric | 0.5 | 1.0 | 0.86 (float) |
| 22 | `AFI fresh cutoff` | `afiFresh` | numeric | 10 | 60 | 30.0 (float) |
| 23 | `AFI building cutoff` | `afiBuilding` | numeric | 40 | 90 | 60.0 (float) |
| 24 | `AFI drift margin` | `afiDriftMargin` | numeric | 5 | 40 | 15.0 (float) |
| 25 | `Decoupling AFI ref %` | `decoupRef` | numeric | 3 | 20 | 8.0 (float) |
| 26 | `TSB fresh band` | `tsbFresh` | numeric | 0 | 30 | 10.0 (float) |
| 27 | `TSB overreach band` | `tsbOverreach` | numeric | -60 | -10 | -30.0 (float) |
| 28 | `Steadiness power CV gate` | `powerCvGate` | numeric | 0.02 | 0.5 | 0.10 (float) |
| 29 | `Coasting fraction gate` | `coastFracGate` | numeric | 0.02 | 0.5 | 0.10 (float) |

**Group 4 — Filter gains & noise (advanced)**

| # | Display title (exact) | property id | control | min | max | default |
|---|---|---|---|---|---|---|
| 30 | `g_P gain (bpm/W)` | `gP` | numeric | 0.05 | 0.4 | 0.15 (float) |
| 31 | `Sigmoid a0` | `a0` | numeric | 0.8 | 1.5 | 1.1 (float) |
| 32 | `Sigmoid a1` | `a1` | numeric | 0.2 | 1.2 | 0.6 (float) |
| 33 | `Sigmoid slope s` | `sigmoidS` | numeric | 0.005 | 0.1 | 0.02 (float) |
| 34 | `Q HR_ss` | `qHr` | numeric | 0.01 | 5 | 0.5 (float) |
| 35 | `Q HR` | `qHrLat` | numeric | 0.01 | 5 | 0.5 (float) |
| 36 | `Q α1` | `qA1` | numeric | 0.0001 | 0.05 | 0.002 (float) |
| 37 | `Q F` | `qF` | numeric | 0.001 | 1 | 0.05 (float) |
| 38 | `R HR` | `rHr` | numeric | 0.5 | 20 | 4.0 (float) |
| 39 | `R α1` | `rA1` | numeric | 0.002 | 0.2 | 0.0225 (float) |

**Group 5 — Options**

| # | Display title (exact) | property id | control | min | max | default |
|---|---|---|---|---|---|---|
| 40 | `Show ACWR (opt-in, contested)` | `acwrEnabled` | boolean | — | — | false (boolean) |
| 41 | `Numeric AFI unlocked (pilot)` | `positivePilot` | boolean | — | — | false (boolean) |
| 42 | `Ship AFI number pre-pilot (override)` | `shipNumberOverride` | boolean | — | — | false (boolean) |
| 43 | `Metric units` | `unitsMetric` | boolean | — | — | true (boolean) |

### How to generate each value from the athlete's training record

The tables above are the **schema**. This section is the **procedure** — it tells you
how to fill each property in, given an athlete's training record. Do not emit a value
without following the rule for that parameter.

**Available record inputs (assume you are handed some or all of these):**
- **Mean-maximal power curve** — the athlete's best average power over durations
  (5 s, 1, 3, 5, 8, 12, 20, 60 min) from recent rides.
- **Set / estimated FTP** already recorded on their training platform.
- **Wellness / HR data** — highest HR ever observed; resting/morning HR trend.
- **Fitness model** — current **CTL** (42-day EWMA of TSS, "Fitness"), current **ATL**
  (7-day EWMA, "Fatigue"), and the **TSB = CTL − ATL** history distribution.
- **Long-ride history** — per-ride total **kJ** and aerobic **decoupling %** (Pw:Hr).
- **Profile** — sex; unit/locale preference.

**Three generation tiers — classify every parameter into exactly one:**

- **Tier A — Personalize from the record.** Derive a number using the recipe below.
  Clamp the result to the setting's `[min, max]`; if the required input is missing,
  fall back to the documented default and say so.
- **Tier B — Set from a known profile fact.** A direct read (sex, units) — no modelling.
- **Tier C — Leave at the documented default.** These are un-calibrated model-internal
  tuning constants (Kalman time-constants, gains, process/measurement noise), data-quality
  gates, or release flags. An LLM must **not** invent them from a training record — doing
  so manufactures false confidence in an un-validated filter. Only a formal calibration
  pilot (white-paper §4.4/§4.5) may change them. Emit the default verbatim.

**Per-parameter generation rules:**

| # | Parameter | Tier | How to generate the value |
|---|---|---|---|
| 1 | `FTP (W)` | A | Platform FTP if present; else ≈ 0.95 × best 20-min power, or best ~40–60-min normalized power. Round to nearest watt. |
| 2 | `Critical Power (W)` | A | Fit the 2-parameter CP model `P(t) = W′/t + CP` to ≥2 maximal efforts (e.g. 3–12 min); `CP` is the asymptote. If no curve, seed CP ≈ FTP. Round to a whole watt (`number` type) and enforce `CP ≤ FTP` (see consistency pass). |
| 3 | `W′ (J)` | A | The `W′` term from the **same** CP-model fit as #2 (anaerobic work capacity), in **Joules** (`20000 J = 20 kJ` — a platform reporting kJ must be ×1000). Round to a whole Joule (`number` type); must be `> 0`. If unfittable, leave default (20000). |
| 4 | `HR max (bpm)` | A | Highest reliable HR observed in the record (max-effort intervals / field test), not an age formula if real data exists. |
| 5 | `HR rest (bpm)` | A | Lowest stable resting/morning HR from wellness data. |
| 6 | `Sex` | B | Direct from profile — set `sexFemale = true` for female, `false` for male. |
| 7 | `CTL seed` | A | The athlete's **current CTL / "Fitness"** at install time, from the training record. Clamp 0–200. |
| 8 | `ATL seed` | A | The athlete's **current ATL / "Fatigue"** at install time. Clamp 0–200. |
| 9–15 | `τ_HR (s)` … `F_ref (bpm)` | C | Acute Kalman time-constants and intensity/duration charges — **leave at default.** Calibration-only. |
| 16 | `Decoupling OK %` | C | Leave default (5%). The app already scores decoupling as **drift vs. the athlete's own minutes-5–15 baseline** (StatusEvaluator / PrimitivesCalculator), so these bands apply to *personalized drift* — re-deriving an absolute band would double-count the baseline. |
| 17 | `Decoupling caution %` | C | Leave default (8%). Applied to personalized drift; keep OK < caution < high. |
| 18 | `Decoupling high %` | C | Leave default (10%). Applied to personalized drift; same ordering. |
| 19 | `DFA artifact gate %` | C | Data-quality gate — leave default (5%). |
| 20 | `Durability kJ anchor` | A | The kJ at which the athlete's decoupling historically starts to drift (from long-ride history); else a typical hard-long-ride total. Clamp 800–4000. |
| 21 | `TRIMP female coeff (0.86/0.64)` | C | Leave default `0.86` — this is a **convention constant, not sex-driven** (its value does not change with the athlete's sex; the code only *applies* it when `sexFemale = true`, males use the `0.64·e^{1.92x}` form). Switch to `0.64` only as a deliberate literature choice. |
| 22 | `AFI fresh cutoff` | C | `F_ref`-dependent convention — calibration-only; leave default. |
| 23 | `AFI building cutoff` | C | As #22 — leave default (keep fresh < building). |
| 24 | `AFI drift margin` | C | As #22 — leave default. |
| 25 | `Decoupling AFI ref %` | C | `F_ref`-tied reference — leave default. |
| 26 | `TSB fresh band` | A | The TSB at which this athlete's history shows "fresh/productive." Derive from their TSB distribution (e.g. upper quantile) if available; else default 10. Clamp 0–30. |
| 27 | `TSB overreach band` | A | The TSB at which they historically feel over-reached (lower tail of their TSB distribution). Else default −30. Clamp −60…−10. |
| 28 | `Steadiness power CV gate` | C | Data-quality gate — leave default. |
| 29 | `Coasting fraction gate` | C | Data-quality gate — leave default. |
| 30–39 | `g_P gain (bpm/W)` … `R α1` | C | Kalman gains, sigmoid shape, and process/measurement noise — **leave at default.** These require formal filter calibration; never derive from a training record. |
| 40 | `Show ACWR (opt-in, contested)` | C | Behavioural flag — leave `false` (contested metric). |
| 41 | `Numeric AFI unlocked (pilot)` | C | Gated behind the criterion-validity pilot — leave `false`. |
| 42 | `Ship AFI number pre-pilot (override)` | C | Honesty override — leave `false`. |
| 43 | `Metric units` | B | From profile/locale — `true` for metric, `false` for imperial. |

**Type rounding.** `ftp`, `cp`, `wPrime`, `hrMax`, `hrRest` are `number` (integer) — round
every generated value to a whole number; never emit a fractional watt/Joule/bpm (a CP or
W′ from a curve fit **must** be rounded). `ctlSeed` / `atlSeed` are `float`, so a decimal
is fine there.

**Consistency pass (run after generating all Tier-A values, before emitting).** The Tier-A
parameters are derived independently, so assert these physiological orderings and repair
any violation by **keeping the more directly-measured value and falling the other back to
its default** (report the fallback):
- `CP ≤ FTP` — CP above FTP is physiologically wrong and breaks the model's `P_AeT` (drift)
  vs `CP` (severe-domain) split. If violated, trust the measured FTP and re-seed `CP ≈ FTP`.
- `HR rest < HR max`.
- `W′ > 0`.
- `TSB overreach band < TSB fresh band` (item 27 < item 26).

**Output contract for the generation step:** for every parameter emit `id`, the chosen
value, and a one-line reason keyed to its tier — e.g. `ftp = 268 (Tier A: 0.95 × 282 W
best-20min)`, `κ_i intensity charge = 0.000145 (Tier C: default, calibration-only)`,
`Metric units = true (Tier B: profile locale)`. Any Tier-A parameter whose input is
missing must fall back to its default and be reported as such — never fabricate.

### Notes carried from the source files
- The `Sex` setting is stored as the boolean `sexFemale` (`false` = Male, `true` = Female).
  The strings `Male` / `Female` exist but are **not referenced** by `settings.xml`, so the
  control renders as a raw on/off toggle (`on` = Female) with no Male/Female labels.
- The section names (`Athlete profile`, `Acute filter (advanced)`, `Bands & thresholds`,
  `Filter gains & noise`, `Options`) are **XML comments** in `settings.xml`, not `<group>`
  elements. The `SetGroupProfile/Filter/Bands/Options` strings exist but are unreferenced,
  so Garmin renders a **flat 43-item list** in document order — the groups here are an
  organizational aid, not on-screen headers. Order across the whole list is still exact:
  keep items 30–39 immediately after item 29 and before Options.
- These are **not** every constant in the model — only the values the white paper marks
  "convention" or "synthesis" are exposed as settings (white-paper §9). Do not add or
  remove parameters; the exposed set and their order are the honesty contract
  (changing a setting must change behaviour). See `docs/traceability.md` for provenance.

### Deliverables
1. **Scaffold:** `resources/settings/settings.xml`, `resources/properties/properties.xml`,
   and the relevant `<string>` entries in `resources/strings/strings.xml` such that the
   rendered Connect IQ settings menu shows the 43 parameters above, with the exact titles,
   in the exact order, with the exact ranges and defaults.
2. **Generated values:** a per-parameter list (all 43, in the same order) giving the value
   you chose, its tier (A/B/C), and the one-line reason, per the output contract above.
   Tier-C parameters must match the documented defaults exactly.
