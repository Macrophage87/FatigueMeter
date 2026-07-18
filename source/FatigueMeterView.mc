using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.System;
using Toybox.Time;

//! The single glance screen + the 1 Hz compute loop (white paper §8.1).
//!
//! compute() keeps the 1 Hz path light and NEVER throws: every calculator is
//! fault-isolated and returns a Signals.Metric, so a missing sensor greys only
//! its own tile (§8.4). The DFA-α1 recompute is budgeted to every 5 s inside the
//! primitives. onUpdate() renders each tile from its own availability.
//! Integration coverage (#81): the onUpdate / dc.* render path is verified
//! per-release in the simulator/on hardware — see docs/release-checklist.md (the
//! pure geometry seams uncertaintyBand / defaultSnapshot / strapHrToken ARE tested).
class FatigueMeterView extends WatchUi.DataField {

    hidden var cfg;
    hidden var prims;
    hidden var filter;
    hidden var effort;
    hidden var ledger;
    hidden var fit;
    hidden var sessions;
    hidden var ant;            // ANT+ HRM RR reader (null if Ant unavailable)

    hidden var tick;           // ride seconds
    hidden var prevTimerMs;    // last activity-timer reading (ms) for real-dt derivation (#22)
    hidden var seeded;
    hidden var finalized;
    hidden var sessionToken;        // stable per-ride id for reconcile dedup (#17)
    hidden var lastCheckpointTick;  // tick of the last durable summary checkpoint (#17)

    // ride-summary accumulators
    hidden var peakAfi;
    hidden var lastFreshMatchCount;
    hidden var ready;          // true only after every collaborator built OK (§8.4, #13)
    hidden var builtAttempted; // #103: ensureBuilt() has run once (render-first deferral)

    // display snapshot (written by compute, read by onUpdate)
    hidden var dStatus;
    hidden var dAfi;
    hidden var dAfiUnc;
    hidden var dDecoup;
    hidden var dAlpha1;
    hidden var dArtifact;
    hidden var dKjw;
    hidden var dKjTotal;
    hidden var dWmatches;
    hidden var dBest1;
    hidden var dBest5;
    hidden var dBest20;
    hidden var dNumericUnlocked;
    hidden var dCalibrated;
    hidden var dSourceSwitched;
    hidden var dPriorDominated;
    hidden var dRedKind;
    hidden var dPowerAvail;
    hidden var dStationary;
    hidden var dWriteFailed;   // last session append could not persist (#18); footer surfacing tracked with #28
    hidden var dStrapHr;       // strap-HR staleness Metric — DISPLAY ONLY (#57); never fed to the filter/math
    hidden var computeFailStreak;   // consecutive compute() failures; drives the degraded footer marker (#28)
    hidden var dSaveOutcome;        // next-start persistence marker severity (#83); DescriptiveStrings.SAVE_*

    //! Conservative NODATA defaults written at construction BEFORE the guarded
    //! collaborator build (§8.4, #13): if that build throws, the field is left on
    //! this safe, HONEST snapshot -- numeric AFI LOCKED, "uncalibrated" tag, NODATA
    //! status, max uncertainty -- so a construction fault never over-claims. Static
    //! + pure so these values can be unit-tested (a DataField subclass cannot be
    //! instantiated off-device, but a static helper can).
    static function defaultSnapshot() {
        return {
            :status          => DescriptiveStrings.STATUS_NODATA,
            :afi             => null,
            :afiUnc          => 100.0,   // max uncertainty
            :numericUnlocked => false,   // numeric AFI stays LOCKED until a clean build
            :calibrated      => false,   // show the "uncalibrated" tag until proven
            :priorDominated  => true,
            :powerAvail      => false,
            :stationary      => false
        };
    }

    //! Clamp the post-pilot uncertainty band to the status bar [pad, pad+barW]
    //! (#30). The raw band is nowX ± uncW, which can start at a negative x
    //! (nowX - uncW < pad) or overflow the bar's right edge (nowX + uncW >
    //! pad + barW) — exactly when uncertainty is highest, painting the band across
    //! the whole dial. Returns [x, width] with width >= 0. Static + pure so the
    //! geometry is unit-testable (like defaultSnapshot on this class).
    static function uncertaintyBand(nowX, uncW, pad, barW) {
        var x0 = nowX - uncW;
        var x1 = nowX + uncW;
        if (x0 < pad)        { x0 = pad; }
        if (x1 > pad + barW) { x1 = pad + barW; }
        var wBand = x1 - x0;
        if (wBand < 0) { wBand = 0; }
        return [x0, wBand];
    }

    //! Diagnostic strap-HR token for the footer (display-only, #57). Pure so the
    //! availability -> text mapping is (:test)-drivable. OK -> "strap 142";
    //! STALE -> "strap 140 stale"; UNAVAILABLE / null / no-value -> "strap --"
    //! (the codebase's "no <sensor>" grey-out convention). Never touches the math.
    static function strapHrToken(m) {
        if (m == null || m.availability == Signals.AVAIL_UNAVAILABLE || m.value == null) {
            return "strap --";
        }
        var v = m.value.format("%d");
        return (m.availability == Signals.AVAIL_STALE) ? ("strap " + v + " stale")
                                                       : ("strap " + v);
    }

