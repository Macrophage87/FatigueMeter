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

- [ ] **FatigueMeterView — `onUpdate` / `dc.*` render** (`source/FatigueMeterView.mc`)
  - The glance screen paints without crashing across the sensor-availability
    matrix (power/HR/RR present in every combination and absent) — the §8.4
    grey-out behaviour. The pure geometry seams (`uncertaintyBand`,
    `defaultSnapshot`, `strapHrToken`) are unit-tested; the `dc.setColor` /
    `fillRectangle` / `drawText` calls are verified visually here.

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

## Why these stay off the CI gate
`AntHrm extends Ant.GenericChannel`, `FatigueMeterView extends WatchUi.DataField`,
and `FatigueMeterApp extends Application.AppBase` are all **unconstructable in the
headless harness** (their `initialize()` calls the runtime base), so no
seam-injection `(:test)` can reach them; `SessionStore`'s quota path is
non-deterministic in the sim. Forcing any of these into the required `simulate`
gate would red it for every PR. (By contrast, `FitLogger` — a plain class with
constructor injection — and `DescriptiveStrings`' pure dispatch **are**
unit-tested; see #81 PR-1 / PR-2.)
