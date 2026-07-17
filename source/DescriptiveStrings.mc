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

    //! Save-outcome severity for the next-start persistence marker (#83). Module
    //! scope (referenced qualified, e.g. DescriptiveStrings.SAVE_FAILED) — a bare
    //! class-scoped enum would hit the SessionSchema.VERSION trap.
    enum { SAVE_OK = 0, SAVE_FAILED = 1, SAVE_TRIMMED = 2 }

    //! Pure severity fold for the save marker (#83). FAILED (a ride recovered from
    //! its #17 checkpoint because the normal durable save did not complete)
    //! OUTRANKS TRIMMED (older history shed to fit a full store) — never imply a
    //! clean save when it wasn't. Plain function to match every other member here
    //! (repo-wide `static` is class-scoped only).
    function saveMarkerSeverity(recovered, trimmed) {
        if (recovered) { return SAVE_FAILED; }
        if (trimmed)   { return SAVE_TRIMMED; }
        return SAVE_OK;
    }

    //! Descriptive copy for a save-outcome severity (#83); SAVE_OK draws nothing.
    function saveMarkerLabel(sev) {
        if (sev == SAVE_FAILED)  { return load(Rez.Strings.SaveRecovered); }
        if (sev == SAVE_TRIMMED) { return load(Rez.Strings.SaveTrimmed); }
        return "";
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
    function degradedTag() { return load(Rez.Strings.DegradedTag); }   // #28 compute-stall marker
    function notMedical() { return load(Rez.Strings.NotMedical); }

    function load(res) {
        try { return WatchUi.loadResource(res); } catch (e) { return ""; }
    }
}
