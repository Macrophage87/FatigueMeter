using Toybox.Lang;
using Toybox.Test;
using Toybox.Math;

//! Coverage-sweep unit tests (#14) — split OUT of PureFunctionTests.mc into their
//! own module so neither file is large enough to exhaust the Monkey C
//! type-checker's fixed heap (the SDK 9.2.0 `monkeyc --unit-test` compile
//! OOM'd -- FunctionTypeChecker.combineSubstitutions -- once PureFunctionTests
//! passed ~75 (:test) functions in ONE module; splitting keeps each module well
//! under that threshold). The CIQ "Run No Evil" runner executes (:test) functions
//! across ALL modules, and scripts/check_ciq_tests.py counts them across all
//! source files, so the split is transparent to the gate.
//!
//! Closes the PURE / near-pure coverage gaps the issue names: StatusEvaluator,
//! CalibrationFit, RingBuffer, and finite-safety guards for MathUtil / KalmanMath
//! / DfaAlpha1 / TrainingLoadLedger, plus a null-sensor AcuteFatigueFilter.step
//! assertion.
//!
//! SCOPE (honest, per review): 7 of the 10 modules the issue named remain
//! untested here because they need hardware or an integration harness, NOT this
//! pure suite -- AntHrm (ANT channel; its pure shouldReopen predicate is covered
//! in PureFunctionTests), FitLogger (FitContributor), SessionStore +
//! CalibrationFit.save/load (Application.Storage), FatigueMeterApp /
//! FatigueMeterView (WatchUi lifecycle), DescriptiveStrings (resource bundle),
//! EffortCharacterizer (follow-up). These execute under the #42 run-gate
//! (monkeydo -t), not just at compile.
module CoverageTests {

    // Local copies of the shared helpers (kept module-local so this file has no
    // cross-module test-helper coupling). Mirrors PureFunctionTests.near/posInf.
    function near(a, b, tol) {
        var d = a - b;
        if (d < 0) { d = -d; }
        return d <= tol;
    }
    function posInf() { var b = 9.0e37; return b * b; }

    // ---- StatusEvaluator (§4.5/§6/§8.2 band logic) ----
    // Helper (NOT a :test): an all-fresh, sensors-present baseline ctx each test
    // mutates -- mirrors how near() is a shared helper in this module.
    function baseStatusCtx() {
        return { :afi => 10.0,
                 :decoupMetric => Signals.Metric.ok(2.0, 1.0),
                 :alpha1Metric => Signals.Metric.ok(0.95, 1.0),
                 :kjWeighted => 0.0, :elapsedS => 0, :wRr => 1.0,
                 :redKind => "none", :sensorsPresent => true, :afiDrift => 0.0 };
    }

    (:test)
    function testStatusNoSensorsIsNoData(logger) {
        var cfg = new Config();
        var ctx = baseStatusCtx();
        ctx[:sensorsPresent] = false;
        var r = StatusEvaluator.evaluate(cfg, ctx);
        return r[:status] == DescriptiveStrings.STATUS_NODATA
            && r[:alpha1Gated] && r[:decoupOnly] && !r[:advisoryActive];
    }

    (:test)
    function testStatusFreshBaseline(logger) {
        var cfg = new Config();
        var r = StatusEvaluator.evaluate(cfg, baseStatusCtx());  // afi 10 < afiFresh 30
        return r[:status] == DescriptiveStrings.STATUS_FRESH
            && !r[:alpha1Gated] && !r[:decoupOnly];
    }

    (:test)
    function testStatusBuildingFromAfiOrDecoup(logger) {
        var cfg = new Config();
        var byAfi = baseStatusCtx();     byAfi[:afi] = 45.0;   // in [afiFresh 30, afiBuilding 60)
        var byDecoup = baseStatusCtx();  byDecoup[:decoupMetric] = Signals.Metric.ok(6.0, 1.0); // > decoupOk 5
        return StatusEvaluator.evaluate(cfg, byAfi)[:status] == DescriptiveStrings.STATUS_BUILDING
            && StatusEvaluator.evaluate(cfg, byDecoup)[:status] == DescriptiveStrings.STATUS_BUILDING;
    }

    (:test)
    function testStatusDriftingFromAbsoluteAfi(logger) {
        var cfg = new Config();
        var ctx = baseStatusCtx();  ctx[:afi] = 70.0;   // >= afiBuilding 60
        return StatusEvaluator.evaluate(cfg, ctx)[:status] == DescriptiveStrings.STATUS_DRIFTING;
    }

