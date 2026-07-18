# Setting up CI for a Connect IQ (Monkey C) app on GitHub Actions

A practical, reusable guide to giving any Garmin Connect IQ app a **compile + unit-test gate** plus lightweight **lint gates** — running entirely on stock GitHub‑hosted `ubuntu-latest` runners, with **no self‑hosted runner** and **no Garmin SDK licensing hassle** in CI.

This is written to be copy‑pasted into a second app. Search for `<DEVICE_ID>` and the other `<…>` placeholders and fill them in.

---

## 1. What you get

| Check | Runs on | Blocks merge? | Catches |
|---|---|---|---|
| **`test`** — compile `--unit-test` + run `(:test)` functions | hosted `ubuntu-latest` (container) | yes, once promoted | crash‑class bugs (illegal API in a data field, syntax), and failing unit tests |
| **`manifest-lint`** — app‑id sanity | hosted `ubuntu-latest` | yes | placeholder / malformed application id → store rejection (a *packaging* bug that still compiles) |
| project‑specific lints (optional) | hosted `ubuntu-latest` | your call | whatever house rules you want to enforce |

The load‑bearing idea: **the Connect IQ SDK is delivered as a prebuilt Docker image**, so a hosted runner just pulls it. You never fight Garmin's SDK‑Manager download, EULA prompts, or the *separately‑downloaded* device definitions.

---

## 2. The core problem, and the insight

Compiling/running a Connect IQ app needs the Garmin SDK **and** the target device definition. On a hosted CI runner that's painful:

- The SDK ships via the **SDK Manager** (interactive, EULA‑gated); there's no clean, stable, unattended download URL.
- **Device definitions download separately** from the SDK zip (into `~/.Garmin/ConnectIQ/Devices`). Miss them and you get `ERROR: <device> is unknown`.
- The simulator is a **Qt GUI app** — it needs a virtual framebuffer (`xvfb`) to run headless.

**Insight:** don't install the SDK in CI at all. Use a **Docker image that already contains the SDK + devices + the test runner**, published to a container registry (GHCR). Hosted runners pull it in seconds. The community image [`ghcr.io/matco/connectiq-tester`](https://github.com/matco/connectiq-tester) (paired with the `matco/action-connectiq-tester` action) does exactly this: it bakes in the SDK (currently **9.2.0**, which includes recent devices like `edge1050`), the device bundle, and the "Run No Evil" `(:test)` framework.

> If you'd rather not depend on a community image, the same pattern works with **your own** image (a `Dockerfile` that installs the SDK once) pushed to your GHCR, or with a **self‑hosted runner** that has the SDK pre‑baked. See §9.

---

## 3. Prerequisites in the app repo

- A normal CIQ project: `manifest.xml`, a `monkey.jungle`, and `source/…` in Monkey C.
- Unit tests written as `(:test)`‑annotated functions using `Toybox.Test`, e.g.:
  ```monkeyc
  (:test)
  function testAdds(logger) { return 2 + 2 == 4; }
  ```
  These are pure/off‑device checks — no sensors — so they run fine headless.
- Know your **primary device id** (`edge1050`, `fenix7`, `fr965`, …). It must exist in the image's SDK (any modern 7.x+/9.x image covers current devices; `fenix7` is a safe fallback).

---

## 4. The workflow — two variants

Create `.github/workflows/ci.yml`. Pick the `test` job that matches your codebase.

### 4a. Common scaffolding (both variants)

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:            # do NOT add paths-ignore here if you require a check —
                           # a PR touching only ignored paths never posts the check
                           # and blocks forever under "require branches up to date"

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read           # least privilege; nothing here writes to the repo
```

### 4b. `test` job — Variant A: your app compiles clean under strict type‑checking

Simplest: use the action directly (it compiles + runs the tests inside its own image).

```yaml
jobs:
  test:
    name: Compile + unit tests
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@<PIN_SHA>            # pin actions/checkout by commit SHA
      - name: Connect IQ unit tests
        uses: matco/action-connectiq-tester@<PIN_SHA>   # e.g. 60fd2e8179994e075d3a58c6250f32aa20e2b37b (SDK 9.2.0)
        with:
          device: <DEVICE_ID>                       # e.g. edge1050
          # certificate: optional; a throwaway signing key is generated if omitted