    //! Pure: next consecutive compute()-failure streak (#28). A good tick
    //! (threw == false) resets to 0; a throw increments — so only a PERSISTENT
    //! per-tick fault latches the degraded marker, never a one-off frame.
    static function nextFailStreak(prev, threw) { return threw ? (prev + 1) : 0; }

    //! Pure: does a persistent compute-stall warrant the footer degraded marker?
    //! True once the streak reaches the threshold (#28).
    static function shouldShowDegraded(streak, threshold) { return streak >= threshold; }

    function initialize() {
        DataField.initialize();
        ready = false;

        // Renderable NODATA snapshot FIRST: onUpdate()/compute() must have a
        // complete, safe state to read even if the guarded construction below
        // fails partway (§8.4 -- a construction fault greys the field, it must NOT
        // brick it to the Connect IQ banner). Defaults are conservative: numeric
        // AFI locked and the "uncalibrated" tag, until a clean build proves otherwise.
        tick = 0;
        prevTimerMs = null;
        seeded = false;
        finalized = false;
        sessionToken = Time.now().value();   // stable per-ride id (ride-start epoch s) for reconcile dedup (#17)
        lastCheckpointTick = 0;
        dWriteFailed = false;
        computeFailStreak = 0;   // #28: no compute failures yet
        dSaveOutcome = DescriptiveStrings.SAVE_OK;   // #83: nothing to show until the store reports one
        peakAfi = 0.0;
        lastFreshMatchCount = 0;

        var snap = defaultSnapshot();
        dStatus = { :status => snap[:status], :redKind => "none",
                    :advisoryActive => false, :alpha1Gated => true, :decoupOnly => true };
        dAfi = snap[:afi]; dAfiUnc = snap[:afiUnc];
        dDecoup = Signals.Metric.unavailable("--");
        dAlpha1 = Signals.Metric.unavailable("no RR");
        dStrapHr = Signals.Metric.unavailable("no HR");   // #57 display-only default
        dArtifact = null;
        dKjw = 0.0; dKjTotal = 0.0; dWmatches = 0;
        dBest1 = 0.0; dBest5 = 0.0; dBest20 = 0.0;
        dNumericUnlocked = snap[:numericUnlocked];   // conservative: numeric AFI LOCKED
        dCalibrated = snap[:calibrated];             // conservative: "uncalibrated" tag
        dSourceSwitched = false;
        dPriorDominated = snap[:priorDominated];
        dRedKind = "none";
        dPowerAvail = snap[:powerAvail];
        dStationary = snap[:stationary];

        // FitContributor field creation is INIT-ONLY (Connect IQ contract):
        // FitContributor.createField() is legal ONLY during a DataField's
        // initialize(). #116 regression -- #103/#108 render-first deferred
        // `new FitLogger(self)` (whose ctor calls createField via
        // createRecordFields/createSessionFields -> mkRec/mkSes) into ensureBuilt()
        // on the COMPUTE path, so createField ran on tick 1 (out of phase) and raised
        // an UNCATCHABLE `System Error: 'Failed invoking '` that bypasses every §8.4
        // try/catch (mkRec's, FitLogger.initialize()'s, ensureBuilt()'s, AND
        // compute()'s top-level guard) and bricks the field one frame after the NODATA
        // baseline paints. So FitLogger is constructed EAGERLY here -- BOTH its 8
        // record fields and 6 session fields register inside the legal init window.
        // Safe to run eager: FitLogger does NO Storage and NO ANT I/O (only createField
        // + println), so it is NOT the #90/#104 load-HANG suspect (that is the ANT
        // GenericChannel.open() in registerSensors(), which stays deferred). And
        // FitLogger.initialize() is TOTAL -- every createField is double-guarded and
        // `ok` derives from what actually registered -- so this never throws out of
        // initialize(). Runs after DataField.initialize() above, so `self` is a valid
        // DataField. See docs/release-checklist.md and #115 (init-contract invariant).
        fit = new FitLogger(self);

        // Render-first (#103): DEFER the remaining guarded collaborator build +
        // registerSensors() out of initialize() into a one-shot ensureBuilt() at the
        // top of computeInner(). initialize() now returns having written ONLY the
        // NODATA snapshot above (plus the eager FitLogger fields), so the view ALWAYS
        // constructs and onUpdate paints the §8.4 baseline BEFORE any DEFERRED
        // collaborator ctor, Storage read, or ANT GenericChannel.open() runs
        // (FitContributor field creation is the one ctor that MUST stay eager, above).
        // A construction FAULT (a deferred ctor that throws) is fully absorbed --
        // ensureBuilt()'s try/catch leaves `ready` false and the field stays on the
        // rendered NODATA baseline. A device-only init HANG (a synchronous
        // never-returns, the ANT open is the #90/#104 suspect; AC-1 refuted a
        // construction OOM) is NOT cured, only RELOCATED: it moves off the load path
        // onto the compute path, so the field paints ONE §8.4 baseline frame first and
        // THEN the compute thread freezes on that tick -- a state the 1 Hz compute
        // watchdog can kill, unlike the pre-#103 load-time strand at the "IQ..." badge
        // that showed no frame at all. `ready` stays false until ensureBuilt()
        // completes a clean build.
        builtAttempted = false;
    }

