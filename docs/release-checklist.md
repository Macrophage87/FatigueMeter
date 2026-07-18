# Pre-release verification checklist

**Status:** the durable home for the integration-only surfaces that a headless
pure `(:test)` cannot exercise (issue #81).

The CI `simulate` job runs the pure `(:test)` suite headlessly (`monkeydo -t`),
and `check_ciq_tests.py` requires it green with `errors == 0` — there is **no
advisory lane for a `(:test)`**, so a best-effort probe of the real
`Storage` / `Ant.GenericChannel` / `Dc` runtime cannot be a gate test (see the
#65 storage-quota resolution). The four surfaces below are therefore verified
**once per release** in the simulator and/or on real hardware, not in CI. Each is
already a fault-isolated `try/catch` surface; this checklist makes that coverage
auditable so #81 closes honestly rather than by hand-wave.

Every source module that owns one of these surfaces carries a one-line pointer
back to the matching item here.

## Checklist (tick before each store submission)

- [ ] **SessionStore — real `Storage` I/O + full-store behaviour** (`source/SessionStore.mc`)
  - History **round-trips** across an app restart: complete a ride, relaunch the
    field, confirm the prior Session Result is present (the real
    `Storage.getValue`/`setValue` path; the pure `sanitize`/`migrate`/`buildResult`
    validators are unit-tested).
  - **Full-store / quota**: fill Storage until `setValue` throws (manual sim run on
    the digest-pinned SDK 9.2.0 image, per #65), confirm `persist()`'s
    shed-until-fits keeps the newest ride and `lastWriteShed()` reports the trim;
    at the `MIN_HISTORY` floor confirm `lastWriteFailed()` and full-history-in-RAM.
    Record the observed quota-exception class in the `persist()` comment (#65).
  - **Save marker `KEY_LAST_OUTCOME` round-trip (#83)**: on a shed (trimmed)
    append, confirm `append()` writes `KEY_LAST_OUTCOME = "trimmed"`; on the next
    `load()` confirm it is read into `trimmedOnLoad` **and cleared** (so a
    subsequent restart shows no marker). Confirm the null-safe read does not crash
    on the common absent-key path.
  - **Retain `KEY_ACTIVE` on a full-store append (#83)**: after a storage-full
    `finalizeSession()` append (`saved == false`), confirm `KEY_ACTIVE` survives
    (the checkpoint is NOT cleared) and that the next start's `reconcileActive()`
    recovers the ride and `pendingSaveOutcome()` returns `SAVE_FAILED`. Confirm
    `KEY` (the persisted history) was genuinely left unchanged by the failed append.

- [ ] **FatigueMeterView — `onUpdate` / `dc.*` render** (`source/FatigueMeterView.mc`)
  - The glance screen paints without crashing across the sensor-availability
    matrix (power/HR/RR present in every combination and absent) — the §8.4
    grey-out behaviour. The pure geometry seams (`uncertaintyBand`,
    `defaultSnapshot`, `strapHrToken`) are unit-tested; the `dc.setColor` /
    `fillRectangle` / `drawText` calls are verified visually here.
  - **Save marker line-2 draw (#83)**: after a trimmed/recovered prior ride,
    confirm the footer line-2 marker (`SaveTrimmed` / `SaveRecovered`) paints; and
    that when an advisory tag already occupies line 2 the measured append drops the
    marker rather than clipping or evicting the tag (the `getTextWidthInPixels`
    non-masking guard). The pure `saveMarkerSeverity` fold is unit-tested.
  - **Render-first construction (#103)**: `initialize()` writes only the NODATA
    snapshot and defers the collaborator build + `registerSensors()` to a one-shot
    `ensureBuilt()` at the top of `computeInner()`. Verify the field **paints the
    §8.4 baseline immediately on add** (before any activity/compute) and never shows
    the stuck "IQ…" load badge; then that the first `compute()` builds the
    collaborators (`ready` flips true) and live tiles populate.
  - **First-compute-time (#103):** the first tick now runs the whole collaborator
    build + `registerSensors()` + a full `compute()` in one 1 Hz slice under the
    compute watchdog. Open the sim **Active Memory / timing** on the primary target
    and confirm tick 1 completes without a watchdog trip; if it runs long, that
    concentration — not an OOM — is the cause, and the build should be split further.
  - **On-device A/B for #90/#104 (hardware-only):** the sim can't reproduce the
    device-only ANT init path, so this runs on an Edge + paired ANT+ strap.
    1. **Build-identity precondition (do this FIRST, before reading any A/B result).**
       The A/B is meaningless unless the device is running *this* sideloaded build.
       Confirm: (i) the `.prg` was built with the **correct `-d` device target** for
       the unit under test; (ii) the device firmware is **≥ `minSdkVersion 4.1.0`**
       (Settings → About; a device below the manifest floor silently refuses to run
       the field and can masquerade as "still stuck"); (iii) the sideload replaced
       the old field (remove the pre-#103 copy first so you aren't reading a stale
       install). Only once all three hold does the A/B distinguish code from environment.
    2. **A/B:** confirm this build **paints the §8.4 baseline** where the pre-#103
       build stuck at "IQ…". A rendered baseline = render-first did its job (the hang,
       if any, is now relocated to the compute path, not the load path).
    3. **Fallback — still sticks at "IQ…" after step 1 passes:** the strand is *not*
       the deferred ANT open, so bisect the remaining first-frame surface. In
       `ensureBuilt()`, temporarily stub the collaborators back in one at a time and
       re-A/B to isolate the offender; the prime suspects are `FitLogger`'s field
       creation (`new FitLogger(self)` → `createField`) and the `SessionStore`
       Storage reads (`new SessionStore()` / `pendingSaveOutcome()`), which are the
       only remaining ctors that touch device-only runtime. Move whichever one stalls
       out of the first-frame path (defer or guard it) and re-verify.

- [ ] **FatigueMeterApp — lifecycle hooks** (`source/FatigueMeterApp.mc`)
  - `onStart` / `getInitialView` bring the field up; `onStop` finalizes the
    Session Result and releases the ANT+ channel (`view.finalizeSession()` +
    `view.releaseAnt()`) without crashing, with the FIT session fields written.

- [ ] **AntHrm — `Ant.GenericChannel` + clock integration** (`source/AntHrm.mc`)
  - With a real ANT+ RR-capable strap (Polar H10 class): RR acquisition drives
    DFA-α1; the HR staleness Metric transitions OK → STALE → UNAVAILABLE as the
    strap is removed; the watchdog re-opens the channel after a decode stall. The
    pure decode/reopen/staleness predicates (`rrDelta`, `shouldReopen`,
    `stallExpired`, `hrByteValid`) are unit-tested (#47/#11/#24).

- [ ] **Release image — data-field runtime peak-heap** (`source/FatigueMeterView.mc`, #91/#93)
  - The required `release-build` CI job compiles the non-`--unit-test` release
    `.prg` for all 8 devices and fails on the compiler's **static** data-field
    memory-budget error — but the compiler cannot see **runtime peak heap**
    (allocations during `compute()`/`onUpdate`: `toArray()` copies, the Kalman
    temp-matrix cascade, `DfaAlpha1.compute`'s `y = new [N]`, plus the ~25–40 KB
    of fixed construction ring buffers per #93). Open the simulator's **Active
    Memory** profiler on **edge1050** (and, per #93, on the tighter budgets —
    `edge540` / `edge840` / `edgeexplore2` / `fr955` / `fenix7x`), drive a ride, and
    confirm peak stays within each device's data-field cap. This is the one lever
    that can confirm/refute #90 root-cause #3 (load-time / runtime OOM).
  - **#93 AC-1 procedure (this is #93's sole closure gate — owner-run, CI can't
    automate it).** Reproducibly:
    1. **Per-device cap:** read each device's data-field memory limit from the SDK
       device definition (the *same* budget `monkeyc` applies in the `release-build`
       gate) — the caps are SDK-owned, not in-repo. Record it per device.
    2. **Fixture:** drive a **≥ 20-minute** ride (so `be20`'s 20-min best-effort
       window fully fills and its ~10 KB `toArray()` worst-case transient is reached)
       with power + HR present, and **inject HRV (RR) intervals via Simulation →
       Sensors** (BUILD.md "Run in the simulator") so the `rrBuf` / `DfaAlpha1.compute`
       (`y = new [N]`) path is exercised — RR arrives over ANT+, not FIT playback.
    3. **Read Active Memory** at four phases per device and tabulate vs the cap:
       **construction**, **first-compute**, **fill-phase** (the #95 lazy-grow ramp),
       **steady-state** (post-20-min).
    4. **Outcome:** if no device is within ~10 % of its cap → **close #93** as
       "profiled, not over budget" with the table attached. If a device shows
       pressure → apply an AC-2 fix (e.g. the #93 `toArray()` snapshot dedup already
       landed; then weigh remediation #4, window resize, only with a fatigue-output
       regression on this fixture — it is model-altering).

    One row **per device** (Step 1 records the cap per device, so don't group them):

    | device | cap (KB) | construction | first-compute | fill-phase | steady | headroom |
    |--------|----------|--------------|---------------|------------|--------|----------|
    | edge1050 (primary) |  |  |  |  |  |  |
    | edge1040 |  |  |  |  |  |  |
    | edge840 |  |  |  |  |  |  |
    | edge540 |  |  |  |  |  |  |
    | edgeexplore2 |  |  |  |  |  |  |
    | fr965 |  |  |  |  |  |  |
    | fr955 |  |  |  |  |  |  |
    | fenix7x |  |  |  |  |  |  |

    (All 8 manifest devices — the tight-budget concern centres on
    `edge540`/`edge840`/`edgeexplore2`/`fr955`/`fenix7x`, but profile edge1050 and
    edge1040 too so the primary target's headroom is on record.)

- [ ] **Store package — regenerate + sign `store/FatigueMeter.iq`** (#91)
  - CI's `release-build` builds the `.iq` with a **throwaway** key (packaging
    validation only, uploaded as an artifact) and the advisory `store-staleness`
    check warns when source outpaces the committed package. Neither can produce
    the store-submittable binary. At release, regenerate it from current `main`
    with the **account-bound developer key**:
    `monkeyc -e -r -f monkey.jungle -o store/FatigueMeter.iq -y <account_key>.der`,
    then commit it so the store package reflects shipped `main` (clears the
    `store-staleness` warning).

## Why these stay off the CI gate
`AntHrm extends Ant.GenericChannel`, `FatigueMeterView extends WatchUi.DataField`,
and `FatigueMeterApp extends Application.AppBase` are all **unconstructable in the
headless harness** (their `initialize()` calls the runtime base), so no
seam-injection `(:test)` can reach them; `SessionStore`'s quota path is
non-deterministic in the sim. Forcing any of these into the required `simulate`
gate would red it for every PR. (By contrast, `FitLogger` — a plain class with
constructor injection — and `DescriptiveStrings`' pure dispatch **are**
unit-tested; see #81 PR-1 / PR-2.)

The two release-image items above are a different case: the required `release-build`
job (#91) DOES compile the shipping artifact and hard-fails on the compiler's
**static** data-field budget error, but **runtime peak-heap** and **real-key store
signing** are structurally beyond a compiler / a secret-free CI run — hence they
live here as per-release manual steps rather than gates.
