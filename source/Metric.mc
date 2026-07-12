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
            value = v;
            availability = a;
            quality = q;
            label = lbl;
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
            return (availability == AVAIL_OK || availability == AVAIL_LOW_CONF)
                   && value != null;
        }
        function isPresent() {
            return value != null && availability != AVAIL_UNAVAILABLE;
        }
    }
}