    //! Lazy, one-shot collaborator build (#103), invoked at the top of
    //! computeInner(). Runs at most once (`builtAttempted`). This is the guarded
    //! build that used to live in initialize(), MINUS `new FitLogger(self)` -- that
    //! one collaborator stays eager in initialize() because FitContributor field
    //! creation is init-only (#116; see the comment there). Everything here is a
    //! Storage/ANT/config collaborator whose TIMING moved (construction -> first
    //! compute), so the field renders its NODATA baseline first. `ready` flips true
    //! only on a clean build (§8.4). registerSensors() stays a separate guarded step
    //! (own try/catch), exactly as before, so an ANT failure never blocks the
    //! collaborator build and vice-versa.
    //!
    //! Two costs of moving this to first-compute, stated honestly:
    //!  (a) A synchronous HANG in here (e.g. ANT open()) is NOT caught or cured --
    //!      try/catch only traps throws, not never-returns. It is RELOCATED off the
    //!      load path: the field paints one baseline frame, then THIS tick freezes.
    //!      The win is that the frozen state is on the watchdog-killable compute
    //!      thread and the user has seen a §8.4 frame, not that the hang is gone.
    //!  (b) COMPUTE-TIME CONCENTRATION: the first tick now does the full collaborator
    //!      build + registerSensors() + a full compute() in a single 1 Hz slice,
    //!      under the compute watchdog. This is one-shot (guarded by builtAttempted),
    //!      so only tick 1 is heavy; every later tick is the old steady-state cost.
    hidden function ensureBuilt() {
        if (builtAttempted) { return; }
        builtAttempted = true;
        try {
            cfg = new Config();
            prims = new PrimitivesCalculator(cfg);
            filter = new AcuteFatigueFilter(cfg);
            effort = new EffortCharacterizer(cfg);
            ledger = new TrainingLoadLedger(cfg);
            sessions = new SessionStore();
            dSaveOutcome = sessions.pendingSaveOutcome();   // #83: surface last save's outcome at next start
            dNumericUnlocked = cfg.numericAfiUnlocked();
            dCalibrated = CalibrationFit.isCalibrated();
            ready = true;
        } catch (e) {
            ready = false;   // any collaborator may be null -> stay on NODATA snapshot
        }
        registerSensors();
    }

    function onSettingsChanged() {
        if (!ready) { return; }   // construction failed -> guarded no-op
        cfg.reload();
        prims.setConfig(cfg);
        filter.setConfig(cfg);
        effort.setConfig(cfg);
        ledger.setConfig(cfg);
        dNumericUnlocked = cfg.numericAfiUnlocked();
    }

    hidden function registerSensors() {
        // A Data Field cannot use Sensor.registerSensorDataListener (Watch-App /
        // Widget only — calling it is an uncatchable crash). To get beat-to-beat
        // RR for DFA-α1 we open a raw ANT+ channel to the HR strap instead — the
        // same approach the alphaHRV field uses. Guarded: if Ant is unavailable
        // or the device/strap can't provide it, `ant` stays null and the app runs
        // decoupling-only (§8.4) with no crash.
        try {
            ant = new AntHrm();
            ant.start();
        } catch (e) {
            ant = null;
        }
    }

    //! Release the raw ANT+ HRM channel at ride end (#47). Null-guarded (ant is
    //! null when Ant was unavailable) + try/catch. Called from App.onStop --
    //! deliberately NOT onHide, which fires on mid-ride data-screen paging and
    //! would tear down the strap / drop RR continuity.
    function releaseAnt() {
        try {
            if (ant != null) { ant.stop(); }
        } catch (e) { }
    }

    // (Removed the dead onSensorData RR callback (#31): a DataField cannot
    // register the Sensor RR listener, so it was never invoked and its pendingRr
    // buffer was never drained. Live RR comes from ant.drainRr() in computeInner.)

    // =====================================================================
    //  1 Hz COMPUTE
    // =====================================================================

    function compute(info) {
        // Top-level guard (§8.4): compute() must never throw — an uncaught error
        // here blanks the field to the Connect IQ banner and stops all logging.
        try {
            // #124 boot-smoke heartbeat. No-op in every shipping build (the
            // source-bootsmoke-stub BootSmoke has an empty body + no FM_TICK
            // literal); emits `FM_TICK <tick>` ONLY in the monkey.bootsmoke.jungle
            // build the advisory boot-smoke CI job boots without `-t`, so the parser
            // can count sustained per-tick liveness. Inside the §8.4 try so it can
            // never blank the field; harmless no-op cost on device.
            BootSmoke.tick(tick);
            computeInner(info);
            computeFailStreak = nextFailStreak(computeFailStreak, false);   // a good tick clears the latch
        } catch (e) {
            // swallow: keep the field alive; the last good snapshot stays on screen.
            // Count it (INSIDE-try reset above; increment here) so a persistent
            // per-tick fault (e.g. a NaN-poisoned filter) surfaces a degraded footer
            // marker instead of freezing silently on a stale snapshot (#28).
            computeFailStreak = nextFailStreak(computeFailStreak, true);
        }
    }

