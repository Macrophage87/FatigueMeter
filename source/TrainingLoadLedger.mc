using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.System;   // getClockTime().timeZoneOffset for the local day-index (#22)

//! LAYER 3 — Per-ride training load (white paper §5, revised).
//!
//! Scope note (§7 revised / PR "drop Layer-3 from the surfaces the field can't
//! back"): an on-device Connect IQ data field only sees the rides it actually
//! runs — never other-app rides, runs, indoor sessions, or a morning resting-HRV
//! reading — so it CANNOT maintain an honest cross-ride CTL/ATL/TSB, and the
//! resting-RMSSD baseline had no on-device source at all. Those are owned by the
//! training-load platform (intervals.icu / Garmin Training Status), not here.
//!
//! What remains is the one Layer-3 quantity the field CAN compute honestly from a
//! single ride: its **load** — power TSS if power is present, else Banister/Edwards
//! HR-TRIMP as a graceful fallback (§8.4). That single number is exported per-ride
//! to the FIT, where the platform does the (complete) chronic accumulation. No
//! cross-ride state is kept, seeded, or persisted; F(0) starts neutral (§7).
class TrainingLoadLedger {

    hidden var cfg;

    // live within-ride accumulators
    hidden var trimpAccum;
    hidden var secondsAccum;       // real elapsed seconds (Float), not a call count (#22)
    hidden var powerSecondsAccum;  // seconds with power present, for the load-model gate (#22)
    hidden var npSumPow4;
    hidden var npCount;

    function initialize(config) {
        cfg = config;
        trimpAccum = 0.0;
        secondsAccum = 0.0;
        powerSecondsAccum = 0.0;
        npSumPow4 = 0.0;
        npCount = 0;
    }

    function setConfig(config) { cfg = config; }

    // =====================================================================
    //  PURE STATIC MATH (unit-testable)
    // =====================================================================

    static function intensityFactor(np, ftp) {
        return MathUtil.safeDiv(np, ftp, 0.0);
    }

    //! TSS = duration_h · IF² · 100 (white paper §5).
    static function tss(durationSec, np, ftp) {
        var iff = intensityFactor(np, ftp);
        var hours = durationSec / 3600.0;
        return hours * iff * iff * 100.0;
    }

    //! Incremental Banister TRIMP for one second (white paper §5, references.md).
    //! dTRIMP = (dt/60)·HRr·coeff·e^(exp·HRr), HRr = (HR−HRrest)/(HRmax−HRrest).
    //! Female coeff is UNRESOLVED (0.86 vs 0.64) — passed in from a SETTING.
    static function trimpIncrement(hr, hrRest, hrMax, dt, coeff, expo) {
        var span = hrMax - hrRest;
        if (span <= 1.0e-6) { return 0.0; }
        var hrr = (hr - hrRest) / span;
        if (hrr < 0) { hrr = 0; }
        if (hrr > 1.0) { hrr = 1.0; }
        var z = expo * hrr;
        if (z > 60.0) { z = 60.0; }
        return (dt / 60.0) * hrr * coeff * Math.pow(2.718281828459045, z);
    }

    //! CTL/ATL-style EWMA fold: new = prev + (load − prev)/tau (white paper §5).
    //! Retained as validated pure math (unit-tested); the on-device app no longer
    //! folds a cross-ride chronic/acute state — that lives in the platform.
    static function ewmaFold(prev, load, tau) {
        // tau == 0 / NaN / null -> no fold instead of Inf/NaN (#34a). safeDiv guards
        // the division only; prev is a finite accumulator so the outer `prev +` can't
        // leak a non-finite value. Dead on-device today (no cross-ride fold).
        return prev + MathUtil.safeDiv(load - prev, tau, 0.0);
    }

    static function tsbFrom(ctlY, atlY) { return ctlY - atlY; }

    // =====================================================================
    //  WITHIN-RIDE ACCUMULATION
    // =====================================================================

    //! dt = real elapsed seconds since the previous update (the caller derives it
    //! from the pause-excluding activity timer, #22). A null/negative dt accrues
    //! nothing (defense on a now-public 3-arg method). NP stays sample-count based
    //! (npSumPow4/npCount) rather than dt-weighted -- a separate approximation left
    //! out of scope; negligible at the nominal ~1 Hz cadence.
    function update(power, hr, dt) {
        if (dt == null || dt < 0.0) { dt = 0.0; }
        secondsAccum += dt;
        if (power != null && power >= 0) {
            // #7: same int^4 overflow as PrimitivesCalculator.normalizedPower.
            var pf = power.toFloat();
            var p2 = pf * pf;
            npSumPow4 += p2 * p2;
            npCount++;                    // NP mean divides by this -- keep it
            powerSecondsAccum += dt;      // seconds-with-power, for the rideLoad() gate
        }
        if (hr != null && hr > 0) {
            var coeff = cfg.sexFemale ? cfg.trimpFemaleCoeff : Constants.TRIMP_MALE_COEFF;
            var expo = cfg.sexFemale ? Constants.TRIMP_FEMALE_EXP : Constants.TRIMP_MALE_EXP;
            trimpAccum += trimpIncrement(hr, cfg.hrRest, cfg.hrMax, dt, coeff, expo);
        }
    }

    //! Ride NP so far (4th-root of mean power⁴ over the whole ride).
    function rideNp() {
        if (npCount == 0) { return 0.0; }
        var m = npSumPow4 / npCount;
        if (m <= 0) { return 0.0; }
        return Math.pow(m, 0.25);
    }

    //! Ride load with graceful degradation: power-TSS if power present, else
    //! HR-TRIMP (white paper §8.4 — no power → HR-TRIMP keeps the load honest).
    function rideLoad() {
        // Gate on power-SECONDS vs total seconds (not sample count vs seconds): under
        // a throttled loop (dt>1) a samples-vs-seconds test would wrongly flip to
        // TRIMP even with power every tick (#22).
        if (powerSecondsAccum > secondsAccum / 4) {  // power present for enough of the ride
            return tss(secondsAccum, rideNp(), cfg.ftp);
        }
        return trimpAccum;                          // TRIMP fallback
    }

    //! End-of-ride: return this ride's load (TSS or TRIMP). No cross-ride fold or
    //! persistence — the FIT export carries the per-ride load to the platform.
    function finalizeRide() {
        return rideLoad();
    }

    // =====================================================================
    //  DAY INDEX (for the session-history date stamp)
    // =====================================================================

    //! Local calendar-day ordinal (days since epoch in the athlete's local time),
    //! so a ride near local midnight is stamped on the right day. Pure/testable
    //! (#22); offsetSeconds is the device's UTC offset (DST-inclusive).
    static function localDayIndex(utcSeconds, offsetSeconds) {
        return ((utcSeconds + offsetSeconds) / 86400).toNumber();
    }

    hidden function dayIndex() {
        // timeZoneOffset already folds in DST for "now", so the stamp lands on the
        // rider's LOCAL calendar day rather than the UTC one (#22).
        return localDayIndex(Time.now().value(), System.getClockTime().timeZoneOffset);
    }
    function dayIndexPublic() { return dayIndex(); }
}
