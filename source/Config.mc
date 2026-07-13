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
        ftp      = num("ftp", 250).toFloat();
        cp       = num("cp", 240).toFloat();
        wPrime   = num("wPrime", 20000).toFloat();
        hrMax    = num("hrMax", 190).toFloat();
        hrRest   = num("hrRest", 50).toFloat();
        sexFemale = bool("sexFemale", false);

        tauHr    = num("tauHr", Constants.TAU_HR).toFloat();
        tauA     = num("tauA", Constants.TAU_A).toFloat();
        tauRec   = num("tauRec", Constants.TAU_REC).toFloat();
        kappaI   = num("kappaI", Constants.KAPPA_I).toFloat();
        kappaD   = num("kappaD", Constants.KAPPA_D).toFloat();
        cF       = num("cF", Constants.C_F).toFloat();
        fRef     = num("fRef", Constants.F_REF).toFloat();
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
        artifactGate  = num("artifactGate", 5.0).toFloat();
        powerCvGate   = num("powerCvGate", 0.10).toFloat();
        coastFracGate = num("coastFracGate", 0.10).toFloat();
        kjAnchor      = num("kjAnchor", 2000.0).toFloat();

        afiFresh      = num("afiFresh", Constants.AFI_FRESH_MAX).toFloat();
        afiBuilding   = num("afiBuilding", Constants.AFI_BUILDING_MAX).toFloat();
        afiDriftMargin = num("afiDriftMargin", 15.0).toFloat();
        decoupRef     = num("decoupRef", Constants.DECOUP_REF).toFloat();

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
