using Toybox.Lang;
using Toybox.Math;

//! LAYER 1 — Observable primitives (white paper §3). The validated backbone.
//!
//! Every output is a Signals.Metric. Nothing here throws into compute() and no
//! NaN/Inf ever leaves (white paper §8.4). Pure math is exposed as static
//! functions for off-device unit testing; the class holds the rolling state.
class PrimitivesCalculator {

    // ---- rolling buffers ----
    hidden var powerNp;        // last 30 s of power for NP
    hidden var winPower;       // last 10 min power for EF window / steadiness
    hidden var winHr;          // last 10 min HR
    hidden var winCad;         // last 10 min cadence
    hidden var rrBuf;          // last ~2 min of RR intervals (ms)

    // ---- baselines captured over minutes 5..15 ----
    hidden var efBaseline;     // Float or null
    hidden var cadBaseline;    // Float or null
    hidden var decoupBaseline; // per-athlete early-ride decoupling baseline (0 by construction)
    hidden var baseSumEf; hidden var baseCntEf;
    hidden var baseSumCad; hidden var baseCntCad;

    // ---- accumulators ----
    hidden var kjTotal;
    hidden var kjWeighted;
    hidden var kjAboveCpAcc;

    // ---- W'bal ----
    hidden var wBal;

    // ---- DFA cadence ----
    hidden var lastDfaTime;
    hidden var cachedAlpha1;   // [alpha, r2, artifact%, fb]
    hidden var lastFb;

    hidden var cfg;
    hidden var elapsed;        // seconds of ride

    function initialize(config) {
        cfg = config;
        powerNp = new RingBuffer(30);
        winPower = new RingBuffer(600);
        winHr = new RingBuffer(600);
        winCad = new RingBuffer(600);
        rrBuf = new RingBuffer(400);   // 2 min can exceed 200 beats at high HR
        efBaseline = null;
        cadBaseline = null;
        decoupBaseline = 0.0;
        baseSumEf = 0.0; baseCntEf = 0;
        baseSumCad = 0.0; baseCntCad = 0;
        kjTotal = 0.0;
        kjWeighted = 0.0;
        kjAboveCpAcc = 0.0;
        wBal = config.wPrime;
        lastDfaTime = -999;
        cachedAlpha1 = [0.0, 0.0, 100.0, 0.0];
        lastFb = 0.0;
        elapsed = 0;
    }

    function setConfig(config) { cfg = config; }

    // =====================================================================
    //  PURE STATIC MATH (unit-testable off device)
    // =====================================================================

    //! NormalizedPower = 4th-root of the mean of power^4 over the buffer.
    static function normalizedPower(powers) {
        if (powers == null || powers.size() == 0) { return 0.0; }
        var s = 0.0;
        for (var i = 0; i < powers.size(); i++) {
            var p = powers[i];
            if (p < 0) { p = 0; }
            var p2 = p * p;
            s += p2 * p2;
        }
        var m = s / powers.size();
        if (m <= 0.0) { return 0.0; }
        return Math.pow(m, 0.25);
    }

    //! Efficiency Factor = NP / meanHR. safeDiv guards HR=0.
    static function efficiencyFactor(np, meanHr) {
        return MathUtil.safeDiv(np, meanHr, 0.0);
    }

    //! Decoupling% = (EF_baseline - EF_window)/EF_baseline * 100.
    static function decouplingPct(efBaseline, efWindow) {
        if (efBaseline == null || efBaseline <= 1.0e-6) { return 0.0; }
        return (efBaseline - efWindow) / efBaseline * 100.0;
    }

    //! Intensity weight for the kJ clock: 1 below CP, ramping to ~3x well above CP
    //! (white paper §3.2). Linear ramp, capped at 3x at ~2·CP.
    static function weightForPower(p, cp) {
        if (p <= cp || cp <= 1.0e-6) { return 1.0; }
        var frac = (p - cp) / cp;            // 0 at CP, 1 at 2·CP
        var w = 1.0 + MathUtil.clamp(frac, 0.0, 1.0) * 2.0;   // 1..3
        return w;
    }

    //! One 1-s step of the Skiba differential W'bal model.
    //!   P >= CP : deplete by (P-CP)·dt
    //!   P <  CP : reconstitute toward W' at rate scaled by the deficit (CP-P)/W'
    static function wprimeBalStep(wBalPrev, p, cp, wPrime, dt) {
        if (wPrime <= 1.0e-6) { return 0.0; }
        var next;
        if (p >= cp) {
            next = wBalPrev - (p - cp) * dt;
        } else {
            var recovery = (cp - p) * (wPrime - wBalPrev) / wPrime * dt;
            next = wBalPrev + recovery;
        }
        return MathUtil.clamp(next, 0.0, wPrime);
    }

    // =====================================================================
    //  STATEFUL 1 Hz UPDATE
    // =====================================================================

