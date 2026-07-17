using Toybox.Lang;
using Toybox.Test;
using Toybox.Math;

//! Coverage-sweep unit tests (#14) — kept in their own module, split out of
//! PureFunctionTests.mc (#14). Each test is written to keep the Monkey C
//! type-checker's per-function work SMALL: no method calls on a dictionary value
//! of static type Object? (that forces method resolution over a wide union), no
//! heterogeneous CONTAINER literal holding class instances (that forces a
//! value-type overlap computation), and no deep boolean expression tree (every
//! condition is a shallow `var okN = ...;` so `combineSubstitutions` never
//! recurses deeply). The SDK 9.2.0 `monkeyc --unit-test` type-checker OOM'd on
//! the first, denser draft; this shape compiles within its fixed heap.
//!
//! Closes the PURE / near-pure coverage gaps the issue names: StatusEvaluator,
//! CalibrationFit, RingBuffer, and finite-safety guards for MathUtil / KalmanMath
//! / DfaAlpha1 / TrainingLoadLedger, plus a null-sensor AcuteFatigueFilter.step
//! assertion.
//!
//! SCOPE (honest, per review): this suite covers the PURE / near-pure surface,
//! INCLUDING EffortCharacterizer's featScore/attritionScore pure statics (added
//! below). What remains genuinely needs hardware or an integration harness, NOT
//! this pure suite: AntHrm channel lifecycle — the reopen paths + stall-watchdog
//! RESTART are channel-bound (integration/on-device), but its pure decode/lifecycle
//! statics ARE covered (shouldReopen in PureFunctionTests; rrDelta / stallExpired /
//! capOldest below, #24), FitLogger's FitContributor field creation +
//! setData (its pure deriveOk partial-success rule IS covered below, #20),
//! SessionStore's Storage-backed load/append/persist (its pure sanitize / migrate
//! / isValidRecord / buildResult validators ARE covered below, #18, and the
//! shed-until-fits floor guard shouldShed, #62) +
//! CalibrationFit.save/load (Application.Storage), FatigueMeterApp and the
//! WatchUi-rendering parts of FatigueMeterView (its defaultSnapshot IS already
//! covered by testViewDefaultSnapshotIsConservative), and DescriptiveStrings
//! (resource bundle). These tests execute under the #42 run-gate (monkeydo -t),
//! not just at compile.
module CoverageTests {

    // Local copies of the shared helpers (module-local, no cross-module coupling).
    function near(a, b, tol) {
        var d = a - b;
        if (d < 0) { d = -d; }
        return d <= tol;
    }
    function posInf() { var b = 9.0e37; return b * b; }

    // ---- StatusEvaluator (§4.5/§6/§8.2 band logic) ----
    // Helper (NOT a :test). The literal holds PRIMITIVES only; the Metric objects
    // are added by assignment so the literal's value-type overlap stays trivial.
    function baseStatusCtx() {
        var ctx = { :afi => 10.0, :kjWeighted => 0.0, :elapsedS => 0, :wRr => 1.0,
                    :redKind => "none", :sensorsPresent => true, :afiDrift => 0.0 };
        ctx[:decoupMetric] = Signals.Metric.ok(2.0, 1.0);
        ctx[:alpha1Metric] = Signals.Metric.ok(0.95, 1.0);
        return ctx;
    }

    (:test)
    function testStatusNoSensorsIsNoData(logger) {
        var ctx = baseStatusCtx();
        ctx[:sensorsPresent] = false;
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        var okStatus = (r[:status] == DescriptiveStrings.STATUS_NODATA);
        var okGated = (r[:alpha1Gated] == true);
        var okDecoup = (r[:decoupOnly] == true);
        var okAdv = (r[:advisoryActive] == false);
        return okStatus && okGated && okDecoup && okAdv;
    }

    (:test)
    function testStatusFreshBaseline(logger) {
        var r = StatusEvaluator.evaluate(new Config(), baseStatusCtx());  // afi 10 < afiFresh 30
        var okStatus = (r[:status] == DescriptiveStrings.STATUS_FRESH);
        var okGated = (r[:alpha1Gated] == false);
        var okDecoup = (r[:decoupOnly] == false);
        return okStatus && okGated && okDecoup;
    }

    (:test)
    function testStatusBuildingFromAfi(logger) {
        var ctx = baseStatusCtx();
        ctx[:afi] = 45.0;                        // in [afiFresh 30, afiBuilding 60)
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        return r[:status] == DescriptiveStrings.STATUS_BUILDING;
    }

    (:test)
    function testStatusBuildingFromDecoup(logger) {
        var ctx = baseStatusCtx();
        ctx[:decoupMetric] = Signals.Metric.ok(6.0, 1.0);   // > decoupOk 5, afi still low
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        return r[:status] == DescriptiveStrings.STATUS_BUILDING;
    }

    (:test)
    function testStatusDriftingFromAbsoluteAfi(logger) {
        var ctx = baseStatusCtx();
        ctx[:afi] = 70.0;                        // >= afiBuilding 60
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        return r[:status] == DescriptiveStrings.STATUS_DRIFTING;
    }

