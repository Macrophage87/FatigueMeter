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

This non-`--unit-test` build is the one that ships and the only one that surfaces
the **data-field memory-budget error**: `monkeyc` applies the target's data-field
memory limit for `type=datafield` and fails the build when the static image (code
+ globals) exceeds it. The required `release-build` CI gate (below) runs exactly
this command for all 8 manifest devices, so an over-budget or non-loading release
image can't ship green. (Runtime peak-heap is a separate concern — measured in the
simulator's Active-Memory profiler, a release-checklist step, not at compile.)

## Package for the Connect IQ store (`.iq`)

The store deliverable is a multi-device `.iq` package produced by `monkeyc -e`
(export):

```sh
# validation build (throwaway key) — proves it packages across all devices
monkeyc -e -f monkey.jungle -o store/FatigueMeter.iq -y developer_key.der

# store-submittable build — sign with your account-bound developer key + --release
monkeyc -e -r -f monkey.jungle -o store/FatigueMeter.iq -y <account_key>.der
```

The `release-build` CI gate builds the validation form every run (throwaway key)
and uploads it as an artifact; the **store-submittable** signed package must be
regenerated from current `main` at release time with the real key (CI cannot — it
has no account-bound key and no write access). See `docs/release-checklist.md`.

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
- **`release-build`** (**required**, #91) — the **release-artifact + memory
  gate**. It compiles the **non-`--unit-test`** release `.prg` (the shipping
  build, the exact "Build" command above plus `-w`) for **all 8 manifest
  devices**, and packages the store `.iq` (`monkeyc -e`) — neither of which the
  `--unit-test`-only `test`/`simulate` jobs ever produce. A release compile
  failure or a data-field memory-budget error (both = a non-zero `monkeyc` exit)
  on any device blocks merges. It does **not** fail on warnings: this codebase is
  intentionally untyped, so `monkeyc` emits benign "container type" notes broadly
  (the same reason CI avoids `-l 3`); an illegal-datafield-API regression is a
  compile/permission *error* (non-zero exit), so it is still gated, while warnings
  are logged for diagnostics only. Per-device `.prg` sizes, the `.iq`, and a
  `release-sizes.txt` are
  uploaded as an artifact so budget pressure is visible over time (feeds #93). It
  catches the #90 class of a **non-loading / static-over-budget** release image;
  runtime peak-heap OOM is out of a compiler's reach and stays a release-checklist
  Active-Memory step.
- **`store-staleness`** (advisory, `continue-on-error`) —
  `scripts/check_store_fresh.sh` emits a GitHub `::warning::` when tracked source
  (`source/`, `resources/`, `manifest.xml`, `monkey.jungle`) was committed after
  the packaged `store/FatigueMeter.iq`, a reminder to regenerate + sign the store
  package at release. Advisory by design: the signed `.iq` is a release deliverable
  regenerated with the account-bound key (CI can't rebuild it), so staleness on a
  source PR is expected, not a merge blocker.
- **`traceability`** (advisory, `continue-on-error`) —
  `scripts/check_traceability.py` enforces "no physiological constant in
  `source/Constants.mc` without a `docs/traceability.md` row." It is advisory
  until the matcher is hardened; it can be promoted into the required set later
  (add it to `ci-required`'s `needs`) once it no longer produces false
  positives.
- **`ci-required`** — the aggregator job that `needs: [manifest-lint, test,
  simulate, release-build]`. **This is the single stable required status check**
  to require in branch protection (with "require branches to be up to date before
  merging"), so a failure in any of the four fails it. `traceability` and
  `store-staleness` stay advisory, out of the required set. Enabling the
  branch-protection rule is a manual repo-admin step. (The `ci-required` context
  name is unchanged, so adding `release-build` needs no branch-protection
  reconfiguration.)

The workflow uses no secrets and every `uses:` action is SHA-pinned, so fork-PR
runs are safe. The PR trigger has **no `paths-ignore`** (the workflow always
runs on PRs) so a `store/**`- or `LICENSE`-only PR still posts a `ci-required`
status instead of sitting pending forever under "require branches up to date".

### Compile + run gates

Three **required** SDK-backed jobs cover the Monkey C surface: **`test`** compiles
the `--unit-test` build for all 8 manifest devices, **`simulate`** runs the
`(:test)` suite headlessly on `edge1050`, and **`release-build`** compiles the
**non-`--unit-test`** release image (the shipping build, with its data-field
memory-budget check) for all 8 devices and packages the store `.iq`. All three run
the `ghcr.io/matco/connectiq-tester` Docker image **as the job container**.

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

These jobs are **required** — in `ci-required`'s `needs`, no `continue-on-error`
(#42, #91): a `--unit-test` compile failure on any device, a failing / non-running
test, or a release-build compile / memory-budget failure blocks merges.
The SDK-dependent checks can also be run locally (see "Build", "Package for the
Connect IQ store", and "Unit tests" above).

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