    hidden function computeInner(info) {
        ensureBuilt();            // #103: lazy one-shot build (render-first deferral)
        if (!ready) { return; }   // not (yet) built / build failed -> stay on the NODATA snapshot
        tick++;

        var power = (info != null) ? sanitize(info.currentPower) : null;
        var hr = (info != null) ? sanitize(info.currentHeartRate) : null;
        var cadence = (info != null) ? sanitize(info.currentCadence) : null;

        // RR intervals come from the ANT+ HRM channel (data fields can't use the
        // Sensor RR listener). Drain whatever arrived since the last second.
        var rr = (ant != null) ? ant.drainRr() : [];

        // "active" = actually doing work (pedaling / producing power). Basing this
        // on pedaling rather than HR>rest is what lets F RELAX on coasting/stops
        // (white paper §4.4 goal): during a coast HR can stay high yet no work is
        // done, so κ_d must switch off and F decays via τ_rec.
        var active = (cadence != null && cadence > 0)
                     || (power != null && power > 0.05 * cfg.ftp);
        var stationary = prims.isStationary();
        dStationary = stationary;
        dPowerAvail = (power != null);

        // ---- Layer 1 ----
        prims.update(power, hr, cadence, rr, tick);

        // ---- ride load (TSS) accumulation — the one honest per-ride Layer-3 output ----
        // Real elapsed seconds from the ACTIVITY TIMER (info.timerTime), which FREEZES
        // while paused, so paused ticks add zero load (#22). compute() keeps firing
        // during a pause, hence a frozen delta must map to dt=0 (not the nominal 1.0).
        // Monotonic getTimer() is a null-only fallback before the timer is available.
        var nowMs = (info != null && info.timerTime != null) ? info.timerTime : System.getTimer();
        var dt = 1.0;                                   // cold-start default (prevTimerMs == null)
        if (prevTimerMs != null) {
            var d = (nowMs - prevTimerMs) / 1000.0;
            dt = (d > 0.0 && d < 30.0) ? d : 0.0;       // paused/frozen -> 0; anomaly/source-switch -> 0
        }
        prevTimerMs = nowMs;
        ledger.update(power, hr, dt);

        // ---- F(0) starts NEUTRAL (§7 revised) ----
        // The acute filter no longer seeds from a cross-ride ledger: an on-device
        // data field can't keep an honest CTL/ATL/TSB (it sees only the rides it
        // runs, never other-app/indoor rides or a morning HRV reading), so we do
        // NOT claim a pre-ride fatigue we can't compute from ride data. F(0) is 0.
        if (!seeded && tick >= 2) {
            filter.seedFromLayer3(0.0);
            seeded = true;
        }

        // ---- α1 expected-for-power (population or calibrated sigmoid) ----
        // One combined call shares a single winPower/winHr snapshot between the α1
        // stationarity gate and decoupling (#93), instead of two toArray() apiece.
        // decoupling reads only winPower/winHr/efBaseline (nothing filter.step
        // mutates), so computing it here and consuming ad[1] below is identical.
        var ad = prims.alpha1AndDecoupling();
        var a1Metric = ad[0];
        var pForA1 = (power != null) ? power.toFloat() : cfg.pAeT;
        var a1Expected = AcuteFatigueFilter.a1Target(pForA1, cfg.pAeT, cfg.a0, cfg.a1, cfg.sigmoidS);
        var a1Measured = a1Metric.isUsable() ? a1Metric.value : a1Expected;
        var a1DriftBelow = a1Expected - a1Measured;      // >0 when below expected
        if (a1DriftBelow < 0) { a1DriftBelow = 0.0; }

        // ---- Layer 2 filter ----
        filter.step(power, hr, a1Metric, prims.alpha1Artifact(), prims.alpha1Fb(),
                    active, stationary);

        // ---- decoupling + AFI blend ----
        dDecoup = ad[1];   // #93: from the shared snapshot computed above
        var decoupVal = dDecoup.isUsable() ? dDecoup.value : 0.0;
        var afi = filter.afiBlended(decoupVal, prims.alpha1Artifact());
        dAfi = afi;
        dAfiUnc = filter.afiUncertainty();
        dSourceSwitched = filter.didSourceSwitch();
        dPriorDominated = filter.isPriorDominated();

        if (afi > peakAfi) { peakAfi = afi; }

        // ---- effort characterizer (off the critical path) ----
        effort.setKjAboveCp(prims.kjAboveCp());
        effort.update(power, prims.wBalFraction(), decoupVal, a1DriftBelow, prims.kjWeightedValue());
        dBest1 = effort.best1();
        dBest5 = effort.best5();
        dBest20 = effort.best20();
        dWmatches = effort.matchesBurned();
        var freshMatch = (effort.matchesBurned() > lastFreshMatchCount);
        lastFreshMatchCount = effort.matchesBurned();
        dRedKind = effort.redCharacter(dBest5, a1DriftBelow);

        // ---- status band (per-athlete; Feat/Attrition never gates) ----
        dAlpha1 = a1Metric;
        var artMetric = prims.artifactPercentMetric();
        dArtifact = artMetric.isPresent() ? artMetric.value : null;
        dKjw = prims.kjWeightedValue();
        var kjt = prims.kjTotalMetric();
        dKjTotal = kjt.isPresent() ? kjt.value : 0.0;
        // Layer 3 (CTL/ATL/TSB) still folds silently into the ledger for the post-
        // ride FIT/summary export and the internal F(0) seed, but is no longer
        // surfaced on the in-ride glance: the field only sees the rides it happens
        // to run, so an in-ride TSB/start-form readout can't be kept honest — that
        // record lives in the training-load platform, not here.

        var wRr = AcuteFatigueFilter.rrWeight(prims.alpha1Artifact(),
                     Constants.ARTIFACT_GOOD, cfg.artifactGate);
        var sensorsPresent = (power != null) || (hr != null) || a1Metric.isUsable();

        dStatus = StatusEvaluator.evaluate(cfg, {
            :afi => afi, :decoupMetric => dDecoup, :alpha1Metric => a1Metric,
            :kjWeighted => dKjw, :elapsedS => tick, :wRr => wRr,
            :redKind => dRedKind, :sensorsPresent => sensorsPresent,
            :afiDrift => filter.afiDriftAboveBaseline()
        });

        // ---- time-in-red split (Feat vs Attrition minutes — §8.3) ----
        if (dStatus[:status] == DescriptiveStrings.STATUS_DRIFTING) {
            effort.accrueRedSecond(power, freshMatch);
        }

        // ---- FIT record logging ----
        fit.logRecord(afi, filter.fState(), decoupVal, prims.alpha1Raw(),
                      prims.wBalFraction() * cfg.wPrime, dKjw,
                      effort.feat(dBest5), effort.attrition(a1DriftBelow));

        // ---- durable checkpoint (#17): survive an ungraceful stop ----
        // computeInner runs inside compute()'s §8.4 try and every Storage call is
        // itself guarded, so a checkpoint failure can never disturb the loop.
        if (!finalized && tick - lastCheckpointTick >= Constants.CHECKPOINT_PERIOD_S) {
            lastCheckpointTick = tick;
            checkpointSession();
        }

        // ---- strap-HR diagnostic snapshot (#57): DISPLAY ONLY ----
        // Written LAST so even an unlikely throw from hrMetric() can only drop this
        // tick's diagnostic, never skip the fatigue math above. Does NOT feed the
        // filter -- info.currentHeartRate remains the sole HR input. hrMetric() is a
        // side-effect-free read on the monotonic System clock.
        dStrapHr = (ant != null) ? ant.hrMetric(System.getTimer())
                                 : Signals.Metric.unavailable("no HR");
    }

