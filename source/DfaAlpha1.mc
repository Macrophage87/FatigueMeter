using Toybox.Lang;
using Toybox.Math;

//! DFA-α1 on a rolling RR window (white paper §3.3, §4 lit review).
//!
//! Pipeline (implemented exactly): integrate the mean-subtracted RR series;
//! partition into non-overlapping boxes of size n (beats); least-squares linear
//! detrend per box; RMS the residuals across boxes -> F(n); α1 = slope of
//! log F(n) vs log n over n in [4,16].
//!
//! ALL functions here are pure and finite-safe. The 2-min window / 5-s recompute
//! cadence is enforced by the caller (PrimitivesCalculator) so this stays cheap.
module DfaAlpha1 {

    //! Artifact fraction (%) via a local-median deviation detector (simplified
    //! Lipponen-Tarvainen). An interval is an artifact if it deviates from the
    //! median of its neighbourhood by more than `tolFrac`. Ectopic beats and
    //! dropped RR both show up here. Returns 0..100.
    function artifactPercent(rr, tolFrac) {
        var n = rr.size();
        if (n < 5) { return 100.0; }   // too few beats to trust
        var flagged = 0;
        for (var i = 0; i < n; i++) {
            // local window median (±3 beats)
            var lo = i - 3; if (lo < 0) { lo = 0; }
            var hi = i + 3; if (hi > n - 1) { hi = n - 1; }
            var win = [];
            for (var j = lo; j <= hi; j++) {
                if (j != i) { win.add(rr[j]); }
            }
            var med = median(win);
            if (med > 1.0) {
                var dev = (rr[i] - med);
                if (dev < 0) { dev = -dev; }
                if (dev / med > tolFrac) { flagged++; }
            }
        }
        return 100.0 * flagged.toFloat() / n.toFloat();
    }

    function median(arr) {
        var n = arr.size();
        if (n == 0) { return 0.0; }
        var s = sortCopy(arr);
        if (n % 2 == 1) { return s[n / 2].toFloat(); }
        return (s[n / 2 - 1] + s[n / 2]) / 2.0;
    }

    function sortCopy(arr) {
        var a = [];
        for (var i = 0; i < arr.size(); i++) { a.add(arr[i]); }
        // insertion sort (arrays are small: a 2-min window is ~120-260 beats,
        // but median only ever sorts ±3-beat windows -> <=7 elements).
        for (var i = 1; i < a.size(); i++) {
            var key = a[i];
            var j = i - 1;
            while (j >= 0 && a[j] > key) { a[j + 1] = a[j]; j--; }
            a[j + 1] = key;
        }
        return a;
    }

    //! Core DFA. Returns [alpha1, r2, nBoxSizesUsed].
    //! r2 is the fit quality of log F(n) vs log n — used for the calibration gate
    //! and as a validity signal.
    function compute(rr, boxMin, boxMax) {
        var N = rr.size();
        if (N < boxMax * 2) { return [0.0, 0.0, 0]; }   // need at least 2 largest boxes

        // 1. mean-subtracted cumulative integration
        var mean = 0.0;
        for (var i = 0; i < N; i++) { mean += rr[i]; }
        mean = mean / N;

        var y = new [N];
        var acc = 0.0;
        for (var i = 0; i < N; i++) {
            acc += (rr[i] - mean);
            y[i] = acc;
        }

        // 2. F(n) for each integer box size n in [boxMin, boxMax]
        var logN = [];
        var logF = [];
        for (var n = boxMin; n <= boxMax; n++) {
            var boxes = N / n;                 // integer division -> non-overlapping
            if (boxes < 1) { break; }
            var sumSq = 0.0;
            var count = 0;
            for (var b = 0; b < boxes; b++) {
                var start = b * n;
                // least-squares line fit within the box, index 0..n-1
                var sx = 0.0; var sy = 0.0; var sxx = 0.0; var sxy = 0.0;
                for (var k = 0; k < n; k++) {
                    var xk = k.toFloat();
                    var yk = y[start + k];
                    sx += xk; sy += yk; sxx += xk * xk; sxy += xk * yk;
                }
                var denom = (n * sxx - sx * sx);
                var slope = 0.0; var intercept = sy / n;
                if (denom > 1.0e-9 || denom < -1.0e-9) {
                    slope = (n * sxy - sx * sy) / denom;
                    intercept = (sy - slope * sx) / n;
                }
                // 3. residuals -> sum of squares
                for (var k = 0; k < n; k++) {
                    var fit = intercept + slope * k;
                    var resid = y[start + k] - fit;
                    sumSq += resid * resid;
                    count++;
                }
            }
            if (count > 0) {
                var Fn = Math.sqrt(sumSq / count);
                if (Fn > 1.0e-9) {
                    logN.add(Math.ln(n.toFloat()));
                    logF.add(Math.ln(Fn));
                }
            }
        }

        if (logN.size() < 2) { return [0.0, 0.0, 0]; }
        var res = MathUtil.olsSlopeR2(logN, logF);
        var alpha = res[0];
        // α1 is bounded in practice to ~[0.2, 1.7]; scrub anything degenerate.
        if (!MathUtil.isFinite(alpha)) { return [0.0, 0.0, 0]; }
        return [alpha, res[1], logN.size()];
    }

    //! Coarse respiratory-frequency estimate (Hz) from the RR window, used ONLY
    //! to flag ventilation-driven α1 movement (white paper §3.3). Counts zero
    //! crossings of the high-pass (detrended) RR series -> oscillations, / window
    //! duration. This is a proxy, not a validated fB — good enough to detect
    //! *rapid change* in breathing rate for R_A1 inflation (§4.4).
    function estimateFb(rr) {
        var n = rr.size();
        if (n < 8) { return 0.0; }
        // remove slow trend with a short moving average, then count sign changes
        var totalMs = 0.0;
        for (var i = 0; i < n; i++) { totalMs += rr[i]; }
        var durS = totalMs / 1000.0;
        if (durS < 5.0) { return 0.0; }

        var mean = totalMs / n;
        var crossings = 0;
        var prevSign = 0;
        for (var i = 0; i < n; i++) {
            var v = rr[i] - mean;
            var sign = (v >= 0) ? 1 : -1;
            if (prevSign != 0 && sign != prevSign) { crossings++; }
            prevSign = sign;
        }
        // two crossings per oscillation
        var cycles = crossings / 2.0;
        return cycles / durS;   // Hz
    }
}