    (:test)
    function testStatusDriftingFromPerAthleteDrift(logger) {
        // §4.5: the absolute afiBuilding cutoff is NOT the sole gate -- per-athlete
        // AFI drift above the athlete's own baseline fires DRIFTING with a LOW afi.
        var cfg = new Config();
        var ctx = baseStatusCtx();  ctx[:afi] = 10.0;  ctx[:afiDrift] = 20.0; // > afiDriftMargin 15
        return StatusEvaluator.evaluate(cfg, ctx)[:status] == DescriptiveStrings.STATUS_DRIFTING;
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
        return r[:advisoryActive] && r[:status] == DescriptiveStrings.STATUS_DRIFTING;
    }

    (:test)
    function testStatusGatingFlags(logger) {
        // α1 not OK -> alpha1Gated ; wRr < 0.5 -> decoupOnly fallback
        var cfg = new Config();
        var ctx = baseStatusCtx();
        ctx[:alpha1Metric] = Signals.Metric.unavailable("no rr");
        ctx[:wRr] = 0.3;
        var r = StatusEvaluator.evaluate(cfg, ctx);
        return r[:alpha1Gated] && r[:decoupOnly];
    }

    (:test)
    function testStatusRedKindIsEvidenceOnly(logger) {
        // §8.2: redKind is attached ONLY when DRIFTING; it never gates the band.
        var cfg = new Config();
        var fresh = baseStatusCtx();  fresh[:redKind] = "feat";           // still FRESH
        var drift = baseStatusCtx();  drift[:afi] = 70.0; drift[:redKind] = "feat";
        return StatusEvaluator.evaluate(cfg, fresh)[:redKind].equals("none")
            && StatusEvaluator.evaluate(cfg, drift)[:redKind].equals("feat");
    }

    // ---- CalibrationFit (R²>0.75 acceptance gate) ----
    (:test)
    function testCalibFitGuardsTooFewSamples(logger) {
        var g1 = CalibrationFit.fitSigmoid(null, null);
        var g2 = CalibrationFit.fitSigmoid([100.0,150.0,200.0,250.0],   // size 4 < 8
                                           [0.90,0.85,0.80,0.75]);
        return !g1["accepted"] && near(g1["r2"], 0.0, 1e-9) && !g2["accepted"];
    }

    (:test)
    function testCalibFitAcceptsFallingAndLocatesAeT(logger) {
        // α1 = 0.95 - 0.001·P crosses AET_ALPHA1 (0.75) at P = 200 W; perfectly
        // linear -> R² = 1 > DFA_R2_GATE and slope < 0 -> accepted, pAeT ≈ 200.
        var P = []; var A = [];
        for (var p = 100; p <= 300; p += 25) { P.add(p.toFloat()); A.add(0.95 - 0.001 * p); }
        var fit = CalibrationFit.fitSigmoid(P, A);
        return fit["accepted"] && fit["r2"] > Constants.DFA_R2_GATE
            && near(fit["pAeT"], 200.0, 0.5) && fit["slope"] < 0.0 && fit["s"] > 0.001;
    }

    (:test)
    function testCalibFitRejectsRisingSlope(logger) {
        // rising α1 with power (slope > 0) is non-physiological -> rejected even if tight
        var P = []; var A = [];
        for (var p = 100; p <= 300; p += 25) { P.add(p.toFloat()); A.add(0.5 + 0.001 * p); }
        return !CalibrationFit.fitSigmoid(P, A)["accepted"];
    }

    (:test)
    function testCalibFitFloorsSigmoidSlope(logger) {
        // near-flat fit maps to s = -4·slope/a1 below the 0.001 floor -> clamped up
        var P = []; var A = [];
        for (var p = 100; p <= 300; p += 25) { P.add(p.toFloat()); A.add(0.80 - 0.0000001 * p); }
        return near(CalibrationFit.fitSigmoid(P, A)["s"], 0.001, 1e-9);
    }

    // ---- RingBuffer (memory-bounding invariant) ----
    (:test)
    function testRingBufferEvictsOldestWhenFull(logger) {
        var rb = new RingBuffer(3);
        var e1 = rb.push(1); var e2 = rb.push(2); var e3 = rb.push(3);
        var e4 = rb.push(4);                 // full -> evicts oldest (1)
        var arr = rb.toArray();              // oldest -> newest
        return e1 == null && e2 == null && e3 == null && e4 == 1
            && rb.isFull() && rb.size() == 3
            && arr[0] == 2 && arr[1] == 3 && arr[2] == 4 && rb.latest() == 4;
    }

    (:test)
    function testRingBufferEmptyState(logger) {
        var rb = new RingBuffer(4);
        return rb.size() == 0 && !rb.isFull() && rb.capacity() == 4
            && rb.latest() == null && rb.toArray().size() == 0;
    }

    (:test)
    function testRingBufferClearResets(logger) {
        var rb = new RingBuffer(2);
        rb.push(9); rb.push(8); rb.push(7);  // wrapped past capacity
        rb.clear();
        return rb.size() == 0 && rb.latest() == null && rb.toArray().size() == 0;
    }