    (:test)
    function testStatusDriftingFromPerAthleteDrift(logger) {
        // §4.5: the absolute afiBuilding cutoff is NOT the sole gate -- per-athlete
        // AFI drift above the athlete's own baseline fires DRIFTING with a LOW afi.
        var ctx = baseStatusCtx();
        ctx[:afi] = 10.0;
        ctx[:afiDrift] = 20.0;                   // > afiDriftMargin 15
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        return r[:status] == DescriptiveStrings.STATUS_DRIFTING;
    }

    (:test)
    function testStatusDurabilityAdvisory(logger) {
        // §6: advisory needs time-on-task AND kJ anchor AND decoupling above caution.
        var cfg = new Config();
        var ctx = baseStatusCtx();
        ctx[:elapsedS] = Constants.DURABILITY_MIN_S;           // past time gate
        ctx[:kjWeighted] = 0.6 * cfg.kjAnchor + 1.0;           // past 0.6·kJ anchor
        ctx[:decoupMetric] = Signals.Metric.ok(9.0, 1.0);      // > decoupCaution 8
        var r = StatusEvaluator.evaluate(cfg, ctx);
        var okAdv = (r[:advisoryActive] == true);
        var okStatus = (r[:status] == DescriptiveStrings.STATUS_DRIFTING);
        return okAdv && okStatus;
    }

    (:test)
    function testStatusGatingFlags(logger) {
        // α1 not OK -> alpha1Gated ; wRr < 0.5 -> decoupOnly fallback
        var ctx = baseStatusCtx();
        ctx[:alpha1Metric] = Signals.Metric.unavailable("no rr");
        ctx[:wRr] = 0.3;
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        var okGated = (r[:alpha1Gated] == true);
        var okDecoup = (r[:decoupOnly] == true);
        return okGated && okDecoup;
    }

    (:test)
    function testStatusRedKindIsEvidenceOnly(logger) {
        // §8.2: redKind is attached ONLY when DRIFTING; it never gates the band.
        var cfg = new Config();
        var fresh = baseStatusCtx();  fresh[:redKind] = "feat";           // still FRESH
        var drift = baseStatusCtx();  drift[:afi] = 70.0; drift[:redKind] = "feat";
        // Cast to String so .equals resolves on String alone (not the Object? union).
        var rkFresh = StatusEvaluator.evaluate(cfg, fresh)[:redKind] as Lang.String;
        var rkDrift = StatusEvaluator.evaluate(cfg, drift)[:redKind] as Lang.String;
        var okFresh = rkFresh.equals("none");
        var okDrift = rkDrift.equals("feat");
        return okFresh && okDrift;
    }

    // ---- CalibrationFit (R²>0.75 acceptance gate) ----
    (:test)
    function testCalibFitGuardsTooFewSamples(logger) {
        var g1 = CalibrationFit.fitSigmoid(null, null);
        var g2 = CalibrationFit.fitSigmoid([100.0,150.0,200.0,250.0],   // size 4 < 8
                                           [0.90,0.85,0.80,0.75]);
        var ok1 = (g1["accepted"] == false);
        var ok1r2 = near(g1["r2"], 0.0, 1e-9);
        var ok2 = (g2["accepted"] == false);
        return ok1 && ok1r2 && ok2;
    }

    (:test)
    function testCalibFitAcceptsFallingAndLocatesAeT(logger) {
        // α1 = 0.95 - 0.001·P crosses AET_ALPHA1 (0.75) at P = 200 W; perfectly
        // linear -> R² = 1 > DFA_R2_GATE and slope < 0 -> accepted, pAeT ≈ 200.
        var P = []; var A = [];
        for (var p = 100; p <= 300; p += 25) { P.add(p.toFloat()); A.add(0.95 - 0.001 * p); }
        var fit = CalibrationFit.fitSigmoid(P, A);
        var okAcc = (fit["accepted"] == true);
        var okR2 = (fit["r2"] > Constants.DFA_R2_GATE);
        var okAet = near(fit["pAeT"], 200.0, 0.5);
        var okSlope = (fit["slope"] < 0.0);
        var okS = (fit["s"] > 0.001);
        return okAcc && okR2 && okAet && okSlope && okS;
    }

    (:test)
    function testCalibFitRejectsRisingSlope(logger) {
        // rising α1 with power (slope > 0) is non-physiological -> rejected even if tight
        var P = []; var A = [];
        for (var p = 100; p <= 300; p += 25) { P.add(p.toFloat()); A.add(0.5 + 0.001 * p); }
        var fit = CalibrationFit.fitSigmoid(P, A);
        return fit["accepted"] == false;
    }

    (:test)
    function testCalibFitFloorsSigmoidSlope(logger) {
        // near-flat fit maps to s = -4·slope/a1 below the 0.001 floor -> clamped up
        var P = []; var A = [];
        for (var p = 100; p <= 300; p += 25) { P.add(p.toFloat()); A.add(0.80 - 0.0000001 * p); }
        var fit = CalibrationFit.fitSigmoid(P, A);
        return near(fit["s"], 0.001, 1e-9);
    }

