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

## CI

`.github/workflows/ci.yml` runs on every push to `main` and on every pull
request. It is deliberately **lightweight**: every job runs on stock
GitHub-hosted `ubuntu-latest` and needs **no self-hosted runner**. The lint
jobs need no Connect IQ SDK at all; the compile/unit-test gate gets the SDK from
a pre-built Docker image (see `test` below).

- **`manifest-lint`** — `scripts/check_manifest_appid.sh`, a packaging check
  that guards the historical placeholder / store-reject app-id class (a bad
  32-hex id, an all-zero or all-same-character id). A compile+test path cannot
  see this — a bad id still compiles and still passes tests — which is exactly
  why this cheap runner-free check exists.
- **`test`** (advisory, `continue-on-error`) — the **compile + unit-test gate**.
  It uses the `matco/action-connectiq-tester` Docker action, which ships the
  Connect IQ SDK (`9.2.0`, incl. `edge1050`) and the "Run No Evil" `(:test)`
  framework baked into a container image, so it runs the compile + off-device
  unit tests on a stock GitHub-hosted runner with **no SDK download and no
  self-hosted runner**. It targets `device: edge1050` (falling back to the
  action's default `fenix7` if that device is not in the image). The action is
  SHA-pinned to `master@60fd2e8` (= SDK 9.2.0) for supply-chain safety. It is
  **advisory** for now so a broken/mismatched image cannot block merges; once a
  real GitHub run confirms the image builds `edge1050` and the tests pass,
  promote it to required by adding `test` to `ci-required`'s `needs`.
- **`traceability`** (advisory, `continue-on-error`) —
  `scripts/check_traceability.py` enforces "no physiological constant in
  `source/Constants.mc` without a `docs/traceability.md` row." It is advisory
  until the matcher is hardened; it can be promoted into the required set later
  (add it to `ci-required`'s `needs`) once it no longer produces false
  positives.
- **`ci-required`** — the aggregator job that `needs: [manifest-lint]`. **This
  is the single stable required status check** to require in branch protection
  (with "require branches to be up to date before merging"). `traceability` is
  advisory and stays out of the required set. Enabling the branch-protection
  rule is a manual repo-admin step.

The workflow uses no secrets and every `uses:` action is SHA-pinned, so fork-PR
runs are safe. The PR trigger has **no `paths-ignore`** (the workflow always
runs on PRs) so a `store/**`- or `LICENSE`-only PR still posts a `ci-required`
status instead of sitting pending forever under "require branches up to date".

### Compile/unit-test gate

The compile + unit-test gate is provided by the **`test`** job above via the
`matco/action-connectiq-tester` Docker action. Previously this gate was deferred
because unattended Garmin SDK download on a GitHub-hosted runner is infeasible
(EULA + manifest-gated, unpredictable zip URLs) and a self-hosted `connectiq`
runner was the only obvious option. The Docker action sidesteps that: the SDK
(`9.2.0`, incl. `edge1050`) and the "Run No Evil" `(:test)` framework are baked
into a container image, so the gate runs on stock `ubuntu-latest` with no SDK
download and no self-hosted runner.

The job is **advisory** (`continue-on-error: true`, and not in `ci-required`'s
`needs`) until a real GitHub run confirms the image builds `edge1050` and the
tests pass — so a broken or mismatched image cannot block merges. Once a green
run is observed, **promote it to required** by adding `test` to `ci-required`'s
`needs`. The SDK-dependent checks can still be run locally (see "Build" and
"Unit tests" above).

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
