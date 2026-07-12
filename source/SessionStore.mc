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
    static function buildResult(date, durationS, tss, startFatigue, endFatigue,
                                fatigueAdded, peakAfi, redFeatS, redAttrS,
                                featScore, attritionScore, best1, best5, best20,
                                matches, durabilityKj, ctl, atl, tsb,
                                startBucket, endBucket, addedBucket, fatigueBandPts) {
        // Raw bpm (startFatigue/endFatigue/fatigueAdded) are kept for FIT export;
        // the coarse BUCKETS + uncertainty band (white paper §7) are what the
        // cross-ride comparison view should present — never the raw point value.
        return {
            "date" => date, "durationS" => durationS, "tss" => tss,
            "startFatigue" => startFatigue, "endFatigue" => endFatigue,
            "fatigueAdded" => fatigueAdded, "peakAfi" => peakAfi,
            "startBucket" => startBucket, "endBucket" => endBucket,
            "addedBucket" => addedBucket, "fatigueBandPts" => fatigueBandPts,
            "redFeatS" => redFeatS, "redAttrS" => redAttrS,
            "featScore" => featScore, "attritionScore" => attritionScore,
            "best1" => best1, "best5" => best5, "best20" => best20,
            "matches" => matches, "durabilityKj" => durabilityKj,
            "ctl" => ctl, "atl" => atl, "tsb" => tsb
        };
    }
}