    // ---- RingBuffer (memory-bounding invariant) ----
    (:test)
    function testRingBufferEvictsOldestWhenFull(logger) {
        var rb = new RingBuffer(3);
        var e1 = rb.push(1); var e2 = rb.push(2); var e3 = rb.push(3);
        var e4 = rb.push(4);                 // full -> evicts oldest (1)
        var arr = rb.toArray();              // oldest -> newest
        var okEvict = (e1 == null) && (e2 == null) && (e3 == null) && (e4 == 1);
        var okState = (rb.isFull() == true) && (rb.size() == 3) && (rb.latest() == 4);
        var okOrder = (arr[0] == 2) && (arr[1] == 3) && (arr[2] == 4);
        return okEvict && okState && okOrder;
    }

    (:test)
    function testRingBufferEmptyState(logger) {
        var rb = new RingBuffer(4);
        var okSize = (rb.size() == 0) && (rb.isFull() == false) && (rb.capacity() == 4);
        var okEmpty = (rb.latest() == null) && (rb.toArray().size() == 0);
        return okSize && okEmpty;
    }

    (:test)
    function testRingBufferClearResets(logger) {
        var rb = new RingBuffer(2);
        rb.push(9); rb.push(8); rb.push(7);  // wrapped past capacity
        rb.clear();
        var okSize = (rb.size() == 0) && (rb.latest() == null);
        var okArr = (rb.toArray().size() == 0);
        return okSize && okArr;
    }

    // ---- RingBuffer degenerate-capacity clamp (#16) ----
    (:test)
    function testRingBufferZeroCapacity(logger) {
        // Regression for #16: capacity 0 must not divide-by-zero or read OOB on push.
        var rb = new RingBuffer(0);
        rb.push(5);
        var arr = rb.toArray();
        var okCap = (rb.capacity() == 1) && (rb.size() == 1);
        var okVals = (rb.latest() == 5) && (arr.size() == 1) && (arr[0] == 5);
        return okCap && okVals;
    }

    (:test)
    function testRingBufferNegativeCapacity(logger) {
        // -3 must not throw inside `new [negative]`; clamps to a single slot.
        var rb = new RingBuffer(-3);
        rb.push(1);
        return (rb.capacity() == 1) && (rb.latest() == 1);
    }

    (:test)
    function testRingBufferFloatCapacity(logger) {
        // 2.9 truncates to a valid length 2, then the >0 clamp applies.
        var rb = new RingBuffer(2.9);
        rb.push(1); rb.push(2);
        var evicted = rb.push(3);            // full -> evict oldest (1)
        var okCap = (rb.capacity() == 2) && (rb.size() == 2);
        return okCap && (evicted == 1) && (rb.latest() == 3);
    }

    (:test)
    function testRingBufferNullCapacity(logger) {
        // null short-circuits before .toNumber() -> single-slot fallback (#16).
        var rb = new RingBuffer(null);
        rb.push(7);
        return (rb.capacity() == 1) && (rb.latest() == 7);
    }

    // ---- MathUtil finite-safety guards ----
    (:test)
    function testSafeDivGuardsDivByZeroAndNull(logger) {
        var okZero = near(MathUtil.safeDiv(5.0, 0.0, -1.0), -1.0, 1e-12);   // den ~0
        var okNullDen = near(MathUtil.safeDiv(5.0, null, -1.0), -1.0, 1e-12);
        var okNullNum = near(MathUtil.safeDiv(null, 2.0, -1.0), -1.0, 1e-12);
        var okNormal = near(MathUtil.safeDiv(10.0, 2.0, 0.0), 5.0, 1e-12);
        return okZero && okNullDen && okNullNum && okNormal;
    }

    (:test)
    function testClampScrubsInfinity(logger) {
        // #9-safe: use the runtime posInf() helper, never an out-of-range literal.
        var pinf = posInf();
        var ninf = -pinf;
        var okHi = near(MathUtil.clamp(pinf, 0.0, 100.0), 100.0, 1e-6);   // +Inf -> hi
        var okLo = near(MathUtil.clamp(ninf, 0.0, 100.0), 0.0, 1e-6);     // -Inf -> lo
        var okMid = near(MathUtil.clamp(42.0, 0.0, 100.0), 42.0, 1e-6);   // passthrough
        return okHi && okLo && okMid;
    }

    (:test)
    function testOlsDegenerateDenominator(logger) {
        // all-equal x -> denom = n·Σx² - (Σx)² = 0 -> safe [0,0], no divide-by-zero
        var r = MathUtil.olsSlopeR2([3.0,3.0,3.0,3.0], [1.0,2.0,3.0,4.0]);
        var okSlope = near(r[0], 0.0, 1e-12);
        var okR2 = near(r[1], 0.0, 1e-12);
        return okSlope && okR2;
    }

    // ---- olsSlopeR2 / mean / stdev never-throws contract (#27) ----
    (:test)
    function testOlsSlopeR2NullInputs(logger) {
        // #27: a null xs or ys must return the [0,0] sentinel, never throw on .size().
        var a = MathUtil.olsSlopeR2(null, [1.0, 2.0]);
        var b = MathUtil.olsSlopeR2([1.0, 2.0], null);
        var okA = near(a[0], 0.0, 1e-9) && near(a[1], 0.0, 1e-9);
        var okB = near(b[0], 0.0, 1e-9) && near(b[1], 0.0, 1e-9);
        return okA && okB;
    }

    (:test)
    function testOlsSlopeR2MismatchedLengths(logger) {
        // #27: ys shorter than xs must NOT throw out-of-bounds -> [0,0].
        var r = MathUtil.olsSlopeR2([0.0, 1.0, 2.0, 3.0], [0.0, 1.0]);
        return near(r[0], 0.0, 1e-9) && near(r[1], 0.0, 1e-9);
    }

