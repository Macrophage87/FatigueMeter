# LLM Prompt — Reproduce the FatigueMeter Connect IQ Settings Parameters

Paste the prompt below into a capable coding LLM to generate the Garmin
Connect IQ **settings / properties** for FatigueMeter. It enumerates **every**
user-configurable parameter exposed in the Garmin Connect / Connect IQ settings
menu, using the **exact display name** the athlete sees and in the **exact order**
the settings appear on screen.

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

### Notes carried from the source files
- The `Sex` setting is stored as the boolean `sexFemale` (`false` = Male, `true` = Female).
  The strings `Male` / `Female` exist for a labelled toggle; the underlying control is boolean.
- Group headers (`Athlete profile`, `Acute filter (advanced)`, `Bands & thresholds`,
  `Options`) exist as strings (`SetGroupProfile`, `SetGroupFilter`, `SetGroupBands`,
  `SetGroupOptions`). The `Filter gains & noise` block is a subsection of the advanced
  filter settings; keep items 30–39 immediately after item 29 and before Options.
- These are **not** every constant in the model — only the values the white paper marks
  "convention" or "synthesis" are exposed as settings (white-paper §9). Do not add or
  remove parameters; the exposed set and their order are the honesty contract
  (changing a setting must change behaviour). See `docs/traceability.md` for provenance.

### Deliverables
Produce `resources/settings/settings.xml`, `resources/properties/properties.xml`, and the
relevant `<string>` entries in `resources/strings/strings.xml` such that the rendered
Connect IQ settings menu shows the 43 parameters above, with the exact titles, in the
exact order, with the exact ranges and defaults.
