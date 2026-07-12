using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Application;

//! Allowed descriptive-copy accessors (white paper §6, §8.1).
//!
//! Every user-facing status/advisory string comes from resources/strings.xml,
//! which is the single allowed-copy list. RULE: descriptive mood only — NO
//! imperative verbs. The validation harness asserts UI strings are drawn from
//! this list and checks MOOD (not a substring blacklist).
module DescriptiveStrings {

    enum {
        STATUS_FRESH = 0,
        STATUS_BUILDING = 1,
        STATUS_DRIFTING = 2,
        STATUS_NODATA = 3
    }

    function statusLabel(status) {
        switch (status) {
            case STATUS_FRESH:    return load(Rez.Strings.StateFresh);
            case STATUS_BUILDING: return load(Rez.Strings.StateBuilding);
            case STATUS_DRIFTING: return load(Rez.Strings.StateDrifting);
            default:              return load(Rez.Strings.StateNoData);
        }
    }

    function redCharacterLabel(kind) {
        if (kind.equals("feat")) { return "🏅 " + load(Rez.Strings.RedFeat); }
        if (kind.equals("attrition")) { return "⚠ " + load(Rez.Strings.RedAttrition); }
        return "";
    }

    function advisoryTag() { return load(Rez.Strings.AdvisoryTag); }
    function uncalibratedTag() { return load(Rez.Strings.UncalibratedTag); }
    function decoupOnlyTag() { return load(Rez.Strings.DecoupOnlyTag); }
    function notMedical() { return load(Rez.Strings.NotMedical); }

    function startBucketLabel(bucket) {
        if (bucket.equals("fresh")) { return load(Rez.Strings.BucketFresh); }
        if (bucket.equals("heavy")) { return load(Rez.Strings.BucketHeavy); }
        return load(Rez.Strings.BucketModerate);
    }

    hidden function load(res) {
        try { return WatchUi.loadResource(res); } catch (e) { return ""; }
    }
}