    (:test)
    function testOlsSlopeR2PerfectLine(logger) {
        // #27 happy-path regression: y = 2x + 1 -> slope 2, r2 1 (guard is a no-op).
        var r = MathUtil.olsSlopeR2([0.0, 1.0, 2.0, 3.0, 4.0],
                                    [1.0, 3.0, 5.0, 7.0, 9.0]);
        return near(r[0], 2.0, 1e-6) && near(r[1], 1.0, 1e-6);
    }

    (:test)
    function testOlsSlopeR2NonFiniteSlopeGuarded(logger) {
        // #27: exercises the isFinite(slope) branch the null/length tests don't.
        // x*x with x ~ 1e20 overflows Float (~1e40 > max) AT RUNTIME, so the slope
        // computes non-finite; the guard must return [0,0] instead of leaking
        // Inf/NaN. Inputs are IN-range literals (< Float max), so there is no #9
        // constant-folder hazard -- the overflow happens inside the sum, not in a
        // literal. (Deleting the `if (!isFinite(slope))` line would fail THIS test.)
        var big = [1.0e20, 2.0e20, 3.0e20];
        var r = MathUtil.olsSlopeR2(big, big);
        return near(r[0], 0.0, 1e-9) && near(r[1], 0.0, 1e-9);
    }

    (:test)
    function testMeanSkipsNullElements(logger) {
        // #27: a null hole must not throw; mean is over the present values -> (2+4)/2.
        return near(MathUtil.mean([2.0, null, 4.0]), 3.0, 1e-9);
    }

    (:test)
    function testMeanAllNullIsZero(logger) {
        // #27: all-null array -> 0.0, never divide by zero.
        return near(MathUtil.mean([null, null]), 0.0, 1e-9);
    }

    (:test)
    function testStdevSkipsNullElements(logger) {
        // #27: sample stdev of {2,4} (null skipped) = sqrt(2) ~ 1.41421.
        return near(MathUtil.stdev([2.0, null, 4.0]), 1.4142135, 1e-5);
    }

    (:test)
    function testFallingSigmoidClampsExpOverflow(logger) {
        // far below P_AeT the exponent saturates -> ~a0; far above -> ~a0-a1; both
        // stay finite and bounded (no exp overflow).
        var lo = MathUtil.fallingSigmoid(-100000.0, 200.0, 1.0, 0.5, 0.02);
        var hi = MathUtil.fallingSigmoid( 100000.0, 200.0, 1.0, 0.5, 0.02);
        var okFinite = MathUtil.isFinite(lo) && MathUtil.isFinite(hi);
        var okVals = near(lo, 1.0, 1e-6) && near(hi, 0.5, 1e-6);
        return okFinite && okVals;
    }

    // ---- KalmanMath.scalarUpdate degenerate FINITE-S skip ----
    // Distinct from #36's testScalarUpdateNonFiniteSGuard (that covers !isFinite(S));
    // this covers the finite S < 1e-9 branch (P=0, R=0) the panel asked to retain.
    (:test)
    function testScalarUpdateSkipsDegenerateS(logger) {
        var x = [1.0, 2.0, 3.0, 4.0];
        var P = KalmanMath.zeros4x4();               // all-zero covariance
        var H = [0.0, 1.0, 0.0, 0.0];
        var r = KalmanMath.scalarUpdate(x, P, H, 100.0, 0.0);   // S = 0 -> skip
        var xn = r[0];
        var ok01 = (xn[0] == 1.0) && (xn[1] == 2.0);
        var ok23 = (xn[2] == 3.0) && (xn[3] == 4.0);
        return ok01 && ok23;
    }

    // ---- DfaAlpha1 cold-start / artifact ----
    (:test)
    function testDfaColdStartReturnsNeutral(logger) {
        // empty and under-filled (N < 2·boxMax) windows -> neutral [0,0,0], never NaN
        var empty = DfaAlpha1.compute([], 4, 16);
        var few = [];
        for (var i = 0; i < 20; i++) { few.add(800.0); }   // 20 < 32
        var short = DfaAlpha1.compute(few, 4, 16);
        var okEmpty = (empty[0] == 0.0) && (empty[2] == 0);
        var okShort = (short[0] == 0.0) && (short[2] == 0);
        return okEmpty && okShort;
    }

    (:test)
    function testArtifactPercentTooFewBeats(logger) {
        // < 5 beats can't be trusted -> 100 % (forces α1 unavailable upstream)
        var okEmpty = near(DfaAlpha1.artifactPercent([], 0.05), 100.0, 1e-6);
        var okFew = near(DfaAlpha1.artifactPercent([800.0,800.0,800.0,800.0], 0.05), 100.0, 1e-6);
        return okEmpty && okFew;
    }

