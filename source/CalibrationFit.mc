using Toybox.Lang;
using Toybox.Application.Storage;

//! Calibration (white paper §10). Fits the personal power→DFA-α1 map from a
//! ramp/step ride and gates acceptance on R² > 0.75; on failure the app falls
//! back to decoupling-only with α1 DISPLAY-ONLY (never silently using a
//! population sigmoid known to misfit ~44% of riders).
//!
//! NOTE (IMPLEMENTATION_NOTES): the full nonlinear sigmoid fit is approximated by
//! a linear fit of α1 vs P across the aerobic transition — sufficient to locate
//! the personal 0.75 crossing (AeT) and a slope, and to compute a fit R² for the
//! gate. Calibration tunes THRESHOLD CROSSINGS and self-consistency only; it does
//! NOT validate the latent F/AFI magnitude (there is no on-bike fatigue truth).
module CalibrationFit {

    const KEY = "fm_calib_v1";

    //! Fit from paired (power, alpha1) samples. Returns a dictionary:
    //!   :accepted bool (R²>0.75), :r2, :pAeT, :slope, :a0, :a1, :s
    function fitSigmoid(powers, alphas) {
        if (powers == null || powers.size() < 8) {
            return { "accepted" => false, "r2" => 0.0 };
        }
        var res = MathUtil.olsSlopeR2(powers, alphas);
        var slope = res[0];
        var r2 = res[1];
        // intercept b = mean(alpha) - slope·mean(power)
        var mp = MathUtil.mean(powers);
        var ma = MathUtil.mean(alphas);
        var b = ma - slope * mp;

        var accepted = (r2 > Constants.DFA_R2_GATE) && (slope < 0.0);
        var pAeT = 0.0;
        if (slope < -1.0e-9) {
            pAeT = (Constants.AET_ALPHA1 - b) / slope;   // α1 crosses 0.75 here
        }
        // map linear slope onto the sigmoid slope parameter s (falling sigmoid's
        // derivative at centre ≈ -a1·s/4 ; solve s ≈ -4·slope/a1)
        var a1 = Constants.SIG_A1;
        var s = -4.0 * slope / a1;
        if (s < 0.001) { s = 0.001; }

        return { "accepted" => accepted, "r2" => r2, "pAeT" => pAeT,
                 "slope" => slope, "a0" => Constants.SIG_A0, "a1" => a1, "s" => s };
    }

    function save(fit) {
        try { Storage.setValue(KEY, fit); } catch (e) { }
    }

    function load() {
        try { return Storage.getValue(KEY); } catch (e) { return null; }
    }

    //! True when an accepted personal calibration is stored.
    function isCalibrated() {
        var f = load();
        return (f instanceof Lang.Dictionary) && f.hasKey("accepted") && f["accepted"];
    }
}
