using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.Time;

//! SessionStore — persistent compact Session Results + rolling history (white
//! paper §8.3). Enables the cross-ride comparison view ("feat-of-strength day vs
//! attrition day"). Written transactionally (primary + backup) so a crash cannot
//! corrupt the history.
class SessionStore {

    hidden const KEY = "fm_sessions_v1";
    hidden const KEY_BAK = "fm_sessions_v1_bak";
    hidden const MAX_HISTORY = 20;

    hidden var history;   // Array of Session Result dictionaries (newest last)

    function initialize() {
        load();
    }

    hidden function load() {
        var h = read(KEY);
        if (!(h instanceof Lang.Array)) { h = read(KEY_BAK); }
        history = (h instanceof Lang.Array) ? h : [];
    }

    hidden function read(key) {
        try { return Storage.getValue(key); } catch (e) { return null; }
    }

    //! Append a Session Result and persist. Transactional: backup first, then
    //! primary. Keeps only the last MAX_HISTORY.
    function append(result) {
        history.add(result);
        while (history.size() > MAX_HISTORY) { history.remove(history[0]); }
        try {
            Storage.setValue(KEY_BAK, history);
            Storage.setValue(KEY, history);
        } catch (e) { }
    }

    function count() { return history.size(); }
    function all() { return history; }
    function latest() {
        if (history.size() == 0) { return null; }
        return history[history.size() - 1];
    }

    //! Build a Session Result dictionary (white paper §8.3 fields).
    //!
    //! Ride-scoped, ride-measured quantities only. Pre-ride residual fatigue and
    //! the cross-ride CTL/ATL/TSB are not computable on-device (§7 revised) and are
    //! deliberately absent — `endFatigue` is the ride-INDUCED cardiovascular drift
    //! (acute F from a neutral start), reported as a coarse bucket, never a raw bpm.
    static function buildResult(date, durationS, tss, endFatigue, peakAfi,
                                redFeatS, redAttrS, featScore, attritionScore,
                                best1, best5, best20, matches, durabilityKj,
                                endBucket, fatigueBandPts) {
        return {
            "date" => date, "durationS" => durationS, "tss" => tss,
            "endFatigue" => endFatigue, "peakAfi" => peakAfi,
            "endBucket" => endBucket, "fatigueBandPts" => fatigueBandPts,
            "redFeatS" => redFeatS, "redAttrS" => redAttrS,
            "featScore" => featScore, "attritionScore" => attritionScore,
            "best1" => best1, "best5" => best5, "best20" => best20,
            "matches" => matches, "durabilityKj" => durabilityKj
        };
    }
}