    (:test)
    function testArtifactPercentFlagsSpike(logger) {
        // clean stationary series ~0 %; a lone doubled RR (missed beat) is caught.
        // Build the spike INSIDE the loop (via add) rather than index-assigning
        // spiked[6] -- the type-checker types an empty [] literal as a zero-length
        // Array and rejects an out-of-range index write on it (SDK 9.2.0).
        var clean = []; var spiked = [];
        for (var i = 0; i < 12; i++) {
            clean.add(800.0);
            spiked.add(i == 6 ? 1600.0 : 800.0);
        }
        var okClean = near(DfaAlpha1.artifactPercent(clean, 0.05), 0.0, 1e-6);
        var okSpike = (DfaAlpha1.artifactPercent(spiked, 0.05) > 0.0);
        return okClean && okSpike;
    }

    // ---- TrainingLoadLedger guard paths ----
    (:test)
    function testTrimpGuardsHrMaxEqualsHrRest(logger) {
        // degenerate HR span (hrMax == hrRest) -> 0, no divide-by-zero
        var t = TrainingLoadLedger.trimpIncrement(150.0, 150.0, 150.0, 60.0, 0.64, 1.92);
        return near(t, 0.0, 1e-12);
    }

    (:test)
    function testTssWithZeroFtp(logger) {
        // ftp == 0 -> IF via safeDiv falls back to 0 -> TSS 0, finite (never NaN)
        var tss = TrainingLoadLedger.tss(3600, 200.0, 0.0);
        var okZero = near(tss, 0.0, 1e-9);
        var okFinite = MathUtil.isFinite(tss);
        return okZero && okFinite;
    }

    // ---- AcuteFatigueFilter.step null-sensor (review item 5) ----
    (:test)
    function testStepNullSensorsStayFinite(logger) {
        // A predict-only step (HR and α1 both missing) must never throw or leak a
        // non-finite output; F coasts and outputs stay finite through the gap.
        var cfg = new Config();
        var filt = new AcuteFatigueFilter(cfg);
        filt.step(200.0, 150.0, null, 0.0, 0.2, true, true);   // seed with a real HR
        for (var i = 0; i < 30; i++) {
            filt.step(null, null, null, 0.0, 0.2, false, true); // no power, no HR, no α1
        }
        var okHr = MathUtil.isFinite(filt.latentHr());
        var okF = MathUtil.isFinite(filt.fState());
        var okAfi = MathUtil.isFinite(filt.afiKalman());
        var okA1 = MathUtil.isFinite(filt.latentA1());
        var okClean = (filt.isDegraded() == false);
        return okHr && okF && okAfi && okA1 && okClean;
    }

    // ---- EffortCharacterizer pure scores (§8.2 — self-labeled unit-testable) ----
    (:test)
    function testFeatScoreAccumulatesTerms(logger) {
        // featScore = kjAboveCp + wSev·severeSec + matchDepth·wMatch + bestBonus,
        // where bestBonus fires only when be5w > cp. Base case: only kjAboveCp.
        var base  = EffortCharacterizer.featScore(100.0, 0.0, 0.0, 250.0, 250.0, 2.0, 1.0, 5.0);
        var severe = EffortCharacterizer.featScore(100.0, 10.0, 0.0, 250.0, 250.0, 2.0, 1.0, 5.0);
        var bonus = EffortCharacterizer.featScore(100.0, 0.0, 0.0, 300.0, 250.0, 2.0, 1.0, 5.0);
        var okBase = near(base, 100.0, 1e-9);   // be5w == cp -> no bonus, no other terms
        var okSevere = (severe > base);          // severe seconds add
        var okBonus = (bonus > base);            // be5w > cp adds the best-power bonus
        return okBase && okSevere && okBonus;
    }

    (:test)
    function testAttritionScoreAddsDriftTerm(logger) {
        // attritionScore = accum + (α1 drift below baseline)·wDrift, drift term only
        // when drift > 0 (a non-positive drift contributes nothing).
        var noDrift = EffortCharacterizer.attritionScore(5.0, 0.0, 3.0);
        var withDrift = EffortCharacterizer.attritionScore(5.0, 0.2, 3.0);
        var negDrift = EffortCharacterizer.attritionScore(5.0, -0.2, 3.0);
        var okNo = near(noDrift, 5.0, 1e-9);
        var okWith = near(withDrift, 5.6, 1e-9);   // 5 + 0.2*3
        var okNeg = near(negDrift, 5.0, 1e-9);      // negative drift ignored
        return okNo && okWith && okNeg;
    }

    // ---- StatusEvaluator null-guard hardening (#10) ----
    // Each test isolates ONE of the three guards so a regression in one can't be
    // masked by another. #53's testStatusNoSensorsIsNoData already covers explicit
    // :sensorsPresent=>false; these cover the ABSENT-key (null) + null-metric paths
    // it left open. Defensive/unit-testability hardening, not a live-crash fix:
    // the live caller always passes non-null and evaluate() runs inside compute()'s
    // try/catch.

    (:test)
    function testStatusMissingSensorsKeyIsNoData(logger) {
        // Guard 1: an ABSENT :sensorsPresent key reads null. The old
        // `!ctx[:sensorsPresent]` threw UnexpectedTypeException; `!= true` falls
        // through to NODATA.
        var r = StatusEvaluator.evaluate(new Config(), {});
        return r[:status] == DescriptiveStrings.STATUS_NODATA;
    }

    (:test)
    function testStatusNullWRrNoCrash(logger) {
        // Guard 2: sensors present but :wRr null must not throw on `wRr < 0.5`;
        // null -> decoupOnly false (signal not asserted).
        var ctx = baseStatusCtx();
        ctx[:wRr] = null;
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        return r[:decoupOnly] == false;
    }

