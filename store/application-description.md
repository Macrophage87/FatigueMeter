# FatigueMeter — Connect IQ Store Application Description

*(Derived from the FatigueMeter white paper. Copy the body below into the Connect IQ
Store "Description" field. A short one-liner is provided first for the store subtitle.)*

---

## Store subtitle (one line)

Durability & fatigue on one glance screen — power, heart rate, and HRV, honestly.

---

## Description

**FatigueMeter turns your ride into one clear "keep going or ease off" read.** It is a
full-screen data field that estimates how your fatigue is building — on two timescales
— from three signals you already carry: mechanical **power**, **heart rate**, and
beat-to-beat **RR intervals** (HRV). No lab, no gas-exchange gear.

You flip to it a few times per ride when you want a decision, not a number to stare at.
It leads with a plain-language status:

- **FRESH / PRODUCTIVE** — you're riding within your aerobic means.
- **FATIGUE BUILDING** — drift is accumulating; still productive work.
- **DURABILITY MARKERS DRIFTING** — the markers say remaining work is now mostly
  fatigue. And because going deep into the red is often the *point*, it tells you
  *why*: a **Feat of Strength** (a big climb or effort you're buying with real output)
  versus **Attrition** (drift with fading output).

### What it shows
- A **fatigue dial** with a green / amber / red band and start-vs-now drift.
- An **evidence row**: aerobic decoupling %, DFA-α1 (with a data-quality dot),
  kilojoules versus your personal durability anchor, and W′ "matches" burned.
- A **feats strip**: best 5-minute power, biggest climb, matches burned, and your
  training-stress balance carried into the ride.
- **Start-of-ride and end-of-ride** fatigue, so you can see how much you brought with
  you and how much you added.

### It logs everything for later
Every marker is written to the **FIT file** (developer fields), so it flows to Garmin
Connect and third-party analysis. A per-ride **session summary** is stored on the
device so you can compare "was today a feat-of-strength day or an attrition day?"
across rides.

### Built to degrade gracefully
Lose a sensor mid-ride and nothing else breaks: drop the power meter and it falls back
to heart-rate load; drop the chest strap and it runs a decoupling-only estimate; any
missing input greys out only the tiles that need it. The screen never blanks and never
crashes.

### Honest by design
This is the part most fatigue apps skip. FatigueMeter separates what is **validated**
from what is **inferred**:

- The **validated backbone** — aerobic decoupling, CTL/ATL/TSB training-load
  accounting, durability-drift magnitudes, and the population DFA-α1 = 0.75 aerobic-
  threshold anchor — is standard, well-supported sports science.
- The **fused Acute Fatigue Index** and the durability advisory are an *estimate*, not
  a measurement. There is no fatigue "ground truth" available on a bike, so the index
  is calibrated to your own consistency and every screen carries a persistent
  **"advisory · not a validated measurement"** tag. It never issues a command, only a
  description.

You can calibrate it to your thresholds, tune every band in Settings, and (optionally)
unlock a precise numeric index once you've validated it against your own efforts.

### What you need
- A **power meter** — for decoupling, kilojoules, W′ balance, and power-based load.
- **Heart rate** — for the fatigue index and heart-rate load.
- An **RR-capable chest strap** (Polar H10 class) — for DFA-α1 and HRV. Wrist optical
  heart rate is **not** accurate enough for DFA-α1; without a strap the app runs its
  decoupling-only fallback.

Add FatigueMeter to a full-screen data page and configure your FTP, critical power,
W′, HR max/rest, and sex in Settings.

### Important
FatigueMeter is a **training-analysis tool, not a medical device.** It does not
diagnose overtraining syndrome or any medical condition. Its within-ride fatigue
estimate is not clinically validated, and the outdoor within-ride use of DFA-α1 in
particular is still an area of active research. Use it as one input alongside your own
judgment and coaching.

---

*Requires a compatible power-capable colour Edge or Forerunner/fēnix device (see
device list). Settings are configured in Garmin Connect Mobile.*