    //! Validate a raw Activity.Info field into a finite number or null. This is
    //! the sensor-read guard (white paper §8.4): a missing/garbage value becomes
    //! null and greys only its dependent tiles.
    hidden function sanitize(v) {
        if (v == null) { return null; }
        if (!(v instanceof Lang.Number || v instanceof Lang.Float
              || v instanceof Lang.Long || v instanceof Lang.Double)) { return null; }
        if (!MathUtil.isFinite(v)) { return null; }
        return v;
    }

    // =====================================================================
    //  SESSION FINALIZE (called from App.onStop — ride ended/saved)
    // =====================================================================

    function finalizeSession() {
        if (!ready || finalized) { return; }   // no collaborators to finalize if init failed
        finalized = true;

        // Ride-induced cardiovascular drift (acute F from a NEUTRAL start) and ride
        // TSS are the honest, ride-scoped Layer-3 outputs. Pre-ride residual fatigue
        // and cross-ride CTL/ATL/TSB are NOT computable on-device (§7 revised), so
        // they are neither exported to the FIT nor kept in the session history — the
        // training-load platform (intervals.icu / Garmin) owns that record.
        var rideDrift = filter.fState();
        var rideTss = ledger.finalizeRide();
        var driftBucketLbl = AcuteFatigueFilter.fatigueBucket(rideDrift, cfg.fRef);

        fit.logSession(buildSummary(rideDrift, rideTss));
        // append() keeps the record in the in-memory history even if the durable
        // write fails; capture the outcome so a "not saved" affordance can surface
        // it (footer rendering coordinated with #28).
        var saved = sessions.append(buildSessionResult(rideDrift, rideTss, driftBucketLbl));
        dWriteFailed = !saved;
        if (saved) {
            sessions.clearActive();   // committed to history — drop the in-progress checkpoint (#17)
        }
        // else: KEEP KEY_ACTIVE (#83). A storage-full append adds to the in-memory
        // history but leaves KEY unchanged, so the ≤one-checkpoint-stale KEY_ACTIVE
        // is the sole durable copy — clearing it here (as the old unconditional
        // clearActive() did) lost the ride. Retaining it lets the NEXT start's
        // reconcileActive() recover it (token not in persisted history), which also
        // raises the "prior ride recovered" footer marker. (Latent data-loss fix.)
    }

