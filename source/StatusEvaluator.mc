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
        // `!= true` (not `!ctx[...]`): an ABSENT key reads null, and `!null` throws
        // UnexpectedTypeException. Only an explicit true proceeds; null/absent falls
        // through to NODATA. Defensive hardening -- the live caller always passes a
        // bool here and evaluate() is inside compute()'s try/catch (#10).
        if (ctx[:sensorsPresent] != true) {
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
        var decoupOnly = (wRr != null && wRr < 0.5);   // null-guard the compare (#10)

        // --- durability advisory (§6): time-on-task + decoupling drift above the
        // athlete's OWN early-ride baseline (decoupling% already IS the drift-vs-
        // baseline signal), with work-done corroboration. TWO TIERS: ELEVATED drift
        // (> caution) needs the FULL kJ anchor; SEVERE drift (> high, #25) needs only
        // a REDUCED (half) kJ anchor. Always time-gated -- NOT a bare absolute >8%.
        var decoupDrift = 0.0;
        var decoupUsable = (decoupMetric != null && decoupMetric.isUsable());
        if (decoupUsable) { decoupDrift = decoupMetric.value; }

        var pastTime = (elapsed != null && elapsed >= Constants.DURABILITY_MIN_S);   // null-guard (#10)
        var pastKj        = (kjw != null && kjw >= 0.6 * cfg.kjAnchor);   // full anchor (elevated tier)
        var pastKjReduced = (kjw != null && kjw >= 0.3 * cfg.kjAnchor);   // reduced anchor (severe tier), half the full
        // cfg.decoupHigh is the severe tier (#25); the local formerly named
        // "decoupHigh" only ever meant "elevated" (> caution).
        var decoupElevated = decoupUsable && (decoupDrift > cfg.decoupCaution);
        var decoupSevere   = decoupUsable && (decoupDrift > cfg.decoupHigh);

        // Elevated drift past BOTH anchors, OR severe drift past the time anchor and
        // the REDUCED kJ anchor (a > decoupHigh drift substitutes for half the work).
        var advisoryActive = pastTime && ((pastKj && decoupElevated) || (pastKjReduced && decoupSevere));

        // Per-athlete AFI drift above the athlete's own rolling baseline (§4.5) —
        // fires the severe band in parallel to the α1 drift signal, so the
        // convention-grade absolute cutoff (afiBuilding, an F_ref-dependent
        // default) is NOT the sole gate.
        var afiDrift = ctx[:afiDrift];
        var afiDriftsHigh = (afiDrift != null && afiDrift > cfg.afiDriftMargin);

        // --- AFI band: absolute (calibrated F_ref scale) OR per-athlete drift ---
        var status;
        if ((afi != null && afi >= cfg.afiBuilding) || afiDriftsHigh || advisoryActive) {
            status = DescriptiveStrings.STATUS_DRIFTING;
        } else if ((afi != null && afi >= cfg.afiFresh)
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
