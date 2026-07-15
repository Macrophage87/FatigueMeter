using Toybox.Lang;
using Toybox.Application;
using Toybox.Application.Properties;

//! Live settings snapshot, read from Application.Properties with white-paper
//! defaults as fallback. Loaded once at start and refreshed on onSettingsChanged.
//!
//! This is where the honesty requirement is enforced mechanically: every value
//! §9 flags "convention"/"synthesis" is a *property*, so the harness can prove
//! that changing the setting changes behaviour (it is not hard-coded).
class Config {

    // profile
    var ftp; var cp; var wPrime; var hrMax; var hrRest; var sexFemale;
    // filter
    var tauHr; var tauA; var tauRec; var kappaI; var kappaD; var cF; var fRef;
    var a0; var a1; var sigmoidS; var gP;
    var qHr; var qHrLat; var qA1; var qF; var rHr; var rA1;
    // bands
    var decoupOk; var decoupCaution; var decoupHigh; var artifactGate;
    var powerCvGate; var coastFracGate; var kjAnchor;
    var afiFresh; var afiBuilding; var afiDriftMargin; var decoupRef;
    // feat/attrition weights (synthesis §8.2)
    var featWSev; var featMatchW; var featBestW; var attrDriftW;
    // load (per-ride TRIMP coefficient; cross-ride CTL/ATL/TSB removed — Rev 5)
    var trimpFemaleCoeff;
    // honesty
    var positivePilot; var shipNumberOverride; var unitsMetric;
    // derived
    var pAeT;

    function initialize() {
        reload();
    }

    // ---- Input sanitisation (issue #6) -------------------------------------
    // Single-point guards for every setting that becomes a denominator or a
    // decay/gain term. PUBLIC + STATIC so PureFunctionTests can drive them with
    // hostile inputs (a `hidden` member is unreachable from the test module).
    // MathUtil.clamp scrubs NaN and -Inf to the floor and +Inf/huge to VALID_MAX,
    // so routing through it also neutralises non-finite property values. These
    // are input-sanitisation floors, NOT physiological constants, so they live
    // here (not Constants.mc) and need no §9 traceability row.
    const VALID_MAX = 1.0e12;    // finite ceiling, far above any physical setting,
                                 // safely below MathUtil.clamp's 1e30 Inf threshold
    const MIN_HR_SPREAD = 20.0;  // TRIMP span & hrSs need a real HRmax-HRrest gap
    const HR_REST_FLOOR = 20.0;  // physiological minimum resting HR (bpm)

    //! Decay time-constant (s): floor at 1.0 so dt = 1/tau in (0,1], keeping the
    //! Kalman decay factor 1-dt in [0,1). Prevents tau=0 (dt=Inf -> NaN matrix)
    //! and 0<tau<1 (negative decay -> divergence).
    static function clampTau(raw) {
        return MathUtil.clamp(raw, 1.0, VALID_MAX);
    }

    //! Strictly-positive denominator / gain with a physical floor.
    static function clampPositive(raw, floor) {
        return MathUtil.clamp(raw, floor, VALID_MAX);
    }

    //! Artifact gate: must sit strictly above ARTIFACT_GOOD (=1.0) so the
    //! RR-quality span (gate - good) in rrWeight() is positive and the
    //! artifactPct/gate scale in effectiveRA1() is well-defined.
    static function clampGate(raw) {
        return MathUtil.clamp(raw, Constants.ARTIFACT_GOOD + 0.5, VALID_MAX);
    }

    //! Validate the HR pair. Returns [rest, max]. If either input is non-finite,
    //! rest is sub-physiological, or the span is too small (including a swapped
    //! rest>=max pair), reset BOTH to the documented defaults. A swapped/degenerate
    //! pair is still a misconfiguration, so the honest fallback is the default,
    //! not a silent swap.
    static function validatedHr(rawRest, rawMax) {
        if (!MathUtil.isFinite(rawRest) || !MathUtil.isFinite(rawMax)
            || rawRest < HR_REST_FLOOR || (rawMax - rawRest) < MIN_HR_SPREAD) {
            return [50.0, 190.0];
        }
        return [rawRest, rawMax];
    }