    //! Snapshot the running summary to durable Storage + refresh the FIT session
    //! fields so an ungraceful stop still leaves a (near-final) summary (#17). All
    //! reads — finalizeRide()/fState()/effort/prims are non-destructive — so this is
    //! safe to call every cadence; it shares finalizeSession's builders so the
    //! checkpoint and the final write can never drift.
    hidden function checkpointSession() {
        var rideDrift = filter.fState();
        var rideTss = ledger.finalizeRide();
        var driftBucketLbl = AcuteFatigueFilter.fatigueBucket(rideDrift, cfg.fRef);
        // Re-set the FIT session fields so a crash-recovered .FIT still has a summary
        // (best-effort: helps only if Garmin's auto-recovery flushes the last setData).
        fit.logSession(buildSummary(rideDrift, rideTss));
        // Durable snapshot for reconcile-on-next-start (the load-bearing safety net).
        sessions.checkpoint(buildSessionResult(rideDrift, rideTss, driftBucketLbl));
    }

    hidden function buildSummary(rideDrift, rideTss) {
        return {
            :tss => rideTss,
            :endFatigue => rideDrift,
            :peakAfi => peakAfi,
            :redFeatS => effort.redFeatSeconds(),
            :redAttrS => effort.redAttritionSeconds(),
            :durabilityKj => prims.kjWeightedValue()
        };
    }

    hidden function buildSessionResult(rideDrift, rideTss, driftBucketLbl) {
        var r = SessionStore.buildResult(
            ledger.dayIndexPublic(), tick, rideTss,
            rideDrift, peakAfi,
            effort.redFeatSeconds(), effort.redAttritionSeconds(),
            effort.feat(effort.best5()), effort.attrition(0.0),
            effort.best1(), effort.best5(), effort.best20(),
            effort.matchesBurned(), prims.kjWeightedValue(),
            driftBucketLbl, filter.afiUncertainty());
        r.put("sessionToken", sessionToken);   // stable id -> reconcile dedup (#17)
        return r;
    }

    // =====================================================================
    //  RENDER — the single glance screen (§8.1)
    // =====================================================================

    function onUpdate(dc) {
        // Top-level guard (§8.4): a render error must never crash the field.
        try {
            var w = dc.getWidth();
            var h = dc.getHeight();
            dc.setColor(Graphics.COLOR_WHITE, 0x111111);
            dc.clear();

            // Evidence row is given AT LEAST equal height to the status band (§8.1 —
            // the primitives are the validated part), 0.26·h each.
            drawStatusBand(dc, w, h, 0, (h * 0.26).toNumber());
            drawDial(dc, w, h, (h * 0.26).toNumber(), (h * 0.18).toNumber());
            drawEvidenceRow(dc, w, h, (h * 0.44).toNumber(), (h * 0.26).toNumber());
            drawFeatsStrip(dc, w, h, (h * 0.70).toNumber(), (h * 0.13).toNumber());
            drawFooter(dc, w, h, (h * 0.83).toNumber(), (h * 0.17).toNumber());
        } catch (e) {
            // last resort: leave whatever was drawn rather than crash to the banner
        }
    }

    hidden function statusColor(status) {
        switch (status) {
            case DescriptiveStrings.STATUS_FRESH:    return 0x2E9E2E;
            case DescriptiveStrings.STATUS_BUILDING: return 0xD9A400;
            case DescriptiveStrings.STATUS_DRIFTING: return 0xCC2222;
            default:                                 return 0x555555;
        }
    }

    //! 1. Status band (largest) with the persistent advisory/uncalibrated tag.
    hidden function drawStatusBand(dc, w, h, y, bandH) {
        var status = dStatus[:status];
        var col = statusColor(status);
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, y, w, bandH);

