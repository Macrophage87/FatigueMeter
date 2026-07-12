using Toybox.Lang;
using Toybox.Math;

//! LAYER 2 — Acute fatigue estimator (white paper §4).
//!
//! A 4-state LINEAR (time-varying) Kalman filter over x = [HR_ss, HR, A1, F]ᵀ.
//! It is a LINEAR KF, not an EKF: every nonlinearity (A1_target(P), the
//! max(0,P−P_AeT) hinge, g_P·P) is a function of the MEASURED input P and enters
//! as a known additive input term u(k); the coupling −c_F·F and recovery −F/τ_rec
//! are linear in the state. No Jacobians.
//!
//! HONESTY (§4.3a, §4.4): on constant-power rides F is weakly observable and
//! prior-dominated (reflects κ tuning, not an independent measurement). HR and α1
//! innovations share drivers (heat, respiration), so the diagonal-R assumption is
//! optimistic — R is inflated and AFI's internal uncertainty is a LOWER BOUND.
//! α1 measurement noise is inflated on rapid-fB / high-artifact windows so
//! respiration-/artifact-driven α1 excursions cannot manufacture fatigue.
class AcuteFatigueFilter {

    // state indices
    enum { S_HRSS = 0, S_HR = 1, S_A1 = 2, S_F = 3 }

    hidden var x;      // Array[4]
    hidden var P;      // 4x4
    hidden var cfg;
    hidden var initialized;
    hidden var seedF;
    hidden var lastFb;
    hidden var priorDominated;   // true when input excitation is low (steady power)
    hidden var dominantRr;       // true when Kalman/RR source dominates the AFI blend
    hidden var lastDominantRr;
    hidden var sourceSwitched;

    function initialize(config) {
        cfg = config;
        initialized = false;
        seedF = 0.0;
        lastFb = 0.0;
        priorDominated = true;
        dominantRr = false;
        lastDominantRr = false;
        sourceSwitched = false;
        x = [0.0, 0.0, Constants.AET_ALPHA1, 0.0];
        P = KalmanMath.zeros4x4();
        lastPower = 0.0;
    }

    function setConfig(config) { cfg = config; }

    //! Seed F(0) from the Layer-3 residual state at ride start (§7). The athlete
    //! starts partly fatigued when carrying load.
    function seedFromLayer3(f0) {
        seedF = MathUtil.clamp(f0, 0.0, cfg.fRef);
    }

    hidden function initState(hr, alpha1) {
        var hr0 = (hr != null && hr > 0) ? hr.toFloat() : (cfg.hrRest + 20.0);
        var a10 = (alpha1 != null && alpha1 > 0) ? alpha1 : Constants.AET_ALPHA1;
        x = [ cfg.hrRest + cfg.gP * 0.0, hr0, a10, seedF ];
        P = KalmanMath.zeros4x4();
        P[S_HRSS][S_HRSS] = Constants.P0_HR;
        P[S_HR][S_HR] = Constants.P0_HRLAT;
        P[S_A1][S_A1] = Constants.P0_A1;
        P[S_F][S_F] = Constants.P0_F;
        initialized = true;
    }

    // =====================================================================
    //  PURE STATIC PIECES (unit-testable)
    // =====================================================================

    //! A1_target(P): falling sigmoid crossing 0.75 at P_AeT (white paper §4.2).
    static function a1Target(p, pAeT, a0, a1, s) {
        return MathUtil.fallingSigmoid(p, pAeT, a0, a1, s);
    }

    //! Graded intensity+duration charge (white paper §4.2). κ_d charges ONLY while
    //! active (pedaling / HR>rest), so F relaxes on recovery/coasting/stops.
    static function chargeTerm(p, pAeT, kappaI, kappaD, active) {
        var intensity = kappaI * ((p > pAeT) ? (p - pAeT) : 0.0);
        var duration = active ? kappaD : 0.0;
        return intensity + duration;
    }

    //! AFI from F: 100·clamp(F/F_ref, 0, 1). An index, not a measurement (§4.5).
    static function afiFromF(f, fRef) {
        return 100.0 * MathUtil.clamp(MathUtil.safeDiv(f, fRef, 0.0), 0.0, 1.0);
    }

