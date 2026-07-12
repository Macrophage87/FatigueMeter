# Building & sideloading FatigueMeter (Edge 1050)

FatigueMeter is a Garmin **Connect IQ data field** written in Monkey C. It targets
the **Edge 1050** primarily and is portable to other power-capable colour Edge /
Forerunner devices (see `manifest.xml`).

## Prerequisites

- **Connect IQ SDK 4.1.0 or newer** (`minSdkVersion` in `manifest.xml`).
  Install via the [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/).
- A **developer key**. Generate one once:
  ```sh
  openssl genrsa -out developer_key.pem 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem \
      -out developer_key.der -nocrypt
  ```
- The Edge 1050 device definition installed in the SDK (via the SDK Manager's
  *Devices* tab).

## Build

```sh
# from the repo root
monkeyc \
  -f monkey.jungle \
  -o bin/FatigueMeter.prg \
  -y developer_key.der \
  -d edge1050
```

To build for a different device, change `-d` to any product id listed in
`manifest.xml` (e.g. `edge840`, `fr965`).

## Run in the simulator

```sh
connectiq            # launches the Connect IQ simulator
monkeydo bin/FatigueMeter.prg edge1050
```

In the simulator, use **Simulation → Activity Data → Play** (or load a FIT/CSV)
to drive `compute()`. Use **Simulation → Sensors** to toggle power / HR / cadence
and to inject **HRV (RR) intervals** so DFA-α1 activates. Toggling sensors off is
the manual way to exercise the graceful-degradation matrix (white paper §8.4).

## Unit tests (off-device, pure functions)

The pure formula functions have Connect IQ unit tests in
`source/PureFunctionTests.mc` (NP, decoupling, W′bal, TSS, TRIMP, CTL/ATL/TSB,
DFA-α1, the Kalman predict/update, the α1↔F coupling, and the
respiration-does-not-manufacture-fatigue check):

```sh
monkeyc -f monkey.jungle -o bin/FatigueMeter-test.prg \
        -y developer_key.der -d edge1050 --unit-test
monkeydo bin/FatigueMeter-test.prg edge1050 -t
```

The **separate** model-consistency harness (Python) specified in
`docs/prompts/scientific-validation-prompt.md` exercises the documented model
across synthetic and real rides; it is regression protection, **not** external
validity (there is no on-bike fatigue ground truth).

## Sideload to an Edge 1050

1. Build `bin/FatigueMeter.prg` as above.
2. Connect the Edge over USB (mass-storage mode).
3. Copy `bin/FatigueMeter.prg` into `GARMIN/Apps/` on the device.
4. Eject, then add **FatigueMeter** as a data field to a full-screen data page
   (it is designed to occupy the whole screen — white paper §8.1).
5. Configure settings (FTP/CP/W′, HR max/rest, sex, CTL/ATL seed, band cutoffs,
   filter τ/κ/gains) in **Garmin Connect Mobile → device → Activities & App
   Management → Data Fields → FatigueMeter → Settings**, or in the simulator via
   **File → Edit Persistent Storage / App Settings**.

## Sensors required for full functionality

- **Power meter** — NP, decoupling, kJ, W′bal, FeatScore, power-TSS.
- **HR** — AFI/`F`, decoupling, HR-TRIMP.
- **RR-capable chest strap** (Polar H10 class) — DFA-α1, RMSSD, fB. Wrist optical
  HR is **not** adequate for DFA-α1.

Any subset works: a missing sensor greys only its dependent tiles; the screen
never blanks and never crashes (white paper §8.4).