        // main label (text + colour — never colour alone)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var label = DescriptiveStrings.statusLabel(status);
        dc.drawText(w / 2, y + bandH * 0.30, Graphics.FONT_LARGE, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // second line: red character (Feat/Attrition) — characterization, NOT a command
        if (status == DescriptiveStrings.STATUS_DRIFTING && !dRedKind.equals("none")) {
            var rc = DescriptiveStrings.redCharacterLabel(dRedKind);
            var rcol = dRedKind.equals("feat") ? 0xFFCC33 : Graphics.COLOR_WHITE;
            dc.setColor(rcol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y + bandH * 0.58, Graphics.FONT_MEDIUM, rc,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // persistent honesty tag ON THE BAND itself — the "advisory · not a
        // validated measurement" tag is ALWAYS present (the "uncalibrated" note is
        // shown separately in the footer, not as a replacement for this one).
        var tag = DescriptiveStrings.advisoryTag();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + bandH * 0.85, Graphics.FONT_XTINY, tag,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! 2. Acute Fatigue dial. Pre-pilot: 3-state band + coarse now marker. Post-
    //! pilot: precise AFI digit + now tick + shaded projection range.
    hidden function drawDial(dc, w, h, y, dialH) {
        var pad = (w * 0.06).toNumber();
        var barY = y + (dialH * 0.45).toNumber();
        var barH = (dialH * 0.22).toNumber();
        var barW = w - 2 * pad;

        // three colour segments (green | amber | red) — always with text markers
        var seg = barW / 3;
        dc.setColor(0x2E9E2E, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(pad, barY, seg, barH);
        dc.setColor(0xD9A400, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(pad + seg, barY, seg, barH);
        dc.setColor(0xCC2222, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(pad + 2 * seg, barY, barW - 2 * seg, barH);

        if (dNumericUnlocked && dAfi != null) {
            // POST-PILOT: precise AFI digit + now tick + projection range
            var nowX = pad + (MathUtil.clamp(dAfi / 100.0, 0.0, 1.0) * barW).toNumber();
            // projection range as a shaded band = now ± uncertainty
            var uncW = (MathUtil.clamp(dAfiUnc / 100.0, 0.0, 1.0) * barW).toNumber();
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            var band = FatigueMeterView.uncertaintyBand(nowX, uncW, pad, barW);   // #30: clamp to the bar
            dc.fillRectangle(band[0], barY, band[1], barH);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(nowX - 1, barY - 2, 3, barH + 4);
            dc.drawText(w / 2, y + (dialH * 0.15).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
                        "AFI " + dAfi.format("%.0f"),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            // PRE-PILOT (default): coarse "now" marker in the active band, no digit
            var nowBucket = statusToBucket(dStatus[:status]);
            var nowX = bucketToX(nowBucket, pad, barW);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(nowX - 2, barY - 4, 5, barH + 8);
            dc.drawText(nowX, barY + barH + 2, Graphics.FONT_XTINY, "NOW",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y + (dialH * 0.12).toNumber(), Graphics.FONT_TINY,
                        "Acute Fatigue (3-state)",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    hidden function statusToBucket(status) {
        if (status == DescriptiveStrings.STATUS_FRESH) { return "fresh"; }
        if (status == DescriptiveStrings.STATUS_BUILDING) { return "moderate"; }
        return "heavy";
    }
    hidden function bucketToX(bucket, pad, barW) {
        var frac = 0.5 / 3.0;                 // green centre
        if (bucket.equals("moderate")) { frac = 1.5 / 3.0; }
        if (bucket.equals("heavy")) { frac = 2.5 / 3.0; }
        return pad + (frac * barW).toNumber();
    }

    //! 3. Evidence row (equal weight to the band — the validated part).
    hidden function drawEvidenceRow(dc, w, h, y, rowH) {
        var cellW = w / 4;
        drawCell(dc, 0, y, cellW, rowH, "DECOUP",
                 fmtMetricPct(dDecoup), metricColor(dDecoup));
        drawCell(dc, cellW, y, cellW, rowH, "DFA-a1",
                 fmtAlpha(dAlpha1), metricColor(dAlpha1));
        drawKjBar(dc, 2 * cellW, y, cellW, rowH);
        // matches (W′bal) is power-dependent — grey with a marker on power loss.
        if (dPowerAvail) {
            drawCell(dc, 3 * cellW, y, cellW, rowH, "MATCHES",
                     dWmatches.format("%d"), Graphics.COLOR_WHITE);
        } else {
            drawCell(dc, 3 * cellW, y, cellW, rowH, "MATCHES", "— no pwr", 0x777777);
        }
    }

    hidden function drawCell(dc, x, y, cw, ch, title, value, valColor) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + cw / 2, y + ch * 0.20, Graphics.FONT_XTINY, title,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + cw / 2, y + ch * 0.60, Graphics.FONT_MEDIUM, value,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawKjBar(dc, x, y, cw, ch) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + cw / 2, y + ch * 0.20, Graphics.FONT_XTINY, "kJ/ANCHOR",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (!dPowerAvail) {
            dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + cw / 2, y + ch * 0.60, Graphics.FONT_MEDIUM, "no power",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var frac = MathUtil.clamp(MathUtil.safeDiv(dKjw, cfg.kjAnchor, 0.0), 0.0, 1.0);
        var bw = (cw * 0.7).toNumber();
        var bx = x + (cw * 0.15).toNumber();
        var by = y + (ch * 0.55).toNumber();
        var bh = (ch * 0.22).toNumber();
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, bw, bh);
        dc.setColor(frac >= 1.0 ? 0xCC2222 : 0x3388CC, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, (bw * frac).toNumber(), bh);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + cw / 2, y + ch * 0.85, Graphics.FONT_XTINY,
                    dKjw.format("%.0f") + "/" + cfg.kjAnchor.format("%.0f"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! 4. Feats strip: best 1 / 5 / 20-min power — the in-ride "feats". These are
    //! ride-scoped efforts the field measures directly, unlike the training-scale
    //! TSB / start-form context that was dropped from the glance (§5): the field
    //! can't keep an honest CTL/ATL from only the rides it runs, so that record
    //! belongs to the training-load platform, not to a per-ride readout.
    hidden function drawFeatsStrip(dc, w, h, y, rowH) {
        var cellW = w / 3;
        drawBestCell(dc, 0, y, cellW, rowH, "BEST 1min", dBest1);
        drawBestCell(dc, cellW, y, cellW, rowH, "BEST 5min", dBest5);
        drawBestCell(dc, 2 * cellW, y, cellW, rowH, "BEST 20min", dBest20);
    }

    //! Best-power cell — power-dependent: grey with "no power" when absent.
    hidden function drawBestCell(dc, x, y, cw, ch, title, watts) {
        if (dPowerAvail) {
            drawCell(dc, x, y, cw, ch, title, watts.format("%.0f") + "W", 0xFFCC33);
        } else {
            drawCell(dc, x, y, cw, ch, title, "no power", 0x777777);
        }
    }

    //! 5. Data-quality footer: artifact %/α1 validity + stationarity + fallback +
    //! the "uncalibrated" note (when applicable) + the non-medical disclaimer.
    hidden function drawFooter(dc, w, h, y, rowH) {
        dc.setColor(0x1A1A1A, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, y, w, rowH);

        // line 1: RR artifact / α1 validity + steadiness indicator, plus the
        // strap-HR diagnostic (#57) appended ONLY if it still fits — line 1 is
        // already a centered single-line FONT_XTINY with no wrap, so on a narrow /
        // round device the strap token gracefully drops rather than clipping.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var line1 = footerText();
        var line1s = line1 + "  ·  " + strapHrToken(dStrapHr);
        if (dc.getTextWidthInPixels(line1s, Graphics.FONT_XTINY) <= w) { line1 = line1s; }
        dc.drawText(w / 2, y + rowH * 0.16, Graphics.FONT_XTINY, line1,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // line 2: advisory basis / uncalibrated note
        var line2 = "";
        if (!dCalibrated) {
            line2 = DescriptiveStrings.uncalibratedTag();
        } else if (dStatus[:decoupOnly]) {
            line2 = DescriptiveStrings.decoupOnlyTag();
        } else if (dStatus[:alpha1Gated] && dStatus[:advisoryActive]) {
            line2 = "advisory on decoupling + kJ only (a1 gated) — weighted down";
        } else if (dPriorDominated) {
            line2 = "steady power: AFI prior-dominated";
        }
        // Persistence marker (#83): the #28 compute-degraded marker lives on LINE 1
        // (footerText); the save-outcome marker co-locates on line 2 AFTER the
        // calibration/advisory chain via #57's measured, non-masking append — so it
        // never evicts the advisory/uncalibrated tag. Honest limitation: when an
        // advisory tag already occupies line 2, the combined string usually won't
        // fit and the marker is silently dropped (acceptable at Priority Low). When
        // line 2 is otherwise empty (the common case) the marker takes it outright.
        var mark = DescriptiveStrings.saveMarkerLabel(dSaveOutcome);
        if (!mark.equals("")) {
            if (line2.equals("")) {
                line2 = mark;
            } else {
                var combined = line2 + "  ·  " + mark;
                if (dc.getTextWidthInPixels(combined, Graphics.FONT_XTINY) <= w) { line2 = combined; }
            }
        }
        if (!line2.equals("")) {
            dc.drawText(w / 2, y + rowH * 0.45, Graphics.FONT_XTINY, line2,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // line 3: persistent non-medical-device disclaimer (white paper §10)
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + rowH * 0.78, Graphics.FONT_XTINY,
                    DescriptiveStrings.notMedical(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function footerText() {
        // A persistent compute stall outranks the normal data-quality line so the
        // field can't sit frozen on a stale snapshot with no indication (#28). The
        // parenthesised count self-diagnoses: climbing every second = hard freeze;
        // small and cleared = transient.
        if (shouldShowDegraded(computeFailStreak, Constants.DEGRADED_AFTER)) {
            return DescriptiveStrings.degradedTag() + " (" + computeFailStreak.format("%d") + ")";
        }
        var steady = dStationary ? "steady" : "variable";
        if (dArtifact == null) { return "no RR — decoupling-only  ·  " + steady; }
        var q = "";
        if (dAlpha1 != null && dAlpha1.availability == Signals.AVAIL_OK) {
            q = "a1 ok";
        } else if (dAlpha1 != null && dAlpha1.label != null) {
            q = "a1 " + dAlpha1.label;
        }
        return "RR artifact " + dArtifact.format("%.0f") + "%  ·  " + q + "  ·  " + steady;
    }

    // ---- metric formatting / colours ----
    hidden function metricColor(m) {
        if (m == null || !m.isPresent()) { return 0x777777; }
        if (m.availability == Signals.AVAIL_OK) { return Graphics.COLOR_WHITE; }
        return 0xAAAA55;   // low-confidence / stale
    }
    hidden function fmtMetricPct(m) {
        if (m == null || !m.isPresent()) { return m == null ? "--" : (m.label == null ? "--" : m.label); }
        return m.value.format("%.1f") + "%";
    }
    hidden function fmtAlpha(m) {
        if (m == null || !m.isPresent()) { return "no RR"; }
        return m.value.format("%.2f");
    }
}
