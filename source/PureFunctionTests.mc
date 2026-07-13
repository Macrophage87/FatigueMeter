using Toybox.Lang;
using Toybox.Test;
using Toybox.Math;

//! Off-device unit tests for the pure formula functions (generation prompt
//! deliverable §3). Run with the Connect IQ test runner:
//!     monkeydo bin/FatigueMeter.prg <device> -t
//!
//! These exercise coding correctness of each formula. The SEPARATE Python
//! model-consistency harness (docs/prompts/scientific-validation-prompt.md)
//! checks behaviour against the documented model — that is regression protection,
//! not external validity.
module PureFunctionTests {

    function near(a, b, tol) {
        var d = a - b;
        if (d < 0) { d = -d; }
        return d <= tol;
    }

    (:test)
    function testNormalizedPowerConstant(logger) {
        // constant 200 W -> NP = 200
        var p = [200.0, 200.0, 200.0, 200.0];
        var np = PrimitivesCalculator.normalizedPower(p);
        return near(np, 200.0, 0.001);
    }

    (:test)
    function testNormalizedPowerVariable(logger) {
        // NP of [100,300] 4th-root of mean of 4th powers > mean(200)
        var np = PrimitivesCalculator.normalizedPower([100.0, 300.0]);
        return np > 200.0 && np < 300.0;
    }

    (:test)
    function testDecouplingIdentity(logger) {
        // EF drops 10% -> decoupling ~10%
        var d = PrimitivesCalculator.decouplingPct(2.0, 1.8);
        return near(d, 10.0, 0.001);
    }

    (:test)
    function testWeightForPower(logger) {
        var wBelow = PrimitivesCalculator.weightForPower(200.0, 250.0);
        var wAt2x = PrimitivesCalculator.weightForPower(500.0, 250.0);
        return near(wBelow, 1.0, 0.001) && near(wAt2x, 3.0, 0.001);
    }

    (:test)
    function testWprimeDepletionRecovery(logger) {
        // above CP depletes; below CP recovers
        var w = 20000.0;
        var depleted = PrimitivesCalculator.wprimeBalStep(w, 400.0, 250.0, 20000.0, 1.0);
        var recovered = PrimitivesCalculator.wprimeBalStep(depleted, 100.0, 250.0, 20000.0, 1.0);
        return depleted < w && recovered > depleted;
    }

    (:test)
    function testTssOneHourFtp(logger) {
        // 1 h at FTP -> ~100 TSS
        var tss = TrainingLoadLedger.tss(3600, 250.0, 250.0);
        return near(tss, 100.0, 0.01);
    }

    (:test)
    function testTsbIdentity(logger) {
        // TSB == CTL - ATL exactly
        var tsb = TrainingLoadLedger.tsbFrom(80.0, 95.0);
        return near(tsb, -15.0, 0.0000001);
    }

    (:test)
    function testEwmaFold(logger) {
        // CTL fold toward a higher load rises
        var next = TrainingLoadLedger.ewmaFold(70.0, 200.0, 42.0);
        return next > 70.0 && next < 200.0;
    }

    (:test)
    function testTrimpPositive(logger) {
        var t = TrainingLoadLedger.trimpIncrement(150.0, 50.0, 190.0, 60.0, 0.64, 1.92);
        return t > 0.0 && MathUtil.isFinite(t);
    }

    (:test)
    function testAfiBounds(logger) {
        var lo = AcuteFatigueFilter.afiFromF(-5.0, 12.0);
        var hi = AcuteFatigueFilter.afiFromF(999.0, 12.0);
        return near(lo, 0.0, 0.001) && near(hi, 100.0, 0.001);
    }

    (:test)
    function testBlendContinuity(logger) {
        // full RR weight -> pure kalman; zero -> pure decoupling
        var k = AcuteFatigueFilter.blendAfi(80.0, 20.0, 1.0);
        var d = AcuteFatigueFilter.blendAfi(80.0, 20.0, 0.0);
        return near(k, 80.0, 0.001) && near(d, 20.0, 0.001);
    }

