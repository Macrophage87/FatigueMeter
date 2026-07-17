# Building & sideloading FatigueMeter (Edge 1050)

FatigueMeter is a Garmin **Connect IQ data field** written in Monkey C. It targets
the **Edge 1050** primarily and is portable to other power-capable colour Edge /
Forerunner devices (see `manifest.xml`).

## Prerequisites

- **Connect IQ SDK 9.2.0** — the toolchain the required CI gate builds and tests
  with (`ghcr.io/matco/connectiq-tester` `v2.8.0`, digest-pinned in
  `.github/workflows/ci.yml`); use it for reproducible builds. Separately,
  `manifest.xml` sets `minSdkVersion=4.1.0` — the runtime-compatibility floor for
  target devices, which is distinct from the build SDK and does not change.
  Install via the [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/);
  confirm your local SDK with `monkeyc --version`.
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
`source/PureFunctionTests.mc` (NP, decoupling, W′bal, TSS, TRIMP, the CTL/ATL EWMA
helper — retained pure math even though the cross-ride ledger was removed in
Rev 5, DFA-α1, the Kalman predict/update, the α1↔F coupling, and the
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
jobs need no Connect IQ SDK at all; the compile/unit-test gate gets the SDK by
running a pre-built Docker image as the job container (see `test` below).

- **`manifest-lint`** — `scripts/check_manifest_appid.sh`, a packaging check
  that guards the historical placeholder / store-reject app-id class (a bad
  32-hex id, an all-zero or all-same-character id). A compile+test path cannot
  see this — a bad id still compiles and still passes tests — which is exactly
  why this cheap runner-free check exists.
- **`test`** (**required**, #42) — the **compile gate**. It compiles the
  `--unit-test` build for **every device in `manifest.xml`** (all 8: `edge1050`,
  `edge1040`, `edge840`, `edge540`, `edgeexplore2`, `fr965`, `fr955`, `fenix7x`)
  in one shell loop, so the SDK image is pulled once rather than per device. It
  runs the pre-built `ghcr.io/matco/connectiq-tester` Docker image **as the job
  `container`** (digest-pinned; `v2.8.0` = SDK `9.2.0`), which ships the Connect
  IQ SDK and the "Run No Evil" `(:test)` framework — **no SDK download, no
  self-hosted runner**. The job invokes `monkeyc` **directly** (the exact
  `--unit-test` command from "Unit tests" above, plus `-w`) with **no `-l`
  flag** — it deliberately bypasses the image's `tester.sh` wrapper, which
  hardcodes `-l 3` (type-check level = **Strict**) and aborts with hundreds of
  "… is untyped" errors on this **intentionally untyped** codebase; passing no
  `-l` matches the project's own build. A `--unit-test` compile failure on any
  device blocks merges.
- **`simulate`** (**required**, #42) — the **run gate**. It compiles `edge1050`
  `--unit-test` (the `(:test)` suite is pure / device-independent; `test` already
  covers the 8-device compile) and **actually runs the tests headlessly** via
  `scripts/run_ciq_tests.sh` (`xvfb` + `monkeydo -t` with a readiness probe and a
  hard timeout — deliberately not the image's `tester.sh`, which hangs on
  failure), asserting `ran == passed == expected`, `failed == 0`, `errors == 0`.
  A failing or non-running test blocks merges.
- **`traceability`** (advisory, `continue-on-error`) —
  `scripts/check_traceability.py` enforces "no physiological constant in
  `source/Constants.mc` without a `docs/traceability.md` row." It is advisory
  until the matcher is hardened; it can be promoted into the required set later
  (add it to `ci-required`'s `needs`) once it no longer produces false
  positives.
- **`ci-required`** — the aggregator job that `needs: [manifest-lint, test,
  simulate]`. **This is the single stable required status check** to require in
  branch protection (with "require branches to be up to date before merging"), so
  a failure in any of the three fails it. Only `traceability` stays advisory,
  out of the required set. Enabling the branch-protection rule is a manual
  repo-admin step.

The workflow uses no secrets and every `uses:` action is SHA-pinned, so fork-PR
runs are safe. The PR trigger has **no `paths-ignore`** (the workflow always
runs on PRs) so a `store/**`- or `LICENSE`-only PR still posts a `ci-required`
status instead of sitting pending forever under "require branches up to date".

### Compile + run gates

Two **required** SDK-backed jobs cover the Monkey C surface: **`test`** compiles
the `--unit-test` build for all 8 manifest devices, and **`simulate`** runs the
`(:test)` suite headlessly on `edge1050`. Both run the
`ghcr.io/matco/connectiq-tester` Docker image **as the job container**.

Unattended Garmin SDK download on a GitHub-hosted runner is infeasible (EULA +
manifest-gated, unpredictable zip URLs), and a self-hosted `connectiq` runner was
the only obvious alternative; the pre-built image sidesteps both — the SDK
(`9.2.0`, incl. all 8 device defs) and the "Run No Evil" `(:test)` framework are
baked in, so the gates run on stock `ubuntu-latest` with no SDK download and no
self-hosted runner.

Each job invokes `monkeyc` / `monkeydo` **directly** and uses the image only for
the SDK it bundles — it does **not** use the `matco/action-connectiq-tester`
wrapper or the image's `tester.sh` entrypoint. Both of those hardcode
`monkeyc … -l 3` (type-check level = **Strict**), which is not exposed as an
input/env and aborts on this **untyped** Monkey C codebase with hundreds of
"… is untyped" errors; the jobs instead compile with **no `-l` flag** (matching
the project's own build) and run the tests via `scripts/run_ciq_tests.sh` (which
fails fast on a hard timeout rather than hanging the way `tester.sh` does). The
image is **pinned by digest** for supply-chain safety; the digest currently
corresponds to `v2.8.0` (SDK 9.2.0).

Both jobs are **required** — in `ci-required`'s `needs`, no `continue-on-error`
(#42): a `--unit-test` compile failure on any device, or a failing / non-running
test, blocks merges. The SDK-dependent checks can also be run locally (see
"Build" and "Unit tests" above).

## Sideload to an Edge 1050

1. Build `bin/FatigueMeter.prg` as above.
2. Connect the Edge over USB (mass-storage mode).
3. Copy `bin/FatigueMeter.prg` into `GARMIN/Apps/` on the device.
4. Eject, then add **FatigueMeter** as a data field to a full-screen data page
   (it is designed to occupy the whole screen — white paper §8.1).
5. Configure settings (FTP/CP/W′, HR max/rest, sex, band cutoffs,
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
