using Toybox.Lang;
using Toybox.Application;
using Toybox.Application.Properties;

// ---- Input-sanitisation floors (issue #6) ---------------------------------
// Declared at MODULE scope (not inside class Config) so the STATIC clamp
// helpers below can reference them: a class-level `const` is only reachable
// from instance context, so neither a bare nor a `Config.`-qualified reference
// resolves from a static method. Module-scope symbols resolve bare from static
// methods. These are input-sanitisation floors, NOT physiological constants, so
// they live here (not Constants.mc) and need no §9 traceability row.
const VALID_MAX = 1.0e12;    // finite ceiling, far above any physical setting,
                             // safely below MathUtil.clamp's 1e30 Inf threshold
const MIN_HR_SPREAD = 20.0;  // TRIMP span & hrSs need a real HRmax-HRrest gap
const HR_REST_FLOOR = 20.0;  // physiological minimum resting HR (bpm)

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
    // so routing through it also neutralises non-finite property values. The
    // sanitisation floors themselves (VALID_MAX / MIN_HR_SPREAD / HR_REST_FLOOR)
    // are declared at module scope above so these static helpers can reach them.

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

    //! Clamp `value` up so it is never below `floor` — enforces band ordering (#29)
    //! so inverted user settings can't make a status band unreachable / a severity
    //! tier fire below the tier beneath it. Pure/(:test)-drivable.
    static function atLeast(value, floor) {
        return (value < floor) ? floor : value;
    }

    //! Order a 3-tier band ladder non-decreasing (#29): caution >= ok, then high >=
    //! the CLAMPED caution (not the raw one). Returns [ok, caution, high]. Pure so
    //! the chained clamp is (:test)-drivable — catches a clamp-against-raw / wrong-
    //! order mutant the atLeast unit test alone can't.
    static function orderBands(ok, caution, high) {
        caution = atLeast(caution, ok);
        high    = atLeast(high, caution);
        return [ok, caution, high];
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
        //
        // TEST-COVERAGE SEAM (acknowledged gap, PR #36 review pt 3): the clamp
        // helpers (clampTau/clampPositive/clampGate/validatedHr) are unit-tested
        // directly in PureFunctionTests, but their WIRING into this reload() block
        // is not — deleting a clamp CALL from a line below would leave every test
        // green. Kept as-is (the minimal faithful option) rather than adding a
        // parallel static `sanitize()` seam purely to be test-observable; the
        // assignments below are the single source of truth and must each route
        // their raw property through the matching helper. Reviewers changing a
        // line here own re-checking that the clamp call is preserved.
        ftp      = clampPositive(num("ftp", 250).toFloat(), 1.0);
        cp       = clampPositive(num("cp", 240).toFloat(), 1.0);
        wPrime   = clampPositive(num("wPrime", 20000).toFloat(), 1.0);
        var hr   = validatedHr(num("hrRest", 50).toFloat(), num("hrMax", 190).toFloat());
        hrRest   = hr[0];
        hrMax    = hr[1];
        sexFemale = bool("sexFemale", false);

        tauHr    = clampTau(num("tauHr", Constants.TAU_HR).toFloat());  // Bucket-C (#141) — still a knob
        tauA     = clampTau(num("tauA", Constants.TAU_A).toFloat());    // ADVANCED (#140): hidden from menu, property retained
        // FROZEN (#140): unobservable latent recovery τ — no on-bike ground truth to
        // fit against, ever (§10). Single source is the constant; clampTau() call
        // dropped (a constant needs no sanitisation), helper retained (unit-tested).
        tauRec   = Constants.TAU_REC;
        kappaI   = num("kappaI", Constants.KAPPA_I).toFloat();
        kappaD   = num("kappaD", Constants.KAPPA_D).toFloat();
        // DE-KNOBBED (#140): cF is not a user knob. Interim: read the C_F constant.
        // #141 will make cF fRef-DERIVED (cF = 0.2/fRef) so it recomputes when fRef
        // is calibrated — it must NOT freeze to a hand-set 0.0167 forever.
        cF       = Constants.C_F;
        fRef     = clampPositive(num("fRef", Constants.F_REF).toFloat(), 0.1);
        // FROZEN (#140): a0/a1 are UNFITTABLE — the runtime sigmoid consumes them
        // (AcuteFatigueFilter.a1Target) but CalibrationFit.fitSigmoid hard-codes
        // SIG_A0/SIG_A1 and never personalizes them, so no fit can move them.
        a0       = Constants.SIG_A0;
        a1       = Constants.SIG_A1;
        sigmoidS = num("sigmoidS", Constants.SIG_S).toFloat();
        gP       = num("gP", Constants.G_P).toFloat();
        // FROZEN (#140): Kalman process/measurement noise — hand-set, no on-bike
        // ground truth; process noise is under-determined, R is a sensor constant.
        qHr      = Constants.Q_HR;
        qHrLat   = Constants.Q_HRLAT;
        qA1      = Constants.Q_A1;
        qF       = Constants.Q_F;
        rHr      = Constants.R_HR;
        rA1      = Constants.R_A1;

        // FROZEN (#140): Friel/TrainingPeaks coaching convention. Single source is
        // the constant; the #29 orderBands() wiring is dropped (the frozen triple is
        // ordered by construction: 5 < 8 < 10) — helper retained (unit-tested).
        decoupOk      = Constants.DECOUP_OK;
        decoupCaution = Constants.DECOUP_CAUTION;
        decoupHigh    = Constants.DECOUP_HIGH;
        // ADVANCED (#140): hidden from menu, property retained. TIGHTEN-ONLY — a
        // sideloaded value may only LOWER the gate to [ARTIFACT_GOOD+0.5, DEFAULT]
        // (stricter/more honest), never raise it (a looser gate defeats the honesty
        // gate). Replaces clampGate() + the bare 5.0 literal.
        artifactGate  = MathUtil.clamp(num("artifactGate", Constants.ARTIFACT_GATE_DEFAULT).toFloat(),
                                       Constants.ARTIFACT_GOOD + 0.5, Constants.ARTIFACT_GATE_DEFAULT);
        // FROZEN (#140): validity-envelope gates — loosening only lets a user defeat
        // the honesty gate.
        powerCvGate   = Constants.POWER_CV_GATE;
        coastFracGate = Constants.COAST_FRAC_GATE;
        kjAnchor      = clampPositive(num("kjAnchor", 2000.0).toFloat(), 1.0);

        // FROZEN (#140): AFI display bands (convention). Single source is the
        // constant; the #29 atLeast() wiring is dropped (30 < 60 by construction) —
        // helper retained (unit-tested). Per-athlete adaptation still runs through
        // the AFI-drift baseline (margin below).
        afiFresh      = Constants.AFI_FRESH_MAX;
        afiBuilding   = Constants.AFI_BUILDING_MAX;
        afiDriftMargin = Constants.AFI_DRIFT_MARGIN;
        // ADVANCED (#140): hidden from menu, property retained. #141 should
        // AUTO-DERIVE decoupRef alongside fRef — its scale travels with fRef, so a
        // static manual toggle goes stale on recalibration.
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