    (:test)
    function testRrWeight(logger) {
        // artifact at good -> 1 ; at gate -> 0
        var wGood = AcuteFatigueFilter.rrWeight(1.0, 1.0, 5.0);
        var wGate = AcuteFatigueFilter.rrWeight(5.0, 1.0, 5.0);
        return near(wGood, 1.0, 0.001) && near(wGate, 0.0, 0.001);
    }

    (:test)
    function testChargeGradedAndActiveGated(logger) {
        // charge larger above AeT; kappa_d only while active
        var above = AcuteFatigueFilter.chargeTerm(320.0, 240.0, 0.0016, 0.00035, true);
        var below = AcuteFatigueFilter.chargeTerm(150.0, 240.0, 0.0016, 0.00035, true);
        var coasting = AcuteFatigueFilter.chargeTerm(150.0, 240.0, 0.0016, 0.00035, false);
        return above > below && below > coasting && near(coasting, 0.0, 1e-9);
    }

    (:test)
    function testA1TargetFalling(logger) {
        // The A1_target sigmoid must cross the 0.75 AeT anchor AT P_AeT and fall
        // with power. Use the shipped a0/a1 (1.0/0.5) so this validates the
        // CORRECTED sigmoid, not the retired 1.1/0.6 (which crossed 0.80).
        var cfg = new Config();
        var atAet = AcuteFatigueFilter.a1Target(cfg.pAeT, cfg.pAeT, cfg.a0, cfg.a1, cfg.sigmoidS);
        var high = AcuteFatigueFilter.a1Target(cfg.pAeT + 120, cfg.pAeT, cfg.a0, cfg.a1, cfg.sigmoidS);
        return near(atAet, 0.75, 0.001) && high < atAet;
    }

    (:test)
    function testDfaOnCorrelatedSeries(logger) {
        // a smooth (correlated) RR series should give α1 well above 0.5
        var rr = [];
        var base = 900.0;
        for (var i = 0; i < 200; i++) {
            base += (i % 7) - 3;               // slow wander -> correlated
            rr.add(base);
        }
        var res = DfaAlpha1.compute(rr, 4, 16);
        return res[0] > 0.5 && MathUtil.isFinite(res[0]);
    }

    (:test)
    function testRrStalenessMarksAlpha1Unavailable(logger) {
        // §8.4 staleness timer: with fresh RR, α1 is usable; once RR has been
        // silent for > RR_STALE_S the α1 tile must go UNAVAILABLE (not keep
        // emitting a stale value off the aged buffer).
        var cfg = new Config();
        var prims = new PrimitivesCalculator(cfg);
        var t = 0;
        for (var s = 0; s < 130; s++) {          // ~130 s of gently-varying RR
            t += 1;
            var a = 560 + (t * 13) % 80;         // 560..639 ms, low-artifact variation
            var b = 560 + (t * 29) % 80;
            prims.update(200, 130, 90, [a, b], t);
        }
        var withRr = prims.alpha1Metric();       // fresh RR -> usable
        for (var s = 0; s < 15; s++) {           // RR goes silent for > 10 s
            t += 1;
            prims.update(200, 130, 90, null, t);
        }
        var stale = prims.alpha1Metric();        // must now be unavailable
        return withRr.isUsable() && !stale.isPresent();
    }

    (:test)
    function testKalmanUpdateMovesState(logger) {
        // a scalar HR update pulls the HR state toward the measurement
        var x = [0.0, 100.0, 0.75, 0.0];
        var P = KalmanMath.zeros4x4();
        P[1][1] = 25.0;
        var H = [0.0, 1.0, 0.0, 0.0];
        var r = KalmanMath.scalarUpdate(x, P, H, 120.0, 4.0);
        var xn = r[0];
        return xn[1] > 100.0 && xn[1] < 120.0;
    }

    (:test)
    function testAlpha1CouplesIntoF(logger) {
        // Structural fusion check (harness §2): an α1 BELOW A1_target must move F.
        var cfg = new Config();
        var filt = new AcuteFatigueFilter(cfg);
        // run steady power with α1 pinned well below its power-predicted target
        var lowA1 = AcuteFatigueFilter.a1Target(cfg.pAeT, cfg.pAeT, cfg.a0, cfg.a1, cfg.sigmoidS) - 0.3;
        var m = Signals.Metric.ok(lowA1, 1.0);
        var f0 = filt.fState();
        for (var i = 0; i < 120; i++) {
            filt.step(cfg.pAeT, 140.0, m, 0.0, 0.2, true, true);
        }
        return filt.fState() > f0;   // α1 innovation genuinely informed F
    }

