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
request. It is split into a **required** gate and **advisory** jobs:

- **`compile`** — a matrix that builds the `--unit-test` binary (`-w`,
  warnings-as-errors) for **every** device id in `manifest.xml`
  (`edge1050`, `edge1040`, `edge840`, `edge540`, `edgeexplore2`, `fr965`,
  `fr955`, `fenix7x`). This is deterministic and catches the crash-class
  regressions this project has shipped (e.g. an illegal-API-for-datafield
  call) as well as test-compilation breakage. **Runs on
  `[self-hosted, connectiq]`** — unattended Garmin SDK download on a hosted
  runner is infeasible (EULA + manifest-gated, unpredictable zip URLs), so a
  pre-baked self-hosted runner (SDK + `edge1050` + Qt) is the only primary path.
- **`manifest-lint`** — `scripts/check_manifest_appid.sh`, a packaging check
  for the placeholder / store-reject app-id class the compile+test path
  cannot see.
- **`ci-required`** — the aggregator job that `needs` both of the above.
  **This is the single required status check** to require in branch
  protection, so adding/removing a matrix device does not churn the
  protected-check list.
- **`simulate`** (advisory, `continue-on-error`) — runs the 23 `(:test)`
  functions headlessly in the Qt simulator under `xvfb` and parses the output
  strictly (`scripts/run_ciq_tests.sh` + `scripts/check_ciq_tests.py`). Also on
  `[self-hosted, connectiq]`. Kept off the merge gate until the sim path is
  proven stable.
- **`traceability`** (advisory, `continue-on-error`) —
  `scripts/check_traceability.py` enforces "no physiological constant without
  a `docs/traceability.md` row."

The required check to enable in branch protection is **`ci-required`** (with
"require branches to be up to date before merging"). Enabling it is a manual
repo-admin step. The jobs use **no secrets** — the signing key is generated
fresh in-job and never committed — so fork PR runs are safe. The `compile` and
`simulate` jobs additionally carry a **fork guard**
(`github.event.pull_request.head.repo.fork == false`) so untrusted fork-PR code
never executes on the persistent self-hosted runner; preserve that invariant.

> **BLUNT STATUS — read before enabling branch protection.** `compile` and
> `simulate` run on `[self-hosted, connectiq]`. Until such a runner is
> **registered and online**, those jobs stay queued/pending and therefore
> **`ci-required` never goes green**. **Do NOT enable branch protection on
> `ci-required`** until (1) a `connectiq`-labelled runner (SDK + `edge1050` +
> Qt pre-baked) is online, and (2) at least one fully-green `ci-required` run
> has been observed. Enabling it before then blocks every merge on a check that
> cannot post a status.
>
> Still owed before protection (cannot be verified without network to
> Garmin/GitHub): that `CIQ_SDK_VERSION` (7.4.3) ships `edge1050`; that each
> pinned action SHA matches its claimed tag; and a **compile-break dry-run**
> proving a `monkeyc` error reddens the *required* check.
>
> The PR trigger has **no `paths-ignore`** (the workflow always runs on PRs) so
> a `store/**`- or `LICENSE`-only PR still posts a `ci-required` status instead
> of sitting pending forever under "require branches up to date".

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