    (:test)
    function testStatusNullElapsedNoCrash(logger) {
        // Guard 3: sensors present but :elapsedS null must not throw on
        // `elapsed >= DURABILITY_MIN_S`; null -> pastTime false, so the durability
        // advisory cannot fire even with kJ + decoupling otherwise qualifying.
        var ctx = baseStatusCtx();
        ctx[:elapsedS] = null;
        ctx[:kjWeighted] = 999999.0;                       // would-be pastKj
        ctx[:decoupMetric] = Signals.Metric.ok(9.0, 1.0);  // > decoupCaution
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        return r[:advisoryActive] == false;
    }

    // ---- FitLogger.deriveOk partial-success rule (#20) ----
    // FitLogger.initialize derives `ok` from how many developer fields actually
    // got created, not from an exception-free run, so a PARTIAL success still logs
    // the fields that registered. This is the pure decision, unit-testable without
    // a real DataField / FitContributor.
    (:test)
    function testDeriveOkTruthTable(logger) {
        var okNone = (FitLogger.deriveOk(0, 0) == false);   // nothing created -> off
        var okRec  = (FitLogger.deriveOk(8, 0) == true);    // record fields only -> on
        var okSes  = (FitLogger.deriveOk(0, 6) == true);    // session fields only -> on
        var okBoth = (FitLogger.deriveOk(8, 6) == true);    // both -> on
        return okNone && okRec && okSes && okBoth;
    }

    // ---- SessionStore record-integrity validators (#18) ----
    // The Storage-backed load/append/persist can't run in the pure harness, but the
    // sanitize/migrate/isValidRecord/buildResult statics that keep a foreign or
    // partially-written value from corrupting the history are pure and covered here.

    (:test)
    function testStoreMigratesUnversioned(logger) {
        // A legacy record predates the "_v" stamp; migrate() upgrades it in place so
        // it validates -- history written before the schema stamp isn't discarded.
        var legacy = { "date" => 1, "durationS" => 3600, "tss" => 50.0 };
        var migrated = SessionStore.migrate(legacy) as Lang.Dictionary;
        var okValid = (SessionStore.isValidRecord(migrated) == true);
        var okStamped = (migrated["_v"] == SessionSchema.VERSION);
        return okValid && okStamped;
    }

    (:test)
    function testStoreRejectsMalformed(logger) {
        // Non-dictionaries, dicts missing a structural key, and wrong-schema dicts
        // are all rejected, so a foreign/partial value can't enter the history.
        var okString = (SessionStore.isValidRecord("nope") == false);
        var okNumber = (SessionStore.isValidRecord(42) == false);
        var okNull   = (SessionStore.isValidRecord(null) == false);
        var noKeys   = { "_v" => SessionSchema.VERSION };            // no date/durationS
        var okNoKeys = (SessionStore.isValidRecord(noKeys) == false);
        var wrongV   = { "_v" => 999, "date" => 1, "durationS" => 10 };
        var okWrongV = (SessionStore.isValidRecord(wrongV) == false);
        return okString && okNumber && okNull && okNoKeys && okWrongV;
    }

    (:test)
    function testStoreSanitizeDropsBadElements(logger) {
        // sanitize() migrates the valid, drops the rest. Build the mixed array via
        // add() -- a heterogeneous literal (dicts + a string + null) would force the
        // type-checker to compute a wide value-type overlap (the #14 shape to avoid).
        var raw = [];
        raw.add({ "_v" => SessionSchema.VERSION, "date" => 1, "durationS" => 10 }); // valid
        raw.add({ "date" => 2, "durationS" => 20 });          // unversioned -> migrated in
        raw.add("garbage");                                   // non-dict -> dropped
        raw.add(null);                                        // null -> dropped
        raw.add({ "date" => 3 });                             // missing durationS -> dropped
        var clean = SessionStore.sanitize(raw);
        var okCount = (clean.size() == 2);
        // Assert the RIGHT two survived in order (valid date=1, migrated date=2),
        // not merely that two elements remain -- a bug that kept the wrong pair
        // would still pass a bare size() check.
        var r0 = clean[0] as Lang.Dictionary;
        var r1 = clean[1] as Lang.Dictionary;
        var okKept = (r0["date"] == 1) && (r1["date"] == 2);
        return okCount && okKept;
    }

    (:test)
    function testStoreBuildResultIsValidAndVersioned(logger) {
        // The write path (buildResult) and the read-side validator (isValidRecord)
        // agree: a freshly built Session Result is stamped with the current schema.
        var r = SessionStore.buildResult(
            1, 3600, 55.0, 8.0, 42.0,
            120.0, 0.0, 3.0, 1.0,
            400.0, 320.0, 280.0, 2, 1800.0,
            "moderate", 5.0);
        var okValid = (SessionStore.isValidRecord(r) == true);
        var rd = r as Lang.Dictionary;
        var okVersion = (rd["_v"] == SessionSchema.VERSION);
        return okValid && okVersion;
    }

