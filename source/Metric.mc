using Toybox.Lang;

//! Fault-isolation envelope (white paper §8.4).
//!
//! Every metric a calculator emits is a Metric: a value PLUS an availability and a
//! quality. This is how "no single sensor failure inhibits anything that does not
//! depend on it" is enforced structurally — the view renders each tile from its
//! own Metric.availability, so a missing input greys out only its dependents.
//!
//! Invariant: a Metric never carries NaN/Inf and never causes compute() to throw.
module Signals {

    enum {
        AVAIL_OK = 0,          // fresh, trustworthy value
        AVAIL_LOW_CONF = 1,    // value present but low confidence (e.g. gate failed, stale FTP)
        AVAIL_STALE = 2,       // holding last-valid past its update, staleness timer running
        AVAIL_UNAVAILABLE = 3  // input absent — tile greys out with a "no <sensor>" marker
    }

    class Metric {
        var value;         // Number/Float or null when unavailable
        var availability;  // one of AVAIL_*
        var quality;       // 0.0..1.0 confidence (1 = best); meaningful when value present
        var label;         // short marker shown when not OK, e.g. "no power", "artifact 7%"

        function initialize(v, a, q, lbl) {
            // §8.4 invariant: a Metric never carries NaN/Inf. If a calculator
            // hands us a non-finite value (e.g. a 0/0 HRV ratio), drop it and
            // grey the tile out rather than letting the bad number reach
            // compute()/rendering. Every factory and every `new Metric(...)`
            // routes through here, so this is the single enforcement point.
            if (v != null && !MathUtil.isFinite(v)) {
                value = null;
                availability = AVAIL_UNAVAILABLE;
                quality = 0.0;
                label = (lbl != null) ? lbl : "--";
            } else {
                value = v;
                availability = a;
                // clamp scrubs NaN->0.0 and +Inf->1.0; null-guard avoids
                // comparing null in clamp.
                quality = (q == null) ? 0.0 : MathUtil.clamp(q, 0.0, 1.0);
                label = lbl;
            }
        }

        //! Convenience constructors.
        static function ok(v, q) {
            return new Metric(v, AVAIL_OK, q, null);
        }
        static function lowConf(v, q, lbl) {
            return new Metric(v, AVAIL_LOW_CONF, q, lbl);
        }
        static function stale(v, lbl) {
            return new Metric(v, AVAIL_STALE, 0.3, lbl);
        }
        static function unavailable(lbl) {
            return new Metric(null, AVAIL_UNAVAILABLE, 0.0, lbl);
        }

        function isUsable() {
            // isFinite(null) == false, so this subsumes the old null check and
            // also rejects a value mutated to NaN/Inf after construction (the
            // fields are public vars).
            return (availability == AVAIL_OK || availability == AVAIL_LOW_CONF)
                   && MathUtil.isFinite(value);
        }
        function isPresent() {
            return MathUtil.isFinite(value) && availability != AVAIL_UNAVAILABLE;
        }
    }

    // ---- Pure staleness/validity classifiers (#11) ----
    // The AntHrm decode()/hrMetric() paths touch hardware + the System clock, so
    // the DECISION logic is factored into these pure statics -- the same
    // "PURE STATIC MATH (unit-testable)" split the rest of the codebase uses.

    //! Byte 7 of an ANT+ HRM page: 0 == no skin contact / no reading. Pure.
    function hrByteValid(b) {
        return (b & 0xFF) != 0;
    }

    //! Freshness test: a valid sample at lastMs is fresh at nowMs if it exists
    //! (lastMs >= 0), is not in the future, and is within windowMs. Pure.
    function freshWithin(lastMs, nowMs, windowMs) {
        if (lastMs < 0) { return false; }        // never seen
        var age = nowMs - lastMs;
        return age >= 0 && age <= windowMs;
    }

    //! Map a sample age to an availability state (§8.4 stale -> unavailable). Pure.
    //! Uses strict > so ageMs == staleMs is still OK and ageMs == unavailMs is
    //! still STALE (the boundaries belong to the fresher state).
    function hrAvailability(hasSample, ageMs, staleMs, unavailMs) {
        if (!hasSample || ageMs > unavailMs) { return AVAIL_UNAVAILABLE; }
        if (ageMs > staleMs) { return AVAIL_STALE; }
        return AVAIL_OK;
    }
}
