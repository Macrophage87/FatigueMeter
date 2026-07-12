using Toybox.Lang;

//! Effort characterizer — Feat of Strength vs Attrition (white paper §8.2).
//!
//! CRITICAL: this classifier is OFF the verdict critical path (Rev 2). It has
//! arbitrary weights, no labeled training data, and no measured error rate, so it
//! must NEVER gate or suppress the status band. FeatScore / AttritionScore are
//! shown as RAW EVIDENCE that contextualises a red state ("this red is dominated
//! by hard output 🏅" vs "…by drift ⚠"). The app never converts this
//! synthesis-grade guess into an authoritative directive.
class EffortCharacterizer {

    hidden var cfg;

    // best-effort trackers (mean-maximal power for 1 / 5 / 20 min)
    hidden var be1; hidden var be5; hidden var be20;

    // severe-domain / W′ match tracking
    hidden var timeSevereS;
    hidden var matchCount;
    hidden var matchDepthSum;
    hidden var inMatch;
    hidden var matchMinFrac;

    // attrition accumulation
    hidden var attritionAccum;
    hidden var timeInRedFeat;      // seconds of red attributed to feat
    hidden var timeInRedAttrition; // seconds of red attributed to attrition

    function initialize(config) {
        cfg = config;
        be1 = new BestEffort(60);
        be5 = new BestEffort(300);
        be20 = new BestEffort(1200);
        timeSevereS = 0;
        matchCount = 0;
        matchDepthSum = 0.0;
        inMatch = false;
        matchMinFrac = 1.0;
        attritionAccum = 0.0;
        timeInRedFeat = 0;
        timeInRedAttrition = 0;
    }

    function setConfig(config) { cfg = config; }

    // =====================================================================
    //  PURE STATIC SCORES (unit-testable)
    // =====================================================================

    //! FeatScore ∝ kJ_above_CP + w_sev·(severe-domain time) + Σ match depths
    //!           + best-effort bonuses (§8.2).
    static function featScore(kjAboveCp, severeSeconds, matchDepthSum, be5w, cp) {
        var wSev = 0.02;             // synthesis weight (§8.2 — arbitrary, labelled)
        var bestBonus = 0.0;
        if (cp > 1.0e-6 && be5w > cp) { bestBonus = (be5w - cp) / cp * 30.0; }
        return kjAboveCp
             + wSev * severeSeconds
             + matchDepthSum * 40.0
             + bestBonus;
    }

    //! AttritionScore ∝ (decoupling above baseline)·(time sub-threshold past the
    //! durability anchor) + (α1 drift below personal baseline-for-power) (§8.2).
    static function attritionScore(attritionAccum, alpha1DriftBelow) {
        var driftTerm = (alpha1DriftBelow > 0) ? alpha1DriftBelow * 100.0 : 0.0;
        return attritionAccum + driftTerm;
    }

    // =====================================================================
    //  1 Hz UPDATE
    // =====================================================================

    function update(power, wBalFraction, decoupPct, alpha1DriftBelow, kjWeighted) {
        if (power != null && power >= 0) {
            be1.add(power); be5.add(power); be20.add(power);
            if (power > cfg.cp) { timeSevereS++; }
        }

        // W′ "match": W'bal fraction drops below threshold then recovers
        if (wBalFraction != null) {
            if (!inMatch && wBalFraction < Constants.WPRIME_MATCH_FRAC) {
                inMatch = true;
                matchMinFrac = wBalFraction;
            } else if (inMatch) {
                if (wBalFraction < matchMinFrac) { matchMinFrac = wBalFraction; }
                if (wBalFraction > 0.5) {           // partial recovery closes the match
                    matchCount++;
                    matchDepthSum += (Constants.WPRIME_MATCH_FRAC - matchMinFrac);
                    inMatch = false;
                    matchMinFrac = 1.0;
                }
            }
        }

        // Attrition accumulation: decoupling above baseline while sub-threshold and
        // past the durability anchor (kJ). Only accrues in the "hole-digging" regime.
        if (power != null && power < cfg.cp
            && kjWeighted != null && kjWeighted > 0.5 * cfg.kjAnchor
            && decoupPct != null && decoupPct > cfg.decoupOk) {
            attritionAccum += (decoupPct - cfg.decoupOk) * 0.01;
        }
    }

    //! Split a second of "red" time into Feat vs Attrition by which score's driver
    //! dominates THIS moment (power above CP or a fresh match -> feat).
    function accrueRedSecond(power, freshMatch) {
        if ((power != null && power > cfg.cp) || freshMatch) {
            timeInRedFeat++;
        } else {
            timeInRedAttrition++;
        }
    }

    // =====================================================================
    //  OUTPUTS
    // =====================================================================

    function feat(be5wValue) {
        return featScore(kjAboveCpValue(), timeSevereS, matchDepthSum,
                         be5wValue, cfg.cp);
    }
    function attrition(alpha1DriftBelow) {
        return attritionScore(attritionAccum, alpha1DriftBelow);
    }

    // kJ above CP is owned by PrimitivesCalculator; the view passes it in via feat().
    hidden var kjAboveCpCache;
    function setKjAboveCp(v) { kjAboveCpCache = v; }
    hidden function kjAboveCpValue() { return (kjAboveCpCache == null) ? 0.0 : kjAboveCpCache; }

    function best1() { return be1.best(); }
    function best5() { return be5.best(); }
    function best20() { return be20.best(); }
    function matchesBurned() { return matchCount; }
    function severeSeconds() { return timeSevereS; }
    function redFeatSeconds() { return timeInRedFeat; }
    function redAttritionSeconds() { return timeInRedAttrition; }

    //! Which kind of red dominates right now — for the status band's second line.
    //! Returns "feat", "attrition", or "none". EVIDENCE, not a gate.
    function redCharacter(be5wValue, alpha1DriftBelow) {
        var f = feat(be5wValue);
        var a = attrition(alpha1DriftBelow);
        if (f <= 0.0 && a <= 0.0) { return "none"; }
        return (f >= a) ? "feat" : "attrition";
    }
}

//! Rolling mean-maximal-power tracker with an O(1) running sum.
class BestEffort {
    hidden var buf;
    hidden var sum;
    hidden var window;
    hidden var bestMean;

    function initialize(windowSeconds) {
        window = windowSeconds;
        buf = new RingBuffer(windowSeconds);
        sum = 0.0;
        bestMean = 0.0;
    }

    function add(power) {
        var evicted = buf.push(power);
        sum += power;
        if (evicted != null) { sum -= evicted; }
        if (buf.isFull()) {
            var mean = sum / window;
            if (mean > bestMean) { bestMean = mean; }
        }
    }

    function best() { return bestMean; }
}