```

⚠️ The action **hardcodes `monkeyc … -l 3`** (Strict type‑checking). If your Monkey C is fully type‑annotated, this is great. If it's **untyped** (very common), it fails with hundreds of `… is untyped` / `Cannot determine type` errors. Use Variant B instead. (See §5.)

### 4c. `test` job — Variant B: untyped codebase (run the image as a container, lower the type‑check level)

This reuses the same image and its build+xvfb+monkeydo+parse harness, but drops the type‑check level to one your code actually builds at.

```yaml
jobs:
  test:
    name: Compile + unit tests
    runs-on: ubuntu-latest
    timeout-minutes: 25
    container:
      # SDK + devices + test runner baked in — no Garmin download.
      # Pin by IMMUTABLE DIGEST (see §6 for how to resolve one).
      image: ghcr.io/matco/connectiq-tester@sha256:<DIGEST>
    steps:
      - uses: actions/checkout@<PIN_SHA>
      - name: Lower hardcoded type-check level (untyped Monkey C)
        run: |
          set -eux
          # The image's tester.sh runs 'monkeyc … -t -l 3' (Strict). Rewrite to
          # -l 1 (Gradual) — or -l 0 (Silent) if -l 1 still errors. Whitespace-robust.
          test -f /connectiq/bin/tester.sh
          sed -i -E 's/-l[[:space:]]*3/-l 1/g' /connectiq/bin/tester.sh
          grep -n 'monkeyc' /connectiq/bin/tester.sh || true
      - name: Run unit tests
        # tester.sh args are (DEVICE_ID, [CERTIFICATE_PATH]); it compiles the
        # monkey.jungle in the current working directory (= the checkout).
        run: bash /connectiq/bin/tester.sh <DEVICE_ID>
```

> Notes that saved us real time:
> - The image's `CONNECT_IQ_HOME=/connectiq`, so `tester.sh` lives at `/connectiq/bin/tester.sh`.
> - `tester.sh` takes **device first**, an optional cert second, and compiles the jungle in `cwd` — it does **not** take a path argument.
> - A **fast (~6 s) failure = a compile error**, not a long test run. Read the log; the errors are precise.

### 4d. Optional: manifest app‑id lint (broadly useful)

Catches the "placeholder / malformed application id → store rejection" class, which compiles and passes tests, so the `test` job can't see it.

`scripts/check_manifest_appid.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
id="$(grep -oiE 'id="[0-9a-f]{32}"' manifest.xml | head -1 | sed -E 's/.*"([0-9a-fA-F]{32})".*/\1/')"
[ -n "$id" ] || { echo "::error::application id missing or not 32-hex"; exit 1; }
case "$id" in
  00000000000000000000000000000000) echo "::error::placeholder (all-zero) app id"; exit 1;;
esac
printf '%s' "$id" | grep -qiE '^(.)\1{31}$' && { echo "::error::placeholder-like app id"; exit 1; }
echo "manifest app id OK: $id"
```
Job:
```yaml
  manifest-lint:
    name: Manifest app-id lint
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@<PIN_SHA>
      - run: ./scripts/check_manifest_appid.sh
```

> Project‑specific lints (e.g. "every constant must have a documentation row") slot in as more jobs the same way. Keep them **advisory** (`continue-on-error: true`) until their matcher is proven, then promote.

### 4e. The required‑check aggregator

Require **one stable check name** in branch protection, so adding/removing jobs later doesn't churn the protected list.

```yaml
  ci-required:
    name: ci-required
    runs-on: ubuntu-latest
    timeout-minutes: 5
    needs: [ manifest-lint ]      # add `test` here AFTER it's proven green (§7)
    steps:
      - run: echo "required checks passed"
