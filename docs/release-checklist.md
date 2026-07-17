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
    `edge540` / `edge840` / `edgeexplore2` / `fr955`), drive a ride, and confirm
    peak stays within each device's data-field cap. This is the one lever that
    can confirm/refute #90 root-cause #3 (load-time / runtime OOM).

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