    (:test)
    function testShouldShedRespectsFloor(logger) {
        // #62: the shed-until-fits floor guard. shouldShed is the LIVE decision
        // persist() calls, so this pins the >/>= boundary that keeps MIN_HISTORY
        // records (a >= bug would shed the last ride the floor exists to protect).
        var okAbove = (SessionStore.shouldShed(2, 1) == true);
        var okAt    = (SessionStore.shouldShed(1, 1) == false);
        var okBelow = (SessionStore.shouldShed(0, 1) == false);
        return okAbove && okAt && okBelow;
    }

    // ---- TrainingLoadLedger day-index + real-dt (#22) and ewmaFold guard (#34a) ----
    // NOTE: the caller-side pause->dt=0 decision lives in FatigueMeterView.computeInner
    // (view loop) and is verified by reasoning, not a pure unit test -- it needs an
    // integration harness, like the other view-loop behaviour noted in the SCOPE block
    // above. The ledger's own dt handling (accumulation, the load gate) IS covered here.

    (:test)
    function testLocalDayIndexAppliesOffset(logger) {
        // #22: the date stamp must be the LOCAL calendar day. Calls the pure static
        // directly (clock-free) rather than the instance dayIndex().
        var utc = 10 * 86400 + 3600;                                          // 01:00 UTC, epoch-day 10
        var okLocal = (TrainingLoadLedger.localDayIndex(utc, -8 * 3600) == 9);   // US Pacific -> prev day
        var okUtc   = (TrainingLoadLedger.localDayIndex(utc, 0) == 10);          // old UTC behaviour
        var utc2 = 20 * 86400 + 23 * 3600;                                   // 23:00 UTC
        var okAhead = (TrainingLoadLedger.localDayIndex(utc2, 13 * 3600) == 21); // NZDT -> next day
        return okLocal && okUtc && okAhead;
    }

    (:test)
    function testTrimpIncrementScalesWithDt(logger) {
        // #22: dt scales the increment linearly; a hard-coded dt=1 regression makes two==one.
        var one = TrainingLoadLedger.trimpIncrement(150.0, 60.0, 190.0, 1.0, 0.64, 1.92);
        var two = TrainingLoadLedger.trimpIncrement(150.0, 60.0, 190.0, 2.0, 0.64, 1.92);
        return near(two, 2.0 * one, 1e-9) && (one > 0.0);
    }

    (:test)
    function testUpdateDtAccumulatesRealTime(logger) {
        // #22: one 10 s update must equal ten 1 s updates (same HR, no power -> TRIMP
        // path). This is the regression gate for update() actually USING dt, which a
        // secondsAccum++ / hard-coded-1.0 mutant fails.
        var cfg = new Config();
        var big   = new TrainingLoadLedger(cfg);
        var small = new TrainingLoadLedger(cfg);
        big.update(null, 150, 10.0);
        for (var i = 0; i < 10; i++) { small.update(null, 150, 1.0); }
        return near(big.rideLoad(), small.rideLoad(), 1e-6);
    }

    (:test)
    function testPowerGateSurvivesThrottling(logger) {
        // #22: dt=5 throttling. The OLD samples-vs-seconds gate reads npCount=20 vs
        // secondsAccum/4=25 -> false -> TRIMP fallback (0, no HR) despite power every
        // tick. The seconds-vs-seconds powerSecondsAccum gate (100 > 25) picks TSS.
        // Also fails if npCount++ were dropped (rideNp -> 0 -> tss 0).
        var cfg = new Config();
        var l = new TrainingLoadLedger(cfg);
        for (var i = 0; i < 20; i++) { l.update(200, null, 5.0); }   // power only, dt=5
        return l.rideLoad() > 0.0;   // TSS path -> >0; a wrong TRIMP fallback would be 0
    }

    (:test)
    function testEwmaFoldGuardsZeroTau(logger) {
        // #34a: tau == 0 -> return prev unchanged (no Inf/NaN); tau > 0 -> normal fold.
        var guarded = TrainingLoadLedger.ewmaFold(5.0, 10.0, 0.0);   // tau 0 -> prev
        var normal  = TrainingLoadLedger.ewmaFold(0.0, 10.0, 2.0);   // 0 + 10/2
        return near(guarded, 5.0, 1e-9) && near(normal, 5.0, 1e-9);
    }

