using Toybox.Lang;
using Toybox.Math;

//! Numeric helpers. Everything here is a PURE FUNCTION and must be finite-safe:
//! no divide-by-zero, no NaN/Inf ever leaks out (white paper §8.4). Callers in
//! the compute() loop rely on these never throwing.
module MathUtil {

    //! Clamp v to [lo, hi]. Also scrubs NaN/Inf to lo.
    function clamp(v, lo, hi) {
        if (!(v == v)) { return lo; }              // NaN check (NaN != NaN)
        if (v > 1.0e30 || v < -1.0e30) { return (v > 0) ? hi : lo; }
        if (v < lo) { return lo; }
        if (v > hi) { return hi; }
        return v;
    }

    //! Safe division: returns fallback when denominator is ~0 or inputs non-finite.
    function safeDiv(num, den, fallback) {
        if (den == null || num == null) { return fallback; }
        if (!(den == den) || !(num == num)) { return fallback; }
        if (den > -1.0e-9 && den < 1.0e-9) { return fallback; }
        var r = num.toFloat() / den.toFloat();
        if (!(r == r)) { return fallback; }
        return r;
    }

    //! True when v is a finite real number.
    function isFinite(v) {
        if (v == null) { return false; }
        if (!(v == v)) { return false; }
        if (v > 1.0e30 || v < -1.0e30) { return false; }
        return true;
    }

    function mean(arr) {
        if (arr == null || arr.size() == 0) { return 0.0; }
        var s = 0.0;
        var n = 0;
        for (var i = 0; i < arr.size(); i++) {
            var v = arr[i];
            if (v == null) { continue; }   // skip holes -> true mean over present values (#27)
            s += v;
            n++;
        }
        if (n == 0) { return 0.0; }        // all-null -> 0, never divide by zero
        return s / n;
    }

    //! Sample standard deviation (N-1). Returns 0 for <2 samples.
    function stdev(arr) {
        if (arr == null || arr.size() < 2) { return 0.0; }
        var m = mean(arr);
        var s = 0.0;
        var n = 0;
        for (var i = 0; i < arr.size(); i++) {
            var v = arr[i];
            if (v == null) { continue; }   // skip holes, consistent with mean() (#27)
            var d = v - m;
            s += d * d;
            n++;
        }
        if (n < 2) { return 0.0; }         // <2 present values -> 0 (N-1 over present count)
        return Math.sqrt(s / (n - 1));
    }

    //! Coefficient of variation = stdev/|mean|. 0 when mean ~0.
    function coeffOfVariation(arr) {
        var m = mean(arr);
        if (m > -1.0e-6 && m < 1.0e-6) { return 0.0; }
        return stdev(arr) / (m < 0 ? -m : m);
    }

    //! Ordinary least-squares slope of y vs x (both arrays, equal length).
    //! Returns [slope, r2]. Used by DFA (log-log slope) and calibration fits.
    function olsSlopeR2(xs, ys) {
        // Front-guard null / short / mismatched-length inputs so a bad window can't
        // throw out of this helper's "never throws" contract (§8.4) -- defense in
        // depth: the two live callers (DfaAlpha1.compute, CalibrationFit.fitSigmoid)
        // already pre-guard their inputs (CalibrationFit's alphas null/length guard
        // landed in #12), but this pure helper must be safe on its own (#27).
        // Subsumes the old `n < 2` check.
        if (xs == null || ys == null || xs.size() < 2 || xs.size() != ys.size()) {
            return [0.0, 0.0];
        }
        var n = xs.size();
        var sx = 0.0; var sy = 0.0; var sxx = 0.0; var sxy = 0.0; var syy = 0.0;
        for (var i = 0; i < n; i++) {
            var x = xs[i]; var y = ys[i];
            sx += x; sy += y; sxx += x * x; sxy += x * y; syy += y * y;
        }
        var denom = (n * sxx - sx * sx);
        if (denom > -1.0e-12 && denom < 1.0e-12) { return [0.0, 0.0]; }
        var slope = (n * sxy - sx * sy) / denom;
        // A sxx/syy-overflow Inf/NaN slope must not leak past the never-throws
        // contract into a caller's calibration math (#27); fail to the sentinel.
        if (!isFinite(slope)) { return [0.0, 0.0]; }
        // r^2
        var num = (n * sxy - sx * sy);
        var d2 = (n * sxx - sx * sx) * (n * syy - sy * sy);
        var r2 = 0.0;
        if (d2 > 1.0e-12) { r2 = (num * num) / d2; }
        return [slope, clamp(r2, 0.0, 1.0)];
    }

    //! Falling sigmoid used for the power->DFA-α1 map (white paper §4.2):
    //!   A1_target(P) = a0 - a1 / (1 + exp(-s·(P - P_AeT)))
    function fallingSigmoid(p, pAeT, a0, a1, s) {
        var z = -s * (p - pAeT);
        if (z > 60.0) { z = 60.0; }       // guard exp overflow
        if (z < -60.0) { z = -60.0; }
        var denom = 1.0 + Math.pow(2.718281828459045, z);
        return a0 - a1 / denom;
    }
}