    //! Feed one second of ride data. Each argument may be null (sensor absent).
    //! rrIntervals is an Array of RR values (ms) received this second, or null.
    function update(power, hr, cadence, rrIntervals, elapsedS) {
        elapsed = elapsedS;

        // --- power-derived accumulators (independent of HR) ---
        if (power != null && power >= 0) {
            powerNp.push(power);
            winPower.push(power);
            kjTotal += power / 1000.0;
            kjWeighted += weightForPower(power, cfg.cp) * power / 1000.0;
            if (power > cfg.cp) { kjAboveCpAcc += (power - cfg.cp) / 1000.0; }
            wBal = wprimeBalStep(wBal, power, cfg.cp, cfg.wPrime, 1.0);
        } else {
            // hold buffers; a dropout is handled by staleness at read time
            winPower.push(0);
        }

        if (hr != null && hr > 0) { winHr.push(hr); } else { winHr.push(0); }
        if (cadence != null && cadence >= 0) { winCad.push(cadence); } else { winCad.push(0); }

        // --- capture EF / cadence baselines over minutes 5..15 ---
        // Build the baseline EF with the SAME NP window (the 10-min rolling
        // buffer) that decouplingMetric() uses for EF_window, so decoupling is an
        // apples-to-apples EF drift, not a 30 s-vs-10 min artifact (review #2).
        if (elapsed >= Constants.EF_BASELINE_START_S && elapsed <= Constants.EF_BASELINE_END_S) {
            var npNow = normalizedPower(winPower.toArray());
            var hrArr = winHr.toArray();
            var hrMean = nonZeroMean(hrArr);
            if (npNow > 0 && hrMean > 0) {
                baseSumEf += npNow / hrMean; baseCntEf++;
            }
            var cadMean = nonZeroMean(winCad.toArray());
            if (cadMean > 0) { baseSumCad += cadMean; baseCntCad++; }
        }
        if (elapsed > Constants.EF_BASELINE_END_S) {
            if (efBaseline == null && baseCntEf > 0) { efBaseline = baseSumEf / baseCntEf; }
            if (cadBaseline == null && baseCntCad > 0) { cadBaseline = baseSumCad / baseCntCad; }
        }

        // --- RR buffer + DFA recompute every 5 s ---
        if (rrIntervals != null && rrIntervals.size() > 0) {
            for (var i = 0; i < rrIntervals.size(); i++) {
                var rrv = rrIntervals[i];
                if (rrv != null && rrv > 250 && rrv < 2500) {   // physiologic RR bounds (ms)
                    rrBuf.push(rrv);
                }
            }
        }
        if (elapsed - lastDfaTime >= Constants.DFA_RECOMPUTE_S) {
            lastDfaTime = elapsed;
            recomputeDfa();
        }
    }

    hidden function recomputeDfa() {
        var rr = trimRrToWindow();
        if (rr.size() < 20) {
            cachedAlpha1 = [0.0, 0.0, 100.0, 0.0];
            return;
        }
        var art = DfaAlpha1.artifactPercent(rr, 0.25);
        var fb = DfaAlpha1.estimateFb(rr);
        var res = DfaAlpha1.compute(rr, Constants.DFA_BOX_MIN, Constants.DFA_BOX_MAX);
        cachedAlpha1 = [res[0], res[1], art, fb];
        lastFb = fb;
    }

    //! Keep only the most recent ~120 s of RR (by summed duration).
    hidden function trimRrToWindow() {
        var all = rrBuf.toArray();
        var n = all.size();
        var sum = 0.0;
        var startIdx = n;
        for (var i = n - 1; i >= 0; i--) {
            sum += all[i];
            if (sum > Constants.DFA_WINDOW_S * 1000.0) { startIdx = i; break; }
            startIdx = i;
        }
        var out = [];
        for (var i = startIdx; i < n; i++) { out.add(all[i]); }
        return out;
    }

    hidden function nonZeroMean(arr) {
        var s = 0.0; var c = 0;
        for (var i = 0; i < arr.size(); i++) {
            if (arr[i] > 0) { s += arr[i]; c++; }
        }
        if (c == 0) { return 0.0; }
        return s / c;
    }

    // =====================================================================
    //  METRIC ACCESSORS (each renders its own tile — §8.4)
    // =====================================================================

    function normalizedPowerMetric() {
        if (winPower.size() < 5 || nonZeroMean(powerNp.toArray()) <= 0) {
            return Signals.Metric.unavailable("no power");
        }
        var np = normalizedPower(powerNp.toArray());
        return Signals.Metric.ok(np, 1.0);
    }

    //! Steadiness gate: emit decoupling only when window power CV and coasting
    //! fraction are below the configured limits (white paper §3.1). Otherwise
    //! low-confidence. Needs the baseline established (>15 min) and HR present.
    function decouplingMetric() {
        var pArr = winPower.toArray();
        var hrArr = winHr.toArray();
        var hrMean = nonZeroMean(hrArr);
        if (hrMean <= 0) { return Signals.Metric.unavailable("no HR"); }
        if (efBaseline == null) {
            return Signals.Metric.lowConf(0.0, 0.2, "warming up");
        }
        var npWin = normalizedPower(pArr);
        var efWin = efficiencyFactor(npWin, hrMean);
        var dec = decouplingPct(efBaseline, efWin);

        // steadiness gate
        var cv = MathUtil.coeffOfVariation(nonZeroArray(pArr));
        var coast = coastingFraction(pArr);
        if (cv > cfg.powerCvGate || coast > cfg.coastFracGate) {
            return Signals.Metric.lowConf(dec, 0.3, "variable");
        }
        return Signals.Metric.ok(dec, 1.0);
    }