    // ---- AntHrm RR state machine + lifecycle statics (#24) ----
    // AntHrm extends Ant.GenericChannel and can't be built in the pure harness, so
    // the beat arithmetic / watchdog gate / buffer cap are extracted as pure statics
    // (the shouldReopen precedent). The reopen paths + watchdog restart themselves
    // are channel-bound -> integration/on-device, noted in the SCOPE block above.
    (:test)
    function testRrDeltaEmitsInWindow(logger) {
        var r = AntHrm.rrDelta(1000, 40, 1820, 41);     // dCount 1, 820 ticks -> 800 ms
        return r[0] == 1 && r[1] == 800;
    }
    (:test)
    function testRrDeltaDropsHighImplausible(logger) {
        var r = AntHrm.rrDelta(1000, 40, 6120, 41);     // 5120 ticks -> 5000 ms > 2200
        return r[0] == 1 && r[1] == null;
    }
    (:test)
    function testRrDeltaDropsLowImplausible(logger) {
        var r = AntHrm.rrDelta(1000, 40, 1100, 41);     // 100 ticks -> ~97 ms < 250
        return r[0] == 1 && r[1] == null;
    }
    (:test)
    function testRrDeltaAdvanceMidBand(logger) {
        var r = AntHrm.rrDelta(1000, 40, 1820, 45);     // dCount 5: advance, no emit
        return r[0] == 1 && r[1] == null;
    }
    (:test)
    function testRrDeltaFwdMaxBoundary(logger) {
        var a = AntHrm.rrDelta(1000, 40, 1820, 55);     // dCount 15 -> ADVANCE
        var b = AntHrm.rrDelta(1000, 40, 1820, 56);     // dCount 16 -> RESYNC
        return a[0] == 1 && b[0] == 2;
    }
    (:test)
    function testRrDeltaDuplicateKeepsState(logger) {
        var r = AntHrm.rrDelta(1000, 40, 1234, 40);     // dCount 0 -> DUP
        return r[0] == 0 && r[1] == null;
    }
    (:test)
    function testRrDeltaReorderResyncs(logger) {
        var r = AntHrm.rrDelta(1000, 40, 900, 37);      // (37-40)&0xFF = 253 -> RESYNC
        return r[0] == 2 && r[1] == null;               // never adopts the stale 37
    }
    (:test)
    function testStallExpiredBoundary(logger) {
        var okAt  = (AntHrm.stallExpired(40000, 0, 40000) == true);    // >= boundary
        var okBel = (AntHrm.stallExpired(39999, 0, 40000) == false);
        return okAt && okBel;
    }
    (:test)
    function testCapOldestDropsWhenFull(logger) {
        var full = [] as Lang.Array;                    // build via add() (avoid zero-length [] index)
        for (var i = 0; i < 4; i++) { full.add(i); }
        var c = AntHrm.capOldest(full, 4);              // at cap -> drop oldest
        var okFull = (c.size() == 3) && (c[0] == 1);
        var under = [9] as Lang.Array;
        var okUnder = (AntHrm.capOldest(under, 4).size() == 1);   // under cap -> unchanged
        return okFull && okUnder;
    }

    // ---- decoupHigh severe tier wired into the durability advisory (#25) ----
    (:test)
    function testDecoupSevereFiresWithReducedKj(logger) {
        // Severe (> high 10) + REDUCED kJ (>= 0.3 anchor, < full 0.6) + time -> DRIFTING.
        // main (full anchor only) left this BUILDING.
        var ctx = baseStatusCtx();
        ctx[:decoupMetric] = Signals.Metric.ok(12.0, 1.0);
        ctx[:kjWeighted] = 700.0;                          // >= 0.3*2000 (600), < 0.6 (1200)
        ctx[:elapsedS] = 4000;
        var r = StatusEvaluator.evaluate(new Config(), ctx);
        return r[:advisoryActive] == true && r[:status] == DescriptiveStrings.STATUS_DRIFTING;
    }
    (:test)
    function testDecoupSevereStillNeedsSomeWork(logger) {
        // Severe is NOT time-alone: below even the reduced 0.3 anchor -> no advisory.
        var ctx = baseStatusCtx();
        ctx[:decoupMetric] = Signals.Metric.ok(12.0, 1.0);
        ctx[:kjWeighted] = 300.0;                          // < 0.3*2000 (600)
        ctx[:elapsedS] = 4000;
        return StatusEvaluator.evaluate(new Config(), ctx)[:advisoryActive] == false;
    }
    (:test)
    function testDecoupElevatedStillNeedsFullKj(logger) {
        // Elevated (caution < 9 < high) needs the FULL anchor -- reduced-only work is
        // the severe tier's privilege only.
        var ctx = baseStatusCtx();
        ctx[:decoupMetric] = Signals.Metric.ok(9.0, 1.0);
        ctx[:kjWeighted] = 700.0;                          // reduced ok, full fails, 9 not severe
        ctx[:elapsedS] = 4000;
        return StatusEvaluator.evaluate(new Config(), ctx)[:advisoryActive] == false;
    }
    (:test)
    function testDecoupSevereStillNeedsTime(logger) {
        // Severe drift + kJ met but only 20 min -> time gate blocks it (not a bare absolute).
        var ctx = baseStatusCtx();
        ctx[:decoupMetric] = Signals.Metric.ok(15.0, 1.0);
        ctx[:kjWeighted] = 5000.0;
        ctx[:elapsedS] = 1200;                             // < DURABILITY_MIN_S
        return StatusEvaluator.evaluate(new Config(), ctx)[:advisoryActive] == false;
    }
    (:test)
    function testDecoupHighSettingMovesBoundary(logger) {
        // #25 honesty: the severe firing boundary tracks cfg.decoupHigh. Same drift
        // (15) + reduced-kJ-only work fires with default high=10 but NOT once high=20.
        // A mutant hard-coding a literal 10 fires in both -> fails here.
        var ctx = baseStatusCtx();
        ctx[:decoupMetric] = Signals.Metric.ok(15.0, 1.0);
        ctx[:kjWeighted] = 700.0;                          // reduced-only path
        ctx[:elapsedS] = 4000;
        var firesDefault = StatusEvaluator.evaluate(new Config(), ctx)[:advisoryActive];
        var raised = new Config();  raised.decoupHigh = 20.0;
        var firesRaised = StatusEvaluator.evaluate(raised, ctx)[:advisoryActive];
        return firesDefault == true && firesRaised == false;
    }
}