    //! Decoupling-only AFI on the common F_ref-equivalent scale (§4.5).
    static function afiFromDecoupling(decoupPct, decoupRef) {
        return 100.0 * MathUtil.clamp(MathUtil.safeDiv(decoupPct, decoupRef, 0.0), 0.0, 1.0);
    }

    //! RR-quality weight w_rr in [0,1] (§4.5): 1 at artifact_good, 0 at the gate.
    static function rrWeight(artifactPct, artifactGood, artifactGate) {
        var span = artifactGate - artifactGood;
        if (span <= 1.0e-6) { return 0.0; }
        return MathUtil.clamp((artifactGate - artifactPct) / span, 0.0, 1.0);
    }

    //! Continuous blend, reference-consistent so start/now ticks stay comparable
    //! across RR-quality transitions (§4.5).
    static function blendAfi(afiKalman, afiDecoup, wRr) {
        return wRr * afiKalman + (1.0 - wRr) * afiDecoup;
    }

    // =====================================================================
    //  1 Hz STEP
    // =====================================================================

    //! Advance the filter one second.
    //!   power        : Float or null (no power -> power input terms held / flagged)
    //!   hr           : Float or null (no HR -> predict-only, F coasts, P grows)
    //!   alpha1Metric : Signals.Metric for α1 (null-usable -> drop the α1 update)
    //!   artifactPct  : current RR artifact %
    //!   fbNow        : respiratory frequency (Hz) for R_A1 inflation
    //!   active       : pedaling / HR>rest (gates κ_d)
    //!   stationary   : within-window power stationary (excitation for observability)
    function step(power, hr, alpha1Metric, artifactPct, fbNow, active, stationary) {
        if (!initialized) {
            var a1seed = (alpha1Metric != null && alpha1Metric.isUsable()) ? alpha1Metric.value : null;
            initState(hr, a1seed);
        }

        var p = (power != null && power >= 0) ? power.toFloat() : lastKnownPower();
        if (power != null && power >= 0) { lastPower = power.toFloat(); }
        priorDominated = stationary;   // steady power -> F is prior-dominated (§4.3a)

        // ---- build linear transition A and input u for this P ----
        var dtHr = 1.0 / cfg.tauHr;
        var dtA = 1.0 / cfg.tauA;
        var dtRec = 1.0 / cfg.tauRec;

        var A = KalmanMath.zeros4x4();
        // HR_ss row: deterministic from input (no dependence on prior state)
        A[S_HRSS][S_HRSS] = 0.0;
        // HR row: HR' = dtHr·HR_ss + (1-dtHr)·HR + dtHr·F
        A[S_HR][S_HRSS] = dtHr;
        A[S_HR][S_HR] = 1.0 - dtHr;
        A[S_HR][S_F] = dtHr;
        // A1 row: A1' = (1-dtA)·A1 − dtA·c_F·F   (+ input dtA·A1_target)
        A[S_A1][S_A1] = 1.0 - dtA;
        A[S_A1][S_F] = -dtA * cfg.cF;
        // F row: F' = (1-dtRec)·F   (+ input charge)
        A[S_F][S_F] = 1.0 - dtRec;

        var hrSsInput = cfg.hrRest + cfg.gP * p;
        var a1tgt = a1Target(p, cfg.pAeT, cfg.a0, cfg.a1, cfg.sigmoidS);
        var charge = chargeTerm(p, cfg.pAeT, cfg.kappaI, cfg.kappaD, active);
        var u = [ hrSsInput, 0.0, dtA * a1tgt, charge ];

        var qDiag = [cfg.qHr, cfg.qHrLat, cfg.qA1, cfg.qF];

        // ---- PREDICT ----
        var pr = KalmanMath.predict(x, P, A, u, qDiag);
        x = pr[0]; P = pr[1];

        // ---- UPDATE: HR channel (skip if HR missing -> predict-only) ----
        if (hr != null && hr > 0) {
            var Hhr = [0.0, 1.0, 0.0, 0.0];
            var up = KalmanMath.scalarUpdate(x, P, Hhr, hr.toFloat(), cfg.rHr);
            x = up[0]; P = up[1];
        }

        // ---- UPDATE: α1 channel (drop if RR poor; inflate R on fB/artifact) ----
        if (alpha1Metric != null && alpha1Metric.isUsable()) {
            var rA1 = effectiveRA1(artifactPct, fbNow);
            var Ha1 = [0.0, 0.0, 1.0, 0.0];
            var up2 = KalmanMath.scalarUpdate(x, P, Ha1, alpha1Metric.value, rA1);
            x = up2[0]; P = up2[1];
        }
        lastFb = fbNow;

        // keep F physically bounded (never negative; cap at wide 3·F_ref)
        x[S_F] = MathUtil.clamp(x[S_F], 0.0, 3.0 * cfg.fRef);
        x[S_A1] = MathUtil.clamp(x[S_A1], 0.1, 1.8);
    }

