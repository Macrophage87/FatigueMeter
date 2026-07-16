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

    // α1 must fall at least this steeply with power for a usable crossing. Shared
    // by BOTH the acceptance gate and the pAeT computation so an accepted fit can
    // never leave pAeT at its 0.0 initializer -- the `slope<0.0` accept vs
    // `slope<-1e-9` crossing mismatch was the [-1e-9,0) "accepted with pAeT=0"
    // dead band (#12).
    const MIN_SLOPE = -1.0e-9;

    //! Fit from paired (power, alpha1) samples. Returns a dictionary:
    //!   :accepted bool (R²>0.75), :r2, :pAeT, :slope, :a0, :a1, :s
    function fitSigmoid(powers, alphas) {
        // Validate BOTH arrays: null, minimum length, AND equal length. Without
        // the alphas guard olsSlopeR2/mean can throw (null) or silently misalign
        // the fit against powers of a different length (#12).
        if (powers == null || alphas == null ||
            powers.size() < 8 || alphas.size() != powers.size()) {
            return { "accepted" => false, "r2" => 0.0 };
        }
        var res = MathUtil.olsSlopeR2(powers, alphas);
        var slope = res[0];
        var r2 = res[1];
        // intercept b = mean(alpha) - slope·mean(power)
        var mp = MathUtil.mean(powers);
        var ma = MathUtil.mean(alphas);
        var b = ma - slope * mp;

        // Single slope gate shared with the crossing below (no more dead band).
        var slopeOk = (slope < MIN_SLOPE);

        var pAeT = 0.0;
        var crossingOk = false;
        if (slopeOk) {
            pAeT = (Constants.AET_ALPHA1 - b) / slope;   // α1 crosses 0.75 here
            // The crossing must fall inside the sampled power range; a shallow but
            // valid slope can otherwise place AeT far outside where we measured.
            var range = rangeOf(powers);
            var pLo = range[0];
            var pHi = range[1];
            crossingOk = (pAeT >= pLo && pAeT <= pHi);
            pAeT = MathUtil.clamp(pAeT, pLo, pHi);       // defensive: never emit a wild/NaN AeT
        }

        // Accept only when R², slope, AND an in-range crossing all hold.
        var accepted = (r2 > Constants.DFA_R2_GATE) && slopeOk && crossingOk;

        // map linear slope onto the sigmoid slope parameter s (falling sigmoid's
        // derivative at centre ≈ -a1·s/4 ; solve s ≈ -4·slope/a1). NOTE: the SIG_A1
        // divisor is left unguarded here on purpose -- that hardening is owned by
        // #34 (SIG_A1 is a fixed nonzero constant today, so it is safe as-is).
        var a1 = Constants.SIG_A1;
        var s = -4.0 * slope / a1;
        if (s < 0.001) { s = 0.001; }

        return { "accepted" => accepted, "r2" => r2, "pAeT" => pAeT,
                 "slope" => slope, "a0" => Constants.SIG_A0, "a1" => a1, "s" => s };
    }

    //! [min, max] of a non-empty numeric array (single pass). Callers guarantee
    //! size >= 8 (the fitSigmoid guard), so arr[0] is safe.
    function rangeOf(arr) {
        var lo = arr[0];
        var hi = arr[0];
        for (var i = 1; i < arr.size(); i++) {
            var v = arr[i];
            if (v < lo) { lo = v; }
            if (v > hi) { hi = v; }
        }
        return [lo, hi];
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
