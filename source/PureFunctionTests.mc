using Toybox.Lang;
using Toybox.Test;
using Toybox.Math;
using Toybox.Ant;

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

    // NOTE (#14): testTsbIdentity / testEwmaFold below cover tsbFrom / ewmaFold,
    // which are RETAINED validated pure math but sit on NO shipped code path --
    // the field stopped folding cross-ride CTL/ATL/TSB on-device in Rev 5 (see the
    // TrainingLoadLedger header and Constants.mc). They are kept (not deleted) as a
    // guard on that retained library; this annotation keeps their scope honest so
    // they don't read as coverage of a live feature (and keeps ewmaFold's
    // "(unit-tested)" doc comment accurate).
    (:test)
    function testTsbIdentity(logger) {
        // TSB == CTL - ATL exactly. Rev-5 retained pure math -- not on any shipped path.
        var tsb = TrainingLoadLedger.tsbFrom(80.0, 95.0);
        return near(tsb, -15.0, 0.0000001);
    }

    (:test)
    function testEwmaFold(logger) {
        // CTL fold toward a higher load rises. Rev-5 retained pure math -- not shipped.
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
        // Charge F up first with an active hard effort. F is the residual HR
        // drift ABOVE the fresh-HR prediction (hrRest + gP*power ~= 170 bpm at
        // this power), so the measured HR must EXCEED that prediction for F to
        // build -- 160 bpm sits below it, keeps the innovation negative, and F
        // never charges (F stays 0, so the coast assertion is vacuously false).
        // Use 185 bpm (below hrMax 190): a physiologically consistent hard effort
        // that genuinely accumulates fatigue drift (surfaced by the #42 test run).
        for (var i = 0; i < 300; i++) {
            filt.step(cfg.pAeT + 80.0, 185.0, null, 100.0, 0.0, true, true);
        }
        var fCharged = filt.fState();
        // Guard against a silently-vacuous test: F MUST have actually charged, or
        // `fState() < fCharged` could pass/fail for the wrong reason if a future
        // gP/hrRest/pAeT change lifts the fresh-HR prediction back above 185 bpm.
        if (!(fCharged > 0.0)) { return false; }
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

    // =====================================================================
    //  #6 — Config input sanitisation (hostile-input guards)
    // =====================================================================

    // build a +Inf without a literal division (overflows Float range)
    function posInf() { var b = 9.0e37; return b * b; }

    (:test)
    function testClampTauFloorsDegenerate(logger) {
        // tau=0 (dt=Inf), 0<tau<1 (negative decay), negatives, NaN and +Inf all
        // clamp to a finite value >= 1.0; a legitimate tau passes through.
        var inf = posInf();
        var nan = inf - inf;
        var zero = Config.clampTau(0.0);
        var sub1 = Config.clampTau(0.5);
        var neg  = Config.clampTau(-5.0);
        var cNan = Config.clampTau(nan);
        var cInf = Config.clampTau(inf);
        var ok   = Config.clampTau(30.0);
        return zero >= 1.0 && sub1 >= 1.0 && neg >= 1.0
            && cNan >= 1.0 && MathUtil.isFinite(cNan)
            && MathUtil.isFinite(cInf)
            && near(ok, 30.0, 1e-9);
    }

    (:test)
    function testClampPositiveFloorsAndPasses(logger) {
        var inf = posInf();
        var nan = inf - inf;
        var ftpBad = Config.clampPositive(0.0, 1.0);
        var cpNeg  = Config.clampPositive(-240.0, 1.0);
        var wNan   = Config.clampPositive(nan, 1.0);
        var fRefZ  = Config.clampPositive(0.0, 0.1);
        var ftpOk  = Config.clampPositive(250.0, 1.0);
        return ftpBad >= 1.0 && cpNeg >= 1.0
            && wNan >= 1.0 && MathUtil.isFinite(wNan)
            && fRefZ >= 0.1
            && near(ftpOk, 250.0, 1e-6);
    }

    (:test)
    function testClampGateAboveGood(logger) {
        var g = Constants.ARTIFACT_GOOD;
        var zero = Config.clampGate(0.0);
        var atGood = Config.clampGate(1.0);
        var ok = Config.clampGate(5.0);
        return zero > g && atGood > g && near(ok, 5.0, 1e-6);
    }

    (:test)
    function testValidatedHrResetsDegeneratePairs(logger) {
        var inf = posInf();
        var swapped   = Config.validatedHr(60.0, 55.0);   // rest >= max
        var tooTight  = Config.validatedHr(180.0, 190.0); // span 10 < 20
        var subFloor  = Config.validatedHr(5.0, 190.0);   // rest below floor
        var nonFinite = Config.validatedHr(inf, 190.0);
        var normal    = Config.validatedHr(50.0, 190.0);
        return (swapped[1] - swapped[0]) >= 20.0
            && (tooTight[1] - tooTight[0]) >= 20.0
            && (subFloor[1] - subFloor[0]) >= 20.0
            && (nonFinite[1] - nonFinite[0]) >= 20.0
            && subFloor[0] >= 20.0
            && near(normal[0], 50.0, 1e-6) && near(normal[1], 190.0, 1e-6);
    }

    (:test)
    function testClampedTauKeepsTransitionFinite(logger) {
        // Mirror testObservabilityFNonDegenerate (:193-205) but feed HOSTILE taus
        // THROUGH clampTau: the transition matrix stays finite and every decay
        // factor 1-dt stays >= 0 (no divergence).
        var tauHr  = Config.clampTau(0.0);     // was Inf
        var tauA   = Config.clampTau(0.5);     // was negative decay
        var tauRec = Config.clampTau(-100.0);  // was negative
        var dtHr = 1.0 / tauHr; var dtA = 1.0 / tauA; var dtRec = 1.0 / tauRec;
        var A = KalmanMath.zeros4x4();
        A[1][0] = dtHr; A[1][1] = 1.0 - dtHr; A[1][3] = dtHr;
        A[2][2] = 1.0 - dtA; A[2][3] = -dtA * 0.0167;
        A[3][3] = 1.0 - dtRec;
        var finiteOk = MathUtil.isFinite(A[1][0]) && MathUtil.isFinite(A[1][1])
            && MathUtil.isFinite(A[2][2]) && MathUtil.isFinite(A[3][3]);
        var decayOk = (1.0 - dtHr) >= 0.0 && (1.0 - dtA) >= 0.0 && (1.0 - dtRec) >= 0.0;
        return finiteOk && decayOk;
    }

    // =====================================================================
    //  #7 — Normalized Power / ledger int^4 overflow regressions
    // =====================================================================

    (:test)
    function testNormalizedPowerConstantHighInt(logger) {
        // #7: constant integer 300 W (300^4 ~ 8.1e9, past the 2.147e9 int32 limit)
        // must give NP ~ 300 -> no overflow.
        var p = [300, 300, 300, 300, 300];   // INTEGERS on purpose
        var np = PrimitivesCalculator.normalizedPower(p);
        return near(np, 300.0, 0.001);
    }

    (:test)
    function testNormalizedPowerBoundary216Int(logger) {
        // #7: exactly the 216 W int32-overflow edge named in the issue.
        var np = PrimitivesCalculator.normalizedPower([216, 216, 216, 216]);
        return near(np, 216.0, 0.001);
    }

    (:test)
    function testNormalizedPowerHighIntVariable(logger) {
        // Mixed high integer power lands in a sane range (NP ~ 348.5) and stays finite.
        var np = PrimitivesCalculator.normalizedPower([250, 400, 250, 400]);
        return near(np, 348.5, 0.5) && MathUtil.isFinite(np);
    }

    (:test)
    function testNormalizedPowerNoOverflowVeryHigh(logger) {
        // Single 1000 W sprint (1000^4 = 1e12) with zeros must give NP ~ 707.1.
        // Assert the VALUE, not just > 0: a wrap that landed positive would pass a
        // bare "> 0" check on unfixed code.
        var np = PrimitivesCalculator.normalizedPower([1000, 0, 0, 0]);
        return near(np, 707.1, 0.5) && MathUtil.isFinite(np);
    }

    (:test)
    function testLedgerRideNpNoOverflowInt(logger) {
        // #7 ledger path: integer power >= 216 W through TrainingLoadLedger.update
        // must not overflow npSumPow4. Constant 300 W -> rideNp ~ 300 and a finite,
        // positive ride load (TSS). Tolerance is looser than the static NP tests
        // because npSumPow4 accumulates 600 single-precision Floats.
        var cfg = new Config();
        var ledger = new TrainingLoadLedger(cfg);
        for (var i = 0; i < 600; i++) {
            ledger.update(300, 150);         // INTEGER power on purpose
        }
        var np = ledger.rideNp();
        var load = ledger.rideLoad();
        return near(np, 300.0, 0.05) && MathUtil.isFinite(load) && load > 0.0;
    }

    // =====================================================================
    //  #8 — Kalman finite-safety (symmetrize scrub, S-guard, self-heal)
    // =====================================================================

    (:test)
    function testSymmetrizeScrubsNonFiniteDiagonal(logger) {
        var inf = posInf();   // runtime +Inf; literal 1.0e30*1.0e30 crashes 9.2.0 folder (#9)
        var nan = inf - inf;
        var P = KalmanMath.zeros4x4();
        P[0][0] = 5.0;
        P[2][2] = inf;
        P[3][3] = nan;
        KalmanMath.symmetrize(P);
        for (var i = 0; i < 4; i++) {
            for (var j = 0; j < 4; j++) {
                if (!MathUtil.isFinite(P[i][j])) { return false; }
            }
            if (P[i][i] < 1.0e-6) { return false; }
        }
        return true;
    }

    (:test)
    function testSymmetrizeScrubsNonFiniteOffDiagonal(logger) {
        var inf = posInf();   // runtime +Inf; literal 1.0e30*1.0e30 crashes 9.2.0 folder (#9)
        var P = KalmanMath.zeros4x4();
        P[0][3] = inf;   // avg (inf + 0)/2 = inf -> non-finite -> scrub both halves to 0
        P[3][0] = 0.0;
        KalmanMath.symmetrize(P);
        return MathUtil.isFinite(P[0][3]) && MathUtil.isFinite(P[3][0])
            && near(P[0][3], 0.0, 1e-12) && near(P[3][0], 0.0, 1e-12);
    }

    (:test)
    function testScalarUpdateNonFiniteSGuard(logger) {
        // Feed R = NaN (NOT +Inf). With +Inf the guard is vacuous: every gain
        // PHt[i]/S = finite/Inf = +0, so x/P stay finite even with the guard
        // removed. NaN is what actually exercises the !isFinite(S) branch: S =
        // R + H·PHt = NaN, and WITHOUT the guard the gains PHt[i]/NaN = NaN would
        // poison x (x[i] + NaN·innov = NaN). The result is finite here ONLY
        // because the guard skips the channel and returns [x, P] unchanged -> so
        // this assertion FAILS on pre-fix code and passes on the fixed code.
        var inf = posInf();   // runtime +Inf; literal 1.0e30*1.0e30 crashes 9.2.0 folder (#9)
        var nan = inf - inf;
        var x = [0.0, 100.0, 0.75, 0.0];
        var P = KalmanMath.zeros4x4();
        P[1][1] = 25.0;
        var H = [0.0, 1.0, 0.0, 0.0];
        var r = KalmanMath.scalarUpdate(x, P, H, 120.0, nan);   // R NaN -> S NaN -> skip
        return KalmanMath.isFiniteVector(r[0]) && KalmanMath.isFiniteMatrix(r[1]);
    }

    (:test)
    function testScalarUpdateKeepsPFiniteFromNonFiniteP(logger) {
        var inf = posInf();   // runtime +Inf; literal 1.0e30*1.0e30 crashes 9.2.0 folder (#9)
        var x = [0.0, 100.0, 0.75, 0.0];
        var P = KalmanMath.zeros4x4();
        P[1][1] = 25.0;
        // Off-diagonal Inf. In scalarUpdate PHt[0] += P[0][3]*H[3] = Inf*0 = NaN,
        // so S = NaN and the degenerate/non-finite S guard FIRES -- it is that
        // guard path's scrub (symmetrize a copy of P) that must return a finite P.
        P[0][3] = inf; P[3][0] = inf;
        var H = [0.0, 1.0, 0.0, 0.0];
        var r = KalmanMath.scalarUpdate(x, P, H, 120.0, 4.0);   // S=NaN -> guard scrubs P before skip
        return KalmanMath.isFiniteMatrix(r[1]) && KalmanMath.isFiniteVector(r[0]);
    }

    (:test)
    function testPredictKeepsPFiniteFromNonFiniteP(logger) {
        var inf = posInf();   // runtime +Inf; literal 1.0e30*1.0e30 crashes 9.2.0 folder (#9)
        var x = [0.0, 100.0, 0.75, 0.0];
        var P = KalmanMath.zeros4x4();
        P[0][0] = inf;                              // non-finite covariance entering predict
        var A = KalmanMath.zeros4x4();
        for (var i = 0; i < 4; i++) { A[i][i] = 1.0; }
        var r = KalmanMath.predict(x, P, A, [0.0,0.0,0.0,0.0], [1.0,1.0,1.0,1.0]);
        return KalmanMath.isFiniteMatrix(r[1]) && KalmanMath.isFiniteVector(r[0]);
    }

    (:test)
    function testIsFiniteVectorAndMatrix(logger) {
        var inf = posInf();   // runtime +Inf; literal 1.0e30*1.0e30 crashes 9.2.0 folder (#9)
        var vBad = [1.0, inf, 3.0, 4.0];
        var mBad = KalmanMath.zeros4x4();
        mBad[2][3] = inf - inf;                     // NaN
        return KalmanMath.isFiniteVector([1.0,2.0,3.0,4.0]) && !KalmanMath.isFiniteVector(vBad)
            && KalmanMath.isFiniteMatrix(KalmanMath.zeros4x4()) && !KalmanMath.isFiniteMatrix(mBad);
    }

    (:test)
    function testFilterSelfHealsFromNonFinitePower(logger) {
        // Public-API integration (review-required #3/#4): one +Inf power sample must
        // NOT latch. Control filter never sees it; injected filter gets +Inf at step
        // 30. With the isFinite(power) gate the +Inf is treated as missing (falls
        // back to lastKnownPower), so both trajectories stay finite, track together,
        // and neither degrades — i.e. the filter self-heals instead of flooring.
        var inf = posInf();   // runtime +Inf; literal 1.0e30*1.0e30 crashes 9.2.0 folder (#9)
        var cfg = new Config();
        var control  = new AcuteFatigueFilter(cfg);
        var injected = new AcuteFatigueFilter(cfg);
        var pw = cfg.pAeT + 80.0;
        for (var i = 0; i < 90; i++) {
            control.step(pw, 160.0, null, 100.0, 0.0, true, true);
            var pInj = (i == 30) ? inf : pw;        // single poisoned sample mid-ride
            injected.step(pInj, 160.0, null, 100.0, 0.0, true, true);
        }
        var finite = MathUtil.isFinite(injected.fState())
              && MathUtil.isFinite(injected.afiKalman())
              && MathUtil.isFinite(injected.latentHr());
        var tracks = near(injected.fState(), control.fState(), 0.5);   // +Inf was ignored
        return finite && tracks
            && !injected.isDegraded()               // prevention: never latched
            && !control.isDegraded();
    }

    (:test)
    function testFilterResetBranchScrubsNonFiniteState(logger) {
        // POSITIVE coverage for the self-heal RESET branch (§8.4). The prevention
        // test above only drives the isFinite(power) gate; the degraded=true +
        // x[S_HR]/x[S_HRSS] scrub branch is otherwise unreachable through the
        // public API (finite-input dynamics + clamps keep x finite). We use the
        // (:test)-only debugInjectNonFiniteState seam to poke a genuine NaN into
        // the HR state, then a single step() must trip the finite check, latch
        // isDegraded(), and scrub the poisoned component back to its safe seed.
        var inf = posInf();   // runtime +Inf; literal 1.0e30*1.0e30 crashes 9.2.0 folder (#9)
        var nan = inf - inf;
        var cfg = new Config();
        var filt = new AcuteFatigueFilter(cfg);
        // index 1 == S_HR (a NEVER-clamped state, the exact gap the branch guards)
        filt.debugInjectNonFiniteState(1, nan);
        filt.step(cfg.pAeT + 80.0, 160.0, null, 100.0, 0.0, true, true);
        // safe seed for HR states is cfg.hrRest + 20.0 (matches initState fallback)
        return filt.isDegraded()
            && MathUtil.isFinite(filt.latentHr())
            && near(filt.latentHr(), cfg.hrRest + 20.0, 1e-6)
            && MathUtil.isFinite(filt.fState())
            && MathUtil.isFinite(filt.afiKalman())
            && MathUtil.isFinite(filt.latentA1());
    }

    // ----------------------------------------------------------- Metric (#21)
    // The Metric "never carries NaN/Inf" invariant (§8.4): a non-finite value is
    // dropped to null + AVAIL_UNAVAILABLE at the single construction choke point,
    // isUsable()/isPresent() finiteness-gate (closing the public-var mutation
    // hole), and quality is clamped to [0,1]. Non-finite sentinels use the
    // runtime posInf() helper -- a literal like 1.0e40 is out of Monkey C Float
    // range and risks the SDK 9.2.0 constant-folder crash (#9).

    (:test)
    function testMetricRejectsNaNValue(logger) {
        // A NaN value must not yield a usable/present Metric; the tile greys out.
        var inf = posInf();
        var nan = inf - inf;                          // genuine NaN (NaN != NaN)
        var m = Signals.Metric.ok(nan, 1.0);
        return m.value == null
               && m.availability == Signals.AVAIL_UNAVAILABLE
               && !m.isUsable() && !m.isPresent();
    }

    (:test)
    function testMetricRejectsInfValue(logger) {
        // Non-finite magnitude is dropped just like NaN.
        var m = Signals.Metric.ok(posInf(), 1.0);
        return m.value == null
               && m.availability == Signals.AVAIL_UNAVAILABLE
               && !m.isUsable() && !m.isPresent();
    }

    (:test)
    function testMetricLowConfRejectsNonFinite(logger) {
        // The lowConf() factory (named in the issue) must also drop a non-finite
        // value -- a lowConf downgrade would otherwise RETAIN the NaN and
        // re-violate the invariant.
        var inf = posInf();
        var nan = inf - inf;
        var m = Signals.Metric.lowConf(nan, 0.5, "decoup");
        return m.value == null
               && m.availability == Signals.AVAIL_UNAVAILABLE
               && !m.isUsable() && !m.isPresent();
    }

    (:test)
    function testMetricClampsQuality(logger) {
        // quality is confidence in [0,1]; over/under-range and NaN are repaired,
        // and a finite value survives the quality scrub.
        var hi = Signals.Metric.ok(50.0, 2.5);        // -> 1.0
        var lo = Signals.Metric.ok(50.0, -0.5);       // -> 0.0
        var inf = posInf();
        var nanQ = Signals.Metric.ok(50.0, inf - inf); // NaN -> 0.0, value stays
        return near(hi.quality, 1.0, 1e-9)
               && near(lo.quality, 0.0, 1e-9)
               && near(nanQ.quality, 0.0, 1e-9)
               && nanQ.isUsable();                    // finite value must survive
    }

    (:test)
    function testMetricFiniteValuePreserved(logger) {
        // A valid finite value + in-range quality must pass through untouched.
        var m = Signals.Metric.ok(42.0, 0.8);
        return near(m.value, 42.0, 1e-9) && near(m.quality, 0.8, 1e-9)
               && m.isUsable() && m.isPresent();
    }

    (:test)
    function testMetricGuardsPostMutation(logger) {
        // Fields are public; a value mutated to NaN after construction must
        // still be rejected by isUsable()/isPresent().
        var m = Signals.Metric.ok(42.0, 1.0);
        var inf = posInf();
        m.value = inf - inf;                          // NaN injected past the ctor
        return !m.isUsable() && !m.isPresent();
    }

    (:test)
    function testViewDefaultSnapshotIsConservative(logger) {
        // #13: when View construction fails, the field must degrade to a SAFE,
        // HONEST NODATA snapshot -- numeric AFI LOCKED, "uncalibrated" tag, NODATA
        // status, max uncertainty -- never over-claiming. Lock those values (the
        // control flow itself isn't off-device testable; the defaults are).
        var s = FatigueMeterView.defaultSnapshot();
        return s[:status] == DescriptiveStrings.STATUS_NODATA
            && s[:numericUnlocked] == false
            && s[:calibrated] == false
            && s[:afi] == null
            && near(s[:afiUnc], 100.0, 1e-9)
            && s[:priorDominated] == true
            && s[:powerAvail] == false
            && s[:stationary] == false;
    }

    (:test)
    function testAntShouldReopenPredicate(logger) {
        // #47: the self-heal reopen DECISION extracted from AntHrm.onAntMessage as
        // a pure static predicate (AntHrm extends Ant.GenericChannel, so it can't
        // be constructed here -- same reason KalmanMath exposes a (:test) seam).
        // Cover every branch with synthetic ANT payloads.
        var closedEvt = [0, Ant.MSG_CODE_EVENT_CHANNEL_CLOSED];
        var otherEvt  = [0, 0xFF];   // some non-close response code
        var resp = Ant.MSG_ID_CHANNEL_RESPONSE_EVENT;
        return
            // the one reopen case: a genuine close event while NOT releasing
            AntHrm.shouldReopen(resp, closedEvt, false) == true
            // a deliberate release() raises the same close event -> suppressed
            && AntHrm.shouldReopen(resp, closedEvt, true) == false
            // a non-close response event never reopens
            && AntHrm.shouldReopen(resp, otherEvt, false) == false
            // a broadcast (data) message never reopens
            && AntHrm.shouldReopen(Ant.MSG_ID_BROADCAST_DATA, closedEvt, false) == false
            // malformed payloads are inert (null / too short)
            && AntHrm.shouldReopen(resp, null, false) == false
            && AntHrm.shouldReopen(resp, [0], false) == false;
    }

    // ================================================================
    //  Coverage sweep (#14) — StatusEvaluator, CalibrationFit, RingBuffer,
    //  and finite-safety guards for MathUtil / KalmanMath / DfaAlpha1 /
    //  TrainingLoadLedger, plus a null-sensor AcuteFatigueFilter.step assertion.
    //
    //  SCOPE (honest, per review): this closes the PURE / near-pure gaps only.
    //  7 of the 10 modules the issue named remain untested here because they need
    //  hardware or an integration harness, NOT this pure suite -- AntHrm (ANT
    //  channel; its pure shouldReopen predicate IS covered above), FitLogger
    //  (FitContributor), SessionStore + CalibrationFit.save/load (Application
    //  .Storage), FatigueMeterApp / FatigueMeterView (WatchUi lifecycle),
    //  DescriptiveStrings (resource bundle), EffortCharacterizer (follow-up).
    //  These execute under the #42 run-gate (monkeydo -t), not just at compile.
    // ================================================================

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