    (:test)
    function testObservabilityFNonDegenerate(logger) {
        // §4.3a: F must be observable (non-degenerate Gramian) under the model,
        // because it couples into both HR and (via −c_F) the α1 channel.
        var cfg = new Config();
        var dtHr = 1.0 / cfg.tauHr; var dtA = 1.0 / cfg.tauA; var dtRec = 1.0 / cfg.tauRec;
        var A = KalmanMath.zeros4x4();
        A[1][0] = dtHr; A[1][1] = 1.0 - dtHr; A[1][3] = dtHr;
        A[2][2] = 1.0 - dtA; A[2][3] = -dtA * cfg.cF;
        A[3][3] = 1.0 - dtRec;
        var Hrows = [ [0.0,1.0,0.0,0.0], [0.0,0.0,1.0,0.0] ];
        var r = KalmanMath.observabilityCheck(A, Hrows);
        return r[:observable] && r[:detGram] > 0.0 && r[:fEnergy] > 0.0;
    }

    (:test)
    function testFatigueBucket(logger) {
        var fresh = AcuteFatigueFilter.fatigueBucket(0.0, 12.0);   // AFI 0
        var mod = AcuteFatigueFilter.fatigueBucket(6.0, 12.0);     // AFI 50
        var heavy = AcuteFatigueFilter.fatigueBucket(11.0, 12.0);  // AFI ~92
        return fresh.equals("fresh") && mod.equals("moderate") && heavy.equals("heavy");
    }

    (:test)
    function testDeltaBucket(logger) {
        var small = AcuteFatigueFilter.deltaBucket(1.0, 12.0);
        var large = AcuteFatigueFilter.deltaBucket(10.0, 12.0);
        return small.equals("small") && large.equals("large");
    }

    (:test)
    function testRecoveryRelaxesF(logger) {
        // §4.4 / harness: on a coast (inactive, low power) F must NOT increase.
        var cfg = new Config();
        var filt = new AcuteFatigueFilter(cfg);
        // charge F up first with an active hard effort
        for (var i = 0; i < 300; i++) {
            filt.step(cfg.pAeT + 80.0, 160.0, null, 100.0, 0.0, true, true);
        }
        var fCharged = filt.fState();
        // now coast: inactive, no power, and HR dropped out (predict-only) so the
        // test isolates the charge/decay dynamics from the HR-innovation confound.
        // κ_d is gated off (inactive) -> F must decay via τ_rec.
        for (var j = 0; j < 300; j++) {
            filt.step(0.0, null, null, 100.0, 0.0, false, true);
        }
        return filt.fState() < fCharged;
    }

    (:test)
    function testRespirationDoesNotManufactureFatigue(logger) {
        // harness §2: isolate the α1 channel — two filters with IDENTICAL power/HR
        // (so the HR-driven F is identical), differing only in fB. With rapid fB,
        // R_A1 inflates so the α1-below-target excursion moves F LESS than with
        // stable fB.
        var cfg = new Config();
        var stable = new AcuteFatigueFilter(cfg);
        var rapid = new AcuteFatigueFilter(cfg);
        var a1v = AcuteFatigueFilter.a1Target(cfg.pAeT, cfg.pAeT, cfg.a0, cfg.a1, cfg.sigmoidS) - 0.3;
        var m = Signals.Metric.ok(a1v, 1.0);
        var fb = 0.25;
        for (var i = 0; i < 60; i++) {
            var fbRapid = fb + 0.15;             // large |Δfb| every step
            stable.step(cfg.pAeT, 140.0, m, 0.0, 0.25, true, true);
            rapid.step(cfg.pAeT, 140.0, m, 0.0, fbRapid, true, true);
            fb = fbRapid;
        }
        return rapid.fState() < stable.fState();
    }
}