    //! Per-athlete decoupling drift above the early-ride baseline (§6). Since the
    //! baseline IS the reference EF, decoupling% already expresses this drift.
    function decouplingDriftMetric() {
        return decouplingMetric();
    }

    //! DFA-α1 with hard artifact gate AND stationarity gate (white paper §3.3).
    //! Returns value + a quality that folds artifact %, fit r2, and stationarity.
    function alpha1Metric() {
        var alpha = cachedAlpha1[0];
        var r2 = cachedAlpha1[1];
        var art = cachedAlpha1[2];
        if (alpha <= 0.0) {
            return Signals.Metric.unavailable("no RR");
        }
        // hard artifact gate
        if (art > cfg.artifactGate) {
            return Signals.Metric.lowConf(alpha, 0.15,
                "artifact " + art.format("%.0f") + "%");
        }
        // stationarity gate: within-window power CV / coasting
        var pArr = winPower.toArray();
        var cv = MathUtil.coeffOfVariation(nonZeroArray(pArr));
        var coast = coastingFraction(pArr);
        if (cv > cfg.powerCvGate || coast > cfg.coastFracGate) {
            // suppress / down-weight — a moving window straddling transients
            // violates α1's stationarity assumption
            return Signals.Metric.lowConf(alpha, 0.25, "non-stationary");
        }
        var q = MathUtil.clamp(r2, 0.0, 1.0);
        return Signals.Metric.ok(alpha, q);
    }

    //! Raw artifact percentage of the current RR window (data-quality footer).
    function artifactPercentMetric() {
        if (cachedAlpha1[0] <= 0.0 && cachedAlpha1[2] >= 100.0) {
            return Signals.Metric.unavailable("no RR");
        }
        return Signals.Metric.ok(cachedAlpha1[2], 1.0);
    }

    function respiratoryFreqHz() { return lastFb; }

    function kjTotalMetric() {
        if (winPower.size() < 2) { return Signals.Metric.unavailable("no power"); }
        return Signals.Metric.ok(kjTotal, 1.0);
    }
    function kjWeightedMetric() {
        if (winPower.size() < 2) { return Signals.Metric.unavailable("no power"); }
        return Signals.Metric.ok(kjWeighted, 1.0);
    }
    function kjAboveCp() { return kjAboveCpAcc; }

    //! W'bal as bpm-free Joules. Carries low-confidence when CP/W' may be stale
    //! (the caller flags staleness; here we just guard the math).
    function wBalMetric() {
        if (winPower.size() < 2) { return Signals.Metric.unavailable("no power"); }
        return Signals.Metric.ok(wBal, 1.0);
    }
    function wBalFraction() {
        return MathUtil.safeDiv(wBal, cfg.wPrime, 1.0);
    }

    function cadenceDriftMetric() {
        if (cadBaseline == null) {
            return Signals.Metric.lowConf(0.0, 0.2, "warming up");
        }
        var cadNow = nonZeroMean(winCad.toArray());
        if (cadNow <= 0) { return Signals.Metric.unavailable("no cadence"); }
        var drift = (cadBaseline - cadNow) / cadBaseline * 100.0;
        return Signals.Metric.ok(drift, 0.6);   // corroborating vote only
    }

    // --- helpers exposed for the filter/characterizer ---
    function alpha1Raw() { return cachedAlpha1[0]; }
    function alpha1Artifact() { return cachedAlpha1[2]; }
    function alpha1Fb() { return cachedAlpha1[3]; }
    function efBaselineValue() { return efBaseline; }
    function kjWeightedValue() { return kjWeighted; }
    function elapsedS() { return elapsed; }

    //! True when the recent window is stationary enough for α1 / decoupling
    //! (white paper §3.1, §3.3). Used to gate the filter's observability
    //! excitation flag and the advisory's α1 weighting.
    function isStationary() {
        var pArr = winPower.toArray();
        if (pArr.size() < 30) { return false; }
        var cv = MathUtil.coeffOfVariation(nonZeroArray(pArr));
        var coast = coastingFraction(pArr);
        return (cv <= cfg.powerCvGate) && (coast <= cfg.coastFracGate);
    }

    hidden function coastingFraction(pArr) {
        if (pArr.size() == 0) { return 0.0; }
        var coastThresh = 0.05 * cfg.ftp;
        var c = 0;
        for (var i = 0; i < pArr.size(); i++) {
            if (pArr[i] < coastThresh) { c++; }
        }
        return c.toFloat() / pArr.size();
    }

    hidden function nonZeroArray(arr) {
        var out = [];
        for (var i = 0; i < arr.size(); i++) {
            if (arr[i] > 0) { out.add(arr[i]); }
        }
        return out;
    }
}