```

---

## 5. The type‑check‑level gotcha (read this)

Monkey C type checking is a compiler flag, `-l 0..3`:

| Level | Name | Untyped code |
|---|---|---|
| `-l 0` | Silent | always builds |
| `-l 1` | Gradual | builds (only checks where types *are* declared) |
| `-l 2` | Informative | warnings |
| `-l 3` | Strict | **errors on any untyped symbol** |

Most hand‑written CIQ apps are **not** fully annotated, so they build fine at the project's default level but **fail at `-l 3`**. The `matco` action forces `-l 3` with no override, which is why Variant B patches it down with `sed`.

- Symbol‑resolution errors (e.g. `Cannot find symbol ':FOO' on type 'self'`) are **not** type‑check‑level dependent — they fail at *any* `-l`. Those are real bugs (e.g. a `static` method referencing a class `const` unqualified — fix by qualifying: `ClassName.FOO`).
- If `-l 1` still drowns you in `… is untyped`, drop to `-l 0`. You still get the real compile gate (syntax + illegal‑API‑for‑data‑field), which is the crash‑class you care about.

---

## 6. Pinning & supply‑chain

- **Pin every `uses:` action by full commit SHA**, not a tag (tags move; a stale `v1` may be years old while `master` is current).
- **Pin the container image by immutable digest** (`@sha256:…`), not `:latest`.

Resolve a GHCR digest without a Docker daemon (anonymous pull token):
```bash
IMAGE=matco/connectiq-tester; TAG=latest
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:$IMAGE:pull" | sed -E 's/.*"token":"([^"]+)".*/\1/')
curl -sI -H "Authorization: Bearer $TOKEN" \
     -H "Accept: application/vnd.oci.image.index.v1+json" \
     "https://ghcr.io/v2/$IMAGE/manifests/$TAG" | grep -i docker-content-digest
```
Record which tag the digest corresponds to in a YAML comment so future‑you can audit it.

---

## 7. Advisory‑first → promote‑to‑required (recommended rollout)

New CI infra is flaky until proven. Bring the `test` job up as **advisory**, watch one real run, then promote:

1. Add `test` with `continue-on-error: true` and **leave it out** of `ci-required.needs`. Merges aren't blocked while you shake it out.
2. Open a PR and let it run. Inspect the **job** result, not just the run — a `continue-on-error` job can be red while the overall run shows green.
3. Once you see a genuinely green `test` job: remove `continue-on-error: true` and add `test` to `ci-required.needs`.
4. Prove the gate *bites*: on a scratch branch, introduce a one‑line compile error and confirm `test` (and thus `ci-required`) goes red; revert.

---

## 8. Enforcing it — branch protection (manual admin step)

A workflow can't protect its own branch; a repo admin does this once (not automatable from the workflow, and it needs admin scope):

```bash
gh api -X PUT repos/<OWNER>/<REPO>/branches/main/protection \
  -f 'required_status_checks[strict]=true' \
  -f 'required_status_checks[contexts][]=ci-required' \
  -f 'enforce_admins=true' \
  -f 'required_pull_request_reviews[required_approving_review_count]=1' \
  -f 'restrictions='
```
Require **`ci-required`** and "require branches up to date before merging." Leave advisory jobs out of the required set.

**Fork safety:** the jobs above use **no secrets** (the signing key is generated in‑job, throwaway). That makes `pull_request` runs from forks safe. Keep it that way — don't add repo secrets to these jobs; if you ever need to sign with a real store key, do it in a *separate* release workflow.

---

## 9. Adapting to another app — checklist

1. Copy `.github/workflows/ci.yml` and `scripts/check_manifest_appid.sh` into the new repo.
2. Set **`<DEVICE_ID>`** to that app's primary device (fallback `fenix7`).
3. Pick the `test` variant:
   - **type‑annotated app →** Variant A (the action). Simplest.
   - **untyped app →** Variant B (container + `sed` to `-l 1`, or `-l 0`).
4. Re‑resolve and pin the **action SHA** and **image digest** (§6).
5. Confirm the app builds from the repo root (its `monkey.jungle` is at the root, which is where `tester.sh` compiles).
6. Roll out advisory‑first, then promote (§7), then enable branch protection (§8).
7. Keep only the lints that make sense for that app (drop project‑specific ones).

---

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR: <device> is unknown` | device not in the image's SDK | use a newer image, or switch `<DEVICE_ID>` to one it has (`fenix7`) |
| Wall of `… is untyped` / `Cannot determine type` | Strict type‑check (`-l 3`) on untyped code | Variant B; `sed` to `-l 1`, then `-l 0` if needed |
| `Cannot find symbol ':FOO' on type 'self'` | real bug: `static` method reads a class `const`/member unqualified | qualify it (`ClassName.FOO`) — not a CI problem |
| Test step fails in ~6 seconds | it's a **compile** error, not a test failure | read the log; the compiler prints exact file:line |
| Overall run green but tests didn't really pass | `test` is `continue-on-error` | inspect the **job/step** conclusion, not the run |
| `ci-required` stuck "pending" forever on some PRs | `paths-ignore` on the `pull_request` trigger skipped the workflow | drop `paths-ignore` from the PR trigger (keep it on `push` only) |
| Simulator hangs / times out | Qt/xvfb startup race (only relevant if you run your own sim harness) | add a bounded readiness probe + `timeout-minutes`; keep the sim job advisory until stable |

---

## 11. Why not a self‑hosted runner / your own image?

Both are valid and sometimes better:

- **Your own GHCR image**: fork the idea of `matco/connectiq-tester` — a `Dockerfile` that installs the SDK + device bundle once, pushed to your registry. Full control, no third‑party trust, but you maintain the image and the SDK‑download step inside it.
- **Self‑hosted runner** with the SDK pre‑baked: needed only if you can't use a hosted‑runner‑pullable image (e.g. air‑gapped, or you want the real GUI simulator). Costs a persistent host; on a public repo add a fork guard (`if: github.event.pull_request.head.repo.fork == false`) so untrusted PR code never runs on it. Note a 1 GB free‑tier VM is marginal for the JVM compiler + Qt simulator — give it swap and expect slowness.

For most apps, the **hosted‑runner + prebuilt image** path in §4 is the least‑effort way to a real gate.

---

## 12. Boot-smoke gate (#124) — headless DataField boot, advisory-first

The `simulate` gate runs the pure `(:test)` suite (`monkeydo … -t`), which cannot
construct `FatigueMeterView extends WatchUi.DataField` — so it never exercises the
real DataField *lifecycle*. The **boot-smoke** job (`.github/workflows/ci.yml`)
boots the real compiled field with `monkeydo` **WITHOUT `-t`**, so the sim
free-runs `compute()` at ~1 Hz, and hands the tick stream + any `CIQ_LOG.YML` to a
fail-closed parser. It targets the crash classes the sim *does* raise — the
#109/#114 `Symbol Not Found` and the render-first `ensureBuilt()`-on-tick-1
recovery crash. It is **not** #116 (the sim does not enforce `createField`'s
init-only window — that stays `check_init_contract.py` R1/R2 + the on-device step).

### Pieces
- **`source-bootsmoke-stub/BootSmoke.mc`** (shipping no-op) vs **`source-bootsmoke/BootSmoke.mc`**
  (emits `FM_TICK <n>`). `compute()` calls `BootSmoke.tick(tick)` unconditionally;
  `monkey.jungle` selects the **stub** (so shipping binaries carry no `FM_TICK`
  literal **by construction**), `monkey.bootsmoke.jungle` selects the emitter.
- **`scripts/run_boot_smoke.sh`** — standalone runner (duplicates the `run_ciq_tests.sh`
  lifecycle; see drift note below). Drops `-t`; treats `timeout` rc **124/137 as the
  expected healthy steady state** (a free-run is always SIGKILLed) and a clean early
  exit (rc 0) as the anomaly; copies `CIQ_LOG.YML` next to the stdout log.
- **`scripts/check_boot_smoke.py`** — fail-closed verdict: PASS iff `FM_TICK` count ≥ K(2)
  **and** ≥ the liveness floor **and** rc ∈ {124,137} **and** no crash marker on
  **either** channel. Empty/missing log ⇒ FAIL.
- **`scripts/check_boot_residue.sh`** — proves the `FM_TICK` literal is absent from
  shipping source **and** the built `-d` `.prg` (scan the flat `.prg`, never the `-e`
  `.iq` ZIP, which can false-clean).

### AC-1 go/no-go (why it's advisory first)
All spike data was **Windows SDK 9.2**; the Linux behaviour is unproven. The job is
`continue-on-error` and **out of `ci-required.needs`**, and it dumps the three facts
a human needs before promotion: **(a)** does a no-`-t` boot free-run `compute()` ≥ K
ticks on the Linux image; **(b)** does the sim write `CIQ_LOG.YML` on Linux (the
runner only captured stdout before #124); **(c)** a **per-class** map of which
channel (stdout / `CIQ_LOG.YML`) surfaces each targeted class. Only after these are
confirmed — and the **liveness floor calibrated** from the measured tick-rate, and an
**AC-5 ≥10-run RED/GREEN** differential demonstrated (inject a real #109-class crash →
RED, `main` → GREEN, zero flakes) — is `boot-smoke` added to `ci-required.needs`.

### Hard-stop rules (no fake-green)
- **If a no-`-t` boot does NOT free-run `compute()` on Linux**, #124 is a **documented
  dead-end**: leave the job advisory/failing, wire nothing. Do not force a gate.
- **If a targeted class surfaces on NEITHER channel on Linux**, that class is silently
  undetectable by this gate — it must **dead-end (RED / not-wired)**, never pass.
- **Lifecycle drift risk (accepted):** `run_boot_smoke.sh` *duplicates* the
  `run_ciq_tests.sh` sim lifecycle rather than refactoring the required script. A
  future fix to HOME/device-def resolution or the readiness probe there will **not**
  propagate here and must be mirrored. A shared-helper refactor is a separate,
  independently-reviewed follow-up once boot-smoke is promoted.
