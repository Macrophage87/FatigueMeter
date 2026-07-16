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
//! this pure suite: AntHrm channel lifecycle (its pure shouldReopen predicate IS
//! covered in PureFunctionTests), FitLogger (FitContributor), SessionStore +
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
}