    hidden function num(key, dflt) {
        var v = null;
        try {
            v = Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        if (v == null) { return dflt; }
        if (v instanceof Lang.Number || v instanceof Lang.Float
            || v instanceof Lang.Long || v instanceof Lang.Double) {
            return v;
        }
        return dflt;
    }

    hidden function bool(key, dflt) {
        var v = null;
        try {
            v = Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        if (v == null) { return dflt; }
        if (v instanceof Lang.Boolean) { return v; }
        return dflt;
    }

    function reload() {
        // Mandatory single-point input-sanitisation guard (issue #6): every
        // setting that becomes a denominator or a decay/gain term is clamped to a
        // finite, sane range here so no user misconfiguration can push Infinity,
        // NaN, a negative decay factor, or a zero denominator into the filter math.
        ftp      = clampPositive(num("ftp", 250).toFloat(), 1.0);
        cp       = clampPositive(num("cp", 240).toFloat(), 1.0);
        wPrime   = clampPositive(num("wPrime", 20000).toFloat(), 1.0);
        var hr   = validatedHr(num("hrRest", 50).toFloat(), num("hrMax", 190).toFloat());
        hrRest   = hr[0];
        hrMax    = hr[1];
        sexFemale = bool("sexFemale", false);

        tauHr    = clampTau(num("tauHr", Constants.TAU_HR).toFloat());
        tauA     = clampTau(num("tauA", Constants.TAU_A).toFloat());
        tauRec   = clampTau(num("tauRec", Constants.TAU_REC).toFloat());
        kappaI   = num("kappaI", Constants.KAPPA_I).toFloat();
        kappaD   = num("kappaD", Constants.KAPPA_D).toFloat();
        cF       = num("cF", Constants.C_F).toFloat();
        fRef     = clampPositive(num("fRef", Constants.F_REF).toFloat(), 0.1);
        a0       = num("a0", Constants.SIG_A0).toFloat();
        a1       = num("a1", Constants.SIG_A1).toFloat();
        sigmoidS = num("sigmoidS", Constants.SIG_S).toFloat();
        gP       = num("gP", Constants.G_P).toFloat();
        qHr      = num("qHr", Constants.Q_HR).toFloat();
        qHrLat   = num("qHrLat", Constants.Q_HRLAT).toFloat();
        qA1      = num("qA1", Constants.Q_A1).toFloat();
        qF       = num("qF", Constants.Q_F).toFloat();
        rHr      = num("rHr", Constants.R_HR).toFloat();
        rA1      = num("rA1", Constants.R_A1).toFloat();

        decoupOk      = num("decoupOk", Constants.DECOUP_OK).toFloat();
        decoupCaution = num("decoupCaution", Constants.DECOUP_CAUTION).toFloat();
        decoupHigh    = num("decoupHigh", Constants.DECOUP_HIGH).toFloat();
        artifactGate  = clampGate(num("artifactGate", 5.0).toFloat());
        powerCvGate   = num("powerCvGate", 0.10).toFloat();
        coastFracGate = num("coastFracGate", 0.10).toFloat();
        kjAnchor      = clampPositive(num("kjAnchor", 2000.0).toFloat(), 1.0);

        afiFresh      = num("afiFresh", Constants.AFI_FRESH_MAX).toFloat();
        afiBuilding   = num("afiBuilding", Constants.AFI_BUILDING_MAX).toFloat();
        afiDriftMargin = num("afiDriftMargin", 15.0).toFloat();
        decoupRef     = clampPositive(num("decoupRef", Constants.DECOUP_REF).toFloat(), 0.1);

        featWSev     = num("featWSev", 0.02).toFloat();
        featMatchW   = num("featMatchW", 40.0).toFloat();
        featBestW    = num("featBestW", 30.0).toFloat();
        attrDriftW   = num("attrDriftW", 100.0).toFloat();

        trimpFemaleCoeff = num("trimpFemaleCoeff", Constants.TRIMP_FEMALE_COEFF_DEFAULT).toFloat();

        positivePilot     = bool("positivePilot", false);
        shipNumberOverride = bool("shipNumberOverride", false);
        unitsMetric       = bool("unitsMetric", true);

        // Derived: aerobic threshold power ≈ 0.75·FTP (white paper §4.4).
        pAeT = 0.75 * ftp;
    }

    //! True when the precise numeric AFI / point start-now-end / projected tick
    //! may be shown (white paper §8.1 decision): gated on a positive pilot OR an
    //! explicitly-recorded pre-pilot override.
    function numericAfiUnlocked() {
        return positivePilot || shipNumberOverride;
    }
}