    //! Inflate R_A1 when respiration changes rapidly or artifact is elevated
    //! (white paper §4.4) — wires the fB/artifact de-weighting INTO the filter so
    //! respiration-/artifact-driven α1 excursions contribute little to F.
    hidden function effectiveRA1(artifactPct, fbNow) {
        var r = cfg.rA1;
        // artifact inflation: scale up as artifact approaches the gate
        var artFactor = 1.0 + 4.0 * MathUtil.clamp(artifactPct / cfg.artifactGate, 0.0, 2.0);
        // rapid-fB inflation: |Δfb| between recomputes
        var dFb = fbNow - lastFb;
        if (dFb < 0) { dFb = -dFb; }
        var fbFactor = 1.0 + 6.0 * MathUtil.clamp(dFb / 0.1, 0.0, 3.0);   // 0.1 Hz ~ meaningful
        // shared-driver overconfidence -> keep R a LOWER-BOUND-safe inflation (×1.5 floor)
        return r * artFactor * fbFactor * 1.5;
    }

    hidden var lastPower;
    hidden function lastKnownPower() {
        if (lastPower == null) { lastPower = 0.0; }
        return lastPower;
    }

    // =====================================================================
    //  OUTPUTS
    // =====================================================================

    function fState() { return initialized ? x[S_F] : seedF; }
    function latentHr() { return initialized ? x[S_HR] : 0.0; }
    function latentA1() { return initialized ? x[S_A1] : Constants.AET_ALPHA1; }

    //! Kalman-only AFI (index 0..100).
    function afiKalman() {
        return afiFromF(fState(), cfg.fRef);
    }

    //! Final AFI: continuous RR-quality blend of Kalman and decoupling-only (§4.5).
    //! Also latches whether the dominant source switched this step (dial marker).
    function afiBlended(decoupPct, artifactPct) {
        var wRr = rrWeight(artifactPct, Constants.ARTIFACT_GOOD, cfg.artifactGate);
        var afiK = afiKalman();
        var afiD = afiFromDecoupling(decoupPct, Constants.DECOUP_REF);
        dominantRr = (wRr >= 0.5);
        sourceSwitched = (dominantRr != lastDominantRr);
        lastDominantRr = dominantRr;
        return blendAfi(afiK, afiD, wRr);
    }

    //! AFI uncertainty (std, index points) from the F covariance, scaled to the
    //! 0..100 index. Widens during predict-only gaps (§8.4). Treated as a LOWER
    //! BOUND on true uncertainty (correlated channels — §4.4).
    function afiUncertainty() {
        if (!initialized) { return 100.0; }
        var varF = P[S_F][S_F];
        if (varF < 0) { varF = 0; }
        var sd = Math.sqrt(varF);
        return MathUtil.clamp(100.0 * sd / cfg.fRef, 0.0, 100.0);
    }

    function isPriorDominated() { return priorDominated; }
    function dominantSourceIsRr() { return dominantRr; }
    function didSourceSwitch() { return sourceSwitched; }
    function isInitialized() { return initialized; }
}