    // ---- MathUtil finite-safety guards ----
    (:test)
    function testSafeDivGuardsDivByZeroAndNull(logger) {
        return near(MathUtil.safeDiv(5.0, 0.0, -1.0), -1.0, 1e-12)     // den ~0 -> fallback
            && near(MathUtil.safeDiv(5.0, null, -1.0), -1.0, 1e-12)    // null den
            && near(MathUtil.safeDiv(null, 2.0, -1.0), -1.0, 1e-12)    // null num
            && near(MathUtil.safeDiv(10.0, 2.0, 0.0), 5.0, 1e-12);     // normal path
    }

    (:test)
    function testClampScrubsInfinity(logger) {
        // #9-safe: use the runtime posInf() helper, never an out-of-range literal.
        var pinf = posInf();
        var ninf = -pinf;
        return near(MathUtil.clamp(pinf, 0.0, 100.0), 100.0, 1e-6)     // +Inf-magnitude -> hi
            && near(MathUtil.clamp(ninf, 0.0, 100.0),   0.0, 1e-6)     // -Inf-magnitude -> lo
            && near(MathUtil.clamp(42.0, 0.0, 100.0),  42.0, 1e-6);    // in-range passthrough
    }

    (:test)
    function testOlsDegenerateDenominator(logger) {
        // all-equal x -> denom = n·Σx² - (Σx)² = 0 -> safe [0,0], no divide-by-zero
        var r = MathUtil.olsSlopeR2([3.0,3.0,3.0,3.0], [1.0,2.0,3.0,4.0]);
        return near(r[0], 0.0, 1e-12) && near(r[1], 0.0, 1e-12);
    }

    (:test)
    function testFallingSigmoidClampsExpOverflow(logger) {
        // far below P_AeT the exponent saturates -> ~a0; far above -> ~a0-a1; both
        // stay finite and bounded (no exp overflow).
        var lo = MathUtil.fallingSigmoid(-100000.0, 200.0, 1.0, 0.5, 0.02);
        var hi = MathUtil.fallingSigmoid( 100000.0, 200.0, 1.0, 0.5, 0.02);
        return MathUtil.isFinite(lo) && MathUtil.isFinite(hi)
            && near(lo, 1.0, 1e-6) && near(hi, 0.5, 1e-6);
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
        return xn[0] == 1.0 && xn[1] == 2.0 && xn[2] == 3.0 && xn[3] == 4.0;
    }

    // ---- DfaAlpha1 cold-start / artifact ----
    (:test)
    function testDfaColdStartReturnsNeutral(logger) {
        // empty and under-filled (N < 2·boxMax) windows -> neutral [0,0,0], never NaN
        var empty = DfaAlpha1.compute([], 4, 16);
        var few = [];
        for (var i = 0; i < 20; i++) { few.add(800.0); }   // 20 < 32
        var short = DfaAlpha1.compute(few, 4, 16);
        return empty[0] == 0.0 && empty[2] == 0 && short[0] == 0.0 && short[2] == 0;
    }

    (:test)
    function testArtifactPercentTooFewBeats(logger) {
        // < 5 beats can't be trusted -> 100 % (forces α1 unavailable upstream)
        return near(DfaAlpha1.artifactPercent([], 0.05), 100.0, 1e-6)
            && near(DfaAlpha1.artifactPercent([800.0,800.0,800.0,800.0], 0.05), 100.0, 1e-6);
    }

    (:test)
    function testArtifactPercentFlagsSpike(logger) {
        // clean stationary series ~0 %; a lone doubled RR (missed beat) is caught
        var clean = []; var spiked = [];
        for (var i = 0; i < 12; i++) { clean.add(800.0); spiked.add(800.0); }
        spiked[6] = 1600.0;
        return near(DfaAlpha1.artifactPercent(clean, 0.05), 0.0, 1e-6)
            && DfaAlpha1.artifactPercent(spiked, 0.05) > 0.0;
    }

    // ---- TrainingLoadLedger guard paths ----
    (:test)
    function testTrimpGuardsHrMaxEqualsHrRest(logger) {
        // degenerate HR span (hrMax == hrRest) -> 0, no divide-by-zero
        return near(TrainingLoadLedger.trimpIncrement(150.0, 150.0, 150.0, 60.0, 0.64, 1.92), 0.0, 1e-12);
    }

    (:test)
    function testTssWithZeroFtp(logger) {
        // ftp == 0 -> IF via safeDiv falls back to 0 -> TSS 0, finite (never NaN)
        var tss = TrainingLoadLedger.tss(3600, 200.0, 0.0);
        return near(tss, 0.0, 1e-9) && MathUtil.isFinite(tss);
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
        return MathUtil.isFinite(filt.latentHr())
            && MathUtil.isFinite(filt.fState())
            && MathUtil.isFinite(filt.afiKalman())
            && MathUtil.isFinite(filt.latentA1())
            && !filt.isDegraded();
    }
}
