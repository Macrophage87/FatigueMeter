using Toybox.Lang;

//! Status-band logic (white paper §4.5, §6, §8.2).
//!
//! Descriptive states only: FRESH/PRODUCTIVE · FATIGUE BUILDING · DURABILITY
//! MARKERS DRIFTING. Band gating uses PER-ATHLETE drift (AFI vs its own scale,
//! decoupling drift above the athlete's early-ride baseline, α1 drift below
//! baseline). The fixed AFI>85 / 8% absolutes are F_ref/convention defaults, not
//! the sole gate.
//!
//! The Feat/Attrition classifier is OFF the critical path — it only labels the
//! KIND of red as a second line; it NEVER gates or suppresses the band (§8.2).
class StatusEvaluator {

    //! Returns a result dictionary:
    //!   :status         one of DescriptiveStrings.STATUS_*
    //!   :redKind        "feat" | "attrition" | "none"  (evidence only)
    //!   :advisoryActive bool — durability advisory is firing
    //!   :alpha1Gated    bool — α1 suppressed (advisory rests on decoup+kJ alone)
    //!   :decoupOnly     bool — RR poor, decoupling-dominant fallback
    static function evaluate(cfg, ctx) {
        // ctx keys: afi, decoupMetric(Signals.Metric), alpha1Metric, kjWeighted,
        //           elapsedS, wRr, redKind, sensorsPresent
        if (!ctx[:sensorsPresent]) {
            return { :status => DescriptiveStrings.STATUS_NODATA, :redKind => "none",
                     :advisoryActive => false, :alpha1Gated => true, :decoupOnly => true };
        }

        var afi = ctx[:afi];
        var decoupMetric = ctx[:decoupMetric];
        var alpha1Metric = ctx[:alpha1Metric];
        var kjw = ctx[:kjWeighted];
        var elapsed = ctx[:elapsedS];
        var wRr = ctx[:wRr];

        var alpha1Gated = !(alpha1Metric != null && alpha1Metric.availability == Signals.AVAIL_OK);
        var decoupOnly = (wRr < 0.5);

        // --- durability advisory (§6): needs time-on-task + decoupling drift ---
        // above the athlete's OWN early-ride baseline (decoupling% already IS the
        // drift-vs-baseline signal), past the kJ anchor. NOT a bare absolute >8%.
        var decoupDrift = 0.0;
        var decoupUsable = (decoupMetric != null && decoupMetric.isUsable());
        if (decoupUsable) { decoupDrift = decoupMetric.value; }

        var pastTime = (elapsed >= Constants.DURABILITY_MIN_S);
        var pastKj = (kjw != null && kjw >= 0.6 * cfg.kjAnchor);
        var decoupHigh = decoupUsable && (decoupDrift > cfg.decoupCaution);

        var advisoryActive = pastTime && pastKj && decoupHigh;

        // --- AFI band (per-athlete-calibrated F_ref scale; §4.5) ---
        var status;
        if (afi != null && afi >= Constants.AFI_BUILDING_MAX) {
            status = DescriptiveStrings.STATUS_DRIFTING;
        } else if (advisoryActive) {
            status = DescriptiveStrings.STATUS_DRIFTING;
        } else if ((afi != null && afi >= Constants.AFI_FRESH_MAX)
                   || (decoupUsable && decoupDrift > cfg.decoupOk)) {
            status = DescriptiveStrings.STATUS_BUILDING;
        } else {
            status = DescriptiveStrings.STATUS_FRESH;
        }

        // red character is evidence only, attached when DRIFTING
        var redKind = "none";
        if (status == DescriptiveStrings.STATUS_DRIFTING) {
            redKind = ctx[:redKind];
            if (redKind == null) { redKind = "none"; }
        }

        return { :status => status, :redKind => redKind,
                 :advisoryActive => advisoryActive,
                 :alpha1Gated => alpha1Gated, :decoupOnly => decoupOnly };
    }
}
